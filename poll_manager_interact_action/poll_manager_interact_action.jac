import logging;
import json;
import uuid;
import os;
import from datetime { datetime, timezone, timedelta }
import from logging { Logger }
import from typing { Union, List, Dict, Optional, Any, Tuple }
import from jivas.agent.action.interact_action { InteractAction }
import from jivas.agent.action.agent_graph_walker { agent_graph_walker }
import from jivas.agent.memory.interaction_response { InteractionMessage, MediaInteractionMessage }
import from jivas.agent.memory.collection { Collection }
import from actions.jivas.poll_manager_interact_action.poll_group_node { PollGroupNode }
import from actions.jivas.poll_manager_interact_action.poll_response_node { PollResponseNode }
import from actions.jivas.poll_manager_interact_action.poll_status { PollStatus }
import from jivas.agent.core.graph_node { GraphNode }
import from jac_cloud.plugin.jaseci { JacPlugin as Jac }


node PollManagerInteractAction(InteractAction) {
    static has logger:Logger = logging.getLogger(__name__);

    # --- Configuration ---
    has whatsapp_action: str = "WPPConnectAction"; # DAF configurable
    has response_recorded_directive: str = "Thanks! Your response has been recorded.";
    has response_record_failed_directive: str = "Sorry, there was an issue recording your response.";
    has unknown_poll_directive: str = "Sorry, I couldn't find the poll you responded to or it may have expired.";
    has poll_completed_directive: str = "This poll has already completed and is no longer accepting responses.";
    has pulse_interval_seconds: int = 300; # Check poll expirations every 5 minutes

    # --- Lifecycle Management ---
    def on_enable() {
        self.start_poll_lifecycle_pulse();
    }

    def on_disable() {
        self.stop_poll_lifecycle_pulse();
    }

    def post_register() {
        # post register procedure to start the outbox scheduler
        self.start_poll_lifecycle_pulse();
    }

    def start_poll_lifecycle_pulse() {
        if (pulse_action := self.get_agent().get_actions().get(action_label="PulseAction")) {
            action_label = self.label;
            interval_spec = f'every({self.pulse_interval_seconds}).seconds';
            pulse_action.remove_schedule(action_label=action_label); # Avoid duplicates
            pulse_action.add_schedule(action_label=action_label, interval_spec=interval_spec);
            self.logger.info(f"Poll lifecycle pulse scheduled for '{action_label}' every {self.pulse_interval_seconds}s.");
        } else {
            self.logger.warning("PulseAction not found. Poll lifecycle management (auto-completion) will be inactive.");
        }
    }

    def stop_poll_lifecycle_pulse() {
        if (pulse_action := self.get_agent().get_actions().get(action_label="PulseAction")) {
            pulse_action.remove_schedule(action_label=self.label);
            self.logger.info(f"Poll lifecycle pulse for '{self.label}' stopped.");
        }
    }

    def pulse() { # This ability is called by PulseAction
        self.logger.debug("PollManagerInteractAction pulse: Checking for expired active polls.");
        collection = self.get_collection();

        active_polls = collection spawn _get_polls_by_status(status_to_find=PollStatus.ACTIVE);

        now_iso = datetime.now(timezone.utc).isoformat();

        for poll_node_data in active_polls.polls { # Assuming walker returns a list of dicts or node objects
            # If walker returns node objects directly:
            # poll_node = poll_node_data; # if poll_node_data is already the node
            # But walker currently returns dicts, we need to fetch the node to update it
            poll_node = collection spawn _get_poll_by_id(internal_id=poll_node_data.get("internal_poll_group_id"));
            if (poll_node and poll_node.poll) { # Check if walker returned the node
                poll_node = poll_node.poll; # Actual PollGroupNode
                if (poll_node.expires_at and poll_node.expires_at < now_iso and poll_node.status == PollStatus.ACTIVE) {
                    poll_node.status = PollStatus.COMPLETED;
                    self.logger.info(f"Poll '{poll_node.name}' (ID: {poll_node.poll_id}) has expired. Status updated to COMPLETED.");
                    # Potentially trigger a notification or summary action here or callback if needed with the results
                }
            }
        }
    }

    # --- Core Abilities ---
    def register_dispatched_poll_instance(
        poll_definition: dict = {}, # Expects {"name", "choices", "options": {"selectableCount", "duration_minutes", ...other_wpp_opts}}
        user_session_id: str = "",  # User it was sent to (can be group ID for WPPConnect)
        whatsapp_poll_id: str = "", # ID of the WA message containing the poll from WPPConnect response
        preferred_internal_id: Optional[str] = None
    ) -> Optional[str] { # Returns the internal_poll_group_id or None on failure
        self.logger.info(f"Registering dispatched poll: WA_ID={whatsapp_poll_id}, User={user_session_id}, PreferredInternalID={preferred_internal_id}");
        self.logger.debug(f"Poll definition received for registration: {poll_definition}");

        poll_name = poll_definition.get("name");
        choices = poll_definition.get("choices");
        # Extract relevant options for PollGroupNode, like duration_minutes, from the full poll_definition.options
        options_for_group_node = {
            "selectableCount": poll_definition.get("options", {}).get("selectableCount", 1),
            "duration_minutes": poll_definition.get("options", {}).get("duration_minutes") # Will be None if not present
            # Copy other non-WPP-specific options if needed
        };

        if (not poll_name or not choices) {
            self.logger.error("Cannot register poll: name or choices missing from definition.");
            return None;
        }

        created_or_found_poll_node = self.create_poll_group_entry(
            poll_name=poll_name,
            choices=choices,
            options=options_for_group_node, # Pass the curated options
            preferred_id=preferred_internal_id
        );

        if (created_or_found_poll_node) {
            created_or_found_poll_node.add_dispatched_wa_id(
                wa_message_id=whatsapp_poll_id,
                user_session_id=user_session_id # Store who it was sent to with this WA ID
            );
            self.logger.info(f"Successfully registered/updated WA poll dispatch: WA_ID={whatsapp_poll_id} linked to InternalGroup_ID={created_or_found_poll_node.id}");
            return created_or_found_poll_node.id;
        } else {
            self.logger.error(f"Failed to create or find poll group entry for WA_ID={whatsapp_poll_id}.");
            return None;
        }
    }

    def dispatch_poll_via_wpp(
        target_user_session_id: str,
        poll_name: str,
        choices: List[str],
        selectable_count: int = 1,
        duration_minutes: Optional[int] = None, # New: duration for the poll
        preferred_internal_id: Optional[str] = None,
        options_extra: Optional[dict] = None
    ) -> Dict {
        wpp_action = self.get_agent().get_actions().get(action_label=self.whatsapp_action);
        if (not wpp_action) {
            return {"status": "failed", "message": "WPPConnectAction not configured."};
        }

        poll_options = {"selectableCount": selectable_count};
        if (duration_minutes) { poll_options["duration_minutes"] = duration_minutes; } # Store for PollGroupNode
        if (options_extra) { poll_options.update(options_extra); }

        poll_def_for_wpp = {"name": poll_name, "choices": choices, "options": {"selectableCount": selectable_count}, "duration_minutes": duration_minutes};
        if (options_extra) { poll_def_for_wpp["options"].update(options_extra); }


        poll_im = MediaInteractionMessage(mime="jivas/poll", content="", data=poll_def_for_wpp);

        self.logger.info(f"Dispatching poll '{poll_name}' to {target_user_session_id}");
        wpp_send_result = wpp_action.send_message(session_id=target_user_session_id, message=poll_im);
        self.logger.debug(f"WPPConnect send result: {wpp_send_result}");

        if (wpp_send_result and wpp_send_result.get("status") == "success" and wpp_send_result.get("response")) {
            # WPPConnect often returns a list of responses if multiple messages were part of the payload
            # Assuming for a single poll, it's the first item. Adjust if WPPConnect returns differently.
            wa_response_details = wpp_send_result.get("response")[0] if isinstance(wpp_send_result.get("response"), list) and wpp_send_result.get("response") else wpp_send_result.get("response");
            whatsapp_poll_id = wa_response_details.get("id") if isinstance(wa_response_details, dict) else "unknown_wa_id";
            internal_poll_group_id = wpp_send_result.get("internal_poll_group_id") if isinstance(wa_response_details, dict) else None;

            if (internal_poll_group_id) {
                self.logger.info(f"Poll dispatched: WA_ID={whatsapp_poll_id}, Internal_ID={internal_poll_group_id}");
                return {
                    "status": "succeeded", "whatsapp_poll_id": whatsapp_poll_id,
                    "internal_poll_group_id": internal_poll_group_id
                };
            } else {
                return {"status": "failed", "message": "Could not create poll entry in collection."};
            }
        } else {
            return {"status": "failed", "message": "WPPConnectAction failed to send.", "details": wpp_send_result};
        }
    }

    def create_poll_group_entry(
        poll_name: str, choices: List[str], options: Dict, preferred_id: Optional[str] = None
    ) -> Optional[PollGroupNode] {
        collection = self.get_collection();

        # Check for existing by preferred_id first if provided
        target_id = preferred_id;
        existing_node = None;
        if (target_id) {
            existing_node_data = collection spawn _get_poll_by_id(internal_id=target_id);
            if (existing_node_data and existing_node_data.poll) { existing_node = existing_node_data.poll; }
        }

        # If not found by preferred_id, or preferred_id not given, check by content
        if (not existing_node) {
            content_match_data = collection spawn _find_poll_by_def(
                name_to_find=poll_name, choices_to_find=choices, options_to_find=options
            );
            if (content_match_data and content_match_data.poll) { existing_node = content_match_data.poll; }
        }

        # Check if existing_node matches the new definition
        if(existing_node){
            # Normalize for comparison
            norm_choices_target = tuple(sorted(choices));
            norm_options_target = tuple(sorted(options if isinstance(options, dict) else {}.items()));

            norm_choices_current = tuple(sorted(existing_node.choices if isinstance(existing_node.choices, list) else []));
            norm_options_current = tuple(sorted(existing_node.options.items() if isinstance(existing_node.options, dict) else {}.items()));

            if (
                not
                    (
                        existing_node.name == poll_name and
                        norm_choices_current == norm_choices_target
                        # and norm_options_current == norm_options_target
                        # Options removed cause the only option is selectableCount, and duration minutes which is not critical for finding the poll
                        # If options are critical, we can add that check back
                    )
                ) {
                # Deny existing node since they aren't the same, and set null
                self.logger.warning(f"Found existing poll group {existing_node.poll_id} but it does not match the new definition. Creating a new one instead.");

                # log comparison for debugging
                self.logger.debug(f"Existing PollGroupNode: {existing_node.name}, Choices: {norm_choices_current}, Options: {norm_options_current}");
                self.logger.debug(f"New PollGroupNode: {poll_name}, Choices: {norm_choices_target}, Options: {norm_options_target}");

                # set existing_node to None to force creation of a new one
                existing_node = None;
            }
        }

        if (existing_node) {
            self.logger.info(f"Found existing poll group: {existing_node.poll_id}. Reusing.");
            # Potentially update expires_at if a new duration is given for a re-dispatch of same poll
            duration_minutes = options.get("duration_minutes");
            if (isinstance(duration_minutes, (int, float)) and duration_minutes > 0) {
                new_expires_at = (datetime.now(timezone.utc) + timedelta(minutes=duration_minutes)).isoformat();
                if (existing_node.status == PollStatus.COMPLETED or (existing_node.expires_at and new_expires_at > existing_node.expires_at)) {
                    existing_node.expires_at = new_expires_at;
                    existing_node.status = PollStatus.ACTIVE; # Reactivate if completed and re-dispatched with new duration
                    self.logger.info(f"Poll {existing_node.poll_id} expiration updated to {new_expires_at} and status to ACTIVE.");
                }
            }

            # update status to ACTIVE if it was completed or Archived
            if (existing_node.status == PollStatus.COMPLETED or existing_node.status == PollStatus.ARCHIVED) {
                existing_node.status = PollStatus.ACTIVE; # Reactivate if completed or archived
                self.logger.info(f"Poll {existing_node.poll_id} status updated to ACTIVE.");
            }

            # set expires to empty string so as to renew the found poll
            if(datetime.now(timezone.utc).isoformat() > existing_node.expires_at){
                existing_node.expires_at = ""; # Reset expiration to renew the poll
                self.logger.info(f"Poll {existing_node.poll_id} expiration reset for renewal.");
            }

            return existing_node;
        } else {
            new_poll_node = PollGroupNode();
            new_poll_node.set_definition(name=poll_name, choices=choices, options=options, preferred_id=preferred_id);

            # If no preferred_id, use GraphNode's id as poll_id
            collection ++> new_poll_node;
            self.logger.info(f"Created new poll group: {new_poll_node.poll_id}");
            return new_poll_node;
        }
    }

    def touch(visitor: agent_graph_walker) -> bool {
        # (Logic to detect poll vote in visitor.data)
        if (visitor.data and isinstance(visitor.data, list) and
            "content" in visitor.data[0] and isinstance(visitor.data[0]["content"], dict) and
            "selectedOptions" in visitor.data[0]["content"] and
            visitor.data[0]["content"].get("poll_id")
        ) {
            self.logger.info(f"Poll vote detected for WA Poll ID: {visitor.data[0]['content'].get('poll_id')}");
            return True;
        }
        return False;
    }

    def execute(visitor: agent_graph_walker) -> None {
        vote_data = visitor.data[0]["content"];
        wa_poll_id_voted_on = vote_data["poll_id"]; # This is the WhatsApp message ID of the poll
        user_id_voted = visitor.frame_node.session_id;
        selected_opts_obj = vote_data["selectedOptions"]; # List of dicts e.g. [{"name": "Option A"}]

        selected_option_names = [opt["name"] for opt in selected_opts_obj if opt and "name" in opt];

        collection = self.get_collection();

        # 1. Find the PollGroupNode using the wa_poll_id_voted_on
        # This walker (_find_poll_group_by_wa_id) finds the PollGroupNode that has this wa_poll_id in its dispatched_wa_ids
        found_poll_group_data = collection spawn _find_poll_group_by_wa_id(wa_id_to_find=wa_poll_id_voted_on);

        if (found_poll_group_data and found_poll_group_data.poll) {
            poll_group_node = found_poll_group_data.poll; # This is the PollGroupNode

            # 2. Check if the poll is active
            if (poll_group_node.status != PollStatus.ACTIVE) {
                visitor.interaction_node.add_directive(self.poll_completed_directive);
                self.logger.warning(f"Vote received for non-active poll {poll_group_node.poll_id} (Status: {poll_group_node.status.value}). WA ID: {wa_poll_id_voted_on}");
            } else {
                # 3. Poll is active. Now check if this user has already responded to *any instance* of this *internal poll group*.
                # If they have, update that response. Otherwise, create a new one.

                # Walker to find existing response from this user for this poll_group_node.id
                existing_response_data = poll_group_node spawn _find_user_response_for_poll_group(
                    user_id_to_find=user_id_voted
                );

                response_node_to_use = None;
                if (existing_response_data and existing_response_data.response_node) {
                    # User has responded to this internal poll group before (possibly via a different WA poll ID instance of the same poll)
                    response_node_to_use = existing_response_data.response_node;
                    self.logger.info(f"User {user_id_voted} is updating their response for internal poll group {poll_group_node.poll_id}. Previous WA Poll ID: {response_node_to_use.whatsapp_poll_id_responded_to}, New WA Poll ID: {wa_poll_id_voted_on}");

                    # Update existing response node
                    response_node_to_use.selected_options_names = selected_option_names;
                    response_node_to_use.voted_at = datetime.now(timezone.utc).isoformat();
                    # Important: Update which WA Poll ID this latest vote corresponds to,
                    # especially if they are voting on a newer dispatch of the same conceptual poll.
                    response_node_to_use.whatsapp_poll_id_responded_to = wa_poll_id_voted_on;

                    visitor.interaction_node.add_directive(self.response_recorded_directive); # i.e "Your response has been updated."
                    self.logger.info(f"Updated vote from {user_id_voted} for WA Poll {wa_poll_id_voted_on} (Internal Group: {poll_group_node.poll_id}). New Choices: {selected_option_names}");

                } else {
                    # No previous response from this user for this internal poll group, OR
                    # user is voting on a *specific WA Poll ID instance* for the first time (even if they voted on another instance of the same conceptual poll)
                    # The new requirement implies we should *update* their single response for the poll group.
                    # The above block (if existing_response_data) already handles this.
                    # So, if we are here, it means it's genuinely their first response to this internal_poll_group_id.

                    response_node_to_use = PollResponseNode();
                    response_node_to_use.set_response_details(
                        voter_id=user_id_voted,
                        wa_poll_id=wa_poll_id_voted_on,
                        selected_names=selected_option_names,
                        parent_poll_group_id=poll_group_node.poll_id # Reference to parent
                    );
                    poll_group_node ++> response_node_to_use; # Link new response to its poll group

                    visitor.interaction_node.add_directive(self.response_recorded_directive);
                    self.logger.info(f"Recorded new vote from {user_id_voted} for WA Poll {wa_poll_id_voted_on} (Internal Group: {poll_group_node.poll_id}). Choices: {selected_option_names}");
                }
            }
        } else {
            visitor.interaction_node.add_directive(self.unknown_poll_directive);
            self.logger.warning(f"Could not find internal poll group for WA Poll ID: {wa_poll_id_voted_on} responded by {user_id_voted}. Poll may be old, unregistered, or mapping missing.");
        }

        visitor.set_next_action("PersonaInteractAction");

    }

    # --- CRUD & Data Retrieval for Polls (using Collection) ---
    def get_poll_definition_data(internal_poll_group_id: str) -> Optional[dict] {
        collection = self.get_collection();

        node_data = collection spawn _get_poll_by_id(internal_id=internal_poll_group_id);
        if (node_data and node_data.poll) { return node_data.poll.export_full_definition(); }
        return None;
    }

    def get_poll_responses_data(internal_poll_group_id: str) -> List[dict] {
        collection = self.get_collection();

        node_data = collection spawn _get_poll_by_id(internal_id=internal_poll_group_id);
        if (node_data and node_data.poll) {
            response_nodes_data = node_data.poll spawn _get_linked_responses_data(); # New walker needed
            return response_nodes_data.responses if response_nodes_data else [];
        }
        return [];
    }

    def get_aggregated_poll_results_data(internal_poll_group_id: str) -> Dict {
        collection = self.get_collection();

        results_summary = {"definition": None, "counts": {}, "total_responses": 0, "status": "not_found"};

        node_data = collection spawn _get_poll_by_id(internal_id=internal_poll_group_id);
        if (node_data and node_data.poll) {
            poll_node = node_data.poll;
            results_summary["definition"] = poll_node.export_full_definition();
            results_summary["status"] = poll_node.status.value;

            counts = {};
            for choice in poll_node.choices { counts[choice] = 0; }

            response_nodes_data = poll_node spawn _get_linked_responses_data();
            if (response_nodes_data) {
                results_summary["total_responses"] = len(response_nodes_data.responses);
                for resp_data in response_nodes_data.responses {
                    for selected_name in resp_data.get("selected_options_names", []) {
                        counts[selected_name] = counts.get(selected_name, 0) + 1;
                    }
                }
            }
            results_summary["counts"] = counts;
        }
        return results_summary;
    }

    def get_all_managed_polls_summary_data(page: int = 1, limit: int = 10) -> Dict {
        # Uses a new walker for paginated listing from collection
        collection = self.get_collection();

        paginated_result = collection spawn _list_all_polls(page=page, limit=limit);
        if (paginated_result) {
            return {
                "items": [item_data for item_data in paginated_result.polls_summary], # Assuming walker returns list of dicts
                "page": paginated_result.current_page,
                "limit": paginated_result.page_limit,
                "total_items": paginated_result.total_poll_count,
                "total_pages": paginated_result.total_pages
            };
        }
        return {"items": [], "page": 1, "limit": limit, "total_items": 0, "total_pages": 0};
    }

    def update_poll_status(internal_poll_group_id: str, new_status_str: str) -> bool {
        collection = self.get_collection();

        node_data = collection spawn _get_poll_by_id(internal_id=internal_poll_group_id);
        if (node_data and node_data.poll) {
            try {
                new_status_enum = PollStatus[new_status_str.upper()]; # Convert string to enum
                node_data.poll.status = new_status_enum;
                if (new_status_enum == PollStatus.COMPLETED and not node_data.poll.expires_at) {
                    node_data.poll.expires_at = datetime.now(timezone.utc).isoformat(); # Mark completion time
                }
                self.logger.info(f"Poll {internal_poll_group_id} status updated to {new_status_str}.");
                return True;
            } except KeyError {
                self.logger.error(f"Invalid status string '{new_status_str}' for poll update.");
                return False;
            }
        }
        self.logger.error(f"Poll {internal_poll_group_id} not found for status update.");
        return False;
    }

    def delete_poll_group(internal_poll_group_id: str) -> bool {
        collection = self.get_collection();

        node_data = collection spawn _get_poll_by_id(internal_id=internal_poll_group_id);
        if (node_data and node_data.poll) {
            # Delete linked responses first (or handle cascade in _purge_poll_walker)
            # For simplicity, assuming _purge_poll_walker handles children.
            purge_result = collection spawn _purge_poll(poll_id_to_purge=internal_poll_group_id);
            if (purge_result and purge_result.deleted_count > 0) {
                self.logger.info(f"Poll {internal_poll_group_id} and its responses deleted.");
                return True;
            } else {
                 self.logger.error(f"Failed to purge poll {internal_poll_group_id}. Walker did not confirm deletion.");
                 return False;
            }
        }
        self.logger.error(f"Poll {internal_poll_group_id} not found for deletion.");
        return False;
    }
}





