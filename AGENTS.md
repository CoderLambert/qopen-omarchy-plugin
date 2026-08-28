# QOpen AI Collaboration Guide

This file is the operating contract for AI agents and human maintainers working
in this repository. Read it before changing code, documentation, branches,
installation state, tags, releases, or the Omarchy Shell runtime.

The user documentation lives in `README.md` and `README.zh-CN.md`. Architectural
decisions and incident history live in `DESIGN.md` and `DEVELOPMENT.md`. This
guide turns those decisions into repeatable development rules.

## 1. Project mission and boundaries

QOpen is a curated personal resource launcher for Omarchy. It manages web
references, files, project directories, TUI tools, commands, and SSH targets.
It complements the first-party Omarchy Menu; it does not replace application
search, system setup, package management, or the stock menu.

When no personal catalog exists, QOpen creates a small generic starter catalog.
Starter changes must remain free of maintainer-specific paths and credentials,
must never seed an existing catalog, and must not invent a generic SSH target.

Non-goals:

- Do not scan the complete home directory or application database.
- Do not store passwords, access tokens, SSH private keys, or other secrets.
- Do not concatenate resource values into shell command strings.
- Do not modify Omarchy first-party files under `/usr/share/omarchy`.
- Do not introduce Qt native file dialogs, `QtQuick.Dialogs`, GTK/GIO/GVFS
  pickers, or another native picker into the shared Quickshell process.

## 2. Rules that must never be bypassed

1. Preserve user data. The personal catalog is
   `~/.config/qopen/config.json`; it is not source code and must never be added
   to this repository.
2. Never run automated CRUD tests against the real personal catalog. Set
   `QOPEN_CONFIG` to an isolated temporary path.
3. Preserve argv boundaries. QML and Python must launch commands as argument
   arrays; do not use `shell=True`, `eval`, or string interpolation into a
   shell.
4. Preserve atomic persistence: validate the complete schema, lock, back up,
   write a same-directory temporary file, `fsync`, and atomically replace.
5. Treat QOpen as code running unsandboxed inside the long-lived Omarchy Shell
   process. Avoid native integrations that can terminate Quickshell.
6. Do not directly commit feature work to `main`, `uat`, or `dev`. Use a task
   branch and a pull request. Fast-forward alignment of long-lived branches
   after a release is the only maintenance exception and requires explicit
   maintainer authorization.
7. Do not move, overwrite, or recreate an already published Git tag.
8. Preserve unrelated and uncommitted user changes. Stop if a requested edit
   overlaps dirty files and cannot be safely isolated.
9. Do not delete branches, releases, backups, plugins, or user configuration
   unless the user explicitly requests that destructive action.
10. Do not publish a tag, GitHub Release, marketplace submission, or upstream
    issue without explicit release or publication authorization.

## 3. Start-of-task checklist

Run these read-only checks before editing:

```bash
git status --short --branch
git log --oneline --decorate -8
git branch -a
git fetch --prune origin
gh pr list --state open
```

Then determine the task class:

| Task | Starting branch | Task branch | PR target |
| --- | --- | --- | --- |
| Feature, refactor, normal fix | `dev` | `feature/<name>` or `fix/<name>` | `dev` |
| Documentation or CI maintenance | `dev` | `docs/<name>` or `chore/<name>` | `dev` |
| UAT promotion | `dev` | no new code branch | `uat` |
| Stable release promotion | `uat` | no new code branch | `main` |
| Production hotfix | `main` | `hotfix/<name>` | `main` |

Before creating a branch, confirm that neither the local nor remote name is
already in use. Never invent a different starting point when the requested
branch model is clear.

## 4. Long-lived branch model

The required promotion path is:

```text
feature/* -> dev -> uat -> main -> vX.Y.Z -> GitHub Release
```

- `dev` is the integration branch. New work begins here and returns here by PR.
- `uat` is the acceptance branch. It receives only a tested `dev` promotion.
- `main` is the stable install and release branch. It receives only accepted
  `uat` content.
- The public Omarchy install/update command follows repository default branch
  `main`, so `main` must always remain releasable.

Promotion rules:

1. Feature PRs must target `dev`, not `main`.
2. Wait for backend and QML CI before merging.
3. Promote `dev` to `uat` with a dedicated PR and perform real Omarchy runtime
   acceptance there.
