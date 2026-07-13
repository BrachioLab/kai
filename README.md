# kai

CLI for submitting and managing jobs on a [KAI Scheduler](https://github.com/run-ai/KAI-Scheduler) cluster.

## Getting started

### Step 1 — Install kai

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/BrachioLab/kai/main/install.sh)"
```

You will be prompted for the configs repository and your lab namespace. The installer checks that your account exists in the repo before proceeding — if it doesn't, ask your lab manager to run `kai add-user --name <you>` first.

The installer also sets up automatic update checks on every login.

Then start a new shell (or run `source ~/.bashrc` / `source ~/.zshrc`) so `kai` is on your PATH.

### Step 2 — Get your kubeconfig from the lab manager

Your lab manager will send you `kai-kubeconfig-<you>.yaml` via a secure channel (Slack DM, encrypted email, etc.). **Keep this secret — treat it like a password.**

### Step 3 — Set up kai

```sh
kai setup kai-kubeconfig-<you>.yaml
```

This installs your kubeconfig and fetches your CLI config automatically from the configs repo.

That's it — you're ready to submit jobs.

---

## Submitting jobs

```sh
# Run a script on 1 GPU (default lane: preemptible — see "Queues / lanes" below)
kai submit --image pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime --gpu 1 -- python train.py

# Guaranteed run on your lab's own nodes (non-preemptible, protected up to quota)
kai submit --image pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime --gpu 1 --queue priority -- python train.py

# Borrow any idle A6000 anywhere (preemptible; yields when an owner needs it)
kai submit --image pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime --gpu 1 --queue preemptible --gpu-type a6000 -- python sweep.py

# Interactive session (opens a shell inside the container)
kai submit --image pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime --gpu 1 --interactive

# Mount a local directory
kai submit --image pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime --gpu 1 -v /data/datasets:/data -- python train.py

# Mount your home directory at the same path (so ~ and relative paths line up)
kai submit --image pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime --gpu 1 --mount-home -- python ~/proj/train.py
```

### Email alerts (opt-in)

Get emailed about your job. **All alerts are opt-in** — nothing is sent unless
you ask. Mail goes to **`<your-username>@upenn.edu`** by default.

| Flag | Emails you when… |
|------|------------------|
| `--alert-finish` | the job **completes or fails** |
| `--alert-runtime DUR` | it's been **running longer than `DUR`** (e.g. `24h`, `90m`, `30s`) |
| `--alert-mem [PCT]` | a container's **memory reaches `PCT`% of its limit** (default `90`; OOM early-warning) |
| `--alert-email ADDR` | *(modifier)* send alerts to `ADDR` instead of `<username>@upenn.edu` |

```sh
# email me when it finishes (or fails)
kai submit --image … --gpu 1 --alert-finish -- python train.py

# warn me if it runs past 12h or memory crosses 85% of the limit; send elsewhere
kai submit --image … --gpu 1 --memory 64Gi \
  --alert-runtime 12h --alert-mem 85 --alert-email me@upenn.edu -- python big.py
