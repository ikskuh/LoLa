# LoLa C++ API

## Usage

```cpp
#include "LoLa/ast.hpp"
#include "LoLa/compiler.hpp"
#include "LoLa/runtime.hpp"

void run_script(char const * source)
{
    auto program = AST::parse(source);
    if(not program)
        return;

    auto compile_unit = LoLa::Compiler::Compiler().compile(*program);

    Runtime::Environment env(compile_unit);
    env.functions["Print"] = new GenericSyncFunction([](Value const * argv, size_t argc) -> Value
    {
        for(size_t i = 0; i < argc; i++)
        {
            if(i > 0)
                std::cout << " ";
            std::cout << argv[i];
        }
        std::cout << std::endl;
        return LoLa::Runtime::Void { };
    });
    env.functions["CreateStack"] = new GenericSyncFunction([](Value const *, size_t) -> Value
    {
        return ObjectRef(new StackObject); //< leaks memory, but we ignore this for now
    });

    Runtime::VirtualMachine machine { env };
    machine.enable_trace = true;
    while(machine.exec() != LoLa::Runtime::ExecutionResult::Done)
	{
    }
}
```

## Tracing

The virtual machine can enable a tracing mechanism which outputs a
debug log to *stderr* containing the current position, the instruction to
execute as well as the current stack.

```
[TRACE] 000000 | call_fn CreateStack, 0          	|
[TRACE] 00000f | store_global 0                  	|	object
[TRACE] 000012 | push_num 10                     	|
[TRACE] 00001b | load_global 0                   	|	10
[TRACE] 00001e | call_obj Push, 1                	|	10	object
[TRACE] 000026 | pop                             	|	void
[TRACE] 000027 | push_num 20                     	|
[TRACE] 000030 | load_global 0                   	|	20
[TRACE] 000033 | call_obj Push, 1                	|	20	object
[TRACE] 00003b | pop                             	|	void
[TRACE] 00003c | push_num 30                     	|
[TRACE] 000045 | load_global 0                   	|	30
[TRACE] 000048 | call_obj Push, 1                	|	30	object
[TRACE] 000050 | pop                             	|	void
[TRACE] 000051 | push_str 'mul'                  	|
[TRACE] 000057 | call_fn Operation, 1            	|	mul
[TRACE] 0000b9 | load_local 0                    	|
[TRACE] 0000bc | push_str 'print'                	|	mul
[TRACE] 0000c4 | eq                              	|	mul	print
[TRACE] 0000c5 | jif 222                         	|	false
[TRACE] 0000de | load_local 0                    	|
[TRACE] 0000e1 | push_str 'add'                  	|	mul
[TRACE] 0000e7 | eq                              	|	mul	add
[TRACE] 0000e8 | jif 282                         	|	false
[TRACE] 00011a | load_local 0                    	|
[TRACE] 00011d | push_str 'mul'                  	|	mul
[TRACE] 000123 | eq                              	|	mul	mul
[TRACE] 000124 | jif 342                         	|	true
[TRACE] 000129 | load_global 0                   	|
[TRACE] 00012c | call_obj Pop, 0                 	|	object
[TRACE] 000133 | store_local 1                   	|	30
[TRACE] 000136 | load_global 0                   	|
[TRACE] 000139 | call_obj Pop, 0                 	|	object
[TRACE] 000140 | store_local 2                   	|	20
[TRACE] 000143 | load_local 1                    	|
[TRACE] 000146 | load_local 2                    	|	30
[TRACE] 000149 | mul                             	|	30	20
[TRACE] 00014a | load_global 0                   	|	600
[TRACE] 00014d | call_obj Push, 1                	|	600	object
[TRACE] 000155 | pop                             	|	void
[TRACE] 000156 | ret                             	|
[TRACE] 000064 | pop                             	|	void
[TRACE] 000065 | push_str 'add'                  	|
[TRACE] 00006b | call_fn Operation, 1            	|	add
[TRACE] 0000b9 | load_local 0                    	|
[TRACE] 0000bc | push_str 'print'                	|	add
[TRACE] 0000c4 | eq                              	|	add	print
[TRACE] 0000c5 | jif 222                         	|	false
[TRACE] 0000de | load_local 0                    	|
[TRACE] 0000e1 | push_str 'add'                  	|	add
[TRACE] 0000e7 | eq                              	|	add	add
[TRACE] 0000e8 | jif 282                         	|	true
[TRACE] 0000ed | load_global 0                   	|
[TRACE] 0000f0 | call_obj Pop, 0                 	|	object
[TRACE] 0000f7 | store_local 1                   	|	600
[TRACE] 0000fa | load_global 0                   	|
[TRACE] 0000fd | call_obj Pop, 0                 	|	object
[TRACE] 000104 | store_local 2                   	|	10
[TRACE] 000107 | load_local 1                    	|
[TRACE] 00010a | load_local 2                    	|	600
[TRACE] 00010d | add                             	|	600	10
[TRACE] 00010e | load_global 0                   	|	610
[TRACE] 000111 | call_obj Push, 1                	|	610	object
[TRACE] 000119 | pop                             	|	void
[TRACE] 00011a | load_local 0                    	|
[TRACE] 00011d | push_str 'mul'                  	|	add
[TRACE] 000123 | eq                              	|	add	mul
[TRACE] 000124 | jif 342                         	|	false
[TRACE] 000156 | ret                             	|
[TRACE] 000078 | pop                             	|	void
[TRACE] 000079 | push_str 'print'                	|
[TRACE] 000081 | call_fn Operation, 1            	|	print
[TRACE] 0000b9 | load_local 0                    	|
[TRACE] 0000bc | push_str 'print'                	|	print
[TRACE] 0000c4 | eq                              	|	print	print
[TRACE] 0000c5 | jif 222                         	|	true
[TRACE] 0000ca | load_global 0                   	|
[TRACE] 0000cd | call_obj Pop, 0                 	|	object
[TRACE] 0000d4 | call_fn Print, 1                	|	610
[TRACE] 0000dd | pop                             	|	void
[TRACE] 0000de | load_local 0                    	|
[TRACE] 0000e1 | push_str 'add'                  	|	print
[TRACE] 0000e7 | eq                              	|	print	add
[TRACE] 0000e8 | jif 282                         	|	false
[TRACE] 00011a | load_local 0                    	|
[TRACE] 00011d | push_str 'mul'                  	|	print
[TRACE] 000123 | eq                              	|	print	mul
[TRACE] 000124 | jif 342                         	|	false
[TRACE] 000156 | ret                             	|
[TRACE] 00008e | pop                             	|	void
[TRACE] 00008f | load_global 0                   	|
[TRACE] 000092 | call_obj GetSize, 0             	|	object
[TRACE] 00009d | push_str 'Stack Length: '       	|	0
[TRACE] 0000ae | call_fn Print, 2                	|	0	Stack Length: 
[TRACE] 0000b7 | pop                             	|	void
[TRACE] 0000b8 | ret                             	|
```
