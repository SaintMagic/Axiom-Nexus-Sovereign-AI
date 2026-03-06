#!/bin/bash
echo "Installing N8N AI Manager Dependencies for Linux..."

# 1. Install Node.js
if command -v apt &> /dev/null; then
    echo "1/4 Installing Node.js via APT..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
elif command -v dnf &> /dev/null; then
    echo "1/4 Installing Node.js via DNF..."
    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
    sudo dnf install -y nodejs
else
    echo "Unsupported distribution. Please install Node.js manually."
fi

# 2. Install Ollama
echo "2/4 Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

# 3. Install n8n globally
echo "3/4 Installing N8N globally..."
sudo npm install -g n8n

# 4. Install Custom Node
echo "4/4 Installing Local AI Manager Custom Node..."
CUSTOM_DIR="$HOME/.n8n/custom"
mkdir -p "$CUSTOM_DIR"
cd "$CUSTOM_DIR"

if [ ! -f "package.json" ]; then
    npm init -y
fi

PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NODE_TGZ="$PROJECT_ROOT/n8n-nodes-local-ai-manager/n8n-nodes-local-ai-manager-0.1.0.tgz"

if [ -f "$NODE_TGZ" ]; then
    npm install "$NODE_TGZ"
    echo "Custom node installed successfully!"
else
    echo "WARNING: Custom node .tgz not found at $NODE_TGZ. Please build it first."
fi

echo "5/5 Pre-loading llama3.2 model..."
ollama run llama3.2 &

echo "Done! You can now run 'n8n start' to begin your automated workflows."
