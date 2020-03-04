#ifndef RUNTIME_HPP
#define RUNTIME_HPP

#include "il.hpp"
#include "compiler.hpp"
#include "error.hpp"

#include <variant>
#include <string>
#include <memory>
#include <vector>
#include <list>
#include <ostream>
#include <functional>

#include "common.hpp"

namespace LoLa::Runtime
{
enum ExecutionResult
{
    Exhausted = 0, //!< Code is still running, but we ran out of quota
    Done = 1,      //!< Code has stopped running and is done
    Paused = 2,    //!< Code has yielded manually and returned control to caller
};

//! Execution environment.
//! May be an Object or just a plain environment.
struct Environment : LoLa::Object
{
    using Getter = std::function<Value()>;
    using Setter = std::function<void(Value)>;
    using GlobalVariable = std::variant<
        Value,                    // internal stored
        Value *,                  // external reference
        std::pair<Getter, Setter> // "smart" variable
        >;

    explicit Environment(std::shared_ptr<const LoLa::Compiler::CompilationUnit> code);

    std::shared_ptr<const LoLa::Compiler::CompilationUnit> code;

    // contains pointers to all available "native" functions
    std::map<std::string, Function const *> functions;
    std::vector<Value> script_globals;
    std::map<String, GlobalVariable> known_globals;

    std::optional<Function const *> getFunction(std::string const &name) const override;
};

struct VirtualMachine
{
    struct ExecutionContext : Compiler::CodeReader, FunctionCall
    {
        struct ManualYield
        {
        };

        std::vector<Value> data_stack;
        std::vector<Value> locals;

        Value pop();
        void push(Value const &v);
        Value &peek();

        std::variant<std::monostate, Value, ManualYield> exec(VirtualMachine &vm);

        std::optional<Value> execute(VirtualMachine &vm) override;

        void resumeFromCall(VirtualMachine &vm, Value const &result) override;

        Environment *override_env = nullptr;
    };

    Environment *env;

    explicit VirtualMachine(Environment &env, size_t entryPoint = 0);

    bool enable_trace = false;
    size_t instruction_quota = 1000;

    //! contains the current execution stack.
    //! each element is either a VM context or an
    //! external function call.
    //! must be a list<T> because we modify it, but don't want our
    //! element pointers to change
    std::list<std::unique_ptr<FunctionCall>> code_stack;

    //! runs a single step of execution
    ExecutionResult exec();
};

inline bool operator==(Enumerator, Enumerator)
{
    throw LoLa::Error::InvalidOperator;
}

inline bool operator!=(Enumerator, Enumerator)
{
    throw LoLa::Error::InvalidOperator;
}

std::ostream &operator<<(std::ostream &stream, Value const &value);
} // namespace LoLa::Runtime

#endif // RUNTIME_HPP
