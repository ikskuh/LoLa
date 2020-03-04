#include <cctype>
#include <fstream>
#include <cassert>
#include <sstream>

#include "driver.hpp"

// LoLa::LoLaDriver::~LoLaDriver()
// {

// }

void LoLa::LoLaDriver::parse(const char *const filename)
{
    assert(filename != nullptr);
    std::ifstream in_file(filename);
    if (!in_file.good())
    {
        exit(EXIT_FAILURE);
    }
    parse_helper(in_file);
    return;
}

bool LoLa::LoLaDriver::parse(std::istream &stream)
{
    if (!stream.good() && stream.eof())
    {
        return false;
    }
    //else
    return parse_helper(stream);
}

bool LoLa::LoLaDriver::parse_helper(std::istream &stream)
{
    scanner = std::make_unique<LoLa::LoLaScanner>(&stream);
    parser = std::make_unique<LoLa::LoLaParser>(*scanner, *this);

    //    while(true)
    //    {
    //        LoLaParser::location_type loc;
    //        int tok = scanner->yylex(new LoLaParser::semantic_type, &loc);
    //        if(tok == 0)
    //            return;
    //        printf("[%d] = '%s'\n", tok, scanner->YYText());
    //        fflush(stdout);
    //    }

    try
    {
        const int accept(0);
        if (parser->parse() != accept)
        {
            std::cerr << "Parse failed!!\n";
            return false;
        }
    }
    catch (std::string const &msg)
    {
        std::cerr << msg << std::endl;
        return false;
    }
    return true;
}
