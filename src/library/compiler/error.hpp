#ifndef ERROR_HPP
#define ERROR_HPP

namespace LoLa
{
enum class Error
{
    InvalidPointer,
    InvalidInstruction,
    InvalidVariable,
    StackEmpty,
    TypeMismatch,
    InvalidOperator,
    UnsupportedFunction,
    InvalidTopLevelReturn,
    ObjectDisposed,
    ReadOnlyVariable,
    InvalidStore,
    VariableNotFound,
    NotInLoop,
    InvalidString
};

char const *to_string(Error err);
} // namespace LoLa

#endif // ERROR_HPP
