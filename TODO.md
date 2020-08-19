# NativeLola'2 TODO

## Compiler TODO
- Add better error message handling and error messages.
  - Syntax errors yield unreadable messages atm
- Improve code gen to use chunk/file name
- Improve code gen to emit debug symbols
- Bugfix: Empty file crashes the compiler.

## Missing features
- Add `string` index operators?
- Fix operator associativity (3 - 2 - 1 => 0)

## More tasks
- Tests for the ObjectPool struct
- Tests for VM
  - Endless loop should not be endless with execution limit
  - Instructions should yield correct errors when called with inappropriate inputs
  - Instructions should yield correct output

## Define a LoLa runtime lib
- ReadFile(path)
- WriteFile(path, contents)
- FileExists(path)

## Implement compiler optimizations
- Auto-constant detection
- Type deduction and error checking
- SSA-like analysis to reuse local variables

## Documentation
- Move examples to own folder / document
- Document how *custom objects* are explicitly not a thing

## Improvements
- implement copy-on-write arrays for improved performance?
  - probably too much implementation overhead

