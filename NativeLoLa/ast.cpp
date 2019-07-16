#include "ast.hpp"
#include "compiler.hpp"
#include <cassert>

using namespace LoLa::AST;
using std::move;
using LoLa::Compiler::CodeWriter;
using LoLa::Compiler::Scope;
using LoLa::IL::Instruction;

LoLa::AST::StatementBase::~StatementBase()
{

}

ExpressionBase::~ExpressionBase()
{

}

LValueExpressionBase::~LValueExpressionBase()
{

}

LValueExpression LoLa::AST::VariableRef(String var)
{
    struct Foo : LValueExpressionBase {
        std::string name;
        Foo(std::string str) : name(str) { }


        void emit(CodeWriter & code, Scope & scope) override
        {
            if(auto local = scope.get(name); local)
            {
                if(scope.is_global)
                    code.emit(Instruction::load_global_idx);
                else
                    code.emit(Instruction::load_local);
                code.emit(uint16_t(*local));
            }
            else if(auto global = (scope.global_scope != nullptr) ? scope.global_scope->get(name) : std::nullopt; global)
            {
                assert(scope.global_scope->is_global);
                code.emit(Instruction::load_global_idx);
                code.emit(uint16_t(*global));
            }
            else
            {
                code.emit(Instruction::load_global_name);
                code.emit(name);
            }
        }

        void emitStore(CodeWriter & code, Scope & scope) override {
            if(auto local = scope.get(name); local)
            {
                if(scope.is_global)
                    code.emit(Instruction::store_global_idx);
                else
                    code.emit(Instruction::store_local);
                code.emit(uint16_t(*local));
            }
            else if(auto global = (scope.global_scope != nullptr) ? scope.global_scope->get(name) : std::nullopt; global)
            {
                assert(scope.global_scope->is_global);
                code.emit(Instruction::store_global_idx);
                code.emit(uint16_t(*global));
            }
            else
            {
                code.emit(Instruction::store_global_name);
                code.emit(name);
            }
        }
    };
    return std::make_unique<Foo>(var);
}

Expression LoLa::AST::NumberLiteral(String literal)
{
    struct Foo : ExpressionBase {
        double value;
        Foo(double v) : value(v) { }

        void emit(CodeWriter & code, Scope &) override {
            code.emit(Instruction::push_num);
            code.emit(value);
        }
    };
    return std::make_unique<Foo>(std::strtod(literal.c_str(), nullptr));
}

Expression LoLa::AST::StringLiteral(String literal)
{
    struct Foo : ExpressionBase {
        std::string text;
        Foo(std::string str) : text(str) { }

        void emit(CodeWriter & code, Scope &) override {
            code.emit(Instruction::push_str);
            code.emit(text);
        }
    };
    assert(literal.size() >= 2);
    return std::make_unique<Foo>(literal.substr(1, literal.size() - 2));
}

LValueExpression LoLa::AST::ArrayIndexer(Expression value, Expression index)
{
    struct Foo : LValueExpressionBase {
        Expression value, index;
        Foo(Expression l, Expression r) : value(move(l)), index(move(r)) { }


        void emit(CodeWriter & code, Scope &) override {
            throw "invalid operation";
        }


        void emitStore(CodeWriter & code, Scope &) override {
            throw "invalid operation";
        }
    };
    return std::make_unique<Foo>(move(value), move(index));
}

Expression LoLa::AST::ArrayLiteral(List<Expression> initializer)
{
    struct Foo : ExpressionBase {
        List<Expression> values;
        Foo(List<Expression> v) : values(move(v)) { }

        void emit(CodeWriter & code, Scope & scope) override {
            assert(values.size() < 65536);

            for(auto it = values.rbegin(); it != values.rend(); it++)
                (*it)->emit(code, scope);

            code.emit(Instruction::array_pack);
            code.emit(uint16_t(values.size()));
        }
    };
    return std::make_unique<Foo>(move(initializer));
}

