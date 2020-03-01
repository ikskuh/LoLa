# NativeLola'2 TODO

## Compiler TODO
- Integrate v2 disassembler
- When new runtime done: Remove runtime features from compiler
- Add better error message handling and error messages.

## Missing features

## The great object interface refactoring
- Functions take an additional parameter: `?ObjectHandle`
  - This removes the need for an additional context parameter on the functions itself
- Introduce `ObjectPool` that will manage dynamic-lifetime objects
