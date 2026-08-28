# Changelog

All notable user-facing changes to QOpen are documented here.

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
