# QOpen 2.3 Design

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
QOpen.qml  <--- watches --->  ~/.config/qopen/config.json
        |
        | argv only
        v
bin/qopen
  |-- validate schema and targets
  |-- lock + backup + atomic replace
  `-- dispatch through Omarchy launch helpers
```

The split is deliberate. QML is responsible for presentation, search and
navigation. Python is responsible for persistence and execution. Resource
values are never interpolated into a shell command by QML.

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

- A file lock serializes mutations.
- Writes go to a same-directory temporary file and use atomic replacement.
- The previous catalog is copied to `config.json.bak` before mutation.
- The complete schema is validated before every write.
- Commands are represented as argument arrays.
- File and project paths expand `~` and environment variables only in the
  backend.
- Directory browsing is read-only, bounded to 1000 entries and does not create
  file-system monitors.
- Destructive removal always asks for confirmation.

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
