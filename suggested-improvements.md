# Suggested improvements for the LLM parts project

This repository is an excellent foundation for the [LLM parts refactor](https://github.com/simonw/llm). The existing examples cover single-turn streaming shapes, tool call argument streaming, reasoning tokens, and server-side web search across all four providers.

The following additions would fill gaps that directly affect the parts design.

## 1. Multi-turn conversation sequences

Every existing example is a single request/response pair. The parts project needs to understand how each provider expects conversation history to be structured when it includes tool calls interleaved with text.

**What to capture:** A 3-4 turn sequence for each provider:
1. User message
2. Assistant response containing a tool call
3. User message feeding back the tool result
4. Assistant final text response

Show the complete request body for steps 2-4 so it's clear how prior turns (including tool calls and results) are represented in the messages array.

**Why it matters:** The `parts=[]` parameter and the Conversation class both need to reconstruct this history faithfully. Each provider structures it differently:
- Anthropic: tool results go in `role: "user"` messages with `type: "tool_result"` content blocks
- OpenAI: tool results use `role: "tool"` messages
- Gemini: tool results use `functionResponse` parts inside user messages
- Mistral: follows the OpenAI pattern

A `multi-turn/` directory with one complete sequence per provider would be ideal.

## 2. Parallel tool calls in a single response

All current examples show a single tool call per response. OpenAI and Anthropic both support returning multiple tool calls simultaneously.

**What to capture:**
- A prompt that naturally triggers 2-3 tool calls at once (e.g., "What's the weather in Paris and Tokyo?")
- Both streaming and non-streaming responses
- The follow-up request that feeds back all tool results at once

**Why it matters:** The streaming assembler uses `part_index` to track which part is currently being built. Parallel tool calls that stream interleaved arguments are the hardest case for this design. Seeing the actual interleaving patterns from each provider is essential — do they stream one tool call's arguments completely before starting the next, or do they interleave?

## 3. Claude code execution

Only Claude web search is currently captured. Claude's code execution (tool type `code_execution`) is a primary motivator for the `server_executed=True` flag on parts.

**What to capture:**
- A prompt that triggers code execution (e.g., "Calculate the first 20 Fibonacci numbers")
- Both streaming and non-streaming responses
- The response should show the full sequence: text → server_tool_use block → server_tool_result block → text

**Why it matters:** This is the canonical example of server-side tool execution — the model runs code and returns the call/result chain in a single response. The parts model needs to represent this faithfully.

## 4. Gemini code execution

Gemini's code execution feature is mentioned in the notes but no response is captured.

**What to capture:**
- A prompt triggering Gemini's built-in code execution
- Both streaming and non-streaming
- Show how the executable code block and its output appear in the response

## 5. Gemini streaming tool calls

Current Gemini examples show tool calls arriving as complete objects. Need to confirm whether Gemini ever streams partial tool call arguments.

**What to capture:**
- A tool call with a large arguments payload (to encourage streaming if supported)
- The streaming response, to see if arguments arrive incrementally or all at once

**Why it matters:** If Gemini always sends complete tool calls in a single chunk, the plugin doesn't need StreamEvent support for tool call arguments — simplifying that code path.

## 6. Reasoning combined with tool calls

No current example shows a model using both extended thinking AND tool calling in a single response.

**What to capture:**
- Claude with extended thinking enabled, given a prompt that requires a tool call
- Streaming response showing: thinking chunks → text chunks → tool call chunks
- The same for OpenAI o-series with tools if applicable

**Why it matters:** This exercises the most complex streaming path — the assembler must handle transitions between reasoning, text, and tool call parts. The `part_index` scheme needs to work cleanly across all three.

## 7. Image/file output in responses

All current examples have text-only responses. Some models can generate images or return files.

**What to capture:**
- Gemini with image generation (if available via API)
- GPT-4o image generation via the API
- The response format showing how binary/image content appears

**Why it matters:** If models can return non-text content in responses, `AttachmentPart` needs to handle output attachments, not just input. If no provider currently returns inline images via the chat completions API, that's also useful to confirm — it means AttachmentPart is input-only for now.

## 8. Structured output / JSON mode

No examples show schema-constrained responses.

**What to capture:**
- A request with `response_format: { type: "json_schema", ... }` (OpenAI) or equivalent for each provider
- Both streaming and non-streaming

**Why it matters:** Schema-constrained responses may affect how parts are structured. If the entire response is a single JSON object, it's one TextPart. But some providers might structure this differently in their response format.

## 9. Error and edge cases

All current examples are successful completions. The parts assembler needs to handle failures gracefully.

**What to capture:**
- A response that hits `max_tokens` mid-stream (finish_reason: "length")
- A response interrupted by a content filter (finish_reason: "content_filter")
- A streaming tool call where the connection drops mid-argument (if reproducible)
- A rate limit error response

**Why it matters:** The assembler needs to finalize partial parts when a stream ends unexpectedly. A tool call with incomplete JSON arguments needs to be represented somehow (as an error part? a partial ToolCallPart?). These edge cases should be designed from real examples, not guessed.
