---
description: Implement a task, independently review it, then apply justified feedback
---
Use the subagent tool as a chain:

1. Ask `worker` to implement and verify: $@
2. Ask `reviewer` to review the implementation using the previous output.
3. Ask `worker` to inspect the actual diff, apply justified review findings, and rerun verification using the previous output.

Return the final implementation summary and verification.
