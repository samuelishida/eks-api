#!/usr/bin/env sh
# kind-e2e — run the real API image against PostgreSQL in an isolated Kind cluster.
set -eu

KIND_BIN="${KIND_BIN:-kind}"
KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
HELM_BIN="${HELM_BIN:-helm}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
CURL_BIN="${CURL_BIN:-curl}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'kind-e2e: required command not found: %s\n' "$1" >&2
    exit 127
  }
}

require_command "$KIND_BIN"
require_command "$KUBECTL_BIN"
require_command "$HELM_BIN"
require_command "$DOCKER_BIN"
require_command "$CURL_BIN"
require_command "$PYTHON_BIN"

"$DOCKER_BIN" info >/dev/null 2>&1 || {
  echo "kind-e2e: Docker daemon is unavailable" >&2
  exit 1
}

NAMESPACE=api-kind
CLUSTER_NAME="eks-api-e2e-$$"
IMAGE_TAG="kind-e2e-$$"
IMAGE="eks-api-api:$IMAGE_TAG"
DB_PASSWORD=kind-local-only
PORT="${KIND_E2E_PORT:-}"
if [ -z "$PORT" ]; then
  PORT=$("$PYTHON_BIN" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
fi
"$PYTHON_BIN" -c 'import sys; p=int(sys.argv[1]); assert 1 <= p <= 65535' "$PORT" || {
  echo "kind-e2e: KIND_E2E_PORT must be an integer from 1 to 65535" >&2
  exit 2
}

umask 077
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/eks-api-kind-e2e.XXXXXX")
KUBECONFIG_FILE="$TMP_DIR/kubeconfig"
PORT_FORWARD_PID=
CLUSTER_OWNED=0
IMAGE_BUILT=0

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM

  if [ -n "$PORT_FORWARD_PID" ]; then
    kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
    wait "$PORT_FORWARD_PID" 2>/dev/null || true
  fi

  if [ "$status" -ne 0 ] && [ -f "$KUBECONFIG_FILE" ]; then
    echo "kind-e2e: diagnostics before cleanup:" >&2
    "$KUBECTL_BIN" --kubeconfig "$KUBECONFIG_FILE" -n "$NAMESPACE" get pods -o wide >&2 2>/dev/null || true
    "$KUBECTL_BIN" --kubeconfig "$KUBECONFIG_FILE" -n "$NAMESPACE" logs deployment/api --all-containers --tail=60 >&2 2>/dev/null || true
    "$KUBECTL_BIN" --kubeconfig "$KUBECONFIG_FILE" -n "$NAMESPACE" logs deployment/postgres --all-containers --tail=60 >&2 2>/dev/null || true
  fi

  if [ "$CLUSTER_OWNED" -eq 1 ]; then
    if "$KIND_BIN" delete cluster --name "$CLUSTER_NAME" >/dev/null; then
      echo "kind-e2e: deleted cluster $CLUSTER_NAME"
    else
      echo "kind-e2e: failed to delete cluster $CLUSTER_NAME" >&2
      status=1
    fi
  fi
  if [ "$IMAGE_BUILT" -eq 1 ]; then
    "$DOCKER_BIN" image rm "$IMAGE" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

EXISTING_CLUSTERS=$("$KIND_BIN" get clusters)
if printf '%s\n' "$EXISTING_CLUSTERS" | grep -Fxq "$CLUSTER_NAME"; then
  echo "kind-e2e: refusing to reuse existing cluster $CLUSTER_NAME" >&2
  exit 1
fi
if "$DOCKER_BIN" image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "kind-e2e: refusing to overwrite existing image $IMAGE" >&2
  exit 1
fi

echo "kind-e2e: creating isolated cluster $CLUSTER_NAME"
CLUSTER_OWNED=1
"$KIND_BIN" create cluster --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG_FILE" --wait 180s

echo "kind-e2e: building $IMAGE"
"$DOCKER_BIN" build -t "$IMAGE" apps/api
IMAGE_BUILT=1
"$KIND_BIN" load docker-image "$IMAGE" --name "$CLUSTER_NAME"

export KUBECONFIG="$KUBECONFIG_FILE"
"$KUBECTL_BIN" create namespace "$NAMESPACE"
"$KUBECTL_BIN" -n "$NAMESPACE" create secret generic api-db-credentials \
  --from-literal=host=postgres \
  --from-literal=port=5432 \
  --from-literal=user=app \
  --from-literal=password="$DB_PASSWORD" \
  --from-literal=name=app

"$KUBECTL_BIN" apply -f - <<'EOF_MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: api-kind
  labels:
    app.kubernetes.io/name: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: postgres
  template:
    metadata:
      labels:
        app.kubernetes.io/name: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          ports:
            - name: postgres
              containerPort: 5432
          env:
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: api-db-credentials
                  key: user
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: api-db-credentials
                  key: password
            - name: POSTGRES_DB
              valueFrom:
                secretKeyRef:
                  name: api-db-credentials
                  key: name
          readinessProbe:
            exec:
              command:
                - sh
                - -ec
                - |
                  pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"
            initialDelaySeconds: 2
            periodSeconds: 2
            timeoutSeconds: 2
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: api-kind
spec:
  selector:
    app.kubernetes.io/name: postgres
  ports:
    - name: postgres
      port: 5432
      targetPort: postgres
EOF_MANIFEST

"$KUBECTL_BIN" -n "$NAMESPACE" rollout status deployment/postgres --timeout=180s

"$HELM_BIN" upgrade --install api charts/api \
  --namespace "$NAMESPACE" \
  -f charts/api/values-dev.yaml \
  --set-string image.repository=eks-api-api \
  --set-string image.tag="$IMAGE_TAG" \
  --set image.pullPolicy=IfNotPresent \
  --set db.sslMode=disable \
  --set ingress.enabled=false
"$KUBECTL_BIN" -n "$NAMESPACE" rollout status deployment/api --timeout=180s

BASE_URL="http://127.0.0.1:$PORT"
echo "kind-e2e: forwarding API at $BASE_URL"
"$KUBECTL_BIN" -n "$NAMESPACE" port-forward --address 127.0.0.1 \
  "service/api" "$PORT:8080" >"$TMP_DIR/port-forward.log" 2>&1 &
PORT_FORWARD_PID=$!

ready=0
attempt=0
while [ "$attempt" -lt 60 ]; do
  if "$CURL_BIN" -fsS "$BASE_URL/healthz" >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "$PORT_FORWARD_PID" >/dev/null 2>&1; then
    cat "$TMP_DIR/port-forward.log" >&2
    echo "kind-e2e: kubectl port-forward exited early" >&2
    exit 1
  fi
  attempt=$((attempt + 1))
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  cat "$TMP_DIR/port-forward.log" >&2
  echo "kind-e2e: API did not become reachable within 60 seconds" >&2
  exit 1
fi

"$PYTHON_BIN" - "$BASE_URL" <<'PY'
import json
import sys
import urllib.error
import urllib.request

base = sys.argv[1]

def request(method, path, payload=None, expected=200):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(
        base + path,
        data=data,
        method=method,
        headers={"Content-Type": "application/json"},
    )
    try:
        response = urllib.request.urlopen(req, timeout=10)
        status, body = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, body = error.code, error.read()
    if status != expected:
        raise AssertionError(f"{method} {path}: got {status}, wanted {expected}; body={body!r}")
    return json.loads(body) if body else None

for path in ("/healthz", "/readyz"):
    result = request("GET", path)
    assert result["status"] == "ok", f"{path}: unexpected body {result!r}"

created = request("POST", "/api/v1/items", {"name": "kind-e2e-item"}, 201)
item_id = created["id"]
assert item_id > 0 and created["name"] == "kind-e2e-item", created

fetched = request("GET", f"/api/v1/items/{item_id}")
assert fetched["id"] == item_id and fetched["name"] == "kind-e2e-item", fetched

listed = request("GET", "/api/v1/items")
assert any(item["id"] == item_id for item in listed), listed

updated = request("PUT", f"/api/v1/items/{item_id}", {"name": "kind-e2e-updated"})
assert updated["id"] == item_id and updated["name"] == "kind-e2e-updated", updated

request("DELETE", f"/api/v1/items/{item_id}", expected=204)
request("GET", f"/api/v1/items/{item_id}", expected=404)

print("kind-e2e: health, readiness, PostgreSQL CRUD, and post-delete 404 passed")
PY
