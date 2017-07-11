from libcpp cimport bool

cdef extern from "cedarpp.h" namespace "cedar":
    #ctypedef npos_t
    ctypedef unsigned long npos_t
    cdef cppclass da[value_type]:
        struct result_triple_type:
            value_type value
            size_t     length
            npos_t     id

        da()
        size_t capacity   () const
        size_t size       () const
        size_t length     () const
        size_t total_size () const
        size_t unit_size  () const
        size_t nonzero_size () const
        size_t nonzero_length () const
        size_t num_keys () const

        result_type exactMatchSearch[result_type] (const char* key, size_t len, npos_t from_) const

        size_t commonPrefixSearch[result_type] (const char* key, result_type* result, size_t result_len, size_t len, npos_t from_) const

        #template <typename T>
        #size_t commonPrefixPredict (const char* key, T* result, size_t result_len)

        void suffix (char* key, size_t len, npos_t to) const
            
        value_type traverse (const char* key, npos_t& from_, size_t& pos) const

        #struct empty_callback { void operator () (const int, const int) {} }; // dummy empty function

        value_type& update(const char* key)
        value_type& update(const char* key, size_t len, value_type val)
        value_type& update(const char* key, npos_t& from_, size_t& pos, size_t len, value_type val)

        #int erase (const char* key) { return erase (key, std::strlen (key)); }
        #int erase (const char* key, size_t len, npos_t from = 0)

        #int build (size_t num, const char** key, const size_t* len = 0, const value_type* val = 0) {

        #template <typename T>
        #void dump (T* result, const size_t result_len) {

        #void shrink_tail () {

        int save (const char* fn, const char* mode, const bool shrink)

        int open (const char* fn, const char* mode, const size_t offset, size_t size_)

        #void restore () { // restore information to update

        #void set_array (void* p, size_t size_ = 0) { // ad-hoc

        #const void* array () const { return _array; }

        int begin (npos_t& from_, size_t& len)

        int next (npos_t& from_, size_t& len, const npos_t root)

        #ctypedef result_triple_type
        #cdef cppclass result_triple_type

