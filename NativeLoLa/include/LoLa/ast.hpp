#ifndef AST_HPP
#define AST_HPP

#include <vector>
#include <string>
#include <memory>
#include <optional>

namespace LoLa::Compiler
{
    struct CodeWriter;
    struct Scope;
}

namespace LoLa::AST
{
    template<typename T>
    using List = std::vector<T>;

    using String = std::string;

    enum class Operator
    {
        LessOrEqual,
        MoreOrEqual,
        Equals,
        Differs,
        Less,
        More,

        Plus,
        Minus,
        Multiply,
        Divide,
        Modulus,

        And,
        Or,
        Not
    };

    struct StatementBase {
        virtual ~StatementBase();
        virtual void emit(Compiler::CodeWriter & writer, Compiler::Scope & scope) = 0;
    };

    struct ExpressionBase {
        virtual ~ExpressionBase();
        virtual void emit(Compiler::CodeWriter & writer, Compiler::Scope & scope) = 0;

        virtual std::unique_ptr<ExpressionBase> clone() const = 0;
    };

    struct LValueExpressionBase : ExpressionBase {
        virtual ~LValueExpressionBase();
        virtual void emitStore(Compiler::CodeWriter & writer, Compiler::Scope & scope) = 0;
    };

    using Statement = std::unique_ptr<StatementBase>;
    using Expression = std::unique_ptr<ExpressionBase>;
    using LValueExpression = std::unique_ptr<LValueExpressionBase>;

    LValueExpression ArrayIndexer(Expression var, Expression index);
    LValueExpression VariableRef(String var);
    Expression ArrayLiteral(List<Expression> initializer);
    Expression FunctionCall(String name, List<Expression> args);
    Expression MethodCall(Expression object, String name, List<Expression> args);
    Expression NumberLiteral(String literal);
    Expression StringLiteral(String literal);

    Expression UnaryOperator(Operator op, Expression value);
    Expression BinaryOperator(Operator op, Expression lhs, Expression rhs);

    Statement Assignment(LValueExpression target, Expression value);

    Statement Return();
    Statement Return(Expression value);
    Statement WhileLoop(Expression condition, Statement body);
    Statement ForLoop(String var, Expression source, Statement body);
    Statement IfElse(Expression condition, Statement true_body);
    Statement IfElse(Expression condition, Statement true_body, Statement false_body);

    Statement DiscardResult(Expression value);

    Statement Declaration(String name);
    Statement Declaration(String name, Expression value);
    Statement ExternDeclaration(String name);

    Statement SubScope(List<Statement> body);

    Statement BreakStatement();

    Statement ContinueStatement();

    struct Function
    {
        std::string name;
        std::vector<std::string> params;
        Statement body;
    };

    struct Program
    {
        std::vector<Function> functions;
        std::vector<Statement> statements;
    };

    std::optional<Program> parse(std::string_view src);
    std::optional<Program> parse(std::istream & src);
}

#endif // AST_HPP
