const std = @import("std");
const root = @import("root.zig");

const Error = root.Error;
const FilterItem = root.FilterItem;
const OpenDialogArgs = root.OpenDialogArgs;
const SaveDialogArgs = root.SaveDialogArgs;
const PickFolderArgs = root.PickFolderArgs;
const WindowHandle = root.WindowHandle;

// --- Objective-C Runtime Types ---

const id = ?*anyopaque;
const SEL = ?*anyopaque;
const NSInteger = isize;
const NSUInteger = usize;
const BOOL = i8;

const YES: BOOL = 1;
const NO: BOOL = 0;

const NSModalResponseOK: NSInteger = 1;
const NSApplicationActivationPolicyAccessory: NSInteger = 1;
const NSApplicationActivationPolicyProhibited: NSInteger = 2;

// --- Objective-C Runtime Functions ---

extern "c" fn objc_getClass(name: [*:0]const u8) id;
extern "c" fn sel_registerName(name: [*:0]const u8) SEL;
extern "c" fn objc_msgSend() callconv(.c) void;
extern "c" fn objc_autoreleasePoolPush() ?*anyopaque;
extern "c" fn objc_autoreleasePoolPop(pool: ?*anyopaque) void;

// --- Typed objc_msgSend Wrappers ---
// objc_msgSend is a trampoline with a variable signature. We @ptrCast to the
// needed function pointer type for each call pattern.

fn msg(comptime R: type, target: id, sel_name: [*:0]const u8) R {
    const f: *const fn (id, SEL) callconv(.c) R = @ptrCast(&objc_msgSend);
    return f(target, sel_registerName(sel_name));
}

fn msg1(comptime R: type, target: id, sel_name: [*:0]const u8, a1: anytype) R {
    const f: *const fn (id, SEL, @TypeOf(a1)) callconv(.c) R = @ptrCast(&objc_msgSend);
    return f(target, sel_registerName(sel_name), a1);
}

fn msg2(comptime R: type, target: id, sel_name: [*:0]const u8, a1: anytype, a2: anytype) R {
    const f: *const fn (id, SEL, @TypeOf(a1), @TypeOf(a2)) callconv(.c) R = @ptrCast(&objc_msgSend);
    return f(target, sel_registerName(sel_name), a1, a2);
}

fn class(name: [*:0]const u8) id {
    return objc_getClass(name);
}

// --- State ---

var old_app_policy: NSInteger = 0;

// --- Public API ---

pub fn init() Error!void {
    const app = msg(id, class("NSApplication"), "sharedApplication");
    old_app_policy = msg(NSInteger, app, "activationPolicy");
    if (old_app_policy == NSApplicationActivationPolicyProhibited) {
        if (msg1(BOOL, app, "setActivationPolicy:", NSApplicationActivationPolicyAccessory) == NO) {
            return error.InitFailed;
        }
    }
}

pub fn deinit() void {
    const app = msg(id, class("NSApplication"), "sharedApplication");
    _ = msg1(BOOL, app, "setActivationPolicy:", old_app_policy);
}

pub fn open_dialog(allocator: std.mem.Allocator, args: OpenDialogArgs) Error!?[]const u8 {
    const pool = objc_autoreleasePoolPush();
    defer objc_autoreleasePoolPop(pool);

    const key_window = get_key_window(args.parent_window);
    const panel = msg(id, class("NSOpenPanel"), "openPanel");
    msg1(void, panel, "setAllowsMultipleSelection:", NO);
    add_filters(panel, args.filter_list);
    set_default_path(panel, args.default_path);

    if (msg(NSInteger, panel, "runModal") == NSModalResponseOK) {
        const url = msg(id, panel, "URL");
        restore_focus(key_window);
        return dupe_url_path(allocator, url);
    }
    restore_focus(key_window);
    return null;
}

