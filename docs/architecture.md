
# HDF5 Filesystem
<p align='justify'>
Within HDF5 container, objects are stored in either custom sized chunks or a single continuous dataset and can be referenced similarly as if it were a regular file system: a path separated by `/`. The collection of paths may be modelled as a tree (or graph), where the intermediate or non-leaf nodes are called groups `h5::gr_t`, and the leaf ones are the datasets `h5::ds_t`.
</p>
<p align='justify'>
The container sports an internal type system, as well as mechanism to store fixed length and variable length data. These features are automatically set in H5CPP by keeping track of object types, and element types at compile time.
How data stored or retrieved from a container is controlled through property lists. To give you an example for a property: [`h5::gzip{9}`][604] sets compression to maximum level. The system differentiates between data access properties: `h5::dapl_t`, data transfer property lists: `h5::dxpl_t`, data control property lists `h5::dcpl_t`. You can get the full property list [from this link](#property-lists). </p>

#### Partial IO Access
<p align='justify'>
Datasets greater than core memory may be loaded by smaller blocks at a time. This type of access pattern is called `chunking` in HDF5 terminology and you can locate a chunk by specifying `h5::offset{...}`, `h5::count{...}` and `h5::stride{...}`.
All these objects take an initializer list as arguments, for example this sets the coordinates to zero: `h5::offset{0,0,0}` for a rank 3 or cube dataset. Upto **rank 7** objects are supported.

`h5::stride` tells if you wish to select adjacent elements or you wish to skip `n`  along a dimension and I find it less useful for fast IO. In fact `h5::stride` can reduce IO bandwidth significantly and completely omitted from `h5::high_throughput` filtering pipeline.

**NOTE:** partial IO is not available for attributes
</p>

#### Single IO Access
The simplest form of IO is to read a dataset entirely into memory, or write it to the disk. The upside is to reduce overhead when working with large amount of small size dataset. Indeed, when objects are saved in single IO op and no filtering is specified, H5CPP will choose this access pattern.  The downside of simplicity is lack of filtering.


#### Data Space
is a way to tell the system how in-memory data mapped to file (or reverse). To give you an example, picture a block of data in consecutive memory that you wish to map into a 3D space on the file layout. Other than that the data space may be fixed size, or able to be extended to a definite or unlimited size along some dimension.

When working with supported objects, the in-memory dataspace is pre computed for you. And when passing raw pointers to IO operators, the filespace will determine the amount of memory used.


#IO Operators
<p align='justify'>
Modern C++ provides rich set of features to create variables and implement program logic running inside the compiler. This compile time mechanism, or template meta-programming, allows not only to match types but passing arguments in arbitrary order; much similarly to what we find in Python. The main difference however is in the implementation: the C++ version is without runtime overhead.
</p>

In the next sections we guide you through H5CPP's CRUD like operators: `h5::create`,`h5::read`,`h5::write`,`h5::append` and `h5::open`, `h5::close`.
The function calls are given in EBNF notation and we start with a few common tokens.


Think of HDF5 as a container, or an image of a file system with a non-POSIX API to access its content. These containers/images may be passed around with standard file operations between computers, while the content may be retrieved with HDF5 specific IO calls. To reference a container within a file-system you either need to pass an open file descriptor `h5::fd_t` or the full path to the HDF5 file:
```cpp
file ::= const h5::fd_t& fd | const std::string& file_path;
```


An HDF5 Dataset is an object within the container, and to uniquely identify one you either have to pass an open dataset-descriptor `h5::ds_t` or tell the 
system where to find the container, and the dataset within. In the latter case the necessary shim code is generated to obtain `h5::fd_t` descriptor at compile time.
```cpp
dataset ::= (const h5::fd_t& fd | 
	const std::string& file_path, const std::string& dataset_path ) | const h5::ds_t& ds;
```




HDF5 datasets may take up various shapes and sizes in memory and on disk. A **dataspace** is a descriptor to specify the current size of the object, and if is capable of growing:
```cpp
dataspace ::= const h5::sp_t& dataspace 
	| const h5::current_dims& current_dim [, const h5::max_dims& max_dims ] 
	[,const h5::current_dims& current_dim] , const h5::max_dims& max_dims;
```

`T` type is the template parameter of an object. In the underlying implementation the element type is deduced compile time, bringing you a flexible abstract approach. The objects may be categorized into ones with continuous memory blocks, such as matrices, vectors, C style POD structures, and complex types such as C++ classes. The latter objects are not yet fully supported. More [detailed explanation in this section.](#types).

#### OPEN
The [previous section](#pythonic-syntax) explained the EBNF tokens: `file`,`dataspace`. The behaviour of the objects are controlled through property lists and the syntax is rather simple:
```cpp
[file]
h5::fd_t h5::open( const std::string& path,  H5F_ACC_RDWR | H5F_ACC_RDONLY [, const h5::fapl_t& fapl] );

[dataset]
h5::ds_t h5::open( const  h5::fd_t& fd, const std::string& path [, const h5::dapl_t& dapl] )
```
Property lists are:  [`h5::fapl_t`][602],  [`h5::dapl_t`][605]

#### CREATE

```cpp
[file]
h5::fd_t h5::create( const std::string& path, H5F_ACC_TRUNC | H5F_ACC_EXCL, 
			[, const h5::fcpl_t& fcpl] [, const h5::fapl_t& fapl]);
[dataset]
template <typename T> h5::ds_t h5::create<T>( file, const std::string& dataset_path, dataspace, 
	[, const h5::lcpl_t& lcpl] [, const h5::dcpl_t& dcpl] [, const h5::dapl_t& dapl]  );
[attribute]
	..TBD..
```
Property lists are: [`h5::fcpl_t`][601], [`h5::fapl_t`][602], [`h5::lcpl_t`][603], [`h5::dcpl_t`][604], [`h5::dapl_t`][605]

**Example:** to create an HDF5 container, and a dataset within:
```cpp
#include <h5cpp/core>
	#include "your_data_definition.h"
#include <h5cpp/io>
...
arma::mat M(2,3);
h5::fd_t fd = h5::create("arma.h5",H5F_ACC_TRUNC);
h5::ds_t ds = h5::create<short>(fd,"dataset/path/object.name"
                ,h5::current_dims{10,20}
                ,h5::max_dims{10,H5S_UNLIMITED}
                ,h5::chunk{2,3} | h5::fill_value<short>{3} |  h5::gzip{9}
        );
//attributes:
ds["attribute-name"] = std::vector<int>(10);
...
```

#### READ
There are two kind of operators:

* **returning an object** are useful when you access data in a single shot, outside of a loop. The object is created with the right size and return value optimization or RVO will make sure that no copy takes place.
* **updating an existing object** are for repeating access, inside a loop, where stressing the memory would be detrimental. It is your responsibility to create the right size of object, then the templates will grab the memory location whenever possible then transfer data from disk to that location directly
without temporaries.


Keep in mind that the underlying HDF5 system always reserves a chunk size buffer for data transfer, usually for filtering and or data conversion. Nevertheless this data transfer buffer is minimal -- as under ideal conditions the chunks should be not more than the level 3 cache size of the processor.
```cpp
template <typename T> T h5::read( dataset
	[, const h5::offset_t& offset]  [, const h5::stride_t& stride] [, const h5::count_t& count]
	[, const h5::dxpl_t& dxpl ] ) const;
template <typename T> h5::err_t h5::read( dataset, T& ref 
	[, const [h5::offset_t& offset]  [, const h5::stride_t& stride] [, const h5::count_t& count]
	[, const h5::dxpl_t& dxpl ] ) const;						 
```
Property lists are: [`dxpl_t`][606]
 
**example:** to read a 10x5 matrix from a 3D array from location {3,4,1}
```cpp
#include <armadillo>
#include <h5cpp/all>
...
auto fd = h5::open("some_file.h5", H5F_ACC_RDWR);
/* the RVO arma::Mat<double> object will have the size 10x5 filled*/
try {
	/* will drop extents of unit dimension returns a 2D object */
	auto M = h5::read<arma::mat>(fd,"path/to/object", 
			h5::offset{3,4,1}, h5::count{10,1,5}, h5::stride{3,1,1} ,h5::block{2,1,1} );
} catch (const std::runtime_error& ex ){
	...
}
```

#### WRITE
There are two kind of operators:

* **reference** are for objects H5CPP is aware of. This is the recommended pattern, and have the same performance characteristics of the pointer types; except the convenience.
* **pointer** support any raw memory locations, as long as they are continous. Mostly useful for cases not covered. You pick the memory location, tell the data transfer properties and the rest is taken care of.

Keep in mind that the underlying HDF5 system always reserves a chunk size buffer for data transfer, usually for filtering and or data conversion. Nevertheless this data transfer buffer is minimal -- as under ideal conditions the chunks should be not more than the level 3 cache size of the processor.

```cpp
template <typename T> h5::err_t h5::write( dataset,  const T& ref
	[,const h5::offset_t& offset] [,const h5::stride_t& stride]  [,const& h5::dxcpl_t& dxpl] );
template <typename T> h5::err_t h5::write( dataset, const T* ptr
	[,const hsize_t* offset] [,const hsize_t* stride] ,const hsize_t* count [, const h5::dxpl_t dxpl ]);
```
Property lists are:  [`dxpl_t`][606]

```cpp
#include <Eigen/Dense>
#include <h5cpp/all>

h5::fd_t fd = h5::create("some_file.h5",H5F_ACC_TRUNC);
h5::write(fd,"/result",M);
```
#### APPEND
When receiving a stream of data, packet tables are the way to go. While this operator does rely on its own `h5::pt_t` descriptor, the underlying dataset is just the same old one introduced in previous section. The `h5::pt_t` are seamlessly convertible to `h5::ds_t` and vica-versa. 

However the similarity ends with that. `h5::pt_t` internals are different from other H5CPP handles, as it has internal buffer and a custom data transfer pipeline. This pipeline can also be used in regular data-transfer operations by adding `h5::experimental` to data transfer property lists. The experimental pipeline is [documented here.][308]



``` c++
#include <h5cpp/core>
	#include "your_data_definition.h"
#include <h5cpp/io>
template <typename T> void h5::append(h5::pt_t& ds, const T& ref);
```

**example:**
``` c++
#include <h5cpp/core>
	#include "your_data_definition.h"
#include <h5cpp/io>
auto fd = h5::create("NYSE high freq dataset.h5");
h5::pt_t pt = h5::create<ns::nyse_stock_quote>( fd, 
		"price_quotes/2018-01-05.qte",h5::max_dims{H5S_UNLIMITED}, h5::chunk{1024} | h5::gzip{9} );
quote_update_t qu;

bool having_a_good_day{true};
while( having_a_good_day ){
	try{
		recieve_data_from_udp_stream( qu )
		h5::append(pt, qu);
	} catch ( ... ){
	  if( cant_fix_connection() )
	  		having_a_good_day = false; 
	}
}
```




# Supported Objects

### Linear Algebra
HDF5 CPP is to simplify object persistence by implementing [CREATE][create], [READ][read], [WRITE][write], [APPEND][append] operations on **fixed** or **variable length** N dimensional arrays.
This header only implementation supports [raw pointers][99] | [armadillo][100] | [eigen3][102] | [blaze][106] | [blitz++][103] |  [it++][104] | [dlib][105] |  [uBlas][101] by directly operating on the underlying data-store, avoiding intermediate/temporary memory allocations and [using copy elision][copy_elision] for returning objects:

```cpp
arma::mat rvo = h5::read<arma::mat>(fd, "path_to_object"); //return value optimization:RVO
```

For high performance operations ie: within loops update the content with partial IO call:
```cpp
h5::ds_t ds = h5::open( ... ) 		// open dataset
arma::mat M(n_rows,n_cols);   		// create placeholder, data-space is reserved on the heap
h5::count_t  count{n_rows,n_cols}; 	// describe the memory region you are reading into
h5::offset_t offset{0,0}; 			// position we reasing data from
// high performance loop with minimal memory operations
for( auto i: column_indices )
	h5::read(ds, M, count, offset); // count, offset and other proeprties may be speciefied in any order
```

List of objects supported in EBNF:
```yacc
T := ([unsigned] ( int8_t | int16_t | int32_t | int64_t )) | ( float | double  )
S := T | c/c++ struct | std::string
ref := std::vector<S> 
	| arma::Row<T> | arma::Col<T> | arma::Mat<T> | arma::Cube<T> 
	| Eigen::Matrix<T,Dynamic,Dynamic> | Eigen::Matrix<T,Dynamic,1> | Eigen::Matrix<T,1,Dynamic>
	| Eigen::Array<T,Dynamic,Dynamic>  | Eigen::Array<T,Dynamic,1>  | Eigen::Array<T,1,Dynamic>
	| blaze::DynamicVector<T,rowVector> |  blaze::DynamicVector<T,colVector>
	| blaze::DynamicVector<T,blaze::rowVector> |  blaze::DynamicVector<T,blaze::colVector>
	| blaze::DynamicMatrix<T,blaze::rowMajor>  |  blaze::DynamicMatrix<T,blaze::colMajor>
	| itpp::Mat<T> | itpp::Vec<T>
	| blitz::Array<T,1> | blitz::Array<T,2> | blitz::Array<T,3>
	| dlib::Matrix<T>   | dlib::Vector<T,1> 
	| ublas::matrix<T>  | ublas::vector<T>
ptr 	:= T* 
accept 	:= ref | ptr 
```

Here is the chart how supported linalgebra systems implement acessors, memory layout:

```
		data            num elements  vec   mat:rm                mat:cm                   cube
-------------------------------------------------------------------------------------------------------------------------
eigen {.data()}          {size()}          {rows():1,cols():0}    {cols():0,rows():1}     {n/a}
arma  {.memptr()}        {n_elem}                                 {n_rows:0,n_cols:1}     {n_slices:2,n_rows:0,n_cols:1}
blaze {.data()}          {n/a}             {columns():1,rows():0} {rows():0,columns():1}  {n/a}
blitz {.data()}          {size()}          {cols:1,  rows:0}                              {slices:2, cols:1,rows:0} 
itpp  {._data()}         {length()}        {cols():1,rows():0}
ublas {.data().begin()}  {n/a}             {size2():1, size1():0}
dlib  {&ref(0,0)}        {size()}          {nc():1,    nr():0}
```



#### Storage Layout: [Row / Column ordering][200]
H5CPP guarantees zero copy, platform and system independent correct behaviour between supported linear algebra Matrices.
In linear algebra the de-facto standard is column major ordering similarly to Fortran. However this is changing and many of the above listed linear algebra systems support row-major ordering as well.

Currently there is no easy way to automatically transpose column major matrix such as `arma::mat` into row major storage. One solution would be to 
do the actual transpose operation when loading/saving the matrix by a custom filter. The alternative is to mark the object as transposed, following BLAS strategy. The latter approach has minimal approach on performance, but requires cooperation from other library writers. Unfortunatelly the HDF5 CAPI doesn't support either of them. Nevertheless **manual transpose** always works, and is supported by most linear algebra systems.

#### Sparse Matrices/Vectors
Compressed Sparse Row ([CSR][csr]) and Compressed Sparse Column ([CSC][csc]) formats will be supported. The actual storage format may be multi objects inside a `h5::gr_t` group, or a single compound data type as a place holder for the indices and actual data. Special structures such as block diagonal, tri diagonal, triangular are not yet supported. Nevertheless will follow BLAS/LAPACK storage layout whenever possible.


### The STL
There are three notable categories from storage perspective:

* `std::vector<T>`, `std::array<T,N>` have `.data()` accessors and H5CPP can directly load/save data from the objects. For efficient partial data transfer the data transfer size must match the element size of the objects.

* `std::list<T>`, `std::forward_list<T>`, `std::deque<T>`, `std::set<T>`, `std::multiset<T>`,`std::unordered_set<T>`,`std::map<K,V>`,`std::multimap<K,V>`, `std::unordered_multimap<K,V>`
don't have direct access to underlying memory store, instead provided iterators are used for data transfer between memory and disk. The IO transaction is broken into chunk size blocks and loaded into STL objects. This method has a maximum memory requirements of `element_size * ( container_size + chunk_size )`

* `std::stack`,`std::queue`,`std::priority_queue` are adaptors, the underlying data-structure determines how data transfer takes place

### Raw Pointers
Currently only memory blocks are supported in consecutive/adjacent location of elementary or POD types. This method comes handy when an object type is not supported. You find the way to grab a pointer to its internal datastore and the size then pass this as an argument. For [read][read] operation make sure there is enough memory reserved, for [write][write] operation you must specify the data transfer size with `h5::count`

**Example:** loading data from HDF5 dataset to a memory location
```cpp
my_object obj(100);
h5::read("file.h5","dataset.dat",obj.ptr(), h5::count{10,10}, h5::offset{100,0});
``` 

### Compound Datatypes
#### POD Struct/Records
Arbitrary deep and complex Plain Old Structured (POD) are supported either by [h5cpp compiler][compiler] or manually writing the necessary shim code. The following example is generated with `h5cpp` compiler, note that in the first step you have to specialize `template<class Type> hid_t inline register_struct<Type>();` to the type you are to use it with and return an HDF5 CAPI `hid_t` type identifier. This `hid_t` object references a memory location inside the HDF5 system, and will be automatically released with `H5Tclose` when used with H5CPP templates. The final step is to register this new type with H5CPP type system : `H5CPP_REGISTER_STRUCT(Type);`.

```cpp
namespace sn {
	struct PODstruct {
		... 
		bool _bool;
	};
}
namespace h5{
    template<> hid_t inline register_struct<sn::PODstruct>(){
        hid_t ct_00 = H5Tcreate(H5T_COMPOUND, sizeof (sn::PODstruct));
		...
        H5Tinsert(ct_00, "_bool",	HOFFSET(sn::PODstruct,_bool),H5T_NATIVE_HBOOL);
        return ct_00;
    };
}
H5CPP_REGISTER_STRUCT(sn::PODstruct);
```
The internal typesystem for POD/Record types supports:

* `std::is_integral` and `std::is_floating_point`
* `std::is_array` plain old array type, but not `std::array` or `std::vector` 
* arrays of the the above, with arbitrary embedding
* POD structs of the above with arbitrary embedding


#### C++ Classes
Work in progress. Requires modification to compiler as well as coordinated effort how to store complex objects such that other platforms capable of reading them.

### Strings
HDF5 supports variable and fixed strings. The former is of interest, as the most common ways for storing strings in a file: consecutively with a separator. The current storage layout is a heap data structure making it less suitable for massive Terra Byte scale storage. In addition the strings have to be copied during [read][read] operation. Both filtering such as `h5::gzip{0-9}` and `h5::utf8` features are supported.

**not supported**: `wchar_t _wchar char16_t _wchar16 char32_t _wchar32`

**TODO:** work out a new efficient storage mechanism for strings.


# Type System
In the core of H5CPP there lies the type mapping mechanism to HDF5 NATIVE types. All type requests are redirected to this segment in one way or another. That includes supported vectors, matrices, cubes, C like structs etc. While HDF5 internally supports type translations among various binary representation H5CPP restricts type handling to the most common case where the program intended to run. This is not in violation of HDF5 use-anywhere policy, just type conversion is delegated to hosts with different binary representation. Since the most common processors are Intel and AMD this approach has the advantage of skipping any conversion.

```yacc
integral 		:= [ unsigned | signed ] [int_8 | int_16 | int_32 | int_64 | float | double ] 
vectors  		:=  *integral
rugged_arrays 	:= **integral
string 			:= **char
linalg 			:= armadillo | eigen | ... 
scalar 			:= integral | pod_struct | string

# not handled yet: long double, complex, specialty types
```

Here is the relevant part responsible for type mapping:
```cpp
#define H5CPP_REGISTER_TYPE_( C_TYPE, H5_TYPE )                                           \
namespace h5 { namespace impl { namespace detail { 	                                      \
	template <> struct hid_t<C_TYPE,H5Tclose,true,true,hdf5::type> : public dt_p<C_TYPE> {\
		using parent = dt_p<C_TYPE>;                                                      \
		using parent::hid_t;                                                              \
		using hidtype = C_TYPE;                                                           \
		hid_t() : parent( H5Tcopy( H5_TYPE ) ) { 										  \
			hid_t id = static_cast<hid_t>( *this );                                       \
			if constexpr ( std::is_pointer<C_TYPE>::value )                               \
					H5Tset_size (id,H5T_VARIABLE), H5Tset_cset(id, H5T_CSET_UTF8);        \
		}                                                                                 \
	};                                                                                    \
}}}                                                                                       \
namespace h5 {                                                                            \
	template <> struct name<C_TYPE> {                                                     \
		static constexpr char const * value = #C_TYPE;                                    \
	};                                                                                    \
}                                                                                         \
```
Arithmetic types are associated with their NATIVE HDF5 equivalent:
```cpp
H5CPP_REGISTER_TYPE_(bool,H5T_NATIVE_HBOOL)

H5CPP_REGISTER_TYPE_(unsigned char, H5T_NATIVE_UCHAR) 			H5CPP_REGISTER_TYPE_(char, H5T_NATIVE_CHAR)
H5CPP_REGISTER_TYPE_(unsigned short, H5T_NATIVE_USHORT) 		H5CPP_REGISTER_TYPE_(short, H5T_NATIVE_SHORT)
H5CPP_REGISTER_TYPE_(unsigned int, H5T_NATIVE_UINT) 			H5CPP_REGISTER_TYPE_(int, H5T_NATIVE_INT)
H5CPP_REGISTER_TYPE_(unsigned long int, H5T_NATIVE_ULONG) 		H5CPP_REGISTER_TYPE_(long int, H5T_NATIVE_LONG)
H5CPP_REGISTER_TYPE_(unsigned long long int, H5T_NATIVE_ULLONG) H5CPP_REGISTER_TYPE_(long long int, H5T_NATIVE_LLONG)
H5CPP_REGISTER_TYPE_(float, H5T_NATIVE_FLOAT) 					H5CPP_REGISTER_TYPE_(double, H5T_NATIVE_DOUBLE)
H5CPP_REGISTER_TYPE_(long double,H5T_NATIVE_LDOUBLE)

H5CPP_REGISTER_TYPE_(char*, H5T_C_S1)
```
Record/POD struct types are registered through this macro:
```cpp
#define H5CPP_REGISTER_STRUCT( POD_STRUCT ) \
	H5CPP_REGISTER_TYPE_( POD_STRUCT, h5::register_struct<POD_STRUCT>() )
```
**FYI:** there are no other public/unregistered macros other than `H5CPP_REGISTER_STRUCT`

### Using CAPI Functions
By default the `hid_t` type automatically is converted to / from H5CPP `h5::hid_t<T>` templated identifiers. All HDF5 CAPI types are wrapped into `h5::impl::hid_t<T>` internal template, keeping binary compatibility, with the exception of `h5::pt_t` packet table handle.
```yacc
T := [ file_handles | property_list ]
file_handles   := [ fd_t | ds_t | att_t | err_t | grp_t | id_t | obj_t ]
property_lists := [ file | dataset | attrib | group | link | string | type | object ]

#            create       access       transfer     copy 
file    := [ h5::fcpl_t | h5::fapl_t                            ] 
dataset := [ h5::dcpl_t | h5::dapl_t | h5::dxpl_t               ]
attrib  := [ h5::acpl_t                                         ] 
group   := [ h5::gcpl_t | h5::gapl_t                            ]
link    := [ h5::lcpl_t | h5::lapl_t                            ]
string  := [              h5::scpl_t                            ] 
type    := [              h5::tapl_t                            ]
object  := [ h5::ocpl_t                           | h5::ocpyl_t ]
```

# Property Lists

The functions, macros, and subroutines listed here are used to manipulate property list objects in various ways, including to reset property values. With the use of property lists, HDF5 functions have been implemented and can be used in applications with fewer parameters than would be required without property lists, this mechanism is similar to [POSIX fcntl][700]. Properties are grouped into classes, and each class member may be daisy chained to obtain a property list.

To give you an example how to obtain a data creation property list with chunk, fill value, shuffling, nbit, fletcher23 filters and gzip compression set:
```cpp
h5::dcpl_t dcpl = h5::chunk{2,3} 
	| h5::fill_value<short>{42} | h5::fletcher32 | h5::shuffle | h5::nbit | h5::gzip{9};
auto ds = h5::create("container.h5","/my/dataset.dat", h5::create_path | h5::utf8, dcpl, h5::default_dapl);
```
Properties may be passed in arbitrary order, by reference, or directly by daisy chaining them. A list of property descriptors:
```yacc
#            create       access       transfer     copy 
file    := [ h5::fcpl_t | h5::fapl_t                            ] 
dataset := [ h5::dcpl_t | h5::dapl_t | h5::dxpl_t               ]
attrib  := [ h5::acpl_t                                         ] 
group   := [ h5::gcpl_t | h5::gapl_t                            ]
link    := [ h5::lcpl_t | h5::lapl_t                            ]
string  := [              h5::scpl_t                            ] 
type    := [              h5::tapl_t                            ]
object  := [ h5::ocpl_t                           | h5::ocpyl_t ]
```




#### [File Creation Property List][1001]
```cpp
// you may pass CAPI property list descriptors daisy chained with '|' operator 
auto fd = h5::create("002.h5", H5F_ACC_TRUNC, 
		h5::file_space_page_size{4096} | h5::userblock{512},  // file creation properties
		h5::fclose_degree_weak | h5::fapl_core{2048,1} );     // file access properties
```


* [`h5::userblock{hsize_t}`][1001] sets the user block size of a file creation property list
* [`h5::sizes{size_t,size_t}`][1002] Sets the byte size of the offsets and lengths used to address objects in an HDF5 file.
* [`h5::sym_k{unsigned,unsigned}`][1003] Sets the size of parameters used to control the symbol table nodes.
* [`h5::istore_k{unsigned}`][1004] Sets the size of the parameter used to control the B-trees for indexing chunked dataset.
* [`h5::file_space_page_size{hsize_t}`][1005] Sets the file space page size for a file creation property list.
* [`h5::shared_mesg_nindexes{unsigned}`][1007] Sets number of shared object header message indexes.
* [`h5::shared_mesg_index{unsigned,unsigned,unsigned}`][1008] Configures the specified shared object header message index.
* [`h5::shared_mesg_phase_change{unsigned,unsigned}`][1009] Sets shared object header message storage phase change thresholds.
 
#### [File Access Property List][1020]
**Example:**
```cpp
h5::fapl_t fapl = h5::fclose_degree_weak | h5::fapl_core{2048,1} | h5::core_write_tracking{false,1} 
			| h5::fapl_family{H5F_FAMILY_DEFAULT,0};
			
```
* [`h5::fclose_degree{H5F_close_degree_t}`][1022] Sets the file close degree.<br/>
	**Flags:** `h5::fclose_degree_weak`, `h5::fclose_degree_semi`, `h5::fclose_degree_strong`, `h5::fclose_degree_default`
* [`h5::fapl_core{size_t increment, hbool_t backing_store}`][1023] Modifies the file access property list to use the H5FD_CORE driver.
* [`h5::core_write_tracking{hbool_t is_enabled, size_t page_size}`][1024] Sets write tracking information for core driver, H5FD_CORE. 
* [`h5::fapl_direct{size_t alignment, size_t block_size, size_t cbuf_size}`][1025] Sets up use of the direct I/O driver.
* [`h5::fapl_family{hsize_t memb_size, hid_t memb_fapl_id}`][1026] Sets the file access property list to use the family driver.
* [`h5::family_offset{hsize_t offset}`][1027] Sets offset property for low-level access to a file in a family of files.
* [`h5::fapl_log{const char *logfile, unsigned long long flags, size_t buf_size}`][1028] Sets up the logging virtual file driver (H5FD_LOG) for use.
* [`h5::fapl_mpiio{MPI_Comm comm, MPI_Info info}`][1029] Stores MPI IO communicator information to the file access property list.
* [`h5::multi{const H5FD_mem_t *memb_map, const hid_t *memb_fapl, const char * const *memb_name, const haddr_t *memb_addr, hbool_t relax}`][1030] Sets up use of the multi-file driver.
* [`h5::multi_type{H5FD_mem_t}`][1031] Specifies type of data to be accessed via the MULTI driver, enabling more direct access. <br>
**Flags:** `h5::multi_type_super`, `h5::multi_type_btree`, `h5::multi_type_draw`, `h5::multi_type_gheap`, `h5::multi_type_lheap`, `h5::multi_type_ohdr`
* [`h5::fapl_split{const char *meta_ext, hid_t meta_plist_id, const char *raw_ext, hid_t raw_plist_id}`][1032] Emulates the old split file driver.
* [`h5::sec2`][1033] (flag) Sets the sec2 driver.
* [`h5::stdio`][1034] (flag) Sets the standard I/O driver.
* [`h5::windows`][1035] Not implemented on H5CPP
* [`h5::file_image{void*,size_t}`][1036] Sets an initial file image in a memory buffer.
* [`h5::file_image_callback{H5_file_image_callbacks_t *callbacks_ptr}`][1037] Sets the callbacks for working with file images.
* [`h5::meta_block_size{hsize_t}`][1038] Sets the minimum metadata block size.
* [`h5::page_buffer_size{size_t,unsigned,unsigned}`][1039] Sets the maximum size for the page buffer and the minimum percentage for metadata and raw data pages.
* [`h5::sieve_buf_size{size_t}`][1040] Sets the maximum size of the data sieve buffer.
* [`h5::alignment{hsize_t, hsize_t}`][1041] Sets alignment properties of a file access property list.
* [`h5::cache{int,size_t,size_t,double}`][1042] Sets the raw data chunk cache parameters.
* [`h5::elink_file_cache_size{unsigned}`][1043] Sets the number of files that can be held open in an external link open file cache.
* [`h5::evict_on_close{hbool_t}`][1044] Controls the library's behavior of evicting metadata associated with a closed object
* [`h5::metadata_read_attempts{unsigned}`][1045] Sets the number of read attempts in a file access property list.
* [`h5::mdc_config{H5AC_cache_config_t*}`][1046] Set the initial metadata cache configuration in the indicated File Access Property List to the supplied value.
* [`h5::mdc_image_config{H5AC_cache_image_config_t * config_ptr}`][1047] Sets the metadata cache image option for a file access property list.
* [`h5::mdc_log_options{const char*,hbool_t}`][1048] Sets metadata cache logging options.
* [`h5::all_coll_metadata_ops{hbool_t}`][1049] Sets metadata I/O mode for read operations to collective or independent (default).
* [`h5::coll_metadata_write{hbool_t}`][1050] Sets metadata write mode to collective or independent (default).
* [`h5::gc_references{unsigned}`][1051] H5Pset_gc_references sets the flag for garbage collecting references for the file.
* [`h5::small_data_block_size{hsize_t}`][1052] Sets the size of a contiguous block reserved for small data.
* [`h5::libver_bounds {H5F_libver_t,H5F_libver_t}`][1053] Sets bounds on library versions, and indirectly format versions, to be used when creating objects.
* [`h5::object_flush_cb{H5F_flush_cb_t,void*}`][1054] Sets a callback function to invoke when an object flush occurs in the file.
* **`h5::fapl_rest_vol`** or to request KITA/RestVOL services both flags are interchangeable you only need to specify one of them follow [instructions:][701] to setup RestVOL, once the required modules are included
* **`h5::kita`** same as above


#### [Group Creation Property List][1100]

* [`h5::local_heap_size_hint{size_t}`][1101] Specifies the anticipated maximum size of a local heap.
* [`h5::link_creation_order{unsigned}`][1102] Sets creation order tracking and indexing for links in a group.
* [`h5::est_link_info{unsigned, unsigned}`][1103] Sets estimated number of links and length of link names in a group.
* [`h5::link_phase_change{unsigned, unsigned}`][1104] Sets the parameters for conversion between compact and dense groups. 

#### [Group Access Property List][1200]
* [`local_heap_size_hint{hbool_t is_collective}`][1201] Sets metadata I/O mode for read operations to collective or independent (default).



#### [Link Creation Property List][1300]
* [`h5::char_encoding{H5T_cset_t}`][1301] Sets the character encoding used to encode link and attribute names. <br/>
**Flags:** `h5::utf8`, `h5::ascii`
* [`h5::create_intermediate_group{unsigned}`][1302] Specifies in property list whether to create missing intermediate groups. <br/>
**Flags** `h5::create_path`, `h5::dont_create_path`

#### [Link Access Property List][1400]
* [`h5::nlinks{size_t}`][1401] Sets maximum number of soft or user-defined link traversals.
* [`h5::elink_cb{H5L_elink_traverse_t, void*}`][1402] Sets metadata I/O mode for read operations to collective or independent (default).
* [`h5::elink_fapl{hid_t}`][1403] Sets a file access property list for use in accessing a file pointed to by an external link.
* [`h5::elink_acc_flags{unsigned}`][1403] Sets the external link traversal file access flag in a link access property list.<br/>
**Flags:** 	`h5::acc_rdwr`, `h5::acc_rdonly`, `h5::acc_default`

#### [Dataset Creation Property List][1500]
**Example:**
```cpp
h5::dcpl_t dcpl = h5::chunk{1,4,5} | h5::deflate{4} | h5::layout_compact | h5::dont_filter_partial_chunks
		| h5::fill_value<my_struct>{STR} | h5::fill_time_never | h5::alloc_time_early 
		| h5::fletcher32 | h5::shuffle | h5::nbit;
```
* [`h5::layout{H5D_layout_t layout}`][1501] Sets the type of storage used to store the raw data for a dataset. <br/>
**Flags:** `h5::layout_compact`, `h5::layout_contigous`, `h5::layout_chunked`, `h5::layout_virtual`
* [`h5::chunk{...}`][1502] control chunk size, takes in initializer list with rank matching the dataset dimensions
* [`h5::chunk_opts{unsigned}`][1503] Sets the edge chunk option in a dataset creation property list.<br/>
**Flags:** `h5::dont_filter_partial_chunks`
* [`h5::deflate{0-9}`][1504] | `h5::gzip{0-9}` set deflate compression ratio
* [`h5::fill_value<T>{T* ptr}`][1505] sets fill value
* [`h5::fill_time{H5D_fill_time_t fill_time}`][1506] Sets the time when fill values are written to a dataset.<br/>
**Flags:** `h5::fill_time_ifset`, `h5::fill_time_alloc`, `h5::fill_time_never`
* [`h5::alloc_time{H5D_alloc_time_t alloc_time}`][1507] Sets the timing for storage space allocation.<br/>
**Flags:** `h5::alloc_time_default`, `h5::alloc_time_early`, `h5::alloc_time_incr`, `h5::alloc_time_late`
* [`h5::fletcher32`][1509] Sets up use of the Fletcher32 checksum filter.
* [`h5::nbit`][1510] Sets up the use of the N-Bit filter.
* [`h5::shuffle`][1512] Sets up use of the shuffle filter.

#### [Dataset Access Property List][301]
In addition to CAPI properties, a custom `high_throughput` property is added, to request alternative, simpler but more efficient pipeline.

* `h5::high_throughput` **Sets high throughput H5CPP custom filter chain.** HDF5 library comes with a complex, feature rich environment to index data-sets by strides, blocks, or even by individual coordinates within chunk boundaries - less fortunate the performance impact on throughput.  Setting this flag will replace the built in filter chain with a simpler one (without complex indexing features), then delegates IO calls to the recently introduced [HDF5 Optimized API][400] calls.

	The implementation is based on BLAS level 3 blocking algorithm, supports data access only at chunk boundaries, edges are handled as expected. For maximum throughput place edges at chunk boundaries.

	**Note:** This feature and indexing within a chunk boundary such as `h5::stride` is mutually exclusive.


* `h5::chunk_cache{size_t, size_t, double}` **Sets the raw data chunk cache parameters.** H5Pset_chunk_cache is used to adjust the chunk cache parameters on a per-dataset basis, as opposed to a global setting for the file using H5Pset_cache. The optimum chunk cache parameters may vary widely with different data layout and access patterns, so for optimal performance they must be set individually for each dataset. It may also be beneficial to reduce the size of the chunk cache for datasets whose performance is not important in order to save memory space.<br/>
H5Pset_chunk_cache sets the number of elements, the total number of bytes, and the preemption policy value in the raw data chunk cache on a dataset access property list. After calling this function, the values set in the property list will override the values in the file's file access property list.

	The raw data chunk cache inserts chunks into the cache by first computing a hash value using the address of a chunk, then using that hash value as the chunk's index into the table of cached chunks. The size of this hash table, i.e., and the number of possible hash values, is determined by the rdcc_nslots parameter. If a different chunk in the cache has the same hash value, this causes a collision, which reduces efficiency. If inserting the chunk into cache would cause the cache to be too big, then the cache is pruned according to the rdcc_w0 parameter.

* `h5::efile_prefix{const char*}` **Sets the external dataset storage file prefix in the dataset access property list.** H5Pset_efile_prefix sets the prefix used to locate raw data files for a dataset that uses external storage. This prefix can provide either an absolute path or a relative path to the external files.
H5Pset_efile_prefix is used in conjunction with H5Pset_external to control the behavior of the HDF5 Library when searching for the raw data files associated with a dataset that uses external storage:<br/>
	* The default behavior of the library is to search for the dataset’s external storage raw data files in the same directory as the HDF5 file which contains the dataset.
	* If the prefix is set to an absolute path, the target directory will be searched for the dataset’s external storage raw data files.
	* If the prefix is set to a relative path, the target directory, relative to the current working directory, will be searched for the dataset’s external storage raw data files.
	* If the prefix is set to a relative path that begins with the special token ${ORIGIN}, that directory, relative to the HDF5 file containing the dataset, will be searched for the dataset’s external storage raw data files

	The HDF5_EXTFILE_PREFIX environment variable can be used to override the above behavior (the environment variable supersedes the API call). Setting the variable to a path string and calling H5Dcreate or H5Dopen is the equivalent of calling H5Pset_efile_prefix and calling the same create or open function. The environment variable is checked at the time of the create or open action and copied so it can be safely changed after the H5Dcreate or H5Dopen call.

	Calling H5Pset_efile_prefix with prefix set to NULL or the empty string returns the search path to the default. The result would be the same as if H5Pset_efile_prefix had never been called.

	**Notes:** If the external file prefix is not an absolute path and the HDF5 file is moved, the external storage files will also need to be moved so they can be accessed at the new location.
As stated above, the use of the HDF5_EXTFILE_PREFIX environment variable overrides any property list setting. H5Pset_efile_prefix and H5Pget_efile_prefix, being property functions, set and retrieve only the property list setting; they are unaware of the environment variable.

	On Windows, the prefix must be an ASCII string since the Windows standard C library’s I/O functions cannot handle UTF-8 file names

* `h5::virtual_view{H5D_vds_view_t}` **Sets the view of the virtual dataset (VDS) to include or exclude missing mapped elements.** H5Pset_virtual_view takes the access property list for the virtual dataset, dapl_id, and the flag, view, and sets the VDS view according to the flag value. If view is set to H5D_VDS_FIRST_MISSING, the view includes all data before the first missing mapped data. This setting provides a view containing only the continuous data starting with the dataset’s first data element. Any break in continuity terminates the view. If view is set to H5D_VDS_LAST_AVAILABLE, the view includes all available mapped data. Missing mapped data is filled with the fill value set in the VDS creation property list.

* `h5::virtual_printf_gap{hsize_t}` **Sets the maximum number of missing source files and/or datasets with the printf-style names when getting the extent of an unlimited virtual dataset.** 5Pset_virtual_printf_gap sets the access property list for the virtual dataset, dapl_id, to instruct the library to stop looking for the mapped data stored in the files and/or datasets with the printf-style names after not finding gap_size files and/or datasets. The found source files and datasets will determine the extent of the unlimited virtual dataset with the printf-style mappings.
	Consider the following examples where the regularly spaced blocks of a virtual dataset are mapped to datasets with the names d-1, d-2, d-3, ..., d-N, ... :

	* If the dataset d-2 is missing and gap_size is set to 0, then the virtual dataset will contain only data found in d-1.
	* If d-2 and d-3 are missing and gap_size is set to 2, then the virtual dataset will contain the data from d-1, d-3, ..., d-N, ... .  The blocks that are mapped to d-2 and d-3 will be filled according to the virtual dataset’s fill value setting.



#### [Dataset Transfer Property List][305]

* `h5::buffer{size_t, void*, void*}` **Sets type conversion and background buffers.** Given a dataset transfer property list, H5Pset_buffer sets the maximum size for the type conversion buffer and background buffer and optionally supplies pointers to application-allocated buffers. If the buffer size is smaller than the entire amount of data being transferred between the application and the file, and a type conversion buffer or background buffer is required, then strip mining will be used.

	Note that there are minimum size requirements for the buffer. Strip mining can only break the data up along the first dimension, so the buffer must be large enough to accommodate a complete slice that encompasses all of the remaining dimensions. For example, when strip mining a 100x200x300 hyperslab of a simple data space, the buffer must be large enough to hold 1x200x300 data elements. When strip mining a 100x200x300x150 hyperslab of a simple data space, the buffer must be large enough to hold 1x200x300x150 data elements.

	If tconv and/or bkg are null pointers, then buffers will be allocated and freed during the data transfer. The default value for the maximum buffer is 1 Mb.

* `h5::edc_check{H5Z_EDC_t}` **Sets whether to enable error-detection when reading a dataset.** H5Pset_edc_check sets the dataset transfer property list plist to enable or disable error detection when reading data. Whether error detection is enabled or disabled is specified in the check parameter. Valid values are as follows:
	* H5Z_ENABLE_EDC   (default)
	* H5Z_DISABLE_EDC

	The error detection algorithm used is the algorithm previously specified in the corresponding dataset creation property list. This function does not affect the use of error detection when writing data.
	
	**Note:** The initial error detection implementation, Fletcher32 checksum, supports error detection for chunked datasets only.
	The Fletcher32 EDC checksum filter, set with H5Pset_fletcher32, was added in HDF5 Release 1.6.0. In the original implementation, however, the checksum value was calculated incorrectly on little-endian systems. The error was fixed in HDF5 Release 1.6.3.

	As a result of this fix, an HDF5 Library of Release 1.6.0 through Release 1.6.2 cannot read a dataset created or written with Release 1.6.3 or later if the dataset was created with the checksum filter and the filter is enabled in the reading library. (Libraries of Release 1.6.3 and later understand the earlier error and comensate appropriately.)

	**Work-around:** An HDF5 Library of Release 1.6.2 or earlier will be able to read a dataset created or written with the checksum filter by an HDF5 Library of Release 1.6.3 or later if the checksum filter is disabled for the read operation. This can be accomplished via an H5Pset_edc_check call with the value H5Z_DISABLE_EDC in the second parameter. This has the obvious drawback that the application will be unable to verify the checksum, but the data does remain accessible.

* [`h5::filter_callback`](https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFilterCallback) **Sets user-defined filter callback function**

```cpp
using filter_callback          = impl::dxpl_call< impl::dxpl_args<hid_t,H5Z_filter_func_t,void*>,H5Pset_filter_callback>;
using data_transform           = impl::dxpl_call< impl::dxpl_args<hid_t,const char *>,H5Pset_data_transform>;
using type_conv_cb             = impl::dxpl_call< impl::dxpl_args<hid_t,H5T_conv_except_func_t,void*>,H5Pset_type_conv_cb>;
using hyper_vector_size        = impl::dxpl_call< impl::dxpl_args<hid_t,size_t>,H5Pset_hyper_vector_size>;
using btree_ratios             = impl::dxpl_call< impl::dxpl_args<hid_t,double,double,double>,H5Pset_btree_ratios>;
```

#### [Object Creation Property List][308]
```cpp
using ocreate_intermediate_group = impl::ocrl_call< impl::ocrl_args<hid_t,unsigned>,H5Pset_create_intermediate_group>;
using obj_track_times            = impl::ocrl_call< impl::ocrl_args<hid_t,hbool_t>,H5Pset_obj_track_times>;
using attr_phase_change          = impl::ocrl_call< impl::ocrl_args<hid_t,unsigned,unsigned>,H5Pset_attr_phase_change>;
using attr_creation_order        = impl::ocrl_call< impl::ocrl_args<hid_t,unsigned>,H5Pset_attr_creation_order>;
```

#### [Object Copy Property List][309]
```cpp
using copy_object                = impl::ocpl_call< impl::ocpl_args<hid_t,unsigned>,H5Pset_copy_object>;
using mcdt_search_cb             = impl::ocpl_call< impl::ocpl_args<hid_t,H5O_mcdt_search_cb_t,void*>,H5Pset_mcdt_search_cb>;
const static h5::copy_object shallow_hierarchy{H5O_COPY_SHALLOW_HIERARCHY_FLAG};
const static h5::copy_object expand_soft_link{H5O_COPY_EXPAND_SOFT_LINK_FLAG};
const static h5::copy_object expand_ext_link{H5O_COPY_EXPAND_EXT_LINK_FLAG};
const static h5::copy_object expand_reference{H5O_COPY_EXPAND_REFERENCE_FLAG};
const static h5::copy_object copy_without_attr{H5O_COPY_WITHOUT_ATTR_FLAG};
const static h5::copy_object merge_commited_dtype{H5O_COPY_MERGE_COMMITTED_DTYPE_FLAG};
```
#### MPI Parallel HDF5 related properties
```cpp
using fapl_mpiio                 = impl::fapl_call< impl::fapl_args<hid_t,MPI_Comm, MPI_Info>,H5Pset_fapl_mpio>;
using all_coll_metadata_ops      = impl::fapl_call< impl::fapl_args<hid_t,hbool_t>,H5Pset_all_coll_metadata_ops>;
using coll_metadata_write        = impl::fapl_call< impl::fapl_args<hid_t,hbool_t>,H5Pset_coll_metadata_write>;
using gc_references              = impl::fapl_call< impl::fapl_args<hid_t,unsigned>,H5Pset_gc_references>;
using small_data_block_size      = impl::fapl_call< impl::fapl_args<hid_t,hsize_t>,H5Pset_small_data_block_size>;
using object_flush_cb            = impl::fapl_call< impl::fapl_args<hid_t,H5F_flush_cb_t,void*>,H5Pset_object_flush_cb>;

using fapl_coll_metadata_ops     = impl::fapl_call< impl::fapl_args<hid_t,hbool_t>,H5Pset_all_coll_metadata_ops>; // file
using gapl_coll_metadata_ops     = impl::gapl_call< impl::gapl_args<hid_t,hbool_t>,H5Pset_all_coll_metadata_ops>; // group 
using dapl_coll_metadata_ops     = impl::gapl_call< impl::dapl_args<hid_t,hbool_t>,H5Pset_all_coll_metadata_ops>; // dataset
using tapl_coll_metadata_ops     = impl::tapl_call< impl::tapl_args<hid_t,hbool_t>,H5Pset_all_coll_metadata_ops>; // type 
using lapl_coll_metadata_ops     = impl::lapl_call< impl::lapl_args<hid_t,hbool_t>,H5Pset_all_coll_metadata_ops>; // link
using aapl_coll_metadata_ops     = impl::gapl_call< impl::gapl_args<hid_t,hbool_t>,H5Pset_all_coll_metadata_ops>; // attribute

using dxpl_mpiio                 = impl::dxpl_call< impl::dxpl_args<hid_t,H5FD_mpio_xfer_t>,H5Pset_dxpl_mpio>;
using dxpl_mpiio_chunk_opt       = impl::dxpl_call< impl::dxpl_args<hid_t,H5FD_mpio_chunk_opt_t>,H5Pset_dxpl_mpio_chunk_opt>;
using dxpl_mpiio_chunk_opt_num   = impl::dxpl_call< impl::dxpl_args<hid_t,unsigned>,H5Pset_dxpl_mpio_chunk_opt_num>;
using dxpl_mpiio_chunk_opt_ratio = impl::dxpl_call< impl::dxpl_args<hid_t,unsigned>,H5Pset_dxpl_mpio_chunk_opt_ratio>;
using dxpl_mpiio_collective_opt  = impl::dxpl_call< impl::dxpl_args<hid_t,H5FD_mpio_collective_opt_t>,H5Pset_dxpl_mpio_collective_opt>;
//TODO; verify * -> ref?
using dxpl_mpiio                 = impl::dxpl_call< impl::dxpl_args<hid_t,H5FD_mpio_xfer_t>,H5Pset_dxpl_mpio>;

using mpiio = fapl_mpiio;
const static h5::dxpl_mpiio collective{H5FD_MPIO_COLLECTIVE};
const static h5::dxpl_mpiio independent{H5FD_MPIO_INDEPENDENT};
```


#### Default Properties
```cpp
const static h5::acpl_t acpl = static_cast<h5::acpl_t>( H5P_DEFAULT );
const static h5::dcpl_t dcpl = static_cast<h5::dcpl_t>( H5P_DEFAULT);
const static h5::dxpl_t dxpl = static_cast<h5::dxpl_t>( H5P_DEFAULT );
const static h5::lcpl_t lcpl = h5::char_encoding{H5T_CSET_UTF8} | h5::create_intermediate_group{1};
const static h5::fapl_t fapl = static_cast<h5::fapl_t>( H5P_DEFAULT );
const static h5::fcpl_t fcpl = static_cast<h5::fcpl_t>( H5P_DEFAULT );

const static h5::acpl_t default_acpl = static_cast<h5::acpl_t>( H5P_DEFAULT );
const static h5::dcpl_t default_dcpl = static_cast<h5::dcpl_t>( H5P_DEFAULT );
const static h5::dxpl_t default_dxpl = static_cast<h5::dxpl_t>( H5P_DEFAULT );
const static h5::lcpl_t default_lcpl = h5::char_encoding{H5T_CSET_UTF8} | h5::create_intermediate_group{1};
const static h5::fapl_t default_fapl = static_cast<h5::fapl_t>( H5P_DEFAULT );
const static h5::fcpl_t default_fcpl = static_cast<h5::fcpl_t>( H5P_DEFAULT );
```



## C++ Idioms


### RAII 

There are c++ mapping for  `hid_t` id-s which reference objects with `std::shared_ptr` type of behaviour with HDF5 CAPI internal reference
counting. For further details see [H5inc_ref][1], [H5dec_ref][2] and [H5get_ref][3]. The internal representation of these objects is binary compatible of the CAPI hid_t and interchangeable depending on the conversion policy:
	`H5_some_function( static_cast<hid_t>( h5::hid_t id ), ...   )`
Direct initialization `h5::ds_t{ some_hid }` bypasses reference counting, and is intended to for use case where you have to take ownership
of a CAPI hid_t object reference. This is equivalent behaviour to `std::shared_ptr`, when object destroyed reference count is decreased.
```cpp
{
	h5::ds_t ds = h5::open( ... ); 
} // resources are guaranteed to be released
```

### Error handling 

Error handling follows the C++ [Guidline][11] and the philosophy H5CPP library is built around, that is to  help you to start without reading much of the documentation, and providing ample of room for more should you require it. The root of exception tree is: `h5::error::any` derived from std::`runtime_exception` in accordance with C++ guidelines [custom exceptions][12]. 
All HDF5 CAPI calls are considered as resource, and in case of error H5CPP aims to roll back to last known stable state, cleaning up all resource allocations between the call entry and thrown error. This mechanism is guaranteed by RAII. 

For granularity `io::[file|dataset|attribute]` exceptions provided, with the pattern to capture the entire subset by `::any`.
Exceptions thrown with error massages  \__FILE\__ and \__LINE\__ relevant to H5CPP template library with a brief description to help the developer to investigate. This error reporting mechanism uses a macro found inside **h5cpp/config.h** and maybe redefined:
```cpp
	...
// redefine macro before including <h5cpp/ ... >
#define H5CPP_ERROR_MSG( msg ) "MY_ERROR: " 
	+ std::string( __FILE__ ) + " this line: " + std::to_string( __LINE__ ) + " message-not-used"
#include <h5cpp/all> 
	...
```
An example to capture and handle errors centrally:
```cpp
	// some H5CPP IO routines used in your software
	void my_deeply_embedded_io_calls() {
		arma::mat M = arma::zeros(20,4);
		// compound IO operations in single call: 
		//     file create, dataset create, dataset write, dataset close, file close
		h5::write("report.h5","matrix.ds", M ); 
	}

	int main() {
		// capture errors centrally with the granularity you desire
		try {
			my_deeply_embedded_io_calls();		
		} catch ( const h5::error::io::dataset::create& e ){
			// handle file creation error
		} catch ( const h5::error::io::dataset::write& e ){
		} catch ( const h5::error::io::file::create& e ){
		} catch ( const h5::error::io::file::close& e ){
		} catch ( const h5::any& e ) {
			// print out internally generated error message, controlled by H5CPP_ERROR_MSG macro
			std::cerr << e.what() << std::endl;
		}
	}
```
Detailed CAPI error stack may be unrolled and dumped, muted, unmuted with provided methods:

* `h5::mute`   - saves current HDF5 CAPI error handler to thread local storage and replaces it with NULL handler, getting rid of all error messages produced by CAPI. CAVEAT: lean and mean, therefore no nested calls are supported. Should you require more sophisticated handler keep reading on.
* `h5::unmute` - restores previously saved error handler, error messages are handled according to previous handler.

usage:
```cpp
	h5::mute();
	 // ... prototyped part with annoying messages
	 // or the entire application ...
	h5::unmute(); 
```

* `h5::use_errorhandler()` - captures ALL CAPI error messages into thread local storage, replacing current CAPI error handler
comes handy when you want to provide details of error happened. 

`std::stack<std::string> h5::error_stack()` - walks through underlying CAPI error handler

usage:
```cpp
	int main( ... ) {
		h5::use_error_handler();
		try {
			... rest of the [ single | multi ] threaded application
		} catch( const h5::read_error& e  ){
			std::stack<std::string> msgs = h5::error_stack();
			for( auto msg: msgs )
				std::cerr << msg << std::endl;
		} catch( const h5::write_error& e ){
		} catch( const h5::file_error& e){
		} catch( ... ){
			// some other errors
		}
	}
```

**Design criteria**
- All HDF5 CAPI calls are checked with the only exception of `H5Lexists` where the failure carries information, that the path does not exist yet. 
- Callbacks of CAPI routines doesn't throw any exceptions, honoring the HDF5 CAPI contract, hence allowing the CAPI call to clean up
- Error messages currently are collected in `H5Eall.hpp` may be customized
- Thrown exceptions are hierarchical
- Only RAII capable/wrapped objects used, guaranteed cleanup through stack unrolling

Exception hierarchy is embedded in namespaces, the chart should be interpreted as tree, for instance a file create exception is
`h5::error::io::file::create`. Keep in mind [namespace aliasing][3] allow you customization should you find the long names inconvenient:
```cpp
using file_error = h5::error::io::file
try{
} catch ( const file_error::create& e ){
	// do-your-thing(tm)
}

```
<pre>
h5::error : public std::runtime_error
  ::any               - captures ALL H5CPP runtime errors with the exception of `rollback`
  ::io::              - namespace: IO related error, see aliasing
  ::io::any           - collective capture of IO errors within this namespace/block recursively
      ::file::        - namespace: file related errors
	        ::any     - captures all exceptions within this namespace/block
            ::create  - create failed
			::open    - check if the object, in this case file exists at all, retry if networked resource
			::close   - resource may have been removed since opened
			::read    - may not be fixed, should software crash crash?
			::write   - is it read only? is recource still available since opening? 
			::misc    - errors which are not covered otherwise: start investigating from reported file/line
       ::dataset::    -
			::any
			::create
			::open
			::close
			::read
			::write
			::append
			::misc
      ::attribute::
			::any
			::create
			::open
			::close
			::read
			::write
			::misc
    ::property_list::
	  ::rollback
      ::any
	  ::misc
	  ::argument
</pre>

This is a work in progress, if for any reasons you think it could be improved, or some real life scenario is not represented please shoot me an email with the use case, a brief working example.


### Diagnostics  
On occasions it comes handy to dump internal state of objects, while currently only `h5::sp_t` data-space descriptor and dimensions supported
in time most of HDF5 CAPI diagnostics/information calls will be added.

```cpp
	h5::ds_t ds =  ... ; 				// obtained by h5::open | h5::create call
	h5::sp_t sp = h5::get_space( ds );  // get the file space descriptor for hyperslab selection
	h5::select_hyperslab(sp,  ... );    // some complicated selection that may fail, and you want to debug
	std::cerr << sp << std::endl;       // prints out the available space
	try { 
		H5Dwrite(ds, ... );            // direct CAPI call fails for with invalid selection
	catch( ... ){
	}
```

### stream operators
Some objects implement `operator<<` to furnish you with diagnostics. In time all objects will the functionality added, for now
only the following objects:

* h5::current_dims_t
* h5::max_dim_t
* h5::chunk_t
* h5::offset_t
* h5::stride_t
* h5::count_t
* h5::block_t
* h5::dims_t
* h5::dt_t
* h5::pt_t
* h5::sp_t
* h5::


### Custom Filter Pipeline
To Be Written

### Performance
|    experiment                               | time  | trans/sec | Mbyte/sec |
|:--------------------------------------------|------:|----------:|----------:|
|append:  1E6 x 64byte struct                 |  0.06 |   16.46E6 |   1053.87 |
|append: 10E6 x 64byte struct                 |  0.63 |   15.86E6 |   1015.49 |
|append: 50E6 x 64byte struct                 |  8.46 |    5.90E6 |    377.91 |
|append:100E6 x 64byte struct                 | 24.58 |    4.06E6 |    260.91 |
|write:  Matrix<float> [10e6 x  16] no-chunk  |  0.4  |    0.89E6 |   1597.74 |
|write:  Matrix<float> [10e6 x 100] no-chunk  |  7.1  |    1.40E6 |    563.36 |

Lenovo 230 i7 8G ram laptop on Linux Mint 18.1 system

**gprof** directory contains [gperf][1] tools base profiling. `make all` will compile files.
In order to execute install  `google-pprof` and `kcachegrind`.

[create]: index.md#create
[read]:   index.md#read
[write]:  index.md#write
[append]: index.mdappend
[compiler]: compiler.md
[copy_elision]: https://en.cppreference.com/w/cpp/language/copy_elision
[csr]: https://en.wikipedia.org/wiki/Sparse_matrix#Compressed_sparse_row_(CSR,_CRS_or_Yale_format)
[csc]: https://en.wikipedia.org/wiki/Sparse_matrix#Compressed_sparse_column_(CSC_or_CCS)

[1]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5I.html#Identify-IncRef
[2]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5I.html#Identify-DecRef
[3]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5I.html#Identify-GetRef

[11]: https://github.com/isocpp/CppCoreGuidelines/blob/master/CppCoreGuidelines.md#S-errors
[12]: https://github.com/isocpp/CppCoreGuidelines/blob/master/CppCoreGuidelines.md#Re-exception-types
[13]: https://en.cppreference.com/w/cpp/language/namespace_alias


[99]: https://en.wikipedia.org/wiki/C_(programming_language)#Pointers
[100]: http://arma.sourceforge.net/
[101]: http://www.boost.org/doc/libs/1_66_0/libs/numeric/ublas/doc/index.html
[102]: http://eigen.tuxfamily.org/index.php?title=Main_Page#Documentation
[103]: https://sourceforge.net/projects/blitz/
[104]: https://sourceforge.net/projects/itpp/
[105]: http://dlib.net/linear_algebra.html
[106]: https://bitbucket.org/blaze-lib/blaze
[107]: https://github.com/wichtounet/etl

[200]: https://en.wikipedia.org/wiki/Row-_and_column-major_order
[201]: https://en.wikipedia.org/wiki/Row-_and_column-major_order#Transposition
[300]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#FileCreatePropFuncs
[301]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#DatasetAccessPropFuncs
[302]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#GroupCreatePropFuncs
[303]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#DatasetCreatePropFuncs
[304]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#DatasetAccessPropFuncs
[305]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#DatasetTransferPropFuncs
[306]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#LinkCreatePropFuncs
[307]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#LinkAccessPropFuncs
[308]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#ObjectCreatePropFuncs
[309]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#ObjectCopyPropFuncs

[400]: https://support.hdfgroup.org/HDF5/doc/HL/RM_HDF5Optimized.html

[1000]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#FileCreatePropFuncs
[1001]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetUserblock
[1002]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetSizes
[1003]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetSymK
[1004]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetIstoreK
[1005]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFileSpacePageSize
[1006]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFileSpaceStrategy
[1007]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetSharedMesgNIndexes
[1008]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetSharedMesgIndex
[1009]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetSharedMesgPhaseChange

[1020]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#FileAccessPropFuncs
[1021]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetDriver
[1022]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFcloseDegree
[1023]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFaplCore
[1024]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetCoreWriteTracking
[1025]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFaplDirect
[1026]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFaplFamily
[1027]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFamilyOffset
[1028]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFaplLog
[1029]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFaplMpio
[1030]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFaplMulti
[1031]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetMultiType
[1032]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFaplSplit
[1033]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFaplSec2
[1034]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFaplStdio
[1035]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFaplWindows
[1036]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFileImage
[1037]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFileImageCallbacks
[1038]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetMetaBlockSize
[1039]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetPageBufferSize
[1040]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetSieveBufSize
[1041]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetAlignment
[1042]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetCache
[1043]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetELinkFileCacheSize
[1044]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetEvictOnClose
[1045]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetMetadataReadAttempts
[1046]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetMdcConfig
[1047]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetMDCImageConfig
[1048]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetMdcLogOptions
[1049]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetAllCollMetadataOps
[1050]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetCollMetadataWrite
[1051]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetGCReferences
[1052]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetSmallData
[1053]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetLibverBounds
[1054]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetObjectFlushCb

[1100]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#GroupCreatePropFuncs
[1101]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetLocalHeapSizeHint
[1102]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetLinkCreationOrder
[1103]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetEstLinkInfo
[1104]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetLinkPhaseChange

[1200]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#GroupAccessPropFuncs
[1201]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetAllCollMetadataOps 

[1300]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#LinkCreatePropFuncs
[1301]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetCharEncoding
[1302]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetCreateIntermediateGroup

[1400]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#LinkAccessPropFuncs
[1401]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetNLinks
[1402]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetAllCollMetadataOps
[1403]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetELinkCb
[1404]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetELinkPrefix
[1405]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetELinkFapl
[1406]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetELinkAccFlags

[1500]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#DatasetCreatePropFuncs 
[1501]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetLayout
[1502]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetChunk
[1503]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetChunkOpts
[1504]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetDeflate 
[1505]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFillValue
[1506]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFillTime 
[1507]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetAllocTime
[1508]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFilter 
[1509]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetFletcher32
[1510]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetNbit 
[1511]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetScaleoffset
[1512]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetShuffle
[1513]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#Property-SetSzip

[601]: #file-creation-property-list
[602]: #file-access-property-list
[603]: #link-creation-property-list
[604]: #dataset-creation-property-list
[605]: #dataset-access-property-list
[606]: #dataset-transfer-property-list

[700]: http://man7.org/linux/man-pages/man2/fcntl.2.html
[701]: https://bitbucket.hdfgroup.org/users/jhenderson/repos/rest-vol/browse
