import logging;
import from logging { Logger }
import from typing { List, Dict, Optional }
import from jivas.agent.action.agent_graph_walker { agent_graph_walker }
import from jivas.agent.core.agent { Agent }
import from jivas.agent.action.action { Action }
import from jivas.agent.action.actions { Actions }

walker dispatch_new_poll(agent_graph_walker) {
    static has logger:Logger = logging.getLogger(__name__);

    has target_user_session_id: str = '';
    has poll_name: str = '';
    has choices: list[str] = [];
    has selectable_count: int = 1;
    has preferred_internal_id: str = "";
    has duration_minutes: int = None; # If provided, will set expiration
    has options_extra: dict = {}; # For WPPConnect specific options

    has response: dict = {}; # To store result from the action

    can on_agent with Agent entry { visit [-->](`?Actions); }
    can on_actions with Actions entry { visit [-->](`?Action)(?enabled==True)(?label=='PollManagerInteractAction'); }
    can on_action with Action entry { # Assuming 'here' is PollManagerInteractAction
        self.response = here.dispatch_poll_via_wpp(
            target_user_session_id=self.target_user_session_id,
            poll_name=self.poll_name,
            choices=self.choices,
            selectable_count=self.selectable_count,
            preferred_internal_id=self.preferred_internal_id,
            duration_minutes=self.duration_minutes,
            options_extra=self.options_extra
        );
    }
}