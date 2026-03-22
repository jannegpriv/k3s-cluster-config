#!/bin/bash

# Script for exporting n8n workflows to JSON files for version control.
# Requires N8N_API_KEY environment variable or n8n-secrets in k8s.
# Usage: ./export-workflows.sh

set -e

WORKFLOWS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Exporterar n8n workflows till $WORKFLOWS_DIR"

# Get API key from environment or k8s secret
if [ -z "$N8N_API_KEY" ]; then
    N8N_API_KEY=$(kubectl get secret -n n8n n8n-secrets -o jsonpath='{.data.N8N_API_KEY}' 2>/dev/null | base64 -d 2>/dev/null || true)
fi

if [ -z "$N8N_API_KEY" ]; then
    echo "ERROR: N8N_API_KEY not set and could not read from k8s secret"
    echo "Set N8N_API_KEY environment variable or ensure kubectl access"
    exit 1
fi

N8N_URL="${N8N_URL:-http://n8n.local}"

# Workflows to export (ID -> filename)
declare -A WORKFLOWS=(
    ["OovUiuo0GcJ1Wftw"]="k3s"
    ["J54qTYk9YbJezmHQ"]="daglig-energianalys"
    ["WX2uKcMMSgeP8Qaf"]="vecko-energisammanfattning"
)

for WORKFLOW_ID in "${!WORKFLOWS[@]}"; do
    WORKFLOW_NAME="${WORKFLOWS[$WORKFLOW_ID]}"
    OUTPUT_FILE="$WORKFLOWS_DIR/${WORKFLOW_NAME}.json"

    echo "Exporterar ${WORKFLOW_NAME} (${WORKFLOW_ID})..."

    # Fetch workflow and extract only the relevant fields (name, nodes, connections, settings)
    curl -s "${N8N_URL}/api/v1/workflows/${WORKFLOW_ID}" \
         -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
         | python3 -c "
import json, sys
w = json.load(sys.stdin)
clean = {k: w[k] for k in ('name', 'nodes', 'connections', 'settings') if k in w}
print(json.dumps(clean, indent=2, ensure_ascii=False))
" > "${OUTPUT_FILE}"

    echo "  -> ${OUTPUT_FILE}"
done

echo ""
echo "Export klar! Glom inte att committa andringarna."
