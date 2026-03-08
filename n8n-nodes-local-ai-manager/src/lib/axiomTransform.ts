export type TransformPlan =
	| { type: 'space_letters' }
	| { type: 'space_words' }
	| { type: 'words_to_lines' }
	| { type: 'blank_lines_between_lines' }
	| { type: 'append_with_blank_lines'; blankLines: number; text: string }
	| { type: 'uppercase_nth'; n: number }
	| { type: 'replace_text'; from: string; to: string; caseSensitive?: boolean }
	| { type: 'line_edit'; lineEdits: Array<{ line: number; text: string }> }
	| { type: 'remove_line'; lines: number[] };

export interface TransformInput {
	plan: TransformPlan;
	content: string;
}

export interface TransformResult {
	ok: boolean;
	content?: string;
	message?: string;
}

const spaceOutLetters = (txt: string): string => {
	const lines = String(txt || '').split(/\r?\n/);
	return lines
		.map((line) => {
			let out = '';
			for (const ch of line) {
				if (ch === ' ') out += '  ';
				else out += `${ch} `;
			}
			return out.trimEnd();
		})
		.join('\n');
};

const spaceOutWords = (txt: string): string => {
	const lines = String(txt || '').split(/\r?\n/);
	return lines
		.map((line) => {
			const words = String(line || '')
				.trim()
				.split(/\s+/)
				.filter((w) => w.length > 0);
			return words.join('  ');
		})
		.join('\n');
};

const insertBlankLinesBetweenLines = (txt: string): string => {
	const lines = String(txt || '').split(/\r?\n/);
	return lines.join('\n\n');
};

const wordsToLines = (txt: string): string => {
	const words = String(txt || '')
		.split(/\s+/)
		.map((w) => w.trim())
		.filter((w) => w.length > 0);
	return words.join('\n');
};

const appendWithBlankLines = (txt: string, blankLines: number, appendText: string): string => {
	const source = String(txt || '').replace(/\r/g, '');
	const payload = String(appendText || '');
	const n = Math.max(0, Math.floor(Number(blankLines || 0)));
	if (!payload.length) return source;

	if (!source.length) {
		return `${'\n'.repeat(n)}${payload}`;
	}

	const base = source.replace(/\n+$/g, '');
	return `${base}${'\n'.repeat(n + 1)}${payload}`;
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

const applyLineEdits = (existingContent: string, edits: Array<{ line: number; text: string }>): string => {
	let lines = String(existingContent || '').split(/\r?\n/);
	if (lines.length === 1 && lines[0] === '') lines = [];
	const maxLine = Math.max(...edits.map((e) => Number(e.line || 0)));
	while (lines.length < maxLine) lines.push('');
	for (const e of edits) {
		const line = Number(e.line || 0);
		if (line >= 1) lines[line - 1] = String(e.text || '');
	}
	return lines.join('\n');
};

const removeLines = (existingContent: string, linesToRemove: number[]): string => {
	let lines = String(existingContent || '').split(/\r?\n/);
	if (lines.length === 1 && lines[0] === '') lines = [];
	const removeSet = new Set(
		(Array.isArray(linesToRemove) ? linesToRemove : [])
			.map((n) => Number(n))
			.filter((n) => Number.isFinite(n) && n >= 1),
	);
	if (!removeSet.size) return lines.join('\n');
	return lines.filter((_, idx) => !removeSet.has(idx + 1)).join('\n');
};

const escapeRegExp = (str: string): string => String(str || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const applyReplace = (text: string, spec: { from: string; to: string; caseSensitive?: boolean }): string => {
	const re = new RegExp(escapeRegExp(spec.from), spec.caseSensitive ? 'g' : 'gi');
	return String(text || '').replace(re, String(spec.to || ''));
};

export function applyDeterministicTransform(input: TransformInput): TransformResult {
	const { plan, content } = input;
	if (!plan || !plan.type) return { ok: false, message: 'No deterministic transform plan available.' };

	if (plan.type === 'space_letters') {
		return { ok: true, content: spaceOutLetters(content) };
	}

	if (plan.type === 'space_words') {
		return { ok: true, content: spaceOutWords(content) };
	}

	if (plan.type === 'words_to_lines') {
		return { ok: true, content: wordsToLines(content) };
	}

	if (plan.type === 'blank_lines_between_lines') {
		return { ok: true, content: insertBlankLinesBetweenLines(content) };
	}

	if (plan.type === 'append_with_blank_lines') {
		const n = Number(plan.blankLines || 0);
		if (!Number.isFinite(n) || n < 0) {
			return { ok: false, message: 'Invalid append_with_blank_lines blankLines value.' };
		}
		if (!String(plan.text || '').length) {
			return { ok: false, message: 'append_with_blank_lines requires text to append.' };
		}
		return { ok: true, content: appendWithBlankLines(content, n, plan.text) };
	}

	if (plan.type === 'uppercase_nth') {
		const n = Number(plan.n || 0);
		if (!Number.isFinite(n) || n <= 1) {
			return { ok: false, message: 'Invalid uppercase_nth transform parameter.' };
		}
		return { ok: true, content: applyNthUpper(content, n) };
	}

	if (plan.type === 'replace_text') {
		if (!String(plan.from || '').length) {
			return { ok: false, message: 'Invalid replace_text source value.' };
		}
		return { ok: true, content: applyReplace(content, plan) };
	}

	if (plan.type === 'line_edit') {
		const edits = Array.isArray(plan.lineEdits) ? plan.lineEdits : [];
		if (!edits.length) {
			return { ok: false, message: 'line_edit requires at least one line edit.' };
		}
		return { ok: true, content: applyLineEdits(content, edits) };
	}

	if (plan.type === 'remove_line') {
		const lines = Array.isArray(plan.lines) ? plan.lines : [];
		if (!lines.length) {
			return { ok: false, message: 'remove_line requires at least one line index.' };
		}
		return { ok: true, content: removeLines(content, lines) };
	}

	return { ok: false, message: `Unsupported transform type: ${(plan as any).type || 'unknown'}` };
}
