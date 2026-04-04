#!/bin/bash
# Anthropic API research - capture example responses for various features
# Uses curl to hit the API directly and save raw JSON responses

set -euo pipefail

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  API_KEY="$ANTHROPIC_API_KEY"
elif command -v llm >/dev/null; then
  API_KEY="$(llm keys get anthropic)"
else
  echo "Set ANTHROPIC_API_KEY or install llm" >&2
  exit 1
fi
BASE_URL="https://api.anthropic.com/v1"
OUTDIR="responses/anthropic"
mkdir -p "$OUTDIR"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_B64=$(base64 < "$SCRIPT_DIR/test-image.png")

# --- 1. Non-streaming text completion ---
echo "==> Anthropic: non-streaming text completion"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 256,
    "messages": [
      {"role": "user", "content": "What are the three primary colors? Reply in one sentence."}
    ]
  }' | tee "$OUTDIR/text.json" | python3 -m json.tool

# --- 2. Streaming text completion ---
echo ""
echo "==> Anthropic: streaming text completion"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 256,
    "stream": true,
    "messages": [
      {"role": "user", "content": "What are the three primary colors? Reply in one sentence."}
    ]
  }' | tee "$OUTDIR/text_streaming.txt"

# --- 3. Vision input ---
echo ""
echo "==> Anthropic: vision input"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 256,
    "messages": [
      {
        "role": "user",
        "content": [
          {"type": "text", "text": "Describe this image in one sentence."},
          {
            "type": "image",
            "source": {
              "type": "base64",
              "media_type": "image/png",
              "data": "'"$IMAGE_B64"'"
            }
          }
        ]
      }
    ]
  }' | tee "$OUTDIR/vision.json" | python3 -m json.tool

# --- 4. Tool calling ---
echo ""
echo "==> Anthropic: tool calling"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 256,
    "messages": [
      {"role": "user", "content": "What is the weather in San Francisco?"}
    ],
    "tools": [
      {
        "name": "get_weather",
        "description": "Get the current weather for a location",
        "input_schema": {
          "type": "object",
          "properties": {
            "location": {"type": "string", "description": "City name"},
            "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
          },
          "required": ["location"]
        }
      }
    ]
  }' | tee "$OUTDIR/tool_call.json" | python3 -m json.tool

# --- 5. Tool calling (streaming) ---
echo ""
echo "==> Anthropic: tool calling (streaming)"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 256,
    "stream": true,
    "messages": [
      {"role": "user", "content": "What is the weather in San Francisco?"}
    ],
    "tools": [
      {
        "name": "get_weather",
        "description": "Get the current weather for a location",
        "input_schema": {
          "type": "object",
          "properties": {
            "location": {"type": "string", "description": "City name"},
            "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
          },
          "required": ["location"]
        }
      }
    ]
  }' | tee "$OUTDIR/tool_call_streaming.txt"

# --- 6. Extended thinking ---
echo ""
echo "==> Anthropic: extended thinking"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 4096,
    "thinking": {
      "type": "enabled",
      "budget_tokens": 2048
    },
    "messages": [
      {"role": "user", "content": "How many r letters are in the word strawberry?"}
    ]
  }' | tee "$OUTDIR/thinking.json" | python3 -m json.tool

# --- 7. Extended thinking (streaming) ---
echo ""
echo "==> Anthropic: extended thinking (streaming)"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 4096,
    "stream": true,
    "thinking": {
      "type": "enabled",
      "budget_tokens": 2048
    },
    "messages": [
      {"role": "user", "content": "How many r letters are in the word strawberry?"}
    ]
  }' | tee "$OUTDIR/thinking_streaming.txt"

# --- 8. Web search (server-side tool) ---
echo ""
echo "==> Anthropic: web search (server-side tool)"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 512,
    "messages": [
      {"role": "user", "content": "What is the latest news about Anthropic?"}
    ],
    "tools": [
      {"type": "web_search_20250305", "name": "web_search"}
    ]
  }' | tee "$OUTDIR/web_search.json" | python3 -m json.tool

# --- 9. Web search (streaming) ---
echo ""
echo "==> Anthropic: web search (streaming)"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 512,
    "stream": true,
    "messages": [
      {"role": "user", "content": "What is the latest news about Anthropic?"}
    ],
    "tools": [
      {"type": "web_search_20250305", "name": "web_search"}
    ]
  }' | tee "$OUTDIR/web_search_streaming.txt"

