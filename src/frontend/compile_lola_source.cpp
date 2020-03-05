#include "../compiler/ast.hpp"
#include "../compiler/compiler.hpp"

#include <getopt.h>
#include <iostream>
#include <sstream>
#include <cstring>
#include <fstream>
#include <sstream>

using namespace LoLa;

struct ModuleBuffer
{
    uint8_t *data;
    size_t length;
};

extern "C" bool compile_lola_source(uint8_t const *source, size_t sourceLength, ModuleBuffer *outbuffer)
{
    *outbuffer = ModuleBuffer{nullptr, 0};

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
        return false;
    }

    if (not program)
    {
        // fprintf(stderr, "Syntax error!\n");
        return false;
    }

    Compiler::Compiler compiler;

    std::shared_ptr<LoLa::Compiler::CompilationUnit> compile_unit;
    try
    {
        compile_unit = compiler.compile(*program);
        if (not compile_unit)
        {
            fprintf(stderr, "Failed to compile source!\n");
            return false;
        }
    }
    catch (LoLa::Error err)
    {
        fprintf(stderr, "Semantic error: %s!\n", LoLa::to_string(err));
        return false;
    }

    // std::ofstream out(std::string(reinterpret_cast<char const *>(outFileName), outFileNameLen));
    std::stringstream out;
    compile_unit->save(out);

    auto const output = out.str();

    *outbuffer = ModuleBuffer{
        reinterpret_cast<uint8_t *>(malloc(output.size())),
        output.size(),
    };
    if (outbuffer->data == nullptr)
        return false;

    memcpy(outbuffer->data, output.data(), output.size());

    return true;
}
