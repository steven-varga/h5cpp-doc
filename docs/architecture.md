
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

#### CREATE
The [previous section](#pythonic-syntax) explained the EBNF tokens: `file`,`dataspace`, the token `flags:==H5F_ACC_EXCL | H5F_ACC_DEBUG` provides control how the HDF5 container. The behaviour of the objects are controlled through property lists and the syntax is rather simple:
```cpp
[file]
h5::fd_t create( const std::string& path, unsigned flags
			[, const h5::fcpl_t& fcpl] [, const h5::fapl_t& fapl]);
[dataset]
template <typename T> h5::ds_t create<T>( file, const std::string& dataset_path, dataspace, 
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
template <typename T> T read( dataset
	[, const h5::offset_t& offset]  [, const h5::stride_t& stride] [, const h5::count_t& count]
	[, const h5::dxpl_t& dxpl ] ) const;
template <typename T> h5::err_t read( dataset, T& ref 
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
template <typename T> h5::err_t write( dataset,  const T& ref
	[,const h5::offset_t& offset] [,const h5::stride_t& stride]  [,const& h5::dxcpl_t& dxpl] );
template <typename T> h5::err_t write( dataset, const T* ptr
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




#### [File Creation Property List][300]
```cpp
// flags := H5F_ACC_TRUNC | H5F_ACC_EXCL either to truncate or open file exclusively
// you may pass CAPI property list descriptors daisy chained with '|' operator 
auto fd = h5::create("002.h5", H5F_ACC_TRUNC, 
		h5::file_space_page_size{4096} | h5::userblock{512},  // file creation properties
		h5::fclose_degree_weak | h5::fapl_core{2048,1} );     // file access properties
```


* `h5::userblock{hsize_t}` **sets the user block size of a file creation property list.** The default user block size is 0; it may be set to any power of 2 equal to 512 or greater (512, 1024, 2048, etc.).

* `h5::istore_k{unsigned}` **Sets the size of the parameter used to control the B-trees for indexing chunked dataset.** 
H5Pset_istore_k sets the size of the parameter used to control the B-trees for indexing chunked datasets. This function is valid only for file creation property lists. ik is one half the rank of a tree that stores chunked raw data. On average, such a tree will be 75% full, or have an average rank of 1.5 times the value of ik. The HDF5 library uses (ik*2) as the maximum # of entries before splitting a B-tree node. Since only 2 bytes are used in storing # of entries for a B-tree node in an HDF5 file, (ik*2) cannot exceed 65536. The default value for ik is 32.

* `h5::file_space_page_size{hsize_t}` **Sets the file space page size for a file creation property list.** H5Pset_file_space_page_size sets the file space page size fsp_size used in paged aggregation and paged buffering. fsp_size has a minimum size of 512. Setting a value less than 512 will return an error. The library default size for the file space page size when not set is 4096. The size set via this routine may not be changed for the life of the file.

* `h5::shared_mesg_nindexes{unsigned}` **Sets number of shared object header message indexes.** H5Pset_shared_mesg_nindexes sets the number of shared object header message indexes in the specified file creation property list. This setting determines the number of shared object header message indexes that will be available in files created with this property list. These indexes can then be configured with 5Pset_shared_mesg_index.
If nindexes is set to 0 (zero), shared object header messages are disabled in files created with this property list.

* `h5::sizes{size_t,size_t}` **Sets the byte size of the offsets and lengths used to address objects in an HDF5 file.** H5Pset_sizes sets the byte size of the offsets and lengths used to address objects in an HDF5 file. This function is only valid for file creation property lists. Passing in a value of 0 for one of the sizeof_... parameters retains the current value. The default value for both values is the same as sizeof(hsize_t) in the library (normally 8 bytes). Valid values currently are 2, 4, 8 and 16.

* `h5::sym_k{unsigned,unsigned}` **Sets the size of parameters used to control the symbol table nodes.** H5Pset_sym_k sets the size of parameters used to control the symbol table nodes.
This function is valid only for file creation property lists. Passing in a value of zero (0) for one of the parameters retains the current value.
ik is one half the rank of a B-tree that stores a symbol table for a group. Internal nodes of the symbol table are on average 75% full. That is, the average rank of the tree is 1.5 times the value of ik. The HDF5 library uses (ik*2) as the maximum # of entries before splitting a B-tree node. Since only 2 bytes are used in storing # of entries for a B-tree node in an HDF5 file, (ik*2) cannot exceed 65536. The default value for ik is 16.
lk is one half of the number of symbols that can be stored in a symbol table node. A symbol table node is the leaf of a symbol table tree which is used to store a group. When symbols are inserted randomly into a group, the group's symbol table nodes are 75% full on average. That is, they contain 1.5 times the number of symbols specified by lk. The default value for lk is 4.

* `h5::shared_mesg_index{unsigned,unsigned,unsigned}` **Configures the specified shared object header message index.**
H5Pset_shared_mesg_index is used to configure the specified shared object header message index, setting the types of messages that may be stored in the index and the minimum size of each message. fcpl_id specifies the file creation property list. index_num specifies the index to be configured. index_num is zero-indexed, so in a file with three indexes, they will be numbered 0, 1, and 2.
mesg_type_flags and min_mesg_size specify, respectively, the types and minimum size of messages that can be stored in this index.

Valid message types are as follows:
```
H5O_SHMESG_NONE_FLAG	No shared messages
H5O_SHMESG_SDSPACE_FLAG    	Simple dataspace message
H5O_SHMESG_DTYPE_FLAG	Datatype message
H5O_SHMESG_FILL_FLAG	Fill value message
H5O_SHMESG_PLINE_FLAG	Filter pipeline message
H5O_SHMESG_ATTR_FLAG	Attribute message
H5O_SHMESG_ALL_FLAG	All message types; i.e., equivalent to the following:
(H5O_SHMESG_SDSPACE_FLAG | H5O_SHMESG_DTYPE_FLAG | H5O_SHMESG_FILL_FLAG 
	| H5O_SHMESG_PLINE_FLAG | H5O_SHMESG_ATTR_FLAG)
```

* `h5::shared_mesg_phase_change{unsigned,unsigned}` **Sets shared object header message storage phase change thresholds.** H5Pset_shared_mesg_phase_change sets threshold values for storage of shared object header message indexes in a file. These phase change thresholds determine the point at which the index storage mechanism changes from a more compact list format to a more performance-oriented B-tree format, and vice-versa.
By default, a shared object header message index is initially stored as a compact list. When the number of messages in an index exceeds the threshold value of max_list, storage switches to a B-tree for improved performance. If the number of messages subsequently falls below the min_btree threshold, the index will revert to the list format.
If max_list is set to 0 (zero), shared object header message indexes in the file will be created as B-trees and will never revert to lists.
fcpl_id specifies the file creation property list.



#### [File Access Property List][301]
**Example:**
```cpp
h5::fapl_t fapl = h5::fclose_degree_weak | h5::fapl_core{2048,1} | h5::core_write_tracking{false,1} 
			| h5::fapl_family{H5F_FAMILY_DEFAULT,0} ;
```
**Preset Values (flags):**

* `h5::sec2`, `h5::stdio` **selects file driver**
* `h5::fclose_degree_weak`, `h5::fclose_degree_semi`, `h5::fclose_degree_strong`, `h5::fclose_degree_default` **Sets the file close degree.** H5Pset_fclose_degree sets the file close degree property fc_degree in the file access property list fapl_id.
The value of fc_degree determines how aggressively H5Fclose deals with objects within a file that remain open when H5Fclose is called to close that file.
* `h5::latest_version` **to set HDF5 API version to latest**

**MPI-IO** The following properties are for parallel HDF5 running on HPC clusters / super computers:

* `h5::fapl_mpiio{MPI_Comm, MPI_Info}` **Stores MPI IO communicator information to the file access property list.**
	H5Pset_fapl_mpio stores the user-supplied MPI IO parameters comm, for communicator, and info, for information, in the file access property list fapl_id. That property list can then be used to create and/or open a file. H5Pset_fapl_mpio is available only in the parallel HDF5 library and is not a collective function. If the file access property list already contains previously-set communicator and Info values, those values will be replaced and the old communicator and Info object will be freed.
	* comm is the MPI communicator to be used for file open, as defined in MPI_FILE_OPEN of MPI-2. This function makes a duplicate of the communicator, so modifications to comm after this function call returns have no effect on the file access property list.
	* info is the MPI Info object to be used for file open, as defined in MPI_FILE_OPEN of MPI-2. This function makes a duplicate copy of the Info object, so modifications to the Info object after this function call returns will have no effect on the file access property list.

* `h5::all_coll_metadata_ops{hbool_t}` **Sets metadata I/O mode for read operations to collective or independent (default).**
H5Pset_all_coll_metadata_ops sets the metadata I/O mode for read operations in the access property list accpl.
When engaging in parallel I/O, all metadata write operations must be collective. If is_collective is TRUE, this property specifies that the HDF5 Library will perform all metadata read operations collectively; if is_collective is FALSE, such operations may be performed independently.
Users must be aware that several HDF5 operations can potentially issue metadata reads. These include opening a dataset, datatype, or group; reading an attribute; or issuing a get info call such as getting information for a group with H5Gget_info. Collective I/O requirements must be kept in mind when issuing such calls in the context of parallel I/O.
If this property is set to true on a file access property list that is used in creating or opening a file, then the HDF5 Library will assume that all metadata read operations issued on that file identifier will be issued collectively from all ranks irrespective of the individual setting of a particular operation. If this assumption is not adhered to, corruption will be introduced in the metadata cache and HDF5’s behavior will be undefined.
Alternatively, a user may wish to avoid setting this property globally on the file access property list, and individually set it on particular object access property lists (dataset, group, link, datatype, attribute access property lists) for certain operations. This will indicate that only the operations issued with such an access property list will be called collectively and other operations may potentially be called independently. There are, however, several HDF5 operations that can issue metadata reads but have no property list in their function signatures to allow passing the collective requirement property. For those operations, the only option is to set the global collective requirement property on the file access property list; otherwise the metadata reads that can be triggered from those operations will be done independently by each process.
Functions that do not accommodate an access property list but that might issue metadata reads are listed in “Functions with No Access Property List Parameter that May Generate Metadata Reads.”

* `h5::coll_metadata_write{hbool_t}` **Sets metadata write mode to collective or independent (default).**
H5Pset_coll_metadata_write tells the HDF5 Library whether to perform metadata writes collectively (TRUE) or independently (FALSE).
If collective access is selected, then on a flush of the metadata cache, all processes will divide the metadata cache entries to be flushed evenly among themselves and issue a single MPI-IO collective write operation. This is the preferred method when the size of the metadata created by the application is large.
If independent access is selected, the library uses the default method for doing metadata I/O either from process zero or independently from each process.

* `h5::fapl_coll_metadata_ops{}` **Sets metadata I/O mode for read operations to collective or independent (default).**
H5Pset_all_coll_metadata_ops sets the metadata I/O mode for read operations in the access property list accpl.
When engaging in parallel I/O, all metadata write operations must be collective. If is_collective is TRUE, this property specifies that the HDF5 Library will perform all metadata read operations collectively; if is_collective is FALSE, such operations may be performed independently.
<br/> Users must be aware that several HDF5 operations can potentially issue metadata reads. These include opening a dataset, datatype, or group; reading an attribute; or issuing a get info call such as getting information for a group with H5Gget_info. Collective I/O requirements must be kept in mind when issuing such calls in the context of parallel I/O.<br/>
If this property is set to true on a file access property list that is used in creating or opening a file, then the HDF5 Library will assume that all metadata read operations issued on that file identifier will be issued collectively from all ranks irrespective of the individual setting of a particular operation. If this assumption is not adhered to, corruption will be introduced in the metadata cache and HDF5’s behavior will be undefined.
<br/>Alternatively, a user may wish to avoid setting this property globally on the file access property list, and individually set it on particular object access property lists (dataset, group, link, datatype, attribute access property lists) for certain operations. This will indicate that only the operations issued with such an access property list will be called collectively and other operations may potentially be called independently. There are, however, several HDF5 operations that can issue metadata reads but have no property list in their function signatures to allow passing the collective requirement property. For those operations, the only option is to set the global collective requirement property on the file access property list; otherwise the metadata reads that can be triggered from those operations will be done independently by each process.
<br/>Functions that do not accommodate an access property list but that might issue metadata reads are listed in “Functions with No Access Property List Parameter that May Generate Metadata Reads.”


**KITA S3 Cloud Store** follow [instructions:][701] to setup RestVOL, once the required modules are included, the file access property become available:

* `h5::fapl_rest_vol` or `h5::kita` **to request KITA/RestVOL services** both flags are interchangeable you only need to specify one of them


**Less Frequent Props:**

* `h5::fapl_core{size_t,hbool_t}` **Modifies the file access property list to use the H5FD_CORE driver.** 
H5Pset_fapl_core modifies the file access property list to use the H5FD_CORE driver.
The H5FD_CORE driver enables an application to work with a file in memory, speeding reads and writes as no disk access is made. File contents are stored only in memory until the file is closed. The backing_store parameter determines whether file contents are ever written to disk.
increment specifies the increment by which allocated memory is to be increased each time more memory is required.
While using H5Fcreate to create a core file, if the backing_store is set to 1 (TRUE), the file contents are flushed to a file with the same name as this core file when the file is closed or access to the file is terminated in memory.
The application is allowed to open an existing file with H5FD_CORE driver. While using H5Fopen to open an existing file, if the backing_store is set to 1 and the flags for H5Fopen is set to H5F_ACC_RDWR, any change to the file contents are saved to the file when the file is closed. If backing_store is set to 0 and the flags for H5Fopen is set to H5F_ACC_RDWR, any change to the file contents will be lost when the file is closed. If the flags for H5Fopen is set to H5F_ACC_RDONLY, no change to the file is allowed either in memory or on file.

* `h5::core_write_tracking{hbool_t,size_t}` **Sets write tracking information for core driver, H5FD_CORE.** When a file is created or opened for writing using the core virtual file driver (VFD) with the backing store option turned on, the core driver can be configured to track changes to the file and write out only the modified bytes. This write tracking feature is enabled and disabled with is_enabled. The default setting is that write tracking is disabled, or off. To avoid a large number of small writes, changes can be aggregated into pages of a user-specified size, page_size. Setting page_size to 1 enables tracking with no page aggregation.
The backing store option is set via the function H5Pset_fapl_core.

* `h5::fapl_family{hsize_t}` **Sets the file access property list to use the family driver.** H5Pset_fapl_family sets the file access property list identifier, fapl_id, to use the family driver. memb_size is the size in bytes of each file member. This size will be saved in file when the property list fapl_id is used to create a new file. If fapl_id is used to open an existing file, memb_size has to be equal to the original size saved in file. A failure with an error message indicating the correct member size will be returned if memb_size does not match the size saved. If any user does not know the original size, H5F_FAMILY_DEFAULT can be passed in. The library will retrieve the saved size. memb_fapl_id is the identifier of the file access property list to be used for each family member.

* `h5::family_offset{hsize_t}` **Sets offset property for low-level access to a file in a family of files.** H5Pset_family_offset sets the offset property in the file access property list fapl_id so that the user application can retrieve a file handle for low-level access to a particular member of a family of files. The file handle is retrieved with a separate call to H5Fget_vfd_handle (or, in special circumstances, to H5FDget_vfd_handle; see Virtual File Layer and List of VFL Functions in HDF5 Technical Notes).
The value of offset is an offset in bytes from the beginning of the HDF5 file, identifying a user-determined location within the HDF5 file. The file handle the user application is seeking is for the specific member-file in the associated family of files to which this offset is mapped.
Use of this function is only appropriate for an HDF5 file written as a family of files with the FAMILY file driver.

* `h5::fapl_log{const char*,unsigned long long,size_t}` **Sets up the logging virtual file driver (H5FD_LOG) for use.** H5Pset_fapl_log modifies the file access property list to use the logging driver, H5FD_LOG. The logging virtual file driver (VFD) is a clone of the standard SEC2 (H5FD_SEC2) driver with additional facilities for logging VFD metrics and activity to a file.
logfile is the name of the file in which the logging entries are to be recorded.
The actions to be logged are specified in the parameter flags using the pre-defined constants described in the following table. Multiple flags can be set through the use of a logical OR contained in parentheses. For example, logging read and write locations would be specified as (H5FD_LOG_LOC_READ|H5FD_LOG_LOC_WRITE).

* `h5::multi_type{H5FD_mem_t}` **Specifies type of data to be accessed via the MULTI driver, enabling more direct access.** H5Pset_multi_type sets the type of data property in the file access property list fapl_id.
This setting enables a user application to specify the type of data the application wishes to access so that the application can retrieve a file handle for low-level access to the particular member of a set of MULTI files in which that type of data is stored. The file handle is retrieved with a separate call to H5Fget_vfd_handle (or, in special circumstances, to H5FDget_vfd_handle; see Virtual File Layer and List of VFL Functions in HDF5 Technical Notes).

	```
H5FD_MEM_SUPER	Super block data
H5FD_MEM_BTREE    	B-tree data
H5FD_MEM_DRAW	Dataset raw data
H5FD_MEM_GHEAP	Global heap data
H5FD_MEM_LHEAP	Local Heap data
H5FD_MEM_OHDR	Object header data
	```

* `h5::fapl_split{const char*, hid_t,const char*,hid_t}` **Emulates the old split file driver.** H5Pset_fapl_split is a compatibility function that enables the multi-file driver to emulate the split driver from HDF5 Releases 1.0 and 1.2. The split file driver stored metadata and raw data in separate files but provided no mechanism for separating types of metadata.
fapl_id is a file access property list identifier.
meta_ext is the filename extension for the metadata file. The extension is appended to the name passed to H5FDopen, usually from H5Fcreate or H5Fopen, to form the name of the metadata file. If the string %s is used in the extension, it works like the name generator as in H5Pset_fapl_multi.
meta_plist_id is the file access property list identifier for the metadata file.
raw_ext is the filename extension for the raw data file. The extension is appended to the name passed to H5FDopen, usually from H5Fcreate or H5Fopen, to form the name of the rawdata file. If the string %s is used in the extension, it works like the name generator as in H5Pset_fapl_multi.
raw_plist_id is the file access property list identifier for the raw data file.
If a user wishes to check to see whether this driver is in use, the user must call H5Pget_driver and compare the returned value to the string H5FD_MULTI. A positive match will confirm that the multi driver is in use; HDF5 provides no mechanism to determine whether it was called as the special case invoked by H5Pset_fapl_split.

* `h5::file_image{void*,size_t}` **Sets an initial file image in a memory buffer.**  H5Pset_file_image and other elements of HDF5 are used to load an image of an HDF5 file into system memory and open that image as a regular HDF5 file. An application can then use the file without the overhead of disk I/O.
H5Pset_file_image allows an application to provide a file image to be used as the initial contents of a file. Calling H5Pset_file_image makes a copy of the buffer specified in buf_ptr of size buf_len.

* `h5::meta_block_size{hsize_t}` **Sets the minimum metadata block size.** H5Pset_meta_block_size sets the minimum size, in bytes, of metadata block allocations when H5FD_FEAT_AGGREGATE_METADATA is set by a VFL driver.
Each raw metadata block is initially allocated to be of the given size. Specific metadata objects (e.g., object headers, local heaps, B-trees) are then sub-allocated from this block.
The default setting is 2048 bytes, meaning that the library will attempt to aggregate metadata in at least 2K blocks in the file. Setting the value to 0 (zero) with this function will turn off metadata aggregation, even if the VFL driver attempts to use the metadata aggregation strategy.
Metadata aggregation reduces the number of small data objects in the file that would otherwise be required for metadata. The aggregated block of metadata is usually written in a single write action and always in a contiguous block, potentially significantly improving library and application performance.

* `h5::page_buffer_size{size_t,unsigned,unsigned}` **Sets the maximum size for the page buffer and the minimum percentage for metadata and raw data pages.**
H5Pset_page_buffer_size sets buf_size, the maximum size in bytes of the page buffer. The default value is zero, meaning that page buffering is disabled. When a non-zero page buffer size is set, the library will enable page buffering if that size is larger or equal than a single page size if a paged file space strategy is enabled using the functions H5Pset_file_space_strategy() and H5Pset_file_space_page_size().
The page buffer layer captures all I/O requests before they are issued to the VFD and "caches" them in fixed sized pages. Once the total number of pages exceeds the page buffer size, the library evicts pages from the page buffer by writing them to the VFD. At file close, the page buffer is flushed writing all the pages to the file.
If a non-zero page buffer size is set, and the file space strategy is not set to paged or the page size for the file space strategy is larger than the page buffer size, the subsequent call to H5Fcreate() or H5Fopen() using the fapl_id will fail.
The function also allows setting the minimum percentage of pages for metadata and raw data to prevent a certain type of data to evict hot data of the other type.

* `h5::sieve_buf_size{size_t}` **Sets the maximum size of the data sieve buffer.**H5Pset_sieve_buf_size sets size, the maximum size in bytes of the data sieve buffer, which is used by file drivers that are capable of using data sieving.
The data sieve buffer is used when performing I/O on datasets in the file. Using a buffer which is large enough to hold several pieces of the dataset being read in for hyperslab selections boosts performance by quite a bit.
The default value is set to 64KB, indicating that file I/O for raw data reads and writes will occur in at least 64KB blocks. Setting the value to 0 with this API function will turn off the data sieving, even if the VFL driver attempts to use that strategy.
Internally, the library checks the storage sizes of the datasets in the file. It picks the smaller one between the size from the file access property and the size of the dataset to allocate the sieve buffer for the dataset in order to save memory usage.

* `h5::alignment{hsize_t, hsize_t}` **Sets alignment properties of a file access property list.**
H5Pset_alignment sets the alignment properties of a file access property list so that any file object greater than or equal in size to threshold bytes will be aligned on an address which is a multiple of alignment. The addresses are relative to the end of the user block; the alignment is calculated by subtracting the user block size from the absolute file address and then adjusting the address to be a multiple of alignment.
Default values for threshold and alignment are one, implying no alignment. Generally the default values will result in the best performance for single-process access to the file. For MPI IO and other parallel systems, choose an alignment which is a multiple of the disk block size.
If the file space handling strategy is set to H5F_FSPACE_STRATEGY_PAGE, then the alignment set via this routine is ignored. The file space handling strategy is set by H5Pset_file_space_strategy.

* `h5::cache{int,size_t,size_t,double}` **Sets the raw data chunk cache parameters.**
Setting raw data chunk cache parameters can be done with H5Pset_cache, H5Pset_chunk_cache, or a combination of both. H5Pset_cache is used to adjust the chunk cache parameters for all datasets via a global setting for the file, and H5Pset_chunk_cache is used to adjust the chunk cache parameters for individual datasets. When both are used, parameters set with H5Pset_chunk_cache will override any parameters set with H5Pset_cache.
Optimum chunk cache parameters may vary widely depending on different data layout and access patterns. For datasets with low performance requirements for example, changing the cache settings can save memory.
H5Pset_cache sets the number of elements, the total number of bytes, and the preemption policy value for all datasets in a file on the file’s file access property list.
The raw data chunk cache inserts chunks into the cache by first computing a hash value using the address of a chunk and then by using that hash value as the chunk’s index into the table of cached chunks. In other words, the size of this hash table and the number of possible hash values is determined by the rdcc_nslots parameter. If a different chunk in the cache has the same hash value, a collision will occur, which will reduce efficiency. If inserting the chunk into the cache would cause the cache to be too big, then the cache will be pruned according to the rdcc_w0 parameter.
The mdc_nelmts parameter is no longer used; any value passed in that parameter will be ignored.
Raw dataset chunk caching is not currently supported when using the MPI I/O and MPI POSIX file drivers in read/write mode; see H5Pset_fapl_mpio and H5Pset_fapl_mpiposix, respectively. When using one of these file drivers, all calls to H5Dread and H5Dwrite will access the disk directly, and H5Pset_cache will have no effect on performance.
Raw dataset chunk caching is supported when these drivers are used in read-only mode.

* `h5::elink_file_cache_size{unsigned}` **Sets the number of files that can be held open in an external link open file cache.**
H5Pset_elink_file_cache_size specifies the number of files that will be held open in an external link open file cache.
The default external link open file cache size is 0 (zero), meaning that files accessed via an external link are not held open. Setting the cache size to a positive integer turns on the cache; setting the size back to zero turns it off.
With this property set, files are placed in the external link open file cache cache when they are opened via an external link. Files are then held open until either they are evicted from the cache or the parent file is closed. This property setting can improve performance when external links are repeatedly accessed.
When the cache is full, files will be evicted using a least recently used (LRU) scheme; the file which has gone the longest time without being accessed through the parent file will be evicted and closed if nothing else is holding that file open.
Files opened through external links inherit the parent file’s file access property list by default, and therefore inherit the parent file’s external link open file cache setting.
When child files contain external links of their own, the caches can form a graph of cached external files. Closing the last external reference to such a graph will recursively close all files in the graph, even if cycles are present.

* `h5::evict_on_close{hbool_t}` **Controls the library's behavior of evicting metadata associated with a closed object**
The library's metadata cache is fairly conservative about holding on to HDF5 object metadata (object headers, chunk index structures, etc.), which can cause the cache size to grow, resulting in memory pressure on an application or system. When enabled, the "evict on close" property will cause all metadata for an object to be evicted from the cache as long as metadata is not referenced by any other open object.
This function only applies to file access property lists.
The default library behavior is to not evict on object or file close.
When applied to a file access property list, any subsequently opened object will inherit the "evict on close" property and will have its metadata evicted when the object is closed.

* `h5::metadata_read_attempts{unsigned}` **Sets the number of read attempts in a file access property list.**
H5Pset_metadata_read_attempts sets the number of reads that the library will try when reading checksummed metadata in an HDF5 file opened with SWMR access. When reading such metadata, the library will compare the checksum computed for the metadata just read with the checksum stored within the piece of checksum. When performing SWMR operations on a file, the checksum check might fail when the library reads data on a system that is not atomic. To remedy such situations, the library will repeatedly read the piece of metadata until the check passes or finally fails the read when the allowed number of attempts is reached.
The number of read attempts used by the library will depend on how the file is opened and whether the user sets the number of read attempts via this routine:
For a file opened with SWMR access:
	* If the user sets the number of attempts to N, the library will use N.
	* If the user does not set the number of attempts, the library will use the default for SWMR access (100).
	* For a file opened with non-SWMR access, the library will always use the default for non-SWMR access (1). The value set via this routine does not have any effect during non-SWMR access.


* `h5::mdc_config{H5AC_cache_config_t*}` **Set the initial metadata cache configuration in the indicated File Access Property List to the supplied value.** H5Pset_mdc_config attempts to set the initial metadata cache configuration to the supplied value. It will fail if an invalid configuration is detected. This configuration is used when the file is opened.
See the overview of the metadata cache in the special topics section of the user manual for details on what is being configured. If you haven't read and understood that documentation, you really shouldn't be using this API call.

* `h5::mdc_log_options{const char*,hbool_t}` **Sets metadata cache logging options.**
The metadata cache is a central part of the HDF5 library through which all file metadata reads and writes take place. File metadata is normally invisible to the user and is used by the library for purposes such as locating and indexing data. File metadata should not be confused with user metadata, which consists of attributes created by users and attached to HDF5 objects such as datasets via H5A API calls.
Due to the complexity of the cache, a trace/logging feature has been created that can be used by HDF5 developers for debugging and performance analysis. The functions that control this functionality will normally be of use to a very limited number of developers outside of The HDF Group. The functions have been documented to help users create logs that can be sent with bug reports.
Control of the log functionality is straightforward. Logging is enabled via the H5Pset_mdc_log_options() function, which will modify the file access property list used to open or create a file. This function has a flag that determines whether logging begins at file open or starts in a paused state. Log messages can then be controlled via the H5Fstart/stop_logging() functions. H5Pget_mdc_log_options() can be used to examine a file access property list, and H5Fget_mdc_logging_status() will return the current state of the logging flags.
The log format is described in the Metadata Cache Logging document.

* `h5::gc_references{unsigned}` **H5Pset_gc_references sets the flag for garbage collecting references for the file.**
Dataset region references and other reference types use space in an HDF5 file's global heap. If garbage collection is on and the user passes in an uninitialized value in a reference structure, the heap might get corrupted. When garbage collection is off, however, and the user re-uses a reference, the previous heap block will be orphaned and not returned to the free heap space.
When garbage collection is on, the user must initialize the reference structures to 0 or risk heap corruption.
The default value for garbage collecting references is off.

* `h5::small_data_block_size{hsize_t}` **Sets the size of a contiguous block reserved for small data.**
H5Pset_small_data_block_size reserves blocks of size bytes for the contiguous storage of the raw data portion of small datasets. The HDF5 library then writes the raw data from small datasets to this reserved space, thus reducing unnecessary discontinuities within blocks of meta data and improving I/O performance.
A small data block is actually allocated the first time a qualifying small dataset is written to the file. Space for the raw data portion of this small dataset is suballocated within the small data block. The raw data from each subsequent small dataset is also written to the small data block until it is filled; additional small data blocks are allocated as required.
The HDF5 library employs an algorithm that determines whether I/O performance is likely to benefit from the use of this mechanism with each dataset as storage space is allocated in the file. A larger size will result in this mechanism being employed with larger datasets.
The small data block size is set as an allocation property in the file access property list identified by fapl_id.
Setting size to zero (0) disables the small data block mechanism.

* `h5::object_flush_cb{H5F_flush_cb_t,void*}` **Sets a callback function to invoke when an object flush occurs in the file.**
H5Pset_object_flush_cb sets the callback function to invoke in the file access property list fapl_id whenever an object flush occurs in the file. Library objects are group, dataset, and committed datatype.
The callback function func must conform to the prototype defined below:
	`typedef herr_t (*H5F_flush_cb_t)(hid_t object_id, void *user_data)` The parameters of the callback function, per the above prototyps, are defined as follows:
	* object_id is the identifier of the object which has just been flushed.
	* user_data is the user-defined input data for the callback function.

* `h5::libver_bounds {H5F_libver_t,H5F_libver_t}` **Sets bounds on library versions, and indirectly format versions, to be used when creating objects.**
	* `h5::latest_version` **flag** to set version to latest


#### [Group Creation Property List][302]

* `h5::local_heap_size_hint{size_t` **Specifies the anticipated maximum size of a local heap.** 
H5Pset_local_heap_size_hint is used with original-style HDF5 groups (see “Motivation” below) to specify the anticipated maximum local heap size, size_hint, for groups created with the group creation property list gcpl_id. The HDF5 Library then uses size_hint to allocate contiguous local heap space in the file for each group created with gcpl_id.<br/>
For groups with many members or very few members, an appropriate initial value of size_hint would be the anticipated number of group members times the average length of group member names, plus a small margin:<br/>
`size_hint = max_number_of_group_members  * (average_length_of_group_member_link_names + 2)`
If it is known that there will be groups with zero members, the use of a group creation property list with size_hint set to to 1 (one) will guarantee the smallest possible local heap for each of those groups. Setting size_hint to zero (0) causes the library to make a reasonable estimate for the default local heap size.

* `h5::link_creation_order{unsigned}` **Sets creation order tracking and indexing for links in a group.**
H5Pset_link_creation_order sets flags for tracking and indexing links on creation order in groups created with the group creation property list gcpl_id. crt_order_flags contains flags with the following meanings:
    * H5P_CRT_ORDER_TRACKED	Link creation order is tracked but not necessarily indexed.
    * H5P_CRT_ORDER_INDEXED    	Link creation order is indexed (requires H5P_CRT_ORDER_TRACKED).

	Default behavior is that link creation order is neither tracked nor indexed. H5Pset_link_creation_order can be used to set link creation order tracking, or to set link creation order tracking and indexing. **Note** that if a creation order index is to be built, it must be specified in the group creation property list. HDF5 currently provides no mechanism to turn on link creation order tracking at group creation time and to build the index later.

* `h5::est_link_info{unsigned, unsigned}` **Sets estimated number of links and length of link names in a group.**
H5Pset_est_link_info inserts two settings into the group creation property list gcpl_id: the estimated number of links that are expected to be inserted into a group created with the property list and the estimated average length of those link names.
The estimated number of links is passed in est_num_entries. The estimated average length of the anticipated link names is passed in est_name_len.
The values for these two settings are multiplied to compute the initial local heap size (for old-style groups, if the local heap size hint is not set) or the initial object header size for (new-style compact groups; see “Group implementations in HDF5”). Accurately setting these parameters will help reduce wasted file space.<br/>
If a group is expected to have many links and to be stored in dense format, set est_num_entries to 0 (zero) for maximum efficiency. This will prevent the group from being created in the compact format. See “Group implementations in HDF5” in the H5G API introduction for a discussion of the available types of HDF5 group structures.

* `h5::link_phase_change{unsigned, unsigned}` **Sets the parameters for conversion between compact and dense groups.** H5Pset_link_phase_change sets the maximum number of entries for a compact group and the minimum number of links to allow before converting a dense group to back to the compact format. `max_compact` is the maximum number of links to store as header messages in the group header as before converting the group to the dense format. Groups that are in compact format and in which the exceed this number of links rises above this threshold are automatically converted to dense format. `min_dense` is the minimum number of links to store in the dense format. Groups which are in dense format and in which the number of links falls below this theshold are automatically converted to compact format. See “Group implementations in HDF5” in the H5G API introduction for a discussion of the available types of HDF5 group structures.

#### [Dataset Creation Property List][303]
**Example:**
```cpp
h5::dcpl_t dcpl = h5::chunk{1,4,5} | h5::deflate{4} | h5::layout_compact | h5::dont_filter_partial_chunks
		| h5::fill_value<my_struct>{STR} | h5::fill_time_never | h5::alloc_time_early 
		| h5::fletcher32 | h5::shuffle | h5::nbit;
```

* `h5::chunk{const hsize_t*}` **control chunk size** takes in initialiser list with rank matching the dataset dimensions:
	* `h5::chunk{1,20,30}` sets chunk size for a cube.
* `h5::fill_value<T>{const void*}` **sets fill value**
* `h5::deflate{0-9} | h5::gzip{0-9}` **set deflate compression ratio**
* `h5::fletcher32`, `h5::shuffle`, `h5::nbit` **set various filters**
* `h5::layout_compact`, `h5::layout_contigous`, `h5::layout_chunked`, `h5::layout_virtual` **Layout control flags**
* `h5::fill_time_ifset`, `h5::fill_time_alloc`, `h5::`fill_time_never **how fill values are handled**
* `h5::alloc_time_default`, `h5::alloc_time_early`, `h5::alloc_time_incr`, `h5::alloc_time_late` **how chunks are allocated**
* `h5::dont_filter_partial_chunks` **prevents filering on edges** during partial IO data access 
	is frequent at unfilled edges, filtering them may be detrimental to performance.<br/> 
	**NOTE:** This feature is not used with H5CPP custom data filter pipeline


#### [Dataset Access Property List][301]
In addition to CAPI properties, a custom `high_throughput` property is added, to request alternative, efficient pipeline.
 
```cpp
using chunk_cache          = impl::dapl_call< impl::dapl_args<hid_t,size_t, size_t, double>,H5Pset_chunk_cache>;
using efile_prefix 		   = impl::dapl_call< impl::dapl_args<hid_t,const char*>,H5Pset_efile_prefix>;
using virtual_view         = impl::dapl_call< impl::dapl_args<hid_t,H5D_vds_view_t>,H5Pset_virtual_view>;
using virtual_printf_gap   = impl::dapl_call< impl::dapl_args<hid_t,hsize_t>,H5Pset_virtual_printf_gap>;
//using num_threads  	   	   = impl::dapl_call< impl::dapl_args<hid_t, unsigned char>,impl::dapl_threads>;
namespace flag {
	using high_throughput      = impl::dapl_call< impl::dapl_args<hid_t>,impl::dapl_pipeline_set>;
}
const static flag::high_throughput high_throughput;

const static h5::dapl_t dapl = static_cast<h5::dapl_t>( H5Pcreate(H5P_DATASET_ACCESS) );
//const static h5::dapl_t default_dapl = high_throughput;
const static h5::dapl_t default_dapl = static_cast<h5::dapl_t>(  H5Pcreate(H5P_DATASET_ACCESS) );
```
#### [Dataset Transfer Property List][305]
```cpp
using buffer                   = impl::dxpl_call< impl::dxpl_args<hid_t,size_t,void*,void*>,H5Pset_buffer>;
using edc_check                = impl::dxpl_call< impl::dxpl_args<hid_t,H5Z_EDC_t>,H5Pset_edc_check>;
using filter_callback          = impl::dxpl_call< impl::dxpl_args<hid_t,H5Z_filter_func_t,void*>,H5Pset_filter_callback>;
using data_transform           = impl::dxpl_call< impl::dxpl_args<hid_t,const char *>,H5Pset_data_transform>;
using type_conv_cb             = impl::dxpl_call< impl::dxpl_args<hid_t,H5T_conv_except_func_t,void*>,H5Pset_type_conv_cb>;
using hyper_vector_size        = impl::dxpl_call< impl::dxpl_args<hid_t,size_t>,H5Pset_hyper_vector_size>;
using btree_ratios             = impl::dxpl_call< impl::dxpl_args<hid_t,double,double,double>,H5Pset_btree_ratios>;
```

#### [Link Creation Property List][306]
```cpp
using char_encoding            = impl::lcpl_call< impl::lcpl_args<hid_t,H5T_cset_t>,H5Pset_char_encoding>;
using create_intermediate_group= impl::lcpl_call< impl::lcpl_args<hid_t,unsigned>,H5Pset_create_intermediate_group>;
const static h5::char_encoding ascii{H5T_CSET_ASCII};
const static h5::char_encoding utf8{H5T_CSET_UTF8};
const static h5::create_intermediate_group create_path{1};
```
#### [Link Access Property List][307]
```cpp
using nlinks                   = impl::lapl_call< impl::lapl_args<hid_t,size_t>,H5Pset_nlinks>;
using elink_cb                 = impl::lapl_call< impl::lapl_args<hid_t,H5L_elink_traverse_t, void*>,H5Pset_elink_cb>;
using elink_prefix             = impl::lapl_call< impl::lapl_args<hid_t,const char*>,H5Pset_elink_prefix>;
using elink_fapl               = impl::lapl_call< impl::lapl_args<hid_t,hid_t>,H5Pset_elink_fapl>;
using elink_acc_flags          = impl::lapl_call< impl::lapl_args<hid_t,unsigned>,H5Pset_elink_acc_flags>;
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
[301]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#FileAccessPropFuncs
[302]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#GroupCreatePropFuncs
[303]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#DatasetCreatePropFuncs
[304]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#DatasetAccessPropFuncs
[305]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#DatasetTransferPropFuncs
[306]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#LinkCreatePropFuncs
[307]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#LinkAccessPropFuncs
[308]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#ObjectCreatePropFuncs
[309]: https://support.hdfgroup.org/HDF5/doc/RM/RM_H5P.html#ObjectCopyPropFuncs

[601]: #file-creation-property-list
[602]: #file-access-property-list
[603]: #link-creation-property-list
[604]: #dataset-creation-property-list
[605]: #dataset-access-property-list
[606]: #dataset-transfer-property-list

[700]: http://man7.org/linux/man-pages/man2/fcntl.2.html
[701]: https://bitbucket.hdfgroup.org/users/jhenderson/repos/rest-vol/browse
