import {
    IExecuteFunctions,
    INodeExecutionData,
    INodeType,
    INodeTypeDescription,
    NodeOperationError,
} from 'n8n-workflow';
import { buildCatalogGuidance } from '../../lib/axiomCatalog';

declare const __dirname: string;

export class LocalAiManager implements INodeType {
    description: INodeTypeDescription = {
        displayName: 'Local AI Manager',
        name: 'localAiManager',
        icon: 'file:robot.svg',
        group: ['transform'],
        version: 1,
        description: 'Sends queries to a local or remote Ollama instance',
        defaults: {
            name: 'Local AI Manager',
        },
        inputs: ['main'],
        outputs: ['main'],
        properties: [
            {
                displayName: 'Connection Type',
                name: 'connectionType',
                type: 'options',
                options: [
                    {
                        name: 'Local',
                        value: 'local',
                        description: 'Use the default local Ollama URL (http://localhost:11434)',
                    },
                    {
                        name: 'Remote / Custom URL',
                        value: 'remote',
                        description: 'Provide a custom Base URL or IP address',
                    },
                ],
                default: 'local',
                description: 'Whether to use localhost or a custom remote URL',
            },
            {
                displayName: 'Base URL',
                name: 'baseUrl',
                type: 'string',
                default: 'http://',
                required: true,
                displayOptions: {
                    show: {
                        connectionType: ['remote'],
                    },
                },
                description: 'The exact base URL for the remote Ollama server (e.g., http://192.168.1.100:11434)',
            },
            {
                displayName: 'Model Name',
                name: 'modelName',
                type: 'string',
                default: 'llama3.2',
                required: true,
                description: 'The name of the Ollama model to use',
            },
            {
                displayName: 'System Directive',
                name: 'systemDirective',
                type: 'string',
                typeOptions: {
                    rows: 4,
                },
                default: 'You are a helpful AI assistant.',
                description: 'System instructions for the model',
            },
            {
                displayName: 'User Input',
                name: 'userInput',
                type: 'string',
                typeOptions: {
                    rows: 4,
                },
                default: '',
                required: true,
                description: 'The query to send to the model',
            },
        ],
    };

    async execute(this: IExecuteFunctions): Promise<INodeExecutionData[][]> {
        const items = this.getInputData();
        const returnData: INodeExecutionData[] = [];

        for (let i = 0; i < items.length; i++) {
            try {
                const connectionType = this.getNodeParameter('connectionType', i) as string;
                let baseUrl = 'http://127.0.0.1:11434';
                const requestFn =
                    (this.helpers as any).httpRequest?.bind(this.helpers) ??
                    (this.helpers as any).request?.bind(this.helpers);

                if (!requestFn) {
                    throw new NodeOperationError(
                        this.getNode(),
                        new Error('No HTTP helper available (expected this.helpers.httpRequest or this.helpers.request).'),
                        { itemIndex: i },
                    );
                }

                if (connectionType === 'remote') {
                    baseUrl = this.getNodeParameter('baseUrl', i) as string;
                }

                // Ensure no trailing slash
                if (baseUrl.endsWith('/')) {
                    baseUrl = baseUrl.slice(0, -1);
                }

                const modelName = this.getNodeParameter('modelName', i) as string;
                const systemDirective = this.getNodeParameter('systemDirective', i) as string;
                const userInput = this.getNodeParameter('userInput', i) as string;
                const pingTimeoutMs = 5000;
                const generateTimeoutMs = 120000;

                // 1. Connection Test: Ping /api/tags
                try {
                    const pingOptions = {
                        method: 'GET' as any,
                        url: `${baseUrl}/api/tags`,
                        uri: `${baseUrl}/api/tags`,
                        timeout: pingTimeoutMs,
                        json: true,
                    };

                    try {
                        await requestFn(pingOptions);
                    } catch (primaryPingError) {
                        // Some Windows/network stacks resolve localhost differently; retry with 127.0.0.1
                        if (baseUrl.includes('localhost')) {
                            const fallbackBaseUrl = baseUrl.replace('localhost', '127.0.0.1');
                            await requestFn({
                                method: 'GET' as any,
                                url: `${fallbackBaseUrl}/api/tags`,
                                uri: `${fallbackBaseUrl}/api/tags`,
                                timeout: pingTimeoutMs,
                                json: true,
                            });
                            baseUrl = fallbackBaseUrl;
                        } else {
                            throw primaryPingError;
                        }
                    }
                } catch (pingError) {
                    const detail = (pingError as any)?.message ? ` Details: ${(pingError as any).message}` : '';
                    throw new NodeOperationError(
                        this.getNode(),
                        new Error(`Ollama not found at ${baseUrl}. Connection test failed.${detail}`),
                        { itemIndex: i }
                    );
                }

                // 2. Perform execution
                const isCommandMode = systemDirective.toLowerCase().includes('planning brain');
                const catalogGuidance = isCommandMode ? buildCatalogGuidance(__dirname) : '';
                const effectiveSystemDirective =
                    isCommandMode && catalogGuidance
                        ? `${systemDirective}\n\n${catalogGuidance}`
                        : systemDirective;

                const generateOptions = {
                    method: 'POST' as any,
                    url: `${baseUrl}/api/chat`,
                    uri: `${baseUrl}/api/chat`,
                    body: {
                        model: modelName,
                        messages: [
                            { role: 'system', content: effectiveSystemDirective },
                            { role: 'user', content: userInput }
                        ],
                        stream: false,
                    } as any,
                    timeout: generateTimeoutMs,
                    json: true,
                };

                if (isCommandMode) {
                    generateOptions.body.tools = [
                        {
                            type: 'function',
                            function: {
                                name: 'execute_axiom_action',
                                description: 'Executes a deterministic filesystem or system action.',
                                parameters: {
                                    type: 'object',
                                    properties: {
                                        action: { type: 'string', enum: ['write_file', 'read_file', 'list_directory', 'create_empty_file', 'delete_file', 'clarify'] },
                                        path: { type: 'string', description: 'Absolute file or directory path.' },
                                        content: { type: 'string', description: 'File content if writing explicit text.' },
                                        writeMode: { type: 'string', enum: ['overwrite', 'append', 'line_edit'] }
                                    },
                                    required: ['action', 'path']
                                }
                            }
                        }
                    ];
                    // Mandated strict schema options
                    generateOptions.body.options = {
                        parallel_tool_calls: false
                    };
                }

                const responseData = await requestFn(generateOptions);

                // Map the /api/chat response back to the legacy { response: "..." } format expected by Axiom Router
                let normalizedResponse = '';
                if (responseData.message?.tool_calls && responseData.message.tool_calls.length > 0) {
                    // Extract the strict JSON arguments from the explicit tool call
                    normalizedResponse = JSON.stringify(responseData.message.tool_calls[0].function.arguments);
                } else if (responseData.message?.content) {
                    normalizedResponse = responseData.message.content;
                }

                returnData.push({
                    json: { ...responseData, response: normalizedResponse },
                });

            } catch (error) {
                if (this.continueOnFail()) {
                    returnData.push({ json: { error: (error as any).message } });
                } else {
                    throw new NodeOperationError(this.getNode(), error as Error, { itemIndex: i });
                }
            }
        }

        return [returnData];
    }
}
