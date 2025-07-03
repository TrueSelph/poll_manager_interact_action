"""Poll Manager Interact Action App
This app allows users to manage polls via WPPConnect, including creating, viewing, and managing poll data.
"""

import json

import pandas as pd
import streamlit as st
from jvclient.lib.utils import call_action_walker_exec
from jvclient.lib.widgets import app_controls, app_header, app_update_action
from streamlit_router import StreamlitRouter  # Assuming this is part of your setup


def render(router: StreamlitRouter, agent_id: str, action_id: str, info: dict) -> None:
    """Render the Poll Manager Interact Action App."""

    (model_key, module_root) = app_header(agent_id, action_id, info)

    # --- Session State Initialization ---
    if f"{model_key}_target_user" not in st.session_state:
        st.session_state[f"{model_key}_target_user"] = ""
    if f"{model_key}_poll_name" not in st.session_state:
        st.session_state[f"{model_key}_poll_name"] = ""
    if f"{model_key}_poll_choices" not in st.session_state:
        st.session_state[f"{model_key}_poll_choices"] = "Option 1, Option 2, Option 3"
    if f"{model_key}_selectable_count" not in st.session_state:
        st.session_state[f"{model_key}_selectable_count"] = 1
    if f"{model_key}_duration_minutes" not in st.session_state:
        st.session_state[f"{model_key}_duration_minutes"] = 60  # Default 1 hour
    if f"{model_key}_preferred_internal_id" not in st.session_state:
        st.session_state[f"{model_key}_preferred_internal_id"] = ""

    if f"{model_key}_polls_list_page" not in st.session_state:
        st.session_state[f"{model_key}_polls_list_page"] = 1
    if f"{model_key}_polls_list_limit" not in st.session_state:
        st.session_state[f"{model_key}_polls_list_limit"] = 10
    if f"{model_key}_polls_list_cache" not in st.session_state:
        st.session_state[f"{model_key}_polls_list_cache"] = (
            None  # Store {items:[], total_pages:1, ...}
        )

    if f"{model_key}_selected_poll_for_view_id" not in st.session_state:
        st.session_state[f"{model_key}_selected_poll_for_view_id"] = None

    tab1, tab2, tab3 = st.tabs(
        ["Dispatch New Poll", "Manage & View Polls", "Configuration"]
    )

    with tab1:
        st.subheader("Dispatch a New Poll via WPPConnect")
        with st.form("dispatch_poll_form"):
            st.session_state[f"{model_key}_target_user"] = st.text_input(
                "Target User Session ID (e.g., WhatsApp number)",
                value=st.session_state[f"{model_key}_target_user"],
            )
            st.session_state[f"{model_key}_poll_name"] = st.text_input(
                "Poll Name/Question", value=st.session_state[f"{model_key}_poll_name"]
            )
            st.session_state[f"{model_key}_poll_choices"] = st.text_area(
                "Poll Choices (comma-separated)",
                value=st.session_state[f"{model_key}_poll_choices"],
            )
            st.session_state[f"{model_key}_selectable_count"] = st.number_input(
                "Selectable Count",
                min_value=1,
                value=st.session_state[f"{model_key}_selectable_count"],
            )
            st.session_state[f"{model_key}_duration_minutes"] = st.number_input(
                "Poll Duration (minutes, 0 for indefinite)",
                min_value=0,
                value=st.session_state[f"{model_key}_duration_minutes"],
                help="Poll will automatically be marked 'COMPLETED' after this duration.",
            )
            st.session_state[f"{model_key}_preferred_internal_id"] = st.text_input(
                "Preferred Internal ID (Optional)",
                value=st.session_state[f"{model_key}_preferred_internal_id"],
            )

            submitted_dispatch = st.form_submit_button("Dispatch Poll")

        if submitted_dispatch:
            if not all(
                [
                    st.session_state[f"{model_key}_target_user"],
                    st.session_state[f"{model_key}_poll_name"],
                    st.session_state[f"{model_key}_poll_choices"],
                ]
            ):
                st.error("Target User, Poll Name, and Choices are required.")
            else:
                choices_list = [
                    choice.strip()
                    for choice in st.session_state[f"{model_key}_poll_choices"].split(
                        ","
                    )
                    if choice.strip()
                ]
                if not choices_list:
                    st.error("Please provide at least one poll choice.")
                else:
                    with st.spinner("Dispatching poll..."):
                        payload = {
                            "target_user_session_id": st.session_state[
                                f"{model_key}_target_user"
                            ],
                            "poll_name": st.session_state[f"{model_key}_poll_name"],
                            "choices": choices_list,
                            "selectable_count": st.session_state[
                                f"{model_key}_selectable_count"
                            ],
                            "duration_minutes": (
                                st.session_state[f"{model_key}_duration_minutes"]
                                if st.session_state[f"{model_key}_duration_minutes"] > 0
                                else None
                            ),
                            "preferred_internal_id": st.session_state[
                                f"{model_key}_preferred_internal_id"
                            ]
                            or None,
                        }
                        result = call_action_walker_exec(
                            agent_id, module_root, "dispatch_new_poll", payload
                        )
                        st.text(f"Dispatch Result: {json.dumps(result, indent=2)}")
                        if result and result.get("status") == "succeeded":
                            st.success(
                                f"Poll dispatch initiated! WA ID: {result.get('whatsapp_poll_id')}, Internal Group ID: {result.get('internal_poll_group_id')}"
                            )
                            st.session_state[f"{model_key}_polls_list_cache"] = (
                                None  # Invalidate list cache
                            )
                        else:
                            st.error(
                                f"Failed to dispatch poll: {result.get('message', 'Unknown error')}"
                            )
                            if result and result.get("details"):
                                st.json(result.get("details"))

    with tab2:
        st.subheader("Managed Polls")

        # --- Polls List & Pagination ---
        if st.button("🔄 Refresh Polls List", key=f"{model_key}_refresh_polls_tab2"):
            st.session_state[f"{model_key}_polls_list_cache"] = None
            st.session_state[f"{model_key}_selected_poll_for_view_id"] = None
            st.rerun()

        # Load polls if cache is empty
        if st.session_state.get(f"{model_key}_polls_list_cache") is None:
            with st.spinner("Loading polls..."):
                list_payload = {
                    "data_type": "all_summaries",
                    "page": st.session_state[f"{model_key}_polls_list_page"],
                    "limit": st.session_state[f"{model_key}_polls_list_limit"],
                }
                list_result = call_action_walker_exec(
                    agent_id, module_root, "get_poll_data", list_payload
                )
                if (
                    list_result
                    and isinstance(list_result, dict)
                    and "items" in list_result
                ):
                    st.session_state[f"{model_key}_polls_list_cache"] = list_result
                else:
                    st.session_state[f"{model_key}_polls_list_cache"] = {
                        "items": [],
                        "total_pages": 1,
                        "total_items": 0,
                        "page": 1,
                        "limit": 10,
                    }
                    st.error("Failed to load polls or no polls found.")

        cached_list_data = st.session_state[f"{model_key}_polls_list_cache"]
        all_polls_items = cached_list_data.get("items", [])
        total_pages = cached_list_data.get("total_pages", 1)
        total_items = cached_list_data.get("total_items", 0)
        current_page = st.session_state[f"{model_key}_polls_list_page"]

        if not all_polls_items and total_items == 0:
            st.info("No polls managed by this action yet.")
        else:
            st.write(
                f"Displaying {len(all_polls_items)} of {total_items} polls. Page {current_page}/{total_pages}"
            )

            cols_nav = st.columns([1, 1, 6, 1])
            if cols_nav[0].button(
                "⬅️ Prev", key=f"{model_key}_prev_polls", disabled=(current_page <= 1)
            ):
                st.session_state[f"{model_key}_polls_list_page"] -= 1
                st.session_state[f"{model_key}_polls_list_cache"] = None  # Force reload
                st.rerun()
            if cols_nav[1].button(
                "Next ➡️",
                key=f"{model_key}_next_polls",
                disabled=(current_page >= total_pages),
            ):
                st.session_state[f"{model_key}_polls_list_page"] += 1
                st.session_state[f"{model_key}_polls_list_cache"] = None  # Force reload
                st.rerun()

            for poll_summary in all_polls_items:
                poll_id = poll_summary.get("internal_poll_group_id")
                with st.expander(
                    f"{poll_summary.get('name', 'N/A')} (ID: {poll_id}, Status: {poll_summary.get('status', 'N/A')})"
                ):
                    st.caption(
                        f"Created: {poll_summary.get('created_at')}, Expires: {poll_summary.get('expires_at', 'N/A')}"
                    )
                    st.caption(
                        f"Choices: {poll_summary.get('choices')}, Options: {poll_summary.get('options')}"
                    )

                    # --- View Results ---
                    if st.button("View Aggregated Results", key=f"view_res_{poll_id}"):
                        st.session_state[f"{model_key}_selected_poll_for_view_id"] = (
                            poll_id
                        )
                        # No need to rerun, just display below or in a modal if complex

                    # --- CRUD Operations ---
                    col_actions1, col_actions2, col_actions3 = st.columns(3)
                    if col_actions1.button(
                        "Archive Poll",
                        key=f"archive_{poll_id}",
                        help="Sets status to ARCHIVED.",
                    ):
                        with st.spinner(f"Archiving poll {poll_id}..."):
                            payload = {
                                "operation": "archive",
                                "internal_poll_group_id": poll_id,
                            }
                            res = call_action_walker_exec(
                                agent_id, module_root, "manage_poll_crud", payload
                            )
                            if res and res.get("status") == "succeeded":
                                st.success("Poll archived.")
                            else:
                                st.error(f"Archive failed: {res.get('message')}")
                            st.session_state[f"{model_key}_polls_list_cache"] = None
                            st.rerun()

                    current_status = poll_summary.get("status", "").upper()
                    if current_status not in {
                        "COMPLETED",
                        "ARCHIVED",
                    } and col_actions2.button(
                        "Mark as Completed", key=f"complete_{poll_id}"
                    ):
                        with st.spinner(f"Marking poll {poll_id} as completed..."):
                            payload = {
                                "operation": "update_status",
                                "internal_poll_group_id": poll_id,
                                "new_status": "COMPLETED",
                            }
                            st.text(f"Payload: {json.dumps(payload)}")
                            res = call_action_walker_exec(
                                agent_id, module_root, "manage_poll_crud", payload
                            )
                            st.text(
                                f"Marking Poll {json.dumps(payload)} as completed: {json.dumps(res, indent=2)}"
                            )
                            if res and res.get("status") == "succeeded":
                                st.success("Poll marked completed.")
                            else:
                                st.error(f"Failed: {res.get('message')}")
                            st.session_state[f"{model_key}_polls_list_cache"] = None
                            st.rerun()

                    if col_actions3.button(
                        "🗑️ Delete Poll", type="primary", key=f"delete_{poll_id}"
                    ):
                        # Add a confirmation step here if desired
                        with st.spinner(f"Deleting poll {poll_id}..."):
                            payload = {
                                "operation": "delete",
                                "internal_poll_group_id": poll_id,
                            }
                            res = call_action_walker_exec(
                                agent_id, module_root, "manage_poll_crud", payload
                            )
                            if res and res.get("status") == "succeeded":
                                st.success("Poll deleted.")
                            else:
                                st.error(f"Delete failed: {res.get('message')}")
                            st.session_state[f"{model_key}_polls_list_cache"] = None
                            st.rerun()

            st.divider()
            # --- Display Selected Poll Details ---
            selected_id_view = st.session_state.get(
                f"{model_key}_selected_poll_for_view_id"
            )
            if selected_id_view:
                st.subheader(f"Details for Poll ID: {selected_id_view}")
                with st.spinner(f"Loading details for poll ID: {selected_id_view}..."):
                    payload_details = {
                        "internal_poll_group_id": selected_id_view,
                        "data_type": "aggregated_results",
                    }
                    details_data = call_action_walker_exec(
                        agent_id, module_root, "get_poll_data", payload_details
                    )

                if details_data and "definition" in details_data:
                    st.markdown(
                        f"**Name:** {details_data['definition'].get('name', 'N/A')}"
                    )
                    st.markdown(f"**Status:** {details_data.get('status', 'N/A')}")
                    st.caption(
                        f"Expires: {details_data['definition'].get('expires_at', 'N/A')}"
                    )
                    st.write("Choices:", details_data["definition"].get("choices", []))
                    st.write("Options:", details_data["definition"].get("options", {}))
                    st.write(
                        f"Total Responses Recorded: {details_data.get('total_responses', 0)}"
                    )

                    counts_data = details_data.get("counts", {})
                    if counts_data:
                        df_data = [
                            {"Option": choice, "Votes": count}
                            for choice, count in counts_data.items()
                        ]
                        if (
                            df_data
                        ):  # Ensure data is not empty before creating DataFrame
                            df = pd.DataFrame(df_data)
                            st.bar_chart(df.set_index("Option"))
                            st.dataframe(df.set_index("Option"))
                        else:
                            st.info("No vote data to display for chart.")
                    else:
                        st.info("No responses yet or no countable choices.")

                    if st.checkbox(
                        "Show Raw Responses Data",
                        key=f"{model_key}_show_raw_details_{selected_id_view}",
                    ):
                        raw_payload = {
                            "internal_poll_group_id": selected_id_view,
                            "data_type": "responses",
                        }
                        raw_data = call_action_walker_exec(
                            agent_id, module_root, "get_poll_data", raw_payload
                        )
                        st.json(raw_data if raw_data else [])
                else:
                    st.error(f"Could not load details for poll ID: {selected_id_view}")
                    if details_data:
                        st.json(details_data)

    with tab3:
        st.subheader("Poll Manager Configuration")
        st.info("Modify action parameters. These are persisted with the agent's DAF.")

        # Example: 'whatsapp_action' is usually fixed by admin, 'response_recorded_directive' can be edited.
        # 'masked' fields are directly supported by default app_controls in jvcli.
        # 'hidden' means it's not shown in the UI.

        # For app_controls, you'd typically list DAF-configurable 'has' variables of the action.
        # `app_controls` will render standard input widgets for them.
        # To make fields masked or hidden, this would require passing parameters to `app_controls` itself

        app_controls(
            agent_id,
            action_id,
            masked=[
                "whatsapp_action"
            ],  # Example: This field is set and not user-editable via UI
            hidden=[],  # Example: Fields you don't want to show in UI at all
        )

        # Final update action call to save any changes made in the app
        app_update_action(agent_id, action_id)
