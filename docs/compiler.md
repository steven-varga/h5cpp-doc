<!---
 Copyright (c) 2018 vargaconsulting, Toronto,ON Canada
 Author: Varga, Steven <steven@vargaconsulting.ca>
--->


### The Idea

The `h5cpp` compiler is a fully-functional Clang-based source code transformation tool, which identifies POD C/C++ `struct` types referenced by the
`h5::create | h5::read | h5::write | h5::append` operators in all translation units (TU) and generates the necessary HDF5 datatype definitions. 

What does this mean in plain English? Take a few include files and a valid C++ program file, and then all you have to do to create an HDF5 dataset is
the following:
```cpp
#include <h5cpp/core>
/* 'ddl.h' will be generated by 'h5cpp' see below '-Dddl.h' option
 the translation unit (TU) must be valid, error free C++17 code with the exception of 
 the 'ddl.h' file to-be-generated. 
 */
#include <ddl.h>

#include <h5cpp/io> 

int main() {
	h5::create<some_complicated_struct>("file.h5", "dataset_name", h5::gzip{9} | h5::chunk{512} );
	return 0;
}
```
You can then invoke the compiler which will create the HDF5 datatype definitions for you:
```bash
h5cpp  struct.cpp --  -I../path/to/h5cpp-llvm  -Dddl.h
```
Besides `h5::create`, there are other convenient IO operators, such as `h5::read | h5::write | h5::append`, provided, who work independently from `h5::create` and are equally capable of producing the right output. Please follow [these instructions](@ref link_h5cpp_install) to set up llvm 7.0.0 and to compile the tool.

**CAVEAT:**
LLVM/CLANG++ **error messages are suppressed**, that is, if an invalid translation unit (a set of C++17 files) is passed, no error message is produced. This is because the compilation is done in two passes:
1. To build up the AST from the translation unit, and find the referenced `struct` dataype
2. To produce the output that will be included in later

Therefore, in this phase, if the input translation unit is invalid, it will produce an error message, no matter what. To prevent false negatives, it was decided to suppress error messages entirely. The author is aware of the immense potential for confusion: **invalid translations units will not have error messages printed out**; In time, if there is sufficient interest in the compiler/source code transformation tool, the error reporting capability may be restored to be more in line with expectations.

The `h5cpp-llvm` directory must contain the LLVM include files with which `h5cpp` was compiled. In case of static linkage, this directory still must be present, since the Clang tooling runtime architecture depends on it.
