# distutils: language=c++
# -*- coding: utf-8 -*-

"""
Python binding of cedar (implementation of efficiently-updatable double-array trie) using Cython
"""

# system library
import sys

# stl classes
from libc.stdlib cimport free
from libc.string cimport memchr
from libcpp.vector cimport vector

# local libraries
from pycedar cimport da
from pycedar cimport npos_t

### package version
# pycedar/VERSION is the single source of truth; setup.py reads it and bakes it
# into the distribution metadata, which is read back here at runtime so that the
# version never has to be maintained in two places.
# (版情報の単一の情報源は pycedar/VERSION。実行時は配布メタデータから読み戻す)
try:
    from importlib.metadata import PackageNotFoundError
    from importlib.metadata import version as _get_distribution_version
    try:
        __version__ = _get_distribution_version('pycedar')
    except PackageNotFoundError:
        # Built in place without being installed. (未インストールのin-placeビルド)
        __version__ = 'unknown'
except ImportError:  # pragma: no cover
    __version__ = 'unknown'

### CPython C-API
# Used to hand cedar a key's bytes without allocating a copy of them.
# (キーのバイト列をコピーせずに cedar へ渡すために使う)
cdef extern from "Python.h":
    bint PyUnicode_Check(object o)
    const char* PyUnicode_AsUTF8AndSize(object o, Py_ssize_t* size) except NULL
    bint PyBytes_Check(object o)
    char* PyBytes_AS_STRING(object o)
    Py_ssize_t PyBytes_GET_SIZE(object o)
    object PyBytes_FromStringAndSize(const char* v, Py_ssize_t len)
    int PyBytes_AsStringAndSize(object o, char** buf, Py_ssize_t* length) except -1

### sentinel values
# C level mirrors of base_trie.NO_VALUE / NO_PATH. The class attributes stay as
# the public API; these are what the hot paths compare against, so that a lookup
# does not have to build a Python tuple of Python ints on every call.
# (公開APIはクラス属性のまま。内部の高頻度経路はこのC定数と比較する)
cdef int _NO_VALUE = -1
cdef int _NO_PATH  = -2

### sentinel for dict.pop()'s omitted default
# A distinct object, so that pop(key) (raise on missing) and pop(key, default)
# can be told apart even when the caller passes None or a falsy default.
# (pop(key) と pop(key, default) を区別するための専用オブジェクト。
#  呼び出し側が None や偽値を渡しても判別できる)
_POP_MISSING = object()

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

cdef str to_str(object s):
    if isinstance(s, str):
        return s
    elif isinstance(s, bytes):
        return bytes_to_str(s)
    elif isinstance(s, unicode):
        # should be python2.x
        return s.encode('utf-8')
    else:
        raise TypeError("expected str, bytes or unicode, but given: %s" % type(s).__name__)

cdef bytes to_bytes(object s):
    if isinstance(s, bytes):
        return s
    elif isinstance(s, unicode):
        return unicode_to_bytes(s)
    else:
        raise TypeError("expected str, bytes or unicode, but given: %s" % type(s).__name__)

cdef unicode to_unicode(object s):
    if isinstance(s, unicode):
        return s
    elif isinstance(s, bytes):
        return bytes_to_unicode(s)
    else:
        raise TypeError("expected str, bytes or unicode, but given: %s" % type(s).__name__)


