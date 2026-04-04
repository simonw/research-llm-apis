#!/bin/bash
# Mistral API research - capture example responses for various features
# Uses curl to hit the API directly and save raw JSON responses

set -euo pipefail

if [ -n "${MISTRAL_API_KEY:-}" ]; then
  API_KEY="$MISTRAL_API_KEY"
elif command -v llm >/dev/null; then
  API_KEY="$(llm keys get mistral)"
else
  echo "Set MISTRAL_API_KEY or install llm" >&2
  exit 1
fi
BASE_URL="https://api.mistral.ai/v1"
OUTDIR="responses/mistral"
mkdir -p "$OUTDIR"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_B64=$(base64 < "$SCRIPT_DIR/test-image.png")

# --- 1. Non-streaming text completion ---
echo "==> Mistral: non-streaming text completion"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-small-latest",
    "messages": [
      {"role": "user", "content": "What are the three primary colors? Reply in one sentence."}
    ]
  }' | tee "$OUTDIR/text.json" | python3 -m json.tool

# --- 2. Streaming text completion ---
echo ""
echo "==> Mistral: streaming text completion"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-small-latest",
    "stream": true,
    "messages": [
      {"role": "user", "content": "What are the three primary colors? Reply in one sentence."}
    ]
  }' | tee "$OUTDIR/text_streaming.txt"

# --- 3. Vision input ---
echo ""
echo "==> Mistral: vision input"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-small-latest",
    "messages": [
      {
        "role": "user",
        "content": [
          {"type": "text", "text": "Describe this image in one sentence."},
          {"type": "image_url", "image_url": {"url": "data:image/png;base64,'"$IMAGE_B64"'"}}
        ]
      }
    ]
  }' | tee "$OUTDIR/vision.json" | python3 -m json.tool

# --- 4. Tool calling ---
echo ""
echo "==> Mistral: tool calling"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-small-latest",
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
    ],
    "tool_choice": "any"
  }' | tee "$OUTDIR/tool_call.json" | python3 -m json.tool

# --- 5. Tool calling (streaming) ---
echo ""
echo "==> Mistral: tool calling (streaming)"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-small-latest",
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
    ],
    "tool_choice": "any"
  }' | tee "$OUTDIR/tool_call_streaming.txt"

# --- 6. Multi-turn tool use sequence ---
# Step 1: Initial request that triggers a tool call
echo ""
echo "==> Mistral: multi-turn step 1 - initial tool call"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-small-latest",
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
    ],
    "tool_choice": "any"
  }' | tee "$OUTDIR/multi_turn_step1.json" | python3 -m json.tool

# Step 2: Feed back tool result and get final response
echo ""
echo "==> Mistral: multi-turn step 2 - tool result and final response"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-small-latest",
    "messages": [
      {"role": "user", "content": "What is the weather in San Francisco?"},
      {
        "role": "assistant",
        "tool_calls": [
          {
            "id": "abc12XY9z",
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
        "name": "get_weather",
        "tool_call_id": "abc12XY9z",
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

# --- 7. Parallel tool calls ---
echo ""
echo "==> Mistral: parallel tool calls"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-small-latest",
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
    ],
    "tool_choice": "any"
  }' | tee "$OUTDIR/parallel_tool_calls.json" | python3 -m json.tool

echo ""
echo "==> Mistral: parallel tool calls (streaming)"
curl -s "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-small-latest",
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
    ],
    "tool_choice": "any"
  }' | tee "$OUTDIR/parallel_tool_calls_streaming.txt"

echo ""
echo "==> Done. Responses saved to $OUTDIR/"
