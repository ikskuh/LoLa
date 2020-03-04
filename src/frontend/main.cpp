#include "../compiler/ast.hpp"
#include "../compiler/compiler.hpp"
#include "../compiler/runtime.hpp"

#include <getopt.h>
#include <iostream>
#include <sstream>
#include <cstring>
#include <fstream>

using namespace LoLa;

static int compile(int argc, char **argv);
static int disasm(int argc, char **argv);

static int compile(int argc, char **argv)
{
    char *outfile = nullptr;

    int opt;
    while ((opt = getopt(argc, argv, "o:")) != -1)
    {
        switch (opt)
        {
        case 'o':
            outfile = optarg;
            break;

        default:
            fprintf(stderr, "Unknown argument: '%c'\n", opt);
            return 1;
        }
    }

    argc = argc - optind;
    if (argc == 0)
    {
        fprintf(stderr, "Missing source argument!\n");
        return 1;
    }

    char const *infile = argv[optind];
    if (outfile == nullptr)
    {
        outfile = (char *)malloc(strlen(infile) + 10);
        strcpy(outfile, infile);
        auto len = strlen(outfile);
        size_t i = len;
        while (i > 0)
        {
            i -= 1;
            if (outfile[i] == '.')
                break;
            if (outfile[i] == '/')
            {
                i = 0;
                break;
            }
        }
        if (i != 0)
        {
            outfile[i] = 0;
        }
        strcat(outfile, ".lm");
    }

    //    fprintf(stderr, "in:  %s\n", infile);
    //    fprintf(stderr, "out: %s\n", outfile);

    FILE *f = fopen(infile, "r");
    if (f == nullptr)
    {
        fprintf(stderr, "File %s not found!\n", infile);
        return 1;
    }

    fseek(f, 0, SEEK_END);
    size_t len = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *fileBuffer = (char *)malloc(len + 1);
    size_t off = 0;
    while (off < len)
    {
        ssize_t l = fread(fileBuffer + off, 1, len - off, f);
        if (l < 0)
        {
            perror("IO error");
            fclose(f);
            return 1;
        }
        off += l;
    }
    fileBuffer[len] = 0;

    fclose(f);

    auto program = AST::parse(fileBuffer);
    if (not program)
    {
        fprintf(stderr, "Syntax error!\n");
        return 1;
    }

    Compiler::Compiler compiler;

    std::shared_ptr<LoLa::Compiler::CompilationUnit> compile_unit;
    try
    {
        compile_unit = compiler.compile(*program);
        if (not compile_unit)
        {
            fprintf(stderr, "Semantic error!\n");
            return 1;
        }
    }
    catch (LoLa::Error err)
    {
        fprintf(stderr, "Semantic error: %s!\n", LoLa::to_string(err));
        return 1;
    }

    {
        std::ofstream out(outfile);
        compile_unit->save(out);
    }

    return 0;
}

static int disasm(int argc, char **argv)
{
    fprintf(stderr, "not implemented yet!\n");
    return 1;
    //    int opt;
    //    while((opt = getopt(argc, argv, "o:")) != -1)
    //    {
    //        switch(opt)
    //        {
    //        default:
    //        }
    //    }

    //    auto compile_unit = compiler.compile(*program);

    //    Compiler::Disassembler disasm;
    //    disasm.disassemble(*compile_unit, std::cout);
}
