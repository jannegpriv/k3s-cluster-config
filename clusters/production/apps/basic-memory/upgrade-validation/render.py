"""Render opt-in validation resources; never included by the production Kustomization."""
import json
import os
from pathlib import Path
import sys

NS = 'basic-memory'
NAME = os.environ.get('BM_VALIDATION_NAME', 'basic-memory-v1-test')
assert NAME in ('basic-memory-v1-test', 'basic-memory-v1-restore', 'basic-memory-pre-v1-rollback')
PVC = NAME + '-data'
IMAGE = 'ghcr.io/basicmachines-co/basic-memory:1.0.0@sha256:cad49f5433bcd8592fea547907a2b967435b3fa60d0f81ebc4d558e2b5cb55a8'
OLD_IMAGE = 'ghcr.io/basicmachines-co/basic-memory:0.23.2@sha256:939f1173d96626c280763e14622f2381d49fbbb7db17cae2e832f4f639405643'
LABELS = {'app.kubernetes.io/name': NAME, 'basic-memory-validation': 'v1'}
SECURITY = {'runAsNonRoot': True, 'runAsUser': 1000, 'runAsGroup': 1000, 'fsGroup': 1000, 'fsGroupChangePolicy': 'OnRootMismatch', 'seccompProfile': {'type': 'RuntimeDefault'}}
CONTAINER_SECURITY = {'allowPrivilegeEscalation': False, 'capabilities': {'drop': ['ALL']}}
AFFINITY = {'podAffinity': {'requiredDuringSchedulingIgnoredDuringExecution': [{'labelSelector': {'matchLabels': {'app.kubernetes.io/name': 'basic-memory', 'app.kubernetes.io/instance': 'basic-memory'}}, 'topologyKey': 'kubernetes.io/hostname'}]}}
ENV = {'BASIC_MEMORY_HOME': '/data/memory', 'BASIC_MEMORY_PROJECT_ROOT': '/data/memory', 'BASIC_MEMORY_CONFIG_DIR': '/data/config', 'BASIC_MEMORY_DEFAULT_PROJECT': 'main', 'BASIC_MEMORY_DATABASE_BACKEND': 'sqlite', 'BASIC_MEMORY_DEFAULT_SEARCH_TYPE': 'hybrid', 'BASIC_MEMORY_SEMANTIC_EMBEDDING_PROVIDER': 'fastembed', 'BASIC_MEMORY_SEMANTIC_EMBEDDING_MODEL': 'sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2', 'BASIC_MEMORY_SEMANTIC_EMBEDDING_DIMENSIONS': '384', 'BASIC_MEMORY_SEMANTIC_EMBEDDING_CACHE_DIR': '/data/cache/fastembed', 'BASIC_MEMORY_SEMANTIC_EMBEDDING_THREADS': '2', 'BASIC_MEMORY_SEMANTIC_EMBEDDING_PARALLEL': '1', 'BASIC_MEMORY_INDEX_CHANGES': 'true', 'BASIC_MEMORY_LOGFIRE_ENABLED': 'false', 'BASIC_MEMORY_LOGFIRE_SEND_TO_LOGFIRE': 'false', 'BASIC_MEMORY_ENV': 'user', 'TZ': 'Europe/Stockholm'}

def resource(kind, name, spec, api='v1'):
    return {'apiVersion': api, 'kind': kind, 'metadata': {'name': name, 'namespace': NS, 'labels': LABELS}, 'spec': spec}

def volume(name, claim, readonly=False):
    return {'name': name, 'persistentVolumeClaim': {'claimName': claim, 'readOnly': readonly}}

