# NativeLola'2 TODO

## Compiler TODO
- Integrate v2 disassembler
- When new runtime done: Remove runtime features from compiler
- Add better error message handling and error messages.

## Missing features
- String literal escaping
- Add `string` index operators?

## More tasks
- Tests for the ObjectPool struct
- Tests for VM
  - Endless loop should not be endless with execution limit
  - Instructions should yield correct errors when called with inappropriate inputs
  - Instructions should yield correct output

## Define LoLa stdlib
- Set of common functions available to all LoLa users

## Implement compiler optimizations
- Auto-constant detection
- Type deduction and error checking
- SSA-like analysis to reuse local variables

## Documentation
- Move examples to own folder / document
- Document how *custom objects* are explicitly not a thing
