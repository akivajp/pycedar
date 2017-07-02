# distutils: language=c++
# -*- coding: utf-8 -*-

from pycedar cimport da
#from pycedar cimport result_triple_type

from cython.operator cimport dereference as deref
#from cython.operator cimport reference as ref
from libcpp.vector cimport vector
from libcpp.string cimport string

cdef class trie:
    cdef da[int] obj

    def __cinit__(self):
        pass
        #self.obj

    def __len__(self):
        return self.obj.num_keys()

    def capacity(self):
        return self.obj.capacity()
    def size(self):
        return self.obj.size()
    def length(self):
        return self.obj.length()
    def total_size(self):
        return self.obj.total_size()
    def unit_size(self):
        return self.obj.unit_size()
    def nonzero_size(self):
        return self.obj.nonzero_size()
    def nonzero_length(self):
        return self.obj.nonzero_length()
    def num_keys(self):
        return self.obj.num_keys()

    def exactMatchSearch(self, key, start=0):
        return self.obj.exactMatchSearch[int] (key, len(key), start)

    def commonPrefixSearch(self, key, start=0):
        pass
        #cdef vector[da[int].result_triple_type] result
        #cdef vector[char] buf
        #cdef string buf
        #cdef string* ptr
        #result.reserve(len(key))
        #ptr = &buf
        #buf.resize(len(key))
        #size_t commonPrefixSearch[ResultType] (const char* key, ResultType* result, size_t result_len, size_t len, npos_t from_) const
        #num = self.obj.commonPrefixSearch[string] (key, &buf, len(key), len(key), start)
        #num = self.obj.commonPrefixSearch[string] (key, &result, len(key), len(key), start)


