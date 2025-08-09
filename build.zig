const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main def-to-lib converter executable
    const exe = b.addExecutable(.{
        .name = "def2lib",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link against Windows libraries for COFF generation
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("kernel32");
        exe.linkSystemLibrary("user32");
    }

    b.installArtifact(exe);

    // def2lib DLL for C/C++ integration
    const dll = b.addSharedLibrary(.{
        .name = "def2lib",
        .root_source_file = b.path("src/def2lib_dll.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link against Windows libraries for DLL
    if (target.result.os.tag == .windows) {
        dll.linkSystemLibrary("kernel32");
        dll.linkSystemLibrary("user32");
    }

    b.installArtifact(dll);

    // Install header file
    const header_install = b.addInstallFile(b.path("include/def2lib.h"), "include/def2lib.h");
    b.getInstallStep().dependOn(&header_install.step);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the def2lib converter");
    run_step.dependOn(&run_cmd.step);

    // DLL build step
    const dll_step = b.step("dll", "Build only the def2lib DLL");
    dll_step.dependOn(&dll.step);
    dll_step.dependOn(&header_install.step);

    // DLL test executable
    const dll_test = b.addExecutable(.{
        .name = "dll_test",
        .target = target,
        .optimize = optimize,
    });
    dll_test.addCSourceFile(.{
        .file = b.path("test/dll_test.c"),
        .flags = &.{},
    });
    dll_test.addIncludePath(b.path("zig-out/include"));
    dll_test.linkLibrary(dll);
    dll_test.linkLibC();

    const dll_test_install = b.addInstallArtifact(dll_test, .{});

    const dll_test_step = b.step("test-dll", "Build and run DLL tests");
    dll_test_step.dependOn(&dll_test_install.step);

    const run_dll_test = b.addRunArtifact(dll_test);
    run_dll_test.step.dependOn(&dll_test_install.step);

    const run_dll_test_step = b.step("run-dll-test", "Run the DLL test");
    run_dll_test_step.dependOn(&run_dll_test.step);

    // Tests
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/def_parser.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
