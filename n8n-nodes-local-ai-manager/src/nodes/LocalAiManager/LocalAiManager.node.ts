import {
    IExecuteFunctions,
    INodeExecutionData,
    INodeType,
    INodeTypeDescription,
    NodeOperationError,
} from 'n8n-workflow';

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
                const generateOptions = {
                    method: 'POST' as any,
                    url: `${baseUrl}/api/generate`,
                    uri: `${baseUrl}/api/generate`,
                    body: {
                        model: modelName,
                        prompt: userInput,
                        system: systemDirective,
                        stream: false,
                    },
                    timeout: generateTimeoutMs,
                    json: true,
                };

                const responseData = await requestFn(generateOptions);

                returnData.push({
                    json: responseData,
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
