import from enum { unique }

@unique
enum PollStatus {
    ACTIVE = "ACTIVE",       # Poll is currently running
    COMPLETED = "COMPLETED", # Poll has run its duration and is closed for new votes
    ARCHIVED = "ARCHIVED",   # Poll is administratively hidden but data retained
    # DRAFT = "DRAFT"; # Optional: If we want a draft state before dispatching
}