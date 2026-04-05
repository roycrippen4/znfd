const std = @import("std");
const builtin = @import("builtin");

const root = @import("root.zig");
const Error = root.Error;
const FilterItem = root.FilterItem;
const OpenDialogArgs = root.OpenDialogArgs;
const SaveDialogArgs = root.SaveDialogArgs;
const PickFolderArgs = root.PickFolderArgs;
const WindowHandle = root.WindowHandle;

const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("gdk/gdkx.h");
    @cInclude("gdk/gdkwayland.h");
});

pub fn init() Error!void {
    if (c.gtk_init_check(null, null) == 0) {
        return error.InitFailed;
    }
}

pub fn deinit() void {
    // GTK cannot be de-initialized
}

pub fn open_dialog(allocator: std.mem.Allocator, args: OpenDialogArgs) Error!?[]const u8 {
    const widget = create_dialog("Open File", c.GTK_FILE_CHOOSER_ACTION_OPEN, "_Open") orelse return error.DialogError;
    defer destroy_widget(widget);

    const chooser = as_chooser(widget);
    add_filters(chooser, args.filter_list);
    set_default_path(chooser, args.default_path);

    const result = run_dialog_with_parent(widget, args.parent_window);
    if (result == c.GTK_RESPONSE_ACCEPT) {
        return @as(?[]const u8, try dupe_gtk_path(allocator, c.gtk_file_chooser_get_filename(chooser)));
    }
    return null;
}

pub fn open_dialog_multiple(allocator: std.mem.Allocator, args: OpenDialogArgs) Error![]const []const u8 {
    const widget = create_dialog("Open Files", c.GTK_FILE_CHOOSER_ACTION_OPEN, "_Open") orelse return error.DialogError;
    defer destroy_widget(widget);

    const chooser = as_chooser(widget);
    c.gtk_file_chooser_set_select_multiple(chooser, 1);
    add_filters(chooser, args.filter_list);
    set_default_path(chooser, args.default_path);

    const result = run_dialog_with_parent(widget, args.parent_window);
    if (result == c.GTK_RESPONSE_ACCEPT) {
        return collect_gtk_paths(allocator, c.gtk_file_chooser_get_filenames(chooser));
    }
    return &.{};
}

pub fn save_dialog(allocator: std.mem.Allocator, args: SaveDialogArgs) Error!?[]const u8 {
    const widget = create_dialog("Save File", c.GTK_FILE_CHOOSER_ACTION_SAVE, "_Save") orelse return error.DialogError;
    defer destroy_widget(widget);

    const chooser = as_chooser(widget);
    c.gtk_file_chooser_set_do_overwrite_confirmation(chooser, 1);
    add_filters(chooser, args.filter_list);
    set_default_path(chooser, args.default_path);

    if (args.default_name) |name| {
        c.gtk_file_chooser_set_current_name(chooser, name.ptr);
    }

    const result = run_dialog_with_parent(widget, args.parent_window);
    if (result == c.GTK_RESPONSE_ACCEPT) {
        return @as(?[]const u8, try dupe_gtk_path(allocator, c.gtk_file_chooser_get_filename(chooser)));
    }
    return null;
}

pub fn pick_folder(allocator: std.mem.Allocator, args: PickFolderArgs) Error!?[]const u8 {
    const widget = create_dialog("Select Folder", c.GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER, "_Select") orelse return error.DialogError;
    defer destroy_widget(widget);

    const chooser = as_chooser(widget);
    set_default_path(chooser, args.default_path);

    const result = run_dialog_with_parent(widget, args.parent_window);
    if (result == c.GTK_RESPONSE_ACCEPT) {
        return @as(?[]const u8, try dupe_gtk_path(allocator, c.gtk_file_chooser_get_filename(chooser)));
    }
    return null;
}

