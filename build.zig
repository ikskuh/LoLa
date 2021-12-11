const std = @import("std");
const builtin = @import("builtin");
const Builder = std.build.Builder;

pub fn createPackage(comptime root: []const u8) std.build.Pkg {
    return std.build.Pkg{
        .name = "lola",
        .path = .{ .path = root ++ "/src/library/main.zig" },
        .dependencies = &[_]std.build.Pkg{
            std.build.Pkg{
                .name = "interface",
                .path = .{ .path = root ++ "/libs/interface.zig/interface.zig" },
            },
            std.build.Pkg{
                .name = "any-pointer",
                .path = .{ .path = root ++ "/libs/any-pointer/any-pointer.zig" },
            },
        },
    };
}

const linkPcre = @import("libs/koino/vendor/libpcre.zig/build.zig").linkPcre;

const pkgs = struct {
    const args = std.build.Pkg{
        .name = "args",
        .path = .{ .path = "libs/args/args.zig" },
        .dependencies = &[_]std.build.Pkg{},
    };

    const interface = std.build.Pkg{
        .name = "interface",
        .path = .{ .path = "libs/interface.zig/interface.zig" },
        .dependencies = &[_]std.build.Pkg{},
    };

    const lola = std.build.Pkg{
        .name = "lola",
        .path = .{ .path = "src/library/main.zig" },
        .dependencies = &[_]std.build.Pkg{ interface, any_pointer },
    };

    const koino = std.build.Pkg{
        .name = "koino",
        .path = .{ .path = "libs/koino/src/koino.zig" },
        .dependencies = &[_]std.build.Pkg{
            std.build.Pkg{ .name = "libpcre", .path = .{ .path = "libs/koino/vendor/libpcre.zig/src/main.zig" } },
            std.build.Pkg{ .name = "htmlentities", .path = .{ .path = "libs/koino/vendor/htmlentities.zig/src/main.zig" } },
            std.build.Pkg{ .name = "clap", .path = .{ .path = "libs/koino/vendor/zig-clap/clap.zig" } },
            std.build.Pkg{ .name = "zunicode", .path = .{ .path = "libs/koino/vendor/zunicode/src/zunicode.zig" } },
        },
    };

    const any_pointer =
        std.build.Pkg{
        .name = "any-pointer",
        .path = .{ .path = "libs/any-pointer/any-pointer.zig" },
    };
};

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

