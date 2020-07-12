#ifndef COMMON_RUNTIME_HPP
#define COMMON_RUNTIME_HPP

#include <variant>
#include <vector>
#include <string>
#include <optional>
#include <memory>

namespace LoLa::Runtime
{

enum class TypeID
{
    Void = 0,
    Number = 1,
    String = 2,
    Object = 3,
    Boolean = 4,
    Array = 5,
    Enumerator = 6,
};

} // namespace LoLa::Runtime

#endif // COMMON_RUNTIME_HPP
