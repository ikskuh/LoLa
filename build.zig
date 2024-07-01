const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("sdkPath requires an absolute path!");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

const Example = struct {
    name: []const u8,
    path: []const u8,
};

const examples = [_]Example{
    Example{
        .name = "minimal-host",
        .path = "examples/host/minimal-host/main.zig",
    },
    Example{
        .name = "multi-environment",
        .path = "examples/host/multi-environment/main.zig",
    },
    Example{
        .name = "serialization",
        .path = "examples/host/serialization/main.zig",
    },
};

pub fn build(b: *Build) !void {
    const version_tag = b.option([]const u8, "version", "Sets the version displayed in the docs and for `lola version`");

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const mod_args = b.dependency("args", .{}).module("args");
    // const mod_interface = b.dependency("interface", .{}).module("interface.zig");
    const mod_any_pointer = b.dependency("any_pointer", .{}).module("any-pointer");

    const mod_lola = b.addModule("lola", .{
        .root_source_file = b.path("src/library/main.zig"),
        .imports = &.{
            // .{ .name = "interface", .module = mod_interface },
            .{ .name = "any-pointer", .module = mod_any_pointer },
        },
    });

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version_tag orelse "development");

    const exe = b.addExecutable(.{
        .name = "lola",
        .root_source_file = b.path("src/frontend/main.zig"),
        .optimize = optimize,
        .target = target,
    });
    exe.root_module.addImport("lola", mod_lola);
    exe.root_module.addImport("args", mod_args);
    exe.root_module.addAnonymousImport("build_options", .{
        .root_source_file = build_options.getSource(),
    });
    b.installArtifact(exe);

    const benchmark_renderer = b.addExecutable(.{
        .name = "benchmark-render",
        .root_source_file = b.path("src/benchmark/render.zig"),
        .optimize = optimize,
        .target = b.host,
    });
    b.installArtifact(benchmark_renderer);

    {
        const render_benchmark_step = b.step("render-benchmarks", "Runs the benchmark suite.");

        const only_render_benchmark = b.addRunArtifact(benchmark_renderer);
        only_render_benchmark.addArg(b.pathFromRoot("benchmarks/data"));
        only_render_benchmark.addArg(b.pathFromRoot("benchmarks/visualization"));

        render_benchmark_step.dependOn(&only_render_benchmark.step);
    }

    const benchmark_modes = [_]std.builtin.Mode{
        .ReleaseSafe, .ReleaseFast, .ReleaseSmall,
    };
    const benchmark_step = b.step("benchmark", "Runs the benchmark suite.");

    const render_benchmark = b.addRunArtifact(benchmark_renderer);
    render_benchmark.addArg(b.pathFromRoot("benchmarks/data"));
    render_benchmark.addArg(b.pathFromRoot("benchmarks/visualization"));
    benchmark_step.dependOn(&render_benchmark.step);

    for (benchmark_modes) |benchmark_mode| {
        const benchmark = b.addExecutable(.{
            .name = b.fmt("benchmark-{s}", .{@tagName(benchmark_mode)}),
            .root_source_file = b.path("src/benchmark/perf.zig"),
            .optimize = benchmark_mode,
            .target = b.host,
        });
        benchmark.root_module.addImport("lola", mod_lola);

        const run_benchmark = b.addRunArtifact(benchmark);
        run_benchmark.addArg(b.pathFromRoot("benchmarks/code"));
        run_benchmark.addArg(b.pathFromRoot("benchmarks/data"));

        render_benchmark.step.dependOn(&run_benchmark.step);
    }

    const wasm_runtime = b.addExecutable(.{
        .name = "lola",
        .root_source_file = b.path("src/wasm-compiler/main.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = .ReleaseSafe,
    });
    wasm_runtime.entry = .disabled;
    wasm_runtime.root_module.addImport("lola", mod_lola);
    b.installArtifact(wasm_runtime);

    const examples_step = b.step("examples", "Compiles all examples");
    inline for (examples) |example| {
        const example_exe = b.addExecutable(.{
            .name = "example-" ++ example.name,
            .root_source_file = b.path(example.path),
            .optimize = optimize,
            .target = target,
        });
        example_exe.root_module.addImport("lola", mod_lola);

        examples_step.dependOn(&b.addInstallArtifact(example_exe, .{}).step);
    }

    const compiler_lola_mod = b.createModule(.{
        .root_source_file = b.path("src/test/compiler.lola"),
    });

    var main_tests = b.addTest(.{
        .root_source_file = b.path("src/library/test.zig"),
        .optimize = optimize,
        .target = b.host,
    });
    // main_tests.root_module.addImport("interface", mod_interface);
    main_tests.root_module.addImport("any-pointer", mod_any_pointer);
    main_tests.root_module.addImport("compiler.lola", compiler_lola_mod);
    // main_tests.main_pkg_path = b.path(".");

    const test_step = b.step("test", "Run test suite");
    test_step.dependOn(&b.addRunArtifact(main_tests).step);

    // Run compiler test suites
    {
        const prefix = "src/test/";

        const behaviour_tests = b.addRunArtifact(exe);
        behaviour_tests.addArg("run");
        behaviour_tests.addArg("--no-stdlib"); // we don't want the behaviour tests to be run with any stdlib functions
        behaviour_tests.addArg(prefix ++ "behaviour.lola");
        behaviour_tests.expectStdOutEqual("Behaviour test suite passed.\n");
        test_step.dependOn(&behaviour_tests.step);

        const stdib_test = b.addRunArtifact(exe);
        stdib_test.addArg("run");
        stdib_test.addArg(prefix ++ "stdlib.lola");
        stdib_test.expectStdOutEqual("Standard library test suite passed.\n");
        test_step.dependOn(&stdib_test.step);

        // when the host is windows, this won't work :(
        if (builtin.os.tag != .windows) {
            std.fs.cwd().makeDir(".zig-cache/tmp") catch |err| switch (err) {
                error.PathAlreadyExists => {}, // nice
                else => |e| return e,
            };

            const runlib_test = b.addRunArtifact(exe);

            // execute in the zig-cache directory so we have a "safe" playfield
            // for file I/O
            runlib_test.cwd = b.path(".zig-cache/tmp");

            // `Exit(123)` is the last call in the runtime suite
            runlib_test.expectExitCode(123);

            runlib_test.expectStdOutEqual(
                \\
                \\1
                \\1.2
                \\[ ]
                \\[ 1, 2 ]
                \\truefalse
                \\hello
                \\Runtime library test suite passed.
                \\
            );

            runlib_test.addArg("run");
            runlib_test.addArg("../../" ++ prefix ++ "runtime.lola");

            test_step.dependOn(&runlib_test.step);
        }

        const emptyfile_test = b.addRunArtifact(exe);
        emptyfile_test.addArg("run");
        emptyfile_test.addArg(prefix ++ "empty.lola");
        emptyfile_test.expectStdOutEqual("");
        test_step.dependOn(&emptyfile_test.step);

        const globreturn_test = b.addRunArtifact(exe);
        globreturn_test.addArg("run");
        globreturn_test.addArg(prefix ++ "global-return.lola");
        globreturn_test.expectStdOutEqual("");
        test_step.dependOn(&globreturn_test.step);

        const extended_behaviour_test = b.addRunArtifact(exe);
        extended_behaviour_test.addArg("run");
        extended_behaviour_test.addArg(prefix ++ "behaviour-with-stdlib.lola");
        extended_behaviour_test.expectStdOutEqual("Extended behaviour test suite passed.\n");
        test_step.dependOn(&extended_behaviour_test.step);

        const compiler_test = b.addRunArtifact(exe);
        compiler_test.addArg("compile");
        compiler_test.addArg("--verify"); // verify should not emit a compiled module
        compiler_test.addArg(prefix ++ "compiler.lola");
        compiler_test.expectStdOutEqual("");
        test_step.dependOn(&compiler_test.step);
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Documentation and Website generation.
    if (b.option(bool, "enable-website", "Enables website generation.") orelse true) {
        const mod_koino = b.dependency("koino", .{
            .optimize = optimize,
            .target = target,
        }).module("koino");

        // Generates documentation and future files.
        const gen_website_step = b.step("website", "Generates the website and all required resources.");

        const md_renderer = b.addExecutable(.{
            .name = "markdown-md-page",
            .root_source_file = b.path("src/tools/render-md-page.zig"),
            .optimize = optimize,
            .target = target,
        });
        md_renderer.root_module.addImport("koino", mod_koino);

        const render = b.addRunArtifact(md_renderer);
        render.addArg(version_tag orelse "development");
        gen_website_step.dependOn(&render.step);

        const copy_wasm_runtime = b.addSystemCommand(&[_][]const u8{
            "cp",
        });
        copy_wasm_runtime.addArtifactArg(wasm_runtime);
        copy_wasm_runtime.addArg("website/lola.wasm");
        gen_website_step.dependOn(&copy_wasm_runtime.step);
    }

    //     var gen_docs_runner = b.addTest(pkgs.lola.source.path);
    //     // gen_docs_runner.emit_bin = .no_emit;
    //     gen_docs_runner.emit_asm = .no_emit;
    //     gen_docs_runner.emit_bin = .no_emit;
    //     gen_docs_runner.emit_docs = .{ .emit_to = "website/docs" };
    //     gen_docs_runner.emit_h = false;
    //     gen_docs_runner.emit_llvm_ir = .no_emit;
    //     for (pkgs.lola.dependencies.?) |dep| {
    //         gen_docs_runner.addPackage(dep);
    //     }
    //     gen_docs_runner.setBuildMode(optimize);
    //     gen_docs_runner.setMainPkgPath(".");

    //     gen_website_step.dependOn(&gen_docs_runner.step);

    //     // Only generates documentation
    //     const gen_docs_step = b.step("docs", "Generate the code documentation");
    //     gen_docs_step.dependOn(&gen_docs_runner.step);
}