Expression LoLa::AST::FunctionCall(String name, List<Expression> args)
{
    struct Foo : ExpressionBase {
        String function;
        List<Expression> args;
        Foo(String f, List<Expression> a) : function(f), args(move(a)) { }

        void emit(CodeWriter & code, Scope & scope) override {

            assert(args.size() < 256);

            for(auto it = args.rbegin(); it != args.rend(); it++)
                (*it)->emit(code, scope);

            code.emit(Instruction::call_fn);
            code.emit(function);
            code.emit(uint8_t(args.size()));
        }
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

        void emit(CodeWriter & code, Scope & scope) override {

            assert(args.size() < 256);

            for(auto it = args.rbegin(); it != args.rend(); it++)
                (*it)->emit(code, scope);

            object->emit(code, scope);

            code.emit(Instruction::call_obj);
            code.emit(function);
            code.emit(uint8_t(args.size()));
        }
    };
    return std::make_unique<Foo>(move(object), name, move(args));
}

Expression LoLa::AST::UnaryOperator(Operator op, Expression value)
{
    struct Foo : ExpressionBase {
        Operator op;
        Expression value;
        Foo(Operator o, Expression v) : op(o), value(move(v)) { }

        void emit(CodeWriter & code, Scope & scope) override {
            value->emit(code, scope);
            switch(op) {
            case Operator::Minus:
                code.emit(Instruction::negate);
                break;
            case Operator::Not:
                code.emit(Instruction::bool_not);
                break;
            default:
                throw "invalid operator!";
            }
        }
    };
    return std::make_unique<Foo>(op, move(value));
}
Expression LoLa::AST::BinaryOperator(Operator op, Expression lhs, Expression rhs)
{
    struct Foo : ExpressionBase {
        Operator op;
        Expression lhs, rhs;
        Foo(Operator o, Expression l, Expression r) : op(o), lhs(move(l)), rhs(move(r)) { }

        void emit(CodeWriter & code, Scope & scope) override {
            lhs->emit(code, scope);
            rhs->emit(code, scope);
            switch(op) {
            case Operator::Plus:  code.emit(Instruction::add); break;
            case Operator::Minus: code.emit(Instruction::sub); break;
            case Operator::Multiply: code.emit(Instruction::mul); break;
            case Operator::Divide: code.emit(Instruction::div); break;
            case Operator::Modulus: code.emit(Instruction::mod); break;
            case Operator::Less: code.emit(Instruction::less); break;
            case Operator::LessOrEqual: code.emit(Instruction::less_eq); break;
            case Operator::More: code.emit(Instruction::greater); break;
            case Operator::MoreOrEqual: code.emit(Instruction::greater_eq); break;
            case Operator::Equals: code.emit(Instruction::eq); break;
            case Operator::Differs:   code.emit(Instruction::neq); break;
            case Operator::And:   code.emit(Instruction::bool_and); break;
            case Operator::Or:   code.emit(Instruction::bool_or); break;
            default:
                throw "invalid operator!";
            }
        }
    };
    return std::make_unique<Foo>(op, move(lhs), move(rhs));
}

Statement LoLa::AST::Assignment(LValueExpression target, Expression value)
{
    struct Foo : StatementBase {
        LValueExpression lhs;
        Expression rhs;
        Foo(LValueExpression l, Expression r) : lhs(move(l)), rhs(move(r)) { }

        void emit(CodeWriter & code, Scope & scope) override {
            rhs->emit(code, scope);
            lhs->emitStore(code, scope);
        }
    };
    return std::make_unique<Foo>(move(target), move(value));
}