cdef class base_trie:
    """
    base trie class
    please use specialized classes below
    """
    cdef da[int] obj
    cdef readonly root
    NO_VALUE = -1
    NO_PATH  = -2

    def __cinit__(self):
        self.obj
        self.root = node(self, 0, 0)

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

    cpdef (int,npos_t,size_t) begin(self, npos_t from_id=0, size_t length=0):
        cdef int result = self.obj.begin(from_id, length)
        return result, from_id, length

    cpdef (int,npos_t,size_t) next(self, npos_t from_id, size_t length, npos_t root=0):
        cdef int result = self.obj.next(from_id, length, root)
        return result, from_id, length

    cpdef int open(self, str filepath, str mode = 'rb', size_t offset = 0, size_t size = 0):
        return self.obj.open(str_to_bytes(filepath), str_to_bytes(mode), offset, size)

    cpdef int save(self, str filepath, str mode = 'wb', bool shrink = True):
        return self.obj.save(str_to_bytes(filepath), str_to_bytes(mode), shrink)

    cpdef bytes dumps(self, bool shrink=True):
        """Serialize the trie image into bytes. (トライイメージを bytes に直列化する)

        The layout is byte-for-byte what ``save()`` writes to a file, so
        ``dumps()`` output can be written to a file and read back with
        ``open()``/``load()``. The image stays platform-dependent (pointer size
        and byte order) exactly like the file format, and carries no integrity
        checks. A malformed image is reported by ``loads()`` returning ``-1``;
        allocation failures raise ``MemoryError``.
        (save() がファイルに書き出すのと同一レイアウトのため、dumps() の結果を
         ファイルに書いて open()/load() で読み戻せる。プラットフォーム依存や
         改竄検査の無さもファイル形式と同じ。不正な入力は loads() が -1 を返す。
         確保失敗は MemoryError)
        """
        cdef char* buf = NULL
        cdef size_t length = 0
        # cedarpp.h allocates the image and hands ownership to us.
        # (cedarpp.h 側で確保し、所有権を受け取る)
        self.obj.save(&buf, &length, shrink)
        try:
            return PyBytes_FromStringAndSize(buf, <Py_ssize_t>length)
        finally:
            # The bytes object copies the contents, so the buffer can go now.
            # (bytes オブジェクトが中身をコピーするため、バッファは直後に解放してよい)
            free(buf)

    cpdef int loads(self, bytes data):
        """Replace the trie with a serialized image. (直列化イメージで中身を置き換える)

        Accepts the bytes produced by ``dumps()`` (or ``save()``). Returns ``0``
        on success and ``-1`` for malformed input, matching the ``save()`` /
        ``load()`` convention. Unlike ``load()``, a malformed image is rejected
        before the current contents are touched, so the trie keeps them and
        stays reusable; only an allocation failure (raised as ``MemoryError``)
        can leave it empty, as with ``load()``. The caller's buffer is copied,
        so it may be released right after the call.
        (dumps() または save() が生成した bytes を受け取る。save()/load() の慣習に
         合わせ、成功時 0、不正入力時 -1 を返す。load() と異なり、不正なイメージは
         現在の中身に触れる前に拒否されるため中身は保持される。MemoryError となり
         うる確保失敗のみ、load() と同様にトライは空になる。バッファはコピーされる
         ため、呼び出し後すぐ解放してよい)
        """
        cdef char* buf = NULL
        cdef Py_ssize_t length = 0
        PyBytes_AsStringAndSize(data, &buf, &length)
        return self.obj.open(buf, <size_t>length)

    def __reduce__(self):
        # Pickle through the serialized image, passing the class explicitly so
        # that the specialized subclasses round trip as themselves.
        # (直列化イメージ経由で pickle 化する。特殊化クラスがそのまま復元されるよう
        #  クラスオブジェクトを明示的に渡す)
        return (_trie_from_image, (self.__class__, self.dumps()))

    ### type dependent operations (型に依存する操作)
    # Declared here purely so that calls dispatch through the vtable. The shared
    # helpers below and pycedar.dict only ever hold a base_trie reference, and
    # without these declarations every call became a method lookup by name, with
    # each C integer argument boxed into a Python int on the way in.
    # (共通ヘルパーと pycedar.dict は base_trie 型しか持たないため、宣言が無いと
    #  名前による動的探索になり、C整数の引数も毎回 Python int に箱詰めされていた)
    #
    # The key is typed as object because the three specialisations accept
    # different key types; each one validates what it is given.
    # (キーが object なのは特殊化ごとに受け付ける型が異なるため。検証は各実装が行う)

    cpdef list common_prefix_predict(self, object key, npos_t from_id=0, int max_size=-1):
        raise NotImplementedError("use one of the specialized trie classes")

    cpdef list common_prefix_search(self, object key, npos_t from_id=0, int max_size=-1):
        raise NotImplementedError("use one of the specialized trie classes")

    cpdef int erase(self, object key, npos_t from_id=0):
        raise NotImplementedError("use one of the specialized trie classes")

    cpdef (int, size_t, npos_t) exact_match_search(self, object key, npos_t from_id=0):
        raise NotImplementedError("use one of the specialized trie classes")

    cpdef int set(self, object key, int value) except *:
        raise NotImplementedError("use one of the specialized trie classes")

    cpdef object suffix(self, npos_t node_id, size_t length=0):
        raise NotImplementedError("use one of the specialized trie classes")

    cpdef (int,npos_t,size_t) traverse(self, object key, npos_t from_id=0, size_t pos=0):
        raise NotImplementedError("use one of the specialized trie classes")

    cpdef int update(self, object key, int delta=0):
        raise NotImplementedError("use one of the specialized trie classes")

