# pycedar

![version](https://img.shields.io/pypi/v/pycedar.svg)
![python](https://img.shields.io/pypi/pyversions/pycedar.svg)
![license](https://img.shields.io/pypi/l/pycedar.svg)

Python binding of ``cedar`` (implementation of efficiently-updatable double-array trie) using Cython

日本語版の README は [README.ja.md](README.ja.md) にあります。

Official URL of ``cedar``: http://www.tkl.iis.u-tokyo.ac.jp/~ynaga/cedar/

## Requirements

* Python 3.9 or newer
* A POSIX-compatible 64-bit platform (Linux, macOS)
* A C++ compiler, when building from source

The extension is tested with CPython 3.9 through 3.14 on Linux and macOS.

## Installation

### install from PyPI release

```shell
$ pip install --user pycedar
```

### install from GitHub master

```shell
$ pip install --user https://github.com/akivajp/pycedar/archive/master.zip
```

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
| ``update(key, delta=0)`` | Add ``delta`` to a key's value, registering it if needed. |
| ``clear()`` | Drop all keys. |
| ``keys()``, ``values()``, ``items()``, ``nodes()`` | Generators over the whole trie. |
| ``find(prefix)``, ``find_keys(prefix)``, ``find_values(prefix)`` | Generators scoped to ``prefix``. |
| ``get_node(key)`` | The ``node`` for ``key``, or ``None``. |
| ``save(filepath, mode='wb', shrink=True)`` | Write a trie image. Returns ``0`` / ``-1``. |
| ``load(filepath, mode='rb')`` | Replace the trie with a stored image. Returns ``0`` / ``-1``. |

``pycedar.__version__`` exposes the installed package version.

## Limitations

### Values are C ``int`` sized, and two of them are reserved

Values are stored as C ``int``, so they must fit in ``-2**31 .. 2**31-1``;
anything larger raises ``OverflowError``.

Two values collide with cedar's sentinels and must not be stored:

* **``-1`` (``NO_VALUE``)** — the key is stored and appears during iteration,
  but ``in``, ``get()`` and ``d[key]`` all report it as absent.
* **``-2`` (``NO_PATH``)** — this value terminates traversal, so ``items()``,
  ``keys()``, ``values()``, ``find()`` and friends silently stop at that key and
  never reach the rest of the trie.

Storing non-negative values avoids both problems. Every other value, including
other negative numbers, round trips normally.

### The serialization format is platform-dependent and unauthenticated

The native cedar ``.dat`` format depends on the pointer size and byte order of
the machine that wrote it, and it carries no integrity checks. Only load files
produced by pycedar on a compatible platform and obtained from a trusted
source.

### I/O failures are reported through return codes

``save()`` / ``load()`` / ``open()`` return ``0`` on success and ``-1`` on
failure instead of raising; check the return value.

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
``pycedar/core/cedar/`` carries two local modifications, documented at the top
of [``cedarpp.h``](pycedar/core/cedar/src/cedarpp.h).

See [CHANGELOG.md](CHANGELOG.md) for the list of contributors to each release.
