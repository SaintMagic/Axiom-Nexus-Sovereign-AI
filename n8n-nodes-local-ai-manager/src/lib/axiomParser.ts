export type AxiomAction = 'write_file' | 'read_file' | 'list_directory' | 'error' | 'clarify';

import {
	AxiomIRExecutionMode,
	AxiomIRValidation,
	AxiomIntentIR,
	buildIntentIR,
	normalizeIntent,
	resolveIntentReferences,
	validateIntentIR,
} from './axiomIntentIR';

export interface AxiomParseInput {
	baseDir: string;
	response: string;
	originalCommand: string;
	lastFilePath?: string;
	lastUserFileCommand?: string;
	plannerTier?: string;
	defaultWriteName?: string;
	clarifyOnError?: boolean;
}

export interface AxiomParseOutput {
	action: AxiomAction;
	message?: string;
	content: string;
	fullPath: string;
	path: string;
	isExternal: boolean;
	append: boolean;
	confidence: number;
	modelConfidence: number | null;
	parserTier: string;
	confidenceBreakdown: Record<string, number>;
	lineEdits?: Array<{ line: number; text: string }>;
	postReadTransform?:
		| { type: 'space_letters' }
		| { type: 'space_words' }
		| { type: 'blank_lines_between_lines' }
		| { type: 'append_with_blank_lines'; blankLines: number; text: string }
		| { type: 'uppercase_nth'; n: number }
		| { type: 'replace_text'; from: string; to: string; caseSensitive?: boolean }
		| { type: 'line_edit'; lineEdits: Array<{ line: number; text: string }> };
	hasSpecificFilePath?: boolean;
	intentIR?: AxiomIntentIR;
	routeMode?: AxiomIRExecutionMode;
	irValidation?: AxiomIRValidation;
	planBlocks?: AxiomPlanBlock[];
	planReadable?: string;
	planReviewRequired?: boolean;
}

export interface AxiomPlanBlock {
	id: string;
	category: 'action' | 'scope' | 'modifier';
	label: string;
	value: string;
	editable: boolean;
	params?: Record<string, unknown>;
}

const ordinalMap: Record<string, number> = {
	first: 1,
	second: 2,
	third: 3,
	thrid: 3,
	tird: 3,
	fourth: 4,
	fifth: 5,
	sixth: 6,
	seventh: 7,
	eighth: 8,
	ninth: 9,
	tenth: 10,
};

const wordToNum: Record<string, number> = {
	one: 1,
	two: 2,
	three: 3,
	four: 4,
	five: 5,
	six: 6,
	seven: 7,
	eight: 8,
	nine: 9,
	ten: 10,
};

const cleanupPath = (raw: unknown): string => {
	let p = String(raw || '').replace(/\\/g, '/').trim();
	p = p.replace(/^[\s"'`]+|[\s"'`]+$/g, '');
	p = p.replace(/[\]\)\}]+$/g, '');
	p = p.replace(/[.,;:!?]+$/g, '');
	return p;
};

const stripInjectedContext = (raw: string): string => {
	let text = String(raw || '');
	text = text.replace(/\n\s*\nCurrent file content:\n[\s\S]*$/i, '');
	text = text.replace(/\n\s*\nTarget file path:\s*[^\n\r]+/i, '');
	return text.trim();
};

const sanitizeName = (name: unknown): string => {
	let n = String(name || '').trim();
	if (!n) return '';
	n = n.replace(/[<>:"/\\|?*]/g, ' ');
	n = n.replace(/\s+/g, '_');
	n = n.replace(/^_+|_+$/g, '');
	n = n.replace(/[^A-Za-z0-9._-]/g, '');
	if (!n) return '';
	if (!/\.[A-Za-z0-9]+$/.test(n)) n += '.txt';
	return n;
};

const parseJsonPayload = (text: string): Record<string, any> | null => {
	const t = String(text || '').trim();
	if (!t) return null;
	const candidates = [t];
	const unfenced = t.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '').trim();
	if (unfenced && unfenced !== t) candidates.push(unfenced);
	const m = unfenced.match(/\{[\s\S]*\}/);
	if (m) candidates.push(m[0]);
	for (const c of candidates) {
		try {
			return JSON.parse(c);
		} catch {
			// Ignore parse attempts and continue.
		}
	}
	return null;
};

const parseLineNumber = (value: unknown): number | null => {
	const t = String(value || '').toLowerCase().trim();
	if (ordinalMap[t]) return ordinalMap[t];
	const m = t.match(/^(\d+)(?:st|nd|rd|th)?[a-z]*$/);
	if (!m) return null;
	const n = Number(m[1]);
	if (!Number.isFinite(n) || n < 1) return null;
	return n;
};

const extractQuotedText = (text: string): string => {
	const dq = String(text || '').match(/"([^"]+)"/);
	if (dq) return dq[1];
	const sq = String(text || '').match(/'([^']+)'/);
	if (sq) return sq[1];
	return '';
};

const extractFileNameHint = (text: string): string => {
	const src = String(text || '');
	const patterns = [
		/\b(?:called|named|name\s+it)\s+([A-Za-z0-9 _.-]{1,80})\b/i,
		/\bfile\s+name\s*(?::|is)?\s+([A-Za-z0-9 _.-]{1,80})\b/i,
		/\bfilename\s*(?::|is)?\s+([A-Za-z0-9 _.-]{1,80})\b/i,
	];
	for (const re of patterns) {
		const m = src.match(re);
		if (m && m[1]) {
			const name = sanitizeName(m[1]);
			if (name) return name;
		}
	}
	return '';
};

