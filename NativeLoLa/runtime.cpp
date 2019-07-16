#include "runtime.hpp"
#include <cstring>
#include <cassert>
#include <cmath>
#include <iostream>
#include <iomanip>

using LoLa::Runtime::ExecutionResult;

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
    assert(code_stack.empty());
    auto & node = code_stack.emplace_back();
    node = ExecutionContext { };

    auto & ctx = std::get<ExecutionContext>(node);
    ctx.code = env.code;
    ctx.offset = entryPoint;
    ctx.locals.resize(env.code->global_count); // top-level node contains the indexable global variables
}

bool LoLa::Runtime::VirtualMachine::returnToCaller(LoLa::Runtime::Value const & result)
{
    code_stack.pop_back();
    if(not code_stack.empty()) {
        std::get<ExecutionContext>(code_stack.back()).data_stack.push_back(result);
        return true;
    } else {
        return false;
    }
}

LoLa::Runtime::ExecutionResult LoLa::Runtime::VirtualMachine::exec()
{
    if(code_stack.empty())
        return ExecutionResult::Done;

    auto & state = code_stack.back();
    if(std::holds_alternative<ExecutionContext>(state))
    {
        auto & ctx = std::get<ExecutionContext>(state);

        if(enable_trace)
        {
            std::cerr << "exec " << std::setw(6) << std::hex << std::setfill('0') << ctx.offset;
            for(auto const & val : ctx.data_stack)
                std::cerr << "\t" << val;
            std::cerr << std::endl;
        }

        if(ctx.exec(*this))
            return ExecutionResult::Exhausted;
        else
            return ExecutionResult::Done;
    }
    else if(std::holds_alternative<std::unique_ptr<FunctionCall>>(state))
    {
        auto & fn = std::get<std::unique_ptr<FunctionCall>>(state);
        if(auto result = fn->execute(); result)
        {
            if(returnToCaller(*result)) {
                return ExecutionResult::Exhausted;
            } else {
                return ExecutionResult::Done;
            }
        }
        return ExecutionResult::Exhausted;
    }
    else
    {
        assert(false and "this should not happen!");
    }
}

bool LoLa::Runtime::VirtualMachine::ExecutionContext::exec(VirtualMachine & vm)
{
    auto & ctx = *this;
    auto & env = (this->override_env != nullptr) ? (*this->override_env) : (*vm.env);
    auto const i = ctx.fetch_instruction();
    switch(i)
    {
    case IL::Instruction::nop:
        return true;

    case IL::Instruction::push_num:
        ctx.push(ctx.fetch_number());
        return true;

    case IL::Instruction::push_str:
        ctx.push(ctx.fetch_string());
        return true;

    case IL::Instruction::store_local:
    {
         auto const index = ctx.fetch_u16();
         if(index >= ctx.locals.size())
             throw Error::InvalidVariable;
         ctx.locals.at(index) = ctx.pop();
         return true;
    }

    case IL::Instruction::load_local:
    {
         auto const index = ctx.fetch_u16();
         if(index >= ctx.locals.size())
             throw Error::InvalidVariable;
         ctx.push(ctx.locals.at(index));
         return true;
    }

    case IL::Instruction::reserve_locals:
    {
        auto const index = ctx.fetch_u16();
        if(index > ctx.locals.size())
            ctx.locals.reserve(index);
        return true;
    }

    case IL::Instruction::ret:
        return vm.returnToCaller(Void { });

    case IL::Instruction::retval:
        return vm.returnToCaller(ctx.pop());

    case IL::Instruction::pop:
        ctx.pop();
        return true;

    case IL::Instruction::jmp:               // [ target:u32 ]
    {
        auto const target = ctx.fetch_u32();
        if(target >= ctx.code->code.size())
            throw Error::InvalidPointer;
        ctx.offset = target;
        return true;
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
        return true;
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
        return true;
    }

#define BINARY_OPERATOR(_Convert, _Operator) \
        { \
            auto const rhs = ctx.pop(); \
            auto const lhs = ctx.pop(); \
            ctx.push(_Convert(lhs) _Operator _Convert(rhs)); \
            return true; \
        }

#define UNARY_OPERATOR(_Convert, _Operator) \
        { \
            auto const value = ctx.pop(); \
            ctx.push(_Operator _Convert(value)); \
            return true; \
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
        return true;
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
        return true;
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
        else if(auto it = ctx.code->functions.find(name); it != ctx.code->functions.end())
        {
            // TODO: Implement native calls
            auto & new_ctx = std::get<ExecutionContext>(vm.code_stack.emplace_back(ExecutionContext{}));
            new_ctx.code = ctx.code;
            new_ctx.offset = it->second.entry_point;
            new_ctx.locals.resize(it->second.local_count);
            assert(argc <= it->second.local_count);
            for(size_t i = 0; i < argc; i++)
            {
                new_ctx.locals[i] = ctx.pop();
            }
        }
        else
        {
            std::cerr << "function " << name << " not found!" << std::endl;
            throw Error::UnsupportedFunction;
        }
        return true;
    }

    case IL::Instruction::store_global_idx:       // [ idx:u16 ]
    {
        auto const index = ctx.fetch_u16();
        if(index >= env.script_globals.size())
            throw Error::InvalidVariable;
        env.script_globals.at(index) = ctx.pop();
        return true;
    }

    case IL::Instruction::load_global_idx:        // [ idx:u16 ]
    {
        auto const index = ctx.fetch_u16();
        if(index >= env.script_globals.size())
            throw Error::InvalidVariable;
        ctx.push(env.script_globals.at(index));
        return true;
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

ExecutionResult LoLa::Runtime::VirtualMachine::exec(size_t instructions)
{
    for(; instructions > 0; --instructions)
    {
        switch(exec())
        {
        case ExecutionResult::Done: return ExecutionResult::Done;
        case ExecutionResult::Paused: return ExecutionResult::Paused;
        case ExecutionResult::Exhausted: continue;
        }
        assert(false and "ExecutionResult case not handled!");
    }
    return ExecutionResult::Exhausted;
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

LoLa::Runtime::Environment::Environment(const LoLa::Compiler::CompilationUnit *code) :
    code(code),
    functions(),
    script_globals(code->global_count),
    known_globals()
{

}
