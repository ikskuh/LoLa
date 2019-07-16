#include "runtime.hpp"
#include <cstring>
#include <cassert>
#include <cmath>
#include <iostream>
#include <iomanip>

using LoLa::Runtime::ExecutionResult;
using LoLa::Runtime::FunctionCall;
using LoLa::Runtime::Value;
using LoLa::Runtime::Function;
using LoLa::Runtime::VirtualMachine;
using LoLa::Compiler::CompilationUnit;

struct ScriptFunction : LoLa::Runtime::Function
{
};

struct NumberHack {
    double value;
    NumberHack(double d) : value(d) { }
    operator double() const { return value; }
};

static double operator%(NumberHack lhs, double rhs)
{
    return std::fmod(lhs, rhs);
}

static NumberHack to_numberhack(LoLa::Runtime::Value const & value) {
    return to_number(value);
}

LoLa::Runtime::VirtualMachine::VirtualMachine(LoLa::Runtime::Environment &env, size_t entryPoint) :
    env(&env)
{
    auto ctx = std::make_unique<ExecutionContext>();
    ctx->code = env.code.get();
    ctx->offset = entryPoint;
    ctx->locals.resize(env.code->global_count); // top-level node contains the indexable global variables
    code_stack.emplace_back(std::move(ctx));
}

LoLa::Runtime::ExecutionResult LoLa::Runtime::VirtualMachine::exec()
{
    if(code_stack.empty())
        return ExecutionResult::Done;

    auto & fn = code_stack.back();
    if(auto result = fn->execute(*this); result)
    {
        this->code_stack.pop_back();
        if(this->code_stack.empty())
        {
            if(typeOf(*result) != TypeID::Void) {
                throw Error::InvalidTopLevelReturn;
            }
            return ExecutionResult::Done;
        }
        else
        {
            this->code_stack.back()->resumeFromCall(*this, *result);
        }
    }
    return ExecutionResult::Exhausted;
}

