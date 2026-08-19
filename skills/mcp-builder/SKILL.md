---
name: mcp-builder
description: Design, implement, or review an MCP server whose tools let LLMs complete realistic tasks against an external system.
---

# MCP Builder

Build the smallest MCP surface that lets an agent complete the target workflows reliably.

## Start from current sources

Before implementation, check the current official [MCP specification](https://modelcontextprotocol.io/specification/latest) and the official SDK documentation for the chosen language, such as the [TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk) or [Python SDK](https://github.com/modelcontextprotocol/python-sdk). Confirm the protocol version, transports, authorization guidance, tool annotations, and SDK APIs in force now. Do not rely on remembered or copied stale examples.

Study the upstream service API and define several realistic user tasks. Design tools around those tasks rather than mirroring every endpoint.

## Tool design

- Give each tool one clear action with a specific name and a description that distinguishes it from neighboring tools.
- Use typed input and output schemas. Bound strings, arrays, page sizes, enum values, and nested structures where the service has real limits.
- Prefer stable identifiers in inputs and return both useful identifiers and human-readable context.
- Make list/search operations paginated. Return a continuation cursor or token and enough metadata for the agent to know whether more results exist.
- Keep responses compact and task-relevant. Offer detail retrieval separately when full records are large.
- Return actionable errors that identify the failed operation, distinguish invalid input, authorization, rate limits, not-found, conflict, and upstream failure, and say what the agent can do next. Do not leak secrets or raw internal traces.
- Declare mutation annotations supported by the current specification accurately, including read-only, destructive, idempotent, and open-world behavior where applicable. An annotation is a hint, not an authorization control.
- Separate reads from writes when that improves safety or clarity. Make consequential mutations explicit and preserve the host harness's confirmation policy.

## Implementation

Use the official SDK and established project conventions. Centralize authentication and upstream error translation without hiding failures. Apply timeouts, pagination limits, and bounded retries appropriate to the service. Validate all inputs at the boundary and test representative success and failure paths.

Add resources or prompts only when they materially improve the target tasks; a focused tool-only server is often sufficient.

## Evaluate with agent tasks

Exercise the server through realistic LLM tasks, not only direct tool unit tests. Include discovery, multi-step reads, pagination, invalid input, permission failures, empty results, and at least one representative mutation when mutations are in scope. Check whether the agent selects the right tools, supplies valid arguments, recovers from actionable errors, and reaches the intended outcome without unnecessary calls.

Report supported tasks, protocol and SDK versions checked, verification performed, known service limitations, and any mutation risks left to the host.
