const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");

const c = @cImport({
    @cInclude("dbus/dbus.h");
});

const Error = root.Error;
const FilterItem = root.FilterItem;
const OpenDialogArgs = root.OpenDialogArgs;
const SaveDialogArgs = root.SaveDialogArgs;
const PickFolderArgs = root.PickFolderArgs;
const WindowHandle = root.WindowHandle;

// DBusError has bitfields that Zig can't represent, so we define a compatible layout.
const DBusError = extern struct {
    name: ?[*:0]const u8 = null,
    message: ?[*:0]const u8 = null,
    dummy_bits: c_uint = 0,
    padding1: ?*anyopaque = null,
};

const DBUS_DESTINATION = "org.freedesktop.portal.Desktop";
const DBUS_PATH = "/org/freedesktop/portal/desktop";
const DBUS_FILECHOOSER_IFACE = "org.freedesktop.portal.FileChooser";
const DBUS_REQUEST_IFACE = "org.freedesktop.portal.Request";
const FILE_URI_PREFIX = "file://";
const RESPONSE_HANDLE_PREFIX = "/org/freedesktop/portal/desktop/request/";

// D-Bus connection state
var dbus_conn: ?*c.DBusConnection = null;
var dbus_unique_name: ?[*:0]const u8 = null;

// --- Init / Deinit ---

pub fn init() Error!void {
    var err: DBusError = .{};
    c.dbus_error_init(@ptrCast(&err));
    defer c.dbus_error_free(@ptrCast(&err));

    dbus_conn = c.dbus_bus_get(c.DBUS_BUS_SESSION, @ptrCast(&err));
    if (dbus_conn == null) return error.InitFailed;

    dbus_unique_name = c.dbus_bus_get_unique_name(dbus_conn);
    if (dbus_unique_name == null) {
        c.dbus_connection_unref(dbus_conn.?);
        dbus_conn = null;
        return error.InitFailed;
    }
}

pub fn deinit() void {
    if (dbus_conn) |conn| {
        c.dbus_connection_unref(conn);
        dbus_conn = null;
    }
}

// --- Dialogs ---

pub fn open_dialog(allocator: std.mem.Allocator, args: OpenDialogArgs) Error!?[]const u8 {
    const msg = try dbus_open_file(false, false, args.filter_list, args.default_path, args.parent_window) orelse return null;
    defer c.dbus_message_unref(msg);

    const uri = try read_response_single_uri(msg) orelse return null;
    return @as(?[]const u8, try decode_file_uri(allocator, uri));
}

pub fn open_dialog_multiple(allocator: std.mem.Allocator, args: OpenDialogArgs) Error![]const []const u8 {
    const msg = try dbus_open_file(true, false, args.filter_list, args.default_path, args.parent_window) orelse return &.{};
    defer c.dbus_message_unref(msg);

    return try read_response_multiple_uris(allocator, msg);
}

pub fn save_dialog(allocator: std.mem.Allocator, args: SaveDialogArgs) Error!?[]const u8 {
    const msg = try dbus_save_file(args.filter_list, args.default_path, args.default_name, args.parent_window) orelse return null;
    defer c.dbus_message_unref(msg);

    const uri = try read_response_single_uri(msg) orelse return null;
    return @as(?[]const u8, try decode_file_uri(allocator, uri));
}

pub fn pick_folder(allocator: std.mem.Allocator, args: PickFolderArgs) Error!?[]const u8 {
    const msg = try dbus_open_file(false, true, &.{}, args.default_path, args.parent_window) orelse return null;
    defer c.dbus_message_unref(msg);

    const uri = try read_response_single_uri(msg) orelse return null;
    return @as(?[]const u8, try decode_file_uri(allocator, uri));
}

pub fn pick_folder_multiple(allocator: std.mem.Allocator, args: PickFolderArgs) Error![]const []const u8 {
    const msg = try dbus_open_file(true, true, &.{}, args.default_path, args.parent_window) orelse return &.{};
    defer c.dbus_message_unref(msg);

    return try read_response_multiple_uris(allocator, msg);
}

