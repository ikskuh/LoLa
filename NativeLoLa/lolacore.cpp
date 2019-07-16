#include "lolacore.hpp"

#include "driver.hpp"

#include "compiler.hpp"
#include "runtime.hpp"

#include <sstream>

#define STR(x) #x
#define SSTR(x) STR(x)

using LoLa::Runtime::Function;
using LoLa::Runtime::Value;

struct GenericSyncFunction : LoLa::Runtime::Function
{
    std::function<Value(Value const * args, size_t cnt)> fn;

    explicit GenericSyncFunction(decltype(fn) const & f) :
        fn(f)
    {
    }

    std::unique_ptr<LoLa::Runtime::FunctionCall> call(const LoLa::Runtime::Value *args, size_t argc) const override
    {
        struct ConstValue : LoLa::Runtime::FunctionCall
        {
            Value value;
            explicit ConstValue(Value const & v) : value(v) { }

            std::optional<Value> execute(LoLa::Runtime::VirtualMachine&) override {
                return value;
            }
        };
        return std::make_unique<ConstValue>(fn(args, argc));
    }
};

bool LoLa::verify(std::string_view code)
{
    std::stringstream str;
    str.write(code.data(), code.size());
    str.seekg(0);

    LoLa::LoLaDriver driver;

    driver.parse(str);

    Compiler::Compiler compiler;

    auto compile_unit = compiler.compile(driver.program);

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

    return true;
}
