# LoLa Intermedia Language

This document describes all available instructions of the Lola intermediate language as well as it's encoding in a binary stream.

## Instructions

The following list contains each instruction and describes it's effects on the virtual machine state.

- `nop` No operation
- `store_global_name` stores global variable by name `[ var:str ]`
	- pops a value and stores it in the environment-global `str`
- `load_global_name` loads global variable by name `[ var:str ]`
	- pushes a value stored in the environment-global `str`
- `push_str` pushes string literal  `[ val:str ]`
	- pushes the string `str`
- `push_num` pushes number literal  `[ val:f64 ]`
	- pushes the number `val`
- `array_pack` packs *num* elements into an array `[ num:u16 ]`
	- pops `num` elements front-to-back and packs them into an array front to back
	- stack top will be the first element
- `call_fn` calls a function `[ fun:str ] [argc:u8 ]`
	- pops `argc` elements front-to-back into the argument list, then calls function `fun`
	- stack top will be the first argument
- `call_obj` calls an object method `[ fun:str ] [argc:u8 ]`
	- pops `argc` elements front-to-back into the argument list,
	- then pops the object to call,
	- then calls function `fun`
	- stack top will be the first argument
- `pop` destroys stack top
	- pops a value and discards it
- `add` adds rhs and lhs together
	- first pops the right hand side,
	- then the left hand side,
	- then adds right to left, pushes the result
- `sub` subtracts rhs and lhs together
	- first pops the right hand side,
	- then the left hand side,
	- then subtracts right from left, pushes the result
- `mul` multiplies rhs and lhs together
	- first pops the left hand side,
	- then the right hand side,
	- then multiplies left and right, pushes the result
- `div` divides rhs and lhs together
	- first pops the left hand side,
	- then the right hand side,
	- then divides left by right, pushing the divisor
- `mod` modulo division of rhs and lhs
	- first pops the left hand side,
	- then the right hand side,
	- then divides left by right, pushing the module
	- `(-5 % 2) == 1`
- `bool_and` conjunct rhs and lhs
	- first pops the left hand side,
	- then the right hand side,
	- then pushes `true` when both left and right hand side are `true`
- `bool_or` disjuncts rhs and lhs
	- first pops the left hand side,
	- then the right hand side,
	- then pushes `true` when either of left or right hand side is `true`
- `bool_not` logically inverts stack top
	- pops a value from the stack
	- pushs `true` if the value was `false`, otherwise `true`
- `negate` arithmetically inverts stack top
	- pops a value from the stack
	- then pushes the negative value
- `eq`
  - pops two values from the stack and compares if they are equal
  - pushes a boolean containing the result of the comparison
- `neq`
  - pops two values from the stack and compares if they are not equal
  - pushes a boolean containing the result of the comparison
- `less_eq`
  - first pops the right hand side,
  - then the left hand side,
  - then pushes `true` when left hand side is less or equal to the right hand side.
- `greater_eq`
  - first pops the right hand side,
  - then the left hand side,
  - then pushes `true` when left hand side is greater or equal to the right hand side.
- `less`
  - first pops the right hand side,
  - then the left hand side,
  - then pushes `true` when left hand side is less to the right hand side.
- `greater`
  - first pops the right hand side,
  - then the left hand side,
  - then pushes `true` when left hand side is greater to the right hand side.
- `jmp` jumps unconditionally `[target:u32 ]`
	- Sets the instruction pointer to `target`
- `jnf` jump when not false `[target:u32 ]`
	- Pops a value from the stack
	- If that value is `true`
		- Sets the instruction pointer to `target`
- `iter_make`
  - Pops an *array* from the stack
  - Creates an *iterator* over that *array*.
  - Pushes the created *iterator*.
- `iter_next`
  - Peeks an *iterator* from the stack
  - If that *iterator* still has values to yield:
    - Push the *value* from the *iterator*
    - Push `true`
    - Advance the iterator by 1
  - else:
    - Push `false`
- `array_store`
  - Then pops the *array* from the stack
  - Then pops the *index* from the stack
  - Pops the *value* from the stack
  - Stores *value* at *index* in *array*
  - Pushes *array* to the stack.
- `array_load`
  - Pops *array* from the stack
  - Pops *index* from the stack
  - Loads a *value* from the *array* at *index*
  - Pushes *value* to the stack
- `ret` returns from the current function with Void
	- returns from the function call with a `void` value
- `store_local` stores a local variable `[index : u16 ]`
  - Pops a *value* from the stack
  - Stores that *value* in the function-local variable at *index*.
- `load_local` loads a local variable `[index : u16 ]`
  - Loads a *value* from the function-local *index*.
  - Pushes that *value* to the stack.