// --- D-Bus method calls ---

fn dbus_open_file(
    multiple: bool,
    directory: bool,
    filter_list: []const FilterItem,
    default_path: ?[]const u8,
    parent_window: ?WindowHandle,
) Error!?*c.DBusMessage {
    const conn = dbus_conn orelse return error.DialogError;

    var handle_token_buf: [128]u8 = undefined;
    const handle_path = make_unique_object_path(&handle_token_buf) orelse return error.DialogError;

    // Subscribe to the response signal
    try subscribe_to_response(conn, handle_path.path);

    // Build the method call
    const query = c.dbus_message_new_method_call(
        DBUS_DESTINATION,
        DBUS_PATH,
        DBUS_FILECHOOSER_IFACE,
        "OpenFile",
    ) orelse return error.DialogError;
    defer c.dbus_message_unref(query);

    // Append arguments
    {
        var iter: c.DBusMessageIter = undefined;
        c.dbus_message_iter_init_append(query, &iter);

        // Parent window handle
        const parent_str = serialize_parent_window(parent_window);
        _ = c.dbus_message_iter_append_basic(&iter, c.DBUS_TYPE_STRING, @ptrCast(&parent_str));

        // Title
        const title: [*:0]const u8 = if (directory)
            (if (multiple) "Select Folders" else "Select Folder")
        else
            (if (multiple) "Open Files" else "Open File");
        _ = c.dbus_message_iter_append_basic(&iter, c.DBUS_TYPE_STRING, @ptrCast(&title));

        // Options dict
        var sub_iter: c.DBusMessageIter = undefined;
        _ = c.dbus_message_iter_open_container(&iter, c.DBUS_TYPE_ARRAY, "{sv}", &sub_iter);

        append_dict_entry_string(&sub_iter, "handle_token", handle_path.token);

        if (multiple) {
            append_dict_entry_bool(&sub_iter, "multiple", true);
        }

        if (directory) {
            append_dict_entry_bool(&sub_iter, "directory", true);
        }

        if (!directory and filter_list.len > 0) {
            append_filters(&sub_iter, filter_list);
        }

        if (default_path) |path| {
            append_dict_entry_byte_array(&sub_iter, "current_folder", path);
        }

        _ = c.dbus_message_iter_close_container(&iter, &sub_iter);
    }

    return try send_and_wait_response(conn, query);
}

fn dbus_save_file(
    filter_list: []const FilterItem,
    default_path: ?[]const u8,
    default_name: ?[]const u8,
    parent_window: ?WindowHandle,
) Error!?*c.DBusMessage {
    const conn = dbus_conn orelse return error.DialogError;

    var handle_token_buf: [128]u8 = undefined;
    const handle_path = make_unique_object_path(&handle_token_buf) orelse return error.DialogError;

    try subscribe_to_response(conn, handle_path.path);

    const query = c.dbus_message_new_method_call(
        DBUS_DESTINATION,
        DBUS_PATH,
        DBUS_FILECHOOSER_IFACE,
        "SaveFile",
    ) orelse return error.DialogError;
    defer c.dbus_message_unref(query);

    {
        var iter: c.DBusMessageIter = undefined;
        c.dbus_message_iter_init_append(query, &iter);

        const parent_str = serialize_parent_window(parent_window);
        _ = c.dbus_message_iter_append_basic(&iter, c.DBUS_TYPE_STRING, @ptrCast(&parent_str));

        const title: [*:0]const u8 = "Save File";
        _ = c.dbus_message_iter_append_basic(&iter, c.DBUS_TYPE_STRING, @ptrCast(&title));

        var sub_iter: c.DBusMessageIter = undefined;
        _ = c.dbus_message_iter_open_container(&iter, c.DBUS_TYPE_ARRAY, "{sv}", &sub_iter);

        append_dict_entry_string(&sub_iter, "handle_token", handle_path.token);

        if (filter_list.len > 0) {
            append_filters(&sub_iter, filter_list);
        }

        if (default_name) |name| {
            var name_buf: [256]u8 = undefined;
            if (name.len < name_buf.len) {
                @memcpy(name_buf[0..name.len], name);
                name_buf[name.len] = 0;
                append_dict_entry_string(&sub_iter, "current_name", @ptrCast(name_buf[0..name.len :0]));
            }
        }

        if (default_path) |path| {
            append_dict_entry_byte_array(&sub_iter, "current_folder", path);
        }

        _ = c.dbus_message_iter_close_container(&iter, &sub_iter);
    }

    return try send_and_wait_response(conn, query);
}

