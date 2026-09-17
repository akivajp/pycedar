# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Windows support: the extension builds under MSVC and CI builds ``AMD64``
  wheels on ``windows-latest``, so prebuilt wheels are now available for
  Windows alongside Linux and macOS.
- Free-threaded CPython support: the extension declares itself
  free-threading compatible (PEP 703) via Cython's
  ``freethreading_compatible`` directive, so it imports and works on a
  free-threaded interpreter (tested on ``3.14t``). Wheels for ``cp314t`` are
  built by CI. This covers concurrency across distinct trie objects;
  concurrent operations on the *same* trie are still not thread-safe.

## [0.5.0] - 2026-09-18

### Added

- ``dict``-like ``pop()`` and ``popitem()`` on ``pycedar.dict``. ``pop()``
  behaves like ``dict.pop``; ``popitem()`` removes and returns the first pair
  in the trie's enumeration order, which is sorted-key order — a trie keeps no
  insertion order, so unlike ``dict.popitem`` it does not return the most
  recently inserted item.
- In-memory serialization: ``dumps()`` returns the trie image as ``bytes`` and
  ``loads()`` replaces the trie with one. The layout is byte-for-byte what
  ``save()`` writes to a file, so the two forms are interchangeable. Unlike a
  failed ``load()``, ``loads()`` rejects a malformed image before touching the
  current contents, so the trie keeps them.
- ``pickle`` support for ``pycedar.dict`` and the trie classes, serializing
  through the same image; ``copy.copy()`` and ``copy.deepcopy()`` work the same
  way. As with ``save()``/``load()``, images are platform-dependent and carry
  no integrity checks.
- Type stubs, shipped as the PEP 561 stub-only package ``pycedar-stubs``, so
  type checkers and IDEs pick the API up without extra configuration.

## [0.4.0] - 2026-09-17

### Changed

- **Breaking**: a key containing a NUL byte now raises `ValueError`. cedar
  keeps short key suffixes in a NUL terminated array, so such a key breaks that
  invariant. It did not merely read back wrong: inserting one and then
  inserting a key that shared its prefix corrupted memory and crashed the
  interpreter with SIGSEGV, from pure Python input and with no unsafe API
  involved. The check runs on the write paths only, where it costs one `memchr`
  over the key, about 1 ns.
- Operations on `str` keys are roughly twice as fast. Each call used to build a
  temporary `bytes` object to hand cedar the key's UTF-8 form; measurement put
  that at 62% of the cost of a `str` lookup, against a `bytes` trie that skips
  it. The key's UTF-8 bytes are now borrowed through
  `PyUnicode_AsUTF8AndSize()`, which for an ASCII string returns the string's
  own storage with nothing copied, and for any other string returns the
  representation CPython caches on the object.

  Measured on 20000 random keys, CPython 3.13, nanoseconds per operation:

  | operation | 0.3.1 | 0.4.0 | builtin `dict` |
  | --- | ---: | ---: | ---: |
  | `key in d` | 52 | 21 | — |
  | `d[key]` | 61 | 28 | 12 |
  | `d.get(key)` | 67 | 35 | — |
  | `d[key] = value` | 61 | 27 | — |
  | `d.set(key, value)` | 70 | 38 | — |
  | `d.update(key, delta)` | 75 | 38 | — |
  | `d.setdefault(key)` | 67 | 34 | — |
  | `d.get_node(key)` | 99 | 65 | — |

  A point lookup now costs roughly twice a `dict` lookup rather than five
  times. Keys outside ASCII are converted once per string object rather than
  once per call, since CPython caches the result on the object.

## [0.3.1] - 2026-09-16

### Changed

- Lookups, writes and traversals are faster, with no change in behaviour.

  `base_trie` declared only the operations that do not depend on the key type.
  Everything else — `exact_match_search()`, `suffix()`, `set()`, `update()`,
  `traverse()`, `erase()` and the prefix queries — lived only on the
  specialisations, while the shared helpers and `pycedar.dict` hold a
  `base_trie` reference. Every one of those calls was therefore a Python method
  lookup by name, with each C integer argument boxed into a Python `int` on the
  way in. They are now declared on `base_trie`, so the calls dispatch through
  the vtable instead. The key parameter is typed as `object` because the three
  specialisations accept different types; each one still validates what it is
  given.
