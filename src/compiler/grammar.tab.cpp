// A Bison parser, made by GNU Bison 3.5.2.

// Skeleton implementation for Bison LALR(1) parsers in C++

// Copyright (C) 2002-2015, 2018-2020 Free Software Foundation, Inc.

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// As a special exception, you may create a larger work that contains
// part or all of the Bison parser skeleton and distribute that work
// under terms of your choice, so long as that work isn't itself a
// parser generator using the skeleton or a modified version thereof
// as a parser skeleton.  Alternatively, if you modify or redistribute
// the parser skeleton itself, you may (at your option) remove this
// special exception, which will cause the skeleton and the resulting
// Bison output files to be licensed under the GNU General Public
// License without this special exception.

// This special exception was added by the Free Software Foundation in
// version 2.2 of Bison.

// Undocumented macros, especially those whose name start with YY_,
// are private implementation details.  Do not rely on them.


// Take the name prefix into account.
#define yylex   grammarlex



#include "grammar.tab.hpp"


// Unqualified %code blocks.
#line 34 "grammar.yy"

#include <iostream>
#include <cstdlib>
#include <fstream>

/* include for all driver functions */
#include "driver.hpp"

#undef yylex
#define yylex scanner.grammarlex

#line 59 "grammar.tab.cpp"


#ifndef YY_
# if defined YYENABLE_NLS && YYENABLE_NLS
#  if ENABLE_NLS
#   include <libintl.h> // FIXME: INFRINGES ON USER NAME SPACE.
#   define YY_(msgid) dgettext ("bison-runtime", msgid)
#  endif
# endif
# ifndef YY_
#  define YY_(msgid) msgid
# endif
#endif

// Whether we are compiled with exception support.
#ifndef YY_EXCEPTIONS
# if defined __GNUC__ && !defined __EXCEPTIONS
#  define YY_EXCEPTIONS 0
# else
#  define YY_EXCEPTIONS 1
# endif
#endif

#define YYRHSLOC(Rhs, K) ((Rhs)[K].location)
/* YYLLOC_DEFAULT -- Set CURRENT to span from RHS[1] to RHS[N].
   If N is 0, then set CURRENT to the empty location which ends
   the previous symbol: RHS[0] (always defined).  */

# ifndef YYLLOC_DEFAULT
#  define YYLLOC_DEFAULT(Current, Rhs, N)                               \
    do                                                                  \
      if (N)                                                            \
        {                                                               \
          (Current).begin  = YYRHSLOC (Rhs, 1).begin;                   \
          (Current).end    = YYRHSLOC (Rhs, N).end;                     \
        }                                                               \
      else                                                              \
        {                                                               \
          (Current).begin = (Current).end = YYRHSLOC (Rhs, 0).end;      \
        }                                                               \
    while (false)
# endif


// Enable debugging if requested.
#if YYDEBUG

// A pseudo ostream that takes yydebug_ into account.
# define YYCDEBUG if (yydebug_) (*yycdebug_)

# define YY_SYMBOL_PRINT(Title, Symbol)         \
  do {                                          \
    if (yydebug_)                               \
    {                                           \
      *yycdebug_ << Title << ' ';               \
      yy_print_ (*yycdebug_, Symbol);           \
      *yycdebug_ << '\n';                       \
    }                                           \
  } while (false)

# define YY_REDUCE_PRINT(Rule)          \
  do {                                  \
    if (yydebug_)                       \
      yy_reduce_print_ (Rule);          \
  } while (false)

# define YY_STACK_PRINT()               \
  do {                                  \
    if (yydebug_)                       \
      yystack_print_ ();                \
  } while (false)

#else // !YYDEBUG

# define YYCDEBUG if (false) std::cerr
# define YY_SYMBOL_PRINT(Title, Symbol)  YYUSE (Symbol)
# define YY_REDUCE_PRINT(Rule)           static_cast<void> (0)
# define YY_STACK_PRINT()                static_cast<void> (0)

#endif // !YYDEBUG

#define yyerrok         (yyerrstatus_ = 0)
#define yyclearin       (yyla.clear ())

#define YYACCEPT        goto yyacceptlab
#define YYABORT         goto yyabortlab
#define YYERROR         goto yyerrorlab
#define YYRECOVERING()  (!!yyerrstatus_)

#line 5 "grammar.yy"
namespace LoLa {
#line 151 "grammar.tab.cpp"


  /// Build a parser object.
  LoLaParser::LoLaParser (LoLaScanner  &scanner_yyarg, LoLaDriver  &driver_yyarg)
#if YYDEBUG
    : yydebug_ (false),
      yycdebug_ (&std::cerr),
#else
    :
#endif
      scanner (scanner_yyarg),
      driver (driver_yyarg)
  {}

  LoLaParser::~LoLaParser ()
  {}

  LoLaParser::syntax_error::~syntax_error () YY_NOEXCEPT YY_NOTHROW
  {}

  /*---------------.
  | Symbol types.  |
  `---------------*/

  // basic_symbol.
#if 201103L <= YY_CPLUSPLUS
  template <typename Base>
  LoLaParser::basic_symbol<Base>::basic_symbol (basic_symbol&& that)
    : Base (std::move (that))
    , value ()
    , location (std::move (that.location))
  {
    switch (this->type_get ())
    {
      case 62: // expr_0
      case 64: // expr_02
      case 66: // expr_1
      case 68: // expr_2
      case 70: // expr_3
      case 71: // expr_4
      case 72: // rvalue
      case 73: // call
      case 74: // array
        value.move< Expression > (std::move (that.value));
        break;

      case 49: // function
        value.move< Function > (std::move (that.value));
        break;

      case 76: // lvalue
        value.move< LValueExpression > (std::move (that.value));
        break;

      case 75: // arglist
        value.move< List<Expression> > (std::move (that.value));
        break;

      case 52: // stmtlist
        value.move< List<Statement> > (std::move (that.value));
        break;

      case 50: // plist
        value.move< List<std::string> > (std::move (that.value));
        break;

      case 20: // LEQUAL
      case 21: // GEQUAL
      case 22: // EQUALS
      case 23: // DIFFERS
      case 24: // LESS
      case 25: // MORE
      case 35: // PLUS
      case 36: // MINUS
      case 37: // MULT
      case 38: // DIV
      case 39: // MOD
      case 40: // AND
      case 41: // OR
      case 42: // INVERT
      case 61: // expr_0_op
      case 63: // expr_02_op
      case 65: // expr_1_op
      case 67: // expr_2_op
      case 69: // expr_3_op
        value.move< Operator > (std::move (that.value));
        break;

      case 48: // program
        value.move< Program > (std::move (that.value));
        break;

      case 51: // body
      case 53: // statement
      case 54: // decl
      case 55: // ass
      case 56: // for
      case 57: // while
      case 58: // return
      case 59: // conditional
      case 60: // expression
        value.move< Statement > (std::move (that.value));
        break;

      case 43: // IDENT
      case 44: // NUMBER
      case 45: // STRING
        value.move< std::string > (std::move (that.value));
        break;

      default:
        break;
    }

  }
#endif

  template <typename Base>
  LoLaParser::basic_symbol<Base>::basic_symbol (const basic_symbol& that)
    : Base (that)
    , value ()
    , location (that.location)
  {
    switch (this->type_get ())
    {
      case 62: // expr_0
      case 64: // expr_02
      case 66: // expr_1
      case 68: // expr_2
      case 70: // expr_3
      case 71: // expr_4
      case 72: // rvalue
      case 73: // call
      case 74: // array
        value.copy< Expression > (YY_MOVE (that.value));
        break;

      case 49: // function
        value.copy< Function > (YY_MOVE (that.value));
        break;

      case 76: // lvalue
        value.copy< LValueExpression > (YY_MOVE (that.value));
        break;

      case 75: // arglist
        value.copy< List<Expression> > (YY_MOVE (that.value));
        break;

      case 52: // stmtlist
        value.copy< List<Statement> > (YY_MOVE (that.value));
        break;

      case 50: // plist
        value.copy< List<std::string> > (YY_MOVE (that.value));
        break;

      case 20: // LEQUAL
      case 21: // GEQUAL
      case 22: // EQUALS
      case 23: // DIFFERS
      case 24: // LESS
      case 25: // MORE
      case 35: // PLUS
      case 36: // MINUS
      case 37: // MULT
      case 38: // DIV
      case 39: // MOD
      case 40: // AND
      case 41: // OR
      case 42: // INVERT
      case 61: // expr_0_op
      case 63: // expr_02_op
      case 65: // expr_1_op
      case 67: // expr_2_op
      case 69: // expr_3_op
        value.copy< Operator > (YY_MOVE (that.value));
        break;

      case 48: // program
        value.copy< Program > (YY_MOVE (that.value));
        break;

      case 51: // body
      case 53: // statement
      case 54: // decl
      case 55: // ass
      case 56: // for
      case 57: // while
      case 58: // return
      case 59: // conditional
      case 60: // expression
        value.copy< Statement > (YY_MOVE (that.value));
        break;

      case 43: // IDENT
      case 44: // NUMBER
      case 45: // STRING
        value.copy< std::string > (YY_MOVE (that.value));
        break;

      default:
        break;
    }

  }



