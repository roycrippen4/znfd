const std = @import("std");
const allocator = std.heap.page_allocator;

const znfd = @import("znfd");

pub fn main() !void {
    try znfd.init();
    defer znfd.deinit();

    const filters = &[_]znfd.FilterItem{
        .{ .name = "Images", .spec = "png,jpg,jpeg,bmp,gif" },
        .{ .name = "Documents", .spec = "pdf,txt,md" },
    };

    var last_dir: ?[]const u8 = null;
    defer if (last_dir) |d| allocator.free(d);

    {
        std.debug.print("\n--- Open File Dialog ---\n", .{});
        const path = try znfd.open_dialog(allocator, .{ .filter_list = filters });
        if (path) |p| {
            defer allocator.free(p);
            std.debug.print("Selected: {s}\n", .{p});
            last_dir = parent_dir(p);
        } else {
            std.debug.print("Cancelled.\n", .{});
        }
    }

    {
        std.debug.print("\n--- Open Multiple Files Dialog ---\n", .{});
        const paths = try znfd.open_dialog_multiple(allocator, .{
            .filter_list = filters,
            .default_path = last_dir,
        });
        defer {
            for (paths) |p| allocator.free(p);
            allocator.free(paths);
        }

        if (paths.len > 0) {
            std.debug.print("Selected {d} file(s):\n", .{paths.len});
            for (paths, 1..) |p, i| std.debug.print("  [{d}] {s}\n", .{ i, p });
            update_last_dir(&last_dir, paths[0]);
        } else {
            std.debug.print("Cancelled.\n", .{});
        }
    }

    {
        std.debug.print("\n--- Save File Dialog ---\n", .{});
        const path = try znfd.save_dialog(allocator, .{
            .filter_list = filters,
            .default_path = last_dir,
            .default_name = "untitled.png",
        });
        if (path) |p| {
            defer allocator.free(p);
            std.debug.print("Save to: {s}\n", .{p});
            update_last_dir(&last_dir, p);
        } else {
            std.debug.print("Cancelled.\n", .{});
        }
    }

    {
        std.debug.print("\n--- Pick Folder Dialog ---\n", .{});
        const path = try znfd.pick_folder(allocator, .{
            .default_path = last_dir,
        });
        if (path) |p| {
            defer allocator.free(p);
            std.debug.print("Folder: {s}\n", .{p});
            if (last_dir) |d| allocator.free(d);
            last_dir = allocator.dupe(u8, p) catch null;
        } else {
            std.debug.print("Cancelled.\n", .{});
        }
    }

    {
        std.debug.print("\n--- Pick Multiple Folders Dialog ---\n", .{});
        const paths = try znfd.pick_folder_multiple(allocator, .{
            .default_path = last_dir,
        });
        defer {
            for (paths) |p| allocator.free(p);
            allocator.free(paths);
        }

        if (paths.len > 0) {
            std.debug.print("Selected {d} folder(s):\n", .{paths.len});
            for (paths, 1..) |p, i| std.debug.print("  [{d}] {s}\n", .{ i, p });
        } else {
            std.debug.print("Cancelled.\n", .{});
        }
    }

    std.debug.print("\nDone.\n", .{});
}

fn parent_dir(path: []const u8) ?[]const u8 {
    var i = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') {
            return allocator.dupe(u8, path[0..i]) catch null;
        }
    }
    return null;
}

fn update_last_dir(last_dir: *?[]const u8, path: []const u8) void {
    if (last_dir.*) |d| allocator.free(d);
    last_dir.* = parent_dir(path);
}
