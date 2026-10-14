"""Tests for uninstall taking the loader back out of monitors.lua.

The script runs for real, against a monitors.lua in a temporary HOME. What is
at stake is somebody's display config, so the contract is: our loader goes,
every other line stays, and a form the script cannot take apart safely leaves
the file exactly as it was.
"""

import os
import subprocess
from pathlib import Path

UNINSTALL = Path(__file__).resolve().parent.parent / "uninstall"

DEFAULT = 'dofile(os.getenv("HOME") .. "/.local/share/omarchy/default/hypr/monitors.lua")\n'
OWN = ('hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0" })\n'
       'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto" })\n')
PATH = "/.config/omarchy/plugins/themo.monitor-profiles/lua/profiles.lua"
INSTALLED = (
    "\n"
    "-- Applies the arrangement of the active profile (themo.monitor-profiles).\n"
    "-- Switch profiles from the bar widget, or with: monitor-profiles use <id|auto>\n"
    'dofile(os.getenv("HOME")\n'
    '  .. "' + PATH + '")\n'
)


def run(tmp_path, text):
    home = tmp_path / "home"
    hypr = home / ".config" / "hypr"
    hypr.mkdir(parents=True, exist_ok=True)
    monitors = hypr / "monitors.lua"
    monitors.write_text(text)
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
               XDG_RUNTIME_DIR=str(tmp_path / "run"))
    result = subprocess.run(["bash", str(UNINSTALL)], env=env,
                            capture_output=True, text=True, timeout=30)
    return result, monitors.read_text(), sorted(p.name for p in hypr.iterdir())


def test_removes_the_loader_install_writes(tmp_path):
    result, text, _ = run(tmp_path, DEFAULT + OWN + INSTALLED)
    assert result.returncode == 0, result.stderr
    assert text == DEFAULT + OWN


def test_removes_a_loader_put_on_one_line(tmp_path):
    loader = 'dofile(os.getenv("HOME") .. "' + PATH + '")\n'
    result, text, _ = run(tmp_path, DEFAULT + OWN + loader)
    assert result.returncode == 0, result.stderr
    assert text == DEFAULT + OWN


def test_removes_a_loader_with_the_paren_on_its_own_line(tmp_path):
    loader = 'dofile(\n  os.getenv("HOME") .. "' + PATH + '"\n)\n'
    result, text, _ = run(tmp_path, DEFAULT + OWN + loader)
    assert result.returncode == 0, result.stderr
    assert text == DEFAULT + OWN


def test_keeps_a_comment_of_the_users_own_above_the_loader(tmp_path):
    mine = "-- my screens, do not touch\n"
    loader = 'dofile(os.getenv("HOME") .. "' + PATH + '")\n'
    result, text, _ = run(tmp_path, DEFAULT + OWN + mine + loader)
    assert result.returncode == 0, result.stderr
    assert text == DEFAULT + OWN + mine


def test_leaves_a_loader_written_through_a_variable_alone(tmp_path):
    """Issue #7: this used to walk back to the Omarchy default dofile( and
    delete everything in between, the user's own hl.monitor lines included."""
    loader = ('local profiles = os.getenv("HOME") .. "' + PATH + '"\n'
              "dofile(profiles)\n")
    original = DEFAULT + OWN + loader
    result, text, files = run(tmp_path, original)
    assert text == original
    assert "by hand" in result.stderr
    assert files == ["monitors.lua"], "no stray backup for a file left unchanged"


def test_nothing_to_do_without_the_loader(tmp_path):
    result, text, _ = run(tmp_path, DEFAULT + OWN)
    assert result.returncode == 0
    assert text == DEFAULT + OWN
    assert "Nothing to remove" in result.stdout
