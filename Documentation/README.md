# The LoLa Programming Language

## Introduction

LoLa is a small programming language developed to be embedded in games. It's not meant as a scripting language to create games with but as language to be programmed *in the game* by the player.

The design goals of the language were:

- Easy to learn
- Small set of language features
- No complex features, there are only value types
- Exhaustible execution – Limit how long a certain script run at most in a single script call

## Hello World

```lola
Print("Hello, World!");
```

As you can see, the *Hello World*-Program is quite short and expressive. The language itself uses a C-like syntax with semicolons at the end of a statement.

More [Examples](#Examples) can be found at the end of the document.

## Additional Documents

These documents contain additional information about implementation details of the current runtime generation.

- [The LoLa Programming Language – Quick Reference](LoLa.md)
- [C++ API Usage](API.md) (Deprecated)
- [Intermedia Representation](IR.md)
- [Compiled Modules](Modules.md)

## Comments

LoLa provides only single-line comments:

```lola
// This is a comment

Print("Hello"); // this is a statement, followed by a comment
```

Everything that is in a comment is ignored by the compiler. A comment is introduced by a double-slash (`//`) and is ended by a line feed character or the end of the file.

## Types

The language provides a small set of types data can have:

| Type      | Description                                                  |
| --------- | ------------------------------------------------------------ |
| `void`    | The `void` type can only have a single value (which is also `void`) and indicates the absence of a value. Functions that do not return something will return this. |
| `boolean` | A truth value, which is either `true` or `false`. This type is the result of comparisons and can be passed to conditionals. It is also the input to the [boolean algebra](https://en.wikipedia.org/wiki/Boolean_algebra) operators. |
| `number`  | A [IEEE-754 binary64](https://en.wikipedia.org/wiki/Double-precision_floating-point_format) encoded real number. This is the basic type for all algebraic operations. |
| `string`  | A [string](https://en.wikipedia.org/wiki/String_(computer_science)) in LoLa is a sequence of bytes, usually encodes text as [ASCII](https://en.wikipedia.org/wiki/ASCII) or [UTF-8](https://en.wikipedia.org/wiki/UTF-8). |
| `object`  | An object is a thing that has an interface with callable methods. |
| `array`   | An array is a sequence of arbitrary values.                  |

## Literals

Literals provide a way to create a primitive value in the language. All of the types except `object` have a literal syntax:

| Type      | Examples                                      |
| --------- | --------------------------------------------- |
| `void`    | `void` (no other values are allowed)          |
| `boolean` | `true`, `false` (no other values are allowed) |
| `number`  | `0`, `1`, `0.0`, `10.0`, `0.25`, `13.37`, …   |
| `string`  | `"Hello, World!"`, `""`, `"One\nTwo\nThree"`  |
| `array`   | `[]`, `[1,2,3,4,5]`, `[true, false, void]`    |

### String Escape Sequence

As strings are contained in double quotes and don't allow to contain a line feed, one needs the possibility to escape those characters. For this, LoLa provides two ways to include escaped and non-printable characters in a string:

- Use a hexadecimal escape (`\x63`)
- Use one of the predefined escape shorthands (`\r`, `\n`)

The hexadecimal escape allows the programmer to embed any byte value into the string. It is introduced by the escape character `\`, followed by a small `x`, then a two-digit hexadecimal number. The number is then converted into a byte value and inserted into the string.

The predefined escape codes provide often-required whitespace and control characters without the need to remember their exact value:

| Shorthand | ASCII Value | Name            |
| --------- | ----------- | --------------- |
| `\a`      | 7           | Alert / Bell    |
| `\b`      | 8           | Backspace       |
| `\t`      | 9           | Horizontal Tab  |
| `\n`      | 10          | Line Feed       |
| `\r`      | 13          | Carriage Return |
| `\e`      | 27          | Escape          |
| `\"`      | 34          | Double Quotes   |
| `\'`      | 39          | Single Quote    |

## Variables

Variables provide a way to store something beyond the context of a single computation.

```lola
var x;      // Uninitialized, global variable
var y = 10; // Initialized global variable

{
	var z;     // Unitialized local variable
	var w = 0; // Initialized local variable
}

extern foo; // External variable
```

There are three kind of variables in LoLa:

- Global Variables
- Local Variables
- External Variables

Global variables are accessible from any scope and are stored in the execution environment. If a global variable has no initializer, it's value is preserved over multiple calls of the script.

Local variables could also be called temporary variables as they are only alive for a short time. A local variables is any variable declared in brackets, so explicit declared locals, loop variables and function parameters.

External variables are special variables that have no defined storage in the script. They are provided by the executing environment. The contents and semantics of those variables is documented by the environment.

All variables are dynamically typed and may change the type of the stored value on assignment.

### Shadowing

LoLa allows shadowing of variable names. This means, that you can have a variable with the same name as a previously declared variable. The previously declared variable will be hidden (shadowed) by the newly declared variable for the scope of the shadowing variable.

## Operators

LoLa provides several operators that execute arithmetic, logic or comparison operations.

### Table of Operators

| Operator | Applies to                  | Description                               | Example                                                      |
| -------- | --------------------------- | ----------------------------------------- | ------------------------------------------------------------ |
| `a + b` <br /> `a += b` | `string`, `number`, `array` | Adds numbers, concats strings and arrays. | `3 + 2 == 5`, `"a" + "b" == "ab"`, `[ 1, 2 ] + [ 3 ] == [ 1, 2, 3 ]` |
| `a - b` <br />`a -= b` | `number` |Subtraction|`5 - 2 == 3`|
| `-a`  | `number` | Negation |`-(4) == -4`|
| `a * b` <br />`a *= b` | `number` |Multiplication|`5 * 2 == 10`|
| `a / b `<br />`a /= b` | `number` |Division|`10 / 5 == 2`|
| `a % b` <br />`a %= b` | `number` |Remainder Division|`10 % 4 == 2`|
| `a and b` | `boolean` |Boolean AND|`true and false == false`|
| `a or b` | `boolean` |Boolean OR|`true or false == true`|
| `not a` | `boolean` |Boolean NOT|`not false == true`|
| `a == b` | *all* |Equality test|`(3 == 3) == true`|
| `a != b` | *all* |Inequality test|`(3 != 2) == true`|
| `a >= b` | `number` |Greater-or-equal test|`(3 >= 2) == true`|
| `a <= b` | `number` |Less-or-equal test|`(3 <= 2) == false`|
| `a > b` | `number` |Greater-than test|`(3 > 2) == true`|
| `a < b` | `number` |Less-than test|`(3 < 2) == false`|
| `a[i]` | `array` | Array index | `([1,2,3])[1] == 2` |

### Operator Precedence 

Operator precedence in the list low to high. A higher precedence means that these operators *bind* more to the variables and will be applied first.

#### Binary

- `and`, `or`
- `==`, `!=`, `>=`, `<=`, `>`, `<`
- `+`, `-`
- `*`, `/`, `%`

#### Unary

- `not`, `-`
- `a[i]`

## Control Flow Structures

LoLa provides a small set of control flow structures that are simple to use and are widespread in a lot of programming languages.

### Blocks

```lola
{ // Blocks are always introduced by a curly bracket
	var x; // local to this block
	// here is the block content
} // and are closed by a curly bracket

// x is not valid here anymore!
```

Blocks are a convenient way of introducing structure into the code. Each block has its own set of local variables, but can access the local variables of its parent as well. Each control structure in LoLa is followed by a block, but blocks can also be freestanding as in the example above.

### Assignments

Assignments in LoLa are statements that return no value. This is different from other programming languages like C that allow nesting assignments into expressions (~~`a + (b = c)`~~).

```lola
a = b; // simple assignment, copy the value from b into a.
```

An assignment will always copy the value that is assigned. It will not create equality of the two names:

```lola
a = 1;
b = a;
a = 2;
Print(a, b); // Will print "2, 1" as b has not been changed
```

You can always assign an item of array:

```lola
a[i] = c; // indexed assignment: copy the value of c into the i'th index of the array a.
```

This allows mutating the contents of the array. The same rules as for a normal variable assignment apply here.

### if`-Conditional

The conditional `if` statement provides a simple way to do things depending on a condition:

```lola
if(a > 5) {
	// This code is executed only when a > 5.
}
```

The code in the curly brackets is only executed when the condition in the round brackets is `true`. The condition must always be a `boolean` value.

If the code should do an *either-or* semantic, you can add an else block:

```lola
if(a > 5) {
	// This code is executed only when a > 5.
}
else {
	// This code is executed when a <= 5. 
}
```

The `else` part is optional.

`if` also provides a short-hand version if only a single statement is conditional:

```lola
if(condition)
	Statement(); // Function call, control flow or assignment
 
if(condition)
	Statement();
else
	Statement();
```



### `while`-Loop

If a piece of code should repeat itself, a loop structure is helpful:

```lola
while(a > 5) {
	// this code repeats as long as a > 5.
}
```

The `while` loop will check the condition in the round brackets. If the condition is `true`, the code in the curly brackets will be executed. After that, the condition will be checked again and the process starts again.

### `for`-Loop

Iterating over an array is such a common task that LoLa provides a built-in loop for that:

```lola
for(x in data) {
	// For each loop iteration, x will contain a value from data
}
```

The syntax for the loop is `for(var in data) { … }` where `var` is a new local variable, and `data` is an array value.

The loop will execute one time for each item in `data`, filling `var` with the current item. The items are processed in order.

### Function Calls

```lola
Print("Hello, World!"); // Calls the function Print with one arg.
x = GetSomething(); // stores the return value of GetSomething()
```

Function calls will execute a sub-program that may return a value to their caller. A function call may take zero or more arguments, but will always return a value. If the return value is not stored, it will be discarded.

### Method Calls

Methods calls are similar to function calls, but require an `object` value to be executed:

```lola
var obj = …; // We require a variable of type object

obj.Print("Hello, World!"); // Call the method Print on obj.
```

The `Print` in this case is not a usual function but a method. Methods are defined on objects and pass the object to the method as well.

This allows the script runtime to provide the user with more complex data structures or interfaces that are implemented via objects instead of free functions.

Objects can also represent resources like [sockets](https://en.wikipedia.org/wiki/Network_socket) or [key-value-stores](https://en.wikipedia.org/wiki/Key-value_database) that are available to the user.

### `return`

`return` will stop the execution of the current sub-program and will return control to the caller.

```lola
return; // Stop execution now, return void
return true; // Stop execution now and return true
```

`return` may take an optional value that will be returned as a result of the sub-program.

### `break`

`break` will stop the current loop. This means that it will stop the execution of the code in the loop block and will return to the end of the loop just like if the condition was `false` or the end of the array was reached.

```lola
var i = 0;
var j = 0;
while(true)
{
	i += 1;
	Print("i = ", i);
	if(i > 5)
		break; // this will stop the while-loop
	j += 1;
}
Print(i, j); // Will print 6, 5
```

### `continue`

`continue` is the counterpart to `break`: It will continue with the next loop iteration instead of completing the current one. This can be used to skip a whole bunch of code:

```lola
var a = [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
var skipped = 0;
for(x in a) {
	if(x < 3) {
		skipped += 1;
		continue;
	}
	Print(x);
}
Print("Skipped ", skipped, " elements!");
```

## Functions

Functions allows the user to declare custom sub-programs in the script:

```lola
function AddFive(a) {
	return a + 5;
}

function Compare(a, b) {
	if(a > b) {
		return "larger";
	}
	else if(a < b) {
  	return "smaller";
  } else {
  	return "equal";
  }
}
```

Functions have their own scope, and may `return` a value to their caller. 

## Top Level Code

Similar to other scripting languages, LoLa allows not only top-level declarations, but also top-level code. This means there is no `main` function that is called when starting execution, but the top-level code will be run instead.

```
// This is not a snippet, but a valid file!
SayHelloTo("me");

function SayHelloTo(name)
{
	Print("Hello, " + name + "!");
}
```

As you can see, the order of declaration is not relevant in LoLa. Functions may be called from top-level before or after declaration.

## List of Keywords

- `and`
- `break`
- `continue`
- `else`
- `extern`
- `for`
- `function`
- `if`
- `in`
- `not`
- `or`
- `return`
- `var`
- `while`

## Wording

The following chapter explains some of the words used in this document with concrete focus on the meaning inside LoLa.

### Statement

A statement is something that can be written as a line of code or execution unit.

The following constructs count as statements:

- Conditionals (`if`)
- Loops (`while`, `for`)
- Everything with a semicolon at the end (`a = …;`, `a[i] = …;`, `Print("Hi!");`)

### Expression

An expression is something that yields a value that can be used in another expression or can be assigned to a value.

Examples for expressions are:

- `1`
- `"Hello"`
- `expr + expr`
- `SumOf(10, 20)`
- …

LoLa does not allow lone statements except for function and method calls. These are special in a way that they may discard their value. The resulting value of all other expressions may not be discarded.

## Examples

The following section will contain small examples on how to use the language.

### Sum the values of an array

```lola
var a = [ 1, 2, 3 ];
var sum = 0;
for(v in a) {
	sum += a;
}
Print("Sum = ", sum);
```

### Bubble Sort

```lola
function BubbleSort(arr)
{
	var len = Length(arr);

	var n = len;
	while(n > 1) {

		var i = 0;
		while(i < n - 1) {
      if (arr[i] > arr[i+1]) {
        var tmp = arr[i];
				arr[i] = arr[i+1];
				arr[i+1] = tmp;
      }

			i += 1;
    }
		n -= 1;
  }

	return arr;
}

Print(BubbleSort([ 7, 8, 9, 3, 2, 1 ]));
```

### Reversing an array

```lola
// Reverse an array
function RevertArray(arr)
{
	var i = 0;
	var l = Length(arr);
	while(i < l/2) {
		var tmp = arr[i];
		arr[i] = arr[l - i - 1];
    arr[l - i - 1] = tmp;
    i += 1;
	}
	return arr;
}
```

### Using an object

```lola
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