fn subscribe_to_response(conn: *c.DBusConnection, handle_path: [*:0]const u8) Error!void {
    var match_err: DBusError = .{};
    c.dbus_error_init(@ptrCast(&match_err));
    defer c.dbus_error_free(@ptrCast(&match_err));

    var match_buf: [512]u8 = undefined;
    const match_rule = std.fmt.bufPrint(
        &match_buf,
        "type='signal',sender='" ++ DBUS_DESTINATION ++ "',path='{s}',interface='" ++ DBUS_REQUEST_IFACE ++ "',member='Response',destination='{s}'",
        .{ std.mem.span(handle_path), std.mem.span(dbus_unique_name orelse return error.DialogError) },
    ) catch return error.DialogError;
    match_buf[match_rule.len] = 0;
    c.dbus_bus_add_match(conn, @ptrCast(match_buf[0..match_rule.len :0]), @ptrCast(&match_err));
    if (c.dbus_error_is_set(@ptrCast(&match_err)) != 0) return error.DialogError;
}

fn send_and_wait_response(conn: *c.DBusConnection, query: *c.DBusMessage) Error!?*c.DBusMessage {
    var err: DBusError = .{};
    c.dbus_error_init(@ptrCast(&err));
    defer c.dbus_error_free(@ptrCast(&err));

    const reply = c.dbus_connection_send_with_reply_and_block(conn, query, c.DBUS_TIMEOUT_INFINITE, @ptrCast(&err));
    if (reply == null) {
        if (err.message) |msg| {
            std.debug.print("D-Bus error: {s}\n", .{std.mem.span(msg)});
        }
        if (err.name) |name| {
            std.debug.print("D-Bus error name: {s}\n", .{std.mem.span(name)});
        }
        return error.DialogError;
    }
    c.dbus_message_unref(reply.?);

    // Wait for the Response signal
    while (c.dbus_connection_read_write(conn, -1) != 0) {
        while (true) {
            const msg = c.dbus_connection_pop_message(conn) orelse break;
            if (c.dbus_message_is_signal(msg, DBUS_REQUEST_IFACE, "Response") != 0) {
                return msg;
            }
            c.dbus_message_unref(msg);
        }
    }

    return error.DialogError;
}

// --- Parent window serialization ---

/// Serialize a window handle to the portal's expected string format.
/// X11: "x11:<hex_window_id>", Wayland: "wayland:<exported_handle>", or "" for no parent.
fn serialize_parent_window(parent: ?WindowHandle) [*:0]const u8 {
    const handle = parent orelse return "";
    switch (handle.type) {
        .x11 => {
            // Format as "x11:<hex>"
            const xid = @intFromPtr(handle.handle);
            const buf = struct {
                var data: [4 + @sizeOf(usize) * 2 + 1]u8 = undefined;
            };
            buf.data[0] = 'x';
            buf.data[1] = '1';
            buf.data[2] = '1';
            buf.data[3] = ':';
            var pos: usize = 4;
            var val = xid;
            // Write hex digits in reverse, then reverse them
            const start = pos;
            if (val == 0) {
                buf.data[pos] = '0';
                pos += 1;
            } else {
                while (val != 0) {
                    const digit: u8 = @intCast(val & 0xF);
                    buf.data[pos] = if (digit < 10) '0' + digit else 'A' - 10 + digit;
                    pos += 1;
                    val >>= 4;
                }
                // Reverse the hex digits
                var lo = start;
                var hi = pos - 1;
                while (lo < hi) {
                    const tmp = buf.data[lo];
                    buf.data[lo] = buf.data[hi];
                    buf.data[hi] = tmp;
                    lo += 1;
                    hi -= 1;
                }
            }
            buf.data[pos] = 0;
            return @ptrCast(buf.data[0..pos :0]);
        },
        // Wayland handle export requires the xdg-foreign protocol which needs
        // async roundtrip — not yet implemented, fall through to empty
        .wayland, .windows, .cocoa => return "",
    }
}

