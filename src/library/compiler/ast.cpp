#include "ast.hpp"
#include "compiler.hpp"
#include "driver.hpp"
#include <cassert>
#include <sstream>

// Imported from Zig code
extern "C" bool resolveEscapeSequences(uint8_t *str, size_t *length);

using namespace LoLa::AST;
using LoLa::Compiler::CodeWriter;
using LoLa::Compiler::Scope;
using LoLa::IL::Instruction;
using std::move;

static List<Expression> clone(List<Expression> const &list)
{
    List<Expression> result(list.size());
    for (size_t i = 0; i < result.size(); i++)
    {
        result[i] = list[i]->clone();
    }
    return result;
}

static bool isReservedName(std::string const &name)
{
    return (name == "true") or (name == "false") or (name == "void");
}

LoLa::AST::StatementBase::~StatementBase()
{
}

ExpressionBase::~ExpressionBase()
{
}

LValueExpression LoLa::AST::VariableRef(String var)
{
    struct Foo : LValueExpressionBase
    {
        std::string name;
        Foo(std::string str) : name(str) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            if (name == "true")
            {
                code.emit(Instruction::push_true);
            }
            else if (name == "false")
            {
                code.emit(Instruction::push_false);
            }
            else if (name == "void")
            {
                code.emit(Instruction::push_void);
            }
            else if (auto local = scope.get(name); local)
            {
                switch (local->second)
                {
                case Scope::Extern:
                    code.emit(Instruction::load_global_name);
                    code.emit(name);
                    break;

                case Scope::Global:
                    code.emit(Instruction::load_global_idx);
                    code.emit(local->first);
                    break;

                case Scope::Local:
                    code.emit(Instruction::load_local);
                    code.emit(local->first);
                    break;
                }
            }
            else
            {
                errors.variableNotFound(name);
            }
        }

        void emitStore(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            if (isReservedName(name))
            {
                errors.invalidStore(name);
            }
            else if (auto local = scope.get(name); local)
            {
                switch (local->second)
                {
                case Scope::Extern:
                    code.emit(Instruction::store_global_name);
                    code.emit(name);
                    break;
                case Scope::Global:
                    code.emit(Instruction::store_global_idx);
                    code.emit(local->first);
                    break;
                case Scope::Local:
                    code.emit(Instruction::store_local);
                    code.emit(local->first);
                    break;
                }
            }
            else
            {
                errors.variableNotFound(name);
            }
        }

        std::unique_ptr<ExpressionBase> clone() const override
        {
            return std::make_unique<Foo>(*this);
        }
    };
    return std::make_unique<Foo>(var);
}

Expression LoLa::AST::NumberLiteral(String literal)
{
    struct Foo : ExpressionBase
    {
        double value;
        Foo(double v) : value(v) {}

        void emit(CodeWriter &code, Scope &, Compiler::ErrorCollection &) override
        {

            code.emit(Instruction::push_num);
            code.emit(value);
        }

        std::unique_ptr<ExpressionBase> clone() const override
        {
            return std::make_unique<Foo>(*this);
        }
    };
    return std::make_unique<Foo>(std::strtod(literal.c_str(), nullptr));
}

Expression LoLa::AST::StringLiteral(String literal)
{
    struct Foo : ExpressionBase
    {
        std::string text;
        Foo(std::string str) : text(str) {}

        void emit(CodeWriter &code, Scope &, Compiler::ErrorCollection &errors) override
        {
            code.emit(Instruction::push_str);

            std::string escaped = text;

            size_t length = escaped.size();
            auto const success = resolveEscapeSequences(
                reinterpret_cast<uint8_t *>(escaped.data()),
                &length);
            if (success)
            {

                escaped.resize(length);

                code.emit(text);
            }
            else
            {
                errors.invalidString(text);
            }
        }

        std::unique_ptr<ExpressionBase> clone() const override
        {
            return std::make_unique<Foo>(*this);
        }
    };
    assert(literal.size() >= 2);
    return std::make_unique<Foo>(literal.substr(1, literal.size() - 2));
}

