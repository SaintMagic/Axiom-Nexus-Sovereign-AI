export type AxiomIRIntent = 'get' | 'change' | 'create' | 'move' | 'analyze' | 'decide' | 'ask' | 'approve';

export type AxiomIRTargetType = 'file' | 'folder' | 'clipboard' | 'selected_text' | 'project' | 'search_results' | 'unknown';

export type AxiomIRTargetRef = 'explicit_path' | 'current_file' | 'planner_path' | 'default_file' | 'base_dir' | 'unresolved';

export type AxiomIRExecutionMode = 'direct' | 'plan' | 'clarify';

export type AxiomIRRisk = 'low' | 'medium' | 'high';

export interface AxiomIRTarget {
	type: AxiomIRTargetType;
	ref: AxiomIRTargetRef;
	path: string;
	hasSpecificPath: boolean;
}

export interface AxiomIROperation {
	type:
		| 'read_text'
		| 'write_text'
		| 'list_directory'
		| 'transform_text'
		| 'delete_file'
		| 'move_file'
		| 'unsupported'
		| 'clarify';
	name: string;
	params: Record<string, unknown>;
}

export interface AxiomIRExecution {
	mode: AxiomIRExecutionMode;
	risk: AxiomIRRisk;
	reasons: string[];
}

export interface AxiomIRValidation {
	valid: boolean;
	errors: string[];
	warnings: string[];
}

export interface AxiomIntentIR {
	intent: AxiomIRIntent;
	target: AxiomIRTarget;
	operation: AxiomIROperation;
	execution: AxiomIRExecution;
	compiler: {
		chain: string[];
	};
	validation: AxiomIRValidation;
}

export interface ResolveReferencesInput {
	originalCommand: string;
	baseDir: string;
	defaultWriteName: string;
	actionHint: string;
	lastFilePath?: string;
	explicitPathFromCommand?: string;
	rawPath?: string;
	fileNameHint?: string;
}

export interface ResolveReferencesResult {
	target: AxiomIRTarget;
	unresolved: boolean;
	reasons: string[];
}

