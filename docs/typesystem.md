# Type System
<img src="../icons/cpp_type_system.png" alt="some text" style="zoom:60%;" />

```
arithmetic ::= (signed | unsigned)[char | short | int | long | long int, long long int] 
					  | [float | double | long double]
reference ::= [ pointer | R value reference | PR value reference]
```

## What you need to know of C++ data types
The way objects arranged in memory is called the layout. The C++ memory model is more relaxed than the one in C or Fortran therefore one can't assume contiguous arrangement of class members, or even being of the same order as defined. Since data transfer operation in HDF5 require contiguous memory arrangement which creates a mismatch between the two systems.  C++ objects may be categorized by memory layout such as:  

* Trivial : class members are in contiguous memory, but order is not guaranteed; consistent among same compiles
* Standard : contiguous memory, class member order is guaranteed, good for interop
* POD or plain old data : members are contiguous memory location and in order


### Trivial 
memory layout 

* no virtual functions or virtual base classes,
* no base classes with a corresponding non-trivial constructor/operator/destructor
* no data members of class type with a corresponding non-trivial constructor/operator/destructor

### Standard Layout
* no virtual functions or virtual base classes
* all non-static data members have the same access control
* all non-static members of class type are standard-layout
* any base classes are standard-layout
* has no base classes of the same type as the first non-static data member.

meets one of these conditions:

* no non-static data member in the most-derived class and no more than one base class with non-static data members, or
* has no base classes with non-static data members

### Plain Old Data (POD)

<div id="object" style="float: right">
	<img src="../icons/struct.svg" alt="some text" style="zoom:60%;" />
</div>
Standard layout C++ classes and POD C style struct types have contigous memory layout with possible padding for memory alignment, and can be represented as
compound datatypes in HDF5 system. Within the container it behaves similar to other datatypes and form a valid element of hypercubes, arrays etc...

### Vectors, Matrices and Hypercubes
<div id="object" style="float: left">
	<img src="../icons/colvector.svg" alt="some text" style="zoom:40%;" />
	<img src="../icons/matrix.svg" alt="some text" style="zoom:50%;" />
	<img src="../icons/hypercube.svg" alt="some text" style="zoom:40%;" />
</div>
Are the most frequently used objects, and the cells may take up any fixed size data format. STL like Sequential and Set containers as well as C++ built in arrays may be mapped 0 - 7 dimensions of HDF5   homogeneous, and regular in shape data structure. Note that `std::array<T,N>` requires the size `N` known at compile time, therefore it is only suitable for partial IO read operations.

- `std::vector<T>`
- `std::array<T>`
- `T[N][M]...`


</br>

### Ragged Arrays

```
element_t ::= std::vector<T> | std::list<T> | std::forward_list
```
<div id="object" style="float: right">
	<img src="../icons/ragged.svg" alt="some text" style="zoom:80%;" />
</div>
Sequences of variable lengths are mapped to HDF5 ragged arrays, a data structure with the fastest growing dimension of variable length. The C++ equivalent is a container within a sequential container -- with embedding limited to one level. 

- `std::vector<element_t>`
- `std::array<element_t,N>`
- `std::list<element_t>`
- `std::forward_list<element_t>`
- `std::stack, std::queue, std::priority_queue`

### Classes: multiple datasets
<div id="object" style="float: right">
	<img src="../icons/key-value.svg" alt="some text" style="zoom:100%;" />
</div>

- `std::map<K,V>`
- `std::multimap<K,V>`
- `std::unordered_map<K,V>`
- `std::unordered_multimap<K,V>`
- `arma::SpMat<T>` sparse matrices in general



## H5CPP Type Systems 




The actual implementation is using `std::is_arithmetic`

### Rank
```
template<class T, class E = void> struct rank : public std::integral_constant<int,0> {}; // definition
template <class T, size_t N> struct rank<T[N]> : public std::rank<T[N]> {}; // arrays
template <class T> struct rank<T, class std::enable_if<
	h5::impl::is_container<T>::value>::type> : public std::integral_constant<size_t,1> {};

template<class T, int N> using is_rank = std::integral_constant<bool, rank<T>::value == N >;

template<class T> using is_scalar = is_rank<T,0>; // numerical | pod 
template<class T> using is_vector = is_rank<T,1>;
template<class T> using is_matrix = is_rank<T,2>;
template<class T> using is_cube   = is_rank<T,3>;
```

### Memory Layout
```
template<class T, size_t N = 0, class E = void> struct is_contigious;
template <class T, size_t N> class is_contigious<T,N, class std::enable_if<
	is_numerical<T>::value || std::is_pod<T>::value || linalg::is_dense<T>::value>::type>
: public std::integral_constant<bool,true>{};

```