LValueExpression LoLa::AST::ArrayIndexer(Expression value, Expression index)
{
    struct Foo : LValueExpressionBase
    {
        Expression value, index;
        Foo(Expression l, Expression r) : value(move(l)), index(move(r)) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            index->emit(code, scope, errors);
            value->emit(code, scope, errors);
            code.emit(Instruction::array_load);
        }

        void emitStore(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            if (auto *lvalue = dynamic_cast<LValueExpressionBase *>(value.get()); lvalue != nullptr)
            {
                // read-modify-write the lvalue expression
                index->emit(code, scope, errors);  // load the index on the stack
                lvalue->emit(code, scope, errors); // load the array on the stack
                code.emit(Instruction::array_store);
                lvalue->emitStore(code, scope, errors); // now store back the value on the stack
            }
            else
            {
                assert(false and "syntax error not implemented yet");
            }
        }

        std::unique_ptr<ExpressionBase> clone() const override
        {
            return std::make_unique<Foo>(value->clone(), index->clone());
        }
    };
    return std::make_unique<Foo>(move(value), move(index));
}

Expression LoLa::AST::ArrayLiteral(List<Expression> initializer)
{
    struct Foo : ExpressionBase
    {
        List<Expression> values;
        Foo(List<Expression> v) : values(move(v)) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            assert(values.size() < 65536);

            for (auto it = values.rbegin(); it != values.rend(); it++)
                (*it)->emit(code, scope, errors);

            code.emit(Instruction::array_pack);
            code.emit(uint16_t(values.size()));
        }

        std::unique_ptr<ExpressionBase> clone() const override
        {
            return std::make_unique<Foo>(::clone(values));
        }
    };
    return std::make_unique<Foo>(move(initializer));
}

Expression LoLa::AST::FunctionCall(String name, List<Expression> args)
{
    struct Foo : ExpressionBase
    {
        String function;
        List<Expression> args;
        Foo(String f, List<Expression> a) : function(f), args(move(a)) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {

            assert(args.size() < 256);

            for (auto it = args.rbegin(); it != args.rend(); it++)
                (*it)->emit(code, scope, errors);

            code.emit(Instruction::call_fn);
            code.emit(function);
            code.emit(uint8_t(args.size()));
        }

        std::unique_ptr<ExpressionBase> clone() const override
        {
            return std::make_unique<Foo>(function, ::clone(args));
        }
    };
    return std::make_unique<Foo>(name, move(args));
}

Expression LoLa::AST::MethodCall(Expression object, String name, List<Expression> args)
{
    struct Foo : ExpressionBase
    {
        Expression object;
        String function;
        List<Expression> args;
        Foo(Expression object, String f, List<Expression> a) : object(move(object)), function(f), args(move(a)) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {

            assert(args.size() < 256);

            for (auto it = args.rbegin(); it != args.rend(); it++)
                (*it)->emit(code, scope, errors);

            object->emit(code, scope, errors);

            code.emit(Instruction::call_obj);
            code.emit(function);
            code.emit(uint8_t(args.size()));
        }

        std::unique_ptr<ExpressionBase> clone() const override
        {
            return std::make_unique<Foo>(this->object->clone(), this->function, ::clone(this->args));
        }
    };
    return std::make_unique<Foo>(move(object), name, move(args));
}

Expression LoLa::AST::UnaryOperator(Operator op, Expression value)
{
    struct Foo : ExpressionBase
    {
        Operator op;
        Expression value;
        Foo(Operator o, Expression v) : op(o), value(move(v)) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            value->emit(code, scope, errors);
            switch (op)
            {
            case Operator::Minus:
                code.emit(Instruction::negate);
                break;
            case Operator::Not:
                code.emit(Instruction::bool_not);
                break;
            default:
                errors.invalidOperator(op);
                break;
            }
        }

        std::unique_ptr<ExpressionBase> clone() const override
        {
            return std::make_unique<Foo>(this->op, this->value->clone());
        }
    };
    return std::make_unique<Foo>(op, move(value));
}
Expression LoLa::AST::BinaryOperator(Operator op, Expression lhs, Expression rhs)
{
    struct Foo : ExpressionBase
    {
        Expression lhs, rhs;
        Operator op;
        Foo(Operator o, Expression l, Expression r) : lhs(move(l)), rhs(move(r)), op(o) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            lhs->emit(code, scope, errors);
            rhs->emit(code, scope, errors);
            switch (op)
            {
            case Operator::Plus:
                code.emit(Instruction::add);
                break;
            case Operator::Minus:
                code.emit(Instruction::sub);
                break;
            case Operator::Multiply:
                code.emit(Instruction::mul);
                break;
            case Operator::Divide:
                code.emit(Instruction::div);
                break;
            case Operator::Modulus:
                code.emit(Instruction::mod);
                break;
            case Operator::Less:
                code.emit(Instruction::less);
                break;
            case Operator::LessOrEqual:
                code.emit(Instruction::less_eq);
                break;
            case Operator::More:
                code.emit(Instruction::greater);
                break;
            case Operator::MoreOrEqual:
                code.emit(Instruction::greater_eq);
                break;
            case Operator::Equals:
                code.emit(Instruction::eq);
                break;
            case Operator::Differs:
                code.emit(Instruction::neq);
                break;
            case Operator::And:
                code.emit(Instruction::bool_and);
                break;
            case Operator::Or:
                code.emit(Instruction::bool_or);
                break;
            default:
                errors.invalidOperator(op);
                break;
            }
        }

        std::unique_ptr<ExpressionBase> clone() const override
        {
            return std::make_unique<Foo>(this->op, this->lhs->clone(), this->rhs->clone());
        }
    };
    return std::make_unique<Foo>(op, move(lhs), move(rhs));
}

