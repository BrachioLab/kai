#!/usr/bin/env python3
"""
kai-alerts — in-cluster controller that emails job alerts.

Alerts are OPT-IN per job: `kai submit --alert-finish / --alert-runtime 24h /
--alert-mem [PCT] [--alert-email ADDR]` writes annotations on the Job:

    kai.alerts/email     <addr>            (default <user>@upenn.edu)
    kai.alerts/finish    "true"            email on Complete/Failed
    kai.alerts/runtime   "24h"             email once running longer than this
    kai.alerts/mem       "90"              email once mem >= PCT% of the limit

This controller polls Jobs cluster-wide, evaluates those rules, sends email via
SMTP (creds from env / a Secret), and dedupes by writing `kai.alerts/sent-*`
annotations back on the Job (so restarts don't re-send). Single file, Python
stdlib only. Reads the cluster via the in-cluster API (or kubectl if run locally).

Env (from the kai-alerts-smtp Secret + Deployment):
  KAI_ALERTS_SMTP_HOST / _PORT(587) / _USER / _PASS / _FROM
  KAI_ALERTS_SMTP_TLS  starttls|ssl|none   (default starttls)
  KAI_ALERTS_CLUSTER   label shown in emails (e.g. "locust")
  KAI_ALERTS_INTERVAL  poll seconds (default 60)
  KAI_ALERTS_DRY_RUN   "true" -> log instead of sending
"""

import json
import os
import re
import smtplib
import ssl
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone
from email.message import EmailMessage

_VERSION = "0.1.0"

SMTP_HOST = os.environ.get("KAI_ALERTS_SMTP_HOST")
SMTP_PORT = int(os.environ.get("KAI_ALERTS_SMTP_PORT", "587"))
SMTP_USER = os.environ.get("KAI_ALERTS_SMTP_USER")
SMTP_PASS = os.environ.get("KAI_ALERTS_SMTP_PASS")
SMTP_FROM = os.environ.get("KAI_ALERTS_FROM") or SMTP_USER or "kai-alerts@localhost"
SMTP_TLS  = os.environ.get("KAI_ALERTS_SMTP_TLS", "starttls").lower()
CLUSTER   = os.environ.get("KAI_ALERTS_CLUSTER", "")
INTERVAL  = max(15, int(os.environ.get("KAI_ALERTS_INTERVAL", "60")))
DRY_RUN   = os.environ.get("KAI_ALERTS_DRY_RUN", "").lower() in ("1", "true", "yes")

_TAG = "[kai-alerts%s]" % (("/" + CLUSTER) if CLUSTER else "")


def log(msg):
    print("%s %s" % (datetime.now(timezone.utc).strftime("%H:%M:%S"), msg), flush=True)

# ── kubernetes access (in-cluster API, else kubectl) ─────────────────────────

_SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"
_SA_TOKEN, _SA_CA = _SA_DIR + "/token", _SA_DIR + "/ca.crt"
_SSL_CTX = None


def in_cluster():
    return bool(os.environ.get("KUBERNETES_SERVICE_HOST")) and os.path.exists(_SA_TOKEN)


def _api_base():
    return "https://%s:%s" % (os.environ["KUBERNETES_SERVICE_HOST"],
                              os.environ.get("KUBERNETES_SERVICE_PORT", "443"))


def _ctx():
    global _SSL_CTX
    if _SSL_CTX is None:
        _SSL_CTX = ssl.create_default_context(cafile=_SA_CA)
    return _SSL_CTX


def _api(path, method="GET", body=None):
    token = open(_SA_TOKEN).read().strip()
    headers = {"Authorization": "Bearer " + token, "Accept": "application/json"}
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/merge-patch+json"
    req = urllib.request.Request(_api_base() + path, data=data, method=method, headers=headers)
    with urllib.request.urlopen(req, context=_ctx(), timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))


