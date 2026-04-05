# Anthropic API Notes

Based on analysis of the `anthropic-sdk-python` client library.

## Endpoint

- **Messages**: `POST https://api.anthropic.com/v1/messages`

There is only one main endpoint for all chat interactions.

## Authentication

```
x-api-key: $API_KEY
anthropic-version: 2023-06-01
Content-Type: application/json
```

- Uses `x-api-key` header (not Bearer token)
- Requires `anthropic-version` header — currently `2023-06-01`

## Models

- `claude-sonnet-4-5-20250929` — latest Sonnet with extended thinking support
- `claude-opus-4-5-20250929` — most capable model
- `claude-haiku-3-5-20241022` — fastest/cheapest

## Basic Message

Request:
```json
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 1024,
  "system": [{"type": "text", "text": "You are a helpful assistant."}],
  "messages": [
    {"role": "user", "content": "What is 2+2?"}
  ]
}
```

Response:
```json
{
  "id": "msg_...",
  "type": "message",
  "role": "assistant",
  "model": "claude-sonnet-4-5-20250929",
  "content": [
    {
      "type": "text",
      "text": "2+2 equals 4."
    }
  ],
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 20,
    "output_tokens": 8
  }
}
```

Key structural differences from OpenAI:
- `content` is always an array of content blocks (not a plain string)
- `max_tokens` is required (not optional)
- `system` is a top-level parameter, not a message in the messages array
- `stop_reason` instead of `finish_reason`; values are `"end_turn"`, `"stop_sequence"`, `"tool_use"`, `"max_tokens"`
- No `choices` array — the response IS the single completion
- `system` can be a string or an array of `{"type": "text", "text": "..."}` blocks

## Streaming

Set `"stream": true` in the request. Response is SSE with typed events:

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_...","type":"message","role":"assistant","content":[],"model":"claude-sonnet-4-5-20250929","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":20,"output_tokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" there"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":8}}

