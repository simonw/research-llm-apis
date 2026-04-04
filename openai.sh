#!/bin/bash
# OpenAI API research - capture example responses for various features
# Uses curl to hit the API directly and save raw JSON responses

set -euo pipefail

if [ -n "${OPENAI_API_KEY:-}" ]; then
  API_KEY="$OPENAI_API_KEY"
elif command -v llm >/dev/null; then
  API_KEY="$(llm keys get openai)"
else
  echo "Set OPENAI_API_KEY or install llm" >&2
  exit 1
fi
BASE_URL="https://api.openai.com/v1"
OUTDIR="responses/openai"
mkdir -p "$OUTDIR"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_B64=$(base64 < "$SCRIPT_DIR/test-image.png")
IMAGE_DATA_URI="data:image/png;base64,$IMAGE_B64"

# --- 1. Non-streaming text completion ---
echo "==> OpenAI: non-streaming text completion"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4.1-mini",
    "messages": [
      {"role": "user", "content": "What are the three primary colors? Reply in one sentence."}
    ]
  }' | tee "$OUTDIR/text.json" | python3 -m json.tool

# --- 2. Streaming text completion ---
echo ""
echo "==> OpenAI: streaming text completion"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4.1-mini",
    "stream": true,
    "messages": [
      {"role": "user", "content": "What are the three primary colors? Reply in one sentence."}
    ]
  }' | tee "$OUTDIR/text_streaming.txt"

# --- 3. Vision input ---
echo ""
echo "==> OpenAI: vision input"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4.1-mini",
    "messages": [
      {
        "role": "user",
        "content": [
          {"type": "text", "text": "Describe this image in one sentence."},
          {"type": "image_url", "image_url": {"url": "'"$IMAGE_DATA_URI"'"}}
        ]
      }
    ]
  }' | tee "$OUTDIR/vision.json" | python3 -m json.tool

# --- 4. Tool calling ---
echo ""
echo "==> OpenAI: tool calling"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4.1-mini",
    "messages": [
      {"role": "user", "content": "What is the weather in San Francisco?"}
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get the current weather for a location",
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
    ]
  }' | tee "$OUTDIR/tool_call.json" | python3 -m json.tool

# --- 5. Tool calling (streaming) ---
echo ""
echo "==> OpenAI: tool calling (streaming)"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4.1-mini",
    "stream": true,
    "messages": [
      {"role": "user", "content": "What is the weather in San Francisco?"}
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get the current weather for a location",
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
    ]
  }' | tee "$OUTDIR/tool_call_streaming.txt"

# --- 6. Reasoning (o3-mini) ---
echo ""
echo "==> OpenAI: reasoning with o3-mini"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "o3-mini",
    "messages": [
      {"role": "user", "content": "How many r letters are in the word strawberry?"}
    ],
    "reasoning_effort": "low"
  }' | tee "$OUTDIR/reasoning.json" | python3 -m json.tool

# --- 7. Reasoning (streaming) ---
echo ""
echo "==> OpenAI: reasoning with o3-mini (streaming)"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "o3-mini",
    "stream": true,
    "messages": [
      {"role": "user", "content": "How many r letters are in the word strawberry?"}
    ],
    "reasoning_effort": "low"
  }' | tee "$OUTDIR/reasoning_streaming.txt"

# --- 8. Web search (responses API) ---
echo ""
echo "==> OpenAI: web search via responses API"
curl -s "$BASE_URL/responses" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4.1-mini",
    "input": "What is the latest news about OpenAI?",
    "tools": [
      {"type": "web_search_preview"}
    ]
  }' | tee "$OUTDIR/web_search.json" | python3 -m json.tool

# --- 9. Web search (responses API, streaming) ---
echo ""
echo "==> OpenAI: web search via responses API (streaming)"
curl -s "$BASE_URL/responses" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4.1-mini",
    "stream": true,
    "input": "What is the latest news about OpenAI?",
    "tools": [
      {"type": "web_search_preview"}
    ]
  }' | tee "$OUTDIR/web_search_streaming.txt"

# --- 10. Multi-turn tool use sequence ---
# Step 1: Initial request that triggers a tool call
echo ""
echo "==> OpenAI: multi-turn step 1 - initial tool call"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4.1-mini",
    "messages": [
      {"role": "user", "content": "What is the weather in San Francisco?"}
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get the current weather for a location",
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
    ]
  }' | tee "$OUTDIR/multi_turn_step1.json" | python3 -m json.tool

# Step 2: Feed back tool result and get final response
echo ""
echo "==> OpenAI: multi-turn step 2 - tool result and final response"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4.1-mini",
    "messages": [
      {"role": "user", "content": "What is the weather in San Francisco?"},
      {
        "role": "assistant",
        "tool_calls": [
          {
            "id": "call_weather_sf",
            "type": "function",
            "function": {
              "name": "get_weather",
              "arguments": "{\"location\": \"San Francisco\"}"
            }
          }
        ]
      },
      {
        "role": "tool",
        "tool_call_id": "call_weather_sf",
        "content": "{\"temperature\": 62, \"unit\": \"fahrenheit\", \"condition\": \"foggy\", \"humidity\": 85}"
      }
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get the current weather for a location",
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
    ]
  }' | tee "$OUTDIR/multi_turn_step2.json" | python3 -m json.tool

# --- 11. Parallel tool calls ---
echo ""
echo "==> OpenAI: parallel tool calls"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4.1-mini",
    "messages": [
      {"role": "user", "content": "What is the weather in Paris and Tokyo?"}
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get the current weather for a location",
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
    ]
  }' | tee "$OUTDIR/parallel_tool_calls.json" | python3 -m json.tool

echo ""
echo "==> OpenAI: parallel tool calls (streaming)"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4.1-mini",
    "stream": true,
    "messages": [
      {"role": "user", "content": "What is the weather in Paris and Tokyo?"}
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get the current weather for a location",
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
    ]
  }' | tee "$OUTDIR/parallel_tool_calls_streaming.txt"

# --- 12. Reasoning + tool calls (o3-mini with tools) ---
echo ""
echo "==> OpenAI: reasoning + tool calls (o3-mini)"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "o3-mini",
    "messages": [
      {"role": "user", "content": "I need to plan an outfit. What is the weather in San Francisco right now?"}
    ],
    "reasoning_effort": "low",
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get the current weather for a location",
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
    ]
  }' | tee "$OUTDIR/reasoning_tool_call.json" | python3 -m json.tool

echo ""
echo "==> OpenAI: reasoning + tool calls (o3-mini, streaming)"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "o3-mini",
    "stream": true,
    "messages": [
      {"role": "user", "content": "I need to plan an outfit. What is the weather in San Francisco right now?"}
    ],
    "reasoning_effort": "low",
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get the current weather for a location",
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
    ]
  }' | tee "$OUTDIR/reasoning_tool_call_streaming.txt"

echo ""
echo "==> Done. Responses saved to $OUTDIR/"
