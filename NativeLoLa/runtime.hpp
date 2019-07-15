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

namespace LoLa::Runtime
{
    struct ObjectState;

    using Void = std::monostate;
    using Number = double;
    using String = std::string;
    using Boolean = bool;
    using Object = std::shared_ptr<ObjectState>;
    struct Array;
    struct Enumerator;

    using Value = std::variant<Void, Number, String, Boolean, Object, Array, Enumerator>;

    struct Array : std::vector<Value> { };

    Array operator +(Array const & lhs, Array const & rhs);

    struct Enumerator
    {
        Array * array;
        size_t index;

        explicit Enumerator(Array & a) : array(&a), index(0) { }

        Value & value() {
            return array->at(index);
        }

        Value const & value() const {
            return array->at(index);
        }

        bool next() {
            index += 1;
            return good();
        }

        bool good() const {
            return index < array->size();
        }
    };

    enum class TypeID
    {
        Void = 0,
        Number = 1,
        String = 2,
        Boolean = 3,
        Object = 4,
        Array = 5,
        Enumerator = 6,
    };

    TypeID typeOf(Value const & value);

    static_assert(std::is_same_v<std::variant_alternative_t<size_t(TypeID::Void),       Value>, Void>);
    static_assert(std::is_same_v<std::variant_alternative_t<size_t(TypeID::Number),     Value>, Number>);
    static_assert(std::is_same_v<std::variant_alternative_t<size_t(TypeID::String),     Value>, String>);
    static_assert(std::is_same_v<std::variant_alternative_t<size_t(TypeID::Boolean),    Value>, Boolean>);
    static_assert(std::is_same_v<std::variant_alternative_t<size_t(TypeID::Object),     Value>, Object>);
    static_assert(std::is_same_v<std::variant_alternative_t<size_t(TypeID::Array),      Value>, Array>);
    static_assert(std::is_same_v<std::variant_alternative_t<size_t(TypeID::Enumerator), Value>, Enumerator>);

    Number  to_number(Value const & v);
    String  to_string(Value const & v);
    Boolean to_boolean(Value const & v);
    Object  to_object(Value const & v);
    Array   to_array(Value const & v);

    struct FunctionCall
    {
        virtual ~FunctionCall();

        virtual std::optional<Value> execute() = 0;
    };

    struct Function
    {
        virtual ~Function();
        virtual std::unique_ptr<FunctionCall> call(Value const * args, size_t argc) const = 0;
    };

    enum ExecutionResult
    {
        Exhausted = 0,  //!< Code is still running, but we ran out of quota
        Done = 1,       //!< Code has stopped running and is done
        Paused = 2,     //!< Code has yielded manually and returned control to caller
    };

    struct VirtualMachine
    {
        struct ExecutionContext : Compiler::CodeReader
        {
            std::vector<Value> data_stack;
            std::vector<Value> locals;

            Value pop();
            void push(Value const & v);

            bool exec(VirtualMachine & vm);
        };

        bool enable_trace = false;

        // contains pointers to all available "native" functions
        std::map<std::string, Function const *> functions;

        //! contains the current execution stack.
        //! each element is either a VM context or an
        //! external function call.
        //! must be a list<T> because we modify it, but don't want our
        //! element pointers to change
        std::list<std::variant<ExecutionContext, std::unique_ptr<FunctionCall>>> code_stack;

        void start(Compiler::CompilationUnit const * cu, size_t offset);

        //! returns *true* if a caller exists, otherwise *false*.
        bool returnToCaller(Value const & val);

        //! runs a single step of execution
        ExecutionResult exec();

        //! runs exec() for `instructions` count.
        ExecutionResult exec(size_t instructions);
    };





    inline bool operator== (Enumerator,Enumerator) {
        throw LoLa::Error::InvalidOperator;
    }

    inline bool operator!= (Enumerator,Enumerator) {
        throw LoLa::Error::InvalidOperator;
    }

    std::ostream & operator<<(std::ostream & stream, Value const & value);
}

#endif // RUNTIME_HPP