// --- D-Bus message building helpers ---

fn append_dict_entry_string(sub_iter: *c.DBusMessageIter, key: [*:0]const u8, value: [*:0]const u8) void {
    var de_iter: c.DBusMessageIter = undefined;
    var variant_iter: c.DBusMessageIter = undefined;
    _ = c.dbus_message_iter_open_container(sub_iter, c.DBUS_TYPE_DICT_ENTRY, null, &de_iter);
    _ = c.dbus_message_iter_append_basic(&de_iter, c.DBUS_TYPE_STRING, @ptrCast(&key));
    _ = c.dbus_message_iter_open_container(&de_iter, c.DBUS_TYPE_VARIANT, "s", &variant_iter);
    _ = c.dbus_message_iter_append_basic(&variant_iter, c.DBUS_TYPE_STRING, @ptrCast(&value));
    _ = c.dbus_message_iter_close_container(&de_iter, &variant_iter);
    _ = c.dbus_message_iter_close_container(sub_iter, &de_iter);
}

fn append_dict_entry_bool(sub_iter: *c.DBusMessageIter, key: [*:0]const u8, value: bool) void {
    var de_iter: c.DBusMessageIter = undefined;
    var variant_iter: c.DBusMessageIter = undefined;
    _ = c.dbus_message_iter_open_container(sub_iter, c.DBUS_TYPE_DICT_ENTRY, null, &de_iter);
    _ = c.dbus_message_iter_append_basic(&de_iter, c.DBUS_TYPE_STRING, @ptrCast(&key));
    _ = c.dbus_message_iter_open_container(&de_iter, c.DBUS_TYPE_VARIANT, "b", &variant_iter);
    var b: c_int = if (value) 1 else 0;
    _ = c.dbus_message_iter_append_basic(&variant_iter, c.DBUS_TYPE_BOOLEAN, @ptrCast(&b));
    _ = c.dbus_message_iter_close_container(&de_iter, &variant_iter);
    _ = c.dbus_message_iter_close_container(sub_iter, &de_iter);
}

fn append_dict_entry_byte_array(sub_iter: *c.DBusMessageIter, key: [*:0]const u8, value: []const u8) void {
    var de_iter: c.DBusMessageIter = undefined;
    var variant_iter: c.DBusMessageIter = undefined;
    var array_iter: c.DBusMessageIter = undefined;
    _ = c.dbus_message_iter_open_container(sub_iter, c.DBUS_TYPE_DICT_ENTRY, null, &de_iter);
    _ = c.dbus_message_iter_append_basic(&de_iter, c.DBUS_TYPE_STRING, @ptrCast(&key));
    _ = c.dbus_message_iter_open_container(&de_iter, c.DBUS_TYPE_VARIANT, "ay", &variant_iter);
    _ = c.dbus_message_iter_open_container(&variant_iter, c.DBUS_TYPE_ARRAY, "y", &array_iter);
    for (value) |byte| {
        _ = c.dbus_message_iter_append_basic(&array_iter, c.DBUS_TYPE_BYTE, @ptrCast(&byte));
    }
    // Trailing null byte required by the portal
    const zero: u8 = 0;
    _ = c.dbus_message_iter_append_basic(&array_iter, c.DBUS_TYPE_BYTE, @ptrCast(&zero));
    _ = c.dbus_message_iter_close_container(&variant_iter, &array_iter);
    _ = c.dbus_message_iter_close_container(&de_iter, &variant_iter);
    _ = c.dbus_message_iter_close_container(sub_iter, &de_iter);
}

