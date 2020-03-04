const std = @import("std");
const Builder = std.build.Builder;

// clang++ -std=c++17 -c -fno-use-cxa-atexit -o hello.o hello.cpp
// zig build-exe -target x86_64-linux-gnu --bundle-compiler-rt --object hello.o --name hello -L /usr/lib -lc -lstdc++

const interfacePkg = std.build.Pkg{
    .name = "interface",
    .path = "libs/interface.zig",
    .dependencies = &[0]std.build.Pkg{},
};
const argsPkg = std.build.Pkg{
    .name = "args",
    .path = "libs/args.zig",
    .dependencies = &[0]std.build.Pkg{},
};

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{
        .default_target = std.zig.CrossTarget{
            .glibc_version = .{
                .major = 2,
                .minor = 30,
            },
        },
    });

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

    const cppSources = [_][]const u8{
        "src/compiler/ast.cpp",
        "src/compiler/compiler.cpp",
        "src/compiler/error.cpp",
        "src/compiler/il.cpp",
        "src/compiler/tombstone.cpp",
        "src/compiler/yy_lex.cpp",
        "src/compiler/common.cpp",
        "src/compiler/driver.cpp",
        "src/compiler/runtime.cpp",
        "src/compiler/grammar.tab.cpp",
    };

    const lib = b.addStaticLibrary("lola", "src/runtime/main.zig");
    lib.step.dependOn(&precompileLexer.step);
    lib.step.dependOn(&precompileGrammar.step);
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.addPackage(interfacePkg);
    lib.addIncludeDir("/usr/include/c++/v1");
    lib.addIncludeDir("/usr/include");
    for (cppSources) |cppSource| {
        lib.addCSourceFile(cppSource, &[_][]const u8{
            "-std=c++17",
            "-fno-use-cxa-atexit",
            "-Wall",
            "-Wextra",
        });
    }
    lib.install();

    const exe = b.addExecutable("lola", "src/demo/main.zig");
    exe.setBuildMode(mode);
    exe.setTarget(target);
    exe.addPackage(argsPkg);
    exe.addPackage(interfacePkg);
    exe.addPackage(std.build.Pkg{
        .name = "lola",
        .path = "src/runtime/main.zig",
        .dependencies = &[_]std.build.Pkg{
            interfacePkg,
        },
    });

    exe.addCSourceFile("src/frontend/main.cpp", &[_][]const u8{
        "-std=c++17",
        "-fno-use-cxa-atexit",
    });

    // exe.step.dependOn(&buildCppPart.step);
    exe.addIncludeDir("/usr/include/c++/v1");
    exe.addIncludeDir("/usr/include");
    exe.addLibPath("/usr/lib/");
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("c++");
    exe.linkLibrary(lib);
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
