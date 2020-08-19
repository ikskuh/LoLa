# LoLa Programming Language

LoLa is a small programming language meant to be embedded into games to be programmed by the players. The compiler and runtime are implemented in Zig and C++.

## Short Example
```js
var list = [ "Hello", "World" ];
for(text in list) {
	Print(text);
}
```

You can find more examples in the [Examples](Examples/) folder.

## Starting Points

To get familiar with LoLa, you can check out these starting points:

- [Documentation](Documentation/README.md)
- [Examples](Examples/README.md)

When you want to contribute to the compiler, check out the following documents:

- [Source Code](src/)
- [Bison Grammar](src/library/compiler/grammar.yy)
- [Flex Tokenizer](src/library/compiler/yy.l)
- [TODO List](TODO.md)

## Building

![CI](https://github.com/MasterQ32/LoLa-native/workflows/CI/badge.svg?branch=master)

**Requirements:**

Required:
- The [Zig Compiler](https://ziglang.org/) (Version 0.6.0+60ea87340 or newer)

Optional dependencies for development:
- Bison 3.2 or newer (optional)
- Flex 2.6 or newer (optional)

**Building:**

```sh
zig build
./zig-cache/bin/lola
```

**Running the test suite:**

When you change things in the compiler or VM implementation, run the test suite:

```sh
zig build test
```

This will execute all zig tests, and also runs a set of predefined tests within the [`tests/`](tests/) folder. These tests will verify that the compiler and language runtime behave correctly.