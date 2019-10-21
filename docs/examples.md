### About Examples
You find examples for most implemented features on the project github page, or when installed from package manager in `/usr/local/share/h5cpp`. Only a `cmake`, a C++17 compatible tool-chain and the HDF5 libraries are required to run them. The examples not only `cmake` but traditional make files as well.

### [container][11]
Demonstrates how to create and manipulate HDF5 containers within H5CPP
 [read on HDF5 container here][104].

### [groups][10]
Datasets within HDF5 containers similarly to other file-systems are addressed by a tree like data structure, each node in the path is called a group these examples help you how to manipulate the groups, including adding attributes.
You can [read on groups here][102].

### [datasets][10]
This example guides you how to create HDF5 datasets, and control its properties. You can [read on datasets here][103].

### [attributes][10]
Objects may have additional information attached to them, called attributes, currently only datasets `h5::ds_t` are supported, but at some point this will be extended to `h5::gr_t` and `h5::dt_t` as well. Since the attributes are saved in the metadata section in the HDF5 container the space is limited. You can [read on attributes here][101].





### [basics][11]
Demonstrates data descriptors, their properties and how to work with them.

### [before/after][12]
is a comparison between [C API][13] and [H5CPP][14] persisting a compound datatype. While the example uses the `h5cpp` compiler, the [generated.hpp][15] header file is provided. Written by Gerd Heber, The HDFGroup


### [compound][16]
is another example for persisting Plain Old Data (POD) Struct types, with a [more complex struct][17] to show that the compiler indeed works, with arbitrary embedding and the quality of [generated header][18] file.

### [linalg][19]
has all the linear algebra related examples for various systems. IF you are a data-scientist/engineer working with massive HDF5 datasets, probably this is where you want to start.

### [mpi][20]
Message Passing Interface (MPI) is de facto standard on HPC clusters and supercomputers. This example demonstrates how to persist data to parallel file system with [collective][21] and [independent][22] IO requests. This section is for people who intend to write code for MPI based systems.

### [multi translation unit][23] - `h5cpp` compiler
Projects are rarely small, breaking it into different translation units is a natural way of handling complexity for compiled systems. This example shows you how to set up your [makefile][24] and write the [program file][25] so it works with `h5cpp` source code transformation tool.


### [packet table][26]
Streams of packets from sensor networks, stock exchange, ... need high performance event processor. This [example shows][27] you how simple it is to persists a stream of various shaped packets into HDF5 dataset. Supported objects are:

* integral types -- buffered into blocks
* POD struct 

Packetable also known to work with matrices, vectors, etc...

### [raw memory][28]
shows you how to save data from memory location, as well as provides examples for filtering algorithms such as
`h5::fletcher32 | h5::shuffle | h5::nbit | h5::gzip{9}` and setting fill value with `h5::fill_value<short>{42}`


### [string][29]
a brief [example][30] on how to save a set of strings with `h5::utf8` encoding


### [transform][31]
simple example how to transform/change data within the data transfer buffer of the HDF5 C library. This feature is 
to change the data set transparently before loading, or saving.

[10]: https://github.com/steven-varga/h5cpp/tree/master/examples/attributes
[11]: https://github.com/steven-varga/h5cpp/tree/master/examples/basics
[12]: https://github.com/steven-varga/h5cpp/tree/master/examples/before-after
[13]: https://github.com/steven-varga/h5cpp/blob/master/examples/before-after/compound.c
[14]: https://github.com/steven-varga/h5cpp/blob/master/examples/before-after/compound.cpp
[15]: https://github.com/steven-varga/h5cpp/blob/master/examples/before-after/generated.h
[16]: https://github.com/steven-varga/h5cpp/tree/master/examples/compound
[17]: https://github.com/steven-varga/h5cpp/blob/master/examples/compound/struct.h
[18]: https://github.com/steven-varga/h5cpp/blob/master/examples/compound/generated.h
[19]: https://github.com/steven-varga/h5cpp/tree/master/examples/linalg
[20]: https://github.com/steven-varga/h5cpp/tree/master/examples/mpi
[21]: https://github.com/steven-varga/h5cpp/blob/master/examples/mpi/collective.cpp
[22]: https://github.com/steven-varga/h5cpp/blob/master/examples/mpi/independent.cpp
[23]: https://github.com/steven-varga/h5cpp/tree/master/examples/multi-tu
[24]: https://github.com/steven-varga/h5cpp/blob/master/examples/multi-tu/Makefile
[25]: https://github.com/steven-varga/h5cpp/blob/master/examples/multi-tu/tu_01.cpp
[26]: https://github.com/steven-varga/h5cpp/tree/master/examples/packet-table
[27]: https://github.com/steven-varga/h5cpp/blob/master/examples/packet-table/packettable.cpp
[28]: https://github.com/steven-varga/h5cpp/tree/master/examples/raw_memory
[29]: https://github.com/steven-varga/h5cpp/blob/master/examples/string
[30]: https://github.com/steven-varga/h5cpp/blob/master/examples/string/string.cpp
[31]: https://github.com/steven-varga/h5cpp/tree/master/examples/transform
[32]: https://github.com/steven-varga/h5cpp/blob/master/examples/transform/transform.cpp




[101]: examples/attributes.md 
[102]: examples/groups.md 
[103]: examples/datasets.md 
[104]: examples/container.md 
