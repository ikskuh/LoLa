# Source Structure

The project is structured into two major parts:
- [`frontend`](frontend/) is the compiler frontend which implements the command line executable
- [`library`](library/) is the implementation of both the runtime as well as the compiler. It is structured into several modules:
    - [`library/compiler`](library/compiler/) is the compiler which translates LoLa source code into LoLa byte code
    - [`library/runtime`](library/runtime) is the virtual machine implementation that allows running LoLa byte code
    - [`library/stdlib`](library/stdlib) is the implementation of the LoLa standard library and builds on the runtime
    