Statement LoLa::AST::Return()
{
    struct Foo : StatementBase {
        Foo() { }

        void emit(CodeWriter & code, Scope & scope) override {
            code.emit(Instruction::ret);
        }
    };
    return std::make_unique<Foo>();
}
Statement LoLa::AST::Return(Expression value)
{
    struct Foo : StatementBase {
        Expression value;
        Foo(Expression v) :value(move(v)) { }

        void emit(CodeWriter & code, Scope & scope) override {
            value->emit(code, scope);
            code.emit(Instruction::retval);
        }
    };
    return std::make_unique<Foo>(move(value));
}
Statement LoLa::AST::WhileLoop(Expression condition, Statement body)
{
    struct Foo : StatementBase {
        Expression cond;
        Statement body;
        Foo(Expression cond, Statement body) : cond(move(cond)), body(move(body)) { }

        void emit(CodeWriter & code, Scope & scope) override {

            auto const loop_start = code.createAndDefineLabel();
            auto const loop_end = code.createLabel();

            cond->emit(code, scope);
            code.emit(Instruction::jif);
            code.emit(loop_end);

            body->emit(code, scope);

            code.emit(Instruction::jmp);
            code.emit(loop_start);

            code.defineLabel(loop_end);
        }
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

        void emit(CodeWriter & code, Scope &) override {
            assert(false and "not implemented yet");
        }
    };
    return std::make_unique<Foo>(var, move(source), move(body));
}
Statement LoLa::AST::IfElse(Expression condition, Statement true_body)
{
    struct Foo : StatementBase {
        Expression cond;
        Statement body;
        Foo(Expression cond, Statement body) : cond(move(cond)), body(move(body)) { }

        void emit(CodeWriter & code, Scope & scope) override {
            cond->emit(code, scope);

            auto lbl = code.createLabel();
            code.emit(Instruction::jif);
            code.emit(lbl);

            body->emit(code, scope);

            code.defineLabel(lbl);
        }
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

        void emit(CodeWriter & code, Scope & scope) override {
            cond->emit(code, scope);

            auto lbl_false = code.createLabel();
            auto lbl_end = code.createLabel();
            code.emit(Instruction::jif);
            code.emit(lbl_false);

            true_body->emit(code, scope);

            code.emit(Instruction::jmp);
            code.emit(lbl_end);

            code.defineLabel(lbl_false);
            false_body->emit(code, scope);

            code.defineLabel(lbl_end);
        }
    };
    return std::make_unique<Foo>(move(condition), move(true_body), move(false_body));
}

Statement LoLa::AST::DiscardResult(Expression value)
{
    struct Foo : StatementBase {
        Expression value;
        Foo(Expression v) :value(move(v)) { }

        void emit(CodeWriter & code, Scope & scope) override {
            value->emit(code, scope);
            code.emit(Instruction::pop);
        }
    };
    return std::make_unique<Foo>(move(value));
}

Statement LoLa::AST::Declaration(String name)
{
    struct Foo : StatementBase {
        String name;
        Foo(String name) :name(move(name)){ }

        void emit(CodeWriter &, Scope & scope) override {
            scope.declare(name);
        }
    };
    return std::make_unique<Foo>(name);
}

Statement LoLa::AST::Declaration(String name, Expression value)
{
    struct Foo : StatementBase {
        String name;
        Expression value;
        Foo(String name, Expression v) :name(move(name)), value(move(v)) { }

        void emit(CodeWriter & code, Scope & scope) override {
            scope.declare(name);
            value->emit(code, scope);

            auto const pos = scope.get(name);
            assert(pos != std::nullopt);

            if(scope.is_global)
                code.emit(Instruction::store_global_idx);
            else
                code.emit(Instruction::store_local);
            code.emit(uint16_t(*pos));
        }
    };
    return std::make_unique<Foo>(name, move(value));
}

Statement LoLa::AST::SubScope(List<Statement> body)
{
    struct Foo : StatementBase {
        List<Statement> content;
        Foo(List<Statement> v) : content(move(v)) { }

        void emit(CodeWriter & code, Scope & scope) override {
            scope.enter();
            for(auto const & stmt : content)
                stmt->emit(code, scope);
            scope.leave();

        }
    };
    return std::make_unique<Foo>(move(body));
}