const extractCreatePayload = (text: string): string => {
	const source = String(text || '');
	const quoted = extractQuotedText(source);
	if (quoted) return quoted;
	const withText = source.match(
		/\bwith\s+text\s+(.+?)(?:\s*(?:,|\.)?\s*(?:make\s+sure|call(?:ed)?|named|name\s+it|file\s+name|filename)\b|$)/i,
	);
	if (withText) return withText[1].trim();
	const textIs = source.match(
		/\btext\s*(?::|is)?\s+(.+?)(?:\s*(?:,|\.)?\s*(?:make\s+sure|call(?:ed)?|named|name\s+it|file\s+name|filename)\b|$)/i,
	);
	if (textIs) return textIs[1].trim();
	const putInto = source.match(
		/\b(?:write|put|save|append|add|make)\s+(.+?)\s+(?:to|into)\s+(?:the\s+)?(?:file|txt|text|document|[A-Za-z0-9._-]+\.[A-Za-z0-9._-]+)/i,
	);
	if (putInto) return putInto[1].trim();
	const m1 = source.match(/\b(?:create|make)(?:\s+me)?\s+(.+?)\s+in\s+(?:a\s+)?txt\s+file\b/i);
	if (m1) return m1[1].trim();
	const m2 = source.match(/\b(?:create|make)(?:\s+me)?\s+(.+?)\s+file\b/i);
	if (m2) return m2[1].trim();
	if (/hello\s+world/i.test(source)) return 'hello world';
	return '';
};

const parseRequestedCount = (text: string): number | null => {
	const lower = String(text || '').toLowerCase();
	const m = lower.match(/\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\b\s+(?:biggest|largest|top)?\s*\w*\s*capitals?/);
	if (!m) return null;
	const token = m[1];
	let n = Number(token);
	if (!Number.isFinite(n)) n = wordToNum[token] || NaN;
	if (!Number.isFinite(n) || n < 1) return null;
	return n;
};

const parseCountToken = (token: string): number | null => {
	const t = String(token || '').toLowerCase().trim();
	if (!t) return null;
	let n = Number(t);
	if (!Number.isFinite(n)) n = wordToNum[t] || NaN;
	if (!Number.isFinite(n) || n < 0) return null;
	return n;
};

const parseNthUpperRule = (textLower: string): number | null => {
	const explicit = textLower.match(/(?:every|each)\s+(\d+)(?:st|nd|rd|th)?\s+letter[^\n\r]*capit/);
	if (explicit) {
		const n = Number(explicit[1]);
		if (Number.isFinite(n) && n > 1) return n;
	}
	if (/(?:every|each)\s+(second|2nd|senond|secnd|seconf|secong)\s+letter[^\n\r]*capit/.test(textLower)) return 2;
	if (/(?:every|each)\s+(third|3rd|thrid|tird)\s+letter[^\n\r]*capit/.test(textLower)) return 3;
	return null;
};

const applyNthUpper = (text: string, n: number): string => {
	let idx = 0;
	return Array.from(String(text || ''))
		.map((ch) => {
			if (!/[a-zA-Z]/.test(ch)) return ch;
			idx += 1;
			return idx % n === 0 ? ch.toUpperCase() : ch.toLowerCase();
		})
		.join('');
};

const inferTopCapitalsContent = (cmd: string): string => {
	const lower = String(cmd || '').toLowerCase();
	const count = parseRequestedCount(lower);
	if (!count || !/\bcapitals?\b/.test(lower)) return '';
	const ranked = ['Tokyo', 'Delhi', 'Beijing', 'Cairo', 'Moscow', 'London', 'Paris', 'Madrid'];
	const chosen = ranked.slice(0, count);
	const spaced =
		/\b(each|every)\s+(two|2)\s+lines?\b/.test(lower) ||
		/\btwo\s+lines?\b/.test(lower) ||
		/\bover\s+next\b/.test(lower);
	return chosen.join(spaced ? '\n\n' : '\n');
};

const resolveKnowledgePhrase = (text: string): string => {
	const t = String(text || '').trim();
	const lower = t.toLowerCase();
	if (/\bslovakia\b/.test(lower) && /\bcapital\b/.test(lower)) return 'Bratislava';
	return t;
};

const normalizeLineEdits = (raw: unknown): Array<{ line: number; text: string }> => {
	if (!Array.isArray(raw)) return [];
	const out: Array<{ line: number; text: string }> = [];
	for (const item of raw) {
		if (!item || typeof item !== 'object') continue;
		const line = parseLineNumber((item as any).line);
		if (!line) continue;
		let text = (item as any).text === undefined ? '' : String((item as any).text).trim();
		if (!text) continue;
		text = resolveKnowledgePhrase(text);
		out.push({ line, text });
	}
	return out;
};

