# NativeLola'2 TODO

## Compiler TODO
- Add better error message handling and error messages.

## Missing features
- Add `string` index operators?
- Fix operator associativity (3 - 2 - 1 => 0)

## More tasks
- Tests for the ObjectPool struct
- Tests for VM
  - Endless loop should not be endless with execution limit
  - Instructions should yield correct errors when called with inappropriate inputs
  - Instructions should yield correct output

## Define LoLa stdlib
- Set of common functions available to all LoLa users
- String API
  - Length(str)
  - SubString(string, start, [length])
  - Trim(string)
  - TrimLeft(string)
  - TrimRight(string)
  - IndexOf(string, text)
  - LastIndexOf(string, text)
  - Byte(str)
  - Chr(byte)
  - NumToString(num, [base]=10)
  - StringToNum(str, [base]=10)
- Array API
  - Range(count)
  - Range(start, count)
  - Length(array)
  - Slice(array, start, end)
  - IndexOf(array, item)
  - LastIndexOf(array, item)
- Math
  - Pi
  - Sin(a)
  - Cos(a)
  - Tan(a)
  - Atan(y, [x])
  - Sqrt(x)
  - Pow(v, e)
  - Log(v, [base])
  - Exp(v)
- Aux
  - Call(functionName, args)
  - Call(obj, methodName, args)
  - Sleep(secs)
  - TypeOf(arg)

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

