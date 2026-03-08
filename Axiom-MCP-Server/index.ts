import express from 'express';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { SSEServerTransport } from '@modelcontextprotocol/sdk/server/sse.js';
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import fs from 'fs/promises';
import path from 'path';
import cors from 'cors';

const app = express();
app.use(cors());

// Strict Base Dir Policy
const AXIOM_BASE_DIR = 'C:/Users/Martin/.n8n-files/Axiom_Files';
const AXIOM_BACKUP_DIR = 'C:/Users/Martin/Axiom_Nexus/Backups'; // example fallback

// Prevent path traversal
function sanitizePath(p: string): string {
    const resolved = path.resolve(AXIOM_BASE_DIR, p.replace(/^[\/\\]+/, ''));
    if (!resolved.toLowerCase().startsWith(AXIOM_BASE_DIR.toLowerCase())) {
        throw new Error(`Path validation failed. Access to ${p} is strictly prohibited.`);
    }
    return resolved;
}

const server = new Server(
    { name: 'axiom-nexus-fs', version: '1.0.0' },
    { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
    return {
        tools: [
            {
                name: 'write_file',
                description: 'Writes explicitly provided text content to a file.',
                inputSchema: {
                    type: 'object',
                    properties: {
                        path: { type: 'string' },
                        content: { type: 'string' },
                        writeMode: { type: 'string', enum: ['overwrite', 'append'] }
                    },
                    required: ['path', 'content']
                }
            },
            {
                name: 'read_file',
                description: 'Reads the contents of a file.',
                inputSchema: {
                    type: 'object',
                    properties: { path: { type: 'string' } },
                    required: ['path']
                }
            },
            {
                name: 'list_directory',
                description: 'Lists all files in a directory.',
                inputSchema: {
                    type: 'object',
                    properties: { path: { type: 'string' } },
                    required: ['path']
                }
            },
            {
                name: 'create_empty_file',
                description: 'Creates a completely empty file without writing any text.',
                inputSchema: {
                    type: 'object',
                    properties: { path: { type: 'string' } },
                    required: ['path']
                }
            },
            {
                name: 'delete_file',
                description: 'Safely removes a specific file.',
                inputSchema: {
                    type: 'object',
                    properties: { path: { type: 'string' } },
                    required: ['path']
                }
            }
        ]
    };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;
    const safePath = sanitizePath((args as any).path || '');

    try {
        if (name === 'write_file') {
            const { content, writeMode } = args as any;
            await fs.mkdir(path.dirname(safePath), { recursive: true });
            if (writeMode === 'append') {
                await fs.appendFile(safePath, content, 'utf8');
            } else {
                await fs.writeFile(safePath, content, 'utf8');
            }
            return { toolResult: { text: `Successfully wrote to ${safePath}` } };
        }
        else if (name === 'read_file') {
            const content = await fs.readFile(safePath, 'utf8');
            return { toolResult: { text: content } };
        }
        else if (name === 'list_directory') {
            const files = await fs.readdir(safePath);
            return { toolResult: { text: JSON.stringify(files, null, 2) } };
        }
        else if (name === 'create_empty_file') {
            await fs.mkdir(path.dirname(safePath), { recursive: true });
            await fs.writeFile(safePath, '', 'utf8');
            return { toolResult: { text: `Created empty file at ${safePath}` } };
        }
        else if (name === 'delete_file') {
            await fs.unlink(safePath);
            return { toolResult: { text: `Deleted file at ${safePath}` } };
        }
        throw new Error(`Unknown tool: ${name}`);
    } catch (e: any) {
        return { toolResult: { text: `Error: ${e.message}`, isError: true } };
    }
});

let transport: SSEServerTransport;

app.get('/sse', async (req, res) => {
    transport = new SSEServerTransport('/messages', res);
    await server.connect(transport);
});

app.post('/messages', async (req, res) => {
    if (transport) {
        await transport.handlePostMessage(req, res);
    }
});

const PORT = 3055;
app.listen(PORT, () => {
    console.log(`Axiom-MCP-Server listening on SSE at http://localhost:${PORT}/sse`);
});
