#ifndef __MCSCANNER_HPP__
#define __MCSCANNER_HPP__ 1

#if !defined(yyFlexLexerOnce)
#include <FlexLexer.h>
#endif

#include "grammar.tab.hpp"
#include "location.hh"

namespace LoLa
{

class LoLaScanner : public yyFlexLexer
{
public:
   LoLaScanner(std::istream *in) : yyFlexLexer(in)
   {
   }
   virtual ~LoLaScanner()
   {
   }

   //get rid of override virtual function warning
   using FlexLexer::yylex;

   virtual int yylex(LoLa::LoLaParser::semantic_type *const lval,
                     LoLa::LoLaParser::location_type *location);
   // YY_DECL defined in mc_lexer.l
   // Method body created by flex in mc_lexer.yy.cc

private:
   /* yyval ptr */
   LoLa::LoLaParser::semantic_type *yylval = nullptr;
};

} // namespace LoLa

#endif /* END __MCSCANNER_HPP__ */
