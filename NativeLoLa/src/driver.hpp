#ifndef __MCDRIVER_HPP__
#define __MCDRIVER_HPP__ 1

#include "scanner.hpp"
#include "grammar.tab.h"
#include "ast.hpp"

#include <string>
#include <cstddef>
#include <istream>
#include <memory>

namespace LoLa
{
class LoLaDriver{
public:
   LoLaDriver() = default;

   virtual ~LoLaDriver();

   /**
    * parse - parse from a file
    * @param filename - valid string with input file
    */
   void parse( const char * const filename );

   /**
    * parse - parse from a c++ input stream
    * @param is - std::istream&, valid input stream
    */
   bool parse( std::istream &iss );

   LoLa::AST::Program program;
private:

   bool parse_helper( std::istream &stream );

   std::unique_ptr<LoLa::LoLaParser>  parser;
   std::unique_ptr<LoLa::LoLaScanner> scanner;
};

} /* end namespace MC */
#endif /* END __MCDRIVER_HPP__ */
