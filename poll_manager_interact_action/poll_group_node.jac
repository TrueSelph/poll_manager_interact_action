import:py from datetime { datetime, timezone, timedelta }
import:py from typing { List, Dict, Optional }
import:jac from jivas.agent.core.graph_node { GraphNode }
import:jac from actions.jivas.poll_manager_interact_action.poll_status { PollStatus }
import:py from jivas.agent.modules.agentlib.utils { Utils } # For node_obj helper
import:jac from actions.jivas.poll_manager_interact_action.poll_response_node { PollResponseNode }

node PollGroupNode :GraphNode: {
    # Stores the definition of a poll and acts as an anchor for its responses.
    # The 'id' of this node (GraphNode.id) will be our internal_poll_group_id if no preffered id is passed.

    has poll_id: str = ""; # Unique identifier for this poll group, can be set by user or auto-generated using GraphNode.id
    has name: str = ""; # The poll question or title
    has choices: list[str] = [];
    has options: dict = {}; # e.g., {"selectableCount": 1, "duration_minutes": 60}
    has created_at: str = str(datetime.now(timezone.utc).isoformat());
    has expires_at: str = ""; # ISO timestamp when the poll should auto-complete
    has status: PollStatus = PollStatus.ACTIVE;
    has original_preferred_id: str = ""; # If user provided one during creation

    # Stores WhatsApp message IDs of dispatched instances of this poll definition
    # Key: whatsapp_message_id, Value: user_session_id it was sent to (or True if broadcast)
    has dispatched_wa_ids: dict = {};


    can set_definition(
        name: str,
        choices: List[str],
        options: Dict, # e.g., {"selectableCount": 1, "duration_minutes": 60}
        preferred_id: Optional[str] = None
    ) {
        self.name = name;
        self.choices = choices;
        self.options = options if options else {};
        self.original_preferred_id = preferred_id if preferred_id else ""; # Store original preferred id if provided
        self.poll_id = preferred_id if preferred_id else self.id; # Use GraphNode's id if no preferred id is given

        duration_minutes = self.options.get("duration_minutes");
        if (isinstance(duration_minutes, (int, float)) and duration_minutes > 0) {
            self.expires_at = (datetime.now(timezone.utc) + timedelta(minutes=duration_minutes)).isoformat();
        } else {
            self.expires_at = ""; # No explicit expiration, or runs indefinitely until manually changed
        }
    }

    can add_dispatched_wa_id(wa_message_id: str, user_session_id: str) {
        # Ensures dispatched_wa_ids is initialized if it wasn't upon node creation
        if (not isinstance(self.dispatched_wa_ids, dict)) {
            self.dispatched_wa_ids = {};
        }
        self.dispatched_wa_ids[wa_message_id] = user_session_id; # Store who it was sent to
    }

    can get_responses_count() -> int {
        # Counts distinct users who responded
        # A more complex query might be needed if responses are directly linked nodes
        # For now, assume responses are stored elsewhere or this is just a quick count
        # This requires actual response nodes to be linked to this PollGroupNode to count properly.
        # Let's assume a walker will do the actual counting of linked PollResponseNodes.
        response_nodes = self spawn _get_linked_responses();
        return len(response_nodes.responses_summary) if response_nodes else 0;
    }

    can export_summary() -> dict {
        return {
            "internal_poll_group_id": self.poll_id, # GraphNode's own id
            "name": self.name,
            "choices": self.choices,
            "options": self.options,
            "status": self.status.value, # Get string value of enum
            "created_at": self.created_at,
            "expires_at": self.expires_at,
            "dispatched_instances": len(self.dispatched_wa_ids if isinstance(self.dispatched_wa_ids, dict) else {})
            # "response_count": self.get_responses_count() # This would require a traversal
        };
    }

    can export_full_definition() -> dict {
        # Similar to summary but could be expanded later if needed
        return self.export_summary(); # For now, same as summary
    }
}

# Internal walker to count responses (example of how it might be done)
walker _get_linked_responses { # Spawns on PollGroupNode
    obj __specs__ {
        # make this a private walker
        static has private: bool = True;
    }

    has responses_summary: list = [];

    # Assumes PollResponseNode are children of PollGroupNode
    can on_poll_group with PollGroupNode entry {
        visit [-->](`?PollResponseNode);
    }
    can on_poll_response with PollResponseNode entry {
        self.responses_summary.append(here.voter_session_id); # Just collecting voter IDs for a count example
    }
}