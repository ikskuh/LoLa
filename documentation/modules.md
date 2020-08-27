#  LoLa Module Format

Native LoLa has a binary module format that contains compiled intermediate code. This format both contains meta-data like function names, but also the compiled code.

## Data Structure

The description uses a file notation similar to Zig syntax. Each segment of the file is described as a structure with fields. The fields are packed and don't have any padding bits. Each field is noted by name, colon, type, and an optional fixed value.

 `u8`, `u16`, … denote a unsigned integer type with *n* bits, `[x]T` is an Array of `x` times `T` where `T` is a type and `x` is either a constant or variable size of a field declared earlier.

Some fields are commented with C++ style comments, introduced by a `//`.

```rust
// Structure of the whole file
File {
  header: FileHeader,  // contains the module header
  globalCount: u16,    // number of global script variables
  temporaryCount: u16, // number of temporary variables (global)
  functionCount: u16,  // number of declared functions
  codeSize: u32,       // size of the intermediate code in bytes
  numSymbols: u32,     // number of debug symbols
  functions: [functionCount]Function, // contains the function meta data
  code: [codeSize]u8, // intermediate code
  debugSymbols: [numSymbols]DebugSymbol, // debug symbols
}

FileHeader {
  identifier: [8]u8 = "LoLa\xB9\x40\x80\x5A"
  version: u32 = 1,   // will increment in future versions
  comment: [256]u8,   // zero terminated
}

Function {
  name: [128]u8,   // zero-terminated function name
  entryPoint: u32, // start of the function in the intermediate code
  localCount: u16, // number of local variable slots.
}

DebugSymbol {
  offset: u32,       // offset in code
  sourceLine: u32,   // line of the original source
  sourceColumn: u16, // 
}
```