  template <typename Base>
  bool
  LoLaParser::basic_symbol<Base>::empty () const YY_NOEXCEPT
  {
    return Base::type_get () == empty_symbol;
  }

  template <typename Base>
  void
  LoLaParser::basic_symbol<Base>::move (basic_symbol& s)
  {
    super_type::move (s);
    switch (this->type_get ())
    {
      case 62: // expr_0
      case 64: // expr_02
      case 66: // expr_1
      case 68: // expr_2
      case 70: // expr_3
      case 71: // expr_4
      case 72: // rvalue
      case 73: // call
      case 74: // array
        value.move< Expression > (YY_MOVE (s.value));
        break;

      case 49: // function
        value.move< Function > (YY_MOVE (s.value));
        break;

      case 76: // lvalue
        value.move< LValueExpression > (YY_MOVE (s.value));
        break;

      case 75: // arglist
        value.move< List<Expression> > (YY_MOVE (s.value));
        break;

      case 52: // stmtlist
        value.move< List<Statement> > (YY_MOVE (s.value));
        break;

      case 50: // plist
        value.move< List<std::string> > (YY_MOVE (s.value));
        break;

      case 20: // LEQUAL
      case 21: // GEQUAL
      case 22: // EQUALS
      case 23: // DIFFERS
      case 24: // LESS
      case 25: // MORE
      case 35: // PLUS
      case 36: // MINUS
      case 37: // MULT
      case 38: // DIV
      case 39: // MOD
      case 40: // AND
      case 41: // OR
      case 42: // INVERT
      case 61: // expr_0_op
      case 63: // expr_02_op
      case 65: // expr_1_op
      case 67: // expr_2_op
      case 69: // expr_3_op
        value.move< Operator > (YY_MOVE (s.value));
        break;

      case 48: // program
        value.move< Program > (YY_MOVE (s.value));
        break;

      case 51: // body
      case 53: // statement
      case 54: // decl
      case 55: // ass
      case 56: // for
      case 57: // while
      case 58: // return
      case 59: // conditional
      case 60: // expression
        value.move< Statement > (YY_MOVE (s.value));
        break;

      case 43: // IDENT
      case 44: // NUMBER
      case 45: // STRING
        value.move< std::string > (YY_MOVE (s.value));
        break;

      default:
        break;
    }

    location = YY_MOVE (s.location);
  }

  // by_type.
  LoLaParser::by_type::by_type ()
    : type (empty_symbol)
  {}

#if 201103L <= YY_CPLUSPLUS
  LoLaParser::by_type::by_type (by_type&& that)
    : type (that.type)
  {
    that.clear ();
  }
#endif

  LoLaParser::by_type::by_type (const by_type& that)
    : type (that.type)
  {}

  LoLaParser::by_type::by_type (token_type t)
    : type (yytranslate_ (t))
  {}

  void
  LoLaParser::by_type::clear ()
  {
    type = empty_symbol;
  }

  void
  LoLaParser::by_type::move (by_type& that)
  {
    type = that.type;
    that.clear ();
  }

  int
  LoLaParser::by_type::type_get () const YY_NOEXCEPT
  {
    return type;
  }


  // by_state.
  LoLaParser::by_state::by_state () YY_NOEXCEPT
    : state (empty_state)
  {}

  LoLaParser::by_state::by_state (const by_state& that) YY_NOEXCEPT
    : state (that.state)
  {}

  void
  LoLaParser::by_state::clear () YY_NOEXCEPT
  {
    state = empty_state;
  }

  void
  LoLaParser::by_state::move (by_state& that)
  {
    state = that.state;
    that.clear ();
  }

  LoLaParser::by_state::by_state (state_type s) YY_NOEXCEPT
    : state (s)
  {}

  LoLaParser::symbol_number_type
  LoLaParser::by_state::type_get () const YY_NOEXCEPT
  {
    if (state == empty_state)
      return empty_symbol;
    else
      return yystos_[+state];
  }

  LoLaParser::stack_symbol_type::stack_symbol_type ()
  {}

  LoLaParser::stack_symbol_type::stack_symbol_type (YY_RVREF (stack_symbol_type) that)
    : super_type (YY_MOVE (that.state), YY_MOVE (that.location))
  {
    switch (that.type_get ())
    {
      case 62: // expr_0
      case 64: // expr_02
      case 66: // expr_1
      case 68: // expr_2
      case 70: // expr_3
      case 71: // expr_4
      case 72: // rvalue
      case 73: // call
      case 74: // array
        value.YY_MOVE_OR_COPY< Expression > (YY_MOVE (that.value));
        break;

      case 49: // function
        value.YY_MOVE_OR_COPY< Function > (YY_MOVE (that.value));
        break;

      case 76: // lvalue
        value.YY_MOVE_OR_COPY< LValueExpression > (YY_MOVE (that.value));
        break;

      case 75: // arglist
        value.YY_MOVE_OR_COPY< List<Expression> > (YY_MOVE (that.value));
        break;

      case 52: // stmtlist
        value.YY_MOVE_OR_COPY< List<Statement> > (YY_MOVE (that.value));
        break;

      case 50: // plist
        value.YY_MOVE_OR_COPY< List<std::string> > (YY_MOVE (that.value));
        break;

      case 20: // LEQUAL
      case 21: // GEQUAL
      case 22: // EQUALS
      case 23: // DIFFERS
      case 24: // LESS
      case 25: // MORE
      case 35: // PLUS
      case 36: // MINUS
      case 37: // MULT
      case 38: // DIV
      case 39: // MOD
      case 40: // AND
      case 41: // OR
      case 42: // INVERT
      case 61: // expr_0_op
      case 63: // expr_02_op
      case 65: // expr_1_op
      case 67: // expr_2_op
      case 69: // expr_3_op
        value.YY_MOVE_OR_COPY< Operator > (YY_MOVE (that.value));
        break;

      case 48: // program
        value.YY_MOVE_OR_COPY< Program > (YY_MOVE (that.value));
        break;

      case 51: // body
      case 53: // statement
      case 54: // decl
      case 55: // ass
      case 56: // for
      case 57: // while
      case 58: // return
      case 59: // conditional
      case 60: // expression
        value.YY_MOVE_OR_COPY< Statement > (YY_MOVE (that.value));
        break;

      case 43: // IDENT
      case 44: // NUMBER
      case 45: // STRING
        value.YY_MOVE_OR_COPY< std::string > (YY_MOVE (that.value));
        break;

      default:
        break;
    }

#if 201103L <= YY_CPLUSPLUS
    // that is emptied.
    that.state = empty_state;
#endif
  }

