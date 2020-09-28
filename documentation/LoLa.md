# LoLa – Quick Reference

## Example

```js
var stack = CreateStack();

stack.Push(10);
stack.Push(20);
stack.Push(30);

function Operation(op)
{
	if(op == "print") {
		Print(stack.Pop());
	}
	if(op == "add") {
		var lhs = stack.Pop();
		var rhs = stack.Pop();
		stack.Push(lhs + rhs);
	}
	if(op == "mul") {
		var lhs = stack.Pop();
		var rhs = stack.Pop();
		stack.Push(lhs * rhs);
	}
}

Operation("mul");
Operation("add");
Operation("print");

Print("Stack Length: ", stack.GetSize());
```

## Overview

- Allows script-style top-level code
- Dynamic typing
- Static scope


### Data Types
- Void (single value type, marks something "not existent")
- Boolean (Logic value, is either `true` or `false`)
- Number (IEEE754 binary64)
- String (ASCII-like or UTF-8 encoded string)
- Array (A ordered list of values, zero-indexed)
- Object (A thing that has methods which can be called)

### Syntax

#### Expressions

- literals
	- number (`1.0`, `4.33`, `2`, …)
	- string (`""`, `"hello"`, `"line\nfeed"`, …)
	- boolean (`true`, `false`, …)
- variable access (`x`, `var`, `var_2`, …)
- array (`[]`, `[expr]`, `[expr, expr]`, …)
- array index (`expr[expr])`
- unary operation (`-expr`, `not expr`, …)
- binary operaton (`expr + expr`, `expr and expr`, …)
- function call (`f()`, `f(expr)`, `f(expr,expr)`, …)
- method call (`o.m()`, `o.m(expr)`, …)
- parenthesis (`(expr)`)

#### Operators

Operator precedence in the list low to high. A higher precedence means
that these operators *bind* more to the variables and will be applied
first.

**Binary:**
- `and`, `or`
- `==`, `!=`, `>=`, `<=`, `>`, `<`
- `+`, `-`
- `*`, `/`, `%`

**Unary:**
- `not`, `-`

#### Statements

- terminated by semicolon (`;`)
- allowed on top level

**Elements:**
- scope (`{ … }`)
- var declaration (`var x;`, `var x = expr;` …)
- function call (`f();`, …)
- assignment (`lval = rval;`, `lval[expr] = rval;`, …)
- for loop (`for(x in expr) { … }`)
- while loop (`while(expr) { … }`)
- condition (`if(expr) { … }`, `if(expr) { … } else { … }`)
- return (`return;`, `return expr;`)

#### Function Declarations

```js
function name()
{
	…
}


function name(arg)
{
	…
}

function name(arg1, arg2)
{
	…
}
```

