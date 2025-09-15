#!/bin/bash

# Generate Dockerfile with custom PORT argument
# Usage: ./generate-dockerfile.sh [version] [port]

set -e

VERSION="${1:-v0.9.0}"
PORT="${2:-9090}"

echo "📥 Fetching Dockerfile from all-smi ${VERSION}..."

# Fetch and modify Dockerfile in one step
curl -sf "https://raw.githubusercontent.com/inureyes/all-smi/${VERSION}/Dockerfile" | \
sed \
    -e "1i# Auto-generated Dockerfile for Algalon\\n# Based on all-smi ${VERSION} with port ${PORT}\\n# Generated: $(date)\\n" \
    -e "s/EXPOSE 9090/EXPOSE ${PORT}/" \
    -e "s/--port\", \"9090/--port\", \"${PORT}/" \
    > Dockerfile

if [[ $? -eq 0 && -s Dockerfile ]]; then
    echo "✅ Generated Dockerfile with port ${PORT}"
else
    echo "❌ Failed to generate Dockerfile"
    exit 1
fi