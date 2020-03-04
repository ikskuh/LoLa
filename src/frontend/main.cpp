#include "../compiler/ast.hpp"
#include "../compiler/compiler.hpp"
#include "../compiler/runtime.hpp"

#include <getopt.h>
#include <iostream>
#include <sstream>
#include <cstring>
#include <fstream>

using namespace LoLa;

extern "C" uint8_t compile_lola_source(uint8_t const *source, size_t sourceLength, uint8_t const *outFileName, size_t outFileNameLen)
{
    std::optional<LoLa::AST::Program> program;
    try
    {
        program = AST::parse(std::string_view{
            reinterpret_cast<char const *>(source),
            sourceLength,
        });
    }
    catch (LoLa::Error err)
    {
        fprintf(stderr, "Syntax error: %s!\n", LoLa::to_string(err));
        return 1;
    }

    if (not program)
    {
        // fprintf(stderr, "Syntax error!\n");
        return 1;
    }

    Compiler::Compiler compiler;

    std::shared_ptr<LoLa::Compiler::CompilationUnit> compile_unit;
    try
    {
        compile_unit = compiler.compile(*program);
        if (not compile_unit)
        {
            fprintf(stderr, "Failed to compile source!\n");
            return 1;
        }
    }
    catch (LoLa::Error err)
    {
        fprintf(stderr, "Semantic error: %s!\n", LoLa::to_string(err));
        return 1;
    }

    std::ofstream out(std::string(reinterpret_cast<char const *>(outFileName), outFileNameLen));
    compile_unit->save(out);

    return 0;
}
