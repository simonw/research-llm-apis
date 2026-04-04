#!/bin/bash
# Gemini API research - capture example responses for various features
# Uses curl to hit the API directly and save raw JSON responses

set -euo pipefail

if [ -n "${GEMINI_API_KEY:-}" ]; then
  API_KEY="$GEMINI_API_KEY"
elif command -v llm >/dev/null; then
  API_KEY="$(llm keys get gemini)"
else
  echo "Set GEMINI_API_KEY or install llm" >&2
  exit 1
fi
BASE_URL="https://generativelanguage.googleapis.com/v1beta"
OUTDIR="responses/gemini"
mkdir -p "$OUTDIR"

IMAGE_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/280px-PNG_transparency_demonstration_1.png"

# --- 1. Non-streaming text completion ---
echo "==> Gemini: non-streaming text completion"
curl -s "$BASE_URL/models/gemini-2.0-flash:generateContent?key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [
      {
        "role": "user",
        "parts": [
          {"text": "What are the three primary colors? Reply in one sentence."}
        ]
      }
    ]
  }' | tee "$OUTDIR/text.json" | python3 -m json.tool

# --- 2. Streaming text completion ---
echo ""
echo "==> Gemini: streaming text completion"
curl -s "$BASE_URL/models/gemini-2.0-flash:streamGenerateContent?alt=sse&key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [
      {
        "role": "user",
        "parts": [
          {"text": "What are the three primary colors? Reply in one sentence."}
        ]
      }
    ]
  }' | tee "$OUTDIR/text_streaming.txt"

# --- 3. Vision input (inline image via URL fetch) ---
echo ""
echo "==> Gemini: vision input"
# Gemini supports inline_data with base64. We'll fetch the image and encode it.
IMAGE_B64=$(curl -s "$IMAGE_URL" | base64)
curl -s "$BASE_URL/models/gemini-2.0-flash:generateContent?key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [
      {
        "role": "user",
        "parts": [
          {"text": "Describe this image in one sentence."},
          {
            "inline_data": {
              "mime_type": "image/png",
              "data": "'"$IMAGE_B64"'"
            }
          }
        ]
      }
    ]
  }' | tee "$OUTDIR/vision.json" | python3 -m json.tool

# --- 4. Tool calling ---
echo ""
echo "==> Gemini: tool calling"
curl -s "$BASE_URL/models/gemini-2.0-flash:generateContent?key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [
      {
        "role": "user",
        "parts": [
          {"text": "What is the weather in San Francisco?"}
        ]
      }
    ],
    "tools": [
      {
        "function_declarations": [
          {
            "name": "get_weather",
            "description": "Get the current weather for a location",
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
  }' | tee "$OUTDIR/tool_call.json" | python3 -m json.tool

# --- 5. Tool calling (streaming) ---
echo ""
echo "==> Gemini: tool calling (streaming)"
curl -s "$BASE_URL/models/gemini-2.0-flash:streamGenerateContent?alt=sse&key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [
      {
        "role": "user",
        "parts": [
          {"text": "What is the weather in San Francisco?"}
        ]
      }
    ],
    "tools": [
      {
        "function_declarations": [
          {
            "name": "get_weather",
            "description": "Get the current weather for a location",
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
  }' | tee "$OUTDIR/tool_call_streaming.txt"

# --- 6. Thinking / reasoning ---
echo ""
echo "==> Gemini: thinking mode"
curl -s "$BASE_URL/models/gemini-2.5-flash:generateContent?key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [
      {
        "role": "user",
        "parts": [
          {"text": "How many r letters are in the word strawberry?"}
        ]
      }
    ],
    "generationConfig": {
      "thinking_config": {
        "thinking_budget": 1024
      }
    }
  }' | tee "$OUTDIR/thinking.json" | python3 -m json.tool

# --- 6b. Thinking with traces included ---
echo ""
echo "==> Gemini: thinking mode (with traces)"
curl -s "$BASE_URL/models/gemini-2.5-flash:generateContent?key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [
      {
        "role": "user",
        "parts": [
          {"text": "How many r letters are in the word strawberry?"}
        ]
      }
    ],
    "generationConfig": {
      "thinking_config": {
        "thinking_budget": 1024,
        "include_thoughts": true
      }
    }
  }' | tee "$OUTDIR/thinking_with_traces.json" | python3 -m json.tool

# --- 7. Thinking (streaming, no traces) ---
echo ""
echo "==> Gemini: thinking mode (streaming, no traces)"
curl -s "$BASE_URL/models/gemini-2.5-flash:streamGenerateContent?alt=sse&key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [
      {
        "role": "user",
        "parts": [
          {"text": "How many r letters are in the word strawberry?"}
        ]
      }
    ],
    "generationConfig": {
      "thinking_config": {
        "thinking_budget": 1024
      }
    }
  }' | tee "$OUTDIR/thinking_streaming.txt"

# --- 7b. Thinking (streaming, with traces) ---
echo ""
echo "==> Gemini: thinking mode (streaming, with traces)"
curl -s "$BASE_URL/models/gemini-2.5-flash:streamGenerateContent?alt=sse&key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [
      {
        "role": "user",
        "parts": [
          {"text": "How many r letters are in the word strawberry?"}
        ]
      }
    ],
    "generationConfig": {
      "thinking_config": {
        "thinking_budget": 1024,
        "include_thoughts": true
      }
    }
  }' | tee "$OUTDIR/thinking_with_traces_streaming.txt"

# --- 8. Google Search (server-side tool) ---
echo ""
echo "==> Gemini: google search (server-side tool)"
curl -s "$BASE_URL/models/gemini-2.0-flash:generateContent?key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [
      {
        "role": "user",
        "parts": [
          {"text": "What is the latest news about Google?"}
        ]
      }
    ],
    "tools": [
      {"google_search": {}}
    ]
  }' | tee "$OUTDIR/google_search.json" | python3 -m json.tool

# --- 9. Google Search (streaming) ---
echo ""
echo "==> Gemini: google search (streaming)"
curl -s "$BASE_URL/models/gemini-2.0-flash:streamGenerateContent?alt=sse&key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [
      {
        "role": "user",
        "parts": [
          {"text": "What is the latest news about Google?"}
        ]
      }
    ],
    "tools": [
      {"google_search": {}}
    ]
  }' | tee "$OUTDIR/google_search_streaming.txt"

echo ""
echo "==> Done. Responses saved to $OUTDIR/"
