const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_portal = b.option(bool, "portal", "Use xdg-desktop-portal instead of GTK on Linux") orelse false;
    const use_x11 = b.option(bool, "x11", "Support X11 on Linux") orelse true;
    const use_wayland = b.option(bool, "wayland", "Support Wayland on Linux") orelse true;
    const append_extension = b.option(bool, "append-extension", "Auto-append file extension in SaveDialog on Linux") orelse false;
    const case_sensitive_filter = b.option(bool, "case-sensitive-filter", "Make filters case sensitive on Linux") orelse false;

    // Capture the build options for the library to use.
    const opts = b.addOptions();
    opts.addOption(bool, "portal", use_portal);
    opts.addOption(bool, "x11", use_x11);
    opts.addOption(bool, "wayland", use_wayland);
    opts.addOption(bool, "append_extension", append_extension);
    opts.addOption(bool, "case_sensitive_filter", case_sensitive_filter);

    const znfd_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/root.zig"),
    });
    znfd_mod.addOptions("opts", opts);

    // Platform-specific dependencies
    const os_tag = target.result.os.tag;
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

            // Generate wayland protocol code from vendored XML
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

    const znfd = b.addLibrary(.{
        .linkage = .dynamic,
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
        .linkage = .dynamic,
        .root_module = demo_mod,
    });
    b.installArtifact(demo);

    const run_cmd = b.addRunArtifact(demo);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the demo");
    run_step.dependOn(&run_cmd.step);
}