event: message_stop
data: {"type":"message_stop"}
```

Key streaming structure:
- Uses named `event:` types (not just `data:` lines)
- Events: `message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`, `message_delta`, `message_stop`
- `ping` events may also appear
- Each content block (text, tool_use) has its own start/delta/stop lifecycle
- The `index` field maps deltas to content blocks
- No `[DONE]` sentinel — `message_stop` is the terminal event

## Vision / Image Input

Images are content blocks in the user message:

```json
{
  "role": "user",
  "content": [
    {"type": "text", "text": "What's in this image?"},
    {
      "type": "image",
      "source": {
        "type": "base64",
        "media_type": "image/png",
        "data": "<base64-encoded-data>"
      }
    }
  ]
}
```

URL-based image source (avoids base64 encoding):
```json
{
  "type": "image",
  "source": {
    "type": "url",
    "url": "https://example.com/image.jpg"
  }
}
```

- Supported media types: `image/jpeg`, `image/png`, `image/gif`, `image/webp`
- Two source types: `base64` (with `media_type` and `data`) or `url` (with `url`)
- Multiple images supported in the same content array

## Tool Use

### Defining tools

```json
{
  "tools": [
    {
      "name": "get_weather",
      "description": "Get weather for a location",
      "input_schema": {
        "type": "object",
        "properties": {
          "location": {"type": "string", "description": "City name"},
          "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
        },
        "required": ["location"]
      }
    }
  ],
  "tool_choice": {"type": "auto"}
}
```

- Uses `input_schema` (not `parameters` like OpenAI)
- `tool_choice` is an object: `{"type": "auto"}`, `{"type": "any"}`, `{"type": "tool", "name": "get_weather"}`
- Optional `"disable_parallel_tool_use": true` inside `tool_choice`

### Tool use in response

```json
{
  "content": [
    {
      "type": "text",
      "text": "I'll check the weather for you."
    },
    {
      "type": "tool_use",
      "id": "toolu_01NRLabsLyVHZPKxbKvkfSMn",
      "name": "get_weather",
      "input": {"location": "San Francisco", "unit": "celsius"}
    }
  ],
  "stop_reason": "tool_use"
}
```

- Tool calls appear as content blocks alongside text
- `input` is a parsed object (not a JSON string like OpenAI)
- `stop_reason` is `"tool_use"`
- The model may include explanatory text before the tool call

### Providing tool results

```json
{
  "role": "user",
  "content": [
    {
      "type": "tool_result",
      "tool_use_id": "toolu_01NRLabsLyVHZPKxbKvkfSMn",
      "content": [
        {"type": "text", "text": "{\"temperature\": 62, \"condition\": \"foggy\"}"}
      ]
    }
  ]
}
```

- Tool results go in a `role: "user"` message (not `role: "tool"`)
- `content` in the tool result can be a string or array of content blocks
- `is_error: true` can be set to indicate the tool call failed

### Tool use in streaming

Tool use blocks stream the `input` JSON incrementally:

```
event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01...","name":"get_weather","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"lo"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"cation\": \"San"}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}
```

- Delta type is `input_json_delta` with `partial_json` field
- The partial JSON fragments must be concatenated and then parsed

## Extended Thinking

```json
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 4096,
  "thinking": {
    "type": "enabled",
    "budget_tokens": 2048
  },
  "messages": [...]
}
```

Response includes a thinking content block:
```json
{
  "content": [
    {
      "type": "thinking",
      "thinking": "Let me count the letters in 'strawberry'...\ns-t-r-a-w-b-e-r-r-y\nI see r at positions 3, 8, 9. That's 3 r's."
    },
    {
      "type": "text",
      "text": "There are 3 r's in strawberry."
    }
  ]
}
```

- `budget_tokens` controls how much thinking is allowed (minimum 1024)
- `max_tokens` must be greater than `budget_tokens`
- Thinking content appears as a `type: "thinking"` content block before the text response
- In streaming, thinking blocks use `content_block_start` with `type: "thinking"` and `content_block_delta` with `type: "thinking_delta"`

## Server-Side Tools (Web Search)

```json
{
  "tools": [
    {
      "type": "web_search_20250305",
      "name": "web_search"
    }
  ]
}
```

- Web search is a built-in tool type (not a function you define)
- The model autonomously decides when to search and executes searches server-side
- Response includes `server_tool_use` content blocks showing what was searched
- Usage includes `server_tool_use.web_search_requests` count
- Results appear as `web_search_tool_result` content blocks with search results and citations

Response content blocks for web search:
```json
{
  "content": [
    {"type": "server_tool_use", "id": "srvtoolu_...", "name": "web_search", "input": {"query": "..."}},
    {"type": "web_search_tool_result", "tool_use_id": "srvtoolu_...", "content": [
      {"type": "web_search_result", "url": "...", "title": "...", "encrypted_content": "...", "page_age": "..."}
    ]},
    {"type": "text", "text": "Based on my search..."}
  ]
}
```

## MCP (Model Context Protocol) — Beta

Anthropic supports server-side MCP via a beta API. The API connects to remote MCP servers and executes tools on your behalf.

Requires:
- Beta endpoint: `POST /v1/messages?beta=true`
- Beta header: `anthropic-beta: mcp-client-2025-11-20`
- Both `mcp_servers` (top-level) AND `tools` with an `mcp_toolset` entry

```json
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 1024,
  "mcp_servers": [
    {
      "type": "url",
      "name": "gitmcp",
      "url": "https://gitmcp.io/anthropics/anthropic-cookbook"
    }
  ],
  "tools": [
    {"type": "mcp_toolset", "mcp_server_name": "gitmcp"}
  ],
  "messages": [
    {"role": "user", "content": "search documentation for tool use"}
  ]
}
```

- `mcp_servers` defines the remote MCP server(s) to connect to
  - `type` must be `"url"`
  - `name` is your label for the server (referenced by `mcp_toolset`)
  - `url` is the MCP server endpoint
  - Optional `authorization_token` for authenticated servers
- `tools` must include `{"type": "mcp_toolset", "mcp_server_name": "..."}` referencing the server by name
- `mcp_toolset` can optionally include `default_config` and per-tool `configs`

Response includes MCP-specific content block types:

```json
{
  "content": [
    {"type": "text", "text": "I'll search for that."},
    {
      "type": "mcp_tool_use",
      "id": "mcptoolu_01DH6bc3QrqEnTcLH5jdtwCw",
      "name": "search_anthropic_docs",
      "input": {"query": "tool use"},
      "server_name": "gitmcp"
    },
    {
      "type": "mcp_tool_result",
      "tool_use_id": "mcptoolu_01DH6bc3QrqEnTcLH5jdtwCw",
      "is_error": false,
      "content": [{"type": "text", "text": "### Search Results..."}]
    },
    {"type": "text", "text": "Based on the search results..."}
  ]
}
```

- `mcp_tool_use` — the model's tool call (like `tool_use` but with `server_name`)
- `mcp_tool_result` — the server-side result (appears automatically, not sent by the client)
- Multiple tool call/result pairs can appear interleaved with text in a single response
- The model may make multiple MCP calls in sequence within one response
- In streaming, `mcp_tool_use` blocks stream like regular `tool_use` (with `input_json_delta`), while `mcp_tool_result` blocks arrive as complete `content_block_start` events

## Key Differences from Other Providers

- Content is always an array of typed blocks (text, tool_use, thinking, image, etc.)
- `max_tokens` is required
- System prompt is a top-level parameter, not a message role
- Tool call inputs are parsed objects, not JSON strings
- Tool results go in user messages, not a special "tool" role
- Streaming uses named event types with explicit lifecycle (start/delta/stop) per content block
- No `choices` array — single response
- Extended thinking is a first-class feature with its own content block type
- Server-side tools (web search) have dedicated content block types
