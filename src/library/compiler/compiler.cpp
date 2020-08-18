#include "compiler.hpp"
#include <cassert>
#include <cstring>
#include <iostream>
#include <iomanip>

std::shared_ptr<LoLa::Compiler::CompilationUnit> LoLa::Compiler::Compiler::compile(const LoLa::AST::Program &program)
{
    auto cu = std::make_shared<CompilationUnit>();

    CodeWriter writer(cu.get());

    Scope global_scope;
    global_scope.is_global = true;
    for (auto const &stmt : program.statements)
        stmt->emit(writer, global_scope, this->errors);
    writer.emit(IL::Instruction::ret); // implicit return at the end of the block

    assert(global_scope.return_point.size() == 1);

    cu->global_count = global_scope.global_variables.size();
    cu->temporary_count = global_scope.max_locals;

    for (auto const &fn : program.functions)
    {
        auto const ep = cu->code.size();

        auto [fun, created] = cu->functions.emplace(fn.name, std::make_unique<ScriptFunction>(cu));
        fun->second->entry_point = ep;

        Scope scope;
        scope.is_global = false;
        scope.global_scope = &global_scope;

        for (auto const &param : fn.params)
            scope.declare(param);

        fn.body->emit(writer, scope, errors);
        writer.emit(IL::Instruction::ret); // implicit return at the end of the function

        fun->second->local_count = scope.max_locals;
    }

    return cu;
}

LoLa::Compiler::CodeWriter::CodeWriter(LoLa::Compiler::CompilationUnit *target) : next_label{1},
                                                                                  labels(),
                                                                                  target(target),
                                                                                  patches()
{
}

LoLa::Compiler::Label LoLa::Compiler::CodeWriter::createLabel()
{
    auto const lbl = next_label;
    next_label.value += 1;
    return lbl;
}

LoLa::Compiler::Label LoLa::Compiler::CodeWriter::createAndDefineLabel()
{
    auto lbl = createLabel();
    defineLabel(lbl);
    return lbl;
}

void LoLa::Compiler::CodeWriter::defineLabel(LoLa::Compiler::Label lbl)
{
    if (auto it = labels.find(lbl); it != labels.end())
        throw LoLa::Error::LabelAlreadyDefined;

    uint32_t const position = target->code.size();

    labels.emplace(lbl, position);

    // resolve all forward references to this label
    for (auto it = patches.begin(); it != patches.end();)
    {
        if (it->first == lbl)
        {
            assert(position >= it->second + sizeof(position));
            memcpy(&target->code[it->second], &position, sizeof(position));
            it = patches.erase(it);
        }
        else
        {
            it++;
        }
    }
}

//! Pushes a new loop construct.
void LoLa::Compiler::CodeWriter::pushLoop(Label breakLabel, Label continueLabel)
{
    this->loops.push_back({breakLabel, continueLabel});
}

//! Removes a loop construct from the loop stack.
void LoLa::Compiler::CodeWriter::popLoop()
{
    assert(this->loops.size() > 0);
    this->loops.pop_back();
}

void LoLa::Compiler::CodeWriter::emitBreak(ErrorCollection &errors)
{
    if (this->loops.size() == 0)
    {
        errors.notInLoop();
    }
    else
    {
        emit(IL::Instruction::jmp);
        emit(this->loops.back().first);
    }
}

void LoLa::Compiler::CodeWriter::emitContinue(ErrorCollection &errors)
{
    if (this->loops.size() == 0)
    {
        errors.notInLoop();
    }
    else
    {
        emit(IL::Instruction::jmp);
        emit(this->loops.back().second);
    }
}

void LoLa::Compiler::CodeWriter::emit(LoLa::Compiler::Label label)
{
    if (auto it = labels.find(label); it != labels.end())
    {
        emit(it->second);
    }
    else
    {
        patches.emplace_back(label, target->code.size());
        emit(~0U);
    }
}

void LoLa::Compiler::CodeWriter::emit(const void *data, size_t len)
{
    size_t offset = target->code.size();
    target->code.resize(offset + len);
    memcpy(&target->code[offset], data, len);
}

