# LoLa-native
Reimplementation of the LoLa language in Zig and C++.

## Short Example
```js
var list = [ "Hello", "World" ];
for(text in list) {
	Print(text);
}
```

## Starting Points

- [Documentation](Documentation/README.md)
- [Examples](tree/master/Examples)
- [Bison Grammar](NativeLoLa/src/grammar.yy)
- [Flex Tokenizer](NativeLoLa/src/yy.ll)

## Building

**Requirements:**

- Bison 3.2 or newer
- Flex 2.6 or newer
- The [Zig Compiler](https://ziglang.org/) (Version 0.5.0+330e30aec or newer)
- [libc++](https://libcxx.llvm.org/) with C++17 support
- glibc

**Building:**

```
zig build
./zig-cache/bin/lola
```