pub fn pick_folder_multiple(allocator: std.mem.Allocator, args: PickFolderArgs) Error![]const []const u8 {
    const widget = create_dialog("Select Folders", c.GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER, "_Select") orelse return error.DialogError;
    defer destroy_widget(widget);

    const chooser = as_chooser(widget);
    c.gtk_file_chooser_set_select_multiple(chooser, 1);
    set_default_path(chooser, args.default_path);

    const result = run_dialog_with_parent(widget, args.parent_window);
    if (result == c.GTK_RESPONSE_ACCEPT) {
        return collect_gtk_paths(allocator, c.gtk_file_chooser_get_filenames(chooser));
    }
    return &.{};
}

/// Run the dialog, setting up window parenting if a parent handle is provided.
fn run_dialog_with_parent(widget: *c.GtkWidget, parent_window: ?WindowHandle) c.gint {
    if (parent_window) |parent| {
        switch (parent.type) {
            .x11 => set_parent_x11(widget, parent.handle),
            .wayland => set_parent_wayland(widget, parent.handle),
            else => {},
        }
    }

    return c.gtk_dialog_run(as_dialog(widget));
}

fn is_x11_display(display: *c.GdkDisplay) bool {
    // Runtime GObject type check — equivalent to GDK_IS_X11_DISPLAY macro
    const x11_type = c.gdk_x11_display_get_type();
    return c.g_type_check_instance_is_a(@ptrCast(@alignCast(display)), x11_type) != 0;
}

fn is_wayland_display(display: *c.GdkDisplay) bool {
    const wayland_type = c.gdk_wayland_display_get_type();
    return c.g_type_check_instance_is_a(@ptrCast(@alignCast(display)), wayland_type) != 0;
}

fn find_or_open_display(backend_name: [*:0]const u8, comptime check_fn: fn (*c.GdkDisplay) bool) ?*c.GdkDisplay {
    const display_manager = c.gdk_display_manager_get();

    // Check existing displays
    var display_list = c.gdk_display_manager_list_displays(display_manager);
    while (display_list) |node| {
        const display: *c.GdkDisplay = @ptrCast(@alignCast(node.*.data));
        const next = node.*.next;
        if (check_fn(display)) {
            c.g_slist_free(display_list);
            return display;
        }
        display_list = next;
    }

    // Try opening one
    c.gdk_set_allowed_backends(backend_name);
    const display = c.gdk_display_manager_open_display(display_manager, null);
    c.gdk_set_allowed_backends(null);
    if (display) |d| {
        if (check_fn(d)) return d;
        c.gdk_display_close(d);
    }
    return null;
}

fn set_parent_x11(widget: *c.GtkWidget, handle: *anyopaque) void {
    const x11_display = find_or_open_display("x11", is_x11_display) orelse return;
    const screen = c.gdk_display_get_default_screen(x11_display) orelse return;
    c.gtk_window_set_screen(@ptrCast(@alignCast(widget)), screen);

    // Realize the widget so it gets a GdkWindow, then set transient parent
    c.gtk_widget_realize(widget);
    const child_window = c.gtk_widget_get_window(widget) orelse return;
    const x11_handle: c.Window = @intFromPtr(handle);
    const parent_gdk_window = c.gdk_x11_window_foreign_new_for_display(x11_display, x11_handle) orelse return;
    c.gdk_window_set_transient_for(child_window, parent_gdk_window);
}

fn set_parent_wayland(widget: *c.GtkWidget, handle: *anyopaque) void {
    const wayland_display = find_or_open_display("wayland", is_wayland_display) orelse return;
    const screen = c.gdk_display_get_default_screen(wayland_display) orelse return;
    c.gtk_window_set_screen(@ptrCast(@alignCast(widget)), screen);

    // Wayland parenting requires xdg-foreign export — not yet fully implemented.
    // Setting the screen ensures the dialog uses the correct Wayland display.
    _ = handle;
}

fn create_dialog(title: [*:0]const u8, action: c_uint, accept_label: [*:0]const u8) ?*c.GtkWidget {
    return c.gtk_file_chooser_dialog_new(
        title,
        null,
        @intCast(action),
        @as([*:0]const u8, "_Cancel"),
        @as(c_int, c.GTK_RESPONSE_CANCEL),
        accept_label,
        @as(c_int, c.GTK_RESPONSE_ACCEPT),
        @as(?*anyopaque, null),
    );
}

