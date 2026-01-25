# Agentic Loop Pattern in LLMProtocolAdapter

## Overview

The `LLMProtocolAdapter` now implements an **agentic loop pattern** that allows the LLM to use tools and synthesize their results into a final answer. This pattern is essential for creating agents that can reason about tool outputs and provide coherent responses based on the tool execution results.

## Problem Statement

Previously, when the adapter received a message through `handleTaskSendWithTools`, the flow was:
1. Send the conversation (the message and task history) to the LLM
2. Append response to message parts
3. Call tools (if necessary)
4. Append tool call results to message parts
5. Update the task artifacts and send a completed status

**The issue**: The LLM never had a chance to process the tool results and synthesize a final answer. The adapter would just append raw tool outputs to the response and complete the task.

## Solution: Agentic Loop

The improved implementation uses an **agentic loop** that continues until the LLM provides a final answer without requesting additional tool calls:

```
┌─────────────────────────────────────────────┐
│ 1. Send conversation to LLM (with tools)   │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│ 2. LLM responds (with/without tool calls)   │
└──────────────┬──────────────────────────────┘
               │
               ▼
        ┌──────┴──────┐
        │ Tool calls? │
        └──────┬──────┘
               │
     ┌─────────┼─────────┐
     │ Yes              │ No
     ▼                  ▼
┌─────────────┐    ┌─────────────┐
│ 3. Execute  │    │ 5. Return   │
│    tools    │    │    final    │
└──────┬──────┘    │   answer    │
       │           └─────────────┘
       ▼
┌─────────────────────────────┐
│ 4. Append tool results to   │
│    conversation & go to #1  │
└─────────────────────────────┘
```

### How It Works

1. **Initial LLM Call**: The adapter sends the user's message along with the conversation history and available tools to the LLM.

2. **Process Response**: The LLM returns a response that may contain:
   - Text content (thinking, reasoning, or final answer)
   - Tool calls (requests to execute specific tools)

3. **Execute Tools** (if requested): If the LLM requested tool calls:
   - Execute each tool with its parameters
   - Capture the tool results
   - Append tool results to the conversation as "tool" messages
   - **Loop back** to step 1 with the updated conversation

4. **Final Answer**: When the LLM responds without tool calls, that response is treated as the final answer and sent to the user.

5. **Max Iterations**: To prevent infinite loops, the adapter has a configurable `maxAgenticIterations` parameter (default: 10).

## Configuration

You can configure the maximum number of agentic iterations when creating the adapter:

```swift
let adapter = LLMProtocolAdapter(
    llm: myLLM,
    model: "gpt-4",
    maxAgenticIterations: 15,  // Default is 10
    // ... other configuration
)
```

Or using the Configuration struct:

```swift
let config = LLMProtocolAdapter.Configuration(
    model: "gpt-4",
    maxAgenticIterations: 15,
    // ... other configuration
)
let adapter = LLMProtocolAdapter(llm: myLLM, configuration: config)
```

## Example Flow

### User Request
"What's the weather in San Francisco and what restaurants are nearby?"

### Iteration 1
- **LLM Response**: "I need to check the weather first."
- **Tool Calls**: `get_weather(location: "San Francisco")`
- **Tool Result**: "72°F, sunny"

### Iteration 2
- **LLM Response**: "Now let me find restaurants."
- **Tool Calls**: `find_restaurants(location: "San Francisco")`
- **Tool Result**: "Found 50 restaurants including..."

### Iteration 3
- **LLM Response**: "Based on the weather and restaurant data, here's my recommendation..."
- **Tool Calls**: (none)
- **Result**: This becomes the final answer sent to the user

## Benefits

1. **Coherent Responses**: The LLM can synthesize tool results into a natural, conversational answer
2. **Multi-Step Reasoning**: The LLM can use tool results to inform subsequent tool calls
3. **Context-Aware**: The LLM maintains context across multiple tool executions
4. **User-Friendly**: Users receive a polished final answer rather than raw tool outputs

## Implementation Details

### Non-Streaming (`handleTaskSendWithTools`)
- Executes the full agentic loop before returning
- Only sends the final synthesized answer to the user
- Logs each iteration for debugging

### Streaming (`handleStreamWithTools`)
- Streams each LLM response as it's generated
- Shows tool execution status to the user
- Continues streaming through multiple iterations
- Sends a final consolidated response at the end

## Logging

The adapter logs important events during the agentic loop:

```
[INFO] Agentic iteration 1/10
[INFO] Executing 2 tool call(s)
[INFO] Agentic iteration 2/10
[INFO] Final response received (no tool calls)
```

Or in case of hitting the limit:

```
[WARNING] Max agentic iterations reached without final response
```

## Best Practices

1. **Set Reasonable Limits**: Default of 10 iterations is usually sufficient. Increase if your use case requires complex multi-step reasoning.

2. **Tool Design**: Design tools to return concise, relevant information. The LLM needs to process these results, so verbose outputs can impact quality.

3. **System Prompts**: Consider adding instructions in your system prompt about how to use tools and synthesize results:
   ```swift
   var prompt = DynamicPrompt(template: """
   When using tools, always synthesize the results into a clear, 
   concise answer for the user. Don't just repeat tool outputs.
   """)
   systemPrompt: prompt
   ```

4. **Monitor Logs**: Watch the logs to understand how many iterations your typical requests require and adjust accordingly.

## Migration from Previous Version

If you're upgrading from the previous version that didn't implement the agentic loop:

1. **No Code Changes Required**: The new parameter has a default value, so existing code continues to work.

2. **Behavioral Change**: Your adapter will now provide synthesized answers instead of raw tool outputs. This is generally an improvement but may change the format of responses.

3. **Performance**: The agentic loop may increase latency for tool-using requests, as it requires multiple LLM calls. Monitor your performance metrics.

## Troubleshooting

### "Maximum iterations reached"
This means the LLM kept requesting tool calls without providing a final answer. Consider:
- Increasing `maxAgenticIterations`
- Reviewing your system prompt to encourage final answers
- Checking if tools are returning useful information

### Response seems incomplete
The LLM might be hitting token limits. Consider:
- Increasing `maxTokens` in your configuration
- Asking tools to return more concise results
- Breaking complex queries into simpler ones

### Too many tool calls
The LLM might be unnecessarily calling tools. Consider:
- Improving your system prompt to encourage efficiency
- Ensuring tools have clear, descriptive descriptions
- Reducing the number of available tools

