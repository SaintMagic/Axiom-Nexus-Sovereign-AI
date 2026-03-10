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
const OLLAMA_PULL_ENDPOINTS = ['http://127.0.0.1:11434/api/pull', 'http://localhost:11434/api/pull'];
const OLLAMA_TAGS_ENDPOINTS = ['http://127.0.0.1:11434/api/tags', 'http://localhost:11434/api/tags'];

interface SessionState {
	sessionId: string;
	server: Server;
	transport: SSEServerTransport;
	createdAt: number;
	lastSeenAt: number;
}

const sessions = new Map<string, SessionState>();

interface ModelInstallEvent {
	ts: number;
	status: string;
	message: string;
	progressPercent: number;
}

interface ModelInstallJob {
	jobId: string;
	modelName: string;
	status: 'queued' | 'running' | 'success' | 'error' | 'cancelled';
	progressPercent: number;
	latestMessage: string;
	error: string;
	createdAt: number;
	updatedAt: number;
	startedAt: number | null;
	finishedAt: number | null;
	events: ModelInstallEvent[];
}

const modelInstallJobs = new Map<string, ModelInstallJob>();
const modelInstallJobsByName = new Map<string, string>();
const MAX_MODEL_INSTALL_EVENTS = 320;
const MODEL_INSTALL_TTL_MS = 1000 * 60 * 60 * 6;

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

const sanitizeModelName = (rawModel: unknown): string => {
	const model = String(rawModel || '').trim();
	if (!model) throw new Error('Model name is required.');
	if (!/^[a-z0-9][a-z0-9._:/-]{0,127}$/i.test(model)) {
		throw new Error(`Invalid model name: ${model}`);
	}
	return model;
};

const normalizeModelKey = (rawModel: unknown): string => {
	const model = String(rawModel || '').trim().toLowerCase();
	if (!model) return '';
	return model.endsWith(':latest') ? model.replace(/:latest$/i, '') : model;
};

const fetchOllamaInstalledModels = async (): Promise<Array<{ name: string; size: number; key: string }>> => {
	let lastError: Error | null = null;

	for (const endpoint of OLLAMA_TAGS_ENDPOINTS) {
		try {
			const response = await fetch(endpoint, {
				method: 'GET',
				headers: { Accept: 'application/json' },
			});
			if (!response.ok) {
				const raw = await response.text();
				throw new Error(`Ollama tags failed at ${endpoint} (HTTP ${response.status}): ${raw || 'no response body'}`);
			}
			const payload = (await response.json()) as { models?: Array<{ name?: unknown; size?: unknown }> };
			const models = Array.isArray(payload?.models) ? payload.models : [];
			return models
				.map((model) => {
					const name = String(model?.name || '').trim();
					const key = normalizeModelKey(name);
					const size = Number(model?.size || 0);
					return {
						name,
						key,
						size: Number.isFinite(size) && size > 0 ? size : 0,
					};
				})
				.filter((item) => item.name && item.key);
		} catch (error) {
			lastError = error as Error;
		}
	}

	throw lastError || new Error('Unable to query Ollama installed models.');
};

const clampProgressPercent = (value: number): number => {
	if (!Number.isFinite(value)) return 0;
	if (value <= 0) return 0;
	if (value >= 100) return 100;
	return Math.round(value);
};

const pushModelInstallEvent = (job: ModelInstallJob, status: string, message: string, progressPercent: number) => {
	const event: ModelInstallEvent = {
		ts: Date.now(),
		status: String(status || '').trim() || 'running',
		message: String(message || '').trim() || 'progress',
		progressPercent: clampProgressPercent(progressPercent),
	};
	job.events.push(event);
	if (job.events.length > MAX_MODEL_INSTALL_EVENTS) {
		job.events.splice(0, job.events.length - MAX_MODEL_INSTALL_EVENTS);
	}
	job.latestMessage = event.message;
	job.progressPercent = Math.max(job.progressPercent, event.progressPercent);
	job.updatedAt = Date.now();
};

