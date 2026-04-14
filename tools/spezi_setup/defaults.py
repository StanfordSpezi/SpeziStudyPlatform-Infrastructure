"""User-editable defaults for the Spezi setup utility.

Adjust the values in `LOCAL_DEFAULTS` to change the argument defaults
without modifying `spezi_setup.py`.
"""

from __future__ import annotations

LOCAL_DEFAULTS: dict[str, object | None] = {
    "kind_cluster_name": "spezi-study-platform",
    "force_recreate_kind": False,
    "local_ip": None,  # auto-detect via helper script when left as None
}
