# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

znfd (Zig Native File Dialog) — a Zig port of [btzy/nativefiledialog-extended](https://github.com/btzy/nativefiledialog-extended). Personal project, not for external distribution. The goal is an idiomatic Zig library importable via `build.zig.zon`.

## User Preferences

- **Snake case everywhere**: Use `snake_case` for all function names, not `camelCase`. This is intentional — helps the user differentiate their code from library code.
- No C ABI compatibility needed. No external consumers.
- Prefer practical, idiomatic Zig solutions over compatibility shims.

## Porting Status

### Completed
- **Build system**: `build.zig` replaces CMake. No build options — Linux backend selection is runtime via `InitOptions`.
- **Public API** (`src/root.zig`): Idiomatic Zig — error unions, optionals, slices. No `nfdresult_t`, no global error strings, no manual `FreePath`. All types are `pub`. Allocator passed by caller. On Linux, both GTK and portal backends are compiled; consumer selects at runtime via `init(.{ .linux_backend = .portal })`.
- **GTK backend** (`src/gtk.zig`): Fully ported. Uses `@cImport("gtk/gtk.h")`. Window parenting works for X11 (Wayland parenting partial — sets display/screen but xdg-foreign export not wired up).
- **Portal backend** (`src/portal.zig`): Fully ported. Talks to `org.freedesktop.portal.FileChooser` via D-Bus. `DBusError` has bitfields so a compatible `extern struct` is defined in the file. X11 window handle serialization works. Wayland handle serialization not yet implemented.

- **Windows backend** (`src/win32.zig`): Fully ported. Pure Zig COM interface definitions (no `@cImport`). Uses `IFileOpenDialog`/`IFileSaveDialog` via manually defined vtables. UTF-8↔UTF-16 conversion handled internally. Links `ole32`, `shell32`.

- **macOS backend** (`src/cocoa.zig`): Fully ported but **untested** (no Mac available). Pure Zig using ObjC runtime directly (`objc_msgSend`, `objc_getClass`, `sel_registerName`). No `@cImport`. Uses `NSOpenPanel`/`NSSavePanel` via typed message-send wrappers. File type filtering via `setAllowedFileTypes:`. Links AppKit framework.

### Features Not Yet Ported (all platforms)
- Case-insensitive file filters (`OpenDialogArgs.case_sensitive_filter` field exists, implementation pending)
- Auto-append extension on save (`SaveDialogArgs.append_extension` field exists, implementation pending)
- Portal version check for folder picker (requires interface >= v3)
- Wayland xdg-foreign surface export for window parenting (GTK + portal backends)

## Architecture

```
src/root.zig          — Public API + runtime backend dispatch (Linux), comptime dispatch (Windows/macOS)
src/gtk.zig           — Linux GTK3 backend (via @cImport)
src/portal.zig        — Linux xdg-desktop-portal backend (via @cImport of dbus/dbus.h)
src/win32.zig         — Windows backend (COM vtables)
src/cocoa.zig         — macOS backend (ObjC runtime)
```

On Linux, both backends are always compiled. Backend selection is runtime via `InitOptions.linux_backend`:
```zig
try znfd.init(.{});                              // default: GTK
try znfd.init(.{ .linux_backend = .portal });     // use xdg-desktop-portal
```

On Windows and macOS, backend selection is comptime via `builtin.os.tag`.

## Public API Shape

```zig
pub fn init(options: InitOptions) Error!void
pub fn deinit() void
pub fn open_dialog(allocator, OpenDialogArgs) Error!?[]const u8
pub fn open_dialog_multiple(allocator, OpenDialogArgs) Error![]const []const u8
pub fn save_dialog(allocator, SaveDialogArgs) Error!?[]const u8
pub fn pick_folder(allocator, PickFolderArgs) Error!?[]const u8
pub fn pick_folder_multiple(allocator, PickFolderArgs) Error![]const []const u8
```

- Returns `null` on cancel, `error.DialogError` on failure, path(s) on success.
- Caller owns returned memory (allocated with the passed-in allocator).
- All arg structs have defaults so callers can use `open_dialog(alloc, .{})`.

## Build Commands

```bash
zig build    # Build library (links both GTK and D-Bus on Linux)
```

## Key Implementation Notes

- **DBusError workaround** (portal.zig): D-Bus's `DBusError` struct has C bitfields that Zig can't represent via `@cImport`. A compatible `extern struct` is defined manually and cast via `@ptrCast`.
- **GDK_IS_X11_DISPLAY workaround** (gtk.zig): The GDK type-check macros call extern functions at comptime which Zig can't do. Runtime `g_type_check_instance_is_a()` is used instead.
- **GSList traversal** (gtk.zig): GTK returns `GSList*` for multi-select. Traversed via `node.*.data` / `node.*.next` since it's a `[*c]` pointer.
- **Dynamic linkage**: The library uses `.linkage = .dynamic` because system libs (GTK, D-Bus) are shared libraries.

## Platform Dependencies

- **Windows:** Windows SDK (ole32, shell32)
- **macOS:** AppKit framework
- **Linux:** libgtk-3-dev, libdbus-1-dev
