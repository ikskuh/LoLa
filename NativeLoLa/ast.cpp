#include "ast.hpp"
#include <cassert>

using namespace LoLa::AST;
using std::move;

LoLa::AST::StatementBase::~StatementBase()
{

}

LoLa::AST::ExpressionBase::~ExpressionBase()
{

}
Expression LoLa::AST::VariableRef(String var)
{
    struct Foo : ExpressionBase {
        std::string name;
        Foo(std::string str) : name(str) { }
    };
    return std::make_unique<Foo>(var);
}

Expression LoLa::AST::NumberLiteral(String literal)
{
    struct Foo : ExpressionBase {
        double value;
        Foo(double v) : value(v) { }
    };
    return std::make_unique<Foo>(std::strtod(literal.c_str(), nullptr));
}

Expression LoLa::AST::StringLiteral(String literal)
{
    struct Foo : ExpressionBase {
        std::string text;
        Foo(std::string str) : text(str) { }
    };
    assert(literal.size() >= 2);
    return std::make_unique<Foo>(literal.substr(1, literal.size() - 2));
}

Expression LoLa::AST::ArrayIndexer(Expression value, Expression index)
{
    struct Foo : ExpressionBase {
        Expression value, index;
        Foo(Expression l, Expression r) : value(move(l)), index(move(r)) { }
    };
    return std::make_unique<Foo>(move(value), move(index));
}

Expression LoLa::AST::ArrayLiteral(List<Expression> initializer)
{
    struct Foo : ExpressionBase {
        List<Expression> values;
        Foo(List<Expression> v) : values(move(v)) { }
    };
    return std::make_unique<Foo>(move(initializer));
}

Expression LoLa::AST::FunctionCall(String name, List<Expression> args)
{
    struct Foo : ExpressionBase {
        String function;
        List<Expression> args;
        Foo(String f, List<Expression> a) : function(f), args(move(a)) { }
    };
    return std::make_unique<Foo>(name, move(args));
}

Expression LoLa::AST::MethodCall(Expression object, String name, List<Expression> args)
{
    struct Foo : ExpressionBase {
        Expression object;
        String function;
        List<Expression> args;
        Foo(Expression object, String f, List<Expression> a) : object(move(object)), function(f), args(move(a)) { }
    };
    return std::make_unique<Foo>(move(object), name, move(args));
}

Expression LoLa::AST::UnaryOperator(Operator op, Expression value)
{
    struct Foo : ExpressionBase {
        Operator op;
        Expression value;
        Foo(Operator o, Expression v) : op(o), value(move(v)) { }
    };
    return std::make_unique<Foo>(op, move(value));
}
Expression LoLa::AST::BinaryOperator(Operator op, Expression lhs, Expression rhs)
{
    struct Foo : ExpressionBase {
        Operator op;
        Expression lhs, rhs;
        Foo(Operator o, Expression l, Expression r) : op(o), lhs(move(l)), rhs(move(r)) { }
    };
    return std::make_unique<Foo>(op, move(lhs), move(rhs));
}

Statement LoLa::AST::Assignment(Expression target, Expression value)
{
    struct Foo : StatementBase {
        Expression lhs, rhs;
        Foo(Expression l, Expression r) : lhs(move(l)), rhs(move(r)) { }
    };
    return std::make_unique<Foo>(move(target), move(value));
}

Statement LoLa::AST::Return()
{
    struct Foo : StatementBase {
        Foo() { }
    };
    return std::make_unique<Foo>();
}
Statement LoLa::AST::Return(Expression value)
{
    struct Foo : StatementBase {
        Expression value;
        Foo(Expression v) :value(move(v)) { }
    };
    return std::make_unique<Foo>(move(value));
}
Statement LoLa::AST::WhileLoop(Expression condition, Statement body)
{
    struct Foo : StatementBase {
        Expression cond;
        Statement body;
        Foo(Expression cond, Statement body) : cond(move(cond)), body(move(body)) { }
    };
    return std::make_unique<Foo>(move(condition), move(body));
}
Statement LoLa::AST::ForLoop(String var, Expression source, Statement body)
{
    struct Foo : StatementBase {
        String var;
        Expression list;
        Statement body;
        Foo(String var, Expression list, Statement body) : var(var), list(move(list)), body(move(body)) { }
    };
    return std::make_unique<Foo>(var, move(source), move(body));
}
Statement LoLa::AST::IfElse(Expression condition, Statement true_body)
{
    struct Foo : StatementBase {
        Expression cond;
        Statement body;
        Foo(Expression cond, Statement body) : cond(move(cond)), body(move(body)) { }
    };
    return std::make_unique<Foo>(move(condition), move(true_body));
}

Statement LoLa::AST::IfElse(Expression condition, Statement true_body, Statement false_body)
{
    struct Foo : StatementBase {
        Expression cond;
        Statement true_body;
        Statement false_body;
        Foo(Expression cond, Statement tbody, Statement fbody) : cond(move(cond)), true_body(move(tbody)), false_body(move(fbody)) { }
    };
    return std::make_unique<Foo>(move(condition), move(true_body), move(false_body));
}

Statement LoLa::AST::DiscardResult(Expression value)
{
    struct Foo : StatementBase {
        Expression value;
        Foo(Expression v) :value(move(v)) { }
    };
    return std::make_unique<Foo>(move(value));
}

Statement LoLa::AST::Declaration(String name)
{
    struct Foo : StatementBase {
        String name;
        Foo(String name) :name(move(name)){ }
    };
    return std::make_unique<Foo>(name);
}
Statement LoLa::AST::Declaration(String name, Expression value)
{
    struct Foo : StatementBase {
        String name;
        Expression value;
        Foo(String name, Expression v) :name(move(name)), value(move(v)) { }
    };
    return std::make_unique<Foo>(name, move(value));
}

Statement LoLa::AST::SubScope(List<Statement> body)
{
    struct Foo : StatementBase {
        List<Statement> content;
        Foo(List<Statement> v) : content(move(v)) { }
    };
    return std::make_unique<Foo>(move(body));
}