### key borrowing
# These return a pointer into the key object itself, so the caller must keep a
# reference to that object alive for as long as the pointer is used. Every call
# site below does: the key is the argument it was handed.
# (返るのはキー自身の内部へのポインタなので、使用中はキーを生かしておく必要がある。
#  呼び出し側は引数として受け取ったキーを保持しているため条件を満たす)

cdef inline const char* key_as_utf8(object key, Py_ssize_t* length) except NULL:
    """Borrow a str's UTF-8 bytes.

    CPython keeps a UTF-8 representation on the object, and for an ASCII string
    that *is* the string's own storage, so nothing is copied or allocated.
    (CPython は UTF-8 表現をオブジェクト上に保持する。ASCII なら文字列自身の
     領域そのものなので、コピーも確保も発生しない)
    """
    if not PyUnicode_Check(key):
        raise TypeError("expected str, but given: %s" % type(key).__name__)
    return PyUnicode_AsUTF8AndSize(key, length)

cdef inline const char* key_as_bytes(object key, Py_ssize_t* length) except NULL:
    """Borrow a bytes object's buffer. (bytes のバッファを借りる)"""
    if not PyBytes_Check(key):
        raise TypeError("expected bytes, but given: %s" % type(key).__name__)
    length[0] = PyBytes_GET_SIZE(key)
    return PyBytes_AS_STRING(key)

### common functions

# Speculative buffer for an unbounded predict query. Both cedar entry points
# return the total number of matches even when the buffer was too small, so one
# call is enough whenever the results fit, and the exact size is known for the
# single retry when they do not.
# (predict の投機バッファ。cedar はバッファ不足でも総数を返すため、
#  収まれば1回で済み、収まらなくても正確な大きさで1回やり直すだけでよい)
cdef size_t _PREDICT_INITIAL_CAPACITY = 64

cdef list common_prefix_predict(base_trie trie, const char* key, size_t keylen, npos_t from_id=0, int max_size=-1):
    cdef vector[da[int].result_triple_type] result_vector
    cdef list result_list = []
    cdef da[int].result_triple_type r
    cdef size_t capacity
    cdef size_t ret
    cdef size_t i

    if max_size == 0:
        return result_list
    if max_size > 0:
        capacity = <size_t>max_size
    else:
        capacity = _PREDICT_INITIAL_CAPACITY

    result_vector.resize(capacity)
    ret = trie.obj.commonPrefixPredict[da[int].result_triple_type] (
        key, &result_vector[0], capacity, keylen, from_id)
    if ret > capacity:
        if max_size > 0:
            # The caller asked for a bounded result. (上限指定ありなので切り詰める)
            ret = capacity
        else:
            # The return value is the exact size needed. (戻り値が必要な大きさそのもの)
            result_vector.resize(ret)
            ret = trie.obj.commonPrefixPredict[da[int].result_triple_type] (
                key, &result_vector[0], ret, keylen, from_id)

    for i in range(ret):
        r = result_vector[i]
        result_list.append( (trie.suffix(r.id, r.length), r.value, r.id) )
    return result_list

cdef list common_prefix_search(base_trie trie, const char* key, size_t keylen, npos_t from_id=0, int max_size=-1):
    cdef vector[da[int].result_triple_type] result_vector
    cdef list result_list = []
    cdef da[int].result_triple_type r
    cdef size_t capacity
    cdef size_t ret
    cdef size_t i

    # cedar advances one position per byte of the key, so a common prefix search
    # can never return more than len(key) results. Sizing the buffer to that
    # removes the counting pass entirely.
    # (キー1バイトにつき最大1件しか返らないため、数え上げの一巡が不要)
    if max_size == 0 or keylen == 0:
        return result_list
    capacity = keylen
    if max_size > 0 and <size_t>max_size < capacity:
        capacity = <size_t>max_size

    result_vector.resize(capacity)
    ret = trie.obj.commonPrefixSearch[da[int].result_triple_type] (
        key, &result_vector[0], capacity, keylen, from_id)
    if ret > capacity:
        ret = capacity

    for i in range(ret):
        r = result_vector[i]
        result_list.append( (trie.suffix(r.id, r.length), r.value, r.id) )
    return result_list

