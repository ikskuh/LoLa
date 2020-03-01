const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const interfacePkg = std.build.Pkg{
        .name = "interface",
        .path = "libs/interface.zig",
        .dependencies = &[0]std.build.Pkg{},
    };

    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("NativeLoLa2", "src/lib/main.zig");
    lib.addPackage(interfacePkg);
    lib.setBuildMode(mode);
    lib.install();

    const exe = b.addExecutable("NativeLoLa2", "src/demo/main.zig");
    exe.setBuildMode(mode);
    exe.addPackage(interfacePkg);
    exe.addPackage(std.build.Pkg{
        .name = "lola",
        .path = "src/lib/main.zig",
        .dependencies = &[_]std.build.Pkg{
            interfacePkg,
        },
    });
    exe.install();

    var main_tests = b.addTest("src/lib/main.zig");
    main_tests.addPackage(interfacePkg);
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