fn destroy_widget(widget: *c.GtkWidget) void {
    wait_for_cleanup();
    c.gtk_widget_destroy(widget);
    wait_for_cleanup();
}

fn wait_for_cleanup() void {
    while (c.gtk_events_pending() != 0) {
        _ = c.gtk_main_iteration();
    }
}

fn as_chooser(widget: *c.GtkWidget) *c.GtkFileChooser {
    return @ptrCast(@alignCast(widget));
}

fn as_dialog(widget: *c.GtkWidget) *c.GtkDialog {
    return @ptrCast(@alignCast(widget));
}

fn set_default_path(chooser: *c.GtkFileChooser, default_path: ?[]const u8) void {
    if (default_path) |path| {
        if (path.len > 0) {
            _ = c.gtk_file_chooser_set_current_folder(chooser, path.ptr);
        }
    }
}

fn add_filters(chooser: *c.GtkFileChooser, filter_list: []const FilterItem) void {
    for (filter_list) |item| {
        const filter = c.gtk_file_filter_new();

        // Build friendly name: "Name (spec)"
        var name_buf: [512]u8 = undefined;
        const friendly = std.fmt.bufPrint(&name_buf, "{s} ({s})", .{ item.name, item.spec }) catch item.name;
        var name_z: [513]u8 = undefined;
        @memcpy(name_z[0..friendly.len], friendly);
        name_z[friendly.len] = 0;
        c.gtk_file_filter_set_name(filter, @ptrCast(&name_z));

        // Parse comma-separated extensions and add as glob patterns
        var spec = item.spec;
        while (spec.len > 0) {
            var end: usize = 0;
            while (end < spec.len and spec[end] != ',') : (end += 1) {}

            const ext = spec[0..end];
            if (ext.len > 0) {
                var pat_buf: [260]u8 = undefined;
                const pattern = std.fmt.bufPrint(&pat_buf, "*.{s}", .{ext}) catch continue;
                pat_buf[pattern.len] = 0;
                c.gtk_file_filter_add_pattern(filter, @ptrCast(&pat_buf));
            }

            if (end < spec.len) {
                spec = spec[end + 1 ..];
            } else {
                break;
            }
        }

        c.gtk_file_chooser_add_filter(chooser, filter);
    }

    // Always add wildcard filter
    const wildcard = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(wildcard, "All files");
    c.gtk_file_filter_add_pattern(wildcard, "*");
    c.gtk_file_chooser_add_filter(chooser, wildcard);
}

/// Take a GTK-allocated C string, dupe it with the Zig allocator, and free the original.
fn dupe_gtk_path(allocator: std.mem.Allocator, gtk_path: ?[*:0]u8) Error![]const u8 {
    const path = gtk_path orelse return error.DialogError;
    defer c.g_free(path);
    const len = std.mem.len(path);
    return allocator.dupe(u8, path[0..len]) catch return error.DialogError;
}

/// Collect a GSList of GTK-allocated strings into a Zig-allocated slice, freeing the GSList.
fn collect_gtk_paths(allocator: std.mem.Allocator, list: ?*c.GSList) Error![]const []const u8 {
    if (list == null) return &.{};

    // Count items
    var count: usize = 0;
    var node = list;
    while (node) |n| : (node = n.next) {
        count += 1;
    }

    var paths = allocator.alloc([]const u8, count) catch return error.DialogError;
    var i: usize = 0;
    node = list;
    while (node) |n| : (node = n.next) {
        const cstr: [*:0]u8 = @ptrCast(n.data orelse continue);
        const len = std.mem.len(cstr);
        paths[i] = allocator.dupe(u8, cstr[0..len]) catch {
            // Free already-duped paths on failure
            for (paths[0..i]) |p| allocator.free(p);
            allocator.free(paths);
            free_gs_List(list);
            return error.DialogError;
        };
        i += 1;
    }

    free_gs_List(list);
    return paths[0..i];
}

fn free_gs_List(list: ?*c.GSList) void {
    var node = list;
    while (node) |n| {
        if (n.data) |data| c.g_free(data);
        node = n.next;
    }
    if (list) |l| c.g_slist_free(l);
}
