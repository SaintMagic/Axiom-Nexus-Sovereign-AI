import cors from 'cors';
import express from 'express';
import fs from 'fs/promises';
import path from 'path';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { SSEServerTransport } from '@modelcontextprotocol/sdk/server/sse.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';

const app = express();
app.use(cors());
app.use(express.json({ limit: '4mb' }));

const AXIOM_BASE_DIR = 'C:/Users/Martin/.n8n-files/Axiom_Files';
const MCP_MESSAGES_ENDPOINT = '/messages';

interface SessionState {
	sessionId: string;
	server: Server;
	transport: SSEServerTransport;
	createdAt: number;
	lastSeenAt: number;
}

const sessions = new Map<string, SessionState>();

const textResult = (text: string, structuredContent?: Record<string, unknown>) => ({
	content: [{ type: 'text' as const, text }],
	...(structuredContent ? { structuredContent } : {}),
});

const errorResult = (message: string, structuredContent?: Record<string, unknown>) => ({
	content: [{ type: 'text' as const, text: `Error: ${message}` }],
	isError: true,
	...(structuredContent ? { structuredContent } : {}),
});

const sanitizePath = (rawPath: unknown): string => {
	const trimmed = String(rawPath || '').trim();
	if (!trimmed) throw new Error('Path is required.');

	const normalized = trimmed.replace(/\\/g, '/').replace(/^[\/\\]+/, '');
	const resolved = path.resolve(AXIOM_BASE_DIR, normalized);
	if (!resolved.toLowerCase().startsWith(path.resolve(AXIOM_BASE_DIR).toLowerCase())) {
		throw new Error(`Path validation failed. Access outside base dir is prohibited: ${trimmed}`);
	}
	return resolved;
};

const listDirectorySafe = async (targetDir: string) => {
	const entries = await fs.readdir(targetDir, { withFileTypes: true });
	return entries
		.map((e) => ({ name: e.name, type: e.isDirectory() ? 'dir' : e.isFile() ? 'file' : 'other' }))
		.sort((a, b) => a.name.localeCompare(b.name));
};

const ensureParentDir = async (targetPath: string) => {
	await fs.mkdir(path.dirname(targetPath), { recursive: true });
};

const createMcpServer = () => {
	const server = new Server({ name: 'axiom-nexus-fs', version: '1.1.0' }, { capabilities: { tools: {} } });

	server.setRequestHandler(ListToolsRequestSchema, async () => ({
		tools: [
			{
				name: 'write_file',
				description:
					'Write text to a file in AXIOM_BASE_DIR. Use content="" with writeMode="overwrite" for true empty-file creation.',
				inputSchema: {
					type: 'object',
					properties: {
						path: { type: 'string' },
						content: { type: 'string' },
						writeMode: { type: 'string', enum: ['overwrite', 'append'] },
					},
					required: ['path', 'content'],
				},
			},
			{
				name: 'read_file',
				description: 'Read UTF-8 text content from a file in AXIOM_BASE_DIR.',
				inputSchema: {
					type: 'object',
					properties: { path: { type: 'string' } },
					required: ['path'],
				},
			},
			{
				name: 'list_directory',
				description: 'List directory entries under AXIOM_BASE_DIR.',
				inputSchema: {
					type: 'object',
					properties: { path: { type: 'string' } },
					required: ['path'],
				},
			},
			{
				name: 'delete_file',
				description: 'Delete a file in AXIOM_BASE_DIR.',
				inputSchema: {
					type: 'object',
					properties: { path: { type: 'string' } },
					required: ['path'],
				},
			},
			{
				name: 'move_file',
				description: 'Rename or move a file within AXIOM_BASE_DIR.',
				inputSchema: {
					type: 'object',
					properties: {
						path: { type: 'string', description: 'Source path.' },
						toPath: { type: 'string', description: 'Destination path.' },
					},
					required: ['path', 'toPath'],
				},
			},
		],
	}));

	server.setRequestHandler(CallToolRequestSchema, async (request) => {
		const { name, arguments: args } = request.params;
		const payload = (args || {}) as Record<string, unknown>;

		try {
			if (name === 'write_file') {
				const safePath = sanitizePath(payload.path ?? payload.filePath);
				const writeMode = String(payload.writeMode || 'overwrite').toLowerCase();
				const content = String(payload.content ?? '');
				await ensureParentDir(safePath);
				if (writeMode === 'append') {
					await fs.appendFile(safePath, content, 'utf8');
				} else {
					await fs.writeFile(safePath, content, 'utf8');
				}
				return textResult(`Successfully wrote file: ${safePath}`, {
					action: 'write_file',
					path: safePath,
					writeMode,
					bytes: Buffer.byteLength(content, 'utf8'),
					emptyWrite: content.length === 0,
				});
			}

			if (name === 'read_file') {
				const safePath = sanitizePath(payload.path ?? payload.filePath);
				const content = await fs.readFile(safePath, 'utf8');
				return textResult(content, {
					action: 'read_file',
					path: safePath,
					bytes: Buffer.byteLength(content, 'utf8'),
				});
			}

			if (name === 'list_directory') {
				const safePath = sanitizePath(payload.path ?? payload.filePath);
				const items = await listDirectorySafe(safePath);
				return textResult(JSON.stringify(items, null, 2), {
					action: 'list_directory',
					path: safePath,
					count: items.length,
				});
			}

			if (name === 'delete_file') {
				const safePath = sanitizePath(payload.path ?? payload.filePath);
				await fs.unlink(safePath);
				return textResult(`Deleted file: ${safePath}`, {
					action: 'delete_file',
					path: safePath,
				});
			}

			if (name === 'move_file') {
				const sourcePath = sanitizePath(payload.path ?? payload.fromPath ?? payload.sourcePath);
				const destinationPath = sanitizePath(payload.toPath ?? payload.destinationPath ?? payload.newPath);
				if (sourcePath.toLowerCase() === destinationPath.toLowerCase()) {
					throw new Error('Source and destination paths are identical.');
				}
				await ensureParentDir(destinationPath);
				await fs.rename(sourcePath, destinationPath);
				return textResult(`Moved file from ${sourcePath} to ${destinationPath}`, {
					action: 'move_file',
					path: sourcePath,
					destinationPath,
				});
			}

			return errorResult(`Unknown tool: ${name}`);
		} catch (error) {
			return errorResult((error as Error).message || 'Tool execution failed.', {
				action: String(name || 'unknown'),
			});
		}
	});

	return server;
};

