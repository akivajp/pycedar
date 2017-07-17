# distutils: language=c++
# -*- coding: utf-8 -*-

#import sys
#cimport cython
#from cython.operator cimport dereference as deref
#from cython.operator cimport reference as ref
#from libcpp.string cimport string

from libcpp.vector cimport vector

from pycedar cimport da
from pycedar cimport npos_t

ctypedef fused strtype:
    str
    bytes

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

cdef class node:
    cdef readonly npos_t id
    cdef readonly size_t length
    cdef trie t

    def __cinit__(self, trie t, npos_t id, size_t length):
        self.t = t
        self.id = id
        self.length = length

    cpdef str key(self):
        return self.t.suffix(self.id, self.length)

    cpdef int value(self):
        return self.t.lookup(self.key())

    cpdef tuple track(self):
        return self.id, self.length

    def __repr__(self):
        return "pycedar.node(t = %s, id=%s, length=%s)" % (self.t,self.id,self.length)

    def __str__(self):
        return self.key()

cdef class trie:
    cdef da[int] obj
    NO_VALUE = -1
    NO_PATH  = -2

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

    cpdef tuple begin(self, npos_t start=0, size_t length=0):
        cdef int result = self.obj.begin(start, length)
        return result, start, length

    cpdef int erase(self, strtype key, npos_t start=0):
        cdef bytes k = to_bytes(key)
        return self.obj.erase(k, len(k), start)

    def find(self, key, npos_t start=0):
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        cdef npos_t root
        for value, node_id, length in self.find_all(key, start):
            yield self.suffix(node_id,length), value

    def find_all(self, key, npos_t start=0):
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        cdef npos_t root
        value, root, length = self.traverse(key)
        if value != trie.NO_PATH:
            value, node_id, length = self.begin(root, length)
        while value != trie.NO_PATH:
            yield value, node_id, length
            value, node_id, length = self.next(node_id, length, root)

    def find_keys(self, key, npos_t start=0):
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        for value, node_id, length in self.find_all(key, start):
            yield self.suffix(node_id, length)

    def find_nodes(self, key, npos_t start=0):
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        for value, node_id, length in self.find_all(key, start):
            yield node(self, node_id, length)

    def find_values(self, key, npos_t start=0):
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        for value, root, length in self.find_all(key, start):
            yield value

    cpdef object get(self, strtype key, object default=trie.NO_VALUE):
        cdef int value = self.lookup(key)
        if value in (trie.NO_VALUE, trie.NO_PATH):
            return default
        return value

    cpdef node get_node(self, strtype key, size_t start=0):
        cdef bytes k = to_bytes(key)
        cdef da[int].result_triple_type result
        result = self.obj.exactMatchSearch[da[int].result_triple_type](k, len(k), start)
        if result.value in (trie.NO_VALUE, trie.NO_PATH):
            return None
        return node(self, result.id, result.length)

    cpdef keys(self):
        return self.find_keys('')

    cpdef items(self):
        return self.find('')

    cpdef int load(self, str filepath, str mode = 'rb', size_t offset = 0, size_t size = 0):
        return self.obj.open(to_bytes(filepath), to_bytes(mode), offset, size)

    cpdef int lookup(self, key, npos_t start=0):
        cdef bytes k = to_bytes(key)
        return self.obj.exactMatchSearch[int] (k, len(k), start)

    cpdef tuple next(self, npos_t start, size_t length, npos_t root=0):
        cdef result = self.obj.next(start, length, root)
        return result, start, length

    cpdef list prefix(self, strtype key, npos_t start=0):
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

    cpdef int save(self, str filepath, str mode = 'wb', bool shrink = True):
        return self.obj.save(to_bytes(filepath), to_bytes(mode), shrink)

    cpdef int set(self, strtype key, int value=0) except *:
        cdef bytes k = to_bytes(key)
        cdef int* r
        if not k:
            raise KeyError("empty key is invalid")
        #if value < 0:
        #    return ValueError("negative value is invalid: %s" % value)
        r = & self.obj.update(k, len(k), value)
        r[0] = value
        return r[0]

    cpdef int setdefault(self, strtype key, int value=0):
        cdef bytes k = to_bytes(key)
        if not k:
            raise KeyError("empty key is invalid")
        cdef int result = self.lookup(k)
        if result not in (trie.NO_VALUE, trie.NO_PATH):
            return result
        return self.set(k, value)

    cpdef str suffix(self, object id_or_tuple, size_t length=0):
        cdef node_id
        if isinstance(id_or_tuple, tuple):
            node_id, length = id_or_tuple
        elif isinstance(id_or_tuple, int):
            node_id = id_or_tuple
        else:
            raise TypeError('expected int or tuple, but given %s' %  type(id_or_tuple).__name__)
        cdef bytes buf = b'\0' * length
        self.obj.suffix(buf, length, node_id)
        return to_str(buf)

    cpdef tuple traverse(self, key, npos_t start=0, size_t pos=0):
        cdef bytes k = to_bytes(key)
        cdef int result = self.obj.traverse(k, start, pos)
        return result, start, pos

    cpdef int update(self, strtype key, int diff=0) except *:
        cdef bytes k = to_bytes(key)
        if not k:
            raise KeyError("empty key is invalid")
        return self.obj.update(k, len(k), diff)

    cpdef values(self):
        return self.find_values('')

    def __contains__(self, key):
        if self.lookup(to_bytes(key)) in (trie.NO_VALUE, trie.NO_PATH):
            return False
        return True

    def __iter__(self):
        return self.keys()

    def __delitem__(self, key):
        if self.erase(to_bytes(key)) < 0:
            raise KeyError(key)
    def __getitem__(self, key):
        cdef int value = self.lookup(to_bytes(key))
        if value in (trie.NO_VALUE, trie.NO_PATH):
            raise KeyError(key)
        return value
    def __setitem__(self, key, int value):
        self.set(to_bytes(key), value)

