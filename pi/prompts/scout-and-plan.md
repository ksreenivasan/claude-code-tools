---
description: Scout the codebase and produce an implementation plan without making changes
---
Use the subagent tool as a chain:

1. Ask `scout` to find all code relevant to: $@
2. Ask `planner` to produce a concrete implementation plan for "$@" using the previous output.

Return the plan without implementing it.
