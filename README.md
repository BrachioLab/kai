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
```

### Queues / lanes

You pick a **lane** with `--queue`; that's the only knob — it decides both where
your job is guaranteed and whether it can be evicted. kai prepends your lab's
namespace automatically (`--queue priority` → `<yourlab>-priority`).

| `--queue` | What you get |
|-----------|--------------|
| *(omitted)* / `preemptible` | **Borrow** — runs on any idle GPU, **preemptible**: reclaimed when an owner needs that node. The safe default; an accident can't block the cluster. |
| `priority` | **Guaranteed** — runs on **your lab's own nodes**, non-preemptible, protected up to your lab's quota. Use for runs that must not be evicted. |

Pick hardware with `--gpu-type` (e.g. `--gpu-type a6000`), or a specific machine
with `--node <hostname>`. There is **no `--priority` flag** — the lane sets it.

## Managing jobs

```sh
kai list                  # show all your jobs and their status
kai logs <job>            # print recent logs
kai logs <job> -f         # stream logs live
kai bash <job>            # open an interactive bash shell inside a running job
kai describe <job>        # detailed job info and events
kai delete <job>          # cancel and remove a job
```

## Cluster info

```sh
kai gpus                  # GPU availability across all nodes
kai status                # all resources in your namespace
kai queue list            # available queues and their GPU quotas
```

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