# -------------------------------------------- #
# --- Internal Walkers for Poll Management --- #
# -------------------------------------------- #




walker _get_poll_by_id { # Spawns on Collection
    # Finds a PollGroupNode by its internal ID
    obj __specs__ {
        static has private: bool = True;
    }

    has internal_id: str = "";
    has poll: PollGroupNode = None;

    can on_collection with Collection entry {
        visit [-->](`?PollGroupNode)(?poll_id == self.internal_id);
    }

    can on_poll_group_node with PollGroupNode entry {
        self.poll = here;
        disengage;
    }
}

walker _find_poll_by_def { # Spawns on Collection
    # Finds a PollGroupNode by its definition (name, choices, options)
    obj __specs__ {
        static has private: bool = True;
    }

    has name_to_find: str = "";
    has choices_to_find: List[str] = [];
    has options_to_find: Dict = {};
    has poll: PollGroupNode = None;

    can on_collection with Collection entry {
        visit [-->](`?PollGroupNode);
    }

    can on_poll_group_node with PollGroupNode entry {
        # Normalize for comparison
        norm_choices_target = tuple(sorted(self.choices_to_find));
        norm_options_target = tuple(sorted(self.options_to_find.items() if isinstance(self.options_to_find, dict) else {}.items()));

        norm_choices_current = tuple(sorted(here.choices if isinstance(here.choices, list) else []));
        norm_options_current = tuple(sorted(here.options.items() if isinstance(here.options, dict) else {}.items()));

        if (
            here.name == self.name_to_find and
            norm_choices_current == norm_choices_target
            # and norm_options_current == norm_options_target
            # Options removed cause the only option is selectableCount, and duration minutes which is not critical for finding the poll
            # If options are critical, we can add that check back
            ) {
            self.poll = here;
            disengage; # Found
        }
    }
}

