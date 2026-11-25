#!/bin/sh
# Metadata and all nine pod logs archived before cleanup, 2026-11-25.
# Only terminal failed Jobs; never volumes, snapshots, CronJobs or alert rules.
set -eu
export KUBECONFIG="$HOME/.kube/config"
proof=analytics-collect-features-29927407
ok=$(kubectl -n openhab-analytics get job "$proof" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')
[ "$ok" = True ] || { echo 'Successful replacement proof required' >&2; exit 1; }
image=$(kubectl -n openhab-analytics get job "$proof" -o jsonpath='{.spec.template.spec.containers[0].image}')
[ "$image" = ghcr.io/jannegpriv/openhab-analytics-collector@sha256:6e46e85b74cad09d5341b3af9e26fa26484a7c38638ea5cf34c5233de0b14277 ] || exit 1
for pair in \
  analytics-collect-features-29926237:f41984af-d585-456a-801b-c224d339a188 \
  analytics-collect-features-29926252:5a3ff9e7-1238-4e64-bd9a-ef5c64758c53 \
  analytics-collect-features-29926267:65ae0f3c-85e8-42ba-95e5-41755a47805b
do
  name=${pair%%:*}; expected=${pair#*:}
  uid=$(kubectl -n openhab-analytics get job "$name" --ignore-not-found -o jsonpath='{.metadata.uid}')
  [ -n "$uid" ] || continue
  [ "$uid" = "$expected" ] || { echo 'Unexpected Job UID' >&2; exit 1; }
  failed=$(kubectl -n openhab-analytics get job "$name" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}')
  [ "$failed" = True ] || { echo 'Job is not terminal Failed' >&2; exit 1; }
  kubectl -n openhab-analytics delete job "$name" --wait=true
done
