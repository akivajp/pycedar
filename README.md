# pycedar

![version](https://img.shields.io/pypi/v/pycedar.svg)
![python](https://img.shields.io/pypi/pyversions/pycedar.svg)
![license](https://img.shields.io/pypi/l/pycedar.svg)

Python binding of ``cedar`` (implementation of efficiently-updatable double-array trie) using Cython

日本語版の README は [README.ja.md](README.ja.md) にあります。

Official URL of ``cedar``: http://www.tkl.iis.u-tokyo.ac.jp/~ynaga/cedar/

## Requirements

* Python 3.9 or newer
* A 64-bit platform: Windows, or a POSIX-compatible one (Linux, macOS)
* A C++ compiler, when building from source (wheels need none)

The extension is tested with CPython 3.9 through 3.14 on Linux, macOS and
Windows, including the free-threaded build of 3.14 (``3.14t``). Wheels cover
Linux (x86_64, aarch64), macOS (x86_64, arm64) and Windows (AMD64, ARM64).
The module is
declared free-threading compatible, so it imports and works on a free-threaded
interpreter without a ``ModuleNotFoundError``; concurrency across *distinct*
trie objects is supported (see [Limitations](#limitations)).

## Why a double-array trie?

A trie encodes the keys into its arrays, so it does not keep a separate string
object per key, and it answers prefix queries that a hash map cannot.

200000 random lowercase keys of 4 to 16 characters, mapped to integers,
measured with `benchmarks/bench.py` on CPython 3.13 (Linux, x86_64):

| | builtin `dict` | pycedar |
| --- | ---: | ---: |
| hash table and values | 13.43 MB | — |
| key strings | 9.73 MB | — |
| node array | — | 2.35 MB |
| tail array | — | 2.06 MB |
| **total** | **23.16 MB** | **4.40 MB** |
| per key | 121 bytes | 23 bytes |

The trade is real and worth stating plainly: a point lookup costs roughly twice
what a `dict` lookup does (30 ns against 16 ns on the same data; the numbers
vary by machine). Reach
for pycedar when the key set is large enough that memory matters, or when you
need prefix search; reach for a `dict` when you only need point lookups.

Run `python benchmarks/bench.py --help` to reproduce these numbers on your own
data.

## Installation

### install from PyPI release

```shell
$ pip install --user pycedar
```

### install from GitHub master

```shell
$ pip install --user https://github.com/akivajp/pycedar/archive/master.zip
```

## Type checking

Type stubs ship as the ``pycedar-stubs`` package (PEP 561). Type checkers and
IDEs pick them up automatically once pycedar is installed — no extra step.
(型スタブは ``pycedar-stubs`` パッケージとして同梱されるため、インストール後は
 型検査器や IDE が自動で API を認識する)

## Usage

### using python-like dict class based on double array trie

```python
>>> import pycedar

>>> d = pycedar.dict()
>>> len(d)
0
>>> bool(d)
False
>>> list(d)
[]

>>> d['nineteen'] = 19
>>> d.set('twenty', 20)
20
>>> d['twenty one'] = 21
>>> d['twenty two'] = 22
>>> d['twenty three'] = 23
>>> d['twenty four'] = 24

>>> len(d)
6
>>> bool(d)
True
>>> list(d)
['nineteen', 'twenty', 'twenty four', 'twenty one', 'twenty three', 'twenty two']
>>> list(d.keys())
['nineteen', 'twenty', 'twenty four', 'twenty one', 'twenty three', 'twenty two']
>>> list(d.values())
[19, 20, 24, 21, 23, 22]
>>> list(d.items())
[('nineteen', 19), ('twenty', 20), ('twenty four', 24), ('twenty one', 21), ('twenty three', 23), ('twenty two', 22)]
>>> d['twenty four']
24
>>> 'twenty four' in d
True
>>> del d['twenty four']
>>> 'twenty four' in d
False
>>> d['twenty four']
Traceback (most recent call last):
    ...
KeyError: 'twenty four'
>>> d.get('twenty three')
23
>>> d.get('twenty four')       # the default is base_trie.NO_VALUE
-1
>>> d.get('twenty four', None) is None
True
```

Prefix queries return generators:

```python
>>> list(d.find(''))
[('nineteen', 19), ('twenty', 20), ('twenty one', 21), ('twenty three', 23), ('twenty two', 22)]
>>> list(d.find('tw'))
[('twenty', 20), ('twenty one', 21), ('twenty three', 23), ('twenty two', 22)]
>>> list(d.find('twenty t'))
[('twenty three', 23), ('twenty two', 22)]
>>> list(d.find_keys('twenty'))
['twenty', 'twenty one', 'twenty three', 'twenty two']
>>> list(d.find_values('twenty'))
[20, 21, 23, 22]
```

Nodes let you keep a position in the trie and search relative to it:

```python
>>> n = d.get_node('twenty')
>>> n.key()
'twenty'
>>> n.value()
20
>>> [child.key() for child in n.find_nodes(' t')]
[' three', ' two']

>>> d.get_node('twenty ') is None    # a path without a value
True
```

Saving and loading:

```python
>>> d.save('test.dat')
0
>>> d2 = pycedar.dict()
>>> d2.setdefault('eighteen', 18)
18
>>> list(d2.items())
[('eighteen', 18)]
>>> d2.load('test.dat')              # replaces the whole trie image
0
>>> list(d2.items())
[('nineteen', 19), ('twenty', 20), ('twenty one', 21), ('twenty three', 23), ('twenty two', 22)]
>>> d2.setdefault('eighteen', 18)
18
>>> list(d2.items())
[('eighteen', 18), ('nineteen', 19), ('twenty', 20), ('twenty one', 21), ('twenty three', 23), ('twenty two', 22)]
```

The image can also be kept in memory as ``bytes``, and the dict supports
pickling and copying:

```python
>>> import pickle, copy

>>> image = d.dumps()
>>> restored = pickle.loads(pickle.dumps(d))
>>> restored['twenty']
20
>>> clone = copy.deepcopy(d)             # copy.copy works the same way
>>> clone['twenty'] = 999
>>> d['twenty']
20

>>> d.pop('twenty two')                  # like dict.pop
22
>>> d.pop('twenty two', 'gone')
'gone'
>>> d.popitem()                          # removes the first key in sorted order
('nineteen', 19)
```

``popitem()`` returns the lexicographically smallest remaining key, because a
trie keeps no insertion order — this is the one place ``pycedar.dict``
intentionally differs from ``dict``.

### using bytes keys

``pycedar.dict`` is parameterised by its key type, which is enforced strictly:

```python
>>> b = pycedar.dict(bytes)
>>> b[b'cedar'] = 1
>>> b[b'cedarpp'] = 2
>>> list(b.items())
[(b'cedar', 1), (b'cedarpp', 2)]
>>> b['str key'] = 3
Traceback (most recent call last):
    ...
TypeError: Argument 'key' has incorrect type (expected bytes, got str)
```

``str`` keys are encoded as UTF-8 before they reach cedar, so lengths reported
by the low level API are byte lengths, not character counts.

### using more primitive data structures

``pycedar.dict`` is a thin convenience layer over the trie classes. You can use
them directly when you want cedar's raw semantics.

```python
>>> t = pycedar.str_trie()
>>> t.set('apple', 1)
1
>>> t.set('applet', 2)
2
>>> t.set('apply', 3)
3

>>> t.exact_match_search('apple')      # (value, length, node id)
(1, 5, 259)
>>> t.exact_match_search('app')[0]     # a prefix carries no value
-1

>>> t.common_prefix_search('applet')   # every key that prefixes the query
[('apple', 1, 259), ('applet', 2, 368)]
>>> [key for key, value, node_id in t.common_prefix_predict('app')]
['le', 'let', 'ly']

>>> t.erase('apply')
0
>>> t.erase('apply')                   # already gone
-1
>>> t.num_keys()
2
```

Note the difference between the two prefix queries:

* ``common_prefix_search(key)`` returns the **complete keys** that are prefixes
  of ``key``.
* ``common_prefix_predict(key)`` returns the **remaining suffixes** of every key
  that starts with ``key``.

Both also have lazy variants that yield one triple at a time instead of
building a list, which matters when a query can match a large part of the trie
or when the first hits are all you need:

```python
>>> [key for key, value, node_id in t.icommon_prefix_predict('app')]   # 'apply' was erased above
['le', 'let']
>>> list(t.icommon_prefix_search('applet'))
[('apple', 1, 259), ('applet', 2, 368)]
```

The lazy variants return the same triples in the same order as the list
versions; results are not guaranteed if the trie is modified while iterating.
Whether laziness pays depends on how early you stop. Measured with
``benchmarks/bench.py`` on the 20000-key set from the table above, taking only
the first hit of a 2-character predict costs roughly a tenth of the full list
(332 ns against 2892 ns per prefix), while draining the whole generator costs
about 10% more than the list version; the search variants, whose results are
capped at one per key byte, are cheap either way.
(遅延版は list 版と同じ組を同じ順で返す。反復中のトライ変更時の結果は保証されない。
 早期に打ち切るほど遅延版が有利になる。上の表と同じ 20000 キーで
 ``benchmarks/bench.py`` により計測した結果、2 文字の predict で先頭 1 件のみの
 取得は全件 list 化の約 1/10 (プレフィックスあたり 332 ns に対し 2892 ns)、
 ジェネレータを最後まで消費すると list 版より約 1 割遅い。search の結果は
 キー1バイトあたり最大1件のためどちらでも安価)

Enumerating a trie (or a subtree) uses ``begin`` / ``next``:

```python
>>> result, from_id, pos = t.traverse('app')   # locate the subtree
>>> value, node_id, length = t.begin(from_id, pos)
>>> while value != pycedar.base_trie.NO_PATH:
...     print(t.suffix(node_id, length), value)
...     value, node_id, length = t.next(node_id, length, from_id)
apple 1
applet 2
```

## API reference

### ``pycedar.base_trie``

Base class for every trie. Not meant to be instantiated directly.

| Member | Description |
| --- | --- |
| ``NO_VALUE`` | ``-1``. Returned when a node exists but carries no value. |
| ``NO_PATH`` | ``-2``. Returned when the path does not exist, and used as the traversal terminator. |
| ``root`` | The ``node`` object for the trie root. |
| ``clear(reuse=True)`` | Drop all keys. |
| ``capacity()``, ``size()``, ``length()``, ``total_size()``, ``unit_size()``, ``nonzero_size()``, ``nonzero_length()``, ``num_keys()`` | cedar's internal statistics. ``num_keys()`` is the number of registered keys. |
| ``begin(from_id=0, length=0)`` | Start an enumeration. Returns ``(value, node_id, length)``. |
| ``next(node_id, length, root=0)`` | Advance an enumeration. Returns ``(value, node_id, length)``. |
| ``open(filepath, mode='rb', offset=0, size=0)`` | Load a trie image. Returns ``0`` on success, ``-1`` on failure. |
| ``save(filepath, mode='wb', shrink=True)`` | Write a trie image. Returns ``0`` on success, ``-1`` on failure. |
| ``dumps(shrink=True)`` | The trie image as ``bytes``. The layout is byte-for-byte what ``save()`` writes, so the two are interchangeable. |
| ``loads(data)`` | Replace the trie with an image from any bytes-like object (``bytes``, ``bytearray``, ``memoryview``, ...). Returns ``0`` / ``-1``. Unlike a failed ``load()``, malformed input is rejected before the current contents are touched, so the trie keeps them. |
| ``icommon_prefix_search(key, from_id=0, max_size=-1)`` | Lazy generator variant of ``common_prefix_search()``; yields the same ``(key, value, node_id)`` triples one at a time. Inherited by the specializations. |
| ``icommon_prefix_predict(key, from_id=0, max_size=-1)`` | Lazy generator variant of ``common_prefix_predict()``; yields the same ``(suffix, value, node_id)`` triples one at a time. Inherited by the specializations. |

### ``pycedar.str_trie`` / ``pycedar.bytes_trie`` / ``pycedar.unicode_trie``

Specialisations of ``base_trie`` for ``str`` keys, ``bytes`` keys, and
``unicode`` keys respectively. On Python 3, ``unicode`` is ``str``, so
``unicode_trie`` behaves identically to ``str_trie`` and is kept only for
backward compatibility.

In addition to the ``base_trie`` members:

| Method | Description |
| --- | --- |
| ``set(key, value)`` | Register ``key`` with ``value``. Returns the stored value. Raises ``KeyError`` for an empty key. |
| ``update(key, delta=0)`` | Register ``key`` if needed and add ``delta`` to its value. Returns the new value. |
| ``erase(key, from_id=0)`` | Remove ``key``. Returns ``0`` on success, ``-1`` if it was not registered. |
| ``exact_match_search(key, from_id=0)`` | Returns ``(value, length, node_id)``. ``value`` is ``NO_VALUE`` / ``NO_PATH`` when not found. |
| ``common_prefix_search(key, from_id=0, max_size=-1)`` | Returns a list of ``(key, value, node_id)`` for every key that prefixes ``key``. |
| ``common_prefix_predict(key, from_id=0, max_size=-1)`` | Returns a list of ``(suffix, value, node_id)`` for every key starting with ``key``. |
| ``traverse(key, from_id=0, pos=0)`` | Follow ``key`` from ``from_id``. Returns ``(value, node_id, pos)``. |
| ``suffix(node_id, length=0)`` | Reconstruct the key ending at ``node_id``. |

``max_size`` caps the number of returned results; ``-1`` means "no limit".
``from_id`` scopes the query to a subtree.

### ``pycedar.node``

A cursor into a trie. Obtained from ``base_trie.root``, ``dict.root``,
``dict.get_node()``, ``dict.nodes()`` or ``node.find_nodes()``.

| Member | Description |
| --- | --- |
| ``id``, ``length``, ``root`` | Read-only position information. |
| ``key()`` | The key this node represents, relative to ``root``. |
| ``value()`` | The value stored at this node. |
| ``track()`` | Returns ``(id, length, root)``. |
| ``traverse(key)`` | Generator yielding ``(value, node_id, length)`` for the subtree under ``key``. |
| ``find_nodes(key)`` | Generator yielding ``node`` objects for the subtree under ``key``. |
| ``get_node(key)`` | The ``node`` for ``key``, or ``None`` if it is absent or carries no value. |

### ``pycedar.dict``

A ``dict``-like façade over a trie. ``pycedar.dict(key_type)`` accepts ``str``
(the default) or ``bytes``.

| Member | Description |
| --- | --- |
| ``trie``, ``root``, ``type`` | The underlying trie, its root ``node``, and the key type. |
| ``d[key]`` | The value, or ``KeyError``. |
| ``d[key] = value`` | Register a key. ``KeyError`` for an empty key. |
| ``del d[key]`` | Remove a key, or ``KeyError``. |
| ``key in d``, ``len(d)``, ``iter(d)`` | Membership, number of keys, iteration over keys. |
| ``get(key, default=NO_VALUE)`` | The value, or ``default``. |
| ``set(key, value)`` | Register a key. Returns the stored value. |
| ``setdefault(key, value=0)`` | Register only if absent. Returns the effective value. |
| ``pop(key, default=…)`` | Remove ``key`` and return its value; raises ``KeyError`` without a default when absent. |
| ``popitem()`` | Remove and return the first ``(key, value)`` in sorted-key order. ``KeyError`` when empty. Unlike ``dict.popitem()``, which pops the most recent insertion — a trie keeps no insertion order. |
| ``update(key, delta=0)`` | Add ``delta`` to a key's value, registering it if needed. |
| ``clear()`` | Drop all keys. |
| ``keys()``, ``values()``, ``items()``, ``nodes()`` | Generators over the whole trie. |
| ``find(prefix)``, ``find_keys(prefix)``, ``find_values(prefix)`` | Generators scoped to ``prefix``. |
| ``get_node(key)`` | The ``node`` for ``key``, or ``None``. |
| ``save(filepath, mode='wb', shrink=True)`` | Write a trie image. Returns ``0`` / ``-1``. |
| ``load(filepath, mode='rb')`` | Replace the trie with a stored image. Returns ``0`` / ``-1``. |
| ``dumps(shrink=True)`` | The trie image as ``bytes``; interchangeable with ``save()`` files. |
| ``loads(data)`` | Replace the trie with an image from ``dumps()``/``save()``, given as any bytes-like object (``bytes``, ``bytearray``, ``memoryview``, ...). Returns ``0`` / ``-1``. |

``pycedar.dict`` (and the trie classes) support ``pickle``, ``copy.copy()`` and
``copy.deepcopy()`` through the same serialized image.

``pycedar.__version__`` exposes the installed package version.

## Limitations

### Concurrent access is safe only across distinct tries

The module is declared free-threading compatible (PEP 703) and works on
free-threaded CPython 3.14. That covers using *separate* trie objects from
several threads at once, which the test suite exercises.

It does not make an individual trie thread-safe: concurrent operations on the
*same* trie race, exactly as they would under the GIL, and can corrupt it.
Guard a shared trie with a lock as you would any other mutable object.

### Values are C ``int`` sized, and two of them are reserved

Values are stored as C ``int``, so they must fit in ``-2**31 .. 2**31-1``;
anything larger raises ``OverflowError``.

``-1`` and ``-2`` are cedar's sentinels — ``base_trie.NO_VALUE`` and
``base_trie.NO_PATH`` — and every writer rejects them:

```python
>>> limited = pycedar.dict()
>>> limited['key'] = -1
Traceback (most recent call last):
    ...
ValueError: -1 is reserved and cannot be stored: ...
```

``update()`` checks the resulting value rather than the delta, because a
perfectly ordinary delta can still land on a sentinel. When it does, the delta
is rolled back and the stored value is left untouched:

```python
>>> limited['counter'] = 1
>>> limited.update('counter', -3)     # 1 + (-3) == -2
Traceback (most recent call last):
    ...
ValueError: -2 is reserved and cannot be stored: ...
>>> limited['counter']
1
```

Every other value round trips, negative ones included.

Before 0.3.0 these two were accepted and silently corrupted the trie: ``-1``
made a key invisible to ``in``, ``get()`` and ``d[key]`` while leaving it
visible to iteration, and ``-2`` ended every traversal early, hiding each key
that came after it. If you are upgrading and were storing either, the values
were not being read back correctly in the first place.

### Keys cannot contain a NUL byte

cedar keeps short key suffixes in a NUL terminated array, so a key carrying a
NUL of its own breaks that invariant. Such keys are rejected:

```python
>>> keyed = pycedar.dict()
>>> keyed['a\x00b'] = 1
Traceback (most recent call last):
    ...
ValueError: key contains a NUL byte, ...
```

Before 0.4.0 the write was accepted, and it did more than read back wrong:
inserting such a key and then inserting one that shared its prefix corrupted
memory and crashed the interpreter.

### The serialization format is platform-dependent and unauthenticated

The native cedar ``.dat`` format depends on the pointer size and byte order of
the machine that wrote it, and it carries no integrity checks. Only load files
produced by pycedar on a compatible platform and obtained from a trusted
source.

The same applies to ``dumps()`` / ``loads()``, which use the identical layout,
and to ``pickle`` — pickling serializes this image, so pickles are only
portable between machines of the same platform and integrity is not verified.
(シリアライズはプラットフォーム依存かつ改竄検査なし。``dumps()``/``loads()`` や
 ``pickle`` も同一レイアウトを使用するため同様)

### I/O failures are reported through return codes

``save()`` / ``load()`` / ``open()`` return ``0`` on success and ``-1`` on
failure instead of raising; check the return value.

Running out of memory is the exception to that rule: ``save()`` and ``load()``
raise ``MemoryError`` rather than returning ``-1``. A failed ``load()`` leaves
the trie **empty**, because the previous contents are released before the new
ones are allocated. The instance stays valid and can be reused. See
[``pycedar/core/cedar/README.md``](pycedar/core/cedar/README.md).

## Development

```shell
$ python -m pip install --upgrade pip
$ python -m pip install . pytest
$ pytest
```

To rebuild in place while iterating on ``pycedar.pyx``:

```shell
$ python -m pip install "Cython>=3.1,<4" setuptools
$ python setup.py build_ext --inplace
```

``./clean.sh`` removes build artifacts.

### Benchmarks

``benchmarks/bench.py`` times the operations pycedar is used for. Run it against
two builds to check whether a change actually paid off:

```shell
$ python benchmarks/bench.py --label before
$ python benchmarks/bench.py --label after
```

It uses ``rich`` for the table when that is installed, and plain text
otherwise. ``--help`` lists the knobs.

## Releasing

The version lives in a single place, [``pycedar/VERSION``](pycedar/VERSION).

1. Update ``pycedar/VERSION`` and ``CHANGELOG.md``.
2. Commit and push to ``master``.
3. Push a matching tag, e.g. ``git tag v0.2.0 && git push origin v0.2.0``.

The [release workflow](.github/workflows/release.yml) verifies that the tag
matches ``pycedar/VERSION``, builds the sdist and the Linux/macOS wheels with
``cibuildwheel``, and publishes them to PyPI via Trusted Publishing.

## License

pycedar is distributed under the same terms as ``cedar`` itself: GPLv2,
LGPLv2.1 and BSD-2-Clause. See the license files bundled under
[``pycedar/core/cedar/``](pycedar/core/cedar/).

## Credits

``cedar`` is written by Naoki Yoshinaga. The copy vendored under
``pycedar/core/cedar/`` carries local modifications.
[``pycedar/core/cedar/README.md``](pycedar/core/cedar/README.md) records what
was changed and why, why the 2022 upstream tarball was deliberately not
re-vendored, and what has to be re-applied if anyone syncs with a newer
release.

See [CHANGELOG.md](CHANGELOG.md) for the list of contributors to each release.
