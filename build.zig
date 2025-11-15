const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var setup_smixml: ?*std.Build.Step.Run = null;
    if (builtin.target.os.tag == .windows) {
        const dotnet_publish = b.addSystemCommand(&[_][]const u8 {
            "dotnet",
            "publish",
            "smixml/smixml/smixml.csproj",
            "-c",
            "Release",
            "-r",
            "win-x64",
            "/p:Platform=\"Any CPU\"",
            "-o",
            "./lib/"
        });

        const copy_import = b.addSystemCommand(&[_][]const u8 {
            "pwsh",
            "-c",
            "copy",
            "'smixml\\smixml\\bin\\Any CPU\\Release\\net9.0\\win-x64\\native\\smixml.lib'",
            ".\\lib\\"
        });
        copy_import.step.dependOn(&dotnet_publish.step);

        const make_include_dir = b.addSystemCommand(&[_][]const u8 {
            "pwsh",
            "-c",
            "mkdir",
            "include",
            "-Force"
        });
        make_include_dir.step.dependOn(&copy_import.step);

        const extract_header = b.addSystemCommand(&[_][]const u8{
            "pwsh",
            "-File",
            "ExtractHeader.ps1",
            "-DllPath",
            "smixml/smixml/bin/Any CPU/Release/net9.0/win-x64/smixml.dll",
            "-OutputHeaderPath",
            "include/smixml.h"
        });
        extract_header.step.dependOn(&make_include_dir.step);

        setup_smixml = extract_header;
    }

    const mod = b.addModule("smilez", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addIncludePath(b.path("include"));

    mod.addLibraryPath(b.path("lib"));
    mod.linkSystemLibrary("smixml", .{
        .preferred_link_mode = .dynamic
    });

    const lib = b.addLibrary(.{
        .name = "smilez",
        .linkage = .static,
        .root_module = mod
    });
    lib.step.dependOn(&setup_smixml.?.step);

    const exe_mod = b.addModule("smilezapp", .{
        .root_source_file = b.path("src/smilezapp/main.zig"),
        .target = target,
        .optimize = optimize
    });
    exe_mod.addImport("smilez", mod);
    exe_mod.link_libc = true;

    const exe = b.addExecutable(.{
        .name = "smilezapp",
        .root_module = exe_mod
    });

    b.installArtifact(exe);
    b.installArtifact(lib);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
