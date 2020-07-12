#ifndef ERROR_HPP
#define ERROR_HPP

namespace LoLa
{
    enum class Error
    {
        InvalidPointer,
        InvalidInstruction,
        StackEmpty,
        TypeMismatch,
        UnsupportedFunction,
        InvalidTopLevelReturn,
        ObjectDisposed,
        LabelAlreadyDefined,
    };

    char const *to_string(Error err);
} // namespace LoLa

#endif // ERROR_HPP
