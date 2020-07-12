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
- [Examples](Examples/README.md)
- [Bison Grammar](NativeLoLa/src/grammar.yy)
- [Flex Tokenizer](NativeLoLa/src/yy.ll)
- [TODO List](TODO.md)

## Building

**Requirements:**

- Bison 3.2 or newer
- Flex 2.6 or newer
- The [Zig Compiler](https://ziglang.org/) (Version 0.6.0+12a7dedb1 or newer)

**Building:**

```
zig build
./zig-cache/bin/lola
```
