# distutils: language=c++
# -*- coding: utf-8 -*-

# system library
import sys

# stl classes
from libcpp.vector cimport vector

# local libraries
from pycedar cimport da
from pycedar cimport npos_t

ctypedef fused strtype:
    str
    bytes
    unicode

### compatible converters (bytes <-> {str,unicode})

cdef bytes py2_str_to_bytes(str s):
    # as-is
    return bytes(s)
cdef bytes py3_str_to_bytes(str s):
    return bytes(s, 'utf-8')

cdef bytes py2_unicode_to_bytes(unicode u):
    return u.encode('utf-8')
cdef bytes py3_unicode_to_bytes(unicode u):
    return bytes(u, 'utf-8')

cdef str py2_bytes_to_str(bytes b):
    # as-is
    return str(b)
cdef str py3_bytes_to_str(bytes b):
    return b.decode('utf-8')

cdef unicode py2_bytes_to_unicode(bytes b):
    return b.decode('utf-8')
cdef unicode py3_bytes_to_unicode(bytes b):
    return b.decode('utf-8')

cdef bytes   (*str_to_bytes)(str)
cdef bytes   (*unicode_to_bytes)(unicode)
cdef str     (*bytes_to_str)(bytes)
cdef unicode (*bytes_to_unicode)(bytes)

if sys.version_info.major >= 3:
    str_to_bytes     = py3_str_to_bytes
    unicode_to_bytes = py3_unicode_to_bytes
    bytes_to_str     = py3_bytes_to_str
    bytes_to_unicode = py3_bytes_to_unicode
else:
    str_to_bytes     = py2_str_to_bytes
    unicode_to_bytes = py2_unicode_to_bytes
    bytes_to_str     = py2_bytes_to_str
    bytes_to_unicode = py2_bytes_to_unicode

cpdef str to_str(object s):
    if isinstance(s, str):
        return s
    elif isinstance(s, bytes):
        return bytes_to_str(s)
    elif isinstance(s, unicode):
        # should be python2.x
        return s.encode('utf-8')
    else:
        raise TypeError("expected str, bytes or unicode, but given: %s" % type(s).__name__)

cpdef bytes to_bytes(object s):
    if isinstance(s, bytes):
        return s
    elif isinstance(s, unicode):
        return unicode_to_bytes(s)
    else:
        raise TypeError("expected str, bytes or unicode, but given: %s" % type(s).__name__)

cpdef unicode to_unicode(object s):
    if isinstance(s, unicode):
        return s
    elif isinstance(s, bytes):
        return bytes_to_unicode(s)
    else:
        raise TypeError("expected str, bytes or unicode, but given: %s" % type(s).__name__)

cdef class node:
    '''internal node information'''
    cdef readonly npos_t id
    cdef readonly size_t length
    cdef base_trie trie

    def __cinit__(self, base_trie trie, npos_t id, size_t length):
        self.trie = trie
        self.id = id
        self.length = length

    cpdef key(self):
        return self.trie.suffix(self.id, self.length)

    cpdef int value(self):
        return self.trie.exact_match_search(self.key())

    cpdef (npos_t,size_t) track(self):
        return self.id, self.length

    def __repr__(self):
        return "pycedar.node(trie = %s, id=%s, length=%s)" % (self.trie, self.id, self.length)

    def __str__(self):
        return self.key()

cdef class base_trie:
    '''
    base trie class
    please use specialized classes below
    '''

    cdef da[int] obj
    NO_VALUE = -1
    NO_PATH  = -2

    def __cinit__(self):
        self.obj

    def __dealloc__(self):
        self.clear()

    cpdef void clear(self, bool reuse=True):
        self.obj.clear(reuse)

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

    cpdef (int,npos_t,size_t) begin(self, npos_t start=0, size_t length=0):
        cdef int result = self.obj.begin(start, length)
        return result, start, length

    cpdef (int,npos_t,size_t) next(self, npos_t start, size_t length, npos_t root=0):
        cdef int result = self.obj.next(start, length, root)
        return result, start, length

    cpdef int open(self, str filepath, str mode = 'rb', size_t offset = 0, size_t size = 0):
        return self.obj.open(str_to_bytes(filepath), str_to_bytes(mode), offset, size)

    cpdef int save(self, str filepath, str mode = 'wb', bool shrink = True):
        return self.obj.save(str_to_bytes(filepath), str_to_bytes(mode), shrink)

### common functions

