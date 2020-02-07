const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("NativeLoLa2", "src/lib/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    const exe = b.addExecutable("NativeLoLa2", "src/main.zig");
    exe.setBuildMode(mode);
    exe.linkLibrary(lib);
    exe.install();

    var main_tests = b.addTest("src/lib/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
