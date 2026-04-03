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
- **Build system**: `build.zig` replaces CMake. Build options passed via `@import("opts")`.
- **Public API** (`src/root.zig`): Idiomatic Zig — error unions, optionals, slices. No `nfdresult_t`, no global error strings, no manual `FreePath`. All types are `pub`. Allocator passed by caller.
- **GTK backend** (`src/gtk.zig`): Fully ported. Uses `@cImport("gtk/gtk.h")`. Window parenting works for X11 (Wayland parenting partial — sets display/screen but xdg-foreign export not wired up).
- **Portal backend** (`src/portal.zig`): Fully ported. Talks to `org.freedesktop.portal.FileChooser` via D-Bus. `DBusError` has bitfields so a compatible `extern struct` is defined in the file. X11 window handle serialization works. Wayland handle serialization not yet implemented.
- **Demo program** (`src/main.zig`): `zig build run` (GTK) or `zig build run -Dportal=true` (portal). Uses `@import("znfd")`.

- **Windows backend** (`src/win32.zig`): Fully ported. Pure Zig COM interface definitions (no `@cImport`). Uses `IFileOpenDialog`/`IFileSaveDialog` via manually defined vtables. UTF-8↔UTF-16 conversion handled internally. Links `ole32`, `shell32`.

### Not Yet Ported
- **macOS backend** (`src/cocoa.zig` — does not exist yet): Reference is `src/nfd_cocoa.m`. Uses Cocoa `NSSavePanel`/`NSOpenPanel`.

### Features Not Yet Ported (all platforms)
- Case-insensitive file filters (original converts `"png"` to `"[pP][nN][gG]"` glob patterns)
- Auto-append extension on save (GTK/portal)
- Portal version check for folder picker (requires interface >= v3)
- Wayland xdg-foreign surface export for window parenting (GTK + portal backends)

## Architecture

```
src/root.zig          — Public API + comptime backend dispatch
src/gtk.zig           — Linux GTK3 backend (via @cImport)
src/portal.zig        — Linux xdg-desktop-portal backend (via @cImport of dbus/dbus.h)
src/win32.zig         — Windows backend (TODO)
src/cocoa.zig         — macOS backend (TODO)
src/main.zig          — Demo/test program
```

Backend selection is comptime via `builtin.os.tag` and build options:
```zig
const backend = switch (builtin.os.tag) {
    .linux => if (opts.portal) @import("portal.zig") else @import("gtk.zig"),
    .windows => @import("win32.zig"),
    .macos => @import("cocoa.zig"),
    else => @compileError("Unsupported OS"),
};
```

Build options are passed to source via `b.addOptions()` → `@import("opts")`.

## Public API Shape

```zig
pub fn init() Error!void
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
zig build                    # Build library + demo (GTK backend on Linux)
zig build run                # Run demo
zig build -Dportal=true      # Use xdg-desktop-portal instead of GTK
zig build run -Dportal=true  # Run demo with portal backend
```

## Key Implementation Notes

- **DBusError workaround** (portal.zig): D-Bus's `DBusError` struct has C bitfields that Zig can't represent via `@cImport`. A compatible `extern struct` is defined manually and cast via `@ptrCast`.
- **GDK_IS_X11_DISPLAY workaround** (gtk.zig): The GDK type-check macros call extern functions at comptime which Zig can't do. Runtime `g_type_check_instance_is_a()` is used instead.
- **GSList traversal** (gtk.zig): GTK returns `GSList*` for multi-select. Traversed via `node.*.data` / `node.*.next` since it's a `[*c]` pointer.
- **Dynamic linkage**: The library and demo use `.linkage = .dynamic` because system libs (GTK, D-Bus) are shared libraries.

## C Reference Files

The original C/C++ implementations are still in the repo as reference:
- `src/nfd_win.cpp` — Windows (COM IFileDialog)
- `src/nfd_cocoa.m` — macOS (Cocoa NSSavePanel/NSOpenPanel)
- `src/nfd_gtk.cpp` — Linux GTK3
- `src/nfd_portal.cpp` — Linux xdg-desktop-portal over D-Bus
- `src/nfd_linux_shared.hpp` — Shared Wayland/X11 code
- `src/include/nfd.h` — Original C API (reference for what functions exist)
- `src/include/nfd.hpp` — C++ wrapper (not relevant to Zig port)

## Platform Dependencies

- **Windows:** Windows SDK (ole32, uuid, shell32)
- **macOS:** AppKit framework (+ UniformTypeIdentifiers on macOS 11+)
- **Linux GTK:** libgtk-3-dev, optionally libwayland-dev + wayland-scanner
- **Linux Portal:** libdbus-1-dev