void LoLa::Compiler::CodeWriter::emit(IL::Instruction val)
{
    emit(&val, sizeof val);
}
void LoLa::Compiler::CodeWriter::emit(double val)
{
    emit(&val, sizeof val);
}
void LoLa::Compiler::CodeWriter::emit(std::string val)
{
    assert(val.size() < 65536);
    emit(uint16_t(val.size()));
    emit(val.data(), val.size());
}
void LoLa::Compiler::CodeWriter::emit(uint8_t val)
{
    emit(&val, sizeof val);
}
void LoLa::Compiler::CodeWriter::emit(uint16_t val)
{
    emit(&val, sizeof val);
}
void LoLa::Compiler::CodeWriter::emit(uint32_t val)
{
    emit(&val, sizeof val);
}

LoLa::Compiler::Scope::Scope()
{
    enter();
}

LoLa::Compiler::Scope::~Scope()
{
    leave();
#ifdef DEBUG
    if (return_point.size() != 0)
    {
        fprintf(stderr, "error: not all scopes were popped properly!\n");
    }
    if (local_variables.size() != 0)
    {
        fprintf(stderr, "error: not all local variables were cleaned up properly!\n");
    }
#endif
}

void LoLa::Compiler::Scope::enter()
{
    return_point.emplace_back(local_variables.size());
}

void LoLa::Compiler::Scope::leave()
{
    assert(not return_point.empty());
    local_variables.resize(return_point.back());
    return_point.pop_back();
}

void LoLa::Compiler::Scope::declare(const std::string &name)
{
    // TODO: Test here for shadowing

    if (is_global and (return_point.size() == 1))
    {
        global_variables.emplace_back(name);
        assert(local_variables.size() < 65536);
        return;
    }
    else
    {
        local_variables.emplace_back(name);
        assert(local_variables.size() < 65536);
        max_locals = std::max<uint16_t>(max_locals, local_variables.size());
    }
}

void LoLa::Compiler::Scope::declareExtern(const std::string &name)
{
    // TODO: Test here for shadowing
    extern_variables.emplace_back(name);
}

std::optional<std::pair<uint16_t, LoLa::Compiler::Scope::Type>> LoLa::Compiler::Scope::get(std::string const &name) const
{
    {
        size_t i = local_variables.size();
        while (i > 0)
        {
            i -= 1;
            if (local_variables[i] == name)
                return std::make_pair(uint16_t(i), Local);
        }
    }

    if (is_global)
    {
        size_t i = global_variables.size();
        while (i > 0)
        {
            i -= 1;
            if (global_variables[i] == name)
            {
                return std::make_pair(uint16_t(i), Global);
            }
        }
    }

    for (auto const &extvar : extern_variables)
    {
        if (extvar == name)
        {
            return std::make_pair(uint16_t(-1), Extern);
        }
    }

    if (global_scope != nullptr)
    {
        auto glob = global_scope->get(name);
        assert(not glob or glob->second != Local);
        return glob;
    }
    else
    {
        return std::nullopt;
    }
}

void LoLa::Compiler::CodeReader::fetch_buffer(void *target, size_t len)
{
    if (offset + len > code->code.size())
        throw Error::InvalidPointer;
    memcpy(target, &code->code[offset], len);
    offset += len;
}

LoLa::IL::Instruction LoLa::Compiler::CodeReader::fetch_instruction()
{
    LoLa::IL::Instruction i;
    fetch_buffer(&i, sizeof i);
    return i;
}

std::string LoLa::Compiler::CodeReader::fetch_string()
{
    auto const len = fetch_u16();

    std::string value(len, '?');
    fetch_buffer(value.data(), len);
    return value;
}

double LoLa::Compiler::CodeReader::fetch_number()
{
    double i;
    fetch_buffer(&i, sizeof i);
    return i;
}

uint8_t LoLa::Compiler::CodeReader::fetch_u8()
{
    uint8_t i;
    fetch_buffer(&i, sizeof i);
    return i;
}

uint16_t LoLa::Compiler::CodeReader::fetch_u16()
{
    uint16_t i;
    fetch_buffer(&i, sizeof i);
    return i;
}

uint32_t LoLa::Compiler::CodeReader::fetch_u32()
{
    uint32_t i;
    fetch_buffer(&i, sizeof i);
    return i;
}

