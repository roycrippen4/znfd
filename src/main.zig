const std = @import("std");
const znfd = @import("znfd");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    try znfd.init();
    defer znfd.deinit();

    // Test open dialog
    const path = try znfd.open_dialog(allocator, .{});

    if (path) |p| {
        std.debug.print("Selected: {s}\n", .{p});
        allocator.free(p);
    } else {
        std.debug.print("Cancelled.\n", .{});
    }
}