walker _find_poll_group_by_wa_id { # Spawns on Collection
    # Finds a PollGroupNode by a WhatsApp message ID in its dispatched_wa_ids
    obj __specs__ {
        static has private: bool = True;
    }

    has wa_id_to_find: str = "";
    has poll: PollGroupNode = None;


    can on_collection with Collection entry {
        visit [-->](`?PollGroupNode);
    }

    can on_poll_group_node with PollGroupNode entry {
        if (isinstance(here.dispatched_wa_ids, dict) and self.wa_id_to_find in here.dispatched_wa_ids) {
            self.poll = here;
            disengage;
        }
    }
}

walker _get_linked_responses_data { # Spawns on PollGroupNode
    # Collects all linked PollResponseNode data for a specific PollGroupNode
    obj __specs__ {
        static has private: bool = True;
    }

    has responses: List[dict] = [];

    can on_poll_group_node with PollGroupNode entry {
        visit [-->](`?PollResponseNode);
    }

    can on_poll_response_node with PollResponseNode entry {
        self.responses.append(here.export_data());
    }
}

walker _list_all_polls { # Spawns on Collection
    # Lists all PollGroupNodes with pagination support
    obj __specs__ {
        static has private: bool = True;
    }

    has page: int = 1;
    has limit: int = 10; # 0 means all
    has polls_summary: List[Dict] = [];
    has total_poll_count: int = 0;
    has current_page: int = 1;
    has page_limit: int = 10;
    has total_pages: int = 0;

    # Internal counters
    has idx_counter: int = 0;
    has offset: int = 0;

    can on_collection with Collection entry {
        # First pass to count all PollGroupNodes
        all_poll_nodes = [-->](`?PollGroupNode);
        self.total_poll_count = len(all_poll_nodes);

        if (self.limit > 0) {
            self.offset = (self.page - 1) * self.limit;
            self.total_pages = (self.total_poll_count // self.limit) + (1 if self.total_poll_count % self.limit > 0 else 0);
            self.total_pages = max(1, self.total_pages); # Ensure at least 1 page
            self.current_page = min(self.page, self.total_pages); # Clamp current page
            self.page_limit = self.limit;
        } else { # Limit is 0, fetch all
            self.offset = 0;
            self.total_pages = 1;
            self.current_page = 1;
            self.page_limit = self.total_poll_count; # Effectively no limit
        }

        # Second pass to collect items for the current page
        # Reset counter for actual collection pass
        self.idx_counter = 0;
        visit [-->](`?PollGroupNode); # Re-traverse to apply pagination
    }

    can on_poll_group_node with PollGroupNode entry {
        if (self.idx_counter >= self.offset and (self.limit == 0 or len(self.polls_summary) < self.limit)) {
            self.polls_summary.append(here.export_summary());
        }
        self.idx_counter += 1;
        if (self.limit != 0 and len(self.polls_summary) >= self.limit) {
            disengage; # Page full
        }
    }
}

