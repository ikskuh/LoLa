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
    };

    char const * to_string(Error err);
}

#endif // ERROR_HPP