cdef list common_prefix_search(base_trie trie, bytes key, npos_t start=0):
    cdef vector[da[int].result_triple_type] result_vector
    cdef list result_list = []
    cdef da[int].result_triple_type r
    cdef size_t ret
    result_vector.resize(len(key))
    ret = trie.obj.commonPrefixSearch[da[int].result_triple_type] (key, &result_vector[0], len(key), len(key), start)
    for r in result_vector:
        if len(result_list) < ret:
            result_list.append( (trie.suffix(r.id,r.length), r.value, r.id) )
    return result_list

cdef node get_node(base_trie trie, bytes key, size_t start=0):
    cdef da[int].result_triple_type result
    result = trie.obj.exactMatchSearch[da[int].result_triple_type](key, len(key), start)
    if result.value in (base_trie.NO_VALUE, base_trie.NO_PATH):
        return None
    return node(trie, result.id, result.length)

cdef int set(base_trie trie, bytes key, int value) except +:
    cdef int* r
    if not key:
        raise KeyError("empty key is invalid")
    r = <int*>&trie.obj.update(key, len(key), value)
    r[0] = value
    return r[0]

cdef bytes suffix(base_trie trie, npos_t node_id, size_t length=0):
    cdef bytes buf = b'\0' * length
    trie.obj.suffix(buf, length, node_id)
    return buf

cdef int update(base_trie trie, bytes key, int delta=0) except +:
    if not key:
        raise KeyError("empty key is invalid")
    return trie.obj.update(key, len(key), delta)

### specialized trie classes

cdef class bytes_trie(base_trie):
    '''specialized trie class using bytes (standard)'''

    def __cinit__(self):
        pass

    cpdef list common_prefix_search(self, bytes key, npos_t start=0):
        return common_prefix_search(self, key, start)

    cpdef int erase(self, bytes key, npos_t start=0):
        return self.obj.erase(key, len(key), start)

    cpdef int exact_match_search(self, bytes key, npos_t start=0):
        return self.obj.exactMatchSearch[int] (key, len(key), start)

    cpdef node get_node(self, bytes key, size_t start=0):
        return get_node(self, key, start)

    cpdef int set(self, bytes key, int value):
        return set(self, key, value)

    cpdef bytes suffix(self, npos_t node_id, size_t length=0):
        return suffix(self, node_id, length)

    cpdef (int,npos_t,size_t) traverse(self, bytes key, npos_t start=0, size_t pos=0):
        cdef int result = self.obj.traverse(key, start, pos)
        return result, start, pos

    cpdef int update(self, bytes key, int delta=0):
        return update(self, key, delta)

cdef class str_trie(base_trie):
    '''specialized trie class using python standard str'''

    def __cinit__(self):
        pass

    cpdef list common_prefix_search(self, str key, npos_t start=0):
        return common_prefix_search(self, str_to_bytes(key), start)

    cpdef int erase(self, str key, npos_t start=0):
        cdef bytes bkey = str_to_bytes(key)
        return self.obj.erase(bkey, len(bkey), start)

    cpdef int exact_match_search(self, str key, npos_t start=0):
        cdef bytes bkey = str_to_bytes(key)
        return self.obj.exactMatchSearch[int] (bkey, len(bkey), start)

    cpdef node get_node(self, str key, size_t start=0):
        return get_node(self, str_to_bytes(key), start)

    cpdef int set(self, str key, int value):
        return set(self, str_to_bytes(key), value)

    cpdef str suffix(self, npos_t node_id, size_t length=0):
        return bytes_to_str( suffix(self, node_id, length) )

    cpdef (int,npos_t,size_t) traverse(self, str key, npos_t start=0, size_t pos=0):
        cdef bytes bkey = str_to_bytes(key)
        cdef int result = self.obj.traverse(bkey, start, pos)
        return result, start, pos

    cpdef int update(self, str key, int delta=0):
        return update(self, str_to_bytes(key), delta)

cdef class unicode_trie(base_trie):
    '''specialized trie class using python unicode string'''

    def __cinit__(self):
        pass

    cpdef list common_prefix_search(self, unicode key, npos_t start=0):
        return common_prefix_search(self, unicode_to_bytes(key), start)

    cpdef int erase(self, unicode key, npos_t start=0):
        cdef bytes bkey = unicode_to_bytes(key)
        return self.obj.erase(bkey, len(bkey), start)

    cpdef int exact_match_search(self, unicode key, npos_t start=0):
        cdef bytes bkey = unicode_to_bytes(key)
        return self.obj.exactMatchSearch[int] (bkey, len(bkey), start)

    cpdef node get_node(self, unicode key, size_t start=0):
        return get_node(self, unicode_to_bytes(key), start)

    cpdef int set(self, unicode key, int value):
        return set(self, unicode_to_bytes(key), value)

    cpdef unicode suffix(self, npos_t node_id, size_t length=0):
        return bytes_to_unicode( suffix(self, node_id, length) )

    cpdef (int,npos_t,size_t) traverse(self, unicode key, npos_t start=0, size_t pos=0):
        cdef bytes bkey = unicode_to_bytes(key)
        cdef int result = self.obj.traverse(bkey, start, pos)
        return result, start, pos

    cpdef int update(self, unicode key, int delta=0):
        return update(self, unicode_to_bytes(key), delta)

