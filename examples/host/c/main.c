#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include "lola.h"

const char* PROGRAM = \
"Print(\"Hello World\");\
Print(\"UserAsync returned: \",UserAsync());\
Print(\"3+2=\",addsub(false,3,2));\
Print(\"3-2=\",addsub(true,3,2));\
";
#define INVALID_ARGS "Invalid Args!"
const char* error = NULL;

lola_ObjectPool* pool=NULL;
lola_Environment* env=NULL;
lola_CompileUnit* cu=NULL;
lola_VM* vm=NULL;

void deinit(void) {
    if (lola_hasError())
        printf("LoLa error: %s\n", lola_getErrorName());
    if (error)
        printf("error: %s\n",error);
    lola_VM_deinit(vm);
    lola_Environment_deinit(env);
    lola_ObjectPool_deinit(pool);
    lola_alloc_deinit();
}
bool addsubCB(lola_Environment* env, void* user_data, const lola_Value* args, size_t arg_len, lola_Value* return_value) {
    if (arg_len!=3) {error=INVALID_ARGS;return false;}
    lola_CValue cargs[3];
    for (int i=0; i<3; i++) {
        cargs[i]=lola_CValue_fromValue(lola_indexArgs(args, arg_len, i));
    }

    if (cargs[0].type_id!=lola_type_boolean) {
        error=INVALID_ARGS;
        return false;
    }
    if (cargs[1].type_id!=lola_type_number) {
        error=INVALID_ARGS;
        return false;
    }
    if (cargs[2].type_id!=lola_type_number) {
        error=INVALID_ARGS;
        return false;
    }
    if (cargs[0].boolean) {
        lola_Value_initNumber(cargs[1].number - cargs[2].number, return_value);
        return true;
    } else {
        lola_Value_initNumber(cargs[1].number + cargs[2].number, return_value);
        return true;
    }
}


bool UserAsyncExecute(void* user_data, lola_Value* return_value, bool* is_return_value_set) {
    static int counter = 0;
    printf("counter: %d\n",counter);
    if (counter>3) {
        lola_Value_initNumber((double)counter, return_value);
        *is_return_value_set = true;
        return true;
    } else {
        counter++;
        return true;
    }
}

bool UserAsyncCB(lola_Environment* env, void* user_data, const lola_Value* args, size_t arg_len, lola_AsyncFunctionCall* return_value) {
    return_value->user_data=NULL;
    return_value->destructor=NULL;
    return_value->execute = UserAsyncExecute;
    return true;
}

int main(void) {
    pool = lola_ObjectPool_init();
    if (!pool) {
        fprintf(stderr, "Failed to init pool\n");
        deinit();
        return EXIT_FAILURE;
    }

    lola_Diagnostics* diag=NULL;
    cu = lola_compile(&diag, lola_Str_fromC("hello_world.lola"), lola_Str_fromC(PROGRAM));
    if (!cu) {
        fprintf(stderr, "Failed to compile\n");
        lola_Diagnostics_display(diag);
        lola_Diagnostics_deinit(diag);
        deinit();
        return EXIT_FAILURE;
    } else if (lola_Diagnostics_hasErrors(diag)) {
        fprintf(stderr, "Failed to validate\n");
        lola_Diagnostics_display(diag);
        lola_Diagnostics_deinit(diag);
        deinit();
        return EXIT_FAILURE;
    }
    lola_Diagnostics_deinit(diag);
    diag=NULL;

    printf("disassembling!\n");
    lola_dis_Alloc dis={0};
    if (!lola_dis_allocZ(cu, (lola_DisassemblerOptions){.instructionOutput=true,.labelOutput=true,.addressPrefix=true}, &dis)) {
        fprintf(stderr, "Failed to disassemble\n");
        deinit();
        return EXIT_FAILURE;
    }
    printf("%s\n",dis.data.items);
    lola_dis_deinit(dis);

    env = lola_Environment_init(cu, pool);
    if (!env) {
        fprintf(stderr, "Failed to init environemnt\n");
        deinit();
        return EXIT_FAILURE;
    }
    if (!lola_Environment_installStd(env)) {
        fprintf(stderr, "Failed to install std\n");
        deinit();
        return EXIT_FAILURE;
    }
    if (!lola_Environment_installRuntime(env)) {
        fprintf(stderr, "Failed to install runtime\n");
        deinit();
        return EXIT_FAILURE;
    }
    if (!lola_Environment_install(env,lola_Str_fromC("addsub"),(lola_CallbackData){.c_func={.sync=addsubCB}})) {
        fprintf(stderr, "Failed to install runtime\n");
        deinit();
        return EXIT_FAILURE;
    }
    lola_CallbackData cbd = {
        .user_data=NULL,
        .c_func = {
            .callback_type=lola_CallbackType_async,
            .async=UserAsyncCB,
        },
    };
    if (!lola_Environment_install(env, lola_Str_fromC("UserAsync"), cbd)) {
        fprintf(stderr, "Failed to install UserAsync\n");
        deinit();
        return EXIT_FAILURE;
    }

    vm = lola_VM_init(env);
    if (!vm) {
        fprintf(stderr, "Failed to init vm\n");
        deinit();
        return EXIT_FAILURE;
    }

    uint8_t result;
    while (1) {
        if (!lola_VM_execute(vm, 0, &result)) {
            deinit();
            return EXIT_FAILURE;
        }
        if (result==lola_ExecutionResult_completed) break;
        if (result==lola_ExecutionResult_paused) printf("paused!\n");
    }
    

    return EXIT_SUCCESS;
}
