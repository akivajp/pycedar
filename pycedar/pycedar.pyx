# distutils: language=c++
# -*- coding: utf-8 -*-

import sys

from cython.operator cimport dereference as deref
#from cython.operator cimport reference as ref
from libcpp.string cimport string
from libcpp.vector cimport vector

from pycedar cimport da
from pycedar cimport npos_t
#from pycedar cimport result_triple_type

#cdef bytes py3_str2bytes(str s):
#    return bytes(s, 'utf-8')
#cdef bytes py2_str2bytes(bytes s):
#    # bytes == str
#    return s
#
#cdef str py3_bytes2str(bytes s):
#    return s.decode('utf-8')
#cdef str py2_str2bytes(str s):
#    # bytes == str
#    return s
#
#cdef str2bytes
#cdef bytes2str
#if sys.version_info.major >= 3:
#    str2bytes = py3_str2bytes
#    bytes2str = py3_bytes2str
#else:
#    str2bytes = py2_str2bytes
#    bytes2str = py2_bytes2str
#
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

#cdef result_to_tuple(da[int].result_triple_type result):
#    return result.value, result.length, result.id

cdef class trie:
    cdef da[int] obj

    def __cinit__(self):
        pass
        #self.obj

    def __len__(self):
        return self.obj.num_keys()

    cpdef capacity(self):
        return self.obj.capacity()
    cpdef size(self):
        return self.obj.size()
    cpdef length(self):
        return self.obj.length()
    cpdef total_size(self):
        return self.obj.total_size()
    cpdef unit_size(self):
        return self.obj.unit_size()
    cpdef nonzero_size(self):
        return self.obj.nonzero_size()
    cpdef nonzero_length(self):
        return self.obj.nonzero_length()
    cpdef num_keys(self):
        return self.obj.num_keys()

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

    def traverse(self, key, npos_t start=0, size_t pos=0):
        cdef bytes k = to_bytes(key)
        cdef int result = self.obj.traverse(k, start, pos)
        return result, start, pos

    def update(self, key, value=0):
        cdef bytes k = to_bytes(key)
        return self.obj.update(k, len(k), value)

    cpdef save(self, filepath, mode = 'wb', bool shrink = False):
        return self.obj.save(to_bytes(filepath), to_bytes(mode), shrink) 

    cpdef open(self, filepath, mode = 'rb', size_t offset = 0, size_t size = 0):
        return self.obj.open(to_bytes(filepath), to_bytes(mode), offset, size)

    def begin(self, npos_t start=0, size_t length=0):
        cdef int result = self.obj.begin(start, length)
        return result, start, length

    def next(self, npos_t start, size_t length, npos_t root=0):
        cdef result = self.obj.next(start, length, root)
        return result, start, length