pub fn open_dialog_multiple(allocator: std.mem.Allocator, args: OpenDialogArgs) Error![]const []const u8 {
    const pool = objc_autoreleasePoolPush();
    defer objc_autoreleasePoolPop(pool);

    const key_window = get_key_window(args.parent_window);
    const panel = msg(id, class("NSOpenPanel"), "openPanel");
    msg1(void, panel, "setAllowsMultipleSelection:", YES);
    add_filters(panel, args.filter_list);
    set_default_path(panel, args.default_path);

    if (msg(NSInteger, panel, "runModal") == NSModalResponseOK) {
        const urls = msg(id, panel, "URLs");
        restore_focus(key_window);
        return collect_url_paths(allocator, urls);
    }
    restore_focus(key_window);
    return &.{};
}

pub fn save_dialog(allocator: std.mem.Allocator, args: SaveDialogArgs) Error!?[]const u8 {
    const pool = objc_autoreleasePoolPush();
    defer objc_autoreleasePoolPop(pool);

    const key_window = get_key_window(args.parent_window);
    const panel = msg(id, class("NSSavePanel"), "savePanel");
    msg1(void, panel, "setExtensionHidden:", NO);
    msg1(void, panel, "setAllowsOtherFileTypes:", YES);
    add_filters(panel, args.filter_list);
    set_default_path(panel, args.default_path);
    set_default_name(panel, args.default_name);

    if (msg(NSInteger, panel, "runModal") == NSModalResponseOK) {
        const url = msg(id, panel, "URL");
        restore_focus(key_window);
        return dupe_url_path(allocator, url);
    }
    restore_focus(key_window);
    return null;
}

pub fn pick_folder(allocator: std.mem.Allocator, args: PickFolderArgs) Error!?[]const u8 {
    const pool = objc_autoreleasePoolPush();
    defer objc_autoreleasePoolPop(pool);

    const key_window = get_key_window(args.parent_window);
    const panel = msg(id, class("NSOpenPanel"), "openPanel");
    msg1(void, panel, "setAllowsMultipleSelection:", NO);
    msg1(void, panel, "setCanChooseDirectories:", YES);
    msg1(void, panel, "setCanCreateDirectories:", YES);
    msg1(void, panel, "setCanChooseFiles:", NO);
    set_default_path(panel, args.default_path);

    if (msg(NSInteger, panel, "runModal") == NSModalResponseOK) {
        const url = msg(id, panel, "URL");
        restore_focus(key_window);
        return dupe_url_path(allocator, url);
    }
    restore_focus(key_window);
    return null;
}

pub fn pick_folder_multiple(allocator: std.mem.Allocator, args: PickFolderArgs) Error![]const []const u8 {
    const pool = objc_autoreleasePoolPush();
    defer objc_autoreleasePoolPop(pool);

    const key_window = get_key_window(args.parent_window);
    const panel = msg(id, class("NSOpenPanel"), "openPanel");
    msg1(void, panel, "setAllowsMultipleSelection:", YES);
    msg1(void, panel, "setCanChooseDirectories:", YES);
    msg1(void, panel, "setCanCreateDirectories:", YES);
    msg1(void, panel, "setCanChooseFiles:", NO);
    set_default_path(panel, args.default_path);

    if (msg(NSInteger, panel, "runModal") == NSModalResponseOK) {
        const urls = msg(id, panel, "URLs");
        restore_focus(key_window);
        return collect_url_paths(allocator, urls);
    }
    restore_focus(key_window);
    return &.{};
}

// --- Internal Helpers ---

fn get_key_window(parent_window: ?WindowHandle) id {
    if (parent_window) |pw| {
        if (pw.type == .cocoa) {
            const window: id = pw.handle;
            msg1(void, window, "makeKeyAndOrderFront:", @as(id, null));
            return window;
        }
    }
    const app = msg(id, class("NSApplication"), "sharedApplication");
    return msg(id, app, "keyWindow");
}

fn restore_focus(key_window: id) void {
    if (key_window != null) {
        msg1(void, key_window, "makeKeyAndOrderFront:", @as(id, null));
    }
}

