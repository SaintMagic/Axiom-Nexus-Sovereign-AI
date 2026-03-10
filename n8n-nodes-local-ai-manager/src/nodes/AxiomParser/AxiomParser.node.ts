import {
	IDataObject,
	IExecuteFunctions,
	INodeExecutionData,
	INodeType,
	INodeTypeDescription,
	NodeOperationError,
} from 'n8n-workflow';

import { parseAxiomPlan } from '../../lib/axiomParser';

export class AxiomParser implements INodeType {
	description: INodeTypeDescription = {
		displayName: 'Axiom Parser',
		name: 'axiomParser',
		icon: 'file:robot.svg',
		group: ['transform'],
		version: 1,
		description: 'Normalize planner output into deterministic, executable file actions',
		defaults: {
			name: 'Axiom Parser',
		},
		inputs: ['main'],
		outputs: ['main'],
		properties: [
			{
				displayName: 'Response Field',
				name: 'responseField',
				type: 'string',
				default: 'response',
				description: 'JSON field containing the raw planner/model response text',
			},
			{
				displayName: 'Planner Tier Field',
				name: 'plannerTierField',
				type: 'string',
				default: 'plannerTier',
				description: 'JSON field containing planner tier metadata',
			},
			{
				displayName: 'Original Command',
				name: 'originalCommand',
				type: 'string',
				default: '={{ $node["Extract Input"].json.content || "" }}',
				description: 'Original user command (supports expressions)',
			},
			{
				displayName: 'Last File Path',
				name: 'lastFilePath',
				type: 'string',
				default: '={{ $node["Extract Input"].json.lastFilePath || "" }}',
				description: 'Most recent bound file path (supports expressions)',
			},
			{
				displayName: 'Last User File Command',
				name: 'lastUserFileCommand',
				type: 'string',
				default: '={{ $node["Extract Input"].json.lastUserFileCommand || "" }}',
				description: 'Previous user file command for contextual normalization',
			},
			{
				displayName: 'Pending Clarify',
				name: 'pendingClarify',
				type: 'boolean',
				default: '={{ $node["Extract Input"].json.pendingClarify === true }}',
				description: 'Whether there is an unresolved clarification choice awaiting user selection',
			},
			{
				displayName: 'Base Directory',
				name: 'baseDir',
				type: 'string',
				default: '={{ $env.AXIOM_BASE_DIR || "C:/Users/Martin/.n8n-files/Axiom_Files" }}',
				description: 'Root working directory for relative file operations',
			},
			{
				displayName: 'Default File Name',
				name: 'defaultWriteName',
				type: 'string',
				default: 'helloWorld.txt',
				description: 'Fallback file name when a write action has no explicit path',
			},
			{
				displayName: 'Clarify On Error',
				name: 'clarifyOnError',
				type: 'boolean',
				default: true,
				description: 'Return clarification prompts for ambiguous requests instead of terminal parser errors',
			},
		],
	};

	async execute(this: IExecuteFunctions): Promise<INodeExecutionData[][]> {
		const items = this.getInputData();
		const out: INodeExecutionData[] = [];

		for (let i = 0; i < items.length; i++) {
			try {
				const responseField = String(this.getNodeParameter('responseField', i));
				const plannerTierField = String(this.getNodeParameter('plannerTierField', i));
				const originalCommand = String(this.getNodeParameter('originalCommand', i));
				const lastFilePath = String(this.getNodeParameter('lastFilePath', i));
				const lastUserFileCommand = String(this.getNodeParameter('lastUserFileCommand', i));
				const pendingClarify = !!this.getNodeParameter('pendingClarify', i);
				const baseDir = String(this.getNodeParameter('baseDir', i));
				const defaultWriteName = String(this.getNodeParameter('defaultWriteName', i));
				const clarifyOnError = !!this.getNodeParameter('clarifyOnError', i);

				const itemJson = (items[i].json || {}) as IDataObject;
				const response = String(itemJson[responseField] || '');
				const plannerTier = String(itemJson[plannerTierField] || 'small');

				const parsed = parseAxiomPlan({
					baseDir,
					response,
					originalCommand,
					lastFilePath,
					lastUserFileCommand,
					pendingClarify,
					plannerTier,
					defaultWriteName,
					clarifyOnError,
				});

				out.push({ json: parsed as unknown as IDataObject });
			} catch (error) {
				if (this.continueOnFail()) {
					out.push({ json: { action: 'error', message: (error as any)?.message || 'Parser failed' } });
				} else {
					throw new NodeOperationError(this.getNode(), error as Error, { itemIndex: i });
				}
			}
		}

		return [out];
	}
}