def _kubectl_json(*args):
    p = subprocess.run(["kubectl"] + list(args) + ["-o", "json"],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip())
    return json.loads(p.stdout)


def list_jobs():
    if in_cluster():
        return _api("/apis/batch/v1/jobs").get("items", [])
    return _kubectl_json("get", "jobs", "--all-namespaces").get("items", [])


def list_job_pods(ns, job):
    sel = "job-name=" + job
    if in_cluster():
        return _api("/api/v1/namespaces/%s/pods?labelSelector=%s" % (ns, sel)).get("items", [])
    return _kubectl_json("get", "pods", "-n", ns, "-l", sel).get("items", [])


def pod_metrics(ns, pod):
    try:
        if in_cluster():
            return _api("/apis/metrics.k8s.io/v1beta1/namespaces/%s/pods/%s" % (ns, pod))
        return _kubectl_json("get", "pods.metrics.k8s.io", "-n", ns, pod)
    except Exception:
        return None


def mark_sent(ns, name, key):
    body = {"metadata": {"annotations": {"kai.alerts/sent-" + key: "true"}}}
    if in_cluster():
        _api("/apis/batch/v1/namespaces/%s/jobs/%s" % (ns, name), method="PATCH", body=body)
    else:
        subprocess.run(["kubectl", "-n", ns, "annotate", "job", name,
                        "kai.alerts/sent-%s=true" % key, "--overwrite"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# ── helpers ──────────────────────────────────────────────────────────────────

_MEM = {"Ki": 1024, "Mi": 1024**2, "Gi": 1024**3, "Ti": 1024**4,
        "k": 1000, "M": 1000**2, "G": 1000**3, "T": 1000**4}


def parse_mem(s):
    s = str(s).strip()
    for suf, mult in sorted(_MEM.items(), key=lambda kv: -len(kv[0])):
        if s.endswith(suf):
            try:
                return int(float(s[:-len(suf)]) * mult)
            except ValueError:
                return 0
    try:
        return int(float(s or 0))
    except ValueError:
        return 0


def parse_dur(s):
    """'24h' '90m' '30s' '2d' -> seconds (bare number = seconds)."""
    m = re.match(r"^\s*(\d+(?:\.\d+)?)\s*([smhd]?)\s*$", str(s))
    if not m:
        return None
    n = float(m.group(1))
    return int(n * {"s": 1, "m": 60, "h": 3600, "d": 86400, "": 1}[m.group(2)])


def age_secs(ts):
    try:
        dt = datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
    except ValueError:
        return 0
    return (datetime.now(timezone.utc) - dt).total_seconds()


def job_finished(status):
    for c in status.get("conditions", []):
        if c.get("status") == "True" and c.get("type") in ("Complete", "Failed"):
            return c["type"]
    return None


def send_email(to, subject, body):
    subject = "%s %s" % (_TAG, subject)
    if DRY_RUN or not SMTP_HOST:
        log("EMAIL(%s) -> %s | %s" % ("dry-run" if DRY_RUN else "no-smtp", to, subject))
        return not (SMTP_HOST is None and not DRY_RUN)  # treat as "sent" in dry-run; fail if misconfigured
    msg = EmailMessage()
    msg["From"], msg["To"], msg["Subject"] = SMTP_FROM, to, subject
    msg.set_content(body)
    try:
        if SMTP_TLS == "ssl":
            srv = smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, timeout=25, context=ssl.create_default_context())
        else:
            srv = smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=25)
            if SMTP_TLS == "starttls":
                srv.starttls(context=ssl.create_default_context())
        if SMTP_USER:
            srv.login(SMTP_USER, SMTP_PASS)
        srv.send_message(msg)
        srv.quit()
        log("sent -> %s | %s" % (to, subject))
        return True
    except Exception as e:
        log("EMAIL FAILED -> %s: %s" % (to, e))
        return False

# ── rule evaluation ──────────────────────────────────────────────────────────