pub fn build(b: *Builder) !void {
    const version_tag = b.option([]const u8, "version", "Sets the version displayed in the docs and for `lola version`");

    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version_tag orelse "development");

    const exe = b.addExecutable("lola", "src/frontend/main.zig");
    exe.setBuildMode(mode);
    exe.setTarget(target);
    exe.addPackage(pkgs.lola);
    exe.addPackage(pkgs.args);
    exe.addPackage(build_options.getPackage("build_options"));
    exe.install();

    const wasm_runtime = b.addSharedLibrary("lola", "src/wasm-compiler/main.zig", .unversioned);
    wasm_runtime.addPackage(pkgs.lola);
    wasm_runtime.setTarget(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    wasm_runtime.setBuildMode(.ReleaseSafe);
    wasm_runtime.install();

    const examples_step = b.step("examples", "Compiles all examples");
    inline for (examples) |example| {
        const example_exe = b.addExecutable("example-" ++ example.name, example.path);
        example_exe.setBuildMode(mode);
        example_exe.setTarget(target);
        example_exe.addPackage(pkgs.lola);

        examples_step.dependOn(&b.addInstallArtifact(example_exe).step);
    }

    var main_tests = b.addTest("src/library/test.zig");
    if (pkgs.lola.dependencies) |deps| {
        for (deps) |pkg| {
            main_tests.addPackage(pkg);
        }
    }
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run test suite");
    test_step.dependOn(&main_tests.step);

    // Run compiler test suites
    {
        const prefix = "src/test/";

        const behaviour_tests = exe.run();
        behaviour_tests.addArg("run");
        behaviour_tests.addArg("--no-stdlib"); // we don't want the behaviour tests to be run with any stdlib functions
        behaviour_tests.addArg(prefix ++ "behaviour.lola");
        behaviour_tests.expectStdOutEqual("Behaviour test suite passed.\n");
        test_step.dependOn(&behaviour_tests.step);

        const stdib_test = exe.run();
        stdib_test.addArg("run");
        stdib_test.addArg(prefix ++ "stdlib.lola");
        stdib_test.expectStdOutEqual("Standard library test suite passed.\n");
        test_step.dependOn(&stdib_test.step);

        // when the host is windows, this won't work :(
        if (builtin.os.tag != .windows) {
            std.fs.cwd().makeDir("zig-cache/tmp") catch |err| switch (err) {
                error.PathAlreadyExists => {}, // nice
                else => |e| return e,
            };

            const runlib_test = exe.run();

            // execute in the zig-cache directory so we have a "safe" playfield
            // for file I/O
            runlib_test.cwd = "zig-cache/tmp";

            // `Exit(123)` is the last call in the runtime suite
            runlib_test.expected_exit_code = 123;

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

        const emptyfile_test = exe.run();
        emptyfile_test.addArg("run");
        emptyfile_test.addArg(prefix ++ "empty.lola");
        emptyfile_test.expectStdOutEqual("");
        test_step.dependOn(&emptyfile_test.step);

        const globreturn_test = exe.run();
        globreturn_test.addArg("run");
        globreturn_test.addArg(prefix ++ "global-return.lola");
        globreturn_test.expectStdOutEqual("");
        test_step.dependOn(&globreturn_test.step);

        const extended_behaviour_test = exe.run();
        extended_behaviour_test.addArg("run");
        extended_behaviour_test.addArg(prefix ++ "behaviour-with-stdlib.lola");
        extended_behaviour_test.expectStdOutEqual("Extended behaviour test suite passed.\n");
        test_step.dependOn(&extended_behaviour_test.step);

        const compiler_test = exe.run();
        compiler_test.addArg("compile");
        compiler_test.addArg("--verify"); // verify should not emit a compiled module
        compiler_test.addArg(prefix ++ "compiler.lola");
        compiler_test.expectStdOutEqual("");
        test_step.dependOn(&compiler_test.step);
    }

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    /////////////////////////////////////////////////////////////////////////
    // Documentation and Website generation:
    // this is disabed by-default so we don't depend on any vcpkgs
    if (b.option(bool, "enable-website", "Enables website generation.") orelse false) {
        // Generates documentation and future files.
        const gen_website_step = b.step("website", "Generates the website and all required resources.");

        const md_renderer = b.addExecutable("markdown-md-page", "src/tools/render-md-page.zig");
        md_renderer.addPackage(pkgs.koino);
        try linkPcre(md_renderer);

        const render = md_renderer.run();
        render.addArg(version_tag orelse "development");
        gen_website_step.dependOn(&render.step);

        const copy_wasm_runtime = b.addSystemCommand(&[_][]const u8{
            "cp",
        });
        copy_wasm_runtime.addArtifactArg(wasm_runtime);
        copy_wasm_runtime.addArg("website/lola.wasm");
        gen_website_step.dependOn(&copy_wasm_runtime.step);

        var gen_docs_runner = b.addTest(pkgs.lola.path.path);
        gen_docs_runner.emit_bin = .no_emit;
        gen_docs_runner.emit_asm = .no_emit;
        gen_docs_runner.emit_bin = .no_emit;
        gen_docs_runner.emit_docs = .no_emit;
        gen_docs_runner.emit_h = false;
        gen_docs_runner.emit_llvm_ir = .no_emit;
        gen_docs_runner.addPackage(pkgs.interface);
        gen_docs_runner.addPackage(pkgs.any_pointer);
        gen_docs_runner.setBuildMode(mode);

        const move_docs = b.addSystemCommand(&[_][]const u8{
            "cp",
            "docs/index.html",
            "docs/data.js",
            "docs/main.js",
            "website/docs/",
        });
        move_docs.step.dependOn(&gen_docs_runner.step);
        gen_website_step.dependOn(&move_docs.step);

        // Only generates documentation
        const gen_docs_step = b.step("docs", "Generate the code documentation");
        gen_docs_step.dependOn(&gen_docs_runner.step);
    }
}
