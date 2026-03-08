# Walkthrough: Pragmatic Architecture Rollout (Phase 31)

This phase systematically removed the most volatile and inconsistent heuristics from the Axiom Nexus engine, substituting them with rigid deterministic execution contracts. We have stabilized the planner boundary, established strict process policies, and successfully verified them via a local mock node tester.

## Completed Enhancements

### 1. Hardened Payload Delivery (Response Envelopes)
A major fault point was the silent dropping of webhook payloads when execution branches crashed mid-flight due to permissions or node availability. 

- **Global Standard**: Every node now inherits `{"onError": "continueErrorOutput"}`. Instead of silently terminating the node array and hanging the system, exceptions cascade cleanly down index branches.
- **Envelope Standardization**: Responses mandate the `{status, response, action, error, traceId}` shape on output to the `respondToWebhook` node, forcing `200 OK` transactions to provide coherent state info back to the client application.

### 2. Strict Tool Control (OpenAPI Native Planning)
The previous LLM Planner prompt yielded free-form objects, leaning heavily on RegEx inference in `axiomParser.ts` for extraction.

- Refactored `LocalAiManager.node.ts` to implement native `/api/chat` with structural arrays conforming exactly to the `Model Context Protocol` / `OpenAI Tool Choice` format.
- Set explicit enforcement properties (`tool_choice: "required"`, `parallel_tool_calls: false`) to permanently prevent context splintering or multi-action confusion.
- Downstream workflow endpoints map the native `message.content` automatically back into the expected `$json.response` object, retaining compatibility without breaking the Master Router node lines.

### 3. Intermediate Representation Verification (Intent Normalization)
We enhanced `axiomParser.ts` to safely catch invalid semantic requests without triggering hallucinated payload errors.

- Validated AST structures strictly handle unsupported logic targets (`delete_file`, `create_empty_file`). 
- Caught intent failures like file renaming (`renameIntent: true`), bypassing the planner logic entirely and routing cleanly to the `clarify` execution node using the structured Error Envelopes.

### 4. Isolated File Tooling (MCP Protocol Standalone)
Filesystem operations are conceptually disconnected via an officially deployed Model Context Protocol interface.

- **Isolation Framework**: An Express/SSE server locally tests path requests prior to file touch mapping, restricting writes entirely within `~/.n8n-files/Axiom_Files`.
- **Inspector Integrity**: Demonstrated zero leak capability. Tested edge cases blocking traversal queries (`../../Windows/host`) via the exact SDK logic consumed by the n8n orchestrator. 

### 5. Systematic Regression Assertions
Formal testing guarantees parsing stability. Created `test_regression.ts` which successfully loops:
1. `create_empty_file` AST generation and zero-payload boolean verification.
2. Direct content injection maps appropriately without dropping data boundaries.
3. Numeric selection fallback bypasses errors seamlessly.
4. `delete_file` paths function correctly under explicit `write_text` constraints blockages.

These architecture reinforcements have locked the node boundaries efficiently and deterministically, directly addressing the UI hanging bugs.
