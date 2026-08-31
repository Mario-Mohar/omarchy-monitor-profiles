"""Import bin/monitor-profiles as a module.

The helper is a python3 script without a .py suffix, so it cannot be imported
by name. Loading it through importlib gives the tests the real module, with no
copy of the logic to drift out of step.

Importing it must not touch the user's own configuration, so CONFIG_DIR and the
paths derived from it are redirected into a temporary directory first.
"""

import importlib.util
import os
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parent.parent / "bin" / "monitor-profiles"


def _load():
    spec = importlib.util.spec_from_loader(
        "monitor_profiles",
        importlib.machinery.SourceFileLoader("monitor_profiles", str(BIN)),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def mp(tmp_path, monkeypatch):
    module = _load()
    monkeypatch.setattr(module, "CONFIG_DIR", str(tmp_path / "config"))
    monkeypatch.setattr(module, "CONFIG_PATH", str(tmp_path / "config" / "profiles.json"))
    monkeypatch.setattr(module, "BACKUP_DIR", str(tmp_path / "config" / "backups"))
    monkeypatch.setattr(module, "RUNTIME_DIR", str(tmp_path / "run"))
    monkeypatch.setattr(module, "APPLIED_PATH", str(tmp_path / "run" / "applied"))
    os.makedirs(tmp_path / "run", exist_ok=True)
    return module