const buildModelInstallView = (job: ModelInstallJob) => {
	const recentEvents = job.events.slice(-20);
	return {
		jobId: job.jobId,
		modelName: job.modelName,
		status: job.status,
		progressPercent: clampProgressPercent(job.progressPercent),
		latestMessage: job.latestMessage || '',
		error: job.error || '',
		createdAt: job.createdAt,
		updatedAt: job.updatedAt,
		startedAt: job.startedAt,
		finishedAt: job.finishedAt,
		events: recentEvents,
	};
};

const computeProgressFromPayload = (payload: Record<string, unknown>, current: number): number => {
	const completed = Number(payload.completed);
	const total = Number(payload.total);
	if (Number.isFinite(completed) && Number.isFinite(total) && total > 0) {
		const ratio = Math.max(0, Math.min(1, completed / total));
		return Math.max(current, clampProgressPercent(ratio * 100));
	}
	return current;
};

const parseNdjsonLines = (buffer: string, onJson: (value: Record<string, unknown>) => void): string => {
	let pending = buffer;
	let splitIndex = pending.indexOf('\n');
	while (splitIndex >= 0) {
		const line = pending.slice(0, splitIndex).trim();
		pending = pending.slice(splitIndex + 1);
		if (line) {
			try {
				const parsed = JSON.parse(line) as Record<string, unknown>;
				onJson(parsed);
			} catch {
				// Ignore malformed stream lines.
			}
		}
		splitIndex = pending.indexOf('\n');
	}
	return pending;
};

const streamOllamaPull = async (
	endpoint: string,
	modelName: string,
	onProgress: (payload: Record<string, unknown>) => void,
) => {
	const response = await fetch(endpoint, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
		body: JSON.stringify({ name: modelName, stream: true }),
	});
	if (!response.ok) {
		const raw = await response.text();
		throw new Error(`Ollama pull failed at ${endpoint} (HTTP ${response.status}): ${raw || 'no response body'}`);
	}
	if (!response.body) {
		throw new Error(`Ollama pull failed at ${endpoint}: no response body.`);
	}

	const reader = response.body.getReader();
	const decoder = new TextDecoder();
	let buffer = '';
	while (true) {
		const { done, value } = await reader.read();
		if (done) break;
		buffer += decoder.decode(value, { stream: true });
		buffer = parseNdjsonLines(buffer, onProgress);
	}
	buffer += decoder.decode();
	if (buffer.trim()) {
		parseNdjsonLines(`${buffer}\n`, onProgress);
	}
};

