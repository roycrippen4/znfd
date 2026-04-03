# Native File Dialog Extended (Zig Port)

A Zig port of [btzy/nativefiledialog-extended](https://github.com/btzy/nativefiledialog-extended), which is itself based on [mlabbe/nativefiledialog](https://github.com/mlabbe/nativefiledialog).

This is **not** the original software. This is a port of Bernard Teo's Native File Dialog Extended library from C/C++ to Zig. All credit for the original design and implementation goes to:

- **Bernard Teo** ([@btzy](https://github.com/btzy)) — Native File Dialog Extended
- **Michael Labbe** ([@mlabbe](https://github.com/mlabbe)) — original Native File Dialog

The original library is licensed under the Zlib license. This port is licensed under the GPL (see [LICENSE](LICENSE)).

---

A small library that portably invokes native file open, folder select and file save dialogs. Write dialog code once and have it pop up native dialogs on all supported platforms.

Features:

- Support for Windows, macOS, and Linux (GTK, portal)
- Friendly names for filters (e.g. `Images (png,jpg)`) on platforms that support it
- Support for setting a default folder path
- Support for setting a default file name (e.g. `untitled.png`)
- Support for setting a parent window handle so that the dialog stays on top
- Consistent UTF-8 support on all platforms
- Support for multiple selection (for file open and folder select dialogs)
- Pure Zig — no C/C++ source files, no `@cImport` on Windows/macOS

# Installation

Add `znfd` as a dependency:

```bash
zig fetch --save https://github.com/roycrippen4/znfd/archive/refs/tags/v0.0.3.tar.gz
```

Then add it to your `build.zig`:

```zig
const znfd = b.dependency("znfd", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("znfd", znfd.module("znfd"));
```

# Usage

Then in your code:

```zig
const znfd = @import("znfd");

pub fn main() !void {
    try znfd.init();
    defer znfd.deinit();

    const path = try znfd.open_dialog(std.heap.page_allocator, .{
        .filter_list = &.{
            .{ .name = "Images", .spec = "png,jpg,gif" },
        },
    });

    if (path) |p| {
        defer std.heap.page_allocator.free(p);
        std.debug.print("Selected: {s}\n", .{p});
    }
}
```

See `src/main.zig` for a full demo that exercises every API function.

## API

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

## File Filter Syntax

Files can be filtered by file extension groups:

```zig
const filters = &[_]znfd.FilterItem{
    .{ .name = "Source code", .spec = "c,cpp,cc" },
    .{ .name = "Headers", .spec = "h,hpp" },
};
```

A file filter is a pair of strings comprising the friendly name and the specification (multiple file extensions are comma-separated).

A wildcard filter is always added to every dialog.

_Note: On macOS, the file dialogs do not have friendly names and there is no way to switch between filters, so the filter specifications are combined. The filter specification is also never explicitly shown to the user. This is usual macOS behaviour and users expect it._

# Building

```
zig build
zig build run    # run the demo
```

Build options:

- `-Dportal=true` — Use xdg-desktop-portal instead of GTK on Linux
- `-Dx11=false` — Disable X11 support on Linux
- `-Dwayland=false` — Disable Wayland support on Linux
- `-Dappend-extension=true` — Auto-append file extension in SaveDialog on Linux
- `-Dcase-sensitive-filter=true` — Make filters case sensitive on Linux

## Dependencies

### Linux

#### GTK (default)

`libgtk-3-dev`

#### Portal

`libdbus-1-dev`

### macOS

AppKit framework (ships with Xcode / Command Line Tools).

**Note:** The macOS backend compiles but has not been tested on real hardware.

### Windows

Windows SDK (ole32, shell32).

# Platform-specific Quirks

### Windows

- The `default_path` option is only respected if there is no recently used folder available. If there is a recently used folder, the dialog opens to that folder instead.
- Relative paths are not supported.

### macOS

- Uses the deprecated `setAllowedFileTypes:` API for file filtering. This still works on current macOS but may need updating if Apple removes it in a future release.

### Linux

- Window parenting does not work on XWayland.
- On Linux, the file extension is appended (if missing) when the user presses "Save". The appended file extension will remain visible even if the user then cancels an overwrite prompt.
- Linux file filters are case-insensitive by default (via a glob pattern hack). Use `-Dcase-sensitive-filter=true` for case-sensitive filtering.

## Using xdg-desktop-portal on Linux

On Linux, you can use the portal implementation instead of GTK, which will open the "native" file chooser selected by the OS or customized by the user. The user must have `xdg-desktop-portal` and a suitable backend installed (this comes pre-installed with most common desktop distros).

Build with `-Dportal=true`.

# Known Limitations

- GTK dialogs don't set the existing window as parent, so if users click the existing window while the dialog is open then the dialog will go behind it.
- This library does not dispatch calls to the UI thread. Call from an appropriate UI thread.

# Credit

This is a Zig port of [Native File Dialog Extended](https://github.com/btzy/nativefiledialog-extended) by Bernard Teo ([@btzy](https://github.com/btzy)), which is based on [Native File Dialog](https://github.com/mlabbe/nativefiledialog) by Michael Labbe ([@mlabbe](https://github.com/mlabbe)).

# License

This port is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for the full text.

The original Native File Dialog Extended is licensed under the Zlib license.

# AI Usage

This port was developed with the assistance of Claude Code (Anthropic). AI was used for code generation, build system migration, and documentation throughout the porting process.
