# Insight: The Model Cannot Define Successful Completion

Ask an LLM to define "successful completion" for an autonomous worker, and it will give you a platitude: "when the task is done." But "done" is not a state the system can verify. It is a subjective judgment.

ATLAS removes the ambiguity. Successful completion means: the execution was authorized within the derived capability, the state change was applied, and the new verified state is consistent with the capability's bounds. If the collateral drops, the capability revokes. If the amount exceeds the policy, the execution reverts.

The model cannot define success because the system defines it deterministically—through the closed loop of evidence → policy → capability → execution → state re-evaluation. Recovery is not a retry; it is a re-entry into that loop with new verified state.

When the worker cannot define success, the system must. ATLAS does.