fn append_filters(sub_iter: *c.DBusMessageIter, filter_list: []const FilterItem) void {
    var de_iter: c.DBusMessageIter = undefined;
    var variant_iter: c.DBusMessageIter = undefined;
    var filter_list_iter: c.DBusMessageIter = undefined;

    _ = c.dbus_message_iter_open_container(sub_iter, c.DBUS_TYPE_DICT_ENTRY, null, &de_iter);
    const filters_key: [*:0]const u8 = "filters";
    _ = c.dbus_message_iter_append_basic(&de_iter, c.DBUS_TYPE_STRING, @ptrCast(&filters_key));
    _ = c.dbus_message_iter_open_container(&de_iter, c.DBUS_TYPE_VARIANT, "a(sa(us))", &variant_iter);
    _ = c.dbus_message_iter_open_container(&variant_iter, c.DBUS_TYPE_ARRAY, "(sa(us))", &filter_list_iter);

    for (filter_list) |item| {
        append_single_filter(&filter_list_iter, item);
    }
    append_wildcard_filter(&filter_list_iter);

    _ = c.dbus_message_iter_close_container(&variant_iter, &filter_list_iter);
    _ = c.dbus_message_iter_close_container(&de_iter, &variant_iter);
    _ = c.dbus_message_iter_close_container(sub_iter, &de_iter);

    // current_filter — default to first filter
    if (filter_list.len > 0) {
        var cf_de_iter: c.DBusMessageIter = undefined;
        var cf_variant_iter: c.DBusMessageIter = undefined;
        _ = c.dbus_message_iter_open_container(sub_iter, c.DBUS_TYPE_DICT_ENTRY, null, &cf_de_iter);
        const cf_key: [*:0]const u8 = "current_filter";
        _ = c.dbus_message_iter_append_basic(&cf_de_iter, c.DBUS_TYPE_STRING, @ptrCast(&cf_key));
        _ = c.dbus_message_iter_open_container(&cf_de_iter, c.DBUS_TYPE_VARIANT, "(sa(us))", &cf_variant_iter);
        append_single_filter(&cf_variant_iter, filter_list[0]);
        _ = c.dbus_message_iter_close_container(&cf_de_iter, &cf_variant_iter);
        _ = c.dbus_message_iter_close_container(sub_iter, &cf_de_iter);
    }
}

fn append_single_filter(base_iter: *c.DBusMessageIter, item: FilterItem) void {
    var struct_iter: c.DBusMessageIter = undefined;
    var sublist_iter: c.DBusMessageIter = undefined;

    _ = c.dbus_message_iter_open_container(base_iter, c.DBUS_TYPE_STRUCT, null, &struct_iter);

    // Friendly name: "Name (spec)"
    var name_buf: [512]u8 = undefined;
    const friendly = std.fmt.bufPrint(&name_buf, "{s} ({s})", .{ item.name, item.spec }) catch item.name;
    name_buf[friendly.len] = 0;
    const name_ptr: [*:0]const u8 = @ptrCast(name_buf[0..friendly.len :0]);
    _ = c.dbus_message_iter_append_basic(&struct_iter, c.DBUS_TYPE_STRING, @ptrCast(&name_ptr));

    // Extension patterns
    _ = c.dbus_message_iter_open_container(&struct_iter, c.DBUS_TYPE_ARRAY, "(us)", &sublist_iter);

    var spec = item.spec;
    while (spec.len > 0) {
        var end: usize = 0;
        while (end < spec.len and spec[end] != ',') : (end += 1) {}
        const ext = spec[0..end];
        if (ext.len > 0) {
            var pat_buf: [260]u8 = undefined;
            const pattern = std.fmt.bufPrint(&pat_buf, "*.{s}", .{ext}) catch {
                if (end < spec.len) {
                    spec = spec[end + 1 ..];
                } else break;
                continue;
            };
            pat_buf[pattern.len] = 0;
            append_filter_pattern(&sublist_iter, @ptrCast(pat_buf[0..pattern.len :0]));
        }
        if (end < spec.len) {
            spec = spec[end + 1 ..];
        } else break;
    }

    _ = c.dbus_message_iter_close_container(&struct_iter, &sublist_iter);
    _ = c.dbus_message_iter_close_container(base_iter, &struct_iter);
}