const runModelInstallJob = async (job: ModelInstallJob) => {
	job.status = 'running';
	job.startedAt = Date.now();
	job.updatedAt = Date.now();
	pushModelInstallEvent(job, 'running', `Preparing download for ${job.modelName}...`, job.progressPercent);

	let lastError: Error | null = null;

	for (const endpoint of OLLAMA_PULL_ENDPOINTS) {
		try {
			await streamOllamaPull(endpoint, job.modelName, (payload) => {
				const statusText = String(payload.status || '').trim();
				const errorText = String(payload.error || '').trim();
				const nextProgress = computeProgressFromPayload(payload, job.progressPercent);
				job.progressPercent = Math.max(job.progressPercent, nextProgress);

				if (errorText) {
					job.status = 'error';
					job.error = errorText;
					pushModelInstallEvent(job, 'error', errorText, job.progressPercent);
					return;
				}

				if (statusText) {
					if (/success|up to date|already exists/i.test(statusText)) {
						job.progressPercent = 100;
					}
					pushModelInstallEvent(job, 'running', statusText, job.progressPercent);
				}
			});

			if (job.error) {
				job.status = 'error';
				throw new Error(job.error || `Model install failed for ${job.modelName}.`);
			}

			job.status = 'success';
			job.progressPercent = 100;
			pushModelInstallEvent(job, 'success', `Model ${job.modelName} installed successfully.`, 100);
			job.finishedAt = Date.now();
			job.updatedAt = Date.now();
			return;
		} catch (error) {
			lastError = error as Error;
			pushModelInstallEvent(
				job,
				'warning',
				`Endpoint ${endpoint} failed: ${(error as Error).message || 'unknown error'}`,
				job.progressPercent,
			);
		}
	}

	job.status = 'error';
	job.error = lastError?.message || `Model install failed for ${job.modelName}.`;
	job.finishedAt = Date.now();
	job.updatedAt = Date.now();
	pushModelInstallEvent(job, 'error', job.error, job.progressPercent);
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

app.post('/api/models/install', async (req, res) => {
	try {
		const modelName = sanitizeModelName(req.body?.name ?? req.body?.modelName ?? req.body?.model);
		const existingJobId = modelInstallJobsByName.get(modelName);
		if (existingJobId) {
			const existingJob = modelInstallJobs.get(existingJobId);
			if (existingJob && (existingJob.status === 'queued' || existingJob.status === 'running')) {
				res.json({
					...buildModelInstallView(existingJob),
					reused: true,
				});
				return;
			}
		}

		const jobId = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
		const now = Date.now();
		const job: ModelInstallJob = {
			jobId,
			modelName,
			status: 'queued',
			progressPercent: 0,
			latestMessage: 'Queued for installation.',
			error: '',
			createdAt: now,
			updatedAt: now,
			startedAt: null,
			finishedAt: null,
			events: [],
		};
		modelInstallJobs.set(jobId, job);
		modelInstallJobsByName.set(modelName, jobId);
		pushModelInstallEvent(job, 'queued', `Queued model install for ${modelName}.`, 0);

		void runModelInstallJob(job);

		res.json({
			...buildModelInstallView(job),
			reused: false,
		});
	} catch (error) {
		res.status(400).json({
			error: (error as Error).message || 'Failed to start model install.',
		});
	}
});

app.get('/api/models/install/:jobId', (req, res) => {
	const jobId = String(req.params.jobId || '').trim();
	if (!jobId) {
		res.status(400).json({ error: 'Missing jobId.' });
		return;
	}
	const job = modelInstallJobs.get(jobId);
	if (!job) {
		res.status(404).json({ error: `Unknown jobId: ${jobId}` });
		return;
	}
	res.json(buildModelInstallView(job));
});

app.get('/api/models/installed', async (_req, res) => {
	try {
		const models = await fetchOllamaInstalledModels();
		const installedByName: Record<string, { name: string; size: number }> = {};
		for (const model of models) {
			installedByName[model.key] = {
				name: model.name,
				size: model.size,
			};
		}
		res.json({
			count: models.length,
			models,
			installedByName,
		});
	} catch (error) {
		res.status(502).json({
			error: (error as Error).message || 'Failed to query Ollama installed models.',
		});
	}
});

app.get('/health', (_req, res) => {
	res.json({
		status: 'ok',
		baseDir: AXIOM_BASE_DIR,
		sessions: sessions.size,
		modelInstallJobs: modelInstallJobs.size,
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
	for (const [jobId, job] of modelInstallJobs.entries()) {
		const terminal = job.status === 'success' || job.status === 'error' || job.status === 'cancelled';
		const stale = terminal && (now - job.updatedAt > MODEL_INSTALL_TTL_MS);
		if (!stale) continue;
		modelInstallJobs.delete(jobId);
		const mapped = modelInstallJobsByName.get(job.modelName);
		if (mapped === jobId) modelInstallJobsByName.delete(job.modelName);
	}
}, 1000 * 60).unref();

const PORT = 3055;
app.listen(PORT, () => {
	console.log(`Axiom-MCP-Server listening on http://localhost:${PORT}`);
});
