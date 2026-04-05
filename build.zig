const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const os_tag = target.result.os.tag;
    const use_dynamic = os_tag != .windows;

    const znfd_mod = b.addModule("znfd", .{
        .target = target,
        .optimize = optimize,
        .link_libc = if (os_tag == .linux) true else null,
        .root_source_file = b.path("src/root.zig"),
    });

    // Platform-specific dependencies
    if (os_tag == .windows) {
        znfd_mod.linkSystemLibrary("ole32", .{});
        znfd_mod.linkSystemLibrary("shell32", .{});
    } else if (os_tag == .macos) {
        znfd_mod.linkFramework("AppKit", .{});
    } else if (os_tag == .linux) {
        znfd_mod.linkSystemLibrary("gtk+-3.0", .{});
        znfd_mod.linkSystemLibrary("dbus-1", .{});
    }

    const linkage: std.builtin.LinkMode = if (use_dynamic) .dynamic else .static;

    const znfd = b.addLibrary(.{
        .linkage = linkage,
        .name = "znfd",
        .root_module = znfd_mod,
    });
    b.installArtifact(znfd);
}
