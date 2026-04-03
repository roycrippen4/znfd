/// Zig Native File Dialog
/// Repository: https://github.com/roycrippen4/znfd
/// License: GPL 3.0
/// Authors: Roy E. Crippen IV, Bernard Teo, Michael Labbe
const std = @import("std");
const builtin = @import("builtin");

const opts = @import("opts");

const backend = switch (builtin.os.tag) {
    .linux => if (opts.portal) @import("portal.zig") else @import("gtk.zig"),
    .windows => @import("win32.zig"),
    .macos => @import("cocoa.zig"),
    else => @compileError("Unsupported OS"),
};

const Result = enum {
    // TODO: Remove this later and have the function signature return an error
    @"error",
    /// User pressed ok or successful return
    okay,
    /// User pressed cancel
    cancel,
};

/// Internal native character type for platform API calls.
/// Windows uses UTF-16; all other platforms use UTF-8.
const NativeChar = if (builtin.os.tag == .windows) u16 else u8;

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
};

pub const SaveDialogArgs = struct {
    filter_list: []const FilterItem = &.{},
    default_path: ?[]const u8 = null,
    default_name: ?[]const u8 = null,
    parent_window: ?WindowHandle = null,
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
pub fn init() Error!void {
    return backend.init();
}

/// Deinitialize the platform library.
pub fn deinit() void {
    backend.deinit();
}

/// Open a single file dialog. Returns the selected path, or null if cancelled.
pub fn open_dialog(allocator: std.mem.Allocator, args: OpenDialogArgs) Error!?[]const u8 {
    return backend.open_dialog(allocator, args);
}

/// Open a multi-file dialog. Returns a slice of selected paths.
pub fn open_dialog_multiple(allocator: std.mem.Allocator, args: OpenDialogArgs) Error![]const []const u8 {
    return backend.open_dialog_multiple(allocator, args);
}

/// Open a save dialog. Returns the selected path, or null if cancelled.
pub fn save_dialog(allocator: std.mem.Allocator, args: SaveDialogArgs) Error!?[]const u8 {
    return backend.save_dialog(allocator, args);
}

/// Open a single folder picker. Returns the selected path, or null if cancelled.
pub fn pick_folder(allocator: std.mem.Allocator, args: PickFolderArgs) Error!?[]const u8 {
    return backend.pick_folder(allocator, args);
}

/// Open a multi-folder picker. Returns a slice of selected paths.
pub fn pick_folder_multiple(allocator: std.mem.Allocator, args: PickFolderArgs) Error![]const []const u8 {
    return backend.pick_folder_multiple(allocator, args);
}
