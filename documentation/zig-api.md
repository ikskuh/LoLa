# Zig API

The Zig API is the main API for the LoLa implementation. It exposes all concepts in a convenient matter

## Basic Architecture

```
ObjectPool    CompileUnit
    \             /
     \           /
      \         /
       \       /
      Environment
           |
           |
     VirtualMachine
```

### Compile Unit
A structure describing a compiled LoLa source file, containing the bytecode and defined function entry points.

### Object Pool
A structure to manage LoLa objects. It's used for garbage collection, handle creation and lifetime management.

### Environment
A script execution environment. This can be seen as an instantiation of a compile unit. Each environment has its own set of global variables and functions.

### Virtual Machine
A virtual machine executes the code instantiated by one or more environments.