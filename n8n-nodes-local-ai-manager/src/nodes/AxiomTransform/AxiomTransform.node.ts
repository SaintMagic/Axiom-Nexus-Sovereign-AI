import {
	IDataObject,
	IExecuteFunctions,
	INodeExecutionData,
	INodeType,
	INodeTypeDescription,
	NodeOperationError,
} from 'n8n-workflow';

import { applyDeterministicTransform, TransformPlan } from '../../lib/axiomTransform';

const parseTransformPlan = (value: unknown): TransformPlan | undefined => {
	if (value && typeof value === 'object' && 'type' in (value as Record<string, unknown>)) {
		return value as TransformPlan;
	}
	if (typeof value !== 'string') return undefined;
	const text = value.trim();
	if (!text) return undefined;
	try {
		const parsed = JSON.parse(text) as unknown;
		if (parsed && typeof parsed === 'object' && 'type' in (parsed as Record<string, unknown>)) {
			return parsed as TransformPlan;
		}
	} catch {
		// Ignore malformed fallback JSON and continue with direct plan resolution.
	}
	return undefined;
};

export class AxiomTransform implements INodeType {
	description: INodeTypeDescription = {
		displayName: 'Axiom Transform',
		name: 'axiomTransform',
		icon: 'file:robot.svg',
		group: ['transform'],
		version: 1,
		description: 'Apply deterministic text transforms to file content after read',
		defaults: {
			name: 'Axiom Transform',
		},
		inputs: ['main'],
		outputs: ['main'],
		properties: [
			{
				displayName: 'Transform Field',
				name: 'transformField',
				type: 'string',
				default: 'postReadTransform',
				description: 'JSON field containing the deterministic transform plan',
			},
			{
				displayName: 'Full Path Field',
				name: 'fullPathField',
				type: 'string',
				default: 'fullPath',
				description: 'JSON field containing the resolved destination file path',
			},
			{
				displayName: 'Fallback Transform JSON',
				name: 'fallbackTransformJson',
				type: 'string',
				default:
					'={{ $node["Parse JSON"].json.postReadTransform ? JSON.stringify($node["Parse JSON"].json.postReadTransform) : "" }}',
				description: 'Optional fallback transform plan when the incoming item does not carry one',
			},
			{
				displayName: 'Fallback Full Path',
				name: 'fallbackFullPath',
				type: 'string',
				default: '={{ $node["Parse JSON"].json.fullPath || $node["Parse JSON"].json.path || "" }}',
				description: 'Optional fallback full path when the incoming item does not include one',
			},
			{
				displayName: 'Source Binary Property',
				name: 'sourceBinaryProperty',
				type: 'string',
				default: 'data',
				description: 'Binary property to read current file content from',
			},
			{
				displayName: 'Fallback Text Field',
				name: 'fallbackTextField',
				type: 'string',
				default: 'data',
				description: 'JSON text field fallback if no binary payload exists',
			},
		],
	};

	async execute(this: IExecuteFunctions): Promise<INodeExecutionData[][]> {
		const items = this.getInputData();
		const out: INodeExecutionData[] = [];

		for (let i = 0; i < items.length; i++) {
			try {
				const transformField = String(this.getNodeParameter('transformField', i));
				const fullPathField = String(this.getNodeParameter('fullPathField', i));
				const fallbackTransformJson = String(this.getNodeParameter('fallbackTransformJson', i, ''));
				const fallbackFullPath = String(this.getNodeParameter('fallbackFullPath', i, ''));
				const sourceBinaryProperty = String(this.getNodeParameter('sourceBinaryProperty', i));
				const fallbackTextField = String(this.getNodeParameter('fallbackTextField', i));

				const itemJson = (items[i].json || {}) as IDataObject;
				const transform =
					parseTransformPlan(itemJson[transformField]) ||
					parseTransformPlan(itemJson.postReadTransform) ||
					parseTransformPlan(fallbackTransformJson);
				const fullPath = String(
					itemJson[fullPathField] || itemJson.fullPath || itemJson.path || fallbackFullPath || '',
				).replace(/\\/g, '/');

				if (!transform || !transform.type) {
					out.push({
						json: {
							action: 'error',
							fullPath,
							path: fullPath,
							message: 'No deterministic transform plan available.',
						},
					});
					continue;
				}

				let inputText = '';
				try {
					const buffer = await this.helpers.getBinaryDataBuffer(i, sourceBinaryProperty);
					inputText = buffer.toString('utf8');
				} catch {
					inputText = '';
				}

				if (!inputText && typeof itemJson[fallbackTextField] === 'string') {
					inputText = String(itemJson[fallbackTextField] || '');
				}

				if (!inputText.length) {
					out.push({
						json: {
							action: 'error',
							fullPath,
							path: fullPath,
							message: `Could not load file content for transform at ${fullPath || 'target file'}.`,
							postReadTransform: transform,
						},
					});
					continue;
				}

				const transformed = applyDeterministicTransform({
					plan: transform,
					content: inputText,
				});

				if (!transformed.ok) {
					out.push({
						json: {
							action: 'error',
							fullPath,
							path: fullPath,
							message: transformed.message || 'Deterministic transform failed.',
							postReadTransform: transform,
						},
					});
					continue;
				}

				out.push({
					json: {
						...itemJson,
						action: 'write_file',
						fullPath,
						path: fullPath,
						content: String(transformed.content || ''),
						append: false,
						postReadTransform: transform,
						postReadTransformApplied: true,
					},
				});
			} catch (error) {
				if (this.continueOnFail()) {
					out.push({ json: { action: 'error', message: (error as any)?.message || 'Transform failed' } });
				} else {
					throw new NodeOperationError(this.getNode(), error as Error, { itemIndex: i });
				}
			}
		}

		return [out];
	}
}
