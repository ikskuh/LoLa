#include "error.hpp"

const char *LoLa::to_string(LoLa::Error err)
{
    switch (err)
    {
    case Error::InvalidPointer:
        return "invalid pointer";
    case Error::InvalidInstruction:
        return "invalid instruction";
    case Error::StackEmpty:
        return "stack empty";
    case Error::TypeMismatch:
        return "type mismatch";
    case Error::UnsupportedFunction:
        return "unsupported function";
    case Error::InvalidTopLevelReturn:
        return "invalid top level return";
    case Error::ObjectDisposed:
        return "object disposed";
    case Error::LabelAlreadyDefined:
        return "label was already defined.";
    }
    return "<unknown error>";
}
