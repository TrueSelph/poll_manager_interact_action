import from typing { List, Dict, Optional, Union }
import from jivas.agent.action.interact_graph_walker { interact_graph_walker }
import from jivas.agent.core.agent { Agent }
import from jivas.agent.action.action { Action }
import from jivas.agent.action.actions { Actions }

walker get_poll_data(interact_graph_walker) {
    has internal_poll_group_id: str = None;
    has data_type: str = "aggregated_results"; # "definition", "responses", "aggregated_results"
    has page: int = 1; # For "all_summaries"
    has limit: int = 10; # For "all_summaries"

    has response: Union[Dict, List, None] = None;

    can on_agent with Agent entry { visit [-->](`?Actions); }
    can on_actions with Actions entry { visit [-->](`?Action)(?enabled==True)(?label=='PollManagerInteractAction'); }
    can on_action with Action entry { # 'here' is PollManagerInteractAction
        if (self.data_type == "all_summaries") {
            self.response = here.get_all_managed_polls_summary_data(page=self.page, limit=self.limit);
        } elif (self.internal_poll_group_id) {
            if (self.data_type == "definition") {
                self.response = here.get_poll_definition_data(internal_poll_group_id=self.internal_poll_group_id);
            } elif (self.data_type == "responses") {
                self.response = here.get_poll_responses_data(internal_poll_group_id=self.internal_poll_group_id);
            } elif (self.data_type == "aggregated_results") {
                self.response = here.get_aggregated_poll_results_data(internal_poll_group_id=self.internal_poll_group_id);
            } else {
                self.response = {"error": f"Unknown data_type '{self.data_type}' for specific poll."};
            }
        } else {
            self.response = {"error": "internal_poll_group_id required for data_types other than 'all_summaries'."};
        }
    }
}