4. Freeze new `dev` merges while the exact UAT snapshot is being promoted.
5. Promote `uat` to `main` with a dedicated release PR.
6. Wait for the final `main` CI, then tag that exact commit.
7. After release, fast-forward `uat` and `dev` to the released `main` only when
   no newer commits make the fast-forward impossible. Never force-push.

For a production hotfix, branch from `main`, merge the fix to `main`, publish a
patch release, then propagate the released commit back to `uat` and `dev`.

## 5. Repository map

| Path | Responsibility |
| --- | --- |
| `manifest.json` | Omarchy plugin identity, version, kinds, and entry points |
| `QOpen.qml` | Main menu, search, collections, routing, mutations, and status |
| `ResourceEditor.qml` | Type-aware add/edit form and validation feedback |
| `PathPicker.qml` | Embedded bounded local file/directory browser |
| `BoundedProcess.qml` | One-line bounded backend transport and process deadlines |
| `BarWidget.qml` | Optional Omarchy bar entry point |
| `bin/qopen` | Python CLI, JSON API, validation, persistence, and launching |
| `tests/test_backend.py` | Backend, API, safety, and QML regression tests |
| `tests/test_docs.py` | Bilingual docs, preview, version, and tag contract tests |
| `.github/workflows/ci.yml` | Backend and QML syntax CI for branches, PRs, and tags |
| `README.md` | English user documentation |
| `README.zh-CN.md` | Chinese user documentation with matching structure/examples |
| `DESIGN.md` | Stable product and architecture decisions |
| `DEVELOPMENT.md` | Development record, incident evidence, and release process |
| `CHANGELOG.md` | Versioned user-facing changes |
| `docs/assets/qopen-usage.png` | README interface screenshot |
| `preview.png` | Marketplace root preview; must match the documented screenshot |
| `AGENTS.md` | This AI/human collaboration contract |

## 6. Architecture ownership

### QML owns

- visual presentation and theme tokens;
- keyboard, mouse, focus, selection, and overlay state;
- search, sorting, grouping, and favorites presentation;
- JSON payload construction;
- process invocation using argv arrays.

### Python owns

- URL, SSH, path, id, and command validation;
- catalog schema validation and normalized machine API output;
- directory enumeration and its 1000-entry bound;
- locking, backup, recovery, permissions, and atomic writes;
- dispatch through Omarchy helpers or safe `xdg-*` fallbacks.

Do not duplicate backend validation as the sole authority in QML. QML may give
early feedback, but every write and launch must still be validated by Python.

## 7. Implementation guidance

### QML changes

- Keep process commands as arrays.
- Route every backend response through `BoundedProcess.qml`; do not use
  `StdioCollector` or direct catalog `FileView` access.
- Keep all file selection inside `PathPicker.qml`.
- Preserve request ids and stale-response rejection in path browsing.
- Preserve explicit error feedback for clipboard, target checks, and writes.
- Preserve the behavior that closes `omarchy.menu` before QOpen takes exclusive
  keyboard focus.
- Compile every QML entry/component after edits.

### Python changes

- Maintain Python 3.10+ compatibility unless a release explicitly changes the
  requirement.
- Keep machine API output compact JSON and send human diagnostics to the
  appropriate stream.
- Keep catalog, backup and recovery operations descriptor-anchored to one
  trusted state directory. Do not reintroduce ordinary pathname reads,
  `shutil.copy2`, pathname `chmod`, or a pathname lock file.
- Enforce producer-side byte limits and monotonic deadlines before data reaches
  QML. Every captured helper subprocess must have bounded output.
- Create starter resources only when the catalog is missing; preserve existing
  catalogs byte-for-byte during reads and upgrades.
- Validate the complete catalog before writes, recovery, and rendering.
- Keep the default state directory private (`0700`) and configuration, backup
  and invalid recovery snapshots private (`0600`). Never change the parent
  directory permissions of a custom `QOPEN_CONFIG`.
- Use `subprocess` argv lists and bounded timeouts where a subprocess can wait.
- Expand paths only in the backend; do not commit machine-specific absolute
  paths.

### Documentation changes

- Keep English and Chinese README section order and executable examples aligned.
- Update both README files when changing commands, shortcuts, requirements,
  versions, screenshots, or troubleshooting behavior.
