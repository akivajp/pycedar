# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

## [0.1.3] - 2020-03-02

### Changed

- Reorganized the directory layout and the distribution settings.

[Unreleased]: https://github.com/akivajp/pycedar/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/akivajp/pycedar/compare/6e1bec6...v0.2.0
[0.1.3]: https://github.com/akivajp/pycedar/commit/6e1bec6
