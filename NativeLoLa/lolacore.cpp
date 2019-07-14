#include "lolacore.hpp"

#include "driver.hpp"

#include <sstream>

#define STR(x) #x
#define SSTR(x) STR(x)

bool LoLa::verify(std::string_view code)
{
    std::stringstream str;
    str.write(code.data(), code.size());
    str.seekg(0);

    LoLa::LoLaDriver driver;

    driver.parse(str);

    for(auto const & fn : driver.program.functions)
        std::cout << "fun " << fn.name << std::endl;

    return true;
}
