# Spezi Environment Setup Utility

This directory contains the Python utility that replaces the previous `setup-local.sh`
and `setup-prod.sh` scripts.  The code lives in `spezi_setup.py` and relies only on
the Python standard library, but running it inside a dedicated virtual environment
helps avoid polluting the global interpreter and keeps dependencies isolated.

## Prerequisites

* Python 3.10+ (with the `venv` module available)
* Platform tooling already installed on your workstation (e.g. `kind`, `kubectl`,
  `gcloud`, `ansible-playbook`, `tofu`/`terraform`, `gsutil`, `jq`, etc.)

## Configure default CLI options

Edit `tools/spezi_setup/defaults.py` to customise the default values passed to the
setup utility (cluster names, GCP project IDs, domains, etc.). The script imports
those dictionaries directly, so you can safely tweak the file without touching
`spezi_setup.py`.

## Create and Activate a Virtual Environment

```bash
python -m venv .venv
source .venv/bin/activate       # replace with `.venv\Scripts\activate` on Windows PowerShell
pip install --upgrade pip
```

The utility currently relies on the Python standard library only. A virtual
environment keeps future dependencies isolated even though there are no packages
to install today.

When you are finished running the tool, deactivate the environment with `deactivate`.

## Usage

After activating the virtual environment:

```bash
python tools/spezi_setup/spezi_setup.py --help
```

Common flows:

* **Local KIND environment**
  ```bash
  python tools/spezi_setup/spezi_setup.py local --force-recreate-kind  # optional to rebuild the cluster
  ```
* **Production GKE environment**
  ```bash
  python tools/spezi_setup/spezi_setup.py prod --gcp-project-id spezistudyplatform-dev
  ```
* **Production teardown**
  ```bash
  python tools/spezi_setup/spezi_setup.py prod --action teardown --auto-approve
  ```

The script still expects to be executed from the repository root because it reads
files from `config/`, `ansible/`, `local-dev/`, and `tofu/`.  See `python tools/spezi_setup/spezi_setup.py --help`
for the full list of options.
