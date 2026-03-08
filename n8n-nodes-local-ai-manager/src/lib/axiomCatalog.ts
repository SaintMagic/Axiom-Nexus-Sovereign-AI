type CatalogEntry = {
	name?: string;
	category?: string;
	description?: string;
	when_to_use?: string[];
	inputs?: Record<string, string>;
	required_inputs?: string[];
	forbidden_cases?: string[];
	deterministic?: boolean;
	risk?: string;
	tags?: string[];
	implementation?: string;
	enabled?: boolean;
	experimental?: boolean;
	version?: string;
};

type CatalogFile = {
	version?: string;
	functions?: CatalogEntry[];
};

declare const require: any;
declare const process: any;

const DEFAULT_CATALOG_RELATIVE_PATH = '../../catalog/functions.json';

const asString = (value: unknown): string => (value === undefined || value === null ? '' : String(value));
const asBoolean = (value: unknown, fallback = false): boolean =>
	typeof value === 'boolean' ? value : fallback;

const asStringArray = (value: unknown): string[] => {
	if (!Array.isArray(value)) return [];
	return value.map((v) => asString(v).trim()).filter((v) => !!v);
};

const asInputKeys = (value: unknown): string[] => {
	if (!value || typeof value !== 'object') return [];
	return Object.keys(value as Record<string, unknown>).filter((k) => !!k);
};

const loadJsonFile = (absolutePath: string): CatalogFile | null => {
	try {
		const fs = require('fs');
		if (!fs.existsSync(absolutePath)) return null;
		const raw = String(fs.readFileSync(absolutePath, 'utf8') || '');
		if (!raw.trim()) return null;
		const parsed = JSON.parse(raw);
		if (!parsed || typeof parsed !== 'object') return null;
		return parsed as CatalogFile;
	} catch {
		return null;
	}
};

const resolveCatalogPath = (callerDir: string): string => {
	const path = require('path');
	const envPath = asString(process.env.AXIOM_FUNCTION_CATALOG || '').trim();
	if (envPath) return envPath;
	return path.resolve(callerDir, DEFAULT_CATALOG_RELATIVE_PATH);
};

const isExperimentalEnabled = (): boolean => {
	const raw = asString(process.env.AXIOM_ENABLE_EXPERIMENTAL || '').trim().toLowerCase();
	return raw === '1' || raw === 'true' || raw === 'yes' || raw === 'on';
};

const normalizeEntry = (entry: CatalogEntry): CatalogEntry => ({
	...entry,
	enabled: entry.enabled !== false,
	experimental: asBoolean(entry.experimental, false),
	version: asString(entry.version || '1.0').trim() || '1.0',
});

const getCatalogEntries = (callerDir: string): CatalogEntry[] => {
	const catalogPath = resolveCatalogPath(callerDir);
	const catalog = loadJsonFile(catalogPath);
	if (!catalog || !Array.isArray(catalog.functions)) return [];
	return catalog.functions.map((fn) => normalizeEntry(fn || {}));
};

const findCatalogFunction = (callerDir: string, functionName: string): CatalogEntry | null => {
	const target = asString(functionName).trim();
	if (!target) return null;
	const entries = getCatalogEntries(callerDir);
	for (const fn of entries) {
		if (asString(fn.name).trim() === target) return fn;
	}
	return null;
};

export const getFunctionAvailability = (
	callerDir: string,
	functionName: string,
): { available: boolean; reason: string } => {
	const fn = findCatalogFunction(callerDir, functionName);
	if (!fn) return { available: true, reason: '' };

	if (fn.enabled === false) {
		return { available: false, reason: `Function "${functionName}" is currently disabled in catalog.` };
	}
	if (fn.experimental && !isExperimentalEnabled()) {
		return { available: false, reason: `Function "${functionName}" is experimental and currently disabled.` };
	}
	return { available: true, reason: '' };
};

export const buildCatalogGuidance = (callerDir: string): string => {
	const entries = getCatalogEntries(callerDir);
	if (!entries.length) return '';
	const includeExperimental = isExperimentalEnabled();

	const lines: string[] = [];
	lines.push('FUNCTION_CATALOG (summary)');
	lines.push('Use only listed functions. If required inputs are missing or forbidden cases apply, return action=\"clarify\".');
	lines.push(
		includeExperimental
			? 'Experimental functions are enabled for this runtime.'
			: 'Experimental functions are disabled for this runtime.',
	);

	for (const fn of entries) {
		const name = asString(fn.name).trim();
		if (!name) continue;
		const enabled = fn.enabled !== false;
		const experimental = asBoolean(fn.experimental, false);
		if (!enabled) continue;
		if (experimental && !includeExperimental) continue;

		const description = asString(fn.description).trim();
		const whenToUse = asStringArray(fn.when_to_use);
		const requiredInputs = asStringArray(fn.required_inputs);
		const inputKeys = asInputKeys(fn.inputs);
		const forbidden = asStringArray(fn.forbidden_cases);
		const tags = asStringArray(fn.tags);
		const deterministic = fn.deterministic === true ? 'true' : 'false';
		const risk = asString(fn.risk).trim() || 'unknown';
		const implementation = asString(fn.implementation).trim();
		const version = asString(fn.version || '1.0').trim() || '1.0';

		lines.push(`- ${name}: ${description || 'No description.'}`);
		if (whenToUse.length) lines.push(`  when_to_use: ${whenToUse.join(' | ')}`);
		if (requiredInputs.length) lines.push(`  required_inputs: ${requiredInputs.join(', ')}`);
		if (!requiredInputs.length && inputKeys.length) lines.push(`  inputs: ${inputKeys.join(', ')}`);
		if (forbidden.length) lines.push(`  forbidden_cases: ${forbidden.join(' | ')}`);
		if (tags.length) lines.push(`  tags: ${tags.join(', ')}`);
		lines.push(`  deterministic: ${deterministic}; risk: ${risk}; version: ${version}; experimental: ${experimental ? 'true' : 'false'}`);
		if (implementation) lines.push(`  spec: ${implementation}`);
	}

	lines.push('Do not invent tools or fields outside this catalog.');
	return lines.join('\n');
};