Statement LoLa::AST::Assignment(LValueExpression target, Expression value)
{
    struct Foo : StatementBase
    {
        LValueExpression lhs;
        Expression rhs;
        Foo(LValueExpression l, Expression r) : lhs(move(l)), rhs(move(r)) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            rhs->emit(code, scope, errors);
            lhs->emitStore(code, scope, errors);
        }
    };
    return std::make_unique<Foo>(move(target), move(value));
}

Statement LoLa::AST::Return()
{
    struct Foo : StatementBase
    {
        void emit(CodeWriter &code, Scope &, Compiler::ErrorCollection &) override
        {
            code.emit(Instruction::ret);
        }
    };
    return std::make_unique<Foo>();
}
Statement LoLa::AST::Return(Expression value)
{
    struct Foo : StatementBase
    {
        Expression value;
        Foo(Expression v) : value(move(v)) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            value->emit(code, scope, errors);
            code.emit(Instruction::retval);
        }
    };
    return std::make_unique<Foo>(move(value));
}
Statement LoLa::AST::WhileLoop(Expression condition, Statement body)
{
    struct Foo : StatementBase
    {
        Expression cond;
        Statement body;
        Foo(Expression cond, Statement body) : cond(move(cond)), body(move(body)) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            auto const loop_start = code.createAndDefineLabel();
            auto const loop_end = code.createLabel();

            code.pushLoop(loop_end, loop_start);

            cond->emit(code, scope, errors);
            code.emit(Instruction::jif);
            code.emit(loop_end);

            body->emit(code, scope, errors);

            code.emit(Instruction::jmp);
            code.emit(loop_start);

            code.defineLabel(loop_end);

            code.popLoop();
        }
    };
    return std::make_unique<Foo>(move(condition), move(body));
}
Statement LoLa::AST::ForLoop(String var, Expression source, Statement body)
{
    struct Foo : StatementBase
    {
        String var;
        Expression list;
        Statement body;
        Foo(String var, Expression list, Statement body) : var(var), list(move(list)), body(move(body)) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            scope.enter();

            list->emit(code, scope, errors);
            code.emit(Instruction::iter_make);

            scope.declare(var);

            auto loopvar = scope.get(var);
            assert(loopvar);

            auto const loop_start = code.createAndDefineLabel();
            auto const loop_end = code.createLabel();

            code.pushLoop(loop_end, loop_start);

            code.emit(Instruction::iter_next);

            code.emit(Instruction::jif);
            code.emit(loop_end);

            if (loopvar->second == Scope::Global)
                code.emit(Instruction::store_global_idx);
            else
                code.emit(Instruction::store_local);
            code.emit(loopvar->first);

            body->emit(code, scope, errors);

            code.emit(Instruction::jmp);
            code.emit(loop_start);

            code.defineLabel(loop_end);

            code.popLoop();

            // erase the iterator from the stack
            code.emit(Instruction::pop);

            scope.leave();
        }
    };
    return std::make_unique<Foo>(var, move(source), move(body));
}
Statement LoLa::AST::IfElse(Expression condition, Statement true_body)
{
    struct Foo : StatementBase
    {
        Expression cond;
        Statement body;
        Foo(Expression cond, Statement body) : cond(move(cond)), body(move(body)) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            cond->emit(code, scope, errors);

            auto lbl = code.createLabel();
            code.emit(Instruction::jif);
            code.emit(lbl);

            body->emit(code, scope, errors);

            code.defineLabel(lbl);
        }
    };
    return std::make_unique<Foo>(move(condition), move(true_body));
}