fn append_wildcard_filter(base_iter: *c.DBusMessageIter) void {
    var struct_iter: c.DBusMessageIter = undefined;
    var sublist_iter: c.DBusMessageIter = undefined;

    _ = c.dbus_message_iter_open_container(base_iter, c.DBUS_TYPE_STRUCT, null, &struct_iter);
    const name: [*:0]const u8 = "All files";
    _ = c.dbus_message_iter_append_basic(&struct_iter, c.DBUS_TYPE_STRING, @ptrCast(&name));
    _ = c.dbus_message_iter_open_container(&struct_iter, c.DBUS_TYPE_ARRAY, "(us)", &sublist_iter);
    const asterisk: [*:0]const u8 = "*";
    append_filter_pattern(&sublist_iter, asterisk);
    _ = c.dbus_message_iter_close_container(&struct_iter, &sublist_iter);
    _ = c.dbus_message_iter_close_container(base_iter, &struct_iter);
}

fn append_filter_pattern(sublist_iter: *c.DBusMessageIter, pattern: [*:0]const u8) void {
    var struct_iter: c.DBusMessageIter = undefined;
    _ = c.dbus_message_iter_open_container(sublist_iter, c.DBUS_TYPE_STRUCT, null, &struct_iter);
    const zero: c_uint = 0;
    _ = c.dbus_message_iter_append_basic(&struct_iter, c.DBUS_TYPE_UINT32, @ptrCast(&zero));
    _ = c.dbus_message_iter_append_basic(&struct_iter, c.DBUS_TYPE_STRING, @ptrCast(&pattern));
    _ = c.dbus_message_iter_close_container(sublist_iter, &struct_iter);
}

// --- D-Bus response reading ---

fn read_response_single_uri(msg: *c.DBusMessage) Error!?[*:0]const u8 {
    var iter: c.DBusMessageIter = undefined;
    if (c.dbus_message_iter_init(msg, &iter) == 0) return error.DialogError;

    if (c.dbus_message_iter_get_arg_type(&iter) != c.DBUS_TYPE_UINT32) return error.DialogError;
    var resp_code: u32 = undefined;
    c.dbus_message_iter_get_basic(&iter, @ptrCast(&resp_code));
    if (resp_code == 1) return null; // cancelled
    if (resp_code != 0) return error.DialogError;

    if (c.dbus_message_iter_next(&iter) == 0) return error.DialogError;

    return find_first_uri(&iter);
}

fn read_response_multiple_uris(allocator: std.mem.Allocator, msg: *c.DBusMessage) Error![]const []const u8 {
    var iter: c.DBusMessageIter = undefined;
    if (c.dbus_message_iter_init(msg, &iter) == 0) return error.DialogError;

    if (c.dbus_message_iter_get_arg_type(&iter) != c.DBUS_TYPE_UINT32) return error.DialogError;
    var resp_code: u32 = undefined;
    c.dbus_message_iter_get_basic(&iter, @ptrCast(&resp_code));
    if (resp_code == 1) return &.{};
    if (resp_code != 0) return error.DialogError;

    if (c.dbus_message_iter_next(&iter) == 0) return error.DialogError;

    return collect_all_uris(allocator, &iter);
}