cdef (int, size_t, npos_t) exact_match_search(base_trie trie, const char* key, size_t keylen, size_t from_id=0):
    cdef da[int].result_triple_type result
    result = trie.obj.exactMatchSearch[da[int].result_triple_type](key, keylen, from_id)
    return result.value, result.length, result.id

cdef inline void reject_embedded_nul(const char* key, size_t keylen) except *:
    """Refuse a key containing a NUL byte. (NUL バイトを含むキーを拒否する)

    cedar stores short suffixes in a NUL terminated tail array, so such a key
    breaks that invariant. It does not merely read back wrong: inserting one and
    then inserting a key that shares its prefix corrupts memory and segfaults.
    Checking here keeps the cost on the write paths, where it is negligible
    next to the insertion itself.
    (cedar は NUL 終端の tail 配列に短い接尾辞を格納するため、不変条件が壊れる。
     読み出しが狂うだけでなく、接頭辞を共有するキーを続けて入れるとメモリ破壊で
     落ちる。検査は書き込み経路に限り、挿入自体に比べれば無視できる)
    """
    if memchr(key, 0, keylen) != NULL:
        raise ValueError(
            "key contains a NUL byte, which cedar uses internally as a "
            "terminator; such a key cannot be stored"
        )

cdef str reserved_value_message(int value):
    # (予約値を格納しようとしたときのメッセージ)
    return (
        "%d is reserved and cannot be stored: %d is base_trie.NO_VALUE and "
        "%d is base_trie.NO_PATH, which cedar uses to mean 'no value here' and "
        "'end of traversal'" % (value, _NO_VALUE, _NO_PATH)
    )

cdef int set(base_trie trie, const char* key, size_t keylen, int value) except *:
    cdef int* r
    if keylen == 0:
        raise KeyError("empty key is invalid")
    reject_embedded_nul(key, keylen)
    if value == _NO_VALUE or value == _NO_PATH:
        raise ValueError(reserved_value_message(value))
    r = <int*>&trie.obj.update(key, keylen, value)
    r[0] = value
    return r[0]

cdef bytes suffix(base_trie trie, npos_t node_id, size_t length=0):
    cdef bytes buf = b'\0' * length
    trie.obj.suffix(buf, length, node_id)
    return buf

cdef int update(base_trie trie, const char* key, size_t keylen, int delta=0) except *:
    cdef int result
    if keylen == 0:
        raise KeyError("empty key is invalid")
    reject_embedded_nul(key, keylen)
    # The result is what matters here, not the delta: a legal delta can still
    # land on a reserved value. Checking afterwards costs one comparison,
    # whereas checking beforehand would cost a second lookup.
    # (問題になるのは加算結果。事前検査では余分なルックアップが要る)
    result = trie.obj.update(key, keylen, delta)
    if result == _NO_VALUE or result == _NO_PATH:
        # Roll the delta back so that no reserved value is left behind.
        # (予約値を残さないようデルタを巻き戻す)
        trie.obj.update(key, keylen, -delta)
        raise ValueError(reserved_value_message(result))
    return result

### specialized trie classes

cdef class bytes_trie(base_trie):
    '''specialized trie class using bytes (standard)'''

    def __cinit__(self):
        pass

    cpdef list common_prefix_predict(self, object key, npos_t from_id=0, int max_size=-1):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_bytes(key, &keylen)
        return common_prefix_predict(self, buf, <size_t>keylen, from_id, max_size)

    cpdef list common_prefix_search(self, object key, npos_t from_id=0, int max_size=-1):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_bytes(key, &keylen)
        return common_prefix_search(self, buf, <size_t>keylen, from_id, max_size)

    cpdef int erase(self, object key, npos_t from_id=0):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_bytes(key, &keylen)
        return self.obj.erase(buf, <size_t>keylen, from_id)

    cpdef (int, size_t, npos_t) exact_match_search(self, object key, npos_t from_id=0):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_bytes(key, &keylen)
        return exact_match_search(self, buf, <size_t>keylen, from_id)

    cpdef int set(self, object key, int value) except *:
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_bytes(key, &keylen)
        return set(self, buf, <size_t>keylen, value)

    cpdef object suffix(self, npos_t node_id, size_t length=0):
        return suffix(self, node_id, length)

    cpdef (int,npos_t,size_t) traverse(self, object key, npos_t from_id=0, size_t pos=0):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_bytes(key, &keylen)
        cdef int result = self.obj.traverse(buf, from_id, pos)
        return result, from_id, pos

    cpdef int update(self, object key, int delta=0):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_bytes(key, &keylen)
        return update(self, buf, <size_t>keylen, delta)

