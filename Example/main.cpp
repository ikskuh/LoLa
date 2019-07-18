#include <iostream>

#include "LoLa/ast.hpp"
#include "LoLa/compiler.hpp"
#include "LoLa/runtime.hpp"

#include <sstream>

#define STR(x) #x
#define SSTR(x) STR(x)

char const example_1[] = R"LoLa(
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

char const my_code[] = R"LoLa(

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

using LoLa::Runtime::Function;
using LoLa::Runtime::Value;

struct GenericSyncFunction : LoLa::Runtime::Function
{
    std::function<Value(Value const * args, size_t cnt)> fn;

    explicit GenericSyncFunction(decltype(fn) const & f) :
        fn(f)
    {
    }

    CallOrImmediate call(const LoLa::Runtime::Value *args, size_t argc) const override
    {
        return fn(args, argc);
    }
};

struct CounterObject : LoLa::Object
{
    double counter = 0;

    GenericSyncFunction getValue, increment, decrement;

    CounterObject() :
        getValue([this](Value const *, size_t) -> Value { return counter; }),
        increment([this](Value const *, size_t) -> Value { return ++counter; }),
        decrement([this](Value const *, size_t) -> Value { return --counter; })
    {

    }

    std::optional<LoLa::Runtime::Function const *> getFunction(std::string const & name) const override
    {
        if(name == "GetValue") {
            return &getValue;
        }
        else if(name == "Increment") {
            return &increment;
        }
        else if(name == "Decrement") {
            return &decrement;
        }
        return std::nullopt;
    }
};


struct StackObject : LoLa::Object
{
    std::vector<LoLa::Runtime::Value> contents;

    GenericSyncFunction getSize, push, pop;

    StackObject() :
        getSize([this](Value const *, size_t) -> Value { return double(contents.size()); }),
        push([this](Value const * a, size_t) -> Value { contents.push_back(a[0]); return LoLa::Runtime::Void { }; }),
        pop([this](Value const *, size_t) -> Value {
            auto val = contents.back();
            contents.pop_back();
            return val;
        })
    {

    }

    std::optional<LoLa::Runtime::Function const *> getFunction(std::string const & name) const override
    {
        if(name == "GetSize") {
            return &getSize;
        }
        else if(name == "Push") {
            return &push;
        }
        else if(name == "Pop") {
            return &pop;
        }
        return std::nullopt;
    }
};

using namespace LoLa;

int main()
{
    auto program = AST::parse(example_1);
    if(not program)
        return 1;

    Compiler::Compiler compiler;

    auto compile_unit = compiler.compile(*program);

    Compiler::Disassembler disasm;
    disasm.disassemble(*compile_unit, std::cout);

    Runtime::Environment env(compile_unit);
    env.functions["Print"] = new GenericSyncFunction([](Value const * argv, size_t argc) -> Value
    {
        for(size_t i = 0; i < argc; i++)
        {
            if(i > 0)
                std::cout << " ";
            std::cout << argv[i];
        }
        std::cout << std::endl;
        return LoLa::Runtime::Void { };
    });
    env.functions["CreateCounter"] = new GenericSyncFunction([](Value const *, size_t) -> Value
    {
        return ObjectRef(new CounterObject);
    });
    env.functions["CreateStack"] = new GenericSyncFunction([](Value const *, size_t) -> Value
    {
        return ObjectRef(new StackObject);
    });

    env.known_globals["RealGlobal"] = Value { LoLa::Runtime::Void { } };
    env.known_globals["ReadOnlyGlobal"] = std::make_pair(
        []() -> LoLa::Runtime::Value {
            return 42.0;
        },
        LoLa::Runtime::Environment::Setter()
    );

    Runtime::VirtualMachine machine { env };
    machine.enable_trace = true;

//    try
    {
        while(machine.exec() != LoLa::Runtime::ExecutionResult::Done)
        {

        }
    }
//    catch (LoLa::Error err)
//    {
//        std::cerr << to_string(err) << std::endl;
//        return false;
//    }

    return 0;
}
