# Changelog

All notable user-facing changes to QOpen are documented here.

## [2.4.2] - 2026-08-28

### Added

- Root `AGENTS.md` collaboration contract for AI agents and human maintainers,
  covering architecture, branch promotion, testing, installation, upgrades,
  releases and marketplace validation.
- Regression coverage that preserves the critical collaboration and release
  workflow contracts documented for future contributors.

### Changed

- The development guide now links to the AI collaboration contract, with the
  branch, testing, installation and release rules consolidated for reuse.

## [2.4.1] - 2026-08-28

### Added

- Root `preview.png` for the Omarchy Plugin Marketplace, generated from the
  documented QOpen interface screenshot.
- Release-contract coverage that binds Git release tags to the manifest version.

### Changed

- The complete marketplace-ready repository state is now published as one
  traceable patch release.
- The maintainer workflow now promotes changes through `dev`, `uat` and `main`
  before tagging a release.
- GitHub CI actions now target the current Node 24-based major versions.

## [2.4.0] - 2026-08-28

### Added

- Validated recovery from `config.json.bak`, with the invalid catalog preserved
  as a private timestamped snapshot.
- `qopen recover` and `qopen fix-permissions` maintenance commands.
- Native JSON API actions for favorites, deletion, recovery and permission repair.
- Backend-validated catalog reads for the QML interface.
- Configuration, backup and lock permission checks in `qopen --doctor`.
- Regression coverage for CRUD conflicts, recovery, permissions, unsafe input and
  command argument round trips.

### Changed

- Favorite and delete actions stay inside QOpen instead of invoking interactive
  CLI menus.
- Command and editor argument arrays use POSIX-safe display quoting when edited.
- QOpen closes the first-party Omarchy Menu before taking exclusive keyboard focus.
- Path browsing ignores stale responses and queues the most recent navigation request.
- Operation status messages remain visible longer and distinguish failures visually.

### Fixed

- Preserved command arguments containing spaces and single quotes after editing.
- Rejected HTTP(S) URLs without a host, embedded URL credentials, unsafe SSH
  option-like targets and control characters.
- Added visible failure feedback for target checks, clipboard reads and clipboard writes.
- Prevented a completed directory request from replacing a newer PathPicker state.
- Prevented schema-invalid but syntactically valid JSON from being rendered as a catalog.
- Deferred the initial catalog process until Omarchy Shell has injected the plugin directory,
  avoiding an erroneous `/bin/qopen` launch during asynchronous plugin loading.

## [2.3.0] - 2026-08-28

### Added

- Embedded `PathPicker.qml` for files and project directories.
- Read-only `api browse-path` backend endpoint using bounded `os.scandir()`
  snapshots.
- Keyboard path navigation, hidden-entry toggle and typed directory paths.
- Detailed public installation, configuration and maintenance documentation.

### Changed

- File and project browsing now stays inside the QOpen surface.
- Directory mode filters out files; file mode shows both directories and files.
- Multi-file development updates use one shell restart after synchronization.

### Removed

- Qt `FileDialog` and `FolderDialog` integration.
- GTK/GIO/GVFS file-dialog dependency from the shared Omarchy Shell process.
- The dedicated Hyprland floating-window rule required by native dialogs.

### Fixed

- Prevented native file-dialog crashes from terminating Quickshell.
- Correctly transfers focus from the typed path field to the directory list.
- Keeps keyboard selection and the accepted file path synchronized.
- Prevented path-picker selection shortcuts from leaking into editor save keys.

## [2.2.0] - 2026-08-28

### Added

- Initial Qt file and directory chooser integration.
- Local file URL decoding and automatic name inference.

### Deprecated

- Native dialog integration was removed in 2.3.0 after reproducible
  Qt/GTK/GVFS crashes in the shared shell process.

## [2.1.0] - 2026-08-28

### Added

- Native single-page resource editor.
- Type-aware project, file, web, TUI, command and SSH fields.
- Clipboard paste button and inline target checks.
- Backend JSON API for create, update, delete and validation.

### Fixed

- Project resources now always expose a directory target field.
- Standard text fields support normal Wayland clipboard paste.

## [2.0.0] - 2026-08-28

### Added

- Standard Omarchy Shell plugin manifest.
- Searchable QML menu, collections, favorites and inline actions.
- Optional QOpen bar widget.
- Curated frontend and React ecosystem resource groups.

## [1.1.0] - 2026-08-28

### Added

- Python resource launcher and guided Omarchy menu flows.
- Locked and atomic JSON persistence with automatic backup.
- Web, file, project, TUI, command and SSH resource types.
