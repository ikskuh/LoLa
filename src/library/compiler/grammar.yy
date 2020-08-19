%skeleton "lalr1.cc"
%require "3.2"
%debug
%defines
%define api.namespace {LoLa}
%define api.parser.class {LoLaParser}

%code requires{
#include "ast.hpp"
#include <vector>

using namespace LoLa::AST;
using std::move;

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
%token CURLY_O CURLY_C ROUND_O ROUND_C SQUARE_O SQUARE_C

// Keywords
%token VAR EXTERN FOR WHILE IF ELSE FUNCTION
%token BREAK CONTINUE RETURN IN

// Operators
%right <Operator> LEQUAL GEQUAL EQUALS DIFFERS LESS MORE
%left  IS DOT COMMA TERMINATOR PLUS_IS MINUS_IS MULT_IS DIV_IS MOD_IS
%left  <Operator> INVERT
%right <Operator> PLUS MINUS MULT DIV MOD AND OR
%token <std::string> IDENT

// Literals
%token <std::string> NUMBER STRING

%type <Program>     program
%type <Statement>   statement body decl ass for while conditional expression return
%type <Function>    function
%type <List<Statement>>  stmtlist
%type <Expression> expr_0 expr_02 expr_1 expr_2 expr_3 expr_4
%type <List<std::string>> plist
%type <Expression> rvalue call array
%type <LValueExpression> lvalue
%type <Operator> expr_0_op expr_02_op expr_1_op expr_2_op expr_3_op
%type <List<Expression>> arglist


%%
compile_unit : program { driver.program = move($1); }

program     : { } /* empty */
            | program function {
                $$ = move($1);
                $$.functions.emplace_back(move($2));
            }
            | program statement {
                $$ = move($1);
                $$.statements.emplace_back(move($2));
            }
            ;

function    : FUNCTION IDENT ROUND_O plist ROUND_C body {
                $$.name = $2;
                $$.params = $4;
                $$.body = move($6);
            }
            | FUNCTION IDENT ROUND_O ROUND_C body {
                $$.name = $2;
                $$.body = move($5);
            }
            ;

plist       : IDENT
            {
                $$.emplace_back(move($1));
            }
            | plist COMMA IDENT
            {
                $$ = move($1);
                $$.emplace_back(move($3));
            }
            ;

body		: CURLY_O stmtlist CURLY_C  { $$ = SubScope(move($2)); }
            ;

stmtlist    : { } /* empty */
            | stmtlist statement {
                $$ = move($1);
                $$.emplace_back(move($2));
            }
            ;

statement   : decl                { $$ = move($1); }
            | ass                 { $$ = move($1); }
            | for                 { $$ = move($1); }
            | while               { $$ = move($1); }
            | conditional         { $$ = move($1); }
            | expression          { $$ = move($1); }
            | return              { $$ = move($1); }
            | body                { $$ = move($1); }
            | BREAK TERMINATOR    { $$ = BreakStatement(); }
            | CONTINUE TERMINATOR { $$ = ContinueStatement(); }
            ;

decl        : VAR IDENT IS expr_0 TERMINATOR			{ $$ = Declaration(move($2), move($4)); }
            | VAR IDENT TERMINATOR						{ $$ = Declaration(move($2)); }
            | EXTERN IDENT TERMINATOR					{ $$ = ExternDeclaration(move($2)); }
            ;

ass         : lvalue IS expr_0 TERMINATOR                { $$ = Assignment(move($1), move($3)); }
            | lvalue PLUS_IS  expr_0 TERMINATOR          { auto dup = $1->clone(); $$ = Assignment(move($1), BinaryOperator(Operator::Plus, move(dup), move($3))); }
            | lvalue MINUS_IS expr_0 TERMINATOR          { auto dup = $1->clone(); $$ = Assignment(move($1), BinaryOperator(Operator::Minus, move(dup), move($3))); }
            | lvalue MULT_IS  expr_0 TERMINATOR          { auto dup = $1->clone(); $$ = Assignment(move($1), BinaryOperator(Operator::Multiply, move(dup), move($3))); }
            | lvalue DIV_IS   expr_0 TERMINATOR          { auto dup = $1->clone(); $$ = Assignment(move($1), BinaryOperator(Operator::Divide, move(dup), move($3))); }
            | lvalue MOD_IS   expr_0 TERMINATOR          { auto dup = $1->clone(); $$ = Assignment(move($1), BinaryOperator(Operator::Modulus, move(dup), move($3))); }
            ;

for			: FOR ROUND_O IDENT IN expr_0 ROUND_C body  { $$ = ForLoop($3,move($5),move($7)); }
            ;

while		: WHILE ROUND_O expr_0 ROUND_C body         { $$ = WhileLoop(move($3), move($5)); }
            ;

return		: RETURN expr_0 TERMINATOR					{ $$ = Return(move($2)); }
            | RETURN TERMINATOR							{ $$ = Return(); }
            ;

conditional : IF ROUND_O expr_0 ROUND_C statement ELSE statement  { $$ = IfElse(move($3), move($5), move($7)); }
            | IF ROUND_O expr_0 ROUND_C statement			{ $$ = IfElse(move($3), move($5)); }
            ;

expression	: call TERMINATOR							{ $$ = DiscardResult(move($1)); }
            ;

expr_0_op	: AND | OR;
expr_0		: expr_0 expr_0_op expr_02                  { $$ = BinaryOperator($2, move($1), move($3)); }
            | expr_02                                   { $$ = move($1); }
            ;

expr_02_op	: EQUALS|DIFFERS|LEQUAL|GEQUAL|MORE|LESS;
expr_02		: expr_02 expr_02_op expr_1                 { $$ = BinaryOperator($2, move($1), move($3)); }
            | expr_1                                    { $$ = move($1); }
            ;


expr_1_op	: PLUS | MINUS ;
expr_1		: expr_1 expr_1_op expr_2					{ $$ = BinaryOperator($2, move($1), move($3)); }
            | expr_2									{ $$ = move($1); }
            ;


expr_2_op	: MULT | DIV | MOD;
expr_2		: expr_2 expr_2_op expr_3					{ $$ = BinaryOperator($2, move($1), move($3)); }
            | expr_3									{ $$ = move($1); }
            ;


expr_3_op	: MINUS | INVERT;
expr_3		: expr_3_op expr_3							{ $$ = UnaryOperator($1, move($2)); }
            | expr_4									{ $$ = move($1); }
            ;


expr_4		: ROUND_O expr_0 ROUND_C					{ $$ = move($2); }
            | rvalue									{ $$ = move($1); }
            | lvalue									{ $$ = move($1); }
            ;

rvalue		: call										{ $$ = move($1); }
            | array										{ $$ = move($1); }
            | STRING									{ $$ = StringLiteral($1); }
            | NUMBER									{ $$ = NumberLiteral($1); }
            ;

call		: expr_4 DOT IDENT ROUND_O ROUND_C			{ $$ = MethodCall(move($1), $3, {}); }
            | expr_4 DOT IDENT ROUND_O arglist ROUND_C	{ $$ = MethodCall(move($1), $3, move($5)); }
            | IDENT ROUND_O ROUND_C						{ $$ = FunctionCall($1, {}); }
            | IDENT ROUND_O arglist ROUND_C				{ $$ = FunctionCall($1, move($3)); }
            ;

array		: SQUARE_O SQUARE_C							{ $$ = ArrayLiteral({}); }
            | SQUARE_O arglist SQUARE_C					{ $$ = ArrayLiteral(move($2)); }
            ;

arglist     : arglist COMMA expr_0 {
                $$ = move($1);
                $$.emplace_back(move($3));
            }
            | expr_0 {
                $$.emplace_back(move($1));
            }
            ;

lvalue      : expr_4 SQUARE_O expr_0 SQUARE_C           { $$ = ArrayIndexer(move($1), move($3)); }
            | IDENT                                     { $$ = VariableRef($1); }
            ;


%%


void
LoLa::LoLaParser::error( const location_type &l, const std::string &err_message )
{
   std::cerr << "Error: " << err_message << " at " << l << "\n";
}
