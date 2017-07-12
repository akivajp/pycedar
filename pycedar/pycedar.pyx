# distutils: language=c++
# -*- coding: utf-8 -*-

import sys

cimport cython
from cython.operator cimport dereference as deref
#from cython.operator cimport reference as ref
from libcpp.string cimport string
from libcpp.vector cimport vector

from pycedar cimport da
from pycedar cimport npos_t

cdef bytes to_bytes(s):
    if isinstance(s, bytes):
        return s
    elif isinstance(s, str):
        return bytes(s, 'utf-8')
    else:
        raise TypeError("expected str of bytes, but given: %s" % type(s).__name__)

cdef str to_str(s):
    if isinstance(s, str):
        return s
    elif isinstance(s, bytes):
        return s.decode('utf-8')
    else:
        raise TypeError("expected str of bytes, but given: %s" % type(s).__name__)

cdef class trie:
    cdef da[int] obj

    def __cinit__(self):
        pass
        #self.obj

    def __len__(self):
        return self.obj.num_keys()

    cpdef size_t capacity(self):
        return self.obj.capacity()
    cpdef size_t size(self):
        return self.obj.size()
    cpdef size_t length(self):
        return self.obj.length()
    cpdef size_t total_size(self):
        return self.obj.total_size()
    cpdef size_t unit_size(self):
        return self.obj.unit_size()
    cpdef size_t nonzero_size(self):
        return self.obj.nonzero_size()
    cpdef size_t nonzero_length(self):
        return self.obj.nonzero_length()
    cpdef size_t num_keys(self):
        return self.obj.num_keys()

    def find(self, key, start=0):
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        cdef npos_t root
        value, root, length = self.traverse(key)
        if value != -2:
            value, node_id, length = self.begin(root, length)
        while value != -2:
            yield self.suffix(node_id,length), value, node_id, length
            value, node_id, length = self.next(node_id, length, root)

    cpdef lookup(self, key, start=0):
        cdef bytes k = to_bytes(key)
        return self.obj.exactMatchSearch[int] (k, len(k), start)

    cpdef prefix(self, key, size=1, start=0):
        cdef bytes k = to_bytes(key)
        cdef vector[da[int].result_triple_type] result_vector
        cdef list result_list = []
        cdef da[int].result_triple_type r
        cdef size_t ret
        result_vector.resize(len(k))
        ret = self.obj.commonPrefixSearch[da[int].result_triple_type] (k, &result_vector[0], len(k), len(k), start)
        for r in result_vector:
            if len(result_list) < ret:
                result_list.append( (self.suffix(r.id,r.length), r.value, r.id) )
        return result_list

    cpdef str suffix(self, node_id, length):
        cdef bytes buf = b'\0' * length
        self.obj.suffix(buf, length, node_id)
        return to_str(buf)

    cpdef traverse(self, key, npos_t start=0, size_t pos=0):
        cdef bytes k = to_bytes(key)
        cdef int result = self.obj.traverse(k, start, pos)
        return result, start, pos

    cpdef update(self, key, value=0):
        cdef bytes k = to_bytes(key)
        cdef int* r
        if not key:
            raise KeyError("empty key is invalid")
        if value < 0:
            return ValueError("negative value is invalid: %s" % value)
        r = & self.obj.update(k, len(k), value)
        r[0] = value
        return r[0]

    cpdef erase(self, key, start = 0):
        cdef bytes k = to_bytes(key)
        return self.obj.erase(k, len(k), start)

    cpdef save(self, filepath, mode = 'wb', bool shrink = True):
        return self.obj.save(to_bytes(filepath), to_bytes(mode), shrink) 

    cpdef load(self, filepath, mode = 'rb', size_t offset = 0, size_t size = 0):
        return self.obj.open(to_bytes(filepath), to_bytes(mode), offset, size)

    cpdef begin(self, npos_t start=0, size_t length=0):
        cdef int result = self.obj.begin(start, length)
        return result, start, length

    cpdef next(self, npos_t start, size_t length, npos_t root=0):
        cdef result = self.obj.next(start, length, root)
        return result, start, length