```

Each alert fires **once** per job. `--alert-mem` needs a memory limit on the job
(`--memory`) and metrics-server in the cluster. Alerts are delivered by an
in-cluster controller (see `alerts/`); nothing extra is needed on your side.

### Identity & home inside the container

Jobs run as **your UID/GID** (not root) so files you write are owned by you. kai
fills in sane defaults for that user so common tools don't trip over the image's
missing `/etc/passwd` entry — you can override any of them with `-e`:

- `USER` / `LOGNAME` = your username (stops `getpass.getuser()`, torch, pip, etc.
  from crashing with *"uid not found"*).
- `HOME` = `/tmp` (writable scratch), or your **mounted home path** when you pass
  `--mount-home`.

`--mount-home` bind-mounts your host home directory into the container at the same
path and sets `$HOME` to it. Because the job runs as your UID, writes are owned by
you — and on an NFS `root_squash` home, your UID is exactly the one allowed to write.
Pass `--root` to run as root instead (these defaults are then skipped).

### Queues / lanes

You pick two things — a **lane** (`--queue`) and a **GPU type** (`--gpu-type`) —
and kai routes the job to the right queue for you. You never type a queue name.

| `--queue` | GPU type | What you get |
|-----------|----------|--------------|
| *(omitted)* / `preemptible` | optional | **Borrow** — runs on any idle GPU (of the type, if you give one), **preemptible**: reclaimed when an owner needs it. The safe default. |
| `priority` | **required** | **Guaranteed** — your lab's contributed quota of that GPU type, non-preemptible. |
| `collaborators` | **required** | Like `priority`, for external collaborators (if your lab has a collaborator quota). |

```sh
kai submit --image … --gpu 1 --gpu-type a100 --queue priority -- python train.py   # guaranteed A100
kai submit --image … --gpu 1 --gpu-type a6000                 -- python sweep.py    # borrow an idle A6000
kai submit --image … --gpu 1                                  -- python quick.py    # borrow any idle GPU
```

How it maps (done automatically): `--gpu-type a100 --queue priority` →
`<yourlab>-a100-priority`; the borrow lane is `<yourlab>-preemptible` (any type).
**Guaranteed lanes require `--gpu-type`** — you can't ask for a guaranteed GPU
without saying which kind (kai will tell you). Your guaranteed quota is **per
type**: e.g. "12 A100 + 8 A6000" are separate pools. Within a type, the scheduler
places you on any node of that type (GPUs of a type are interchangeable); use
`--node <hostname>` only if you need a specific machine.

kai **warns** when you omit `--queue` (defaults to borrow) or `--gpu-type` (job
may land on any GPU type), so you always know what you got. There is **no
`--priority` flag** — the lane sets it. See your quotas with `kai quota`.

### Job files

Instead of long flag lists, describe a job in YAML and submit it (CLI flags
override file values):

```sh
kai submit -f job.yaml
```

```yaml
# job.yaml — keys mirror the flags
name: train-run
image: pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime
gpu: 1
queue: priority
memory: 64Gi
volumes: [ /data/datasets:/data ]
env: { WANDB_PROJECT: myproj }
ports: [ 8888 ]
command: python train.py --epochs 50
```

### More submit options

| Flag | Use |
|------|-----|
| `--name`, `-n` | name the job (otherwise auto-generated) |
| `--cpu` / `--memory` (`--mem`) | resource requests, e.g. `--cpu 8 --memory 64Gi` (also sets the limit alert baseline) |
| `--env`, `-e KEY=VALUE` | set env vars (repeatable) |
| `--volume`, `-v HOST:CTR[:ro]` | mount host paths (repeatable) |
| `--workdir`, `-w PATH` | working directory in the container |
| `--large-shm` | bigger `/dev/shm` (needed by PyTorch dataloaders/NCCL) |
| `--port`, `-p` + `--forward` | declare a port and port-forward it to your machine (e.g. Jupyter/TensorBoard) |
| `--host-network` | use the node's network namespace |
| `--attach` | stream stdin/stdout (interactive run, not a shell) |
| `--backoff-limit N` | retries after preemption/eviction (default 10) |
| `--root` | run as root instead of your UID/GID |

## Managing jobs

```sh
kai list                  # show all your jobs and their status
kai pods                  # show the underlying pods (wide)
kai logs <job>            # print recent logs
kai logs <job> -f         # stream logs live
kai bash <job>            # open an interactive bash shell inside a running job
kai exec <job> -- <cmd>   # run a one-off command in the job's pod
kai describe <job>        # detailed job info and events
kai port-forward <job> 8888   # forward a port from a running job (alias: kai pf)
kai delete <job>          # cancel and remove a job
```

## Cluster info

```sh
kai gpus                  # GPU used/free across all nodes
kai nodes                 # node health, GPU usage, conditions
kai quota                 # your queues' GPU quota/used/free (+ the nodes each is pinned to)
kai status                # all resources in your namespace
kai queue list            # all queues, quotas, and pinned nodes
```

## Lab managers

```sh
# add a user to your lab (creates their RBAC + kubeconfig, pushes their CLI config)
kai add-user --name <user> [--role researcher|lab-manager]
kai add-user --name <user> --queue collaborators --allowed-queues <lab>-collaborators

kai push-config --name <user> [--queue <lane>] [--allowed-queues <q>]   # update a user's config (no cluster change)

kai queue create --name <lab>-<lane> --quota N --priority 100 --parent locust   # new queue leaf
kai queue delete <name>
```

Send the generated `kai-kubeconfig-<user>.yaml` to the user securely; they run
`kai setup <that-file>`. (A lab manager can self-serve their own lab's members;
cross-lab/admin setup needs cluster-admin — see the cluster's onboarding runbook.)

## Updates

kai checks for updates automatically on every login. You will be prompted before anything is applied. To check manually:

```sh
kai update                # check for a config update
kai self-update           # check for a kai binary update
```

To apply without being prompted (e.g. in a script):

```sh
kai update --force
kai self-update --force
```

## Troubleshooting

**`kai: command not found`** — run `source ~/.bashrc` (or `~/.zshrc`) to pick up the PATH change from the installer, or start a new terminal.

**`error: namespace not set`** — you haven't run `kai setup` yet, or the config file wasn't found at `~/.kai/config.yaml`.

**`error: unable to connect to cluster`** — your kubeconfig may be missing or expired. Ask your lab manager for a new one and re-run `kai setup`.
