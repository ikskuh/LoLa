#ifndef COMMON_RUNTIME_HPP
#define COMMON_RUNTIME_HPP

#include <variant>
#include <vector>
#include <string>
#include <optional>
#include <memory>

namespace LoLa::Runtime
{
    struct ObjectState;

    struct Void {
        bool operator ==(Void) const { return true; }
        bool operator !=(Void) const { return false; }
    };
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

        [[nodiscard]] Value & value() {
            return array->at(index);
        }

        [[nodiscard]]  Value const & value() const {
            return array->at(index);
        }

        bool next() {
            index += 1;
            return good();
        }

        [[nodiscard]] bool good() const {
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

    struct VirtualMachine;

    struct FunctionCall
    {
        virtual ~FunctionCall();

        //! called every exec() cycle by the virtual machine.
        virtual std::optional<Value> execute(VirtualMachine & vm) = 0;

        //! called by the virtual machine when a function call
        //! returns to this call (so: returns a value)
        virtual void resumeFromCall(VirtualMachine & vm, Value const & result);
    };

    struct Function
    {
        virtual ~Function();
        virtual std::unique_ptr<FunctionCall> call(Value const * args, size_t argc) const = 0;
    };
}

#endif // COMMON_RUNTIME_HPP
