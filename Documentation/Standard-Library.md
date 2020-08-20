# LoLa Standard Library

This file documents the LoLa Standard Library, a set of basic routines to enable LoLa programs.

## String API

### `Length(string): number`

Returns the length of the string.

### `SubString(string, start, [length]): string`

Returns a portion of `string`. The portion starts at `start` and is `length` bytes long. If `length` is not given, only the start of the string is cut.

### `Trim(string): string`

Removes leading and trailing white space from the string. White space is on of the following ascii characters:
- `0x09` (horizontal tab)
- `0x0A` (line feed)
- `0x0B` (vertical tab)
- `0x0C` (form feed)
- `0x0D` (carriage return)
- `0x20` (space)

### `TrimLeft(string): string`

Removes leading white space from the string.

### `TrimRight(string): string`

Removes trailing white space from the string.

### `IndexOf(string, text): number|void`

Searches for the first occurrence `text` in `string`, returns the offset to the start in bytes. If `text` is not found, `void` is returned.

### `LastIndexOf(string, text): number|void`

Searches for the last occurrence of `text` in `string`, returns the offset to the start in bytes. If `text` is not found, `void` is returned.

### `Byte(string): number`

Returns the first byte of the string as a number value. If the string is empty, `void` is returned, if the string contains more than one byte, still only the first byte is considered.

### `Chr(byte): string`

Returns a string of the length 1 containing `byte` as a byte value.

### `NumToString(num, [base]=10): string`

Converts the number `num` into a string represenation to base `base`. If `base` is given, it will format the integer value of the number to `base`, otherwise, a decimal floating point output will be given.

### `StringToNum(str, [base]=10): number|void`

Converts the string `str` to a number. If `base` is not given, the number is assumed to be base 10 and a floating point value. Otherwise, `base` is used as the numeric base for conversion, and only integer values are accepted.

If the conversion fails, `void` is returned.

If `base` is 16, `0x` is accepted as a prefix, and `h` as a postfix.

## Array API

### `Range(count): array`

Returns an array with `count` increasing numbers starting at 0.

### `Range(start, count)`

Returns an array with `count` increasing numbers starting at `start`.

### `Length(array): number`

Returns the number of items in `array`.

### `Slice(array, start, length): array`

Returns a portion of the `array`, starting at `index` (inclusive) and taking up to `length` items from the array. If less items are possible, an empty array is returned.

### `IndexOf(array, item): number|void`

Returns the index of a given `item` in `array`. If the item is not found, `void` is returned.

### `LastIndexOf(array, item): number|void`

Returns the last index of a given `item` in `array`. If the item is not found, `void` is returned.

## Math

### `Pi: number`

Global constant containing the number *pi*.

### `DeltaEqual(a, b, delta): boolean`

Compares `a` and `b` with a certain `delta`. Returns `true` when `abs(a-b) < delta`.

### `Sin(a): number`, `Cos(a): number`, `Tan(a): number`

Trigonometric functions, all use radians.

### `Atan(y, [x]): number`

Calculates the arcus tangens of `y`, and, if `x` is given, divides `y` by `x` before.

Use the two-parameter version for higher precision.

### `Sqrt(x): number`

Calculates the square root of `x`.

### `Pow(v, e): number`

Returns `v` to the power of `e`.

### `Log(v, [base]): number`

Returns the logarithm of `v` to base `base`. If `base` is not given, base 10 is used.

### `Exp(v): number`

Returns *e* to the power of `v`. *e* is the euler number.

## Auxiliary

### `Sleep(secs): void`

Sleeps for `secs` seconds.

### `Timestamp(): number`

Returns the current wall clock time as a unix timestamp.

### `TypeOf(arg): string`

Returns the type of the argument as a string. Returns one of the following:

```lola
"void", "boolean", "string", "number", "object", "array"
```

### `ToString(val): string`

Converts the input `val` into a string representation.

### `HasFunction(name): boolean`

Returns `true` if the current environment has a function called `name`, `false` otherwise.

### `HasFunction(object, name): boolean`

Returns `true` if the `object` has a function called `name`, `false` otherwise.

### `Call(functionName, args): any`

Calls a function `functionName` with the given argument list `args`.

### `Call(obj, methodName, args): any`

Calls a method `methodName` on object `obj` with the given argument list `args`.
