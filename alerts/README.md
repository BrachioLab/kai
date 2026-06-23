# kai-alerts

Opt-in **email alerts** for KAI jobs: finished, running too long, or near its
memory limit. A small in-cluster controller (single-file Python, stdlib only)
watches Jobs, evaluates per-job rules, and emails the submitter.

## How a user requests alerts

At submit time (all opt-in — nothing fires unless asked):

```sh
kai submit --image … --gpu 1 --alert-finish -- python train.py          # email on done/fail
kai submit --image … --alert-runtime 24h -- python long.py              # email if it runs > 24h
kai submit --image … --alert-mem -- python hungry.py                    # email at >=90% of mem limit
kai submit --image … --alert-mem 80 --alert-finish -- python x.py       # combine; custom threshold
kai submit --image … --alert-finish --alert-email me@upenn.edu -- …      # override recipient
```

Default recipient is **`<your-username>@upenn.edu`**. These flags just write
annotations on the Job (`kai.alerts/finish|runtime|mem|email`); the controller
does the rest.

## What fires

| Alert | Annotation | Condition | Sends |
|-------|-----------|-----------|-------|
| Finish | `kai.alerts/finish=true` | Job `Complete` or `Failed` | once |
| Long-running | `kai.alerts/runtime=24h` | running longer than the duration | once |
| Near memory limit | `kai.alerts/mem=90` | a running container's RAM ≥ PCT% of its `limits.memory` (via metrics-server) | once |

Dedupe is durable: the controller writes `kai.alerts/sent-<type>=true` back on
the Job, so a restart never re-sends. (`--alert-mem` needs the container to have
a `memory` limit set, and metrics-server present.)

## Deploy (per cluster)

```sh
deploy/deploy.sh                       # builds the alerts.py ConfigMap, applies RBAC + Deployment

# SMTP config (one secret per cluster):
kubectl -n kai-alerts create secret generic kai-alerts-smtp \
  --from-literal=host=<smtp-host> --from-literal=port=587 \
  --from-literal=user=<smtp-user> --from-literal=pass=<smtp-app-password> \
  --from-literal=from='KAI cluster <noreply@…>' \
  --from-literal=tls=starttls \
  --from-literal=cluster=locust
```

The Deployment runs fine before the secret exists (it just logs `no-smtp` and
doesn't send). `tls` ∈ `starttls|ssl|none`. Set `KAI_ALERTS_DRY_RUN=true` on the
deployment to log instead of send (handy for testing). RBAC: read jobs/pods +
`metrics.k8s.io`, patch jobs (for the dedupe annotations).

## Notes

- The controller is **stateless** apart from the `sent-*` Job annotations.
- Email is the submitter's `<username>@upenn.edu` unless `--alert-email` overrides
  (assumes username = PennKey).
- Single file, no pip deps; reads the cluster via the in-cluster API (or `kubectl`
  if run outside a pod).