  LoLaParser::stack_symbol_type::stack_symbol_type (state_type s, YY_MOVE_REF (symbol_type) that)
    : super_type (s, YY_MOVE (that.location))
  {
    switch (that.type_get ())
    {
      case 62: // expr_0
      case 64: // expr_02
      case 66: // expr_1
      case 68: // expr_2
      case 70: // expr_3
      case 71: // expr_4
      case 72: // rvalue
      case 73: // call
      case 74: // array
        value.move< Expression > (YY_MOVE (that.value));
        break;

      case 49: // function
        value.move< Function > (YY_MOVE (that.value));
        break;

      case 76: // lvalue
        value.move< LValueExpression > (YY_MOVE (that.value));
        break;

      case 75: // arglist
        value.move< List<Expression> > (YY_MOVE (that.value));
        break;

      case 52: // stmtlist
        value.move< List<Statement> > (YY_MOVE (that.value));
        break;

      case 50: // plist
        value.move< List<std::string> > (YY_MOVE (that.value));
        break;

      case 20: // LEQUAL
      case 21: // GEQUAL
      case 22: // EQUALS
      case 23: // DIFFERS
      case 24: // LESS
      case 25: // MORE
      case 35: // PLUS
      case 36: // MINUS
      case 37: // MULT
      case 38: // DIV
      case 39: // MOD
      case 40: // AND
      case 41: // OR
      case 42: // INVERT
      case 61: // expr_0_op
      case 63: // expr_02_op
      case 65: // expr_1_op
      case 67: // expr_2_op
      case 69: // expr_3_op
        value.move< Operator > (YY_MOVE (that.value));
        break;

      case 48: // program
        value.move< Program > (YY_MOVE (that.value));
        break;

      case 51: // body
      case 53: // statement
      case 54: // decl
      case 55: // ass
      case 56: // for
      case 57: // while
      case 58: // return
      case 59: // conditional
      case 60: // expression
        value.move< Statement > (YY_MOVE (that.value));
        break;

      case 43: // IDENT
      case 44: // NUMBER
      case 45: // STRING
        value.move< std::string > (YY_MOVE (that.value));
        break;

      default:
        break;
    }

    // that is emptied.
    that.type = empty_symbol;
  }

#if YY_CPLUSPLUS < 201103L
  LoLaParser::stack_symbol_type&
  LoLaParser::stack_symbol_type::operator= (const stack_symbol_type& that)
  {
    state = that.state;
    switch (that.type_get ())
    {
      case 62: // expr_0
      case 64: // expr_02
      case 66: // expr_1
      case 68: // expr_2
      case 70: // expr_3
      case 71: // expr_4
      case 72: // rvalue
      case 73: // call
      case 74: // array
        value.copy< Expression > (that.value);
        break;

      case 49: // function
        value.copy< Function > (that.value);
        break;

      case 76: // lvalue
        value.copy< LValueExpression > (that.value);
        break;

      case 75: // arglist
        value.copy< List<Expression> > (that.value);
        break;

      case 52: // stmtlist
        value.copy< List<Statement> > (that.value);
        break;

      case 50: // plist
        value.copy< List<std::string> > (that.value);
        break;

      case 20: // LEQUAL
      case 21: // GEQUAL
      case 22: // EQUALS
      case 23: // DIFFERS
      case 24: // LESS
      case 25: // MORE
      case 35: // PLUS
      case 36: // MINUS
      case 37: // MULT
      case 38: // DIV
      case 39: // MOD
      case 40: // AND
      case 41: // OR
      case 42: // INVERT
      case 61: // expr_0_op
      case 63: // expr_02_op
      case 65: // expr_1_op
      case 67: // expr_2_op
      case 69: // expr_3_op
        value.copy< Operator > (that.value);
        break;

      case 48: // program
        value.copy< Program > (that.value);
        break;

      case 51: // body
      case 53: // statement
      case 54: // decl
      case 55: // ass
      case 56: // for
      case 57: // while
      case 58: // return
      case 59: // conditional
      case 60: // expression
        value.copy< Statement > (that.value);
        break;

      case 43: // IDENT
      case 44: // NUMBER
      case 45: // STRING
        value.copy< std::string > (that.value);
        break;

      default:
        break;
    }

    location = that.location;
    return *this;
  }

  LoLaParser::stack_symbol_type&
  LoLaParser::stack_symbol_type::operator= (stack_symbol_type& that)
  {
    state = that.state;
    switch (that.type_get ())
    {
      case 62: // expr_0
      case 64: // expr_02
      case 66: // expr_1
      case 68: // expr_2
      case 70: // expr_3
      case 71: // expr_4
      case 72: // rvalue
      case 73: // call
      case 74: // array
        value.move< Expression > (that.value);
        break;

      case 49: // function
        value.move< Function > (that.value);
        break;

      case 76: // lvalue
        value.move< LValueExpression > (that.value);
        break;

      case 75: // arglist
        value.move< List<Expression> > (that.value);
        break;

      case 52: // stmtlist
        value.move< List<Statement> > (that.value);
        break;

      case 50: // plist
        value.move< List<std::string> > (that.value);
        break;

      case 20: // LEQUAL
      case 21: // GEQUAL
      case 22: // EQUALS
      case 23: // DIFFERS
      case 24: // LESS
      case 25: // MORE
      case 35: // PLUS
      case 36: // MINUS
      case 37: // MULT
      case 38: // DIV
      case 39: // MOD
      case 40: // AND
      case 41: // OR
      case 42: // INVERT
      case 61: // expr_0_op
      case 63: // expr_02_op
      case 65: // expr_1_op
      case 67: // expr_2_op
      case 69: // expr_3_op
        value.move< Operator > (that.value);
        break;

      case 48: // program
        value.move< Program > (that.value);
        break;

      case 51: // body
      case 53: // statement
      case 54: // decl
      case 55: // ass
      case 56: // for
      case 57: // while
      case 58: // return
      case 59: // conditional
      case 60: // expression
        value.move< Statement > (that.value);
        break;

      case 43: // IDENT
      case 44: // NUMBER
      case 45: // STRING
        value.move< std::string > (that.value);
        break;

      default:
        break;
    }

    location = that.location;
    // that is emptied.
    that.state = empty_state;
    return *this;
  }
#endif

  template <typename Base>
  void
  LoLaParser::yy_destroy_ (const char* yymsg, basic_symbol<Base>& yysym) const
  {
    if (yymsg)
      YY_SYMBOL_PRINT (yymsg, yysym);
  }

#if YYDEBUG
  template <typename Base>
  void
  LoLaParser::yy_print_ (std::ostream& yyo,
                                     const basic_symbol<Base>& yysym) const
  {
    std::ostream& yyoutput = yyo;
    YYUSE (yyoutput);
    symbol_number_type yytype = yysym.type_get ();
#if defined __GNUC__ && ! defined __clang__ && ! defined __ICC && __GNUC__ * 100 + __GNUC_MINOR__ <= 408
    // Avoid a (spurious) G++ 4.8 warning about "array subscript is
    // below array bounds".
    if (yysym.empty ())
      std::abort ();
#endif
    yyo << (yytype < yyntokens_ ? "token" : "nterm")
        << ' ' << yytname_[yytype] << " ("
        << yysym.location << ": ";
    YYUSE (yytype);
    yyo << ')';
  }
#endif

  void
  LoLaParser::yypush_ (const char* m, YY_MOVE_REF (stack_symbol_type) sym)
  {
    if (m)
      YY_SYMBOL_PRINT (m, sym);
    yystack_.push (YY_MOVE (sym));
  }

  void
  LoLaParser::yypush_ (const char* m, state_type s, YY_MOVE_REF (symbol_type) sym)
  {
#if 201103L <= YY_CPLUSPLUS
    yypush_ (m, stack_symbol_type (s, std::move (sym)));
#else
    stack_symbol_type ss (s, sym);
    yypush_ (m, ss);
#endif
  }

  void
  LoLaParser::yypop_ (int n)
  {
    yystack_.pop (n);
  }

#if YYDEBUG
  std::ostream&
  LoLaParser::debug_stream () const
  {
    return *yycdebug_;
  }

  void
  LoLaParser::set_debug_stream (std::ostream& o)
  {
    yycdebug_ = &o;
  }


  LoLaParser::debug_level_type
  LoLaParser::debug_level () const
  {
    return yydebug_;
  }

  void
  LoLaParser::set_debug_level (debug_level_type l)
  {
    yydebug_ = l;
  }
#endif // YYDEBUG

  LoLaParser::state_type
  LoLaParser::yy_lr_goto_state_ (state_type yystate, int yysym)
  {
    int yyr = yypgoto_[yysym - yyntokens_] + yystate;
    if (0 <= yyr && yyr <= yylast_ && yycheck_[yyr] == yystate)
      return yytable_[yyr];
    else
      return yydefgoto_[yysym - yyntokens_];
  }

  bool
  LoLaParser::yy_pact_value_is_default_ (int yyvalue)
  {
    return yyvalue == yypact_ninf_;
  }

  bool
  LoLaParser::yy_table_value_is_error_ (int yyvalue)
  {
    return yyvalue == yytable_ninf_;
  }

  int
  LoLaParser::operator() ()
  {
    return parse ();
  }

