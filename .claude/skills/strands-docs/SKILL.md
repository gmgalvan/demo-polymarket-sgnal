---
name: strands-docs
description: Fetch and review Strands Agents SDK documentation before writing agent code. Use when implementing agents, tools, model providers, multi-agent graphs, MCP integration, structured output, or any code that imports from strands.
user-invocable: true
allowed-tools: WebFetch, Read, Grep, Glob
---

# Strands Agents SDK — Documentation Lookup

Before writing ANY code that uses Strands Agents SDK, you MUST fetch the relevant documentation page and verify the current API (imports, class names, method signatures, parameters).

## How to use

1. Identify which Strands feature the task requires
2. Fetch the matching documentation URL from the table below using `WebFetch`
3. Read the current API surface — pay attention to imports, class constructors, and method signatures
4. Only then write code that matches the actual SDK

## Documentation URLs

| Feature | URL |
|---------|-----|
| Quickstart / overview | https://strandsagents.com/docs/user-guide/quickstart/overview/ |
| Agent class | https://strandsagents.com/docs/user-guide/concepts/agents/overview/ |
| Tools (`@tool` decorator) | https://strandsagents.com/docs/user-guide/concepts/tools/overview/ |
| Model providers overview | https://strandsagents.com/docs/user-guide/concepts/model-providers/overview/ |
| LiteLLM provider | https://strandsagents.com/docs/user-guide/concepts/model-providers/litellm/ |
| OpenAI provider | https://strandsagents.com/docs/user-guide/concepts/model-providers/open-ai/ |
| Multi-agent overview | https://strandsagents.com/docs/user-guide/concepts/multi-agent/overview/ |
| Graph orchestration | https://strandsagents.com/docs/user-guide/concepts/multi-agent/graphs/ |
| MCP tools | https://strandsagents.com/docs/user-guide/concepts/tools/mcp-tools/ |
| Structured output | https://strandsagents.com/docs/user-guide/concepts/agents/structured-output/ |
| Streaming & async | https://strandsagents.com/docs/user-guide/concepts/agents/streaming/ |
| Observability / tracing | https://strandsagents.com/docs/user-guide/concepts/agents/observe-trace/ |
| Sessions & memory | https://strandsagents.com/docs/user-guide/concepts/agents/sessions-and-memory/ |
| Hooks & lifecycle | https://strandsagents.com/docs/user-guide/concepts/agents/hooks-and-callbacks/ |

## When to fetch multiple pages

- Building a multi-agent graph → fetch **Graph orchestration** + **Agent class** + **Model providers**
- Adding MCP tools to an agent → fetch **MCP tools** + **Tools overview**
- Setting up structured output → fetch **Structured output** + **Agent class**

## Important

- The live documentation is the source of truth — NOT the code examples in CLAUDE.md
- If the docs show a different API than what CLAUDE.md describes, follow the docs
- After fetching, note any discrepancies so we can update CLAUDE.md
