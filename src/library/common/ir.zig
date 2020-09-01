/// This enumeration contains all possible instructions and assigns each a value.
pub const InstructionName = enum(u8) {
    nop = 0,
    scope_push = 1, // deprecated
    scope_pop = 2, // deprecated
    declare = 3, // deprecated
    store_global_name = 4,
    load_global_name = 5,
    push_str = 6,
    push_num = 7,
    array_pack = 8,
    call_fn = 9,
    call_obj = 10,
    pop = 11,
    add = 12,
    sub = 13,
    mul = 14,
    div = 15,
    mod = 16,
    bool_and = 17,
    bool_or = 18,
    bool_not = 19,
    negate = 20,
    eq = 21,
    neq = 22,
    less_eq = 23,
    greater_eq = 24,
    less = 25,
    greater = 26,
    jmp = 27,
    jnf = 28,
    iter_make = 29,
    iter_next = 30,
    array_store = 31,
    array_load = 32,
    ret = 33,
    store_local = 34,
    load_local = 35,
    // HERE BE HOLE
    retval = 37,
    jif = 38,
    store_global_idx = 39,
    load_global_idx = 40,
    push_true = 41,
    push_false = 42,
    push_void = 43,
};

/// This union contains each possible instruction with its (optional) arguments already encoded.
/// Each instruction type is either `NoArg`, `SingleArg`, `CallArg` or `Deprecated`, defining how
/// each instruction is encoded.
/// This information can be used to encode/decode the instructions based on their meta-information.
pub const Instruction = union(InstructionName) {
    pub const Deprecated = struct {};
    pub const NoArg = struct {};
    
    fn SingleArg(comptime T: type) type {
        return struct { value: T };
    }

    pub const CallArg = struct {
        function: []const u8,
        argc: u8,
    };

    nop: NoArg,
    scope_push: Deprecated,
    scope_pop: Deprecated,
    declare: Deprecated,
    store_global_name: SingleArg([]const u8),
    load_global_name: SingleArg([]const u8),
    push_str: SingleArg([]const u8),
    push_num: SingleArg(f64),
    array_pack: SingleArg(u16),
    call_fn: CallArg,
    call_obj: CallArg,
    pop: NoArg,
    add: NoArg,
    sub: NoArg,
    mul: NoArg,
    div: NoArg,
    mod: NoArg,
    bool_and: NoArg,
    bool_or: NoArg,
    bool_not: NoArg,
    negate: NoArg,
    eq: NoArg,
    neq: NoArg,
    less_eq: NoArg,
    greater_eq: NoArg,
    less: NoArg,
    greater: NoArg,
    jmp: SingleArg(u32),
    jnf: SingleArg(u32),
    iter_make: NoArg,
    iter_next: NoArg,
    array_store: NoArg,
    array_load: NoArg,
    ret: NoArg,
    store_local: SingleArg(u16),
    load_local: SingleArg(u16),
    retval: NoArg,
    jif: SingleArg(u32),
    store_global_idx: SingleArg(u16),
    load_global_idx: SingleArg(u16),
    push_true: NoArg,
    push_false: NoArg,
    push_void: NoArg,
};
