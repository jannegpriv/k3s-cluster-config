#!/bin/bash

set -euo pipefail

NAMESPACE="monitoring"
RULE_NAME="k3s-alert-rules"
PROMETHEUS_POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')
RULE_PATH="clusters/production/apps/monitoring/k3s-alert-rules.yaml"

echo "✅ Steg 1: Tar bort eventuell gammal PrometheusRule..."
kubectl delete prometheusrule -n $NAMESPACE $RULE_NAME || true

echo "🕐 Väntar på att filen ska försvinna från Prometheus (kan ta några sekunder)..."
sleep 5

echo "✅ Steg 2: Startar om Prometheus Operator..."
kubectl rollout restart deployment -n $NAMESPACE kube-prometheus-stack-operator
sleep 10

echo "✅ Steg 3: Startar om Prometheus..."
kubectl rollout restart statefulset -n $NAMESPACE prometheus-kube-prometheus-stack-prometheus
sleep 20

echo "✅ Steg 4: Återskapar korrekt PrometheusRule från Git/YAML..."
kubectl apply -f "$RULE_PATH"

echo "🕵️ Steg 5: Verifierar att rätt uttryck är på plats..."
PROMETHEUS_POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n $NAMESPACE "$PROMETHEUS_POD" -- \
  grep -A 5 'alert: K3sServiceDown' /etc/prometheus/rules/prometheus-kube-prometheus-stack-prometheus-rulefiles-0/*.yaml \
  | grep expr