def mem_breach(ns, name, pct):
    """Return (pod, container, used_pct) if a running container is >= pct% of its
    memory limit, else None."""
    for p in list_job_pods(ns, name):
        if p.get("status", {}).get("phase") != "Running":
            continue
        limits = {c["name"]: c.get("resources", {}).get("limits", {}).get("memory")
                  for c in p.get("spec", {}).get("containers", [])}
        m = pod_metrics(ns, p["metadata"]["name"])
        if not m:
            continue
        for c in m.get("containers", []):
            lim = limits.get(c.get("name"))
            if not lim:
                continue
            used, limb = parse_mem(c.get("usage", {}).get("memory", "0")), parse_mem(lim)
            if limb and 100.0 * used / limb >= pct:
                return (p["metadata"]["name"], c.get("name"), int(round(100.0 * used / limb)))
    return None


def _ctx_lines(meta, status):
    user = meta.get("labels", {}).get("kai.scheduler/user", "?")
    queue = meta.get("labels", {}).get("kai.scheduler/queue", "?")
    return ("job:       %s\nnamespace: %s\nuser:      %s\nqueue:     %s%s"
            % (meta["name"], meta["namespace"], user, queue,
               ("\ncluster:   " + CLUSTER) if CLUSTER else ""))


def evaluate(job):
    meta = job.get("metadata", {})
    ann = meta.get("annotations", {})
    to = ann.get("kai.alerts/email")
    if not to:
        return
    ns, name, status = meta["namespace"], meta["name"], job.get("status", {})

    def sent(k):
        return ann.get("kai.alerts/sent-" + k) == "true"

    if ann.get("kai.alerts/finish") == "true" and not sent("finish"):
        state = job_finished(status)
        if state:
            ok = send_email(to, "job %s %s" % (name, "completed" if state == "Complete" else "FAILED"),
                            "Your job has finished: %s\n\n%s\n" % (state, _ctx_lines(meta, status)))
            if ok:
                mark_sent(ns, name, "finish")

    if ann.get("kai.alerts/runtime") and not sent("runtime"):
        secs = parse_dur(ann["kai.alerts/runtime"])
        start = status.get("startTime")
        if secs and status.get("active", 0) and start and age_secs(start) >= secs:
            hrs = age_secs(start) / 3600.0
            ok = send_email(to, "job %s running %.1fh" % (name, hrs),
                            "Heads up — your job has been running %.1f hours (threshold %s):\n\n%s\n"
                            % (hrs, ann["kai.alerts/runtime"], _ctx_lines(meta, status)))
            if ok:
                mark_sent(ns, name, "runtime")

    if ann.get("kai.alerts/mem") and not sent("mem"):
        try:
            pct = float(ann["kai.alerts/mem"])
        except ValueError:
            pct = 90.0
        hit = mem_breach(ns, name, pct)
        if hit:
            pod, cont, used = hit
            ok = send_email(to, "job %s near memory limit (%d%%)" % (name, used),
                            "Your job's memory use hit %d%% of its limit (threshold %g%%) "
                            "— OOM risk.\npod/container: %s/%s\n\n%s\n"
                            % (used, pct, pod, cont, _ctx_lines(meta, status)))
            if ok:
                mark_sent(ns, name, "mem")


def main():
    log("kai-alerts %s starting | interval=%ss dry_run=%s smtp=%s cluster=%s"
        % (_VERSION, INTERVAL, DRY_RUN, SMTP_HOST or "(unset)", CLUSTER or "(unset)"))
    if not in_cluster():
        log("note: not in-cluster — using local kubectl")
    while True:
        try:
            for job in list_jobs():
                if any(k.startswith("kai.alerts/") for k in job.get("metadata", {}).get("annotations", {})):
                    try:
                        evaluate(job)
                    except Exception as e:
                        log("eval error %s: %s" % (job.get("metadata", {}).get("name"), e))
        except Exception as e:
            log("poll error: %s" % e)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