- `common_prefix_search()` no longer walks the trie twice. cedar advances one
  position per byte of the key, so the result can never exceed `len(key)`;
  sizing the buffer to that removes the counting pass entirely.
  `common_prefix_predict()` has no such bound, so it starts from a speculative
  buffer and retries once, at the exact size cedar reports, only when the
  results do not fit.

  Measured on 20000 random keys, CPython 3.13, nanoseconds per operation:

  | operation | 0.3.0 | 0.3.1 |
  | --- | --- | --- |
  | `key in d` | 98 | 52 |
  | `d[key]` | 107 | 61 |
  | `d.get(key)` | 114 | 67 |
  | `d.setdefault(key)` | 103 | 67 |
  | `d.get_node(key)` | 145 | 99 |
  | `d[key] = value` | 78 | 61 |
  | `d.set(key, value)` | 85 | 70 |
  | `d.update(key, delta)` | 90 | 75 |
  | `common_prefix_predict()` | 3568 | 2572 |
  | `list(d.items())` per key | 188 | 163 |

  `exact_match_search()` called directly on a specialisation stayed at 82 ns,
  as it should: that call was never the dynamic one.

## [0.3.0] - 2026-09-16

### Changed

- **Breaking**: storing `-1` or `-2` now raises `ValueError`. They are cedar's
  sentinels, `base_trie.NO_VALUE` and `base_trie.NO_PATH`, and accepting them
  silently corrupted the trie: `-1` made a key invisible to `in`, `get()` and
  `d[key]` while leaving it visible to iteration, and `-2` terminated every
  traversal early, hiding each key stored after it. Anyone affected was already
  unable to read those values back, so the exception replaces silent data loss
  rather than working behaviour.

  The check lives in the writers shared by both layers, so `d[key] = value`,
  `set()`, `setdefault()` and the trie level `set()` all enforce it.
  `update()` validates the resulting value instead of the delta, because an
  ordinary delta can still land on a sentinel; when it does, the delta is
  rolled back and the stored value is left untouched. A key created by such a
  rejected `update()` is left registered with the value `0`.

  As a consequence, `get()` returning `NO_VALUE` is now unambiguous: no stored
  value can collide with it.

## [0.2.2] - 2026-09-16

### Added

- `benchmarks/bench.py`, which times the operations pycedar is used for so that
  a performance change can be measured rather than assumed.

### Changed

- `dict.get()`, `set()`, `setdefault()`, `update()` and `get_node()` are roughly
  twice as fast. They were declared with a fused `str`/`bytes` parameter, and
  Cython's runtime dispatch for that cost more than the trie operation itself.
  The parameter is now `object`, which is what `d[key]` already used; the key
  type is still enforced by the trie underneath, so behaviour is unchanged.
- Sentinel checks on the lookup paths compare against C constants instead of
  building a Python tuple of Python ints on every call, which speeds up
  `d[key]`, `key in d` and the traversals.

  Measured on 20000 random keys, CPython 3.13, nanoseconds per operation:

  | operation | 0.2.1 | 0.2.2 |
  | --- | --- | --- |
  | `d.get(key)` | 302 | 135 |
  | `d.set(key, value)` | 242 | 108 |
  | `d.update(key, delta)` | 235 | 112 |
  | `d.setdefault(key)` | 290 | 129 |
  | `d.get_node(key)` | 348 | 177 |
  | `d[key]` | 165 | 132 |
  | `key in d` | 133 | 123 |

### Fixed

- `node.traverse()` compared integers with `is`, which only worked because
  CPython interns small integers. It now uses `!=`.

## [0.2.1] - 2026-09-16

### Added

- `pycedar/core/cedar/README.md`, recording what was modified in the vendored
  copy of cedar and why, that upstream's `cedarpp.h` has been unchanged since
  2017 despite the 2022 tarball, and why that tarball was deliberately not
  re-vendored.

### Changed

- Allocation failures now raise `MemoryError` instead of `RuntimeError`. The
  vendored cedar throws `std::bad_alloc`, which Cython's `except +` maps to
  `MemoryError`, so every allocation failure reaches Python as the same, and
  the idiomatic, exception. `RuntimeError` is now reserved for the one
  non-allocation case, a zero-length key reaching cedar's `update()`.
- The vendored `cedarpp.h` adopts upstream's `clear()` layout and its
  `STATIC_ASSERT` pragmas. Behaviour is unchanged; this removes the six
  compiler warnings the file used to emit and reduces the delta against
  upstream.