LoLa::Compiler::ScriptFunction::ScriptFunction(std::weak_ptr<const CompilationUnit> code) : code(code)
{
}

void LoLa::Compiler::CompilationUnit::save(std::ostream &stream)
{
    uint32_t version = 1;
    std::array<char, 256> comment{"Created with NativeLola.cpp"};

    stream.write("LoLa\xB9\x40\x80\x5A", 8);
    stream.write(reinterpret_cast<char const *>(&version), 4);
    stream.write(comment.data(), comment.size());

    uint16_t globalCount = this->global_count;
    stream.write(reinterpret_cast<char const *>(&globalCount), 2);

    uint16_t temporaryCount = this->temporary_count;
    stream.write(reinterpret_cast<char const *>(&temporaryCount), 2);

    uint16_t functionCount = static_cast<uint16_t>(this->functions.size());
    stream.write(reinterpret_cast<char const *>(&functionCount), 2);

    uint32_t codeSize = static_cast<uint32_t>(this->code.size());
    stream.write(reinterpret_cast<char const *>(&codeSize), 4);

    uint32_t numDebugSymbols = static_cast<uint32_t>(0);
    stream.write(reinterpret_cast<char const *>(&numDebugSymbols), 4);

    for (auto const &fnpair : this->functions)
    {
        std::array<char, 128> name;
        strncpy(name.data(), fnpair.first.c_str(), name.size());
        stream.write(name.data(), name.size());

        uint32_t ep = fnpair.second->entry_point;
        stream.write(reinterpret_cast<char const *>(&ep), 4);

        uint16_t localCount = fnpair.second->local_count;
        stream.write(reinterpret_cast<char const *>(&localCount), 2);
    }

    stream.write(reinterpret_cast<char const *>(this->code.data()), this->code.size());
}

void LoLa::Compiler::ErrorCollection::add(CompileError &&error)
{
    this->errors.emplace_back(std::move(error));
}

void LoLa::Compiler::ErrorCollection::invalidStore(std::string const &str)
{
    add(CompileError{
        "<not implemented yet>",
        1,
        1,
        "Changing the value of predefined symbol " + str + " is not allowed.",
        false,
    });
}

void LoLa::Compiler::ErrorCollection::invalidVariable(std::string const &str)
{
    add(CompileError{
        "<not implemented yet>",
        1,
        1,
        "The variable name " + str + " is not valid.",
        false,
    });
}

void LoLa::Compiler::ErrorCollection::variableNotFound(std::string const &str)
{
    add(CompileError{
        "<not implemented yet>",
        1,
        1,
        "The variable " + str + " does not exist.",
        false,
    });
}

void LoLa::Compiler::ErrorCollection::invalidString(std::string const &str)
{
    add(CompileError{
        "<not implemented yet>",
        1,
        1,
        "The string \"" + str + "\" contains invalid escape sequences.",
        false,
    });
}

static char const *op_to_string(LoLa::AST::Operator op)
{
    using namespace LoLa;
    switch (op)
    {
    case AST::Operator::LessOrEqual:
        return "<=";
    case AST::Operator::MoreOrEqual:
        return ">=";
    case AST::Operator::Equals:
        return "==";
    case AST::Operator::Differs:
        return "!=";
    case AST::Operator::Less:
        return "<";
    case AST::Operator::More:
        return ">";

    case AST::Operator::Plus:
        return "+";
    case AST::Operator::Minus:
        return "-";
    case AST::Operator::Multiply:
        return "*";
    case AST::Operator::Divide:
        return "/";
    case AST::Operator::Modulus:
        return "%";

    case AST::Operator::And:
        return "and";
    case AST::Operator::Or:
        return "or";
    case AST::Operator::Not:
        return "not";
    }
    return "<invalid>";
}

void LoLa::Compiler::ErrorCollection::invalidOperator(AST::Operator op)
{
    add(CompileError{
        "<not implemented yet>",
        1,
        1,
        "The operator " + std::string(op_to_string(op)) + " is not valid at this point.",
        false,
    });
}

void LoLa::Compiler::ErrorCollection::notInLoop()
{
    add(CompileError{
        "<not implemented yet>",
        1,
        1,
        "Use of break/continue outside of a loop structure.",
        false,
    });
}