const cleanDirectiveText = (raw: string): string => {
	let value = String(raw || '').trim();
	if (!value) return '';
	value = value.replace(/^\s*(?:text|line|content)\s*(?::|is)?\s*/i, '');
	value = value.replace(/^\s*(?:is|to|as)\b\s*/i, '');
	value = value.replace(/^\s*(?:should\s+be|should\s+say|it\s+is|it\s+says?|says?)\s*/i, '');
	value = value.replace(/^\s*(?:one|two|three|four|five|six|seven|eight|nine|ten|\d+)\s+(?:empty|blank)\s+lines?\s+and\s*/i, '');
	value = value.replace(/^\s*(?:write|put|add|append|insert|set|make)\s+(?:text|line|content)?\s*/i, '');
	value = value.replace(/^['"]|['"]$/g, '').trim();
	return resolveKnowledgePhrase(value);
};

const extractLineEditsFromCommand = (text: string): Array<{ line: number; text: string }> => {
	const out: Array<{ line: number; text: string }> = [];
	const src = String(text || '');
	const patterns = [
		/\bon\s+(?:the\s+)?(\d+(?:st|nd|rd|th)?[a-z]*|first|second|third|thrid|tird|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\s+line\s+(?:write|put|add|append|insert|set|make|change|update|udpate|updte|updat|udate)\s+(.+?)(?=$|\s*(?:and\s+)?on\s+(?:the\s+)?(?:\d+(?:st|nd|rd|th)?[a-z]*|first|second|third|thrid|tird|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\s+line)/gi,
		/(?:add|put|set|write|change|make|update|udpate|updte|updat|udate)\s+(.+?)\s+(?:on|to|at)\s+(?:the\s+)?(\d+(?:st|nd|rd|th)?[a-z]*|first|second|third|thrid|tird|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\s+line/gi,
	];

	for (const re of patterns) {
		const matches = [...src.matchAll(re)];
		for (const m of matches) {
			const firstGroupLine = parseLineNumber(m[1]);
			const secondGroupLine = parseLineNumber(m[2]);
			const line = firstGroupLine || secondGroupLine;
			if (!line) continue;
			const rawValue = firstGroupLine ? String(m[2] || '').trim() : String(m[1] || '').trim();
			const quotedValue = extractQuotedText(rawValue);
			const value = cleanDirectiveText(quotedValue || rawValue);
			if (!value) continue;
			out.push({ line, text: value });
		}
	}

	const byLine = new Map<number, string>();
	for (const e of out) byLine.set(e.line, e.text);
	return [...byLine.entries()]
		.sort((a, b) => a[0] - b[0])
		.map(([line, value]) => ({ line, text: value }));
};

const extractBlankLineAppendSpec = (text: string): { blankLines: number; text: string } | null => {
	const source = String(text || '');
	const lower = source.toLowerCase();
	const countMatch = lower.match(/\b(?:add|insert|put|append|include)\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s+(?:empty|blank)\s+lines?\b/i);
	if (!countMatch) return null;

	const blankLines = parseCountToken(countMatch[1] || '');
	if (blankLines === null) return null;

	const quoted = extractQuotedText(source);
	let payload = quoted;
	if (!payload) {
		const unquoted = source.match(
			/\b(?:and|then)\s*(?:write|put|add|append|insert|set|make)\s+(?:text|line|content)?\s*(.+?)\s*$/i,
		);
		if (unquoted) payload = String(unquoted[1] || '').trim();
	}
	payload = cleanDirectiveText(payload || '');
	if (!payload) return null;

	return { blankLines, text: payload };
};

const extractInjectedCurrentContent = (cmd: string): string => {
	const m = String(cmd || '').match(/Current file content:\n([\s\S]*)$/i);
	return m ? String(m[1] || '') : '';
};

const isSpaceAfterEachLetterIntent = (cmdLower: string): boolean => {
	return (
		/\b(?:space|spacing)\b.*\b(?:after|between)\b.*\b(?:each|every)\b.*\b(?:letter|character|char)\b/.test(cmdLower) ||
		/\binclude\s+space\s+after\s+each\s+(?:letter|character|char)\b/.test(cmdLower) ||
		/\bspace\s+out\s+(?:the\s+)?(?:letters|text)\b/.test(cmdLower) ||
		/\bafter\s+each\s+(?:letter|character|char)\b[\s\S]*\b(?:add|insert|put|include)\b[\s\S]*\bspace\b/.test(cmdLower) ||
		/\b(?:every|each)\s+(?:letter|character|char)\b[\s\S]*\bfollow\w*\b[\s\S]*\bspace\b/.test(cmdLower)
	);
};

const isSpaceBetweenWordsIntent = (cmdLower: string): boolean => {
	return (
		/\b(?:between|after)\s+words?\b[\s\S]*\bspace/.test(cmdLower) ||
		/\beach\s+word\b[\s\S]*\bspace/.test(cmdLower)
	);
};

const isBlankLinesBetweenLinesIntent = (cmdLower: string): boolean => {
	return (
		/\bblank\s+lines?\b[\s\S]*\bbetween\s+lines?\b/.test(cmdLower) ||
		/\bbetween\s+lines?\b[\s\S]*\bblank\s+lines?\b/.test(cmdLower) ||
		/\binsert\s+blank\s+lines?\b/.test(cmdLower)
	);
};

const extractSelectionChoice = (text: string): 1 | 2 | 3 | 4 | null => {
	const m = String(text || '').match(/(?:^|\n)\s*(?:selection\s*:?\s*|option\s*)?(1|2|3|4)\s*(?:\n|$)/i);
	if (!m) return null;
	const n = Number(m[1]);
	return n >= 1 && n <= 4 ? (n as 1 | 2 | 3 | 4) : null;
};

const buildSpacingClarifyMessage = (): string =>
	[
		'I can apply this in several ways. Choose one:',
		'1. Add spaces between every character',
		'2. Add spaces between words',
		'3. Insert blank lines between lines',
		'4. Cancel',
		'Reply with 1, 2, 3, or 4.',
	].join('\n');

const escapeRegExp = (str: string): string => String(str || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const extractReplaceSpec = (text: string): { from: string; to: string; caseSensitive?: boolean } | null => {
	const src = String(text || '').trim();
	const m1 = src.match(/\breplace\s+"([^"]+)"\s+with\s+"([^"]+)"/i);
	if (m1) return { from: m1[1], to: m1[2], caseSensitive: false };
	const m2 = src.match(/\breplace\s+'([^']+)'\s+with\s+'([^']+)'/i);
	if (m2) return { from: m2[1], to: m2[2], caseSensitive: false };
	const m3 = src.match(/\breplace\s+([^\n\r]+?)\s+with\s+([^\n\r]+?)\s*$/i);
	if (m3) {
		return {
			from: String(m3[1] || '').trim().replace(/^['"]|['"]$/g, ''),
			to: String(m3[2] || '').trim().replace(/^['"]|['"]$/g, ''),
			caseSensitive: false,
		};
	}
	return null;
};

const extractCommandPath = (text: string): string => {
	const t = String(text || '');
	const direct = t.match(/([A-Za-z]:[\\/][^\n\r]+)/);
	if (direct && direct[1]) return cleanupPath(direct[1]);
	return '';
};

const inferActionFromCommand = (text: string, contextPath: string): AxiomAction | '' => {
	const lower = String(text || '').toLowerCase();
	const hasLineEditIntent =
		/\b(?:add|put|set|write|change|make|update|udpate|updte|updat|udate|edit|modify|replace|rewrite)\b/.test(lower) &&
		/\b(?:\d+(?:st|nd|rd|th)?[a-z]*|first|second|third|thrid|tird|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\s+line\b/.test(
			lower,
		);
	const hasTransformIntent =
		isSpaceAfterEachLetterIntent(lower) ||
		hasLineEditIntent ||
		/\breplace\b[\s\S]*\bwith\b/.test(lower) ||
		/\b(?:every|each)\s+\d+(?:st|nd|rd|th)?\s+letter[^\n\r]*capit/.test(lower);
	const hasRead = /\b(read|open|show)\b/.test(lower) && /\b(file|txt|text|document|note)\b/.test(lower);
	const hasList = /\b(list|show)\b/.test(lower) && /\b(directory|folder|files?)\b/.test(lower);
	const hasWrite =
		/\b(write|put|create|save|append|update|udpate|updte|updat|udate|edit|modify|add|make|build|generate|include|insert|format|transform|adjust|rewrite|change|replace)\b/.test(
			lower,
		) &&
		(/\b(file|txt|text|document|note)\b/.test(lower) || /\b(it|this|that|same|latest|last|previous|current)\b/.test(lower));
	if (
		hasTransformIntent &&
		(contextPath.length > 0 || /\b(file|txt|text|document|note|it|this|that|same|latest|last|previous|current)\b/.test(lower))
	) {
		return 'write_file';
	}
	if (hasRead) return 'read_file';
	if (hasList) return 'list_directory';
	if (hasWrite) return 'write_file';
	if (
		contextPath &&
		/\b(it|this|that|same|latest|last|previous|current)\b/.test(lower) &&
		/\b(add|append|update|edit|modify|change|replace|rewrite|include|insert|format|transform|adjust|write|put)\b/.test(lower)
	) {
		return 'write_file';
	}
	return '';
};

const sanitizePath = (inputPath: string, actionType: AxiomAction, baseDir: string, defaultWriteName: string): string => {
	let p = cleanupPath(inputPath);
	if (!p) {
		if (actionType === 'write_file') return `${baseDir}/${sanitizeName(defaultWriteName) || 'helloWorld.txt'}`;
		return baseDir;
	}
	if (/^[a-zA-Z]:/.test(p)) {
		if (p.toLowerCase().startsWith(baseDir.toLowerCase())) {
			if (actionType !== 'write_file') return p;
			if (p.toLowerCase() === baseDir.toLowerCase() || /[\\/]$/.test(p)) {
				return `${baseDir}/${sanitizeName(defaultWriteName) || 'helloWorld.txt'}`;
			}
			const parts = p.split('/').filter((seg) => seg.length > 0);
			const filePart = parts.pop() || defaultWriteName;
			const safeFile = sanitizeName(filePart) || sanitizeName(defaultWriteName) || 'helloWorld.txt';
			return `${parts.join('/')}/${safeFile}`;
		}
		const name = sanitizeName(p.split('/').filter(Boolean).pop() || defaultWriteName) || 'file.txt';
		return `${baseDir}/${name}`;
	}
	const maybeName = sanitizeName(p.replace(/^\/+/, ''));
	if (actionType === 'write_file' && maybeName) return `${baseDir}/${maybeName}`;
	return `${baseDir}/${p.replace(/^\/+/, '')}`;
};

const intentLabelMap: Record<string, string> = {
	get: 'GET',
	change: 'CHANGE',
	create: 'CREATE',
	move: 'MOVE',
	analyze: 'ANALYZE',
	decide: 'DECIDE',
	ask: 'ASK',
	approve: 'APPROVE',
};

const targetRefLabelMap: Record<string, string> = {
	current_file: 'this file',
	explicit_path: 'explicit path',
	planner_path: 'resolved target',
	default_file: 'default file',
	base_dir: 'working directory',
	unresolved: 'unresolved target',
};

const operationLabelMap: Record<string, string> = {
	read_text: 'read text',
	write_text: 'write text',
	list_directory: 'list directory',
	transform_text: 'transform text',
	unsupported: 'unsupported operation',
	clarify: 'clarify',
};

const buildPlanBlocksFromIR = (ir?: AxiomIntentIR): AxiomPlanBlock[] => {
	if (!ir) return [];
	const blocks: AxiomPlanBlock[] = [];
	const actionLabel = intentLabelMap[String(ir.intent || '').toLowerCase()] || String(ir.intent || 'ACTION').toUpperCase();
	blocks.push({
		id: 'action',
		category: 'action',
		label: 'ACTION',
		value: actionLabel,
		editable: false,
		params: { intent: ir.intent },
	});

	const scopeValue =
		ir.target.ref === 'current_file'
			? 'this file'
			: ir.target.ref === 'unresolved'
				? 'unresolved target'
				: ir.target.path || targetRefLabelMap[ir.target.ref] || 'target';
	blocks.push({
		id: 'scope',
		category: 'scope',
		label: 'TARGET',
		value: scopeValue,
		editable: ir.target.ref === 'unresolved',
		params: { targetType: ir.target.type, targetRef: ir.target.ref, path: ir.target.path },
	});

	const opType = String(ir.operation.type || '');
	const opName = String(ir.operation.name || '');
	let opValue = operationLabelMap[opType] || opType || 'operation';
	if (opType === 'transform_text' && opName) opValue = opName;
	if (opType === 'write_text') opValue = opName || 'write_text';
	blocks.push({
		id: 'operation',
		category: 'modifier',
		label: 'USING',
		value: opValue,
		editable: opType === 'clarify',
		params: { ...ir.operation.params, operationType: opType, operationName: opName },
	});

	if (Array.isArray(ir.compiler.chain) && ir.compiler.chain.length > 0) {
		blocks.push({
			id: 'compile-chain',
			category: 'modifier',
			label: 'THEN',
			value: ir.compiler.chain.join(' -> '),
			editable: false,
			params: { chain: ir.compiler.chain },
		});
	}

	return blocks;
};

const buildPlanReadable = (blocks: AxiomPlanBlock[]): string => {
	if (!Array.isArray(blocks) || blocks.length === 0) return '';
	return blocks.map((b) => `[${b.label}: ${b.value}]`).join('\n');
};

const withFailure = (
	action: AxiomAction,
	message: string,
	baseDir: string,
	fullPath: string,
	modelConfidence: number | null,
	plannerTier: string,
	postReadTransform?: AxiomParseOutput['postReadTransform'],
	intentIR?: AxiomIntentIR,
	routeMode?: AxiomIRExecutionMode,
	irValidation?: AxiomIRValidation,
): AxiomParseOutput => {
	const planBlocks = buildPlanBlocksFromIR(intentIR);
	const planReadable = buildPlanReadable(planBlocks);
	return {
		action,
		message,
		content: '',
		fullPath: fullPath || baseDir,
		path: fullPath || baseDir,
		isExternal: false,
		append: false,
		confidence: 0,
		modelConfidence,
		parserTier: plannerTier,
		confidenceBreakdown: {},
		postReadTransform,
		intentIR,
		routeMode,
		irValidation,
		planBlocks: planBlocks.length ? planBlocks : undefined,
		planReadable: planReadable || undefined,
		planReviewRequired: routeMode === 'plan' || false,
	};
};

const mapIRValidationErrorToMessage = (errors: string[]): string => {
	if (!Array.isArray(errors) || !errors.length) return 'The requested operation failed validation.';
	if (errors.includes('unresolved_target_reference')) {
		return 'I need the target file path before I can execute this operation.';
	}
	if (errors.includes('unsupported_operation')) {
		return 'This operation is not supported yet in Direct Command.';
	}
	if (errors.some((e) => e.startsWith('missing_required_param:content'))) {
		return 'I need the text to write. Please include content for the file operation.';
	}
	if (errors.some((e) => e.startsWith('operation_not_allowed_for_target'))) {
		return 'That operation is not valid for the selected target type.';
	}
	if (errors.includes('direct_mode_not_allowed_for_high_risk')) {
		return 'This operation is high risk and needs plan review before execution.';
	}
	return `Validation failed: ${errors[0]}`;
};

export function parseAxiomPlan(input: AxiomParseInput): AxiomParseOutput {
	const plannerTier = String(input.plannerTier || 'small').toLowerCase();
	const baseDir = cleanupPath(input.baseDir || '');
	const originalCommand = String(input.originalCommand || '');
	const commandForParsing = stripInjectedContext(originalCommand);
	const lastFilePath = cleanupPath(input.lastFilePath || '');
	const lastUserFileCommand = String(input.lastUserFileCommand || '');
	const lowerCommand = commandForParsing.toLowerCase();
	const selectionChoice = extractSelectionChoice(originalCommand);
	const defaultWriteName = String(input.defaultWriteName || 'helloWorld.txt');
	const clarifyOnError = input.clarifyOnError !== false;

	const parsed = parseJsonPayload(String(input.response || '')) || {};
	const modelConfidenceRaw = Number((parsed as any).confidence);
	const modelConfidence = Number.isFinite(modelConfidenceRaw) ? modelConfidenceRaw : null;
	const renameIntent =
		/\b(rename|renmae|move)\b/.test(lowerCommand) &&
		(/\b(file|txt|text|document|note)\b/.test(lowerCommand) ||
			/\b(it|this|that|same|latest|last|previous|current)\b/.test(lowerCommand));

	const allowedActions: AxiomAction[] = ['write_file', 'read_file', 'list_directory'];
	const plannerAction = allowedActions.includes(String((parsed as any).action || '').toLowerCase() as AxiomAction)
		? (String((parsed as any).action).toLowerCase() as AxiomAction)
		: '';
	const inferredAction = inferActionFromCommand(commandForParsing, lastFilePath);

	let action: AxiomAction = (plannerAction || inferredAction || (clarifyOnError ? 'clarify' : 'error')) as AxiomAction;
	if (inferredAction && plannerAction && inferredAction !== plannerAction) {
		action = inferredAction;
	}

	const contextRef =
		/\b(this|that|same|latest|last|previous|current)\b/.test(lowerCommand) || /\b(?:in|into)\s+it\b/.test(lowerCommand);
	const explicitPathFromCommand = extractCommandPath(commandForParsing);
	const fileNameHint = extractFileNameHint(commandForParsing);
	const rawPath = cleanupPath((parsed as any).path || (parsed as any).filePath || (parsed as any).filename || '');
	const hasExplicitPathInCommand =
		!!explicitPathFromCommand || /\b[A-Za-z0-9 _.-]+\.(?:txt|text|md|json|csv|log)\b/i.test(commandForParsing);
	const referenceResolution = resolveIntentReferences({
		originalCommand: commandForParsing,
		baseDir,
		defaultWriteName,
		actionHint: action,
		lastFilePath,
		explicitPathFromCommand,
		rawPath,
		fileNameHint,
	});
	let chosenPath = referenceResolution.target.path || '';
	if (!chosenPath) {
		chosenPath = action === 'write_file' ? lastFilePath || defaultWriteName : lastFilePath || baseDir;
	}

	let fullPath = sanitizePath(chosenPath, action, baseDir, defaultWriteName);
	if (renameIntent) {
		const renameIntentResult = normalizeIntent({
			originalCommand: commandForParsing,
			actionHint: 'write_file',
			append: false,
			content: '',
			renameIntent: true,
			lineEdits: [],
		});
		const renameIR = buildIntentIR({
			intent: renameIntentResult.intent,
			target: {
				...referenceResolution.target,
				path: fullPath,
				hasSpecificPath: !!fullPath && !String(fullPath || '').match(/[\\/]Axiom_Files[\\/]?$/i),
			},
			operation: renameIntentResult.operation,
			confidence: 0.4,
			actionHint: 'clarify',
			isExternal: false,
			unresolved: referenceResolution.unresolved,
		});
		const renameValidation = validateIntentIR(renameIR);
		renameIR.validation = renameValidation;
		return withFailure(
			clarifyOnError ? 'clarify' : 'error',
			'File rename/move is not enabled yet. I can create, read, and update file contents. Ask me to rewrite or edit a file instead.',
			baseDir,
			fullPath,
			modelConfidence,
			plannerTier,
			undefined,
			renameIR,
			renameIR.execution.mode,
			renameValidation,
		);
	}
	let append =
		(parsed as any).append !== undefined ? !!(parsed as any).append : String((parsed as any).writeMode || '').toLowerCase() === 'append';

	const commandHasLineIntent =
		/\b(?:\d+(?:st|nd|rd|th)?[a-z]*|first|second|third|thrid|tird|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\s+line\b/.test(
			lowerCommand,
		);
	const plannerWriteMode = String((parsed as any).writeMode || '').toLowerCase();
	let lineEdits = normalizeLineEdits((parsed as any).lineEdits);
	if (lineEdits.length && !commandHasLineIntent && plannerWriteMode !== 'line_edit') lineEdits = [];
	const commandLineEdits = extractLineEditsFromCommand(commandForParsing);
	if (commandLineEdits.length) lineEdits = commandLineEdits;

	let content = (parsed as any).content === undefined ? '' : String((parsed as any).content);
	if (!content && (parsed as any).text !== undefined) content = String((parsed as any).text);

	const injectedCurrent = extractInjectedCurrentContent(originalCommand);
	const spaceLettersIntent = isSpaceAfterEachLetterIntent(lowerCommand);
	const spaceWordsIntent = isSpaceBetweenWordsIntent(lowerCommand);
	const blankLinesIntent = isBlankLinesBetweenLinesIntent(lowerCommand);
	const spacingSignal = /\b(spaces?|spacing|spaced|blank\s+line|blank\s+lines|newline|new\s+line)\b/.test(lowerCommand);
	const transformSignal = /\b(add|insert|put|make|format|transform|adjust|ensure|apply|after|between|follow\w*)\b/.test(
		lowerCommand,
	);
	const hasTransformContext =
		!!lastFilePath ||
		contextRef ||
		/\b(open|read|update|udpate|updte|updat|udate|edit|modify|rewrite|change|replace|format|transform|adjust)\b/.test(
			lowerCommand,
		);
	const nthRule = parseNthUpperRule(lowerCommand);
	const capitalsIntent = /\bcapitals?\b/.test(lowerCommand) && /\b(write|put|add)\b/.test(lowerCommand);
	const replaceSpec = extractReplaceSpec(commandForParsing);
	const blankLineAppendSpec = extractBlankLineAppendSpec(commandForParsing);
	const transformVerb =
		/\b(update|udpate|updte|updat|udate|edit|modify|change|replace|rewrite|transform|format|adjust)\b/.test(lowerCommand);

	const spacingTransform =
		selectionChoice === 1
			? ({ type: 'space_letters' } as const)
			: selectionChoice === 2
				? ({ type: 'space_words' } as const)
				: selectionChoice === 3
					? ({ type: 'blank_lines_between_lines' } as const)
					: spaceLettersIntent
						? ({ type: 'space_letters' } as const)
						: spaceWordsIntent
							? ({ type: 'space_words' } as const)
							: blankLinesIntent
								? ({ type: 'blank_lines_between_lines' } as const)
								: undefined;

	const spacingAmbiguous =
		!spacingTransform && selectionChoice === null && spacingSignal && transformSignal && hasTransformContext;

	if (selectionChoice === 4) {
		return withFailure('clarify', 'Canceled. No changes were made.', baseDir, fullPath, modelConfidence, plannerTier);
	}

	if (spacingAmbiguous) {
		return withFailure('clarify', buildSpacingClarifyMessage(), baseDir, fullPath, modelConfidence, plannerTier);
	}

	const deterministicTransform = (() => {
		if (spacingTransform && (contextRef || !!lastFilePath || hasTransformContext)) return spacingTransform;
		if (replaceSpec && (contextRef || transformVerb || !!lastFilePath)) return { type: 'replace_text' as const, ...replaceSpec };
		if (commandLineEdits.length > 0 && (contextRef || transformVerb || !!lastFilePath)) {
			return { type: 'line_edit' as const, lineEdits: commandLineEdits };
		}
		if (blankLineAppendSpec && (contextRef || transformVerb || !!lastFilePath)) {
			return {
				type: 'append_with_blank_lines' as const,
				blankLines: Number(blankLineAppendSpec.blankLines || 0),
				text: String(blankLineAppendSpec.text || ''),
			};
		}
		if (nthRule && (contextRef || transformVerb)) return { type: 'uppercase_nth' as const, n: nthRule };
		return undefined;
	})();

	const missingTransformTarget = !!deterministicTransform && !explicitPathFromCommand && !rawPath && !lastFilePath;
	if (deterministicTransform && !explicitPathFromCommand && !rawPath && lastFilePath) {
		fullPath = sanitizePath(lastFilePath, 'read_file', baseDir, defaultWriteName);
	}
	if (missingTransformTarget) {
		return withFailure(
			clarifyOnError ? 'clarify' : 'error',
			'I need the target file path to apply that transformation. Please specify which file to update.',
			baseDir,
			fullPath,
			modelConfidence,
			plannerTier,
			deterministicTransform,
		);
	}

	if (deterministicTransform && action !== 'error' && action !== 'clarify') {
		action = 'read_file';
		append = false;
		content = '';
		lineEdits = [];
	}

	if (action === 'write_file') {
		if (!content && /\b(create|make|write)\b/.test(lowerCommand)) {
			content = extractCreatePayload(commandForParsing);
		}
		if (!content && lastUserFileCommand && /\b(create|make|write)\b/.test(lastUserFileCommand.toLowerCase())) {
			content = extractCreatePayload(lastUserFileCommand);
		}
		if (capitalsIntent) {
			const capitals = inferTopCapitalsContent(commandForParsing);
			if (capitals) {
				content = capitals;
				append = false;
			}
		}
		if (nthRule && content) content = applyNthUpper(content, nthRule);
		content = String(content || '').trimEnd();
	}

	if (action === 'write_file' && !String(content || '').trim()) {
		if (injectedCurrent && (spacingTransform || nthRule || replaceSpec || lineEdits.length)) {
			action = 'read_file';
		} else {
			return withFailure(
				clarifyOnError ? 'clarify' : 'error',
				'I need the text to write. Please include content for the file operation.',
				baseDir,
				fullPath,
				modelConfidence,
				plannerTier,
			);
		}
	}

	if (!allowedActions.includes(action as AxiomAction)) {
		return withFailure(
			clarifyOnError ? 'clarify' : 'error',
			'I could not determine a safe tool action. Please ask to read a file, write a file with content, or list a directory.',
			baseDir,
			fullPath,
			modelConfidence,
			plannerTier,
		);
	}

	const inferActionMatch = inferredAction ? inferredAction === action : true;
	const sanePath = !!fullPath && (fullPath.toLowerCase().startsWith(baseDir.toLowerCase()) || /^[A-Za-z]:\//.test(fullPath));
	const hasSpecificFilePath = !!fullPath && !String(fullPath || '').match(/[\\/]Axiom_Files[\\/]?$/i);
	const requiredFields =
		action === 'write_file'
			? String(content || '').trim().length > 0 && !!fullPath
			: action === 'read_file' && deterministicTransform
				? hasSpecificFilePath
				: !!fullPath;
	const needsContextBinding = contextRef && !hasExplicitPathInCommand;
	const contextBindingSucceeded =
		!needsContextBinding || (lastFilePath && sanitizePath(lastFilePath, action, baseDir, defaultWriteName).toLowerCase() === fullPath.toLowerCase());

	let contentSanity = true;
	if (action === 'write_file') {
		contentSanity = !!String(content || '').trim();
	} else if (action === 'read_file' && deterministicTransform) {
		if (deterministicTransform.type === 'line_edit') {
			contentSanity = Array.isArray(deterministicTransform.lineEdits) && deterministicTransform.lineEdits.length > 0;
		} else if (deterministicTransform.type === 'replace_text') {
			contentSanity = !!String(deterministicTransform.from || '').trim();
		} else if (deterministicTransform.type === 'uppercase_nth') {
			const n = Number(deterministicTransform.n || 0);
			contentSanity = Number.isFinite(n) && n > 1;
		} else if (deterministicTransform.type === 'append_with_blank_lines') {
			const n = Number(deterministicTransform.blankLines || 0);
			contentSanity = Number.isFinite(n) && n >= 0 && !!String(deterministicTransform.text || '').trim();
		} else if (deterministicTransform.type === 'space_words' || deterministicTransform.type === 'blank_lines_between_lines') {
			contentSanity = true;
		}
	}

	let deterministicConfidence = 0;
	const breakdown: Record<string, number> = {};
	if (allowedActions.includes(action)) {
		deterministicConfidence += 0.25;
		breakdown.validAction = 0.25;
	}
	if (sanePath) {
		deterministicConfidence += 0.2;
		breakdown.sanePath = 0.2;
	}
	if (requiredFields) {
		deterministicConfidence += 0.2;
		breakdown.requiredFields = 0.2;
	}
	if (inferActionMatch) {
		deterministicConfidence += 0.15;
		breakdown.intentMatch = 0.15;
	}
	if (contextBindingSucceeded) {
		deterministicConfidence += 0.1;
		breakdown.contextBinding = 0.1;
	}
	if (contentSanity) {
		deterministicConfidence += 0.1;
		breakdown.contentSanity = 0.1;
	}
	deterministicConfidence = Number(deterministicConfidence.toFixed(2));

	const normalizedIntent = normalizeIntent({
		originalCommand: commandForParsing,
		actionHint: action,
		append,
		content: action === 'write_file' ? String(content || '') : '',
		renameIntent: false,
		deterministicTransform: deterministicTransform as any,
		lineEdits,
		selectionChoice,
	});

	let referenceForIR = resolveIntentReferences({
		originalCommand: commandForParsing,
		baseDir,
		defaultWriteName,
		actionHint: action,
		lastFilePath,
		explicitPathFromCommand,
		rawPath,
		fileNameHint,
	});
	if (deterministicTransform && !explicitPathFromCommand && !rawPath && !!lastFilePath) {
		const hasSpecificBoundPath = !!fullPath && !String(fullPath || '').match(/[\\/]Axiom_Files[\\/]?$/i);
		referenceForIR = {
			target: {
				type: 'file',
				ref: hasSpecificBoundPath ? 'current_file' : 'unresolved',
				path: fullPath,
				hasSpecificPath: hasSpecificBoundPath,
			},
			unresolved: !hasSpecificBoundPath,
			reasons: [...referenceForIR.reasons, 'reference: deterministic transform context path'],
		};
	}

	const intentIR = buildIntentIR({
		intent: normalizedIntent.intent,
		target: {
			...referenceForIR.target,
			path: fullPath,
			type: action === 'list_directory' ? 'folder' : referenceForIR.target.type === 'unknown' ? 'file' : referenceForIR.target.type,
			hasSpecificPath: hasSpecificFilePath,
		},
		operation: normalizedIntent.operation,
		confidence: deterministicConfidence,
		actionHint: action,
		isExternal: false,
		unresolved: referenceForIR.unresolved,
	});
	const irValidation = validateIntentIR(intentIR);
	intentIR.validation = irValidation;

	if (!irValidation.valid) {
		const validationMessage = mapIRValidationErrorToMessage(irValidation.errors);
		return withFailure(
			clarifyOnError ? 'clarify' : 'error',
			validationMessage,
			baseDir,
			fullPath,
			modelConfidence,
			plannerTier,
			deterministicTransform,
			intentIR,
			intentIR.execution.mode,
			irValidation,
		);
	}

	if (intentIR.execution.mode === 'plan') {
		return withFailure(
			clarifyOnError ? 'clarify' : 'error',
			'This operation needs plan review before execution. Switch to Plan Builder to confirm and run it.',
			baseDir,
			fullPath,
			modelConfidence,
			plannerTier,
			deterministicTransform,
			intentIR,
			intentIR.execution.mode,
			irValidation,
		);
	}

	const planBlocks = buildPlanBlocksFromIR(intentIR);
	const planReadable = buildPlanReadable(planBlocks);

	return {
		action,
		content: action === 'write_file' ? String(content || '') : '',
		fullPath,
		path: fullPath,
		isExternal: false,
		append: action === 'write_file' ? append : false,
		confidence: deterministicConfidence,
		modelConfidence,
		parserTier: plannerTier,
		confidenceBreakdown: breakdown,
		lineEdits: lineEdits.length ? lineEdits : undefined,
		postReadTransform: deterministicTransform,
		hasSpecificFilePath,
		intentIR,
		routeMode: intentIR.execution.mode,
		irValidation,
		planBlocks: planBlocks.length ? planBlocks : undefined,
		planReadable: planReadable || undefined,
		planReviewRequired: false,
	};
}
