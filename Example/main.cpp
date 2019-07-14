#include <iostream>

#include "lolacore.hpp"

char const * const my_code = R"LoLa(

function Fibonacci1(num)
{
    if (num <= 1) {
        return 1;
    }
    return Fibonacci(num - 1) + Fibonacci(num - 2);
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

Print("Fibonacci(4) = ");
Print(Fibonacci1(4));
Print(Fibonacci2(4));

var counter = CreateCounter();
Print("cnt = ", counter.GetValue());
Print("cnt = ", counter.Increment());
Print("cnt = ", counter.Increment());
Print("cnt = ", counter.Decrement());

var list = [ "This", "is", "a" ];
list = list + [ "Sentence" ];
Print(list);

var a = 10;
Print(a);
a = "Hallo";
Print(a);

)LoLa";


int main()
{
    auto const success = LoLa::verify(my_code);

    if(success)
        std::cout << "good" << std::endl;
    else
        std::cout << "bad" << std::endl;

    return success ? 0 : 1;
}
