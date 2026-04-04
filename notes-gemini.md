# Gemini API Notes

Based on analysis of the `python-genai` client library.

## Endpoints

- **Generate Content**: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- **Stream Generate Content**: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent`
- Streaming uses a different endpoint path (not a request body flag)

Authentication is via API key as a query parameter: `?key=$API_KEY`

## Authentication

Two modes:
1. **API Key** (simpler): `?key=$API_KEY` as query parameter
2. **OAuth/Service Account**: `Authorization: Bearer $TOKEN` header (for Vertex AI)

## Models

- `gemini-2.0-flash` — fast, capable, supports tools and vision
- `gemini-2.5-flash` — supports thinking/reasoning
- `gemini-2.5-pro` — most capable
- `gemini-2.0-flash-lite` — cheapest

## Basic Content Generation

Request:
```json
{
  "contents": [
    {
      "role": "user",
      "parts": [
        {"text": "What is 2+2?"}
      ]
    }
  ]
}
```

Response:
```json
{
  "candidates": [
    {
      "content": {
        "parts": [
          {"text": "2+2 equals 4."}
        ],
        "role": "model"
      },
      "finishReason": "STOP",
      "avgLogprobs": -0.012
    }
  ],
  "usageMetadata": {
    "promptTokenCount": 10,
    "candidatesTokenCount": 8,
    "totalTokenCount": 18
  },
  "modelVersion": "gemini-2.0-flash"
}
```

Key structural differences:
- Uses `contents` (not `messages`) with `parts` (not `content`)
- Role is `"model"` (not `"assistant"`)
- Response wraps in `candidates` array (not `choices`)
- Uses `finishReason` (camelCase) with values like `"STOP"`, `"MAX_TOKENS"`, `"SAFETY"`
- Uses `usageMetadata` (not `usage`)

## Multi-turn Conversation

```json
{
  "contents": [
    {"role": "user", "parts": [{"text": "Hello"}]},
    {"role": "model", "parts": [{"text": "Hi there!"}]},
    {"role": "user", "parts": [{"text": "What is 2+2?"}]}
  ]
}
```

- Alternating `user` and `model` roles
- System instructions are a separate top-level field:
```json
{
  "system_instruction": {
    "parts": [{"text": "You are a helpful assistant."}]
  },
  "contents": [...]
}
```

## Streaming

Uses a **different endpoint** — append `:streamGenerateContent` instead of `:generateContent`, plus `?alt=sse` for SSE format:

```
POST /v1beta/models/gemini-2.0-flash:streamGenerateContent?alt=sse&key=$API_KEY
```

Response is SSE:
```
data: {"candidates":[{"content":{"parts":[{"text":"Hello"}],"role":"model"},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":1,"totalTokenCount":11}}

data: {"candidates":[{"content":{"parts":[{"text":" there!"}],"role":"model"}}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":3,"totalTokenCount":13}}
```

Key differences from OpenAI/Mistral streaming:
- Each SSE chunk is a complete `GenerateContentResponse` (not a delta)
- The text in each chunk is the incremental addition (not cumulative)
- No `[DONE]` sentinel — stream just ends
- `usageMetadata` may appear in each chunk with running totals
- Without `?alt=sse`, returns a JSON array of responses instead of SSE

## Vision / Image Input

### Inline base64 data

```json
{
  "contents": [
    {
      "role": "user",
      "parts": [
        {"text": "Describe this image."},
        {
          "inline_data": {
            "mime_type": "image/png",
            "data": "<base64-encoded-bytes>"
          }
        }
      ]
    }
  ]
}
```

### File reference (for uploaded files)

```json
{
  "parts": [
    {
      "file_data": {
        "file_uri": "https://generativelanguage.googleapis.com/v1beta/files/abc123",
        "mime_type": "image/jpeg"
      }
    }
  ]
}
```

- Supports `inline_data` (base64) and `file_data` (uploaded file URI)
- No direct URL support for arbitrary web images — must be base64 or uploaded via Files API
- Supports images, video, audio, PDFs as inline_data

## Tool / Function Calling

### Defining tools

```json
{
  "tools": [
    {
      "function_declarations": [
        {
          "name": "get_weather",
          "description": "Get weather for a location",
          "parameters": {
            "type": "OBJECT",
            "properties": {
              "location": {"type": "STRING", "description": "City name"},
              "unit": {"type": "STRING", "enum": ["celsius", "fahrenheit"]}
            },
            "required": ["location"]
          }
        }
      ]
    }
  ]
}
```

- Tools contain `function_declarations` array (not individual tool objects)
- Schema types are UPPERCASE: `"OBJECT"`, `"STRING"`, `"NUMBER"`, `"BOOLEAN"`, `"ARRAY"`
- Multiple functions can be in one `function_declarations` array

### Tool call in response

```json
{
  "candidates": [
    {
      "content": {
        "parts": [
          {
            "functionCall": {
              "name": "get_weather",
              "args": {
                "location": "San Francisco",
                "unit": "celsius"
              }
            }
          }
        ],
        "role": "model"
      },
      "finishReason": "STOP"
    }
  ]
}
```

- Function calls appear as `functionCall` parts (camelCase)
- `args` is a parsed object (not a JSON string)
- Note: `finishReason` may still be `"STOP"` even with function calls (unlike OpenAI's `"tool_calls"`)

### Providing tool results

```json
{
  "contents": [
    {"role": "user", "parts": [{"text": "What's the weather?"}]},
    {"role": "model", "parts": [{"functionCall": {"name": "get_weather", "args": {"location": "SF"}}}]},
    {
      "role": "user",
      "parts": [
        {
          "functionResponse": {
            "name": "get_weather",
            "response": {"temperature": 62, "condition": "foggy"}
          }
        }
      ]
    }
  ]
}
```

- Tool results use `functionResponse` part in a `user` role message
- `response` is a parsed object (not a string)
- No explicit `tool_call_id` — matched by `name`

### Tool calls in streaming

Function calls stream as complete parts (not incrementally):
```
data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"get_weather","args":{"location":"San Francisco"}}}],"role":"model"}}]}
```

- With `stream_function_call_arguments: true` in generation config, arguments can stream incrementally

## Thinking / Reasoning

Available on `gemini-2.5-flash` and `gemini-2.5-pro`:

```json
{
  "generationConfig": {
    "thinking_config": {
      "thinking_budget": 1024
    }
  }
}
```

Response includes thinking parts:
```json
{
  "candidates": [
    {
      "content": {
        "parts": [
          {
            "thought": true,
            "text": "Let me count the letters..."
          },
          {
            "text": "There are 3 r's in strawberry."
          }
        ],
        "role": "model"
      }
    }
  ]
}
```

- Thinking content appears as parts with `"thought": true`
- `thinking_budget` controls token budget for thinking (0 to disable, -1 for dynamic)
- Thinking parts appear before the regular response parts

## Server-Side Tools (Google Search)

```json
{
  "tools": [
    {"google_search": {}}
  ]
}
```

Response includes grounding metadata:
```json
{
  "candidates": [
    {
      "content": {
        "parts": [{"text": "Based on recent news..."}],
        "role": "model"
      },
      "groundingMetadata": {
        "searchEntryPoint": {
          "renderedContent": "<HTML search widget>"
        },
        "groundingChunks": [
          {
            "web": {
              "uri": "https://example.com/article",
              "title": "Article Title"
            }
          }
        ],
        "groundingSupports": [
          {
            "segment": {"startIndex": 0, "endIndex": 50, "text": "..."},
            "groundingChunkIndices": [0],
            "confidenceScores": [0.95]
          }
        ],
        "webSearchQueries": ["search query used"]
      }
    }
  ]
}
```

- Google Search is configured as a tool object `{"google_search": {}}`
- Results include `groundingMetadata` with source URLs, confidence scores, and text segment mappings
- `searchEntryPoint.renderedContent` contains an HTML widget for displaying search results
- `groundingSupports` maps response text segments to source chunks with confidence scores
- `webSearchQueries` shows what queries were executed

Other server-side tools:
- `{"code_execution": {}}` — runs Python code server-side
- `{"google_search_retrieval": {"dynamic_retrieval_config": {"mode": "MODE_DYNAMIC", "dynamic_threshold": 0.5}}}` — dynamic search grounding

## Generation Config

```json
{
  "generationConfig": {
    "temperature": 0.7,
    "topP": 0.9,
    "topK": 40,
    "maxOutputTokens": 1024,
    "stopSequences": ["END"],
    "candidateCount": 1,
    "responseMimeType": "application/json",
    "responseSchema": {"type": "OBJECT", "properties": {...}},
    "thinking_config": {"thinking_budget": 1024}
  }
}
```

- Uses camelCase for config fields
- `responseMimeType: "application/json"` with `responseSchema` enables structured output
- `candidateCount` can generate multiple responses (unlike most providers)

## Key Differences from Other Providers

- Completely different message structure: `contents` with `parts` instead of `messages` with `content`
- Role is `"model"` not `"assistant"`
- Schema types are UPPERCASE strings
- Streaming uses a different endpoint path (not a request body flag)
- No `[DONE]` sentinel in SSE streams
- Function calls use `functionCall`/`functionResponse` (camelCase) as parts
- No tool_call_id for matching results — uses function name
- Arguments are always parsed objects
- Grounding metadata is rich with segment-level source attribution
- System instructions are a top-level field with `parts` structure
- API key goes in query string, not headers
- `finishReason` doesn't distinguish between text and function call completions
