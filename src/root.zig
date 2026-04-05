/// Zig Native File Dialog
/// Repository: https://github.com/roycrippen4/znfd
/// License: GPL 3.0
/// Authors: Roy E. Crippen IV, Bernard Teo, Michael Labbe
const std = @import("std");
const builtin = @import("builtin");

const is_linux = builtin.os.tag == .linux;

const linux = if (is_linux) struct {
    const gtk = @import("gtk.zig");
    const portal = @import("portal.zig");
} else struct {};

const native_backend = switch (builtin.os.tag) {
    .windows => @import("win32.zig"),
    .macos => @import("cocoa.zig"),
    else => struct {},
};

/// Internal native character type for platform API calls.
/// Windows uses UTF-16; all other platforms use UTF-8.
const NativeChar = if (builtin.os.tag == .windows) u16 else u8;

pub const LinuxBackend = enum { gtk, portal };

pub const InitOptions = struct {
    linux_backend: LinuxBackend = .gtk,
};

var linux_backend: LinuxBackend = .gtk;

pub const FilterItem = struct {
    name: []const u8,
    spec: []const u8,
};

/// The native window handle type.
pub const WindowHandleType = enum {
    /// Windows: handle is HWND (the Windows API typedefs this to void*)
    windows,
    /// Cocoa: handle is NSWindow*
    cocoa,
    /// X11: handle is Window
    x11,
    /// Wayland: handle is wl_surface*
    wayland,
};

/// The native window handle.
/// If using a platform abstraction framework (e.g. SDL2), obtain the
/// native handle through that framework's API.
pub const WindowHandle = struct {
    type: WindowHandleType,
    handle: *anyopaque,
};

pub const OpenDialogArgs = struct {
    filter_list: []const FilterItem = &.{},
    default_path: ?[]const u8 = null,
    parent_window: ?WindowHandle = null,
    case_sensitive_filter: bool = false,
};

pub const SaveDialogArgs = struct {
    filter_list: []const FilterItem = &.{},
    default_path: ?[]const u8 = null,
    default_name: ?[]const u8 = null,
    parent_window: ?WindowHandle = null,
    append_extension: bool = false,
};

pub const PickFolderArgs = struct {
    default_path: ?[]const u8 = null,
    parent_window: ?WindowHandle = null,
};

pub const Error = error{
    InitFailed,
    DialogError,
};

/// Initialize the platform library (e.g. GTK, COM, D-Bus).
/// Must be called before any dialog functions.
pub fn init(options: InitOptions) Error!void {
    if (is_linux) {
        linux_backend = options.linux_backend;
        return switch (linux_backend) {
            .gtk => linux.gtk.init(),
            .portal => linux.portal.init(),
        };
    }
    return native_backend.init();
}

/// Deinitialize the platform library.
pub fn deinit() void {
    if (is_linux) {
        return switch (linux_backend) {
            .gtk => linux.gtk.deinit(),
            .portal => linux.portal.deinit(),
        };
    }
    return native_backend.deinit();
}

/// Open a single file dialog. Returns the selected path, or null if cancelled.
pub fn open_dialog(allocator: std.mem.Allocator, args: OpenDialogArgs) Error!?[]const u8 {
    if (is_linux) {
        return switch (linux_backend) {
            .gtk => linux.gtk.open_dialog(allocator, args),
            .portal => linux.portal.open_dialog(allocator, args),
        };
    }
    return native_backend.open_dialog(allocator, args);
}

/// Open a multi-file dialog. Returns a slice of selected paths.
pub fn open_dialog_multiple(allocator: std.mem.Allocator, args: OpenDialogArgs) Error![]const []const u8 {
    if (is_linux) {
        return switch (linux_backend) {
            .gtk => linux.gtk.open_dialog_multiple(allocator, args),
            .portal => linux.portal.open_dialog_multiple(allocator, args),
        };
    }
    return native_backend.open_dialog_multiple(allocator, args);
}

/// Open a save dialog. Returns the selected path, or null if cancelled.
pub fn save_dialog(allocator: std.mem.Allocator, args: SaveDialogArgs) Error!?[]const u8 {
    if (is_linux) {
        return switch (linux_backend) {
            .gtk => linux.gtk.save_dialog(allocator, args),
            .portal => linux.portal.save_dialog(allocator, args),
        };
    }
    return native_backend.save_dialog(allocator, args);
}

/// Open a single folder picker. Returns the selected path, or null if cancelled.
pub fn pick_folder(allocator: std.mem.Allocator, args: PickFolderArgs) Error!?[]const u8 {
    if (is_linux) {
        return switch (linux_backend) {
            .gtk => linux.gtk.pick_folder(allocator, args),
            .portal => linux.portal.pick_folder(allocator, args),
        };
    }
    return native_backend.pick_folder(allocator, args);
}

/// Open a multi-folder picker. Returns a slice of selected paths.
pub fn pick_folder_multiple(allocator: std.mem.Allocator, args: PickFolderArgs) Error![]const []const u8 {
    if (is_linux) {
        return switch (linux_backend) {
            .gtk => linux.gtk.pick_folder_multiple(allocator, args),
            .portal => linux.portal.pick_folder_multiple(allocator, args),
        };
    }
    return native_backend.pick_folder_multiple(allocator, args);
}
