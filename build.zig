const std = @import("std");
const Builder = std.build.Builder;

// clang++ -std=c++17 -c -fno-use-cxa-atexit -o hello.o hello.cpp
// zig build-exe -target x86_64-linux-gnu --bundle-compiler-rt --object hello.o --name hello -L /usr/lib -lc -lstdc++

const interfacePkg = std.build.Pkg{
    .name = "interface",
    .path = "libs/interface.zig/interface.zig",
    .dependencies = &[0]std.build.Pkg{},
};
const argsPkg = std.build.Pkg{
    .name = "args",
    .path = "libs/args/args.zig",
    .dependencies = &[0]std.build.Pkg{},
};

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{
        .default_target = if (std.builtin.os.tag == .windows)
            std.zig.CrossTarget.parse(.{ .arch_os_abi = "native-native-gnu" }) catch unreachable
        else
            std.zig.CrossTarget{},
    });

    const precompileGrammar = b.addSystemCommand(&[_][]const u8{
        "bison",
        "-d",
        "--name-prefix=grammar",
        "--file-prefix=grammar",
        "--output=grammar.tab.cpp",
        "grammar.yy",
    });
    precompileGrammar.cwd = "src/library/compiler/";

    const precompileLexer = b.addSystemCommand(&[_][]const u8{
        "flex",
        "--prefix=yy",
        "--nounistd",
        "--outfile=yy_lex.cpp",
        "yy.l",
    });
    precompileLexer.cwd = "src/library/compiler/";
    precompileLexer.step.dependOn(&precompileGrammar.step);

    const cppSources = [_][]const u8{
        "src/library/compiler/ast.cpp",
        "src/library/compiler/compiler.cpp",
        "src/library/compiler/error.cpp",
        "src/library/compiler/yy_lex.cpp",
        "src/library/compiler/driver.cpp",
        "src/library/compiler/grammar.tab.cpp",
    };

    const lib = b.addStaticLibrary("liblola", "./src/library/main.zig");
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.addPackage(interfacePkg);
    lib.addIncludeDir("./libs/flex");
    lib.linkLibC();
    lib.linkSystemLibrary("c++");
    for (cppSources) |cppSource| {
        lib.addCSourceFile(cppSource, &[_][]const u8{
            "-std=c++17",
            "-fno-use-cxa-atexit",
            "-Wall",
            "-Wextra",
        });
    }
    lib.install();

    const exe = b.addExecutable("lola", "./src/frontend/main.zig");
    exe.setBuildMode(mode);
    exe.setTarget(target);
    exe.addPackage(argsPkg);
    exe.addPackage(interfacePkg);
    exe.addPackage(std.build.Pkg{
        .name = "lola",
        .path = "./src/library/main.zig",
        .dependencies = &[_]std.build.Pkg{
            interfacePkg,
        },
    });

    exe.addCSourceFile("src/frontend/compile_lola_source.cpp", &[_][]const u8{
        "-std=c++17",
        "-fno-use-cxa-atexit",
    });

    // exe.step.dependOn(&buildCppPart.step);
    // exe.addIncludeDir("/usr/include/c++/v1");
    // exe.addIncludeDir("/usr/include");
    // exe.addLibPath("/usr/lib/");
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("c++");
    exe.linkLibrary(lib);
    exe.install();

    var main_tests = b.addTest("src/library/main.zig");
    main_tests.addPackage(interfacePkg);
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run test suite");
    test_step.dependOn(&main_tests.step);

    // Run compiler test suites
    {
        const behaviour_tests = exe.run();
        behaviour_tests.addArg("run");
        behaviour_tests.addArg("--no-stdlib"); // we don't want the behaviour tests to be run with any stdlib functions
        behaviour_tests.addArg("./test/behaviour.lola");
        test_step.dependOn(&behaviour_tests.step);

        const stdib_test = exe.run();
        stdib_test.addArg("run");
        stdib_test.addArg("./test/stdlib.lola");
        test_step.dependOn(&stdib_test.step);

        const emptyfile_test = exe.run();
        emptyfile_test.addArg("run");
        emptyfile_test.addArg("./test/empty.lola");
        test_step.dependOn(&emptyfile_test.step);

        const compiler_test = exe.run();
        compiler_test.addArg("compile");
        compiler_test.addArg("--verify"); // verify should not emit a compiled module
        compiler_test.addArg("./test/empty.lola");
        test_step.dependOn(&compiler_test.step);
    }

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const refresh_step = b.step("refresh", "Recompiles flex/bison grammar files");
    refresh_step.dependOn(&precompileLexer.step);
    refresh_step.dependOn(&precompileGrammar.step);
}
