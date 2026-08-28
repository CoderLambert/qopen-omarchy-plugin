# QOpen 2.5.1 Design

## Product boundary

QOpen is a personal resource catalog, not another application index. Omarchy
and launchers such as OmaLauncher already index installed applications and
shell commands well. QOpen owns the resources that do not fit that model:

- curated web references and documentation;
- project directories and files;
- terminal applications and explicit commands;
- SSH destinations;
- personal grouping, descriptions and favorites.

## Architecture

```text
Omarchy menu / bar
        |
        v
QOpen.qml
        |
        | bounded argv / one-line JSON
        v
BoundedProcess.qml
        |
        v
bin/qopen
  |-- descriptor-anchored state validation
  |-- directory FD lock + backup + atomic replace
  |-- bounded reads, responses and helper processes
  `-- dispatch through Omarchy launch helpers
        |
        v
~/.config/qopen/config.json
```

The split is deliberate. QML is responsible for presentation, search and
navigation. Python is responsible for catalog reads, schema validation,
persistence and execution. Resource values are never interpolated into a shell
command by QML.

## Interaction model

The main surface has three stable regions:

1. Search and global add action in the header.
2. Collections with live counts in the sidebar.
3. A resource list with favorite, copy, edit and remove actions.

Search is global within the selected collection and includes name,
description, id, type, group, target and command. Favorites are both a
collection and a sort priority inside every collection.

Add and edit use a native single-page `ResourceEditor.qml` surface. Type-aware
fields stay visible together, paths accept normal paste, and the user can
review the complete item before saving. The editor sends JSON over an argv
boundary to the backend API; it never writes the catalog itself. The guided
Omarchy menu flow remains available through the CLI as a compatibility path.
File and project fields use an embedded `PathPicker.qml` surface. It asks the
Python backend for bounded, sorted directory listings and never loads Qt's
native file-dialog integration. This is intentional because QOpen shares the
long-running Quickshell process with the rest of Omarchy Shell: failures in
GTK/GIO/GVFS must not be able to terminate the shell. File mode lists files and
directories; project mode lists directories only.

## Data model

The catalog remains version 1 for compatibility:

```json
{
  "version": 1,
  "defaults": { "editor": "nvim", "webMode": "app" },
  "items": [
    {
      "id": "react",
      "name": "React Docs",
      "type": "web",
      "group": "frameworks",
      "target": "https://react.dev/learn",
      "favorite": true
    }
  ]
}
```

Supported item types are `web`, `file`, `project`, `tui`, `command` and
`ssh`. IDs are stable keys; names and groups are user-facing metadata.

## Persistence and safety

- Every state-directory component is opened from `/` with directory
  descriptors, `O_DIRECTORY` and `O_NOFOLLOW`; the final directory must be
  owned by the current user and not writable by another account.
- The trusted state-directory descriptor itself is locked with nonblocking
  `flock` and a monotonic deadline; no pathname lock file is needed.
- Configuration and backup files use `O_NOFOLLOW`, `O_NONBLOCK` and descriptor
  metadata checks that reject symlinks, hard links and non-regular files.
- Reads are capped at 1 MiB and detect in-place changes before accepting JSON.
- Writes go to a descriptor-relative same-directory temporary file, `fsync`
  the file, atomically replace with `src_dir_fd`/`dst_dir_fd`, then `fsync` the
  directory.
- The same validated bytes used for a mutation are retained as
  `config.json.bak`; the backup is never reopened through an ordinary path.
- Backups are validated before recovery, and the replaced invalid catalog is
  retained as a private timestamped snapshot.
- The default state directory uses `0700`; state files use `0600`. Custom
  `QOPEN_CONFIG` parent permissions are validated but never changed.
- The complete schema is validated before every write.
- API input, producer output, helper output, item count and directory scan work
  all have explicit limits.
- QML has no catalog `FileView` and no `StdioCollector`. Backend responses use
  one compact JSON line, a second consumer-side limit and real TERM-to-KILL
  process deadlines.
- Commands are represented as argument arrays and use lossless POSIX quoting
  when displayed for editing.
- File and project paths expand `~` and environment variables only in the
  backend.
- Directory browsing is read-only, bounded to 1000 entries and does not create
  file-system monitors. Request ids prevent stale directory responses from
  replacing newer navigation state.
- Destructive removal always asks for confirmation.

These controls prevent pathname redirection, special-file blocking, unbounded
retention and writes outside the trusted state directory. They do not claim to
prevent a deliberately malicious process running as the same Unix uid from
directly replacing valid user-owned application code or data; that process
already has the user's filesystem authority.

## Integration

The plugin id is `qopen.launcher` and its manifest exposes `menu` and
`bar-widget` entry points. It can be summoned with:

```bash
omarchy-shell shell toggle qopen.launcher '{}'
omarchy-shell shell toggle qopen.launcher '{"favorites":true}'
omarchy-shell shell toggle qopen.launcher '{"group":"projects"}'
```

The long-standing `~/.local/bin/qopen` command remains a compatibility entry
point and delegates to the installed plugin backend when available.

## Deliberate non-goals

- Re-indexing every installed desktop application.
- Replacing Omarchy's command or plugin search.
- Storing passwords, SSH keys or other secrets.
- Executing arbitrary command strings from QML.

## Future extensions

- Optional provider integration for OmaLauncher search results.
- Import/export presets for reusable curated collections.
- Resource duplication and reusable item templates.
- Usage-based ranking, while preserving explicit favorites.