### Fixed

- An allocation failure inside `save()` or `load()` no longer terminates the
  interpreter. The vendored cedar called `std::exit(1)` from `shrink_tail()`
  and `open()`, killing the process and discarding buffered output; both now
  throw. `open()` resets itself to a valid empty trie first, so the instance
  stays usable instead of being handed back half-built.
- `load()` no longer leaks a file descriptor every time it fails. Upstream's
  `open()` returns `-1` from nine places without closing the file; 200 failed
  loads leaked exactly 200 descriptors, eventually exhausting the table.

## [0.2.0] - 2026-09-16

This release restores compatibility with current Python and Cython toolchains,
which had been broken since Cython 3. Most of the work in it comes from
[@iceout](https://github.com/iceout) via [#2](https://github.com/akivajp/pycedar/pull/2).

### Added

- Continuous integration covering CPython 3.9 through 3.14 on Linux and macOS,
  testing both the built wheel and a clean source distribution install.
- A tag-driven release workflow that builds wheels with `cibuildwheel` and
  publishes to PyPI through Trusted Publishing.
- `pycedar.__version__`, resolved from the installed distribution metadata so
  that `pycedar/VERSION` remains the single source of truth.
- A PEP 517 build configuration (`pyproject.toml`) declaring the Cython and
  setuptools build requirements.
- `MANIFEST.in`, so that the Cython sources, the Cedar header and the Cedar
  license files are shipped in the source distribution.
- An assertion-based test suite covering the `dict` façade, the low level trie
  and node API, and the examples embedded in both READMEs.
- A Japanese README ([README.ja.md](README.ja.md)), an API reference and a
  documented list of limitations.

### Changed

- **Breaking**: Python 3.5 through 3.8 are no longer supported. The minimum
  supported version is now Python 3.9.
- The build uses `cythonize()` with `language_level=3` instead of the removed
  `Cython.Distutils.build_ext` code path, and no longer compiles the `.pxd`
  file as a translation unit.
- Cedar is compiled with `-fno-strict-overflow` on GNU-compatible toolchains,
  which prevents optimizer-induced hangs during dense randomized insertion. The
  flag is applied only when the distutils compiler type is `unix`.
- Package metadata was refreshed: SPDX-style license names, `python_requires`,
  per-version classifiers, project URLs and bundled license files.

### Fixed

- Build failure with Cython 3 (`CompileError: pycedar/pycedar.pyx`), which made
  `pip install pycedar` fail on any recent Python.
  ([#1](https://github.com/akivajp/pycedar/issues/1))
- `pycedar.dict(bytes)` left its `root` node unset, so `items()`, `keys()`,
  `values()`, `nodes()` and `find()` all failed for non-`str` key types.
- Zero-result prefix searches indexed an empty `std::vector`, which is undefined
  behaviour.
- `__dealloc__` invoked `cpdef` methods during deallocation, and duplicated the
  teardown already performed by cedar's own destructor.
- C++ exceptions thrown by cedar could cross the extension boundary without
  being translated; the affected declarations now carry `except +`.
- `_consult()` is synced with the upstream `cedar-2022-03-18` release. Apart
  from this project's deliberate `_err()` → `throw std::runtime_error` patch,
  the vendored header is now functionally identical to upstream.

The entries below were reconstructed from the git history and the PyPI upload
records; the corresponding tags were added retroactively.

## [0.1.3] - 2020-03-02

### Changed

- Reorganized the directory layout and the distribution settings.

## [0.1.2] - 2020-03-02

### Added

- `pycedar/VERSION` as the single source of truth for the version number.

### Changed

- Declared support for Python 3.5, 3.6 and 3.7.

## [0.1.1] - 2019-01-27

### Added

- Documentation.

### Fixed

- Assorted bugs.

## [0.0.4] - 2018-08-06

### Added

- First release published on PyPI.

### Fixed

- Build failure with clang on macOS.

[Unreleased]: https://github.com/akivajp/pycedar/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/akivajp/pycedar/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/akivajp/pycedar/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/akivajp/pycedar/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/akivajp/pycedar/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/akivajp/pycedar/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/akivajp/pycedar/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/akivajp/pycedar/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/akivajp/pycedar/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/akivajp/pycedar/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/akivajp/pycedar/compare/v0.0.4...v0.1.1
[0.0.4]: https://github.com/akivajp/pycedar/releases/tag/v0.0.4
