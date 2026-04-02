# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Zig port of Native File Dialog Extended (NFDe) — a library that portably invokes native file open, save, and folder picker dialogs on Windows, macOS, and Linux. Personal project, not for external distribution.

## Porting Goal

Port the entire codebase from C/C++ to idiomatic Zig. No C ABI compatibility needed. The end result should be a Zig library importable into other Zig projects via `build.zig.zon`.

Key porting decisions:
- Expose an idiomatic Zig API: error unions, optionals, slices — not the C-style `nfdresult_t` + global error string + manual `FreePath` pattern.
- UTF-8 everywhere in the public API; Windows UTF-16 conversion is internal only. The `_U8`/`_N` split goes away.
- Use `defer` for resource cleanup instead of RAII guard objects.
- Zig can call C APIs directly (`@cImport`) for platform SDK calls (COM, Cocoa, GTK, D-Bus).
- Each platform implementation file (`nfd_win.cpp`, `nfd_cocoa.m`, `nfd_gtk.cpp`, `nfd_portal.cpp`) maps roughly 1:1 to a Zig source file. The C/C++ sources are the reference.

## Build Commands

```bash
zig build

# With options (Linux)
zig build -Dportal=true        # xdg-desktop-portal instead of GTK
zig build -Dwayland=false      # disable Wayland support
zig build -Dx11=false           # disable X11 support
zig build -Dappend-extension=true
zig build -Dcase-sensitive-filter=true
```

Tests are GUI programs (they open native dialogs), not automated unit tests. Test binaries are in `zig-out/bin/`.

## Architecture

Each platform has a single implementation file — no shared base class or vtable, just the same C API implemented per-platform:

- `src/nfd_win.cpp` — Windows via IFileDialog (COM). UTF-16 native, UTF-8 conversion layer.
- `src/nfd_cocoa.m` — macOS via Cocoa NSSavePanel/NSOpenPanel.
- `src/nfd_gtk.cpp` — Linux via GTK3.
- `src/nfd_portal.cpp` — Linux via xdg-desktop-portal over D-Bus (alternative to GTK).
- `src/nfd_linux_shared.hpp` — Shared Wayland display/xdg-exporter code used by both Linux backends.
- `src/xdg-foreign-unstable-v1.xml` — Vendored Wayland protocol definition for window handle export.

Public API is in `src/include/nfd.h`. Every dialog function has `_U8` (UTF-8) and `_N` (native encoding) variants, plus `_With` variants that take a struct of arguments. On non-Windows platforms, `_N` is an alias for `_U8`.

## Platform Dependencies

- **Windows:** Windows SDK only (ole32, uuid, shell32)
- **macOS:** AppKit framework (+ UniformTypeIdentifiers on macOS 11+)
- **Linux GTK:** libgtk-3-dev
- **Linux Portal:** libdbus-1-dev
- **Linux Wayland:** libwayland-dev + `wayland-scanner` (protocol XML is vendored in `src/`)

## Error Handling Pattern (C reference — to be replaced)

All dialog functions return `nfdresult_t` (`NFD_OKAY`, `NFD_CANCEL`, `NFD_ERROR`). On error, call `NFD_GetError()` for a description string. Callers must free returned paths with `NFD_FreePath*()`. The Zig port should replace this with error unions and optionals.
