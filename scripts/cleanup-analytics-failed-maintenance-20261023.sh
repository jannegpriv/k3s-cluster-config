#!/bin/sh
# Archived metadata/logs and successful replacement proof precede this cleanup.
# Run on the k3s master. Removes only one terminal failed Job, never PVCs/data.
set -eu
name=analytics-maintenance-29878605
uid=$(sudo k3s kubectl -n openhab-analytics get job "$name" --ignore-not-found -o jsonpath='{.metadata.uid}')
[ -n "$uid" ] || exit 0
[ "$uid" = "3badc391-379d-495e-938c-3f40548bd336" ] || { echo 'Unexpected Job UID; stopping' >&2; exit 1; }
failed=$(sudo k3s kubectl -n openhab-analytics get job "$name" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}')
[ "$failed" = True ] || { echo 'Job is not terminal Failed; stopping' >&2; exit 1; }
proof=$(sudo k3s kubectl -n openhab-analytics get job analytics-maintenance-proof-20261023 -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')
[ "$proof" = True ] || { echo 'Replacement proof is incomplete; stopping' >&2; exit 1; }
sudo k3s kubectl -n openhab-analytics delete job "$name" --wait=true
