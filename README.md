```
 a,  8a
 `8, `8)                            ,adPPRg,
  8)  ]8                        ,ad888888888b
 ,8' ,8'                    ,gPPR888888888888
,8' ,8'                 ,ad8""   `Y888888888P
8)  8)              ,ad8""        (8888888""
8,  8,          ,ad8""            d888""
`8, `8,     ,ad8""      G     ,ad8""
 `8, `" ,ad8""      I     ,ad8""
    ,gPPR8b     C     ,ad8""
   dP:::::Yb      ,ad8""
   8):::::(8  ,ad8""
   Yb:;;;:d888""
    "8ggg8P"
```

# cig

The coolest C compiler in town... he even smokes.  
Built by following Nora Sandler's "Writing a C Compiler" book using Zig.

## Usage
> [!IMPORTANT]
> Supports Linux and MacOS. Tested on Ubuntu 24.04 x86_64.

To run on a C source file, you can use the below command:

```bash
zig build run -- source.c

```
Below commands are available to test separate compiler stages:
- `--lex`: stop at lexing
- `--parse`: stop at parsing
- `--codegen`: stop at codegen
- `-S`: emit assembly but do not assemble

## Other stuff
Next on the list is the end of Chapter 1:
- Assembly emission
- Reference assembly AST from zig compiler

## LICENSE
**See LICENSE file.**  
**Copyright © 2025 Artemis Rosman**

Header ASCII art by Normand Veilleux.