Statement LoLa::AST::IfElse(Expression condition, Statement true_body, Statement false_body)
{
    struct Foo : StatementBase
    {
        Expression cond;
        Statement true_body;
        Statement false_body;
        Foo(Expression cond, Statement tbody, Statement fbody) : cond(move(cond)), true_body(move(tbody)), false_body(move(fbody)) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            cond->emit(code, scope, errors);

            auto lbl_false = code.createLabel();
            auto lbl_end = code.createLabel();
            code.emit(Instruction::jif);
            code.emit(lbl_false);

            true_body->emit(code, scope, errors);

            code.emit(Instruction::jmp);
            code.emit(lbl_end);

            code.defineLabel(lbl_false);
            false_body->emit(code, scope, errors);

            code.defineLabel(lbl_end);
        }
    };
    return std::make_unique<Foo>(move(condition), move(true_body), move(false_body));
}

Statement LoLa::AST::DiscardResult(Expression value)
{
    struct Foo : StatementBase
    {
        Expression value;
        Foo(Expression v) : value(move(v)) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            value->emit(code, scope, errors);
            code.emit(Instruction::pop);
        }
    };
    return std::make_unique<Foo>(move(value));
}

Statement LoLa::AST::Declaration(String name)
{
    struct Foo : StatementBase
    {
        String name;
        Foo(String name) : name(move(name)) {}

        void emit(CodeWriter &, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            if (isReservedName(name))
                errors.invalidVariable(name);
            else
                scope.declare(name);
        }
    };
    return std::make_unique<Foo>(name);
}

Statement LoLa::AST::ExternDeclaration(String name)
{
    struct Foo : StatementBase
    {
        String name;
        Foo(String name) : name(move(name)) {}

        void emit(CodeWriter &, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            if (isReservedName(name))
                errors.invalidVariable(name);
            else
                scope.declareExtern(name);
        }
    };
    return std::make_unique<Foo>(name);
}

Statement LoLa::AST::Declaration(String name, Expression value)
{
    struct Foo : StatementBase
    {
        String name;
        Expression value;
        Foo(String name, Expression v) : name(move(name)), value(move(v)) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            if (isReservedName(name))
            {
                errors.invalidVariable(name);
            }
            else
            {

                scope.declare(name);
                value->emit(code, scope, errors);

                auto const pos = scope.get(name);
                assert(pos != std::nullopt);

                if (pos->second == Scope::Global)
                    code.emit(Instruction::store_global_idx);
                else
                    code.emit(Instruction::store_local);
                code.emit(pos->first);
            }
        }
    };
    return std::make_unique<Foo>(name, move(value));
}

Statement LoLa::AST::SubScope(List<Statement> body)
{
    struct Foo : StatementBase
    {
        List<Statement> content;
        Foo(List<Statement> v) : content(move(v)) {}

        void emit(CodeWriter &code, Scope &scope, Compiler::ErrorCollection &errors) override
        {
            scope.enter();
            for (auto const &stmt : content)
                stmt->emit(code, scope, errors);
            scope.leave();
        }
    };
    return std::make_unique<Foo>(move(body));
}

Statement LoLa::AST::BreakStatement()
{
    struct Foo : StatementBase
    {
        void emit(CodeWriter &code, Scope &, Compiler::ErrorCollection &errors) override
        {
            code.emitBreak(errors);
        }
    };
    return std::make_unique<Foo>();
}

Statement LoLa::AST::ContinueStatement()
{
    struct Foo : StatementBase
    {
        void emit(CodeWriter &code, Scope &, Compiler::ErrorCollection &errors) override
        {
            code.emitContinue(errors);
        }
    };
    return std::make_unique<Foo>();
}

std::optional<LoLa::AST::Program> LoLa::AST::parse(std::string_view src)
{
    std::stringstream source;
    source << src;
    return parse(source);
}

std::optional<LoLa::AST::Program> LoLa::AST::parse(std::istream &src)
{
    LoLa::LoLaDriver driver;
    if (driver.parse(src))
        return std::move(driver.program);
    else
        return std::nullopt;
}
