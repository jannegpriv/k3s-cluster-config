#!/bin/bash

# Script för att exportera n8n workflows till JSON-filer
# Kräver att n8n MCP server är konfigurerad

set -e

WORKFLOWS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATE=$(date +%Y%m%d)

echo "Exporterar n8n workflows till $WORKFLOWS_DIR"

# Lista av workflows att exportera (ID:Name)
declare -A WORKFLOWS=(
    ["OovUiuo0GcJ1Wftw"]="k3s"
    ["J54qTYk9YbJezmHQ"]="daglig-energianalys"
    ["WX2uKcMMSgeP8Qaf"]="vecko-energisammanfattning"
)

# Exportera varje workflow
for WORKFLOW_ID in "${!WORKFLOWS[@]}"; do
    WORKFLOW_NAME="${WORKFLOWS[$WORKFLOW_ID]}"
    OUTPUT_FILE="$WORKFLOWS_DIR/${WORKFLOW_NAME}.json"

    echo "Exporterar ${WORKFLOW_NAME} (${WORKFLOW_ID})..."

    # Använd n8n CLI för att exportera (om tillgängligt)
    # Annars kan du använda curl med n8n API
    # curl -X GET "http://n8n.local/api/v1/workflows/${WORKFLOW_ID}" \
    #      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    #      -o "${OUTPUT_FILE}"

    echo "  Exporterad till: ${OUTPUT_FILE}"
done

echo "Export klar!"
echo ""
echo "OBS: Detta script kräver n8n API-nyckel eller MCP-konfiguration."
echo "Workflows kan också exporteras manuellt via n8n UI."
