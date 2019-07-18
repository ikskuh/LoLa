# LoLa-native
Reimplementation of the LoLa language in C++

## Short Example
```
var list = [ "Hello", "World" ];
for(text in list) {
	Print(text);
}
```

## Starting Points

- [Documentation](Documentation/README.md)
- [Example Project](Example/main.cpp)
- [Library Headers](NativeLoLa/include/LoLa)
- [Bison Grammar](NativeLoLa/src/grammar.yy)
- [Flex Tokenizer](NativeLoLa/src/yy.ll)

## Building

**Requirements:**

- Bison 3.0 or newer
- Flex 2.6 or newer
- QMake
- C++17 compiler

**Building:**

```
mkdir build
cd build/
qmake ../NativeLoLa.pro
make -j
```

There are two folders built:
- *Example* contains a small program that runs the example from the documentation
  with tracing enabled.
- *NativeLola* contains `libNativeLoLa.a`, the static library that contains the
  compiler and runtime.
