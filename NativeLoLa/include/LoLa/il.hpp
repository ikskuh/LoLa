#ifndef IL_HPP
#define IL_HPP

#include <cstdint>

namespace LoLa::IL
{
    //! Instruction of the LoLa virtual machine.
    //! Instructions may be followed by some parameters
    //! required by the instruction.
    //! The following types exist:
    //! u8  (unsigned  8 bit integer)
    //! u16 (unsigned 16 bit integer, little endian)
    //! u32 (unsigned 32 bit integer, little endian)
    //! f64 (ieee 64 bit double, binary64)
    //! str (u16 defining the string length, followed by *length* tims u8, marking the string content)
    enum class Instruction : uint8_t
    {
        nop = 0,                //!< No operation
        // scope_push = 1,
        // scope_pop = 2,
        // declare = 3,         //!< [ var:str ]
        store_global_name = 4,  //!< stores global variable by name [ var:str ]
        load_global_name = 5,   //!< loads global variable by name [ var:str ]
        push_str = 6,           //!< pushes string literal  [ val:str ]
        push_num = 7,           //!< pushes number literal  [ val:f64 ]
        array_pack = 8,         //!< packs *num* elements into an array [ num:u16 ]
        call_fn = 9,            //!< calls a function [ fun:str ] [argc:u8 ]
        call_obj = 10,          //!< calls an object method [ fun:str ] [argc:u8 ]
        pop = 11,               //!< destroys stack top
        add = 12,               //!< adds rhs and lhs together
        sub = 13,               //!< subtracts rhs and lhs together
        mul = 14,               //!< multiplies rhs and lhs together
        div = 15,               //!< divides rhs and lhs together
        mod = 16,               //!< reminder division of rhs and lhs
        bool_and = 17,          //!< conjunct rhs and lhs
        bool_or = 18,           //!< disjuncts rhs and lhs
        bool_not = 19,          //!< logically inverts stack top
        negate = 20,            //!< arithmetically inverts stack top
        eq = 21,
        neq = 22,
        less_eq = 23,
        greater_eq = 24,
        less = 25,
        greater = 26,
        jmp = 27,               //!< jumps unconditionally [ target:u32 ]
        jnf = 28,               //!< jump when not false [ target:u32 ]
        iter_make = 29,
        iter_next = 30,
        array_store = 31,
        array_load = 32,
        ret = 33,               //!< returns from the current function with Void
        store_local = 34,       //!< [ index : u16 ]
        load_local = 35,        //!< [ index : u16 ]
        retval = 37,            //!< returns from the current function with a value
        jif = 38,               //!< jump when false[ target:u32 ]
        store_global_idx = 39,  //!< stores global variable by index [ idx:u16 ]
        load_global_idx = 40,   //!< loads global variable by index [ idx:u16 ]
        push_true = 41, //!< pushes `true` literal
        push_false = 42, //!< pushes `false` literal
        push_void = 43, //!< pushes `void` literal
    };
}

#endif // IL_HPP
