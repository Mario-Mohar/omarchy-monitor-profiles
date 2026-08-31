# Contributing

Thanks for taking the time. This is a small project, so the process is short.

## Getting set up

The plugin is a directory that Omarchy loads. To work on it, clone the
repository and point your installation at the clone:

```bash
git clone https://github.com/Mario-Mohar/omarchy-monitor-profiles.git
cd omarchy-monitor-profiles
./install
```

`install` copies the plugin into `~/.config/omarchy/plugins/themo.monitor-profiles/` and adds
its entry to `shell.json`, backing that file up first. `./uninstall` reverses
both. Neither uses `sudo`, neither downloads anything, and neither writes
outside your own directories.

Only `python3` is required at runtime — the standard library, nothing to
install. `bin/monitor-profiles` talks to Hyprland through `hyprctl`, so a
running Hyprland session is needed to try changes by hand, but not to run the
tests: everything with judgement in it is pure and tested without a compositor.

## Running the checks

The pipeline runs exactly what you can run here, so nothing should surprise you
on a pull request:

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install pytest ruff

python3 .github/scripts/check_plugin.py   # manifest.json and textFormat
ruff check .                              # Python lint
pytest tests/ -v                          # tests
shellcheck install uninstall              # shell scripts
```

QML syntax is checked with `qmllint` (`qt6-declarative-dev-tools`). It also
reports unresolved Quickshell imports, which cannot be resolved outside a
running shell — the pipeline only fails on diagnostics tagged `[syntax]`, and
so should you.

## Two rules worth knowing before you write code

**Every `Text` item declares a `textFormat`.** A `Text` without one keeps Qt's
default `AutoText`, which renders HTML-shaped content as rich text inside the
shell process and can make it load a remote image. Anything that displays a
value read back from Hyprland is a hole. The rule is deliberately blunt — *every* `Text`,
including static labels — so that adding one always forces the decision.
`python3 .github/scripts/check_plugin.py` fails on a missing one.

**`manifest.json` and the code have to agree.** Declared entry points must
exist, every schema entry needs a `defaultValue`, an enum's default must be one
of its own options, and `defaults` may not contain a key the schema does not
describe. The marketplace rejects a submission that gets this wrong; the same
check runs here so you find out in seconds instead of in a submission thread.

## The two places with real judgement in them

**`auto_pick` decides which setup fits the screens that are plugged in.** The
most specific profile wins — the four-screen desk beats the two-screen home
setup, which beats the laptop on its own — and deliberately without depending
on the order the profiles happen to be saved in. A profile with an empty
`match` matches everything and is the last resort.

**`derive_id` turns a typed name into an id.** That id is what `use`, the IPC
target and `monitors.lua` all address, so it has to be plain, stable and
unique, while the name stays whatever was typed. "Büro" becomes `buro`,
"Straße" becomes `strasse`, and a second setup with the same name gets `-2`.

`profiles.json` is expected to be hand-edited, so `sanitize` treats every field
as untrusted and drops bad entries rather than letting them reach Hyprland. Its
contract is that it never raises. One subtlety worth keeping: an explicitly
empty profile list is somebody having deleted their last setup and must be
respected, while a list that merely held nothing usable still falls back to the
shipped ones — that is what makes a mangled file recoverable.

`tests/test_monitor_profiles.py` documents all of it. It loads the helper
through `importlib`, since the script has no `.py` suffix, so there is no copy
of the logic to drift out of step.

## Pull requests

- Branch off `main`. Any branch name is fine.
- Commit messages follow `fix(scope):`, `feat(scope):`, `docs:`, `chore:`.
  The pipeline reads the pull request title's prefix to label it.
- Say what changed and why. If it is user-visible, a screenshot helps.
- The pipeline comments the result on the pull request and updates that comment
  on every push. Green plus not-a-draft gets a `ready-to-merge` label.
- Maintainers can ask for a deeper look by commenting `/claude review` on the
  pull request.

Tests are welcome but not demanded for every change. A bug fix that comes with
the test that would have caught it is the ideal, not the entry fee.

## Reporting something

Use the issue templates. For a bug, the two things that always help are your
Omarchy version and what `bin/monitor-profiles status` prints, together with
`hyprctl monitors -j`.

## Licence

MIT, same as the project. By contributing you agree your work ships under it.