export const resolveIntentReferences = (input: ResolveReferencesInput): ResolveReferencesResult => {
	const originalCommand = String(input.originalCommand || '');
	const lower = originalCommand.toLowerCase();
	const baseDir = String(input.baseDir || '').replace(/\\/g, '/');
	const defaultWriteName = String(input.defaultWriteName || 'helloWorld.txt');
	const actionHint = String(input.actionHint || '');
	const lastFilePath = String(input.lastFilePath || '').replace(/\\/g, '/');
	const explicitPathFromCommand = String(input.explicitPathFromCommand || '').replace(/\\/g, '/');
	const rawPath = String(input.rawPath || '').replace(/\\/g, '/');
	const fileNameHint = String(input.fileNameHint || '').replace(/\\/g, '/');
	const commandFileMentionQuoted =
		originalCommand.match(/["'`]([^"'`]+\.(?:txt|text|md|json|csv|log))["'`]/i)?.[1] || '';
	const commandFileMentionBare =
		originalCommand.match(/(?:^|\s)([A-Za-z0-9_.-]+\.(?:txt|text|md|json|csv|log))(?=$|\s|[.,;:!?])/i)?.[1] || '';
	const commandFileMention = String(commandFileMentionQuoted || commandFileMentionBare || '')
		.replace(/^["'`]+|["'`]+$/g, '')
		.trim();

	const namingItPhrase = /\b(?:name|named|call(?:ed)?)\s+it\b/.test(lower);
	const createWithExplicitName =
		/\b(?:create|make|build|generate|new)\b/.test(lower) &&
		(/\b(?:name\s+it|named|called|filename|file\s+name)\b/.test(lower) || !!fileNameHint);
	const contextRef =
		(/\b(it|this|that|same|latest|last|previous|current)\b/.test(lower) || /\b(?:in|into)\s+it\b/.test(lower)) &&
		!(namingItPhrase && createWithExplicitName);

	let ref: AxiomIRTargetRef = 'base_dir';
	let path = baseDir;
	const reasons: string[] = [];

	if (explicitPathFromCommand) {
		ref = 'explicit_path';
		path = explicitPathFromCommand;
		reasons.push('reference: explicit path in user command');
	} else if (rawPath) {
		ref = 'planner_path';
		path = rawPath;
		reasons.push('reference: planner path');
	} else if (commandFileMention) {
		ref = 'explicit_path';
		path = `${baseDir}/${commandFileMention}`;
		reasons.push('reference: filename mention in user command');
	} else if (contextRef && lastFilePath) {
		ref = 'current_file';
		path = lastFilePath;
		reasons.push('reference: context-bound previous file');
	} else if ((actionHint === 'write_file' || actionHint === 'read_file' || actionHint === 'delete_file' || actionHint === 'move_file') && fileNameHint) {
		ref = 'default_file';
		path = `${baseDir}/${fileNameHint}`;
		reasons.push('reference: filename hint in command');
	} else if (actionHint === 'write_file') {
		ref = 'default_file';
		path = `${baseDir}/${defaultWriteName}`;
		reasons.push('reference: default write target');
	}

	const isFolder = actionHint === 'list_directory' || /[\\/]$/.test(path) || path.toLowerCase() === baseDir.toLowerCase();
	const targetType: AxiomIRTargetType = isFolder ? 'folder' : 'file';
	const hasSpecificPath = !!path && !/[\\/]Axiom_Files[\\/]?$/i.test(path);
	const unresolved = (actionHint === 'read_file' || actionHint === 'write_file' || actionHint === 'delete_file' || actionHint === 'move_file') && !hasSpecificPath;

	return {
		target: {
			type: unresolved ? 'unknown' : targetType,
			ref: unresolved ? 'unresolved' : ref,
			path,
			hasSpecificPath,
		},
		unresolved,
		reasons,
	};
};

export interface NormalizeIntentInput {
	originalCommand: string;
	actionHint: string;
	append: boolean;
	content: string;
	isCreateFileWithoutPayload?: boolean;
	moveTargetPath?: string;
	renameIntent: boolean;
	deterministicTransform?: { type: string;[k: string]: unknown };
	lineEdits?: Array<{ line: number; text: string }>;
	selectionChoice?: number | null;
}

export interface NormalizeIntentResult {
	intent: AxiomIRIntent;
	operation: AxiomIROperation;
	reasons: string[];
}

export const normalizeIntent = (input: NormalizeIntentInput): NormalizeIntentResult => {
	const lower = String(input.originalCommand || '').toLowerCase();
	const actionHint = String(input.actionHint || '');
	const content = String(input.content || '');
	const lineEdits = Array.isArray(input.lineEdits) ? input.lineEdits : [];
	const transform = input.deterministicTransform;
	const reasons: string[] = [];

	if (input.renameIntent) {
		reasons.push('intent: move (rename) requested');
		return {
			intent: 'move',
			operation: { type: 'unsupported', name: 'rename_file', params: {} },
			reasons,
		};
	}

	if (actionHint === 'list_directory') {
		reasons.push('intent: retrieve directory listing');
		return {
			intent: 'get',
			operation: { type: 'list_directory', name: 'list_directory', params: {} },
			reasons,
		};
	}

	if (actionHint === 'read_file' && transform && transform.type) {
		reasons.push('intent: change via deterministic transform');
		return {
			intent: 'change',
			operation: {
				type: 'transform_text',
				name: String(transform.type),
				params: { ...transform },
			},
			reasons,
		};
	}

	if (actionHint === 'read_file') {
		reasons.push('intent: read file');
		return {
			intent: 'get',
			operation: { type: 'read_text', name: 'read_text', params: {} },
			reasons,
		};
	}

	if (actionHint === 'delete_file') {
		reasons.push('intent: delete file');
		return {
			intent: 'change',
			operation: { type: 'delete_file', name: 'delete_file', params: {} },
			reasons,
		};
	}

	if (actionHint === 'move_file') {
		reasons.push('intent: move/rename file');
		return {
			intent: 'move',
			operation: {
				type: 'move_file',
				name: 'move_file',
				params: {
					toPath: String(input.moveTargetPath || ''),
				},
			},
			reasons,
		};
	}

	if (input.actionHint === 'write_file') {
		const isCreate = /\b(create|make|new)\b/.test(lower) && !/\b(update|edit|modify|replace|rewrite|append)\b/.test(lower);
		const intent: AxiomIRIntent = isCreate ? 'create' : 'change';

		if (lineEdits.length > 0) {
			reasons.push('intent: change via line edits');
			return {
				intent: 'change',
				operation: { type: 'transform_text', name: 'line_edit', params: { lineEdits } },
				reasons,
			};
		}

		const params: Record<string, unknown> = { content };
		if (input.append) params.append = true;
		if (input.isCreateFileWithoutPayload) params.isCreateFileWithoutPayload = true;

		reasons.push(isCreate ? 'intent: create file' : 'intent: change file content');
		return {
			intent,
			operation: {
				type: 'write_text',
				name: input.append ? 'append_text' : 'overwrite_text',
				params,
			},
			reasons,
		};
	}

	if (input.selectionChoice !== null && input.selectionChoice !== undefined) {
		reasons.push('intent: follow-up choice selection');
		return {
			intent: 'decide',
			operation: { type: 'clarify', name: 'selection', params: { choice: input.selectionChoice } },
			reasons,
		};
	}

	reasons.push('intent: unresolved');
	return {
		intent: 'ask',
		operation: { type: 'clarify', name: 'clarify', params: {} },
		reasons,
	};
};

export interface BuildIRInput {
	intent: AxiomIRIntent;
	target: AxiomIRTarget;
	operation: AxiomIROperation;
	confidence: number;
	actionHint: string;
	isExternal: boolean;
	unresolved: boolean;
}

export const buildIntentIR = (input: BuildIRInput): AxiomIntentIR => {
	const reasons: string[] = [];
	let risk: AxiomIRRisk = 'low';
	let mode: AxiomIRExecutionMode = 'direct';

	if (input.operation.type === 'unsupported' || input.unresolved || input.intent === 'ask') {
		risk = 'high';
		mode = 'clarify';
		reasons.push('unresolved or unsupported operation');
	} else if (input.isExternal) {
		risk = 'high';
		mode = 'plan';
		reasons.push('external target');
	} else if (
		input.operation.type === 'transform_text' ||
		input.operation.type === 'write_text' ||
		input.operation.type === 'delete_file' ||
		input.operation.type === 'move_file'
	) {
		risk = 'medium';
		reasons.push('content-changing operation');
	}

	if (input.confidence < 0.55) {
		mode = 'clarify';
		reasons.push('low confidence');
	} else if (input.confidence < 0.8 && mode === 'direct') {
		mode = 'plan';
		reasons.push('medium confidence');
	}

	const chain: string[] =
		input.operation.type === 'read_text'
			? ['read_file']
			: input.operation.type === 'list_directory'
				? ['list_directory']
				: input.operation.type === 'write_text'
					? ['write_file']
					: input.operation.type === 'transform_text'
						? ['read_file', 'transform_text', 'write_file']
						: input.operation.type === 'delete_file'
							? ['delete_file']
							: input.operation.type === 'move_file'
								? ['move_file']
						: [];

	return {
		intent: input.intent,
		target: input.target,
		operation: input.operation,
		execution: {
			mode,
			risk,
			reasons,
		},
		compiler: {
			chain,
		},
		validation: {
			valid: true,
			errors: [],
			warnings: [],
		},
	};
};

export const validateIntentIR = (ir: AxiomIntentIR): AxiomIRValidation => {
	const errors: string[] = [];
	const warnings: string[] = [];

	if (!ir.target.path) errors.push('missing_target_path');
	if (ir.target.ref === 'unresolved') errors.push('unresolved_target_reference');
	if (ir.operation.type === 'unsupported') errors.push('unsupported_operation');

	const allowedByTarget: Record<AxiomIRTargetType, Set<string>> = {
		file: new Set(['read_text', 'write_text', 'transform_text', 'delete_file', 'move_file']),
		folder: new Set(['list_directory']),
		clipboard: new Set(['read_text', 'write_text', 'transform_text']),
		selected_text: new Set(['read_text', 'write_text', 'transform_text']),
		project: new Set(['list_directory']),
		search_results: new Set(['read_text']),
		unknown: new Set<string>(),
	};

	if (!allowedByTarget[ir.target.type].has(ir.operation.type)) {
		errors.push(`operation_not_allowed_for_target:${ir.operation.type}:${ir.target.type}`);
	}

	if (ir.operation.type === 'write_text') {
		const content = String((ir.operation.params || {}).content || '');
		const allowEmpty = (ir.operation.params as any)?.isCreateFileWithoutPayload === true;
		if (!content.trim() && !allowEmpty) errors.push('missing_required_param:content');
	}

	if (ir.operation.type === 'transform_text') {
		const name = String(ir.operation.name || '');
		if (!name) errors.push('missing_transform_name');
		if (name === 'line_edit') {
			const edits = (ir.operation.params || {}).lineEdits as Array<unknown>;
			if (!Array.isArray(edits) || edits.length === 0) errors.push('missing_required_param:lineEdits');
		}
	}

	if (ir.operation.type === 'move_file') {
		const toPath = String((ir.operation.params || {}).toPath || '');
		if (!toPath.trim()) errors.push('missing_required_param:toPath');
	}

	if (ir.execution.mode === 'direct' && ir.execution.risk === 'high') {
		errors.push('direct_mode_not_allowed_for_high_risk');
	}

	if (ir.execution.mode === 'plan' && ir.execution.risk === 'low') {
		warnings.push('plan_mode_may_be_unnecessary');
	}

	return {
		valid: errors.length === 0,
		errors,
		warnings,
	};
};
