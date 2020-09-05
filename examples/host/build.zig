const std = @import("std");

const examples = [_][]const u8{
    "minimal-host",
    "multi-environment",
};

const pkgs = struct {
    const lola = std.build.Pkg{
        .name = "lola",
        .path = "../../src/library/main.zig",
    };
};

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    inline for (examples) |example_name| {
        const exe = b.addExecutable(example_name, example_name ++ "/main.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.addPackage(pkgs.lola);
        exe.install();

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());

        const run_step = b.step(example_name, "Run the example " ++ example_name);
        run_step.dependOn(&run_cmd.step);
    }
}