fn find_first_uri(results_iter: *c.DBusMessageIter) Error!?[*:0]const u8 {
    if (c.dbus_message_iter_get_arg_type(results_iter) != c.DBUS_TYPE_ARRAY) return error.DialogError;

    var dict_iter: c.DBusMessageIter = undefined;
    c.dbus_message_iter_recurse(results_iter, &dict_iter);

    while (c.dbus_message_iter_get_arg_type(&dict_iter) == c.DBUS_TYPE_DICT_ENTRY) {
        var de_iter: c.DBusMessageIter = undefined;
        c.dbus_message_iter_recurse(&dict_iter, &de_iter);

        if (c.dbus_message_iter_get_arg_type(&de_iter) == c.DBUS_TYPE_STRING) {
            var key: [*:0]const u8 = undefined;
            c.dbus_message_iter_get_basic(&de_iter, @ptrCast(&key));

            if (std.mem.eql(u8, std.mem.span(key), "uris")) {
                if (c.dbus_message_iter_next(&de_iter) == 0) return error.DialogError;
                if (c.dbus_message_iter_get_arg_type(&de_iter) != c.DBUS_TYPE_VARIANT) return error.DialogError;
                var variant_iter: c.DBusMessageIter = undefined;
                c.dbus_message_iter_recurse(&de_iter, &variant_iter);
                if (c.dbus_message_iter_get_arg_type(&variant_iter) != c.DBUS_TYPE_ARRAY) return error.DialogError;
                var uri_iter: c.DBusMessageIter = undefined;
                c.dbus_message_iter_recurse(&variant_iter, &uri_iter);
                if (c.dbus_message_iter_get_arg_type(&uri_iter) != c.DBUS_TYPE_STRING) return error.DialogError;
                var uri: [*:0]const u8 = undefined;
                c.dbus_message_iter_get_basic(&uri_iter, @ptrCast(&uri));
                return uri;
            }
        }

        _ = c.dbus_message_iter_next(&dict_iter);
    }

    return error.DialogError;
}

fn collect_all_uris(allocator: std.mem.Allocator, results_iter: *c.DBusMessageIter) Error![]const []const u8 {
    if (c.dbus_message_iter_get_arg_type(results_iter) != c.DBUS_TYPE_ARRAY) return error.DialogError;

    var dict_iter: c.DBusMessageIter = undefined;
    c.dbus_message_iter_recurse(results_iter, &dict_iter);

    while (c.dbus_message_iter_get_arg_type(&dict_iter) == c.DBUS_TYPE_DICT_ENTRY) {
        var de_iter: c.DBusMessageIter = undefined;
        c.dbus_message_iter_recurse(&dict_iter, &de_iter);

        if (c.dbus_message_iter_get_arg_type(&de_iter) == c.DBUS_TYPE_STRING) {
            var key: [*:0]const u8 = undefined;
            c.dbus_message_iter_get_basic(&de_iter, @ptrCast(&key));

            if (std.mem.eql(u8, std.mem.span(key), "uris")) {
                if (c.dbus_message_iter_next(&de_iter) == 0) return error.DialogError;
                if (c.dbus_message_iter_get_arg_type(&de_iter) != c.DBUS_TYPE_VARIANT) return error.DialogError;
                var variant_iter: c.DBusMessageIter = undefined;
                c.dbus_message_iter_recurse(&de_iter, &variant_iter);
                if (c.dbus_message_iter_get_arg_type(&variant_iter) != c.DBUS_TYPE_ARRAY) return error.DialogError;
                var uri_iter: c.DBusMessageIter = undefined;
                c.dbus_message_iter_recurse(&variant_iter, &uri_iter);

                // Count URIs
                var count: usize = 0;
                var count_iter = uri_iter;
                while (c.dbus_message_iter_get_arg_type(&count_iter) == c.DBUS_TYPE_STRING) {
                    count += 1;
                    if (c.dbus_message_iter_next(&count_iter) == 0) break;
                }

                var paths = allocator.alloc([]const u8, count) catch return error.DialogError;
                var i: usize = 0;
                while (c.dbus_message_iter_get_arg_type(&uri_iter) == c.DBUS_TYPE_STRING) {
                    var uri: [*:0]const u8 = undefined;
                    c.dbus_message_iter_get_basic(&uri_iter, @ptrCast(&uri));
                    paths[i] = decode_file_uri(allocator, uri) catch {
                        for (paths[0..i]) |p| allocator.free(p);
                        allocator.free(paths);
                        return error.DialogError;
                    };
                    i += 1;
                    if (c.dbus_message_iter_next(&uri_iter) == 0) break;
                }
                return paths[0..i];
            }
        }

        _ = c.dbus_message_iter_next(&dict_iter);
    }

    return &.{};
}

