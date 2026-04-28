#include <stdint.h>
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

typedef struct lola_CompileUnit lola_CompileUnit;
typedef struct lola_Diagnostics lola_Diagnostics;
typedef struct lola_ObjectPool lola_ObjectPool;
typedef struct lola_Environment lola_Environment;
typedef struct lola_VM lola_VM;
typedef struct lola_Value lola_Value;

enum lola_TypeID {
    lola_type_void = 0,
    lola_type_number = 1,
    lola_type_object = 2,
    lola_type_boolean = 3,
    lola_type_string = 4,
    lola_type_array = 5,
    lola_type_enumerator = 6,
};

typedef struct {
    const char* items;
    size_t len;
} lola_Str;

typedef struct {
    lola_Value* elements;
    size_t len;
} lola_value_Array;

typedef struct {
    lola_value_Array array;
    size_t index;
} lola_value_Enumerator;
typedef uint64_t lola_ObjectHandle;
typedef struct {
    uint8_t type_id;
    union {
        double number;
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

// enum lola_MessageKind:uint8_t {
//     error=0,
//     warning,
//     notice,
// };

enum lola_ExecutionResult {
    /// The vm instruction quota was exhausted and the execution was terminated.
    lola_ExecutionResult_exhausted = 0,

    /// The vm has encountered an asynchronous function call and waits for the completion.
    lola_ExecutionResult_paused = 1,

    /// The vm has completed execution of the program and has no more instructions to
    /// process.
    lola_ExecutionResult_completed = 2,
};

typedef struct {
    /// Prefix each line of the disassembly with the hexadecimal address.
    bool addressPrefix;

    /// If set, a hexdump with both hex- and ascii display will be emitted.
    /// Each line of text will contain `hexwidth` number of bytes.
    size_t hexwidth;

    /// If set to `true`, the output will contain a line with the
    /// name of function that starts at this offset. This option
    /// is set by default.
    bool labelOutput;

    /// If set to `true`, the disassembled instruction will be emitted.
    /// This is set by default.
    bool instructionOutput;
} lola_DisassemblerOptions;

// function/callback

enum lola_CallbackType {
    lola_CallbackType_sync = 0,
    lola_CallbackType_async = 1,
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
    uint8_t callback_type;
    union {
        bool(*sync)(lola_Environment* environment, void* user_data, const lola_Value* args, size_t arg_len, lola_Value* return_value);
        bool(*async)(lola_Environment* environment, void* user_data, const lola_Value* args, size_t arg_len, lola_AsyncFunctionCall* return_value);

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

bool lola_dis_toBuffer(char* buf, size_t buf_len, const lola_CompileUnit* cu, lola_DisassemblerOptions options);
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
void* lola_alloc_alloc(size_t size, size_t alignment);
void lola_alloc_free(void* ptr, size_t size, size_t alignment);
bool lola_alloc_reisze(void** ptr, size_t old_size,size_t new_size, size_t alignment);

bool lola_CArray_init(lola_value_Array* array, size_t size);
void lola_CValue_toValue(lola_CValue cvalue, lola_Value* to_value);
// performs a shallow copy of value
lola_CValue lola_CValue_fromValue(const lola_Value* value);

// value is an in param
bool lola_Value_initObject(lola_Environment* environment, lola_Object* object, lola_Value* value);
bool lola_Value_initString(lola_Str str, lola_Value* value);
void lola_Value_initBoolean(bool boolean, lola_Value* value);
void lola_Value_initNumber(double number, lola_Value* value);
// returns a shallow copy of value
lola_Value* lola_Value_clone(const lola_Value* value);
size_t lola_Value_sizeof(void);
void lola_Value_deinit(lola_Value* value);

const lola_Value* lola_indexArgs(const lola_Value* args, size_t arg_len, size_t index);

lola_Str lola_Str_fromC(const char* str);


bool lola_Diagnostics_display(lola_Diagnostics* diag);
bool lola_Diagnostics_hasErrors(lola_Diagnostics* diag);
void lola_Diagnostics_deinit(lola_Diagnostics* diag);

lola_CompileUnit* lola_loadCUFromMem(uint8_t* mem, size_t len);
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
bool lola_VM_execute(lola_VM* vm, uint32_t quota, uint8_t* execution_result);
void lola_VM_deinit(lola_VM* vm);