fn set_default_path(panel: id, default_path: ?[]const u8) void {
    const path = default_path orelse return;
    if (path.len == 0) return;
    const ns_str = to_nsstring(path) orelse return;
    const url = msg2(id, class("NSURL"), "fileURLWithPath:isDirectory:", ns_str, YES);
    msg1(void, panel, "setDirectoryURL:", url);
}

fn set_default_name(panel: id, default_name: ?[]const u8) void {
    const name = default_name orelse return;
    if (name.len == 0) return;
    const ns_str = to_nsstring(name) orelse return;
    msg1(void, panel, "setNameFieldStringValue:", ns_str);
}

fn add_filters(panel: id, filter_list: []const FilterItem) void {
    if (filter_list.len == 0) return;
    const ns_array = build_allowed_file_types(filter_list) orelse return;
    msg1(void, panel, "setAllowedFileTypes:", ns_array);
}

/// Build an autoreleased NSArray of NSString file extensions from filter items.
/// Parses comma-separated specs: "png,jpg" becomes [@"png", @"jpg"].
fn build_allowed_file_types(filter_list: []const FilterItem) id {
    const mutable = msg(id, msg(id, class("NSMutableArray"), "alloc"), "init");
    if (mutable == null) return null;

    for (filter_list) |item| {
        var spec = item.spec;
        while (spec.len > 0) {
            var end: usize = 0;
            while (end < spec.len and spec[end] != ',') : (end += 1) {}
            const ext = spec[0..end];
            if (ext.len > 0) {
                if (to_nsstring(ext)) |ns_ext| {
                    msg1(void, mutable, "addObject:", ns_ext);
                }
            }
            spec = if (end < spec.len) spec[end + 1 ..] else &.{};
        }
    }

    const result = msg1(id, class("NSArray"), "arrayWithArray:", mutable);
    msg(void, mutable, "release");
    return result;
}

/// Create an autoreleased NSString from a UTF-8 slice.
fn to_nsstring(utf8: []const u8) id {
    // stringWithUTF8String: needs a null-terminated C string.
    var buf: [1024]u8 = undefined;
    if (utf8.len < buf.len) {
        @memcpy(buf[0..utf8.len], utf8);
        buf[utf8.len] = 0;
        return msg1(id, class("NSString"), "stringWithUTF8String:", @as([*:0]const u8, buf[0..utf8.len :0]));
    }
    // Heap fallback for long strings
    const z = std.heap.page_allocator.alloc(u8, utf8.len + 1) catch return null;
    defer std.heap.page_allocator.free(z);
    @memcpy(z[0..utf8.len], utf8);
    z[utf8.len] = 0;
    return msg1(id, class("NSString"), "stringWithUTF8String:", @as([*:0]const u8, z[0..utf8.len :0]));
}

/// Get the UTF-8 file path from an NSURL and dupe it with the allocator.
fn dupe_url_path(allocator: std.mem.Allocator, url: id) Error!?[]const u8 {
    if (url == null) return error.DialogError;
    const ns_path = msg(id, url, "path");
    if (ns_path == null) return error.DialogError;
    const utf8: [*:0]const u8 = msg([*:0]const u8, ns_path, "UTF8String");
    const len = std.mem.len(utf8);
    return @as(?[]const u8, allocator.dupe(u8, utf8[0..len]) catch return error.DialogError);
}

/// Collect paths from an NSArray of NSURLs into a Zig-allocated slice.
fn collect_url_paths(allocator: std.mem.Allocator, urls: id) Error![]const []const u8 {
    if (urls == null) return &.{};
    const count = msg(NSUInteger, urls, "count");
    if (count == 0) return &.{};

    const paths = allocator.alloc([]const u8, count) catch return error.DialogError;
    var i: NSUInteger = 0;
    while (i < count) : (i += 1) {
        const url = msg1(id, urls, "objectAtIndex:", i);
        paths[i] = (try dupe_url_path(allocator, url)) orelse {
            free_partial(allocator, paths[0..i]);
            return error.DialogError;
        };
    }
    return paths;
}

fn free_partial(allocator: std.mem.Allocator, paths: []const []const u8) void {
    for (paths) |p| allocator.free(p);
    allocator.free(paths);
}
