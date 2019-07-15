#ifndef ERROR_HPP
#define ERROR_HPP

namespace LoLa
{
    enum class Error
    {
        InvalidPointer,
        InvalidInstruction,
        InvalidLocal,
        StackEmpty,
        TypeMismatch,
        InvalidOperator,
        UnsupportedFunction
    };

    char const * to_string(Error err);
}

#endif // ERROR_HPP
