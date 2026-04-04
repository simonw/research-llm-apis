# OpenAI API Notes

Based on analysis of the `openai-python` client library.

## Endpoints

- **Chat Completions**: `POST https://api.openai.com/v1/chat/completions`
- **Responses API** (newer): `POST https://api.openai.com/v1/responses` — supports built-in tools like web search

## Authentication

```
Authorization: Bearer $API_KEY
Content-Type: application/json
```

## Models

- `gpt-4.1-mini`, `gpt-4.1`, `gpt-4o`, `gpt-4o-mini` — standard chat models
- `o3-mini`, `o3`, `o4-mini` — reasoning models (support `reasoning_effort` parameter)

## Basic Chat Completion

Request:
```json
{
  "model": "gpt-4.1-mini",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello!"},
    {"role": "assistant", "content": "Hi there!"},
    {"role": "user", "content": "What is 2+2?"}
  ]
}
```

Response:
```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "gpt-4.1-mini",
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

## Streaming

Set `"stream": true` in the request. Response is Server-Sent Events (SSE):

```
data: {"id":"chatcmpl-...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":" there"},"finish_reason":null}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

Key differences from non-streaming:
- Object type is `chat.completion.chunk` instead of `chat.completion`
- Uses `delta` instead of `message` — each chunk contains incremental content
- Stream terminates with `data: [DONE]`

## Vision / Image Input

Images are passed as multi-part content in the user message:

```json
{
  "role": "user",
  "content": [
    {"type": "text", "text": "What's in this image?"},
    {
      "type": "image_url",
      "image_url": {
        "url": "https://example.com/image.jpg",
        "detail": "auto"
      }
    }
  ]
}
```

- `url` can be a public URL or a base64 data URI: `data:image/jpeg;base64,...`
- `detail` can be `"auto"`, `"low"`, or `"high"` — controls image resolution/token usage
- Multiple images can be included in the same content array

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
        },
        "strict": true
      }
    }
  ],
  "tool_choice": "auto"
}
```

- `tool_choice` can be `"auto"`, `"none"`, `"required"`, or `{"type": "function", "function": {"name": "get_weather"}}` to force a specific tool
- `strict: true` enables structured outputs / guaranteed schema compliance

### Tool call in response

When the model wants to call a tool, the response looks like:

```json
{
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": null,
        "tool_calls": [
          {
            "id": "call_abc123",
            "type": "function",
            "function": {
              "name": "get_weather",
              "arguments": "{\"location\": \"San Francisco\", \"unit\": \"celsius\"}"
            }
          }
        ]
      },
      "finish_reason": "tool_calls"
    }
  ]
}
```

- `arguments` is a JSON string (not a parsed object)
- `finish_reason` is `"tool_calls"` instead of `"stop"`
- Multiple tool calls can appear in one response (parallel tool calling)

### Providing tool results

```json
{
  "messages": [
    {"role": "user", "content": "What's the weather in SF?"},
    {
      "role": "assistant",
      "tool_calls": [
        {
          "id": "call_abc123",
          "type": "function",
          "function": {"name": "get_weather", "arguments": "{\"location\": \"San Francisco\"}"}
        }
      ]
    },
    {
      "role": "tool",
      "tool_call_id": "call_abc123",
      "content": "{\"temperature\": 62, \"condition\": \"foggy\"}"
    }
  ]
}
```

### Tool calls in streaming

Tool calls stream incrementally via `delta.tool_calls`:

```
data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"get_weather","arguments":""}}]}}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"lo"}}]}}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"cation"}}]}}]}
```

- The `index` field identifies which tool call the delta applies to
- `id`, `type`, and `function.name` appear in the first chunk; subsequent chunks append to `arguments`

## Reasoning Models (o3-mini, o3)

```json
{
  "model": "o3-mini",
  "messages": [...],
  "reasoning_effort": "low"
}
```

- `reasoning_effort` can be `"low"`, `"medium"`, or `"high"`
- Response includes `reasoning_tokens` in usage but the reasoning content is not exposed in the response
- Reasoning models do NOT support `temperature`, `top_p`, or system messages in the same way

## Responses API (newer endpoint)

The Responses API is a newer endpoint that supports built-in server-side tools:

```json
{
  "model": "gpt-4.1-mini",
  "input": "What is the latest news about OpenAI?",
  "tools": [
    {"type": "web_search_preview"}
  ]
}
```

- Uses `input` instead of `messages`
- Supports `web_search_preview` as a built-in tool type
- Can also use `file_search` and `code_interpreter` as built-in tools
- Streaming works with `"stream": true` and returns SSE events

## Key Differences from Other Providers

- Uses `role: "tool"` for tool results (not `role: "user"` with special content)
- Tool call arguments are JSON strings, not parsed objects
- `finish_reason` field indicates why generation stopped (`stop`, `tool_calls`, `length`, `content_filter`)
- System messages use `role: "system"` in the messages array
- The newer Responses API coexists with Chat Completions — different structure, different capabilities
