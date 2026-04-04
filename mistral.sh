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

IMAGE_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/280px-PNG_transparency_demonstration_1.png"

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
          {"type": "image_url", "image_url": {"url": "'"$IMAGE_URL"'"}}
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

echo ""
echo "==> Done. Responses saved to $OUTDIR/"
