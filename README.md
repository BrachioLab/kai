# kai

CLI for submitting and managing jobs on a [KAI Scheduler](https://github.com/run-ai/KAI-Scheduler) cluster.

## Getting started

### Step 1 — Install kai

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/BrachioLab/kai/main/install.sh)"
```

This downloads `kai` to `~/.kai/bin/kai` and adds `~/.kai/bin` to your PATH in `~/.bashrc` or `~/.zshrc`.

Then start a new shell (or run `source ~/.bashrc` / `source ~/.zshrc`) so `kai` is on your PATH.

### Step 2 — Get your credentials from the lab manager

Your lab manager will send you two files:

| File | How to receive it |
|------|-------------------|
| `<lab>-<you>.yaml` — your CLI config | Safe to share; can be sent over Slack, email, etc. |
| `kai-kubeconfig-<you>.yaml` — your cluster credentials | **Keep this secret** — treat it like a password |

### Step 3 — Set up kai

```sh
kai setup <lab>-<you>.yaml kai-kubeconfig-<you>.yaml
```

This copies both files into `~/.kai/` and saves the URL that future config updates will be fetched from.

### Step 4 — Enable automatic updates

```sh
kai install
```

This adds two lines to your shell rc file so that every time you open a new terminal, kai silently checks for updates to itself and to your config. If an update is available, it will ask before applying it.

That's it — you're ready to submit jobs.

---

## Submitting jobs

```sh
# Run a script on 1 GPU
kai submit --image pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime --gpu 1 -- python train.py

# Run on a specific node
kai submit --image pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime --gpu 2 --node carnaroli -- torchrun --nproc=2 train.py

# Interactive session (opens a shell inside the container)
kai submit --image pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime --gpu 1 --interactive

# Mount a local directory
kai submit --image pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime --gpu 1 -v /data/datasets:/data -- python train.py
```

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

kai checks for updates automatically on every login (after `kai install`). You will be prompted before anything is applied. To check manually:

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
