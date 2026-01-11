# K3s Workflow - Dokumentation

## Översikt

K3s workflowet övervakar klustrets hälsa och rapporterar status till Mattermost kanalen `k3s-cluster`.

## Funktioner

1. **CPU-användning** - Hämtar CPU-användning per nod från Prometheus
2. **Minnesanvändning** - Hämtar minnesanvändning per nod från Prometheus
3. **Aktiva Alerts** - Hämtar aktiva varningar från Alertmanager
4. **Kubernetes Events** - Hämtar icke-normala events från Kubernetes API (NYTT 2026-01-11)
5. **AI-analys** - Claude AI analyserar data och ger svensk sammanfattning

## Triggers

- **Webhook**: `http://n8n.local/webhook/cluster-status`
- **Mattermost Outgoing Webhook**: Triggas av `@k3s` eller `!status` i k3s-cluster kanalen
- **Schedule**: Daglig schemalagd körning (konfigureras i workflow)

## Kubernetes Events Integration

### ServiceAccount & RBAC

För att kunna hämta Kubernetes events har vi skapat:

```yaml
# ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: n8n
  namespace: n8n

# ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: n8n-events-reader
rules:
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]

# ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: n8n-events-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: n8n-events-reader
subjects:
- kind: ServiceAccount
  name: n8n
  namespace: n8n
```

### Credential Configuration

I n8n måste en **Header Auth** credential skapas:
- **Name**: `Authorization`
- **Value**: `Bearer <ServiceAccount-token>`

Token hämtas från Secret `n8n-token` i namespace `n8n`:
```bash
kubectl get secret n8n-token -n n8n -o jsonpath='{.data.token}' | base64 -d
```

## Workflow Noder

1. **WH Get K3s status** - Webhook trigger
2. **Schedule Trigger K3s status** - Tidsbaserad trigger
3. **Get K3s CPU usage** - HTTP Request till Prometheus
4. **Get K3s memory usage** - HTTP Request till Prometheus
5. **Get K3s active alerts** - HTTP Request till Alertmanager
6. **Get K3s Events** - HTTP Request till Kubernetes API (NY)
7. **Format data** - Code node som formaterar all data till rapport
8. **AI Agent** - Claude AI analyserar rapporten
9. **Result to k3s-cluster** - Postar resultatet till Mattermost

## AI Prompt

AI-agenten är konfigurerad att:
- Ge övergripande hälsostatus (bra/varning/kritisk)
- Identifiera problem med CPU, minne, alerts OCH events
- Prioritera kritiska events (CrashLoopBackOff, certifikat-varningar etc)
- Jämföra med tidigare rapporter
- Ge rekommendationer på svenska

## Underhåll

### Uppdatera ServiceAccount Token

Om ServiceAccount token behöver förnyas:
```bash
kubectl delete secret n8n-token -n n8n
kubectl apply -f clusters/production/apps/n8n/serviceaccount-token.yaml
```

Hämta ny token och uppdatera credential i n8n.

### Exportera Workflow

Via n8n UI: Workflow → Settings → Download

Eller använd MCP API för automatisk export.

## Changelog

### 2026-01-11
- Lade till Kubernetes events-monitoring
- Skapade ServiceAccount med RBAC för events-läsning
- Uppdaterade AI-prompt för att analysera events
- Lade till filtrering av icke-normala events (top 10 senaste)
