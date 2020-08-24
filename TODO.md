# NativeLola'2 TODO

## Bugs
- Script functions need a associated environment as when another execution environment is used as a object, the backing compile unit may change (as well as the environment)

## Compiler TODO
- Add better error message handling and error messages.
  - Syntax errors yield unreadable messages atm
- Improve code gen to use chunk/file name
- Improve code gen to emit debug symbols
- Add character literals

## Runtime Implementations
- Runtime Library
- Standard Library
  - `Serialize`
  - `Deserialize`

## Missing features
- Add `string` index operators?

## Tests
- Tests for the ObjectPool struct
- Tests for VM
  - Endless loop should not be endless with execution limit
  - Instructions should yield correct errors when called with inappropriate inputs
  - Instructions should yield correct output
- More behaviour tests
  - Object API

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

