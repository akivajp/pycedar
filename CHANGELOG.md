# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/akivajp/pycedar/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/akivajp/pycedar/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/akivajp/pycedar/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/akivajp/pycedar/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/akivajp/pycedar/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/akivajp/pycedar/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/akivajp/pycedar/compare/v0.0.4...v0.1.1
[0.0.4]: https://github.com/akivajp/pycedar/releases/tag/v0.0.4