// --- URI decoding ---

fn decode_file_uri(allocator: std.mem.Allocator, uri: [*:0]const u8) Error![]const u8 {
    const span = std.mem.span(uri);

    if (!std.mem.startsWith(u8, span, FILE_URI_PREFIX)) return error.DialogError;
    const encoded = span[FILE_URI_PREFIX.len..];

    // Calculate decoded length
    var decoded_len: usize = 0;
    var j: usize = 0;
    while (j < encoded.len) {
        if (encoded[j] == '%') {
            if (j + 2 >= encoded.len) return error.DialogError;
            j += 3;
        } else {
            j += 1;
        }
        decoded_len += 1;
    }

    var buf = allocator.alloc(u8, decoded_len) catch return error.DialogError;
    var out: usize = 0;
    j = 0;
    while (j < encoded.len) {
        if (encoded[j] == '%') {
            const high = parse_hex(encoded[j + 1]) orelse {
                allocator.free(buf);
                return error.DialogError;
            };
            const low = parse_hex(encoded[j + 2]) orelse {
                allocator.free(buf);
                return error.DialogError;
            };
            buf[out] = (high << 4) | low;
            j += 3;
        } else {
            buf[out] = encoded[j];
            j += 1;
        }
        out += 1;
    }

    return buf[0..out];
}

fn parse_hex(ch: u8) ?u8 {
    if (ch >= '0' and ch <= '9') return ch - '0';
    if (ch >= 'A' and ch <= 'F') return ch - 'A' + 10;
    if (ch >= 'a' and ch <= 'f') return ch - 'a' + 10;
    return null;
}

// --- Object path generation ---

const ObjectPath = struct {
    path: [*:0]const u8,
    token: [*:0]const u8,
};

fn make_unique_object_path(buf: *[128]u8) ?ObjectPath {
    const sender = std.mem.span(dbus_unique_name orelse return null);
    const clean_sender = if (sender.len > 0 and sender[0] == ':') sender[1..] else sender;

    var pos: usize = 0;

    for (RESPONSE_HANDLE_PREFIX) |byte| {
        if (pos >= buf.len) return null;
        buf[pos] = byte;
        pos += 1;
    }

    for (clean_sender) |byte| {
        if (pos >= buf.len) return null;
        buf[pos] = if (byte == '.') '_' else byte;
        pos += 1;
    }

    if (pos >= buf.len) return null;
    buf[pos] = '/';
    pos += 1;

    const token_start = pos;

    var random_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);
    for (random_bytes) |byte| {
        if (pos + 1 >= buf.len) return null;
        buf[pos] = 'A' + (byte & 0x0F);
        pos += 1;
        buf[pos] = 'A' + (byte >> 4);
        pos += 1;
    }

    if (pos >= buf.len) return null;
    buf[pos] = 0;

    return .{
        .path = @ptrCast(buf[0..pos :0]),
        .token = @ptrCast(buf[token_start..pos :0]),
    };
}
