# Changelog

## [0.0.1] - 2025-06-05

### Added

- **Initial Version (`PollManagerInteractAction`)**
- Core functionality for dispatching polls via a configured `WPPConnectAction`.
- Registration of dispatched polls (from self or external actions) into a persistent Jivas Collection.
  - Custom graph nodes: `PollGroupNode` for poll definitions and `PollResponseNode` for user votes.
- Handling of incoming poll votes via `touch` and `execute` abilities.
- Lifecycle management:
  - Polls can have a `duration_minutes`.
  - `pulse` ability (for `PulseAction`) to automatically mark active polls as "COMPLETED" upon expiration.
- Status management for polls: `ACTIVE`, `COMPLETED`, `ARCHIVED`.
- CRUD operations for polls:
  - Create (via dispatch).
  - Read (definitions, individual responses, aggregated results, paginated list of summaries).
  - Update (status, e.g., to archive or manually complete).
  - Delete (poll definition and all associated responses).
- Walkers (`dispatch_new_poll_walker`, `get_poll_data_walker`, `manage_poll_crud_walker`) for UI interaction.
- Internal walkers for collection querying and manipulation.
- Streamlit UI (`app/app.py`) for:
  - Dispatching new polls with name, choices, selectable count, and duration.
  - Viewing a paginated list of managed polls.
  - Displaying aggregated results (vote counts, bar chart) and raw responses for selected polls.
  - Buttons for archiving, marking as complete, and deleting polls.
  - Basic configuration display.
- `find_existing_poll_by_definition` ability to group dispatches of identical polls under a single internal ID.
- README.md and this CHANGELOG.md.

### Known Issues / To Be Addressed

- **Duplicate Dispatch:** The action currently does not prevent sending the same poll definition to the same user multiple times if `dispatch_poll_via_wpp` is called repeatedly for that user. Each dispatch will create a new WhatsApp poll message. While votes will be linked to the same internal poll group (if definitions match), the user experience might be suboptimal. This is targeted for improvement in a future version.
- Persistence of `active_wa_poll_to_internal_id` map relies on rebuilding from collection or could be made more robust with its own collection node if performance becomes an issue for very frequent vote processing on many active polls. Current implementation for vote lookup (`_find_poll_group_by_wa_id_walker`) queries the `dispatched_wa_ids` within `PollGroupNode`s, which is good for persistence.