cdef class str_trie(base_trie):
    '''specialized trie class using python standard str'''

    def __cinit__(self):
        pass

    cpdef list common_prefix_predict(self, object key, npos_t from_id=0, int max_size=-1):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_utf8(key, &keylen)
        return common_prefix_predict(self, buf, <size_t>keylen, from_id, max_size)

    cpdef list common_prefix_search(self, object key, npos_t from_id=0, int max_size=-1):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_utf8(key, &keylen)
        return common_prefix_search(self, buf, <size_t>keylen, from_id, max_size)

    cpdef int erase(self, object key, npos_t from_id=0):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_utf8(key, &keylen)
        return self.obj.erase(buf, <size_t>keylen, from_id)

    cpdef (int, size_t, npos_t) exact_match_search(self, object key, npos_t from_id=0):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_utf8(key, &keylen)
        return exact_match_search(self, buf, <size_t>keylen, from_id)

    cpdef int set(self, object key, int value) except *:
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_utf8(key, &keylen)
        return set(self, buf, <size_t>keylen, value)

    cpdef object suffix(self, npos_t node_id, size_t length=0):
        return bytes_to_str( suffix(self, node_id, length) )

    cpdef (int,npos_t,size_t) traverse(self, object key, npos_t from_id=0, size_t pos=0):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_utf8(key, &keylen)
        cdef int result = self.obj.traverse(buf, from_id, pos)
        return result, from_id, pos

    cpdef int update(self, object key, int delta=0):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_utf8(key, &keylen)
        return update(self, buf, <size_t>keylen, delta)

cdef class unicode_trie(base_trie):
    '''specialized trie class using python unicode string'''

    def __cinit__(self):
        pass

    cpdef list common_prefix_predict(self, object key, npos_t from_id=0, int max_size=-1):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_utf8(key, &keylen)
        return common_prefix_predict(self, buf, <size_t>keylen, from_id, max_size)

    cpdef list common_prefix_search(self, object key, npos_t from_id=0, int max_size=-1):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_utf8(key, &keylen)
        return common_prefix_search(self, buf, <size_t>keylen, from_id, max_size)

    cpdef int erase(self, object key, npos_t from_id=0):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_utf8(key, &keylen)
        return self.obj.erase(buf, <size_t>keylen, from_id)

    cpdef (int, size_t, npos_t) exact_match_search(self, object key, npos_t from_id=0):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_utf8(key, &keylen)
        return exact_match_search(self, buf, <size_t>keylen, from_id)

    cpdef int set(self, object key, int value) except *:
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_utf8(key, &keylen)
        return set(self, buf, <size_t>keylen, value)

    cpdef object suffix(self, npos_t node_id, size_t length=0):
        return bytes_to_unicode( suffix(self, node_id, length) )

    cpdef (int,npos_t,size_t) traverse(self, object key, npos_t from_id=0, size_t pos=0):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_utf8(key, &keylen)
        cdef int result = self.obj.traverse(buf, from_id, pos)
        return result, from_id, pos

    cpdef int update(self, object key, int delta=0):
        cdef Py_ssize_t keylen
        cdef const char* buf = key_as_utf8(key, &keylen)
        return update(self, buf, <size_t>keylen, delta)

### utility classes