- `retval` returns from the current function with a value
	- pops a value from the stack
	- returns from the function call with the popped value
- `jif` jump when false `[ target:u32 ]`
	- Pops a value from the stack
	- If that value is `false`
		- Sets the instruction pointer to `target`
- `store_global_idx` stores global variable by index `[ idx:u16 ]`
  - Pops a value from the stack
  - Stores this value in the object-global storage
- `load_global_idx` loads global variable by index `[ idx:u16 ]`
  - Loads a value from the object-global storage
  - Pushes that value to the stack
- `push_true`
  - pushes literal boolean `true`
- `push_false`
  - pushes literal boolean `false`
- `push_void`
  - pushes void value

## Encoding

### Instructions

The instructions are encoded in an intermediate language. Each instruction is encoded by a single byte, followed by arguments different for each instruction.

Argument types are noted in `name:type` notation where type is one of the following: `str`, `f64`, `u16`, `u8`, `u32`. The encoding of these types is described below the table.

| Instruction       | Value | Arguments          | Description                                    |
| ----------------- | ----- | ------------------ | ---------------------------------------------- |
| nop               | 0     |                    | No operation                                   |
| scope_push        | 1     |                    | *reserved*                                     |
| scope_pop         | 2     |                    | *reserved*                                     |
| declare           | 3     | `var:str`          | *reserved*                                     |
| store_global_name | 4     | `var:str`          | stores global variable by name                 |
| load_global_name  | 5     | `var:str`          | loads global variable by name                  |
| push_str          | 6     | `val:str`          | pushes string literal                          |
| push_num          | 7     | `val:f64`          | pushes number literal                          |
| array_pack        | 8     | `num:u16`          | packs *num* elements into an array             |
| call_fn           | 9     | `fun:str, argc:u8` | calls a function                               |
| call_obj          | 10    | `fun:str, argc:u8` | calls an object method                         |
| pop               | 11    |                    | destroys stack top                             |
| add               | 12    |                    | adds rhs and lhs together                      |
| sub               | 13    |                    | subtracts rhs and lhs together                 |
| mul               | 14    |                    | multiplies rhs and lhs together                |
| div               | 15    |                    | divides rhs and lhs together                   |
| mod               | 16    |                    | reminder division of rhs and lhs               |
| bool_and          | 17    |                    | conjunct rhs and lhs                           |
| bool_or           | 18    |                    | disjuncts rhs and lhs                          |
| bool_not          | 19    |                    | logically inverts stack top                    |
| negate            | 20    |                    | arithmetically inverts stack top               |
| eq                | 21    |                    |                                                |
| neq               | 22    |                    |                                                |
| less_eq           | 23    |                    |                                                |
| greater_eq        | 24    |                    |                                                |
| less              | 25    |                    |                                                |
| greater           | 26    |                    |                                                |
| jmp               | 27    | `target:u32`       | jumps unconditionally                          |
| jnf               | 28    | `target:u32`       | jump when not false                            |
| iter_make         | 29    |                    |                                                |
| iter_next         | 30    |                    |                                                |
| array_store       | 31    |                    |                                                |
| array_load        | 32    |                    |                                                |
| ret               | 33    |                    | returns from the current function with Void    |
| store_local       | 34    | `index:u16`        |                                                |
| load_local        | 35    | `index:u16`        |                                                |
| retval            | 37    |                    | returns from the current function with a value |
| jif               | 38    | `target:u32`       | jump when false                                |
| store_global_idx  | 39    | `idx:u16`          | stores global variable by index                |
| load_global_idx   | 40    | `idx:u16`          | loads global variable by index                 |
| push_true | 41 | | pushes a boolean `true` |
| push_false | 42 | | pushes a boolean `false` |
| push_void | 43 | | pushes a `void` value. |

### Types

#### `u8`, `u16`, `u32`

Each of these corresponds to a single, little endian encoded unsigned integer with either 8, 16 or 32 bits width.

#### `f64`

A 64 bit floating point number, encoded with **IEEE 754** *binary64* format, also known as `double`.

#### `str`

A literal string value with a maximum of 65535 bytes length. It's text is encoded in an application-defined encoding where all values below 128 must follow the ASCII encoding scheme. Values equal or above 128 are interpreted by an application-defined logic.

A string is started by a 16 bit unsigned integer defining the length of the string, followed by *length* bytes of content.

**Rationale:** The encoding is not fixed to UTF-8 as the language is meant to be embedded into games where a unicode encoding would be a burden to the player. Thus, a string is defined to be "at least" ASCII-compatible and allows UTF-8 encoding, but does not enforce this.