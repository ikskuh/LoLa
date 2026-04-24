#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

typedef uint8_t u8;
typedef uint32_t u32;
typedef uint64_t u64;
typedef int32_t i32;
typedef double f64;
typedef size_t usize;

typedef struct lola_CompileUnit lola_CompileUnit;
typedef struct lola_Diagnostics lola_Diagnostics;
typedef struct lola_ObjectPool lola_ObjectPool;
typedef struct lola_Environment lola_Environment;
typedef struct lola_VM lola_VM;
typedef struct lola_Value lola_Value;

enum lola_TypeID: u8 {
    lola_type_void,
    lola_type_number,
    lola_type_object,
    lola_type_boolean,
    lola_type_string,
    lola_type_array,
    lola_type_enumerator,
};

typedef struct {
    const char* items;
    usize len;
} lola_Str;

typedef struct {
    lola_Value* elements;
    usize len;
} lola_value_Array;

typedef struct {
    lola_value_Array array;
    usize index;
} lola_value_Enumerator;
typedef u64 lola_ObjectHandle;
typedef struct {
    enum lola_TypeID type;
    union {
        f64 number;
        lola_ObjectHandle object;
        bool boolean;
        lola_Str string;
        lola_value_Array array;
        lola_value_Enumerator enumerator;
    };
} lola_CValue;

// typedef struct {
//     const char **messages;
//     size_t count;
// } lola_Diagnostics;

// enum lola_MessageKind:u8 {
//     error=0,
//     warning,
//     notice,
// };

enum lola_ExecutionResult: u8 {
    /// The vm instruction quota was exhausted and the execution was terminated.
    lola_ExecutionResult_exhausted,

    /// The vm has encountered an asynchronous function call and waits for the completion.
    lola_ExecutionResult_paused,

    /// The vm has completed execution of the program and has no more instructions to
    /// process.
    lola_ExecutionResult_completed,
};

typedef struct {
    /// Prefix each line of the disassembly with the hexadecimal address.
    bool addressPrefix;

    /// If set, a hexdump with both hex- and ascii display will be emitted.
    /// Each line of text will contain `hexwidth` number of bytes.
    usize hexwidth;

    /// If set to `true`, the output will contain a line with the
    /// name of function that starts at this offset. This option
    /// is set by default.
    bool labelOutput;

    /// If set to `true`, the disassembled instruction will be emitted.
    /// This is set by default.
    bool instructionOutput;
} lola_DisassemblerOptions;

// function/callback

enum lola_CallbackType: u8 {
    lola_CallbackType_sync,
    lola_CallbackType_async,
};

typedef void(*lola_DestructructorFunc)(void* user_data);

typedef struct {
    // Optional
    void* user_data;
    /// return false on error, or true on success
    bool (*execute)(void* user_data, lola_Value* return_value, bool* is_return_value_set);
    // Optional
    lola_DestructructorFunc destructor;
} lola_AsyncFunctionCall;

typedef struct {
    enum lola_CallbackType type;
    union {
        bool(*sync)(lola_Environment* environment, void* user_data, const lola_Value* args, usize arg_len, lola_Value* return_value);
        bool(*async)(lola_Environment* environment, void* user_data, const lola_Value* args, usize arg_len, lola_AsyncFunctionCall* return_value);

    };
} lola_FuncType;


typedef struct {
    // Optoinal
    void* user_data;
    lola_FuncType c_func;
    // Optional
    lola_DestructructorFunc destructer;
} lola_CallbackData;

// Object

typedef struct {
    bool (*getMethod)(void* user_data, lola_Str name, lola_FuncType* func);
    // optional
    lola_DestructructorFunc destructer;
} lola_Object_VTable;

typedef struct {
    void* user_data;
    lola_Object_VTable vtable;
} lola_Object;

// functions

bool lola_dis_toBuffer(char* buf, usize buf_len, const lola_CompileUnit* cu, lola_DisassemblerOptions options);
typedef struct {lola_Str data;} lola_dis_Alloc;
bool lola_dis_alloc(const lola_CompileUnit* cu, lola_DisassemblerOptions options, lola_dis_Alloc* dis);
//returns null terminated string
bool lola_dis_allocZ(const lola_CompileUnit* cu, lola_DisassemblerOptions options, lola_dis_Alloc* dis);
void lola_dis_deinit(lola_dis_Alloc dis);

lola_Object* lola_Object_init(void* user_data, lola_Object_VTable vtable);

const char* lola_getErrorName(void);
bool lola_hasError(void);

// alloc
void lola_alloc_deinit(void);
void* lola_alloc_alloc(usize size, usize alignment);
void lola_alloc_free(void* ptr, usize size, usize alignment);
bool lola_alloc_reisze(void** ptr, usize old_size,usize new_size, usize alignment);

bool lola_CArray_init(lola_value_Array* array, usize size);
void lola_CValue_toValue(lola_CValue cvalue, lola_Value* to_value);
// performs a shallow copy of value
lola_CValue lola_CValue_fromValue(const lola_Value* value);

// value is an in param
bool lola_Value_initObject(lola_Environment* environment, lola_Object* object, lola_Value* value);
bool lola_Value_initString(lola_Str str, lola_Value* value);
void lola_Value_initBoolean(bool boolean, lola_Value* value);
void lola_Value_initNumber(f64 number, lola_Value* value);
// returns a shallow copy of value
lola_Value* lola_Value_clone(const lola_Value* value);
usize lola_Value_sizeof(void);
void lola_Value_deinit(lola_Value* value);

const lola_Value* lola_indexArgs(const lola_Value* args, usize arg_len, usize index);

lola_Str lola_Str_fromC(const char* str);


bool lola_Diagnostics_display(lola_Diagnostics* diag);
bool lola_Diagnostics_hasErrors(lola_Diagnostics* diag);
void lola_Diagnostics_deinit(lola_Diagnostics* diag);

lola_CompileUnit* lola_loadCUFromMem(u8* mem, usize len);
lola_CompileUnit* lola_compile(lola_Diagnostics** diag, lola_Str chunk_name, lola_Str source_code);
void lola_CompileUnit_deinit(lola_CompileUnit* cu);

lola_ObjectPool* lola_ObjectPool_init(void);
void lola_ObjectPool_deinit(lola_ObjectPool* object_pool);

lola_Environment* lola_Environment_init(lola_CompileUnit* compile_unit, lola_ObjectPool* object_pool);
bool lola_Environment_install(lola_Environment* environment, lola_Str name, lola_CallbackData func_data);
bool lola_Environment_installStd(lola_Environment* environment);
bool lola_Environment_installRuntime(lola_Environment* environment);
void lola_Environment_deinit(lola_Environment* environment);

lola_VM* lola_VM_init(lola_Environment* environment);
bool lola_VM_execute(lola_VM* vm, u32 quota, enum lola_ExecutionResult* result);
void lola_VM_deinit(lola_VM* vm);