if sys.argv[1] == 'setup':
    pvc = resource('PersistentVolumeClaim', PVC, {'accessModes': ['ReadWriteOnce'], 'storageClassName': 'rook-ceph-block', 'resources': {'requests': {'storage': '5Gi'}}})
    pvc['metadata']['annotations'] = {'kustomize.toolkit.fluxcd.io/prune': 'disabled'}
    scripts = {'apiVersion': 'v1', 'kind': 'ConfigMap', 'metadata': {'name': NAME + '-scripts', 'namespace': NS, 'labels': LABELS}, 'data': {'snapshot_copy.py': Path(__file__).with_name('snapshot_copy.py').read_text()}}
    pod = {'automountServiceAccountToken': False, 'restartPolicy': 'Never', 'securityContext': SECURITY, 'affinity': AFFINITY, 'containers': [{'name': 'copy', 'image': OLD_IMAGE, 'command': ['python', '/scripts/snapshot_copy.py'], 'securityContext': CONTAINER_SECURITY, 'resources': {'requests': {'cpu': '100m', 'memory': '128Mi'}, 'limits': {'cpu': '1', 'memory': '512Mi'}}, 'volumeMounts': [{'name': 'source', 'mountPath': '/source', 'readOnly': True}, {'name': 'target', 'mountPath': '/data'}, {'name': 'scripts', 'mountPath': '/scripts', 'readOnly': True}]}], 'volumes': [volume('source', 'basic-memory-data', True), volume('target', PVC), {'name': 'scripts', 'configMap': {'name': NAME + '-scripts'}}]}
    job = resource('Job', NAME + '-copy', {'backoffLimit': 0, 'activeDeadlineSeconds': 600, 'template': {'metadata': {'labels': LABELS}, 'spec': pod}}, 'batch/v1')
    policy = resource('NetworkPolicy', NAME, {'podSelector': {'matchLabels': LABELS}, 'policyTypes': ['Ingress', 'Egress'], 'ingress': [], 'egress': [{'to': [{'namespaceSelector': {'matchLabels': {'kubernetes.io/metadata.name': 'kube-system'}}, 'podSelector': {'matchLabels': {'k8s-app': 'kube-dns'}}}], 'ports': [{'protocol': 'UDP', 'port': 53}, {'protocol': 'TCP', 'port': 53}]}, {'to': [{'ipBlock': {'cidr': '0.0.0.0/0', 'except': ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16']}}], 'ports': [{'protocol': 'TCP', 'port': 443}]}]}, 'networking.k8s.io/v1')
    result = {'apiVersion': 'v1', 'kind': 'List', 'items': [pvc, scripts, policy, job]}
elif sys.argv[1] in ('server', 'index'):
    assert NAME != 'basic-memory-pre-v1-rollback', 'Never migrate the rollback copy'
    container = {'name': 'basic-memory', 'image': IMAGE, 'command': ['basic-memory', 'mcp', '--transport', 'streamable-http', '--host', '127.0.0.1', '--port', '8000', '--path', '/mcp', '--project', 'main'], 'env': [{'name': k, 'value': v} for k, v in ENV.items()], 'securityContext': CONTAINER_SECURITY, 'resources': {'requests': {'cpu': '500m', 'memory': '1Gi'}, 'limits': {'cpu': '2', 'memory': '3Gi'}}, 'volumeMounts': [{'name': 'data', 'mountPath': '/data'}], 'startupProbe': {'exec': {'command': ['python', '-c', 'import socket; socket.create_connection(("127.0.0.1",8000),3).close()']}, 'periodSeconds': 5, 'failureThreshold': 180}, 'readinessProbe': {'exec': {'command': ['python', '-c', 'import socket; socket.create_connection(("127.0.0.1",8000),3).close()']}, 'periodSeconds': 10}}
    pod = {'automountServiceAccountToken': False, 'securityContext': SECURITY, 'affinity': AFFINITY, 'containers': [container], 'volumes': [volume('data', PVC)]}
    if sys.argv[1] == 'index':
        assert NAME == 'basic-memory-v1-restore'
        container['command'] = ['/bin/sh', '-ec', 'basic-memory reindex --full --search -p main && basic-memory reindex --embeddings -p main']
        container.pop('startupProbe')
        container.pop('readinessProbe')
        for item in container['env']:
            if item['name'] == 'BASIC_MEMORY_INDEX_CHANGES':
                item['value'] = 'false'
        pod['restartPolicy'] = 'Never'
        result = resource('Job', NAME + '-index', {'backoffLimit': 0, 'activeDeadlineSeconds': 3600, 'template': {'metadata': {'labels': LABELS}, 'spec': pod}}, 'batch/v1')
    else:
        result = resource('Deployment', NAME, {'replicas': 1, 'strategy': {'type': 'Recreate'}, 'selector': {'matchLabels': LABELS}, 'template': {'metadata': {'labels': LABELS}, 'spec': pod}}, 'apps/v1')
elif sys.argv[1] == 'backup-restore':
    assert NAME == 'basic-memory-v1-restore'
    pvc = resource('PersistentVolumeClaim', PVC, {'accessModes': ['ReadWriteOnce'], 'storageClassName': 'rook-ceph-block', 'resources': {'requests': {'storage': '5Gi'}}})
    scripts = {'apiVersion': 'v1', 'kind': 'ConfigMap', 'metadata': {'name': NAME + '-scripts', 'namespace': NS, 'labels': LABELS}, 'data': {'restore_check.py': Path(__file__).with_name('restore_check.py').read_text(), 'backup.py': Path(__file__).parent.parent.joinpath('scripts/backup.py').read_text(), 'known_hosts': Path(__file__).parent.parent.joinpath('scripts/known_hosts').read_text()}}
    mounts = [{'name': 'data', 'mountPath': '/data', 'readOnly': True}, {'name': 'target', 'mountPath': '/restore'}, {'name': 'scripts', 'mountPath': '/scripts', 'readOnly': True}, {'name': 'scripts', 'mountPath': '/ssh', 'readOnly': True}, {'name': 'credentials', 'mountPath': '/credentials', 'readOnly': True}, {'name': 'work', 'mountPath': '/work'}]
    container = {'name': 'backup-restore', 'image': 'alpine:3.23@sha256:85fe1e81d6758c208f3e1eed4338a1997e19d4be002d4dd32d3100c9a8c010a0', 'command': ['/bin/sh', '-ec', 'apk add --no-cache python3 openssh-client sshpass; exec python3 /scripts/restore_check.py'], 'env': [{'name': 'BASIC_MEMORY_BACKUP_DESTINATION', 'value': '/volume1/k3s_backups/basic-memory-upgrade-test-20261106'}, {'name': 'BASIC_MEMORY_BACKUP_VERSION', 'value': '1.0.0'}], 'volumeMounts': mounts, 'resources': {'requests': {'cpu': '100m', 'memory': '128Mi'}, 'limits': {'cpu': '1', 'memory': '512Mi'}}}
    pod = {'automountServiceAccountToken': False, 'restartPolicy': 'Never', 'affinity': AFFINITY, 'containers': [container], 'volumes': [volume('data', 'basic-memory-v1-test-data', True), volume('target', PVC), {'name': 'scripts', 'configMap': {'name': NAME + '-scripts'}}, {'name': 'credentials', 'secret': {'secretName': 'basic-memory-nas', 'defaultMode': 256}}, {'name': 'work', 'emptyDir': {'sizeLimit': '2Gi'}}]}
    job = resource('Job', NAME, {'backoffLimit': 0, 'activeDeadlineSeconds': 1200, 'template': {'metadata': {'labels': {**LABELS, 'validation-job': 'backup-restore'}}, 'spec': pod}}, 'batch/v1')
    policy = resource('NetworkPolicy', NAME, {'podSelector': {'matchLabels': LABELS}, 'policyTypes': ['Ingress', 'Egress'], 'ingress': [], 'egress': [{'to': [{'namespaceSelector': {'matchLabels': {'kubernetes.io/metadata.name': 'kube-system'}}, 'podSelector': {'matchLabels': {'k8s-app': 'kube-dns'}}}], 'ports': [{'protocol': 'UDP', 'port': 53}, {'protocol': 'TCP', 'port': 53}]}, {'to': [{'ipBlock': {'cidr': '0.0.0.0/0', 'except': ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16']}}], 'ports': [{'protocol': 'TCP', 'port': 443}]}]}, 'networking.k8s.io/v1')
    nas_policy = resource('NetworkPolicy', NAME + '-nas', {'podSelector': {'matchLabels': {**LABELS, 'validation-job': 'backup-restore'}}, 'policyTypes': ['Egress'], 'egress': [{'to': [{'ipBlock': {'cidr': '192.168.50.25/32'}}], 'ports': [{'protocol': 'TCP', 'port': 4711}]}]}, 'networking.k8s.io/v1')
    result = {'apiVersion': 'v1', 'kind': 'List', 'items': [pvc, scripts, policy, nas_policy, job]}
else:
    raise SystemExit('Choose setup, server, index or backup-restore')
print(json.dumps(result))
