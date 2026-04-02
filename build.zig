const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_portal = b.option(bool, "portal", "Use xdg-desktop-portal instead of GTK on Linux") orelse false;
    const use_x11 = b.option(bool, "x11", "Support X11 on Linux") orelse true;
    const use_wayland = b.option(bool, "wayland", "Support Wayland on Linux") orelse true;
    const append_extension = b.option(bool, "append-extension", "Auto-append file extension in SaveDialog on Linux") orelse false;
    const case_sensitive_filter = b.option(bool, "case-sensitive-filter", "Make filters case sensitive on Linux") orelse false;

    const znfd_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    znfd_mod.addIncludePath(b.path("src/include"));

    // Platform-specific sources and dependencies
    const os_tag = target.result.os.tag;
    if (os_tag == .windows) {
        znfd_mod.addCSourceFile(.{ .file = b.path("src/nfd_win.cpp") });
        znfd_mod.linkSystemLibrary("ole32", .{});
        znfd_mod.linkSystemLibrary("uuid", .{});
        znfd_mod.linkSystemLibrary("shell32", .{});
    } else if (os_tag == .macos) {
        znfd_mod.addCSourceFile(.{ .file = b.path("src/nfd_cocoa.m") });
        znfd_mod.linkFramework("AppKit", .{});
    } else if (os_tag == .linux) {
        if (use_portal) {
            znfd_mod.addCSourceFile(.{ .file = b.path("src/nfd_portal.cpp") });
            znfd_mod.linkSystemLibrary("dbus-1", .{});
            znfd_mod.addCMacro("NFD_PORTAL", "1");
        } else {
            znfd_mod.addCSourceFile(.{ .file = b.path("src/nfd_gtk.cpp") });
            znfd_mod.linkSystemLibrary("gtk+-3.0", .{});
        }

        if (append_extension) {
            znfd_mod.addCMacro("NFD_APPEND_EXTENSION", "1");
        }
        if (case_sensitive_filter) {
            znfd_mod.addCMacro("NFD_CASE_SENSITIVE_FILTER", "1");
        }
        if (use_x11) {
            znfd_mod.addCMacro("NFD_X11", "1");
        }
        if (use_wayland) {
            znfd_mod.addCMacro("NFD_WAYLAND", "1");
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

    // Tests — each test is a small C program that opens a dialog
    const test_sources = [_][]const u8{
        "test/test_opendialog.c",
        "test/test_opendialog_native.c",
        "test/test_opendialog_with.c",
        "test/test_opendialog_cpp.cpp",
        "test/test_opendialogmultiple.c",
        "test/test_opendialogmultiple_native.c",
        "test/test_opendialogmultiple_enum.c",
        "test/test_opendialogmultiple_enum_native.c",
        "test/test_opendialogmultiple_cpp.cpp",
        "test/test_pickfolder.c",
        "test/test_pickfolder_native.c",
        "test/test_pickfolder_with.c",
        "test/test_pickfolder_native_with.c",
        "test/test_pickfoldermultiple.c",
        "test/test_pickfoldermultiple_native.c",
        "test/test_pickfolder_cpp.cpp",
        "test/test_savedialog.c",
        "test/test_savedialog_native.c",
        "test/test_savedialog_with.c",
        "test/test_savedialog_native_with.c",
    };

    for (test_sources) |src| {
        const name = std.fs.path.stem(src);
        const is_cpp = std.mem.endsWith(u8, src, ".cpp");
        const exe_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = if (is_cpp) true else null,
        });
        exe_mod.addCSourceFile(.{ .file = b.path(src) });
        exe_mod.addIncludePath(b.path("src/include"));
        exe_mod.linkLibrary(znfd);

        const exe = b.addExecutable(.{
            .name = name,
            .linkage = .dynamic,
            .root_module = exe_mod,
        });
        b.installArtifact(exe);
    }
}