# --- 10. Multi-turn tool use sequence ---
# Step 1: Initial request that triggers a tool call
echo ""
echo "==> Anthropic: multi-turn step 1 - initial tool call"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 256,
    "messages": [
      {"role": "user", "content": "What is the weather in San Francisco?"}
    ],
    "tools": [
      {
        "name": "get_weather",
        "description": "Get the current weather for a location",
        "input_schema": {
          "type": "object",
          "properties": {
            "location": {"type": "string", "description": "City name"},
            "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
          },
          "required": ["location"]
        }
      }
    ]
  }' | tee "$OUTDIR/multi_turn_step1.json" | python3 -m json.tool

# Step 2: Feed back tool result and get final response
echo ""
echo "==> Anthropic: multi-turn step 2 - tool result and final response"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 256,
    "messages": [
      {"role": "user", "content": "What is the weather in San Francisco?"},
      {
        "role": "assistant",
        "content": [
          {"type": "text", "text": "I'\''ll check the weather in San Francisco for you."},
          {
            "type": "tool_use",
            "id": "toolu_weather_sf",
            "name": "get_weather",
            "input": {"location": "San Francisco"}
          }
        ]
      },
      {
        "role": "user",
        "content": [
          {
            "type": "tool_result",
            "tool_use_id": "toolu_weather_sf",
            "content": "{\"temperature\": 62, \"unit\": \"fahrenheit\", \"condition\": \"foggy\", \"humidity\": 85}"
          }
        ]
      }
    ],
    "tools": [
      {
        "name": "get_weather",
        "description": "Get the current weather for a location",
        "input_schema": {
          "type": "object",
          "properties": {
            "location": {"type": "string", "description": "City name"},
            "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
          },
          "required": ["location"]
        }
      }
    ]
  }' | tee "$OUTDIR/multi_turn_step2.json" | python3 -m json.tool

# --- 11. Parallel tool calls ---
echo ""
echo "==> Anthropic: parallel tool calls"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 512,
    "messages": [
      {"role": "user", "content": "What is the weather in Paris and Tokyo?"}
    ],
    "tools": [
      {
        "name": "get_weather",
        "description": "Get the current weather for a location",
        "input_schema": {
          "type": "object",
          "properties": {
            "location": {"type": "string", "description": "City name"},
            "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
          },
          "required": ["location"]
        }
      }
    ]
  }' | tee "$OUTDIR/parallel_tool_calls.json" | python3 -m json.tool

echo ""
echo "==> Anthropic: parallel tool calls (streaming)"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 512,
    "stream": true,
    "messages": [
      {"role": "user", "content": "What is the weather in Paris and Tokyo?"}
    ],
    "tools": [
      {
        "name": "get_weather",
        "description": "Get the current weather for a location",
        "input_schema": {
          "type": "object",
          "properties": {
            "location": {"type": "string", "description": "City name"},
            "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
          },
          "required": ["location"]
        }
      }
    ]
  }' | tee "$OUTDIR/parallel_tool_calls_streaming.txt"

# --- 12. Reasoning + tool calls (extended thinking with tools) ---
echo ""
echo "==> Anthropic: reasoning + tool calls (extended thinking)"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 4096,
    "thinking": {
      "type": "enabled",
      "budget_tokens": 2048
    },
    "messages": [
      {"role": "user", "content": "I need to plan an outfit. What is the weather in San Francisco right now?"}
    ],
    "tools": [
      {
        "name": "get_weather",
        "description": "Get the current weather for a location",
        "input_schema": {
          "type": "object",
          "properties": {
            "location": {"type": "string", "description": "City name"},
            "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
          },
          "required": ["location"]
        }
      }
    ]
  }' | tee "$OUTDIR/thinking_tool_call.json" | python3 -m json.tool

echo ""
echo "==> Anthropic: reasoning + tool calls (extended thinking, streaming)"
curl -s "$BASE_URL/messages" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 4096,
    "stream": true,
    "thinking": {
      "type": "enabled",
      "budget_tokens": 2048
    },
    "messages": [
      {"role": "user", "content": "I need to plan an outfit. What is the weather in San Francisco right now?"}
    ],
    "tools": [
      {
        "name": "get_weather",
        "description": "Get the current weather for a location",
        "input_schema": {
          "type": "object",
          "properties": {
            "location": {"type": "string", "description": "City name"},
            "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
          },
          "required": ["location"]
        }
      }
    ]
  }' | tee "$OUTDIR/thinking_tool_call_streaming.txt"

echo ""
echo "==> Done. Responses saved to $OUTDIR/"
