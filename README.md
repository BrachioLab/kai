# kai

CLI for submitting and managing jobs on a [KAI Scheduler](https://github.com/run-ai/KAI-Scheduler) cluster.

## Install

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/BrachioLab/kai/main/install.sh)"
```

This installs `kai` to `~/.kai/bin/kai` and adds it to your PATH.

## First-time setup

Get your config and kubeconfig files from your lab manager, then:

```sh
kai setup config.yaml kubeconfig.yaml
kai install   # add auto-update hook to your shell
```

## Usage

```
kai submit --image pytorch:24.01 --gpu 1 -- python train.py
kai list
kai logs <job>
kai bash <job>          # open a bash shell in a running job
kai delete <job>
kai gpus                # show GPU availability
kai queue list
kai update              # pull latest config from GitHub
```

## Updating kai itself

```sh
kai self-update
```
