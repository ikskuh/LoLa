# LoLa Programming Language

LoLa is a small programming language meant to be embedded into games. The compiler and runtime are implemented in Zig and C++.

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

- [Bison Grammar](src/library/compiler/grammar.yy)
- [Flex Tokenizer](src/library/compiler/yy.l)
- [TODO List](TODO.md)

## Building

**Requirements:**

Required:
- The [Zig Compiler](https://ziglang.org/) (Version 0.6.0+60ea87340 or newer)

Optional dependencies for development:
- Bison 3.2 or newer (optional)
- Flex 2.6 or newer (optional)

**Building:**

```
zig build
./zig-cache/bin/lola
```
