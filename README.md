# Poll Manager Interact Action

## Package Information

- **Name:** jivas/poll_manager_interact_action
- **Author:** AA
- **Architype:** PollManagerAction
- **Version:** 0.0.1

## Meta Information

- **Title:** Poll Manager Interact Action
- **Description:** Manages the creation, dispatch (via WPPConnect), response tracking, and lifecycle of polls. Poll data is persisted in Jiva Collections.
- **Group:** utility
- **Type:** interact_action

## Features (v0.0.1)

- **Persistent Storage:** Poll definitions and responses are stored in Jiva Collections, ensuring data survives agent restarts.
- **Poll Dispatch:** Can dispatch polls to users via a configured `WPPConnectAction`.
  - Supports poll name, choices, selectable count, and an optional duration.
- **External Registration:** Allows other actions (like `WPPConnectAction`) to register polls they dispatch, linking them to internal tracking.
- **Response Tracking:** Captures user votes on polls (when `visitor.data` contains poll response).
- **Lifecycle Management:**
  - Polls can have a duration.
  - A `pulse` ability (intended for use with `PulseAction`) automatically marks active polls as "COMPLETED" when their duration expires.
- **CRUD Operations (via Walkers & Action Abilities):**
  - Create new polls (via dispatch).
  - Read poll definitions, responses, and aggregated results.
  - Update poll status (e.g., manually mark as "COMPLETED", "ARCHIVED").
  - Delete polls and their associated responses.
- **Data Retrieval & Summaries:**
  - Get individual poll details.
  - Get paginated lists of all managed polls.
  - Get aggregated vote counts for polls.
- **Streamlit UI:** Provides an interface in the Action App for:
  - Dispatching new polls.
  - Viewing lists of polls with pagination.
  - Viewing aggregated results and raw responses for selected polls.
  - Performing CRUD operations (archive, mark complete, delete).
  - Basic configuration.

## Configuration (To be set in Agent DAF under this action's context)

- **`whatsapp_action`**: (String, default: "WPPConnectAction") The label of the `WPPConnectAction` instance this agent uses.
- **`response_recorded_directive`**: (String) Message template for confirming a vote.
- **`response_record_failed_directive`**: (String) Message template for vote recording failure.
- **`unknown_poll_directive`**: (String) Message template if a vote is for an unknown/expired poll.
- **`poll_completed_directive`**: (String) Message template if a vote is for a completed poll.
- **`pulse_interval_seconds`**: (Integer, default: 300) How often the lifecycle pulse checks for expired polls.

## Core Stored Data (Jiva Collection Nodes)

- **`PollGroupNode`**: Represents a unique poll definition.
  - Stores: `name`, `choices`, `options` (including `selectableCount`, `duration_minutes`), `created_at`, `expires_at`, `status` (ACTIVE, COMPLETED, ARCHIVED), `dispatched_wa_ids` (map of WA message IDs to user session IDs).
- **`PollResponseNode`**: Represents a single user's vote on a poll instance.
  - Stores: `voter_session_id`, `whatsapp_poll_id_responded_to`, `selected_options_names`, `voted_at`, `poll_group_id_ref`.

## Key Abilities

- **`dispatch_poll_via_wpp(...)`**: Dispatches a new poll using `WPPConnectAction` and registers it.
- **`register_dispatched_poll_instance(...)`**: Registers a poll dispatched by an external system (e.g., `WPPConnectAction` directly).
- **`touch(...)` / `execute(...)`**: Handles incoming poll votes from users.
- **`pulse()`**: Manages poll lifecycle (auto-completion).
- **CRUD abilities**: `get_poll_definition_data`, `update_poll_status`, `delete_poll_group`, etc.

## Walkers

- **`dispatch_new_poll_walker`**: For UI to trigger `dispatch_poll_via_wpp`.
- **`get_poll_data_walker`**: For UI to fetch poll data (summaries, details, responses) with pagination.
- **`manage_poll_crud_walker`**: For UI to trigger status updates, archive, and delete operations.

## Dependencies

- **Jiva Core**: `^2.0.0` (or as appropriate)
- **Jiva Actions**:
  - `jivas/wppconnect_action: ^0.0.1` (or version used for sending polls)
  - `jivas/pulse_action: ^0.0.1` (for scheduled lifecycle management)
- **Python Libraries**: (Typically managed by Jiva environment, ensure compatibility if custom versions are needed)
  - `requests` (if WPPConnect uses it, or for any direct HTTP by this action - not currently used directly)

## Important Note (v0.0.1)

- **Duplicate Dispatch Prevention:** The current version of `dispatch_poll_via_wpp` and `register_dispatched_poll_instance` **does not actively prevent sending the exact same poll definition to the same user multiple times if called repeatedly.** While `create_poll_group_entry` attempts to find and reuse existing poll *definitions* by content or preferred ID, it doesn't track if a specific `whatsapp_poll_id` has already been generated for that *user* for that *definition* recently.
- **Consequence:** If you dispatch the same poll definition to the same user session ID multiple times, they will receive multiple poll messages and can potentially vote on each. Each vote will be recorded against the respective `whatsapp_poll_id`, but all linked to the same `internal_poll_group_id`.
- **Mitigation:** Users of this action (e.g., UI logic or other calling actions) should implement their own checks if they need to prevent re-sending an identical active poll to a user.
- This behavior will be reviewed for improvement in future versions.

## Setup

1.  Ensure `WPPConnectAction` and `PulseAction` are configured for your agent.
2.  Add `PollManagerInteractAction` to your agent's `descriptor.yaml` and configure its context variables (especially `whatsapp_action` label).
3.  The associated `app/app.py` provides a UI for managing polls.