- Record user-visible changes in `CHANGELOG.md`.
- Record durable architecture decisions or incident evidence in
  `DEVELOPMENT.md` or `DESIGN.md`, not only in a PR description.

## 8. Required automated validation

Run the complete local gate before every PR:

```bash
python -m json.tool manifest.json >/dev/null
python -m py_compile bin/qopen
python -m unittest discover -s tests -v
omarchy plugin validate .
```

Compile QML with the same strategy as CI:

```bash
qopen_qmlcachegen=$(find /usr/lib/qt6 -type f -name qmlcachegen -print -quit)
test -n "$qopen_qmlcachegen"
qopen_qml_output=$(mktemp -d)
for qopen_qml_file in BoundedProcess.qml QOpen.qml ResourceEditor.qml PathPicker.qml BarWidget.qml; do
  "$qopen_qmlcachegen" --only-bytecode \
    -o "$qopen_qml_output/$qopen_qml_file.qmlc" "$qopen_qml_file"
done
```

Also run:

```bash
git diff --check
git status --short --branch
```

Do not claim completion when a required check is skipped. State exactly which
checks ran, which did not, and why.

## 9. Isolated backend and CRUD testing

Never use the real personal catalog for automated mutation tests. Use an
isolated path:

```bash
qopen_test_dir=$(mktemp -d)
QOPEN_CONFIG="$qopen_test_dir/config.json" ./bin/qopen add project \
  --name "Fixture" \
  --target "$qopen_test_dir"
QOPEN_CONFIG="$qopen_test_dir/config.json" ./bin/qopen --list
QOPEN_CONFIG="$qopen_test_dir/config.json" ./bin/qopen --doctor
```

Keep destructive cleanup scoped to the exact temporary directory. Do not use
home-directory globs or unresolved variables as deletion targets.

At minimum, backend changes must cover:

- valid and invalid schema handling;
- CRUD conflicts and atomic backup behavior;
- command argument round trips, including spaces and quotes;
- unsafe URL, SSH, and control-character rejection;
- permission audit and repair;
- symlink, hard-link, FIFO and non-regular state-file rejection;
- held-lock, oversized-response and concurrent pathname-race behavior;
- recovery with valid and invalid backups;
- project/file browser filtering and stale request behavior.

## 10. Omarchy runtime acceptance

Runtime testing is required for changes to QML, routing, focus, launch behavior,
plugin loading, or installation. Automated tests alone cannot prove behavior
inside the shared Quickshell process.

Verify manually:

- the menu opens and search receives focus;
- Omarchy Menu and QOpen do not remain open together;
- all six resource types expose the correct fields;
- project browsing shows directories only;
- file browsing accepts files and directories for navigation;
- paste, Check, add, edit, favorite, copy, and confirmed delete behave correctly;
- cancel does not change the catalog hash;
- theme tokens remain readable in the active theme;
- no native GTK/GVFS file picker appears.

After the test window, inspect runtime health:

```bash
pgrep -a quickshell
journalctl --user --since "15 minutes ago" --no-pager | \
  rg -i 'qopen|quickshell|qml|failed|error|warning'
coredumpctl list quickshell --since "15 minutes ago" --no-pager
```

Separate unrelated desktop warnings from QOpen/Quickshell failures. Do not claim
causality without timing, logs, and reproducible evidence.

## 11. Installation and developer synchronization

### Public Git installation

```bash
omarchy plugin add \
  https://github.com/CoderLambert/qopen-omarchy-plugin.git \
  --enable
```

The installed checkout is expected at:

```text
~/.config/omarchy/plugins/qopen.launcher/
```

The personal catalog remains separate at:

```text
~/.config/qopen/config.json
```

### Testing a pushed development commit locally

Prefer isolated backend tests first. When an actual Omarchy runtime test is
required, the installed plugin must be a clean Git checkout:

```bash
qopen_installed="$HOME/.config/omarchy/plugins/qopen.launcher"
qopen_task_branch="feature/example"
git -C "$qopen_installed" status --short --branch
git -C "$qopen_installed" fetch origin "$qopen_task_branch"
git -C "$qopen_installed" switch --detach FETCH_HEAD
omarchy plugin validate "$qopen_installed"
omarchy restart shell
```

