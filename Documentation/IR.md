# LoLa Intermedia Representation

## Instructions

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
	- pops `num` elements and packs them into an array front to back
	- stack top will be the first element
- `call_fn` calls a function `[ fun:str ] [argc:u8 ]`
	- pops `argc` elements into the argument list, then calls function `fun`
	- stack top will be the first argument
- `call_obj` calls an object method `[ fun:str ] [argc:u8 ]`
	- pops `argc` elements into the argument list,
	- then pops the object to call,
	- then calls function `fun`
	- stack top will be the first argument
- `pop` destroys stack top
	- pops a value and discards it
- `add` adds rhs and lhs together
	- first pops the left hand side,
	- then the right hand side,
	- then adds right to left, pushes the result
- `sub` subtracts rhs and lhs together
	- first pops the left hand side,
	- then the right hand side,
	- then subtracts right from left, pushes the result
- `mul` multiplies rhs and lhs together
	- first pops the left hand side,
	- then the right hand side,
	- then multiplies left and right, pushes the result
- `div` divides rhs and lhs together
	- first pops the left hand side,
	- then the right hand side,
	- then divides left by right, pushing the divisor
- `mod` reminder division of rhs and lhs
	- first pops the left hand side,
	- then the right hand side,
	- then divides left by right, pushing the remainder
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
- `neq`
- `less_eq`
- `greater_eq`
- `less`
- `greater`
- `jmp` jumps unconditionally `[target:u32 ]`
	- Sets the instruction pointer to `target`
- `jnf` jump when not false `[target:u32 ]`
	- Pops a value from the stack
	- If that value is `true`
		- Sets the instruction pointer to `target`
- `iter_make`
- `iter_next`
- `array_store`
- `array_load`
- `ret` returns from the current function with Void
	- returns from the function call with a `void` value
- `store_local` stores a local variable `[index : u16 ]`
- `load_local` loads a local variable `[index : u16 ]`
- `retval` returns from the current function with a value
	- pops a value from the stack
	- returns from the function call with the popped value
- `jif` jump when false `[ target:u32 ]`
	- Pops a value from the stack
	- If that value is `false`
		- Sets the instruction pointer to `target`
- `store_global_idx` stores global variable by index `[ idx:u16 ]`
- `load_global_idx` loads global variable by index `[ idx:u16 ]`

## Example

```asm
000000	<main>:
000000		call_fn CreateStack, 0
00000F		store_global 0
000012		push_num 10
00001B		load_global 0
00001E		call_obj Push, 1
000026		pop
000027		push_num 20
000030		load_global 0
000033		call_obj Push, 1
00003B		pop
00003C		push_num 30
000045		load_global 0
000048		call_obj Push, 1
000050		pop
000051		push_str 'mul'
000057		call_fn Operation, 1
000064		pop
000065		push_str 'add'
00006B		call_fn Operation, 1
000078		pop
000079		push_str 'print'
000081		call_fn Operation, 1
00008E		pop
00008F		load_global 0
000092		call_obj GetSize, 0
00009D		push_str 'Stack Length: '
0000AE		call_fn Print, 2
0000B7		pop
0000B8		ret
0000B9	Operation:
0000B9		load_local 0
0000BC		push_str 'print'
0000C4		eq
0000C5		jif DE
0000CA		load_global 0
0000CD		call_obj Pop, 0
0000D4		call_fn Print, 1
0000DD		pop
0000DE		load_local 0
0000E1		push_str 'add'
0000E7		eq
0000E8		jif 11A
0000ED		load_global 0
0000F0		call_obj Pop, 0
0000F7		store_local 1
0000FA		load_global 0
0000FD		call_obj Pop, 0
000104		store_local 2
000107		load_local 1
00010A		load_local 2
00010D		add
00010E		load_global 0
000111		call_obj Push, 1
000119		pop
00011A		load_local 0
00011D		push_str 'mul'
000123		eq
000124		jif 156
000129		load_global 0
00012C		call_obj Pop, 0
000133		store_local 1
000136		load_global 0
000139		call_obj Pop, 0
000140		store_local 2
000143		load_local 1
000146		load_local 2
000149		mul
00014A		load_global 0
00014D		call_obj Push, 1
000155		pop
000156		ret
```