### utility class

cdef class dict:
    '''python dict-like class'''

    cdef public base_trie trie
    cdef public object type
    cdef public object fallback_cast

    def __cinit__(self, type type=str):
        if type is str:
            self.trie = str_trie()
            self.fallback_cast = to_str
        elif type is bytes:
            # should be pyton3
            self.trie = bytes_trie()
            self.fallback_cast = to_bytes
        elif type is unicode:
            # should be python2
            self.trie = unicode_trie()
            self.fallback_cast = to_unicode
        else:
            raise TypeError("expected type as str or bytes, but given: %s" % type.__name__)
        self.type = type

    def __dealloc__(self):
        self.clear()

    cpdef clear(self):
        self.trie.clear()

    def find(self, key, npos_t start=0):
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        cdef npos_t root
        for value, node_id, length in self.find_all(key, start):
            yield self.trie.suffix(node_id,length), value

    def find_all(self, key, npos_t start=0):
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        cdef npos_t root
        if not isinstance(key, self.type):
            key = self.fallback_cast(key)
        value, root, length = self.trie.traverse(key)
        if value != base_trie.NO_PATH:
            value, node_id, length = self.trie.begin(root, length)
        while value != base_trie.NO_PATH:
            yield value, node_id, length
            value, node_id, length = self.trie.next(node_id, length, root)

    def find_keys(self, key, npos_t start=0, bool force=False):
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        for value, node_id, length in self.find_all(key, start):
            try:
                yield self.trie.suffix(node_id, length)
            except Exception as e:
                if force:
                    pass
                else:
                    raise e

    def find_nodes(self, key, npos_t start=0):
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        for value, node_id, length in self.find_all(key, start):
            yield node(self.trie, node_id, length)

    def find_values(self, key, npos_t start=0):
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        for value, root, length in self.find_all(key, start):
            yield value

    cpdef object get(self, strtype key, object default=base_trie.NO_VALUE):
        cdef int value = self.trie.exact_match_search(key)
        if value in (base_trie.NO_VALUE, base_trie.NO_PATH):
            return default
        return value

    cpdef node get_node(self, strtype key, size_t start=0):
        return self.trie.get_node(key, start)

    cpdef keys(self):
        return self.find_keys(self.type())

    cpdef items(self):
        return self.find(self.type())

    cpdef int load(self, str filepath, str mode = 'rb', size_t offset = 0, size_t size = 0):
        return self.trie.open(filepath, mode, offset, size)

    cpdef nodes(self):
        return self.find_nodes(self.type())

    cpdef int save(self, str filepath, str mode = 'wb', bool shrink = True):
        return self.trie.save(filepath, mode, shrink)

    cpdef int set(self, strtype key, int value):
        return self.trie.set(key, value)

    cpdef int setdefault(self, strtype key, int value=0):
        if not key:
            raise KeyError("empty key is invalid")
        cdef int result = self.trie.exact_match_search(key)
        if result in (base_trie.NO_VALUE, base_trie.NO_PATH):
            result = self.set(key, value)
        return result

    cpdef int update(self, strtype key, int delta=0):
        return self.trie.update(key, delta)

    cpdef values(self):
        return self.find_values(self.type())

    def __len__(self):
        return self.trie.num_keys()

    def __contains__(self, key):
        if self.trie.exact_match_search(key) in (base_trie.NO_VALUE, base_trie.NO_PATH):
            return False
        return True

    def __iter__(self):
        return self.keys()

    def __delitem__(self, key):
        if self.trie.erase(key) < 0:
            raise KeyError(key)

    def __getitem__(self, key):
        cdef int value = self.trie.exact_match_search(key)
        if value in (base_trie.NO_VALUE, base_trie.NO_PATH):
            raise KeyError(key)
        return value

    def __setitem__(self, key, int value):
        self.trie.set(key, value)