cdef class node:
    """
    internal node reprsentation
    """
    cdef readonly npos_t id
    cdef readonly npos_t root
    cdef readonly size_t length
    cdef base_trie trie

    def __cinit__(self, base_trie trie, npos_t id, size_t length, npos_t root=0):
        self.trie = trie
        self.id = id
        self.length = length
        self.root = root

    cpdef key(self):
        return self.trie.suffix(self.id, self.length)

    cpdef int value(self):
        return self.trie.exact_match_search(self.key(), self.root)[0]

    #cpdef (npos_t,size_t) track(self):
    #    return self.id, self.length

    cpdef (npos_t,size_t,npos_t) track(self):
        return self.id, self.length, self.root

    def traverse(self, key):
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        cdef npos_t root
        value, root, length = self.trie.traverse(key, self.id)
        if value != _NO_PATH:
            value, node_id, length = self.trie.begin(root, length)
        while value != _NO_PATH:
            yield value, node_id, length
            value, node_id, length = self.trie.next(node_id, length, root)

    def find_nodes(self, key):
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        for value, node_id, length in self.traverse(key):
            yield node(self.trie, node_id, length, self.id)

    cpdef node get_node(self, key):
        cdef int value
        cdef size_t length
        cdef npos_t node_id
        value, length, node_id = self.trie.exact_match_search(key, self.id)
        if value == _NO_PATH or value == _NO_VALUE:
            return None
        else:
            return node(self.trie, node_id, length, self.id)

    def __repr__(self):
        return "pycedar.node(trie=%s, id=%s, length=%s, root=%s)" % (self.trie, self.id, self.length, self.root)

    def __str__(self):
        #return self.key()
        return repr(self.key())


### unpickling factories
# Referenced by __reduce__ above. Kept as module-level functions because pickle
# stores the callable itself, which for a cdef class would embed the class in
# the pickle by value semantics Cython does not provide.
# (__reduce__ から参照される。cdef クラスでは実現できない値渡しセマンティクスに
#  なるのを避けるため、モジュールレベル関数として置く)

def _trie_from_image(type cls, bytes image):
    """Rebuild a trie from a serialized image (pickle support).
    (直列化イメージからトライを復元する。pickle 対応用)"""
    t = cls()
    if t.loads(image) < 0:
        raise ValueError("invalid pycedar image data")
    return t


def _dict_from_image(type key_type, bytes image):
    """Rebuild a pycedar.dict from a serialized image (pickle support).
    (直列化イメージから pycedar.dict を復元する。pickle 対応用)"""
    d = dict(key_type)
    if d.loads(image) < 0:
        raise ValueError("invalid pycedar image data")
    return d