Complete the multi-file Git switch before restarting the shell. Do not copy
files one at a time while relying on hot reload; earlier multi-file intermediate
states correlated with Quickshell crashes.

After testing, restore the stable installation:

```bash
git -C "$qopen_installed" switch main
git -C "$qopen_installed" pull --ff-only origin main
omarchy plugin validate "$qopen_installed"
omarchy restart shell
```

Before and after installation work, compare the personal catalog hash when the
task should not change data:

```bash
sha256sum "$HOME/.config/qopen/config.json"
```

Never edit `/usr/share/omarchy` and never replace
`~/.config/qopen/config.json` as part of a plugin-code synchronization.

## 12. User upgrades and diagnostics

Normal Git-managed upgrade:

```bash
omarchy plugin update qopen.launcher
```

Non-interactive upgrade after reviewing/trusting the release:

```bash
omarchy plugin update qopen.launcher --yes
```

Then verify:

```bash
~/.config/omarchy/plugins/qopen.launcher/bin/qopen --version
~/.config/omarchy/plugins/qopen.launcher/bin/qopen --doctor
```

Omarchy updates the default branch `HEAD`; it does not pin installations to the
latest tag and may not fetch tag objects. Keep `main` stable. Fetch tags
explicitly only when verifying release metadata:

```bash
git -C "$HOME/.config/omarchy/plugins/qopen.launcher" fetch --tags origin
```

Plugin removal does not delete the personal catalog:

```bash
omarchy plugin remove qopen.launcher --yes
```

Do not run removal unless explicitly requested.

## 13. Versioning, tags, releases, and marketplace updates

All public version surfaces must match:

```text
manifest.json version
= bin/qopen VERSION
= README.md current release
= README.zh-CN.md current release
= newest CHANGELOG.md section
= Git tag v<version>
= GitHub Release tag
```

Release checklist:

1. Update every public version surface and the changelog on a release task
   branch.
2. Run the complete automated gate and UAT runtime checks.
3. Promote the accepted commit to `main` by PR.
4. Wait for final `main` CI.
5. Create an annotated tag on the exact `main` commit.
6. Push the tag and wait for tag CI. `tests/test_docs.py` rejects a tag whose
   name does not equal `v<manifest version>`.
7. Create a non-draft, non-prerelease GitHub Release from that tag.
8. Verify the tag peeled commit, release URL, and public clone path.
9. Run the marketplace compatibility and security baseline against the same
   exact commit before submitting or promoting the listing.

The marketplace verification is commit-bound. Any later `main` commit may make
the listed snapshot appear as an unverified update. Batch documentation,
preview, CI, and code changes into intentional releases where practical.

## 14. AI collaboration behavior

An AI agent working in this repository must:

- lead with the current branch, intended target branch, and scope;
- distinguish observed evidence from inference;
- communicate non-blocking progress during long test or CI waits;
- use the smallest change that satisfies the task;
- preserve existing style and avoid unrelated cleanup;
- inspect and respect a dirty worktree;
- use pull requests for branch promotion and wait for required CI;
- report exact commands/checks that passed;
- report the final branch, commit, PR, tag, release, and installed version when
  those objects are part of the task;
- leave recoverable backups when changing local installation state;
- ask for authority before destructive operations or external publication not
  already included in the request.

Do not declare success merely because unit tests pass. Match verification to
risk: backend changes require isolated tests, QML changes require compilation,
runtime changes require Omarchy acceptance, and releases require tag and public
repository verification.

## 15. Definition of done

A normal development task is complete only when:

- the implementation matches the product boundary;
- user data and command boundaries remain safe;
- tests cover the regression or new behavior;
- manifest, Python, unit, Omarchy plugin, and QML checks pass as applicable;
- bilingual user documentation remains aligned when behavior changes;
- the task branch is pushed and its PR targets the correct long-lived branch;
- CI passes;
- the handoff identifies any manual Omarchy checks still required.

A release is complete only when:

- UAT is accepted;
- `main` is clean and releasable;
- all version surfaces match;
- the annotated tag points to the exact final `main` commit;
- main and tag CI pass;
- the GitHub Release is public;
- the local Git-managed installation updates successfully without changing the
  personal catalog unexpectedly;
- marketplace validation is rerun for the exact release commit when listing or
  updating the plugin.
