# Mistral API Notes

Based on analysis of the `client-python` (Mistral) client library.

## Endpoint

- **Chat Completions**: `POST https://api.mistral.ai/v1/chat/completions`

Follows the OpenAI-compatible format closely.

## Authentication

```
Authorization: Bearer $API_KEY
Content-Type: application/json
```

## Models

- `mistral-small-latest` — efficient model with vision support
- `mistral-large-latest` — most capable model
- `mistral-medium-latest` — balanced option
- Also codestral models for code tasks

## Basic Chat Completion

Request:
```json
{
  "model": "mistral-small-latest",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "What is 2+2?"}
  ]
}
```

Response:
```json
{
  "id": "cmpl-...",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "mistral-small-latest",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "2+2 equals 4."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 20,
    "completion_tokens": 8,
    "total_tokens": 28
  }
}
```

Very similar to OpenAI's format — same `choices` array structure, same `finish_reason` values.

## Streaming

Set `"stream": true`. Response is SSE:

```
data: {"id":"cmpl-...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

data: {"id":"cmpl-...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

data: {"id":"cmpl-...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":" there"},"finish_reason":null}]}

data: {"id":"cmpl-...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

Identical to OpenAI streaming format.

## Vision / Image Input

Images use the same multi-part content format as OpenAI:

```json
{
  "role": "user",
  "content": [
    {"type": "text", "text": "What's in this image?"},
    {
      "type": "image_url",
      "image_url": {"url": "https://example.com/image.jpg"}
    }
  ]
}
```

- Supports public URLs and base64 data URIs (`data:image/png;base64,...`)
- The `image_url` value can be a string URL directly or an object with `url` key — the client library supports both forms
- Vision is available on models like `mistral-small-latest` (Pixtral-based models)

Alternative simpler form (Mistral-specific):
```json
{
  "type": "image_url",
  "image_url": "https://example.com/image.jpg"
}
```

Note: the `image_url` field can be either a string or an object — this is a Mistral extension.

## Tool / Function Calling

### Defining tools

```json
{
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get weather for a location",
        "parameters": {
          "type": "object",
          "properties": {
            "location": {"type": "string", "description": "City name"},
            "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
          },
          "required": ["location"]
        }
      }
    }
  ],
  "tool_choice": "auto"
}
```

- Same structure as OpenAI
- `tool_choice` can be `"auto"`, `"none"`, `"any"` (forces a tool call), or `{"type": "function", "function": {"name": "..."}}`

### Tool call in response

```json
{
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "",
        "tool_calls": [
          {
            "id": "call_abc123",
            "type": "function",
            "function": {
              "name": "get_weather",
              "arguments": "{\"location\": \"San Francisco\"}"
            }
          }
        ]
      },
      "finish_reason": "tool_calls"
    }
  ]
}
```

- `arguments` can be a JSON string OR a parsed dict — the Mistral SDK accepts both (`Union[Dict, str]`)
- This is different from OpenAI which always returns a JSON string

### Providing tool results

```json
{
  "role": "tool",
  "name": "get_weather",
  "content": "{\"temperature\": 62}",
  "tool_call_id": "call_abc123"
}
```

- Uses `role: "tool"` like OpenAI
- Includes `name` field (the function name) — OpenAI doesn't require this in tool messages

### Tool calls in streaming

Same pattern as OpenAI — `delta.tool_calls` with `index` field for incremental argument building.

## Mistral-Specific Features

### Agents API

Mistral has a separate agents endpoint:
- `POST https://api.mistral.ai/v1/agents/completions`
- Uses `agent_id` instead of `model`
- Agents can have pre-configured tools and instructions

### Document/File Support

Mistral supports document content in messages:
```json
{
  "type": "document_url",
  "document_url": "https://example.com/document.pdf"
}
```

Also supports:
- `document_chunk` type for pre-chunked documents
- `reference_ids` for uploaded file references

### JSON Mode

```json
{
  "response_format": {"type": "json_object"}
}
```

## Key Differences from OpenAI

- API is largely OpenAI-compatible but with some extensions
- `image_url` can be a plain string (not just an object)
- Tool call `arguments` may be a parsed dict or a JSON string
- Tool result messages include `name` field
- `tool_choice: "any"` forces tool use (OpenAI uses `"required"`)
- Has agents API as a separate endpoint
- Supports document content types (`document_url`, `document_chunk`)
- No reasoning/thinking models at this time
- No server-side tool execution (web search etc.) at this time

## Key Differences from Anthropic

- Follows OpenAI message format (choices array, finish_reason, etc.)
- System prompt is a message in the array, not a top-level parameter
- Tool results use `role: "tool"`, not embedded in user messages
- Content can be a plain string (not always an array of blocks)
- No extended thinking / reasoning features
- No built-in server-side tools
