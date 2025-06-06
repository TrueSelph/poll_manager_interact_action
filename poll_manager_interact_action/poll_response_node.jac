import:py from datetime { datetime, timezone }
import:py from typing { List }
import:jac from jivas.agent.core.graph_node { GraphNode }

node PollResponseNode :GraphNode: {
    # Stores a single user's response to a specific WhatsApp poll instance.
    # This node will be a child of a PollGroupNode.

    has voter_session_id: str = ""; # User who voted (e.g., WhatsApp number)
    has whatsapp_poll_id_responded_to: str = ""; # The WA message ID of the poll they voted on
    has selected_options_names: list[str] = []; # List of choice names they selected
    has voted_at: str = str(datetime.now(timezone.utc).isoformat());
    has poll_group_id_ref: str = ""; # Reference back to the parent PollGroupNode.id

    can set_response_details(
        voter_id: str,
        wa_poll_id: str,
        selected_names: List[str],
        parent_poll_group_id: str
    ) {
        self.voter_session_id = voter_id;
        self.whatsapp_poll_id_responded_to = wa_poll_id;
        self.selected_options_names = selected_names;
        self.poll_group_id_ref = parent_poll_group_id;
    }

    can export_data() -> dict {
        return {
            "response_id": self.id, # GraphNode's own id
            "voter_session_id": self.voter_session_id,
            "whatsapp_poll_id_responded_to": self.whatsapp_poll_id_responded_to,
            "selected_options_names": self.selected_options_names,
            "voted_at": self.voted_at,
            "poll_group_id_ref": self.poll_group_id_ref
        };
    }
}