# Spezi Environment Setup Utility

This directory contains the Python utility for bootstrapping the local
development environment. The code lives in `spezi_setup.py` and relies only on
the Python standard library.

## Prerequisites

* Python 3.10+ (with the `venv` module available)
* Platform tooling already installed on your workstation (e.g. `kind`, `kubectl`,
  `tofu`/`terraform`, `jq`, etc.)

## Configure default CLI options

Edit `tools/spezi_setup/defaults.py` to customise the default values passed to the
setup utility (cluster names, etc.). The script imports those dictionaries
directly, so you can safely tweak the file without touching `spezi_setup.py`.

## Usage

```bash
python tools/spezi_setup/spezi_setup.py --help
```

Common flow:

* **Local KIND environment**
  ```bash
  python tools/spezi_setup/spezi_setup.py local --force-recreate-kind  # optional to rebuild the cluster
  ```

The script expects to be executed from the repository root because it reads
files from `config/`, `local-dev/`, and `tofu/`. See `python tools/spezi_setup/spezi_setup.py --help`
for the full list of options.
