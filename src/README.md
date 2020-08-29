# Source Structure

The project is structured into two major parts:
- [`frontend`](frontend/) is the compiler frontend which implements the command line executable
- [`library`](library/) is the implementation of both the runtime as well as the compiler. It is structured into several modules:
    - [`library/compiler`](library/compiler/) is the compiler which translates LoLa source code into LoLa byte code
    - [`library/runtime`](library/runtime) is the virtual machine implementation that allows running LoLa byte code
    - [`library/stdlib`](library/stdlib) is the implementation of the LoLa standard library and builds on the runtime
- [`tools`](tools/) contains small tools that are used in this repo, but have no relevance to LoLa itself. One example is the markdown renderer for the website.
- [`test`](test/) contains source files that are used to test the compiler and runtime implementation. See `build.zig` and the source files in `library` for the use of those. Each file in this folder has a header that explains its usage.