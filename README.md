
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
- Friendly names for filters (e.g. `C/C++ Source files (*.c;*.cpp)` instead of `(*.c;*.cpp)`) on platforms that support it
- Automatically append file extension on platforms where users expect it
- Support for setting a default folder path
- Support for setting a default file name (e.g. `Untitled.c`)
- Support for setting a parent window handle so that the dialog stays on top
- Consistent UTF-8 support on all platforms
- Support for multiple selection (for file open and folder select dialogs)
- No third party dependencies

# Building

## Zig Build

```
zig build
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
Make sure `libgtk-3-dev` is installed on your system.

#### Portal
Make sure `libdbus-1-dev` is installed on your system.

### macOS
On macOS, the AppKit and UniformTypeIdentifiers frameworks are required.

### Windows
On Windows, the Windows SDK is required (ole32, uuid, shell32).

# Usage

See the `test` directory for example code.

## File Filter Syntax

Files can be filtered by file extension groups:

```C
nfdu8filteritem_t filters[2] = { { "Source code", "c,cpp,cc" }, { "Headers", "h,hpp" } };
```

A file filter is a pair of strings comprising the friendly name and the specification (multiple file extensions are comma-separated).

A wildcard filter is always added to every dialog.

*Note: On macOS, the file dialogs do not have friendly names and there is no way to switch between filters, so the filter specifications are combined (e.g. "c,cpp,cc,h,hpp"). The filter specification is also never explicitly shown to the user. This is usual macOS behaviour and users expect it.*

*Note 2: You must ensure that the specification string is non-empty and that every file extension has at least one character. Otherwise, bad things might ensue (i.e. undefined behaviour).*

*Note 3: On Linux, the file extension is appended (if missing) when the user presses down the "Save" button. The appended file extension will remain visible to the user, even if an overwrite prompt is shown and the user then presses "Cancel".*

*Note 4: Linux is designed for case-sensitive file filters, but this is perhaps not what most users expect. A simple hack is used to make filters case-insensitive. To get case-sensitive filtering, use `-Dcase-sensitive-filter=true`.*

## Using xdg-desktop-portal on Linux

On Linux, you can use the portal implementation instead of GTK, which will open the "native" file chooser selected by the OS or customized by the user. The user must have `xdg-desktop-portal` and a suitable backend installed (this comes pre-installed with most common desktop distros), otherwise `NFD_ERROR` will be returned.

To use the portal implementation, build with `-Dportal=true`.

*Note: The folder picker is only supported on org.freedesktop.portal.FileChooser interface version >= 3, which corresponds to xdg-desktop-portal version >= 1.7.1. `NFD_PickFolder()` will query the interface version at runtime, and return `NFD_ERROR` if the version is too low.*

## Platform-specific Quirks

### Windows
- The `defaultPath` option is only respected if there is no recently used folder available. If there is a recently used folder, the dialog opens to that folder instead.
- Relative paths are not supported.
- Windows virtual folders (e.g. "Documents", "Pictures") are supported via `defaultPath`.

### macOS
- If the macOS deployment target is >= 11.0, the `allowedContentTypes` property is used instead of the deprecated `allowedFileTypes` for file filters. Custom file extensions need to be defined in your `Info.plist`.

### Linux
- Window parenting does not work on XWayland.

# Known Limitations

- No support for Windows XP's legacy dialogs.
- No Emscripten (WebAssembly) bindings.
- GTK dialogs don't set the existing window as parent, so if users click the existing window while the dialog is open then the dialog will go behind it.
- This library does not explicitly dispatch calls to the UI thread. Call NFDe from an appropriate UI thread.

# Credit

This is a Zig port of [Native File Dialog Extended](https://github.com/btzy/nativefiledialog-extended) by Bernard Teo ([@btzy](https://github.com/btzy)), which is based on [Native File Dialog](https://github.com/mlabbe/nativefiledialog) by Michael Labbe ([@mlabbe](https://github.com/mlabbe)).

# License

This port is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for the full text.

The original Native File Dialog Extended is licensed under the Zlib license.

# AI Usage

This port was developed with the assistance of Claude Code (Anthropic). AI was used for code generation, build system migration, and documentation throughout the porting process.
