# distutils: language=c++
# -*- coding: utf-8 -*-

cdef extern from "cedarpp.h" namespace "cedar":
    ctypedef npos_t
    #ctypedef result_triple_type
    cdef cppclass da[ValueType]:
        da()
        size_t capacity   () const
        size_t size       () const
        size_t length     () const
        size_t total_size () const
        size_t unit_size  () const
        size_t nonzero_size () const
        size_t nonzero_length () const
        size_t num_keys () const

        ResultType exactMatchSearch[ResultType] (const char* key, size_t len, npos_t from_) const

        size_t commonPrefixSearch[ResultType] (const char* key, ResultType* result, size_t result_len, size_t len, npos_t from_) const

        #ctypedef result_triple_type
        #cdef cppclass result_triple_type

