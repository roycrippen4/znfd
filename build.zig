const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const os_tag = target.result.os.tag;
    const is_linux = os_tag == .linux;

    const use_portal = is_linux and (b.option(bool, "portal", "Use xdg-desktop-portal instead of GTK on Linux") orelse false);
    const use_x11 = is_linux and (b.option(bool, "x11", "Support X11 on Linux") orelse true);
    const use_wayland = is_linux and (b.option(bool, "wayland", "Support Wayland on Linux") orelse true);
    const append_extension = is_linux and (b.option(bool, "append-extension", "Auto-append file extension in SaveDialog on Linux") orelse false);
    const case_sensitive_filter = is_linux and (b.option(bool, "case-sensitive-filter", "Make filters case sensitive on Linux") orelse false);

    const opts = b.addOptions();
    opts.addOption(bool, "portal", use_portal);
    opts.addOption(bool, "x11", use_x11);
    opts.addOption(bool, "wayland", use_wayland);
    opts.addOption(bool, "append_extension", append_extension);
    opts.addOption(bool, "case_sensitive_filter", case_sensitive_filter);

    const use_dynamic = os_tag != .windows;

    const znfd_mod = b.addModule("znfd", .{
        .target = target,
        .optimize = optimize,
        .link_libc = if (os_tag == .linux) true else null,
        .root_source_file = b.path("src/root.zig"),
    });
    znfd_mod.addOptions("opts", opts);

    // Platform-specific dependencies
    if (os_tag == .windows) {
        znfd_mod.linkSystemLibrary("ole32", .{});
        znfd_mod.linkSystemLibrary("shell32", .{});
    } else if (os_tag == .macos) {
        znfd_mod.linkFramework("AppKit", .{});
    } else if (os_tag == .linux) {
        if (use_portal) {
            znfd_mod.linkSystemLibrary("dbus-1", .{});
        } else {
            znfd_mod.linkSystemLibrary("gtk+-3.0", .{});
        }

        if (use_wayland) {
            znfd_mod.linkSystemLibrary("wayland-client", .{});

            const protocol_xml = b.path("src/xdg-foreign-unstable-v1.xml");

            const gen_header = b.addSystemCommand(&.{ "wayland-scanner", "client-header" });
            gen_header.addFileArg(protocol_xml);
            const header = gen_header.addOutputFileArg("xdg-foreign-unstable-v1.h");

            const gen_code = b.addSystemCommand(&.{ "wayland-scanner", "private-code" });
            gen_code.addFileArg(protocol_xml);
            const code = gen_code.addOutputFileArg("xdg-foreign-unstable-v1.c");

            znfd_mod.addCSourceFile(.{ .file = code });
            znfd_mod.addIncludePath(header.dirname());
        }
    }

    const linkage: std.builtin.LinkMode = if (use_dynamic) .dynamic else .static;

    const znfd = b.addLibrary(.{
        .linkage = linkage,
        .name = "znfd",
        .root_module = znfd_mod,
    });
    b.installArtifact(znfd);

    // Demo executable
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    demo_mod.addImport("znfd", znfd_mod);

    const demo = b.addExecutable(.{
        .name = "demo",
        .linkage = linkage,
        .root_module = demo_mod,
    });
    b.installArtifact(demo);

    const run_cmd = b.addRunArtifact(demo);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the demo");
    run_step.dependOn(&run_cmd.step);
}