  int
  LoLaParser::parse ()
  {
    int yyn;
    /// Length of the RHS of the rule being reduced.
    int yylen = 0;

    // Error handling.
    int yynerrs_ = 0;
    int yyerrstatus_ = 0;

    /// The lookahead symbol.
    symbol_type yyla;

    /// The locations where the error started and ended.
    stack_symbol_type yyerror_range[3];

    /// The return value of parse ().
    int yyresult;

#if YY_EXCEPTIONS
    try
#endif // YY_EXCEPTIONS
      {
    YYCDEBUG << "Starting parse\n";


    /* Initialize the stack.  The initial state will be set in
       yynewstate, since the latter expects the semantical and the
       location values to have been already stored, initialize these
       stacks with a primary value.  */
    yystack_.clear ();
    yypush_ (YY_NULLPTR, 0, YY_MOVE (yyla));

  /*-----------------------------------------------.
  | yynewstate -- push a new symbol on the stack.  |
  `-----------------------------------------------*/
  yynewstate:
    YYCDEBUG << "Entering state " << int (yystack_[0].state) << '\n';

    // Accept?
    if (yystack_[0].state == yyfinal_)
      YYACCEPT;

    goto yybackup;


  /*-----------.
  | yybackup.  |
  `-----------*/
  yybackup:
    // Try to take a decision without lookahead.
    yyn = yypact_[+yystack_[0].state];
    if (yy_pact_value_is_default_ (yyn))
      goto yydefault;

    // Read a lookahead token.
    if (yyla.empty ())
      {
        YYCDEBUG << "Reading a token: ";
#if YY_EXCEPTIONS
        try
#endif // YY_EXCEPTIONS
          {
            yyla.type = yytranslate_ (yylex (&yyla.value, &yyla.location));
          }
#if YY_EXCEPTIONS
        catch (const syntax_error& yyexc)
          {
            YYCDEBUG << "Caught exception: " << yyexc.what() << '\n';
            error (yyexc);
            goto yyerrlab1;
          }
#endif // YY_EXCEPTIONS
      }
    YY_SYMBOL_PRINT ("Next token is", yyla);

    /* If the proper action on seeing token YYLA.TYPE is to reduce or
       to detect an error, take that action.  */
    yyn += yyla.type_get ();
    if (yyn < 0 || yylast_ < yyn || yycheck_[yyn] != yyla.type_get ())
      {
        goto yydefault;
      }

    // Reduce or error.
    yyn = yytable_[yyn];
    if (yyn <= 0)
      {
        if (yy_table_value_is_error_ (yyn))
          goto yyerrlab;
        yyn = -yyn;
        goto yyreduce;
      }

    // Count tokens shifted since error; after three, turn off error status.
    if (yyerrstatus_)
      --yyerrstatus_;

    // Shift the lookahead token.
    yypush_ ("Shifting", state_type (yyn), YY_MOVE (yyla));
    goto yynewstate;


  /*-----------------------------------------------------------.
  | yydefault -- do the default action for the current state.  |
  `-----------------------------------------------------------*/
  yydefault:
    yyn = yydefact_[+yystack_[0].state];
    if (yyn == 0)
      goto yyerrlab;
    goto yyreduce;


  /*-----------------------------.
  | yyreduce -- do a reduction.  |
  `-----------------------------*/
  yyreduce:
    yylen = yyr2_[yyn];
    {
      stack_symbol_type yylhs;
      yylhs.state = yy_lr_goto_state_ (yystack_[yylen].state, yyr1_[yyn]);
      /* Variants are always initialized to an empty instance of the
         correct type. The default '$$ = $1' action is NOT applied
         when using variants.  */
      switch (yyr1_[yyn])
    {
      case 62: // expr_0
      case 64: // expr_02
      case 66: // expr_1
      case 68: // expr_2
      case 70: // expr_3
      case 71: // expr_4
      case 72: // rvalue
      case 73: // call
      case 74: // array
        yylhs.value.emplace< Expression > ();
        break;

      case 49: // function
        yylhs.value.emplace< Function > ();
        break;

      case 76: // lvalue
        yylhs.value.emplace< LValueExpression > ();
        break;

      case 75: // arglist
        yylhs.value.emplace< List<Expression> > ();
        break;

      case 52: // stmtlist
        yylhs.value.emplace< List<Statement> > ();
        break;

      case 50: // plist
        yylhs.value.emplace< List<std::string> > ();
        break;

      case 20: // LEQUAL
      case 21: // GEQUAL
      case 22: // EQUALS
      case 23: // DIFFERS
      case 24: // LESS
      case 25: // MORE
      case 35: // PLUS
      case 36: // MINUS
      case 37: // MULT
      case 38: // DIV
      case 39: // MOD
      case 40: // AND
      case 41: // OR
      case 42: // INVERT
      case 61: // expr_0_op
      case 63: // expr_02_op
      case 65: // expr_1_op
      case 67: // expr_2_op
      case 69: // expr_3_op
        yylhs.value.emplace< Operator > ();
        break;

      case 48: // program
        yylhs.value.emplace< Program > ();
        break;

      case 51: // body
      case 53: // statement
      case 54: // decl
      case 55: // ass
      case 56: // for
      case 57: // while
      case 58: // return
      case 59: // conditional
      case 60: // expression
        yylhs.value.emplace< Statement > ();
        break;

      case 43: // IDENT
      case 44: // NUMBER
      case 45: // STRING
        yylhs.value.emplace< std::string > ();
        break;

      default:
        break;
    }


      // Default location.
      {
        stack_type::slice range (yystack_, yylen);
        YYLLOC_DEFAULT (yylhs.location, range, yylen);
        yyerror_range[1].location = yylhs.location;
      }

      // Perform the reduction.
      YY_REDUCE_PRINT (yyn);
#if YY_EXCEPTIONS
      try
#endif // YY_EXCEPTIONS
        {
          switch (yyn)
            {
  case 2:
#line 82 "grammar.yy"
                       { driver.program = move(yystack_[0].value.as < Program > ()); }
#line 1238 "grammar.tab.cpp"
    break;

  case 3:
#line 84 "grammar.yy"
              { }
#line 1244 "grammar.tab.cpp"
    break;

  case 4:
#line 85 "grammar.yy"
                               {
                yylhs.value.as < Program > () = move(yystack_[1].value.as < Program > ());
                yylhs.value.as < Program > ().functions.emplace_back(move(yystack_[0].value.as < Function > ()));
            }
#line 1253 "grammar.tab.cpp"
    break;

  case 5:
#line 89 "grammar.yy"
                                {
                yylhs.value.as < Program > () = move(yystack_[1].value.as < Program > ());
                yylhs.value.as < Program > ().statements.emplace_back(move(yystack_[0].value.as < Statement > ()));
            }
#line 1262 "grammar.tab.cpp"
    break;

  case 6:
#line 95 "grammar.yy"
                                                        {
                yylhs.value.as < Function > ().name = yystack_[4].value.as < std::string > ();
                yylhs.value.as < Function > ().params = yystack_[2].value.as < List<std::string> > ();
                yylhs.value.as < Function > ().body = move(yystack_[0].value.as < Statement > ());
            }
#line 1272 "grammar.tab.cpp"
    break;

  case 7:
#line 100 "grammar.yy"
                                                  {
                yylhs.value.as < Function > ().name = yystack_[3].value.as < std::string > ();
                yylhs.value.as < Function > ().body = move(yystack_[0].value.as < Statement > ());
            }
#line 1281 "grammar.tab.cpp"
    break;

  case 8:
#line 107 "grammar.yy"
            {
                yylhs.value.as < List<std::string> > ().emplace_back(move(yystack_[0].value.as < std::string > ()));
            }
#line 1289 "grammar.tab.cpp"
    break;

  case 9:
#line 111 "grammar.yy"
            {
                yylhs.value.as < List<std::string> > () = move(yystack_[2].value.as < List<std::string> > ());
                yylhs.value.as < List<std::string> > ().emplace_back(move(yystack_[0].value.as < std::string > ()));
            }
#line 1298 "grammar.tab.cpp"
    break;

  case 10:
#line 117 "grammar.yy"
                                            { yylhs.value.as < Statement > () = SubScope(move(yystack_[1].value.as < List<Statement> > ())); }
#line 1304 "grammar.tab.cpp"
    break;

  case 11:
#line 120 "grammar.yy"
              { }
#line 1310 "grammar.tab.cpp"
    break;

  case 12:
#line 121 "grammar.yy"
                                 {
                yylhs.value.as < List<Statement> > () = move(yystack_[1].value.as < List<Statement> > ());
                yylhs.value.as < List<Statement> > ().emplace_back(move(yystack_[0].value.as < Statement > ()));
            }
#line 1319 "grammar.tab.cpp"
    break;

  case 13:
#line 127 "grammar.yy"
                                  { yylhs.value.as < Statement > () = move(yystack_[0].value.as < Statement > ()); }
#line 1325 "grammar.tab.cpp"
    break;

  case 14:
#line 128 "grammar.yy"
                                  { yylhs.value.as < Statement > () = move(yystack_[0].value.as < Statement > ()); }
#line 1331 "grammar.tab.cpp"
    break;

  case 15:
#line 129 "grammar.yy"
                                  { yylhs.value.as < Statement > () = move(yystack_[0].value.as < Statement > ()); }
#line 1337 "grammar.tab.cpp"
    break;

  case 16:
#line 130 "grammar.yy"
                                  { yylhs.value.as < Statement > () = move(yystack_[0].value.as < Statement > ()); }
#line 1343 "grammar.tab.cpp"
    break;

  case 17:
#line 131 "grammar.yy"
                                  { yylhs.value.as < Statement > () = move(yystack_[0].value.as < Statement > ()); }
#line 1349 "grammar.tab.cpp"
    break;

  case 18:
#line 132 "grammar.yy"
                                  { yylhs.value.as < Statement > () = move(yystack_[0].value.as < Statement > ()); }
#line 1355 "grammar.tab.cpp"
    break;

  case 19:
#line 133 "grammar.yy"
                                  { yylhs.value.as < Statement > () = move(yystack_[0].value.as < Statement > ()); }
#line 1361 "grammar.tab.cpp"
    break;

  case 20:
#line 134 "grammar.yy"
                                  { yylhs.value.as < Statement > () = move(yystack_[0].value.as < Statement > ()); }
#line 1367 "grammar.tab.cpp"
    break;

  case 21:
#line 135 "grammar.yy"
                                  { yylhs.value.as < Statement > () = BreakStatement(); }
#line 1373 "grammar.tab.cpp"
    break;

  case 22:
#line 136 "grammar.yy"
                                  { yylhs.value.as < Statement > () = ContinueStatement(); }
#line 1379 "grammar.tab.cpp"
    break;

  case 23:
#line 139 "grammar.yy"
                                                                { yylhs.value.as < Statement > () = Declaration(move(yystack_[3].value.as < std::string > ()), move(yystack_[1].value.as < Expression > ())); }
#line 1385 "grammar.tab.cpp"
    break;

  case 24:
#line 140 "grammar.yy"
                                                                                { yylhs.value.as < Statement > () = Declaration(move(yystack_[1].value.as < std::string > ())); }
#line 1391 "grammar.tab.cpp"
    break;

  case 25:
#line 141 "grammar.yy"
                                                                        { yylhs.value.as < Statement > () = ExternDeclaration(move(yystack_[1].value.as < std::string > ())); }
#line 1397 "grammar.tab.cpp"
    break;

  case 26:
#line 144 "grammar.yy"
                                                        { yylhs.value.as < Statement > () = Assignment(move(yystack_[3].value.as < LValueExpression > ()), move(yystack_[1].value.as < Expression > ())); }
#line 1403 "grammar.tab.cpp"
    break;

  case 27:
#line 145 "grammar.yy"
                                                         { auto dup = yystack_[3].value.as < LValueExpression > ()->clone(); yylhs.value.as < Statement > () = Assignment(move(yystack_[3].value.as < LValueExpression > ()), BinaryOperator(Operator::Plus, move(dup), move(yystack_[1].value.as < Expression > ()))); }
#line 1409 "grammar.tab.cpp"
    break;

  case 28:
#line 146 "grammar.yy"
                                                         { auto dup = yystack_[3].value.as < LValueExpression > ()->clone(); yylhs.value.as < Statement > () = Assignment(move(yystack_[3].value.as < LValueExpression > ()), BinaryOperator(Operator::Minus, move(dup), move(yystack_[1].value.as < Expression > ()))); }
#line 1415 "grammar.tab.cpp"
    break;

  case 29:
#line 147 "grammar.yy"
                                                         { auto dup = yystack_[3].value.as < LValueExpression > ()->clone(); yylhs.value.as < Statement > () = Assignment(move(yystack_[3].value.as < LValueExpression > ()), BinaryOperator(Operator::Multiply, move(dup), move(yystack_[1].value.as < Expression > ()))); }
#line 1421 "grammar.tab.cpp"
    break;

  case 30:
#line 148 "grammar.yy"
                                                         { auto dup = yystack_[3].value.as < LValueExpression > ()->clone(); yylhs.value.as < Statement > () = Assignment(move(yystack_[3].value.as < LValueExpression > ()), BinaryOperator(Operator::Divide, move(dup), move(yystack_[1].value.as < Expression > ()))); }
#line 1427 "grammar.tab.cpp"
    break;

  case 31:
#line 149 "grammar.yy"
                                                         { auto dup = yystack_[3].value.as < LValueExpression > ()->clone(); yylhs.value.as < Statement > () = Assignment(move(yystack_[3].value.as < LValueExpression > ()), BinaryOperator(Operator::Modulus, move(dup), move(yystack_[1].value.as < Expression > ()))); }
#line 1433 "grammar.tab.cpp"
    break;

  case 32:
#line 152 "grammar.yy"
                                                                    { yylhs.value.as < Statement > () = ForLoop(yystack_[4].value.as < std::string > (),move(yystack_[2].value.as < Expression > ()),move(yystack_[0].value.as < Statement > ())); }
#line 1439 "grammar.tab.cpp"
    break;

  case 33:
#line 155 "grammar.yy"
                                                            { yylhs.value.as < Statement > () = WhileLoop(move(yystack_[2].value.as < Expression > ()), move(yystack_[0].value.as < Statement > ())); }
#line 1445 "grammar.tab.cpp"
    break;

  case 34:
#line 158 "grammar.yy"
                                                                                { yylhs.value.as < Statement > () = Return(move(yystack_[1].value.as < Expression > ())); }
#line 1451 "grammar.tab.cpp"
    break;

  case 35:
#line 159 "grammar.yy"
                                                                                { yylhs.value.as < Statement > () = Return(); }
#line 1457 "grammar.tab.cpp"
    break;

  case 36:
#line 162 "grammar.yy"
                                                                  { yylhs.value.as < Statement > () = IfElse(move(yystack_[4].value.as < Expression > ()), move(yystack_[2].value.as < Statement > ()), move(yystack_[0].value.as < Statement > ())); }
#line 1463 "grammar.tab.cpp"
    break;

  case 37:
#line 163 "grammar.yy"
                                                                        { yylhs.value.as < Statement > () = IfElse(move(yystack_[2].value.as < Expression > ()), move(yystack_[0].value.as < Statement > ())); }
#line 1469 "grammar.tab.cpp"
    break;

  case 38:
#line 166 "grammar.yy"
                                                                                        { yylhs.value.as < Statement > () = DiscardResult(move(yystack_[1].value.as < Expression > ())); }
#line 1475 "grammar.tab.cpp"
    break;

  case 39:
#line 169 "grammar.yy"
                  { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1481 "grammar.tab.cpp"
    break;

  case 40:
#line 169 "grammar.yy"
                        { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1487 "grammar.tab.cpp"
    break;

  case 41:
#line 170 "grammar.yy"
                                                            { yylhs.value.as < Expression > () = BinaryOperator(yystack_[1].value.as < Operator > (), move(yystack_[2].value.as < Expression > ()), move(yystack_[0].value.as < Expression > ())); }
#line 1493 "grammar.tab.cpp"
    break;

  case 42:
#line 171 "grammar.yy"
                                                        { yylhs.value.as < Expression > () = move(yystack_[0].value.as < Expression > ()); }
#line 1499 "grammar.tab.cpp"
    break;

  case 43:
#line 174 "grammar.yy"
                  { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1505 "grammar.tab.cpp"
    break;

  case 44:
#line 174 "grammar.yy"
                         { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1511 "grammar.tab.cpp"
    break;

  case 45:
#line 174 "grammar.yy"
                                 { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1517 "grammar.tab.cpp"
    break;

  case 46:
#line 174 "grammar.yy"
                                        { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1523 "grammar.tab.cpp"
    break;

  case 47:
#line 174 "grammar.yy"
                                               { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1529 "grammar.tab.cpp"
    break;

  case 48:
#line 174 "grammar.yy"
                                                    { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1535 "grammar.tab.cpp"
    break;

  case 49:
#line 175 "grammar.yy"
                                                            { yylhs.value.as < Expression > () = BinaryOperator(yystack_[1].value.as < Operator > (), move(yystack_[2].value.as < Expression > ()), move(yystack_[0].value.as < Expression > ())); }
#line 1541 "grammar.tab.cpp"
    break;

  case 50:
#line 176 "grammar.yy"
                                                        { yylhs.value.as < Expression > () = move(yystack_[0].value.as < Expression > ()); }
#line 1547 "grammar.tab.cpp"
    break;

  case 51:
#line 180 "grammar.yy"
                  { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1553 "grammar.tab.cpp"
    break;

  case 52:
#line 180 "grammar.yy"
                         { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1559 "grammar.tab.cpp"
    break;

  case 53:
#line 181 "grammar.yy"
                                                                                { yylhs.value.as < Expression > () = BinaryOperator(yystack_[1].value.as < Operator > (), move(yystack_[2].value.as < Expression > ()), move(yystack_[0].value.as < Expression > ())); }
#line 1565 "grammar.tab.cpp"
    break;

  case 54:
#line 182 "grammar.yy"
                                                                                        { yylhs.value.as < Expression > () = move(yystack_[0].value.as < Expression > ()); }
#line 1571 "grammar.tab.cpp"
    break;

  case 55:
#line 186 "grammar.yy"
                  { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1577 "grammar.tab.cpp"
    break;

  case 56:
#line 186 "grammar.yy"
                         { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1583 "grammar.tab.cpp"
    break;

  case 57:
#line 186 "grammar.yy"
                               { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1589 "grammar.tab.cpp"
    break;

  case 58:
#line 187 "grammar.yy"
                                                                                { yylhs.value.as < Expression > () = BinaryOperator(yystack_[1].value.as < Operator > (), move(yystack_[2].value.as < Expression > ()), move(yystack_[0].value.as < Expression > ())); }
#line 1595 "grammar.tab.cpp"
    break;

  case 59:
#line 188 "grammar.yy"
                                                                                        { yylhs.value.as < Expression > () = move(yystack_[0].value.as < Expression > ()); }
#line 1601 "grammar.tab.cpp"
    break;

  case 60:
#line 192 "grammar.yy"
                  { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1607 "grammar.tab.cpp"
    break;

  case 61:
#line 192 "grammar.yy"
                          { yylhs.value.as < Operator > () = yystack_[0].value.as < Operator > (); }
#line 1613 "grammar.tab.cpp"
    break;

  case 62:
#line 193 "grammar.yy"
                                                                                        { yylhs.value.as < Expression > () = UnaryOperator(yystack_[1].value.as < Operator > (), move(yystack_[0].value.as < Expression > ())); }
#line 1619 "grammar.tab.cpp"
    break;

  case 63:
#line 194 "grammar.yy"
                                                                                        { yylhs.value.as < Expression > () = move(yystack_[0].value.as < Expression > ()); }
#line 1625 "grammar.tab.cpp"
    break;

  case 64:
#line 198 "grammar.yy"
                                                                                { yylhs.value.as < Expression > () = move(yystack_[1].value.as < Expression > ()); }
#line 1631 "grammar.tab.cpp"
    break;

  case 65:
#line 199 "grammar.yy"
                                                                                        { yylhs.value.as < Expression > () = move(yystack_[0].value.as < Expression > ()); }
#line 1637 "grammar.tab.cpp"
    break;

  case 66:
#line 200 "grammar.yy"
                                                                                        { yylhs.value.as < Expression > () = move(yystack_[0].value.as < LValueExpression > ()); }
#line 1643 "grammar.tab.cpp"
    break;

  case 67:
#line 203 "grammar.yy"
                                                                                                { yylhs.value.as < Expression > () = move(yystack_[0].value.as < Expression > ()); }
#line 1649 "grammar.tab.cpp"
    break;

  case 68:
#line 204 "grammar.yy"
                                                                                                { yylhs.value.as < Expression > () = move(yystack_[0].value.as < Expression > ()); }
#line 1655 "grammar.tab.cpp"
    break;

  case 69:
#line 205 "grammar.yy"
                                                                                        { yylhs.value.as < Expression > () = StringLiteral(yystack_[0].value.as < std::string > ()); }
#line 1661 "grammar.tab.cpp"
    break;

  case 70:
#line 206 "grammar.yy"
                                                                                        { yylhs.value.as < Expression > () = NumberLiteral(yystack_[0].value.as < std::string > ()); }
#line 1667 "grammar.tab.cpp"
    break;

  case 71:
#line 209 "grammar.yy"
                                                                        { yylhs.value.as < Expression > () = MethodCall(move(yystack_[4].value.as < Expression > ()), yystack_[2].value.as < std::string > (), {}); }
#line 1673 "grammar.tab.cpp"
    break;

  case 72:
#line 210 "grammar.yy"
                                                        { yylhs.value.as < Expression > () = MethodCall(move(yystack_[5].value.as < Expression > ()), yystack_[3].value.as < std::string > (), move(yystack_[1].value.as < List<Expression> > ())); }
#line 1679 "grammar.tab.cpp"
    break;

  case 73:
#line 211 "grammar.yy"
                                                                                { yylhs.value.as < Expression > () = FunctionCall(yystack_[2].value.as < std::string > (), {}); }
#line 1685 "grammar.tab.cpp"
    break;

  case 74:
#line 212 "grammar.yy"
                                                                        { yylhs.value.as < Expression > () = FunctionCall(yystack_[3].value.as < std::string > (), move(yystack_[1].value.as < List<Expression> > ())); }
#line 1691 "grammar.tab.cpp"
    break;

  case 75:
#line 215 "grammar.yy"
                                                                                        { yylhs.value.as < Expression > () = ArrayLiteral({}); }
#line 1697 "grammar.tab.cpp"
    break;

  case 76:
#line 216 "grammar.yy"
                                                                        { yylhs.value.as < Expression > () = ArrayLiteral(move(yystack_[1].value.as < List<Expression> > ())); }
#line 1703 "grammar.tab.cpp"
    break;

  case 77:
#line 219 "grammar.yy"
                                   {
                yylhs.value.as < List<Expression> > () = move(yystack_[2].value.as < List<Expression> > ());
                yylhs.value.as < List<Expression> > ().emplace_back(move(yystack_[0].value.as < Expression > ()));
            }
#line 1712 "grammar.tab.cpp"
    break;

  case 78:
#line 223 "grammar.yy"
                     {
                yylhs.value.as < List<Expression> > ().emplace_back(move(yystack_[0].value.as < Expression > ()));
            }
#line 1720 "grammar.tab.cpp"
    break;

  case 79:
#line 228 "grammar.yy"
                                                        { yylhs.value.as < LValueExpression > () = ArrayIndexer(move(yystack_[3].value.as < Expression > ()), move(yystack_[1].value.as < Expression > ())); }
#line 1726 "grammar.tab.cpp"
    break;

  case 80:
#line 229 "grammar.yy"
                                                        { yylhs.value.as < LValueExpression > () = VariableRef(yystack_[0].value.as < std::string > ()); }
#line 1732 "grammar.tab.cpp"
    break;


#line 1736 "grammar.tab.cpp"

            default:
              break;
            }
        }
#if YY_EXCEPTIONS
      catch (const syntax_error& yyexc)
        {
          YYCDEBUG << "Caught exception: " << yyexc.what() << '\n';
          error (yyexc);
          YYERROR;
        }
#endif // YY_EXCEPTIONS
      YY_SYMBOL_PRINT ("-> $$ =", yylhs);
      yypop_ (yylen);
      yylen = 0;
      YY_STACK_PRINT ();

      // Shift the result of the reduction.
      yypush_ (YY_NULLPTR, YY_MOVE (yylhs));
    }
    goto yynewstate;


  /*--------------------------------------.
  | yyerrlab -- here on detecting error.  |
  `--------------------------------------*/
  yyerrlab:
    // If not already recovering from an error, report this error.
    if (!yyerrstatus_)
      {
        ++yynerrs_;
        error (yyla.location, yysyntax_error_ (yystack_[0].state, yyla));
      }


    yyerror_range[1].location = yyla.location;
    if (yyerrstatus_ == 3)
      {
        /* If just tried and failed to reuse lookahead token after an
           error, discard it.  */

        // Return failure if at end of input.
        if (yyla.type_get () == yyeof_)
          YYABORT;
        else if (!yyla.empty ())
          {
            yy_destroy_ ("Error: discarding", yyla);
            yyla.clear ();
          }
      }

    // Else will try to reuse lookahead token after shifting the error token.
    goto yyerrlab1;


  /*---------------------------------------------------.
  | yyerrorlab -- error raised explicitly by YYERROR.  |
  `---------------------------------------------------*/
  yyerrorlab:
    /* Pacify compilers when the user code never invokes YYERROR and
       the label yyerrorlab therefore never appears in user code.  */
    if (false)
      YYERROR;

    /* Do not reclaim the symbols of the rule whose action triggered
       this YYERROR.  */
    yypop_ (yylen);
    yylen = 0;
    goto yyerrlab1;


  /*-------------------------------------------------------------.
  | yyerrlab1 -- common code for both syntax error and YYERROR.  |
  `-------------------------------------------------------------*/
  yyerrlab1:
    yyerrstatus_ = 3;   // Each real token shifted decrements this.
    {
      stack_symbol_type error_token;
      for (;;)
        {
          yyn = yypact_[+yystack_[0].state];
          if (!yy_pact_value_is_default_ (yyn))
            {
              yyn += yy_error_token_;
              if (0 <= yyn && yyn <= yylast_ && yycheck_[yyn] == yy_error_token_)
                {
                  yyn = yytable_[yyn];
                  if (0 < yyn)
                    break;
                }
            }

          // Pop the current state because it cannot handle the error token.
          if (yystack_.size () == 1)
            YYABORT;

          yyerror_range[1].location = yystack_[0].location;
          yy_destroy_ ("Error: popping", yystack_[0]);
          yypop_ ();
          YY_STACK_PRINT ();
        }

      yyerror_range[2].location = yyla.location;
      YYLLOC_DEFAULT (error_token.location, yyerror_range, 2);

      // Shift the error token.
      error_token.state = state_type (yyn);
      yypush_ ("Shifting", YY_MOVE (error_token));
    }
    goto yynewstate;


  /*-------------------------------------.
  | yyacceptlab -- YYACCEPT comes here.  |
  `-------------------------------------*/
  yyacceptlab:
    yyresult = 0;
    goto yyreturn;


  /*-----------------------------------.
  | yyabortlab -- YYABORT comes here.  |
  `-----------------------------------*/
  yyabortlab:
    yyresult = 1;
    goto yyreturn;


  /*-----------------------------------------------------.
  | yyreturn -- parsing is finished, return the result.  |
  `-----------------------------------------------------*/
  yyreturn:
    if (!yyla.empty ())
      yy_destroy_ ("Cleanup: discarding lookahead", yyla);

    /* Do not reclaim the symbols of the rule whose action triggered
       this YYABORT or YYACCEPT.  */
    yypop_ (yylen);
    while (1 < yystack_.size ())
      {
        yy_destroy_ ("Cleanup: popping", yystack_[0]);
        yypop_ ();
      }

    return yyresult;
  }
#if YY_EXCEPTIONS
    catch (...)
      {
        YYCDEBUG << "Exception caught: cleaning lookahead and stack\n";
        // Do not try to display the values of the reclaimed symbols,
        // as their printers might throw an exception.
        if (!yyla.empty ())
          yy_destroy_ (YY_NULLPTR, yyla);

        while (1 < yystack_.size ())
          {
            yy_destroy_ (YY_NULLPTR, yystack_[0]);
            yypop_ ();
          }
        throw;
      }
#endif // YY_EXCEPTIONS
  }

  void
  LoLaParser::error (const syntax_error& yyexc)
  {
    error (yyexc.location, yyexc.what ());
  }

  // Generate an error message.
  std::string
  LoLaParser::yysyntax_error_ (state_type, const symbol_type&) const
  {
    return YY_("syntax error");
  }


  const signed char LoLaParser::yypact_ninf_ = -98;

  const signed char LoLaParser::yytable_ninf_ = -1;

  const short
  LoLaParser::yypact_[] =
  {
     -98,    10,    35,   -98,   -98,   163,    54,   -37,   -22,    19,
      23,    26,    42,    31,    57,   158,    88,   -98,   -98,   -98,
     -98,   -98,   -98,   -98,   -98,   -98,   -98,   -98,   -98,     2,
     -98,    71,   -98,   187,   117,   -98,   -98,    17,   202,   -19,
      45,   163,   -98,     2,   -98,   -98,   -98,    51,    -3,   -15,
      72,    59,   163,   163,    99,   -98,   -98,   -98,   -14,    69,
     163,    63,   -98,   163,   163,   163,   163,   163,   163,   -98,
     -98,   -98,   -98,   -98,   163,   -98,   -98,   -98,   -98,   -98,
     -98,   163,   -98,   -98,   163,   -98,   -98,   -98,   163,   -98,
     -98,   163,   163,   -98,   -98,    90,    24,    48,     6,   -98,
     -98,     7,    -4,   110,   118,   137,   140,   150,   156,   169,
      51,   202,   -19,    45,    51,   175,   163,   120,   139,   120,
     -98,    13,   -98,   -98,   131,   -98,   -98,   -98,   -98,   -98,
     -98,   -98,    67,   -98,   111,   -98,   120,    89,   -98,    75,
     120,   139,   -98,   -98,   -98,   -98,   -98
  };

  const signed char
  LoLaParser::yydefact_[] =
  {
       3,     0,     2,     1,    11,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,    80,    70,    69,     4,
      20,     5,    13,    14,    15,    16,    19,    17,    18,     0,
      65,    67,    68,    66,     0,    60,    61,     0,    42,    50,
      54,     0,    59,    63,    67,    66,    75,    78,     0,     0,
       0,     0,     0,     0,     0,    21,    22,    35,     0,     0,
       0,     0,    38,     0,     0,     0,     0,     0,     0,    10,
      12,    64,    39,    40,     0,    45,    46,    43,    44,    48,
      47,     0,    51,    52,     0,    55,    56,    57,     0,    62,
      76,     0,     0,    24,    25,     0,     0,     0,     0,    34,
      73,     0,     0,     0,     0,     0,     0,     0,     0,     0,
      41,    49,    53,    58,    77,     0,     0,     0,     0,     0,
       8,     0,    74,    79,     0,    26,    27,    28,    29,    30,
      31,    23,     0,    33,    37,     7,     0,     0,    71,     0,
       0,     0,     6,     9,    72,    32,    36
  };

  const signed char
  LoLaParser::yypgoto_[] =
  {
     -98,   -98,   -98,   -98,   -98,   -97,   -98,   -31,   -98,   -98,
     -98,   -98,   -98,   -98,   -98,   -98,     3,   -98,    50,   -98,
      61,   -98,    55,   -98,   112,    -2,   -98,    -1,   -98,   -52,
       0
  };

  const signed char
  LoLaParser::yydefgoto_[] =
  {
      -1,     1,     2,    19,   121,    20,    34,    21,    22,    23,
      24,    25,    26,    27,    28,    74,    47,    81,    38,    84,
      39,    88,    40,    41,    42,    43,    30,    44,    32,    48,
      45
  };

  const unsigned char
  LoLaParser::yytable_[] =
  {
      29,    31,    33,    70,   123,    90,    49,   101,    37,    60,
       3,    92,   119,   122,    93,    99,    82,    83,    58,   136,
     133,    50,   135,    71,    51,    91,    72,    73,    52,    61,
     117,    53,    29,    31,    33,    91,    72,    73,     4,   142,
       5,   137,     6,   145,     7,     8,     9,    10,    11,   120,
      12,    13,    14,    15,   118,    96,    97,    72,    73,     5,
      55,     6,    46,   102,    72,    73,   104,   105,   106,   107,
     108,   109,   139,   140,     5,   100,     6,   110,    16,    17,
      18,   144,    85,    86,    87,    54,    56,   134,    72,    73,
      35,    72,    73,    59,   114,   115,    36,    16,    17,    18,
      62,    94,    95,    91,    98,    35,   103,    72,    73,   116,
     146,    36,    16,    17,    18,   124,    29,    31,    33,   132,
       4,    69,     5,     4,     6,   141,     7,     8,     9,    10,
      11,   111,   143,    13,    14,    15,     5,   138,     6,    29,
      31,    33,     4,   113,     5,   112,     6,   125,     7,     8,
       9,    10,    11,    89,     0,    13,    14,    15,    72,    73,
      16,    17,    18,     5,     0,     6,   126,    35,     5,   127,
       6,     0,     0,    36,    16,    17,    18,    72,    73,   128,
      72,    73,    16,    17,    18,   129,     0,    57,     0,     0,
      72,    73,     0,     0,    35,     0,    72,    73,   130,    35,
      36,    16,    17,    18,   131,    36,    16,    17,    18,    72,
      73,     0,     0,    63,     0,    72,    73,    64,    65,    66,
      67,    68,    75,    76,    77,    78,    79,    80
  };

  const short
  LoLaParser::yycheck_[] =
  {
       2,     2,     2,    34,     8,     8,    43,    59,     5,     7,
       0,    26,     6,     6,    29,    29,    35,    36,    15,     6,
     117,    43,   119,     6,     5,    28,    40,    41,     5,    27,
       6,     5,    34,    34,    34,    28,    40,    41,     3,   136,
       5,    28,     7,   140,     9,    10,    11,    12,    13,    43,
      15,    16,    17,    18,     6,    52,    53,    40,    41,     5,
      29,     7,     8,    60,    40,    41,    63,    64,    65,    66,
      67,    68,   124,     6,     5,     6,     7,    74,    43,    44,
      45,     6,    37,    38,    39,    43,    29,   118,    40,    41,
      36,    40,    41,     5,    91,    92,    42,    43,    44,    45,
      29,    29,    43,    28,     5,    36,    43,    40,    41,    19,
     141,    42,    43,    44,    45,     5,   118,   118,   118,   116,
       3,     4,     5,     3,     7,    14,     9,    10,    11,    12,
      13,    81,    43,    16,    17,    18,     5,     6,     7,   141,
     141,   141,     3,    88,     5,    84,     7,    29,     9,    10,
      11,    12,    13,    41,    -1,    16,    17,    18,    40,    41,
      43,    44,    45,     5,    -1,     7,    29,    36,     5,    29,
       7,    -1,    -1,    42,    43,    44,    45,    40,    41,    29,
      40,    41,    43,    44,    45,    29,    -1,    29,    -1,    -1,
      40,    41,    -1,    -1,    36,    -1,    40,    41,    29,    36,
      42,    43,    44,    45,    29,    42,    43,    44,    45,    40,
      41,    -1,    -1,    26,    -1,    40,    41,    30,    31,    32,
      33,    34,    20,    21,    22,    23,    24,    25
  };

  const signed char
  LoLaParser::yystos_[] =
  {
       0,    47,    48,     0,     3,     5,     7,     9,    10,    11,
      12,    13,    15,    16,    17,    18,    43,    44,    45,    49,
      51,    53,    54,    55,    56,    57,    58,    59,    60,    71,
      72,    73,    74,    76,    52,    36,    42,    62,    64,    66,
      68,    69,    70,    71,    73,    76,     8,    62,    75,    43,
      43,     5,     5,     5,    43,    29,    29,    29,    62,     5,
       7,    27,    29,    26,    30,    31,    32,    33,    34,     4,
      53,     6,    40,    41,    61,    20,    21,    22,    23,    24,
      25,    63,    35,    36,    65,    37,    38,    39,    67,    70,
       8,    28,    26,    29,    29,    43,    62,    62,     5,    29,
       6,    75,    62,    43,    62,    62,    62,    62,    62,    62,
      62,    64,    66,    68,    62,    62,    19,     6,     6,     6,
      43,    50,     6,     8,     5,    29,    29,    29,    29,    29,
      29,    29,    62,    51,    53,    51,     6,    28,     6,    75,
       6,    14,    51,    43,     6,    51,    53
  };

  const signed char
  LoLaParser::yyr1_[] =
  {
       0,    46,    47,    48,    48,    48,    49,    49,    50,    50,
      51,    52,    52,    53,    53,    53,    53,    53,    53,    53,
      53,    53,    53,    54,    54,    54,    55,    55,    55,    55,
      55,    55,    56,    57,    58,    58,    59,    59,    60,    61,
      61,    62,    62,    63,    63,    63,    63,    63,    63,    64,
      64,    65,    65,    66,    66,    67,    67,    67,    68,    68,
      69,    69,    70,    70,    71,    71,    71,    72,    72,    72,
      72,    73,    73,    73,    73,    74,    74,    75,    75,    76,
      76
  };

  const signed char
  LoLaParser::yyr2_[] =
  {
       0,     2,     1,     0,     2,     2,     6,     5,     1,     3,
       3,     0,     2,     1,     1,     1,     1,     1,     1,     1,
       1,     2,     2,     5,     3,     3,     4,     4,     4,     4,
       4,     4,     7,     5,     3,     2,     7,     5,     2,     1,
       1,     3,     1,     1,     1,     1,     1,     1,     1,     3,
       1,     1,     1,     3,     1,     1,     1,     1,     3,     1,
       1,     1,     2,     1,     3,     1,     1,     1,     1,     1,
       1,     5,     6,     3,     4,     2,     3,     3,     1,     4,
       1
  };


#if YYDEBUG
  // YYTNAME[SYMBOL-NUM] -- String name of the symbol SYMBOL-NUM.
  // First, the terminals, then, starting at \a yyntokens_, nonterminals.
  const char*
  const LoLaParser::yytname_[] =
  {
  "END", "error", "$undefined", "CURLY_O", "CURLY_C", "ROUND_O",
  "ROUND_C", "SQUARE_O", "SQUARE_C", "VAR", "EXTERN", "FOR", "WHILE", "IF",
  "ELSE", "FUNCTION", "BREAK", "CONTINUE", "RETURN", "IN", "LEQUAL",
  "GEQUAL", "EQUALS", "DIFFERS", "LESS", "MORE", "IS", "DOT", "COMMA",
  "TERMINATOR", "PLUS_IS", "MINUS_IS", "MULT_IS", "DIV_IS", "MOD_IS",
  "PLUS", "MINUS", "MULT", "DIV", "MOD", "AND", "OR", "INVERT", "IDENT",
  "NUMBER", "STRING", "$accept", "compile_unit", "program", "function",
  "plist", "body", "stmtlist", "statement", "decl", "ass", "for", "while",
  "return", "conditional", "expression", "expr_0_op", "expr_0",
  "expr_02_op", "expr_02", "expr_1_op", "expr_1", "expr_2_op", "expr_2",
  "expr_3_op", "expr_3", "expr_4", "rvalue", "call", "array", "arglist",
  "lvalue", YY_NULLPTR
  };


  const unsigned char
  LoLaParser::yyrline_[] =
  {
       0,    82,    82,    84,    85,    89,    95,   100,   106,   110,
     117,   120,   121,   127,   128,   129,   130,   131,   132,   133,
     134,   135,   136,   139,   140,   141,   144,   145,   146,   147,
     148,   149,   152,   155,   158,   159,   162,   163,   166,   169,
     169,   170,   171,   174,   174,   174,   174,   174,   174,   175,
     176,   180,   180,   181,   182,   186,   186,   186,   187,   188,
     192,   192,   193,   194,   198,   199,   200,   203,   204,   205,
     206,   209,   210,   211,   212,   215,   216,   219,   223,   228,
     229
  };

  // Print the state stack on the debug stream.
  void
  LoLaParser::yystack_print_ ()
  {
    *yycdebug_ << "Stack now";
    for (stack_type::const_iterator
           i = yystack_.begin (),
           i_end = yystack_.end ();
         i != i_end; ++i)
      *yycdebug_ << ' ' << int (i->state);
    *yycdebug_ << '\n';
  }

  // Report on the debug stream that the rule \a yyrule is going to be reduced.
  void
  LoLaParser::yy_reduce_print_ (int yyrule)
  {
    int yylno = yyrline_[yyrule];
    int yynrhs = yyr2_[yyrule];
    // Print the symbols being reduced, and their result.
    *yycdebug_ << "Reducing stack by rule " << yyrule - 1
               << " (line " << yylno << "):\n";
    // The symbols being reduced.
    for (int yyi = 0; yyi < yynrhs; yyi++)
      YY_SYMBOL_PRINT ("   $" << yyi + 1 << " =",
                       yystack_[(yynrhs) - (yyi + 1)]);
  }
#endif // YYDEBUG

  LoLaParser::token_number_type
  LoLaParser::yytranslate_ (int t)
  {
    // YYTRANSLATE[TOKEN-NUM] -- Symbol number corresponding to
    // TOKEN-NUM as returned by yylex.
    static
    const token_number_type
    translate_table[] =
    {
       0,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     1,     2,     3,     4,
       5,     6,     7,     8,     9,    10,    11,    12,    13,    14,
      15,    16,    17,    18,    19,    20,    21,    22,    23,    24,
      25,    26,    27,    28,    29,    30,    31,    32,    33,    34,
      35,    36,    37,    38,    39,    40,    41,    42,    43,    44,
      45
    };
    const int user_token_number_max_ = 300;

    if (t <= 0)
      return yyeof_;
    else if (t <= user_token_number_max_)
      return translate_table[t];
    else
      return yy_undef_token_;
  }

#line 5 "grammar.yy"
} // LoLa
#line 2201 "grammar.tab.cpp"

#line 233 "grammar.yy"



void
LoLa::LoLaParser::error( const location_type &l, const std::string &err_message )
{
   std::cerr << "Error: " << err_message << " at " << l << "\n";
}
