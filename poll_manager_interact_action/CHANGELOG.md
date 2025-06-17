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

## [0.0.2] - 2025-06-17
### Bug Fix

- Fixed broken imports and removed excess logs.