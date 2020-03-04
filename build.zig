const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const interfacePkg = std.build.Pkg{
        .name = "interface",
        .path = "libs/interface.zig",
        .dependencies = &[0]std.build.Pkg{},
    };

    const mode = b.standardReleaseOptions();

    const precompileGrammar = b.addSystemCommand(&[_][]const u8{
        "bison",
        "-d",
        "--name-prefix=grammar",
        "--file-prefix=grammar",
        "--output=grammar.tab.cpp",
        "grammar.yy",
    });
    precompileGrammar.cwd = "src/compiler/";

    const precompileLexer = b.addSystemCommand(&[_][]const u8{
        "flex",
        "--prefix=yy",
        "--nounistd",
        "--outfile=yy_lex.cpp",
        "yy.l",
    });
    precompileLexer.cwd = "src/compiler/";
    precompileLexer.step.dependOn(&precompileGrammar.step);

    // clang++ -std=c++17 -c -fno-use-cxa-atexit -o hello.o hello.cpp
    // zig build-exe -target x86_64-linux-gnu --bundle-compiler-rt --object hello.o --name hello -L /usr/lib -lc -lstdc++
    const buildCppPart = b.addSystemCommand(&[_][]const u8{
        "clang++",
        "-c",
        "-std=c++17",
        "-fno-use-cxa-atexit",
        "src/compiler/ast.cpp",
        "src/compiler/compiler.cpp",
        "src/compiler/error.cpp",
        "src/compiler/il.cpp",
        "src/compiler/tombstone.cpp",
        "src/compiler/yy_lex.cpp",
        "src/compiler/common.cpp",
        "src/compiler/driver.cpp",
    });
    buildCppPart.step.dependOn(&precompileLexer.step);
    buildCppPart.step.dependOn(&precompileGrammar.step);

    const exe = b.addExecutable("lola", "src/demo/main.zig");
    exe.setBuildMode(mode);
    exe.addPackage(interfacePkg);
    exe.addPackage(std.build.Pkg{
        .name = "lola",
        .path = "src/runtime/main.zig",
        .dependencies = &[_]std.build.Pkg{
            interfacePkg,
        },
    });
    exe.step.dependOn(&buildCppPart.step);
    // exe.addObjectFile("compiler.o");
    exe.install();

    var main_tests = b.addTest("src/runtime/main.zig");
    main_tests.addPackage(interfacePkg);
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