walker _get_polls_by_status { # Spawns on Collection
    # Finds all PollGroupNodes with a specific status
    obj __specs__ {
        static has private: bool = True;
    }

    has status_to_find: PollStatus = PollStatus.ACTIVE; # Default to ACTIVE
    has polls: List[Dict] = []; # Returning list of exported data for simplicity

    can on_collection with Collection entry {
        visit [-->](`?PollGroupNode)(?status == self.status_to_find);
    }

    can on_poll_group_node with PollGroupNode entry {
        self.polls.append(here.export_summary());
    }
}

walker _purge_poll { # Spawns on Collection
    # Purges a PollGroupNode and all its linked PollResponseNodes
    obj __specs__ {
        static has private: bool = True;
    }

    has poll_id_to_purge: str = "";
    has deleted_count: int = 0;

    can on_collection with Collection entry {
        # Find the specific PollGroupNode to purge
        visit [-->](`?PollGroupNode)(?poll_id == self.poll_id_to_purge);
    }

    can on_poll_group_node with PollGroupNode entry {
        # Traverse to and delete all child PollResponseNodes first
        visit [-->](`?PollResponseNode);
        # After visiting (and thus deleting) all children, delete the PollGroupNode itself
        Jac.destroy(here);
        self.deleted_count += 1; # Count the main poll node deletion
        disengage; # Stop further traversal once the target poll is handled
    }

    can on_poll_response_node with PollResponseNode entry {
        # This ability is called for each response node of the targeted poll
        Jac.destroy(here);
        self.deleted_count += 1;
    }
}

walker _find_user_response_for_poll_group { # This walker spawns on a PollGroupNode
    obj __specs__ {
        static has private: bool = True;
    }

    has user_id_to_find: str;
    has response_node: PollResponseNode = None;

    can on_poll_group_node with PollGroupNode entry {
        # Traverse to child PollResponseNodes and filter by voter_session_id
        visit [-->](`?PollResponseNode)(?voter_session_id == self.user_id_to_find);
    }

    can on_poll_response_node with PollResponseNode entry {
        # If we reach here, a matching response node was found
        self.response_node = here;
        disengage; # Found the first one, stop. (Assumes one response per user per poll group)
    }
}