const closeSession = async (sessionId: string) => {
	const state = sessions.get(sessionId);
	if (!state) return;
	sessions.delete(sessionId);
	try {
		await state.transport.close();
	} catch {
		// Ignore transport close errors.
	}
};

app.get('/sse', async (_req, res) => {
	try {
		const server = createMcpServer();
		const transport = new SSEServerTransport(MCP_MESSAGES_ENDPOINT, res);
		await server.connect(transport);

		const sessionId = transport.sessionId;
		sessions.set(sessionId, {
			sessionId,
			server,
			transport,
			createdAt: Date.now(),
			lastSeenAt: Date.now(),
		});

		transport.onclose = () => {
			void closeSession(sessionId);
		};
		transport.onerror = () => {
			void closeSession(sessionId);
		};
	} catch (error) {
		res.status(500).json({ error: (error as Error).message || 'Failed to open SSE session.' });
	}
});

app.post('/messages', async (req, res) => {
	const sessionId = String(req.query.sessionId || '').trim();
	if (!sessionId) {
		res.status(400).json({ error: 'Missing sessionId query parameter.' });
		return;
	}

	const session = sessions.get(sessionId);
	if (!session) {
		res.status(404).json({ error: `Unknown or expired sessionId: ${sessionId}` });
		return;
	}

	session.lastSeenAt = Date.now();
	try {
		await session.transport.handlePostMessage(req, res, req.body);
	} catch (error) {
		if (!res.headersSent) {
			res.status(500).json({ error: (error as Error).message || 'Failed to process MCP message.' });
		}
	}
});

app.get('/health', (_req, res) => {
	res.json({
		status: 'ok',
		baseDir: AXIOM_BASE_DIR,
		sessions: sessions.size,
	});
});

const SESSION_TTL_MS = 1000 * 60 * 30;
setInterval(() => {
	const now = Date.now();
	for (const [sessionId, state] of sessions.entries()) {
		if (now - state.lastSeenAt > SESSION_TTL_MS) {
			void closeSession(sessionId);
		}
	}
}, 1000 * 60).unref();

const PORT = 3055;
app.listen(PORT, () => {
	console.log(`Axiom-MCP-Server listening on http://localhost:${PORT}`);
});
