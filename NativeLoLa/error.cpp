#include "error.hpp"

const char *LoLa::to_string(LoLa::Error err)
{
    switch(err)
    {
    case Error::InvalidPointer:      return "invalid pointer";
    case Error::InvalidInstruction:  return "invalid instruction";
    case Error::InvalidLocal:        return "invalid local";
    case Error::StackEmpty:          return "stack empty";
    case Error::TypeMismatch:        return "type mismatch";
    case Error::InvalidOperator:     return "invalid operator";
    case Error::UnsupportedFunction: return "unsupported function";
    }
    return "<unknown error>";
}
