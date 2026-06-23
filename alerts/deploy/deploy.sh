#!/usr/bin/env sh
# Deploy the kai-alerts controller into the current kubectl context.
# Builds the source ConfigMap from alerts.py, applies RBAC + Deployment, rolls it.
#
#   deploy/deploy.sh
# SMTP is configured separately via the kai-alerts-smtp secret, e.g.:
#   kubectl -n kai-alerts create secret generic kai-alerts-smtp \
#     --from-literal=host=smtp.example.edu --from-literal=port=587 \
#     --from-literal=user=<user> --from-literal=pass=<app-password> \
#     --from-literal=from='KAI cluster <noreply@example.edu>' \
#     --from-literal=tls=starttls --from-literal=cluster=locust
set -eu
DIR="$(cd "$(dirname "$0")/.." && pwd)"
NS=kai-alerts

kubectl apply -f "$DIR/deploy/alerts.yaml"
kubectl -n "$NS" create configmap kai-alerts-src \
  --from-file=alerts.py="$DIR/alerts.py" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" rollout restart deployment kai-alerts
kubectl -n "$NS" rollout status deployment kai-alerts --timeout=120s
echo ">> kai-alerts deployed. Configure SMTP via the kai-alerts-smtp secret (see header)."
