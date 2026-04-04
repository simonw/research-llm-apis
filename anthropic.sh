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

IMAGE_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/280px-PNG_transparency_demonstration_1.png"

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
              "type": "url",
              "url": "'"$IMAGE_URL"'"
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

echo ""
echo "==> Done. Responses saved to $OUTDIR/"