cdef class dict:
    """
    python dict-like class
    """

    cdef readonly base_trie trie
    cdef readonly node root
    cdef readonly object type
    cdef readonly object fallback_cast

    def __cinit__(self, type type=str):
        """
        constructor
        :param type: string type (str, bytes, unicode), default value is str
        :return: pycedar.dict object
        """
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
        self.root = node(self.trie, 0, 0)
        self.type = type

    cpdef clear(self):
        """
        clear all the strings
        """
        self.trie.clear()

    def find(self, key):
        """
        yield all string with prefix string `key` and its value
        :param key: prefix string
        :return: genarator yielding tuple of (string key, int value)
        """
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        for value, node_id, length in self.root.traverse(key):
            yield self.trie.suffix(node_id, length), value

    def find_keys(self, key):
        """
        yield all the string with prefix string `key`
        :param key: prefix string
        :return: genarator yielding key string
        """
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        for value, node_id, length in self.root.traverse(key):
            yield self.trie.suffix(node_id, length)

    def find_values(self, key):
        """
        find all the string with prefix string `key` and yield theire values
        :param key: prefix string
        :return: genarator yielding int value
        """
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        for value, node_id, length in self.root.traverse(key):
            yield value

    cpdef object get(self, object key, object default=base_trie.NO_VALUE):
        """
        get int value associated with `key` string
        :param key: key string
        :param default: value returned when `key` not found (default value is pycedar.base_trie.NO_VALUE)
        :return: if `key` string is found, return its associated int value, otherwise `default`
        """
        cdef int value
        value = self.trie.exact_match_search(key)[0]
        if value == _NO_VALUE or value == _NO_PATH:
            return default
        return value

    cpdef node get_node(self, object key):
        """
        get node object associated with `key` string
        :param key: key string
        :return:
        """
        #return self.trie.get_node(key)
        return self.root.get_node(key)

    cpdef keys(self):
        """
        :return: generator yielding all the key strings
        """
        return self.find_keys(self.type())

    cpdef items(self):
        """
        :return: generator yielding each tuple of (key string, int value)
        """
        return self.find(self.type())

    cpdef int load(self, str filepath, str mode = 'rb'):
        """
        load trie data from `filepath`
        :param filepath: file path to load trie data
        :param mode: file open mode
        """
        return self.trie.open(filepath, mode)

    cpdef nodes(self):
        """
        :return: generator yielding all the nodes
        """
        return self.root.find_nodes(self.type())

    cpdef int save(self, str filepath, str mode = 'wb', bool shrink=True):
        """
        save trie data into `filepath`
        :param filepath: file path to write trie data
        :param mode:  file open mode
        :param shrink: shrinking flat
        """
        return self.trie.save(filepath, mode, shrink)

    cpdef bytes dumps(self, bool shrink=True):
        """
        serialize the trie image into bytes (see pycedar.base_trie.dumps)
        :param shrink: shrinking flat
        :return: bytes object holding the serialized trie image
        """
        return self.trie.dumps(shrink)

    cpdef int loads(self, bytes data):
        """
        replace the trie with a serialized image (see pycedar.base_trie.loads)
        :param data: bytes produced by dumps() or save()
        :return: 0 on success, -1 on malformed input (the trie is left empty)
        """
        return self.trie.loads(data)

    cpdef int set(self, object key, int value) except *:
        """
        set value associating with `key` string
        :param key: key string
        :param value: int value
        """
        return self.trie.set(key, value)

    cpdef int setdefault(self, object key, int value=0) except *:
        """
        if `key` string is not found, set associating int value
        :param key:  key string
        :param value: int value
        :return: if `key` string is not found, return new int value, otherwise existing int value
        """
        cdef int result
        result = self.trie.exact_match_search(key)[0]
        if result == _NO_VALUE or result == _NO_PATH:
            result = self.set(key, value)
        return result

    cpdef int update(self, object key, int delta=0):
        """
        register `key` string and update associating value with delta (adding to existing value)
        :param key: key string
        :param delta: differential int value (default is 0)
        :return: updated int value associating with `key` string
        """
        return self.trie.update(key, delta)

    cpdef object pop(self, object key, object default=_POP_MISSING):
        """
        remove `key` and return its value, like dict.pop
        :param key: key string
        :param default: value returned when `key` is not found; when omitted,
                        a missing key raises KeyError
        :return: the value `key` carried, or `default`
        """
        cdef int value = self.trie.exact_match_search(key)[0]
        if value == _NO_VALUE or value == _NO_PATH:
            if default is _POP_MISSING:
                raise KeyError(key)
            return default
        # The lookup above found the key, so the erase cannot fail; the check
        # stays as a backstop against a malformed trie image.
        # (直前の検索で見つかっているため失敗はありえないが、不正なイメージ対策の
        #  保険として残す)
        if self.trie.erase(key) < 0:
            raise KeyError(key)
        return value

    cpdef tuple popitem(self):
        """
        remove and return the first (key, value) pair in the trie's enumeration
        order, which is sorted-key order. Note this differs from dict.popitem,
        which pops the most recently inserted item: a trie keeps no insertion
        order, so the lexicographically smallest remaining key is returned.
        (列挙順 = ソート順で最初の (キー, 値) を取り除いて返す。トライは挿入順を
         保持しないため、dict.popitem と異なり辞書順で最小の残存キーが返る)
        :return: tuple of (key string, int value)
        """
        cdef int value
        cdef npos_t node_id
        cdef size_t length
        value, node_id, length = self.trie.begin(0, 0)
        if value == _NO_PATH:
            raise KeyError("'popitem(): dictionary is empty'")
        key = self.trie.suffix(node_id, length)
        if self.trie.erase(key) < 0:
            raise KeyError(key)
        return key, value

    cpdef values(self):
        """
        :return: generator yielding all the int values associating with registered keys
        """
        return self.find_values(self.type())

    def __len__(self):
        return self.trie.num_keys()

    def __contains__(self, key):
        cdef int value = self.trie.exact_match_search(key)[0]
        if value == _NO_VALUE or value == _NO_PATH:
            return False
        return True

    def __iter__(self):
        return self.keys()

    def __delitem__(self, key):
        if self.trie.erase(key) < 0:
            raise KeyError(key)

    def __getitem__(self, key):
        cdef int value
        value = self.trie.exact_match_search(key)[0]
        if value == _NO_VALUE or value == _NO_PATH:
            raise KeyError(key)
        return value

    def __setitem__(self, key, int value):
        self.trie.set(key, value)

    def __reduce__(self):
        # Pickle through the serialized image, carrying the key type so that
        # the rebuilt dict enforces the same key type.
        # (直列化イメージ経由で pickle 化する。キー型も渡し、復元後に同じ型検査が
        #  働くようにする)
        return (_dict_from_image, (self.type, self.dumps()))
