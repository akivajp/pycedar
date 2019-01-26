from libcpp cimport bool

cdef extern from "cedarpp.h" namespace "cedar":
    ctypedef unsigned long npos_t

    cdef cppclass da[value_type]:

        struct result_triple_type:
            value_type value
            size_t     length
            npos_t     id

        da() except +
        void clear (const bool reuse)

        size_t capacity   () const
        size_t size       () const
        size_t length     () const
        size_t total_size () const
        size_t unit_size  () const
        size_t nonzero_size () const
        size_t nonzero_length () const
        size_t num_keys () const

        result_type exactMatchSearch[result_type] (const char* key, size_t len, npos_t from_) const

        size_t commonPrefixPredict[result_type] (const char* key, result_type* result, size_t result_len, size_t len, npos_t from_) const

        size_t commonPrefixSearch[result_type] (const char* key, result_type* result, size_t result_len, size_t len, npos_t from_) const

        void suffix (char* key, size_t len, npos_t to) const

        value_type traverse (const char* key, npos_t& from_, size_t& pos) const

        value_type& update (const char* key, size_t len, value_type val) except +

        int erase (const char* key, size_t len, npos_t from_)

        int save (const char* fn, const char* mode, const bool shrink)

        int open (const char* fn, const char* mode, const size_t offset, size_t size_)

        void restore ()

        int begin (npos_t& from_, size_t& len)

        int next (npos_t& from_, size_t& len, const npos_t root)

