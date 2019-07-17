#include <iostream>

#include "lolacore.hpp"

char const * const example_1 = R"LoLa(
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
)LoLa";

char const * const my_code = R"LoLa(

function Fibonacci1(num)
{
    if (num <= 1) {
        return 1;
    }
    return Fibonacci1(num - 1) + Fibonacci1(num - 2);
}

function Fibonacci2(num)
{
    var a = 1;
    var b = 0;
    var temp;

    while (num >= 0)
    {
        temp = a;
        a = a + b;
        b = temp;
        num = num - 1;
    }

    return b;
}

function Retless(a)
{
    Print("a = ", a);
}

Print("Fibonacci(4) = ");
Print(Fibonacci1(4));
Print(Fibonacci2(4));

var list = [ "This", "is", "a" ];
list = list + [ "Sentence" ];
Print(list);

// is this comment?
var a = 10;
Print(a);
a = "Hallo";
Print(a);

var glob;
function SetGlob(x) {
    glob = x;
    Print("Set glob to '", x, "'");
}
SetGlob("glob-content");
Print("glob is '", glob, "'");

var counter = CreateCounter();
Print("cnt = ", counter.GetValue());
Print("cnt = ", counter.Increment());
Print("cnt = ", counter.Increment());
Print("cnt = ", counter.Decrement());

RealGlobal = 10;

Print(ReadOnlyGlobal);
// ReadOnlyGlobal = 10;

list[1] = "was";
Print(list[0]);

for(x in list) {
    Print(x);
}

)LoLa";


int main()
{
    auto const success = LoLa::verify(example_1);

    if(success)
        std::cout << "good" << std::endl;
    else
        std::cout << "bad" << std::endl;

    return success ? 0 : 1;
}
