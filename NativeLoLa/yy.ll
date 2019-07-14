%{
/* C++ string header, for string ops below */
#include <string>

/* Implementation of yyFlexScanner */
#include "scanner.hpp"
#undef  YY_DECL
#define YY_DECL int LoLa::LoLaScanner::yylex( LoLa::LoLaParser::semantic_type * const lval, LoLa::LoLaParser::location_type *loc )

/* typedef to make the returns for the tokens shorter */
using token = LoLa::LoLaParser::token;

/* define yyterminate as this instead of NULL */
#define yyterminate() return( token::END )

/* msvc2010 requires that we exclude this header file. */
#define YY_NO_UNISTD_H

/* update location on matching */
#define YY_USER_ACTION loc->step(); loc->columns(yyleng);

%}

%option debug
%option yyclass="LoLa::LoLaScanner"
%option noyywrap
%option c++

%%
%{          /** Code executed at the beginning of yylex **/
            yylval = lval;
%}

\/\/.*                      { /* eat me */ }
\/\*.*?\*\/                 { /* eat me */ }
[\r\t ]+                    { /* eat me */ }
\n                          { loc->lines(1); }

\{                          { return token::CURLY_O; }
\}                          { return token::CURLY_C; }
\(                          { return token::ROUND_O; }
\)                          { return token::ROUND_C; }
\[                          { return token::SQUARE_O; }
\]                          { return token::SQUARE_C; }

var                         { return token::VAR; }
for                         { return token::FOR; }
while                       { return token::WHILE; }
if                          { return token::IF; }
else                        { return token::ELSE; }
function                    { return token::FUNCTION; }
in                          { return token::IN; }

break                       { return token::BREAK; }
continue                    { return token::CONTINUE; }
return                      { return token::RETURN; }

\<\=                        { lval->emplace<Operator>(Operator::LessOrEqual); return token::LEQUAL; }
\>\=                        { lval->emplace<Operator>(Operator::GreaterOrEqual); return token::GEQUAL; }
\=\=                        { lval->emplace<Operator>(Operator::Equals); return token::EQUALS; }
\!\=                        { lval->emplace<Operator>(Operator::Differs); return token::DIFFERS; }
\<                          { lval->emplace<Operator>(Operator::Less); return token::LESS; }
\>                          { lval->emplace<Operator>(Operator::More); return token::MORE; }

\=                          { return token::IS; }

\.                          { return token::DOT; }
\,                          { return token::COMMA; }
\;                          { return token::TERMINATOR; }

\+                          { lval->emplace<Operator>(Operator::Plus); return token::PLUS; }
\-                          { lval->emplace<Operator>(Operator::Minus); return token::MINUS; }
\*                          { lval->emplace<Operator>(Operator::Multiply); return token::MULT; }
\%                          { lval->emplace<Operator>(Operator::Modulus); return token::MOD; }
\/                          { lval->emplace<Operator>(Operator::Divide); return token::DIV; }

and                         { lval->emplace<Operator>(Operator::And); return token::AND; }
or                          { lval->emplace<Operator>(Operator::Or); return token::OR; }
not                         { lval->emplace<Operator>(Operator::Not); return token::INVERT; }

[0-9]+(\.[0-9]+)?           { lval->emplace<std::string>(yytext); return token::NUMBER; }

\"(?:\\\"|.)*?\"            { lval->emplace<std::string>(yytext); return token::STRING; }

[A-Za-z][A-Za-z0-9]*        { lval->emplace<std::string>(yytext); return token::IDENT; }

.                           { printf("damn. [[%s]] \n", yytext); }

%%

