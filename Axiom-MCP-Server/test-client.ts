import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { SSEClientTransport } from '@modelcontextprotocol/sdk/client/sse.js';

async function runTest() {
    console.log('Connecting to SSE at http://localhost:3055/sse ...');
    // Using global EventSource as required by the spec
    const transport = new SSEClientTransport(new URL('http://localhost:3055/sse'));

    // Create the client
    const client = new Client(
        { name: 'mcp-test-client', version: '1.0.0' },
        { capabilities: {} }
    );

    await client.connect(transport);
    console.log('Connected! Discovering tools...');

    const tools = await client.listTools();
    console.log('Available tools:');
    tools.tools.forEach(t => console.log(`- ${t.name}: ${t.description}`));

    console.log('\nExecuting write_file tool...');
    try {
        const res = await client.callTool({
            name: 'write_file',
            arguments: {
                path: 'test_mcp_output.txt',
                content: 'Hello from MCP Integration Test!'
            }
        });
        console.log('Tool Response:', res);
    } catch (err: any) {
        console.error('Call failed:', err.message);
    }

    console.log('\nReading the file back...');
    try {
        const readRes = await client.callTool({
            name: 'read_file',
            arguments: { path: 'test_mcp_output.txt' }
        });
        console.log('Read Response:', readRes);
    } catch (err: any) {
        console.error('Read failed:', err.message);
    }

    console.log('\nTesting Path Validation Policy (should block):');
    try {
        const escRes = await client.callTool({
            name: 'read_file',
            arguments: { path: '../../../Windows/System32/drivers/etc/hosts' }
        });
        console.log('Esc Response:', escRes);
    } catch (err: any) {
        console.error('Esc failed:', err.message);
    }

    console.log('\nClosing connection...');
    await transport.close();
}

runTest().catch(console.error);
