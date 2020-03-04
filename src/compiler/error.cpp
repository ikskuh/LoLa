#include "error.hpp"

const char *LoLa::to_string(LoLa::Error err)
{
    switch(err)
    {
    case Error::InvalidPointer:        return "invalid pointer";
    case Error::InvalidInstruction:    return "invalid instruction";
    case Error::InvalidVariable:       return "invalid variable";
    case Error::StackEmpty:            return "stack empty";
    case Error::TypeMismatch:          return "type mismatch";
    case Error::InvalidOperator:       return "invalid operator";
    case Error::UnsupportedFunction:   return "unsupported function";
    case Error::InvalidTopLevelReturn: return "invalid top level return";
    case Error::ObjectDisposed:        return "object disposed";
    case Error::ReadOnlyVariable:      return "read only variable";
    case Error::InvalidStore:          return "invalid store";
    case Error::VariableNotFound:      return "variable not found";
    case Error::NotInLoop:             return "break/continue outside of loop";
    }
    return "<unknown error>";
}