std::variant<std::monostate, LoLa::Runtime::Value, LoLa::Runtime::VirtualMachine::ExecutionContext::ManualYield> LoLa::Runtime::VirtualMachine::ExecutionContext::exec(VirtualMachine & vm)
{
    auto constexpr continue_execution = std::monostate { };
    auto constexpr yield_execution = ManualYield { };

    auto & ctx = *this;
    auto & env = (this->override_env != nullptr) ? (*this->override_env) : (*vm.env);
    if(vm.enable_trace)
        std::cerr << "[TRACE] " << std::hex << std::setw(6) << std::setfill('0') << ctx.offset << std::endl;

    auto const i = ctx.fetch_instruction();
    switch(i)
    {
    case IL::Instruction::nop:
        return continue_execution;

    case IL::Instruction::push_num:
        ctx.push(ctx.fetch_number());
        return continue_execution;

    case IL::Instruction::push_str:
        ctx.push(ctx.fetch_string());
        return continue_execution;

    case IL::Instruction::store_local:
    {
         auto const index = ctx.fetch_u16();
         if(index >= ctx.locals.size())
             throw Error::InvalidVariable;
         ctx.locals.at(index) = ctx.pop();
         return continue_execution;
    }

    case IL::Instruction::load_local:
    {
         auto const index = ctx.fetch_u16();
         if(index >= ctx.locals.size())
             throw Error::InvalidVariable;
         ctx.push(ctx.locals.at(index));
         return continue_execution;
    }

    case IL::Instruction::reserve_locals:
    {
        auto const index = ctx.fetch_u16();
        if(index > ctx.locals.size())
            ctx.locals.reserve(index);
        return continue_execution;
    }

    case IL::Instruction::ret:
        return Void { };

    case IL::Instruction::retval:
        return ctx.pop();

    case IL::Instruction::pop:
        ctx.pop();
        return continue_execution;

    case IL::Instruction::jmp:               // [ target:u32 ]
    {
        auto const target = ctx.fetch_u32();
        if(target >= ctx.code->code.size())
            throw Error::InvalidPointer;
        ctx.offset = target;
        return continue_execution;
    }
    case IL::Instruction::jnf:               // [ target:u32 ]
    {
        auto const target = ctx.fetch_u32();
        auto const take_jump = to_boolean(ctx.pop());
        if(take_jump)
        {
            if(target >= ctx.code->code.size())
                throw Error::InvalidPointer;
            ctx.offset = target;
        }
        return continue_execution;
    }

    case IL::Instruction::jif:               // [ target:u32 ]
    {
        auto const target = ctx.fetch_u32();
        auto const take_jump = not to_boolean(ctx.pop());
        if(take_jump)
        {
            if(target >= ctx.code->code.size())
                throw Error::InvalidPointer;
            ctx.offset = target;
        }
        return continue_execution;
    }

#define BINARY_OPERATOR(_Convert, _Operator) \
        { \
            auto const rhs = ctx.pop(); \
            auto const lhs = ctx.pop(); \
            ctx.push(_Convert(lhs) _Operator _Convert(rhs)); \
            return continue_execution; \
        }

#define UNARY_OPERATOR(_Convert, _Operator) \
        { \
            auto const value = ctx.pop(); \
            ctx.push(_Operator _Convert(value)); \
            return continue_execution; \
        } \

    case IL::Instruction::add:
    {
        auto const rhs = ctx.pop();
        auto const lhs = ctx.pop();
        switch(typeOf(lhs))
        {
        case TypeID::Number:
            ctx.push(to_number(lhs) + to_number(rhs));
            break;

        case TypeID::String:
            ctx.push(to_string(lhs) + to_string(rhs));
            break;

        case TypeID::Array:
            ctx.push(to_array(lhs) + to_array(rhs));
            break;

        case TypeID::Void:
        case TypeID::Object:
        case TypeID::Boolean:
        case TypeID::Enumerator:
            throw Error::InvalidOperator;
        }
        return continue_execution;
    }

    case IL::Instruction::sub:      BINARY_OPERATOR(to_number, -)
    case IL::Instruction::mul:      BINARY_OPERATOR(to_number, *)
    case IL::Instruction::div:      BINARY_OPERATOR(to_number, /)
    case IL::Instruction::mod:      BINARY_OPERATOR(to_numberhack, %)

    case IL::Instruction::bool_and: BINARY_OPERATOR(to_boolean, and)
    case IL::Instruction::bool_or:  BINARY_OPERATOR(to_boolean, or)

    case IL::Instruction::eq: BINARY_OPERATOR(, ==)
    case IL::Instruction::neq: BINARY_OPERATOR(, !=)
    case IL::Instruction::less_eq: BINARY_OPERATOR(to_number, <=)
    case IL::Instruction::greater_eq: BINARY_OPERATOR(to_number, >=)
    case IL::Instruction::less: BINARY_OPERATOR(to_number, <)
    case IL::Instruction::greater: BINARY_OPERATOR(to_number, >)

    case IL::Instruction::bool_not: UNARY_OPERATOR(to_boolean, not)
    case IL::Instruction::negate: UNARY_OPERATOR(to_number, -)

    case IL::Instruction::array_pack:         // [ num:u16 ]
    {
        auto const cnt = ctx.fetch_u16();
        Array array;
        array.resize(cnt);
        for(size_t i = 0; i < cnt; i++)
        {
            array[i] = ctx.pop();
        }
        ctx.push(array);
        return continue_execution;
    }

    case IL::Instruction::call_fn:            // [ fun:str ] [argc:u8 ]
    {
        auto const name = ctx.fetch_string();
        auto const argc = ctx.fetch_u8();
        if(auto it = env.functions.find(name); it != env.functions.end())
        {
            std::vector<Value> argv;
            argv.resize(argc);
            for(size_t i = 0; i < argc; i++)
                argv[i] = ctx.pop();

            auto fn = it->second->call(argv.data(), argv.size());
            vm.code_stack.emplace_back(std::move(fn));
        }
        else
        {
            std::cerr << "function " << name << " not found!" << std::endl;
            throw Error::UnsupportedFunction;
        }
        return yield_execution;
    }

    case IL::Instruction::store_global_idx:       // [ idx:u16 ]
    {
        auto const index = ctx.fetch_u16();
        if(index >= env.script_globals.size())
            throw Error::InvalidVariable;
        env.script_globals.at(index) = ctx.pop();
        return continue_execution;
    }

    case IL::Instruction::load_global_idx:        // [ idx:u16 ]
    {
        auto const index = ctx.fetch_u16();
        if(index >= env.script_globals.size())
            throw Error::InvalidVariable;
        ctx.push(env.script_globals.at(index));
        return continue_execution;
    }

    case IL::Instruction::store_global_name:       // [ var:str ]
    case IL::Instruction::load_global_name:        // [ var:str ]
    case IL::Instruction::call_obj:          // [ fun:str ] [argc:u8 ]
    case IL::Instruction::iter_make:
    case IL::Instruction::iter_next:
    case IL::Instruction::array_store:
    case IL::Instruction::array_load:
        assert(false and "not implemented yet");
    }
    throw Error::InvalidInstruction;
}

