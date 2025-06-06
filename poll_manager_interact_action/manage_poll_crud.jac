import:py from typing { Dict, Optional, Literal }
import:jac from jivas.agent.action.interact_graph_walker { interact_graph_walker }
import:jac from jivas.agent.core.agent { Agent }
import:jac from jivas.agent.action.action { Action }
import:jac from jivas.agent.action.actions { Actions }


walker manage_poll_crud :interact_graph_walker: {
    has operation: Literal["update_status", "delete", "archive"] = "update_status";
    has internal_poll_group_id: str = "";
    has new_status: str = None; # e.g., "COMPLETED", "ARCHIVED"

    has response: Dict = {};

    can on_agent with Agent entry { visit [-->](`?Actions); }
    can on_actions with Actions entry { visit [-->](`?Action)(?enabled==True)(?label=='PollManagerInteractAction'); }
    can on_action with Action entry {
        if (self.operation == "update_status") {
            if (self.new_status) {
                success = here.update_poll_status(
                    internal_poll_group_id=self.internal_poll_group_id,
                    new_status_str=self.new_status
                );
                self.response = {"status": "succeeded" if success else "failed", "message": f"Status update {'' if success else 'un'}successful."};
            } else { self.response = {"status": "failed", "message": "new_status is required for update_status."}; }
        } elif (self.operation == "delete") {
            success = here.delete_poll_group(internal_poll_group_id=self.internal_poll_group_id);
            self.response = {"status": "succeeded" if success else "failed", "message": f"Deletion {'' if success else 'un'}successful."};
        } elif (self.operation == "archive") { # Archive is just a status update
            success = here.update_poll_status(
                internal_poll_group_id=self.internal_poll_group_id,
                new_status_str="ARCHIVED" # Directly use "ARCHIVED"
            );
            self.response = {"status": "succeeded" if success else "failed", "message": f"Archive operation {'' if success else 'un'}successful."};
        } else {
            self.response = {"status": "failed", "message": f"Unknown CRUD operation: {self.operation}"};
        }
    }
}