%skeleton "lalr1.cc"
%require  "3.0"
%debug
%defines
%define api.namespace {LoLa}
%define parser_class_name {LoLaParser}

%code requires{
#include "ast.hpp"
#include <vector>

using namespace LoLa::AST;

namespace LoLa {
  class LoLaDriver;
  class LoLaScanner;
}

// The following definitions is missing when %locations isn't used
# ifndef YY_NULLPTR
#  if defined __cplusplus && 201103L <= __cplusplus
#   define YY_NULLPTR nullptr
#  else
#   define YY_NULLPTR 0
#  endif
# endif

}

%parse-param { LoLaScanner  &scanner  }
%parse-param { LoLaDriver  &driver  }

%code{
#include <iostream>
#include <cstdlib>
#include <fstream>

/* include for all driver functions */
#include "driver.hpp"

#undef yylex
#define yylex scanner.grammarlex
}

%define api.value.type variant
%define parse.assert

%locations

%token END 0

// Brackets
%token CURLY_O, CURLY_C, ROUND_O, ROUND_C, SQUARE_O, SQUARE_C

// Keywords
%token VAR, FOR, WHILE, IF, ELSE, FUNCTION
%token BREAK, CONTINUE, RETURN, IN

// Operators
%left  <Operator> LEQUAL, GEQUAL, EQUALS, DIFFERS, LESS, MORE
%left  IS, DOT, COMMA, TERMINATOR
%left  <Operator> PLUS, MINUS, MULT, DIV, MOD, AND, OR, INVERT
%token <std::string> IDENT

// Literals
%token <std::string> NUMBER, STRING

%type <Program>     program
%type <Statement>   statement body decl ass for while conditional expression return
%type <Function>    function
%type <List<Statement>>  stmtlist
%type <Expression> expr_0 expr_1 expr_2 expr_3 expr_4
%type <List<std::string>> plist
%type <Expression> rvalue call array
%type <Expression> lvalue
%type <Operator> expr_0_op expr_1_op expr_2_op expr_3_op
%type <List<Expression>> arglist

%%
compile_unit : program { driver.program = std::move($1); }

program     : /* empty */
            | program function {
                $$ = std::move($1);
                $$.functions.emplace_back(std::move($2));
            }
            | program statement {
                $$ = std::move($1);
                $$.statements.emplace_back(std::move($2));
            }
            ;

function    : FUNCTION IDENT ROUND_O plist ROUND_C body {
                $$.name = $2;
                $$.params = $4;
                $$.body = std::move($6);
            }
            | FUNCTION IDENT ROUND_O ROUND_C body {
                $$.name = $2;
                $$.body = std::move($5);
            }
            ;

plist       : IDENT
            {
                $$.emplace_back(std::move($1));
            }
            | plist COMMA IDENT
            {
                $$ = std::move($1);
                $$.emplace_back(std::move($3));
            }
            ;

body		: CURLY_O stmtlist CURLY_C  { $$ = SubScope(std::move($2)); }
            ;

stmtlist    : /* empty */
            | stmtlist statement {
                $$ = std::move($1);
                $$.emplace_back(std::move($2));
            }
            ;

statement   : decl          { $$ = std::move($1); }
            | ass           { $$ = std::move($1); }
            | for           { $$ = std::move($1); }
            | while         { $$ = std::move($1); }
            | conditional   { $$ = std::move($1); }
            | expression    { $$ = std::move($1); }
            | return        { $$ = std::move($1); }
            ;

decl		: VAR IDENT IS expr_0 TERMINATOR			{ $$ = Declaration(std::move($2), std::move($4)); }
            | VAR IDENT TERMINATOR						{ $$ = Declaration(std::move($2)); }
            ;

ass			: lvalue IS expr_0 TERMINATOR				{ $$ = Assignment(std::move($1), std::move($3)); }
            ;

for			: FOR ROUND_O IDENT IN expr_0 ROUND_C body	{ $$ = ForLoop($3,std::move($5),std::move($7)); }
            ;

while		: WHILE ROUND_O expr_0 ROUND_C body			{ $$ = WhileLoop(std::move($3), std::move($5)); }
            ;

return		: RETURN expr_0 TERMINATOR					{ $$ = Return(std::move($2)); }
            | RETURN TERMINATOR							{ $$ = Return(); }
            ;

conditional : IF ROUND_O expr_0 ROUND_C body ELSE body  { $$ = IfElse(std::move($3), std::move($5), std::move($7)); }
            | IF ROUND_O expr_0 ROUND_C body			{ $$ = IfElse(std::move($3), std::move($5)); }
            ;

expression	: call TERMINATOR							{ $$ = DiscardResult(std::move($1)); }
            ;

expr_0_op	: EQUALS|DIFFERS|LEQUAL|GEQUAL|MORE|LESS;
expr_0		: expr_0 expr_0_op expr_0					{ $$ = BinaryOperator($2, std::move($1), std::move($3)); }
            | expr_1									{ $$ = std::move($1); }
            ;


expr_1_op	: PLUS | MINUS ;
expr_1		: expr_1 expr_1_op expr_1					{ $$ = BinaryOperator($2, std::move($1), std::move($3)); }
            | expr_2									{ $$ = std::move($1); }
            ;


expr_2_op	: MULT | DIV | MOD | AND | OR;
expr_2		: expr_2 expr_2_op expr_2					{ $$ = BinaryOperator($2, std::move($1), std::move($3)); }
            | expr_3									{ $$ = std::move($1); }
            ;


expr_3_op	: MINUS | INVERT;
expr_3		: expr_3_op expr_3							{ $$ = UnaryOperator($1, std::move($2)); }
            | expr_4									{ $$ = std::move($1); }
            ;


expr_4		: ROUND_O expr_0 ROUND_C					{ $$ = std::move($2); }
            | rvalue									{ $$ = std::move($1); }
            | lvalue									{ $$ = std::move($1); }
            ;

rvalue		: call										{ $$ = std::move($1); }
            | array										{ $$ = std::move($1); }
            | STRING									{ $$ = StringLiteral($1); }
            | NUMBER									{ $$ = NumberLiteral($1); }
            ;

call		: IDENT DOT IDENT ROUND_O ROUND_C			{ $$ = MethodCall(VariableRef($1), $3, {}); }
            | IDENT DOT IDENT ROUND_O arglist ROUND_C	{ $$ = MethodCall(VariableRef($1), $3, std::move($5)); }
            | IDENT ROUND_O ROUND_C						{ $$ = FunctionCall($1, {}); }
            | IDENT ROUND_O arglist ROUND_C				{ $$ = FunctionCall($1, std::move($3)); }
            ;

array		: SQUARE_O SQUARE_C							{ $$ = ArrayLiteral({}); }
            | SQUARE_O arglist SQUARE_C					{ $$ = ArrayLiteral(std::move($2)); }
            ;

arglist     : arglist COMMA expr_0 {
                $$ = std::move($1);
                $$.emplace_back(std::move($3));
            }
            | expr_0 {
                $$.emplace_back(std::move($1));
            }
            ;

lvalue      : IDENT SQUARE_O expr_0 SQUARE_C            { $$ = ArrayIndexer(VariableRef($1), std::move($3)); }
            | IDENT                                     { $$ = VariableRef($1); }
            ;


%%


void
LoLa::LoLaParser::error( const location_type &l, const std::string &err_message )
{
   std::cerr << "Error: " << err_message << " at " << l << "\n";
}