std::optional<LoLa::Runtime::Value> LoLa::Runtime::VirtualMachine::ExecutionContext::execute(LoLa::Runtime::VirtualMachine &vm)
{
    size_t quota = vm.instruction_quota;
    for(; quota > 0; --quota)
    {
        auto val = exec(vm);
        if(std::holds_alternative<ManualYield>(val))
            return std::nullopt;
        else if(std::holds_alternative<Value>(val))
            return std::get<Value>(val);
    }
    return std::nullopt;
}

void LoLa::Runtime::VirtualMachine::ExecutionContext::resumeFromCall(LoLa::Runtime::VirtualMachine &, const LoLa::Runtime::Value &result)
{
    push(result);
}

LoLa::Runtime::Value LoLa::Runtime::VirtualMachine::ExecutionContext::pop()
{
    if(data_stack.empty())
        throw Error::StackEmpty;
    Value v = std::move(data_stack.back());
    data_stack.pop_back();
    return v;
}

void LoLa::Runtime::VirtualMachine::ExecutionContext::push(const LoLa::Runtime::Value &v)
{
    data_stack.emplace_back(v);
}



LoLa::Runtime::Number  LoLa::Runtime::to_number(Value const & v)
{
   if(std::holds_alternative<Number>(v))
       return std::get<Number>(v);
   else
       throw Error::TypeMismatch;
}

LoLa::Runtime::String  LoLa::Runtime::to_string(Value const & v)
{
   if(std::holds_alternative<String>(v))
       return std::get<String>(v);
   else
       throw Error::TypeMismatch;
}

LoLa::Runtime::Boolean LoLa::Runtime::to_boolean(Value const & v)
{
   if(std::holds_alternative<Boolean>(v))
       return std::get<Boolean>(v);
   else
       throw Error::TypeMismatch;
}

LoLa::Runtime::Object  LoLa::Runtime::to_object(Value const & v)
{
   if(std::holds_alternative<Object>(v))
       return std::get<Object>(v);
   else
       throw Error::TypeMismatch;
}

LoLa::Runtime::Array  LoLa::Runtime::to_array(Value const & v)
{
   if(std::holds_alternative<Array>(v))
       return std::get<Array>(v);
   else
       throw Error::TypeMismatch;
}

LoLa::Runtime::TypeID LoLa::Runtime::typeOf(const LoLa::Runtime::Value &value)
{
    if(value.index() == std::variant_npos)
        return TypeID::Void;
    return TypeID(value.index());
}

LoLa::Runtime::Array LoLa::Runtime::operator +(const LoLa::Runtime::Array &lhs, const LoLa::Runtime::Array &rhs)
{
    Array result;
    result.resize(lhs.size() + rhs.size());
    std::copy(
        rhs.begin(),
        rhs.end(),
        std::copy(
            lhs.begin(), lhs.end(),
            result.begin()
        )
    );
    return result;
}

std::ostream &LoLa::Runtime::operator<<(std::ostream &stream, const LoLa::Runtime::Value &value)
{
    switch(typeOf(value))
    {
    case TypeID::Void: stream << "void"; return stream;
    case TypeID::Object: stream << "object"; return stream;
    case TypeID::Enumerator: stream << "enumerator"; return stream;
    case TypeID::Number: stream << std::get<Number>(value); return stream;
    case TypeID::String: stream << std::get<String>(value); return stream;
    case TypeID::Boolean: stream << (std::get<Boolean>(value) ? "true" : "false"); return stream;
    case TypeID::Array: {
        auto const & array = std::get<Array>(value);
        stream << "[";
        for(auto const & val : array)
            stream << " " << val;
        stream << " ]";
        return stream;
    }
    }
    assert(false and "type cannot be cast into string!");
}

LoLa::Runtime::Function::~Function()
{

}

LoLa::Runtime::FunctionCall::~FunctionCall()
{

}

void LoLa::Runtime::FunctionCall::resumeFromCall(LoLa::Runtime::VirtualMachine &, LoLa::Runtime::Value const &)
{
    assert(false and "function type called subroutin, but did not implement resumeFromCall");
}

LoLa::Runtime::Environment::Environment(std::shared_ptr<const Compiler::CompilationUnit> code) :
    code(code),
    functions(),
    script_globals(code->global_count),
    known_globals()
{
    for(auto const & fn : code->functions)
        functions.emplace(fn.first, fn.second.get());
}
