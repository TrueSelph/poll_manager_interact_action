# Action Node
include:jac poll_manager_interact_action;

# Walkers
include:jac dispatch_new_poll;
include:jac get_poll_data;
include:jac manage_poll_crud; # New CRUD walker

# Module (Custom Graph Node Definitions)
# include:jac poll_status;
# include:jac poll_group_node;
# include:jac poll_response_node;