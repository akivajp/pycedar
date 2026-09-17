# Vendored copy of cedar

This directory holds a vendored copy of `cedar`, the double-array trie
implementation that pycedar wraps.

* Upstream: <http://www.tkl.iis.u-tokyo.ac.jp/~ynaga/cedar/>
* Author: Naoki Yoshinaga
* License: GPLv2, LGPLv2.1 and BSD-2-Clause (see `BSD`, `COPYING`, `GPL`, `LGPL`)

This file records what was changed locally and why, so that a future maintainer
who finds a newer tarball on the upstream site can decide what to do without
repeating the investigation.
(上流サイトに新しい tarball を見つけた人が、調査をやり直さずに判断できるようにするための記録)

## What is actually used

Only **one** file is compiled and shipped. Everything else is here because the
original tarball was vendored wholesale, and is dead weight.

| Path | Status |
| --- | --- |
| `src/cedarpp.h` | **Compiled and shipped.** The only file `pycedar.pxd` declares (`cdef extern from "cedarpp.h"`) and the only source `setup.py` ships in `package_data`. |
| `AUTHORS`, `BSD`, `COPYING`, `GPL`, `LGPL`, `THANKS` | Shipped, for license compliance. |
| `src/cedar.h`, `src/cedar.cc`, `src/bench.cc`, `src/bench_static.cc`, `src/mkcedar.cc`, `src/Makefile.am`, `Makefile.in` | Present in git, **never compiled and never shipped.** They differ substantially from upstream, which is irrelevant. |

## Local modifications to `src/cedarpp.h`

Upstream's error handler terminates the process:

```cpp
static void _err (const char* fn, const int ln, const char* msg)
{ std::fprintf (stderr, "cedar: %s [%d]: %s", fn, ln, msg); std::exit (1); }
```

For a library loaded into a Python process that is unacceptable, so **four** of
the five `_err()` call sites were converted to throw instead. The Cython
declarations in `pycedar.pxd` carry `except +`, which turns the exception into a
Python one.

| Change | Reason |
| --- | --- |
| `#include <new>`, `#include <stdexcept>` | Needed by the `throw` sites below. |
| `update()`: inserting a zero-length key throws `std::runtime_error` instead of calling `_err()` | Surfaces as a Python exception. `pycedar` rejects empty keys with `KeyError` before reaching this, so it is a backstop. |
| `_realloc_array()`: a failed `realloc` throws `std::bad_alloc` instead of calling `_err()` | Surfaces as `MemoryError` rather than killing the interpreter. |
| `shrink_tail()`: a failed `malloc` throws `std::bad_alloc` instead of calling `_err()` | Reached through `save()`, whose `shrink` argument defaults to `True`. Nothing has been mutated at that point, so the trie survives intact. |
| `open()`: a failed `malloc` calls `fclose()`, then `clear(true)`, then throws `std::bad_alloc` | Reached through `load()`. Unlike the site above, `clear(false)` has already dropped the previous contents, so the object has to be reset to a valid empty trie before the exception escapes. |
| `open()`: every early `return -1` closes the file first | Upstream leaks the `FILE*` on all nine of those paths. A loop of failed loads exhausts the descriptor table: 200 failed loads leaked exactly 200 descriptors before the fix. |
| `_consult()` synced with upstream revision 1916 (2017-07-12) | Upstream bug fix, applied in [#2](https://github.com/akivajp/pycedar/pull/2). |
| `clear()` layout and the `STATIC_ASSERT` pragmas taken from upstream | Pure formatting, adopted to remove the compiler warnings this copy used to emit. Reduces the delta against upstream rather than adding to it. |
| `save(char** buf, size_t* len, bool shrink)` and `open(const char* buf, size_t buf_len)` added (not upstream methods) | Memory-backed serialization for pycedar's `dumps()` / `loads()` and pickle support, so that no temp file is involved. The image layout is byte-for-byte what the file-based `save()` writes, so the two forms are interchangeable. The memory `open()` copies the buffer, so the trie owns its memory and the caller may release the original immediately; its failure paths mirror the file-based `open()` (malformed input returns `-1` before touching the contents, a failed allocation resets to a valid empty trie and throws `std::bad_alloc`). |

The original lines are kept as comments next to the replacements, so the delta
against upstream stays readable.

### The one `_err()` call site that is left

`dump()` still calls `_err()`, and therefore still calls `std::exit(1)`. That is
acceptable because `pycedar.pxd` does not declare `dump()`, so it is
unreachable from Python. Check with:

```shell
$ grep -n '_err (__FILE__' pycedar/core/cedar/src/cedarpp.h
```

Every line that comes back should either be commented out or sit inside
`dump()`. Anything else is a path that can kill the interpreter.
(上記以外が出てきたら、インタプリタを落としうる経路が増えたということ)

### What an allocation failure looks like from Python

Every allocation failure raises `MemoryError`, because Cython's `except +` maps
`std::bad_alloc` to it. Use `std::bad_alloc` — not `std::runtime_error` — for any
further allocation site, so that all of them stay on one exception type.
(確保失敗はすべて `MemoryError`。新たに確保箇所を足すときも `std::bad_alloc` を使うこと)

`std::runtime_error` is reserved for the one non-allocation case, the
zero-length key in `update()`, which reaches Python as `RuntimeError`.

`load()` is destructive: recovering from a failed load leaves an **empty** trie,
not the previous contents. cedar frees the old arrays before allocating the new
ones, so the old contents are already gone by the time the failure is detected.
(読み込み失敗後のトライは空になる。cedar は新規確保より前に旧配列を解放するため)

## Upstream status, checked 2026-09-16

The download page offers `cedar-latest.tar.gz`, which unpacks to
`cedar-2022-03-18/`. That date is misleading:

```
cedar-2022-03-18/src/cedarpp.h
  $Id: cedarpp.h 1916 2017-07-12 07:30:56Z ynaga $
```

**`cedarpp.h` itself has not changed upstream since 2017-07-12.** The 2022
tarball is a repackage. The single functional change made in 2017 was the
`_consult()` fix, and pycedar already carries it.

Reproduce the comparison with:

```shell
$ curl -O http://www.tkl.iis.u-tokyo.ac.jp/~ynaga/cedar/cedar-latest.tar.gz
$ tar xzf cedar-latest.tar.gz
$ diff -u pycedar/core/cedar/src/cedarpp.h cedar-*/src/cedarpp.h
```

## Decision: the 2022 tarball was not re-vendored

Once the `_consult()` fix landed, the remaining delta against upstream is only
the deliberate local patches listed above, plus comment wording. Everything
else that upstream had and this copy did not — the `clear()` layout and the
`STATIC_ASSERT` pragmas — has since been adopted, which silenced the six
compiler warnings this copy used to emit:

```
5 x -Wmisleading-indentation   (from the old clear() formatting)
1 x -Wunused-local-typedefs    (from STATIC_ASSERT)
```

There is **no functional difference left to gain**. Re-vendoring wholesale would
mean re-applying the patches by hand, and silently losing them would convert
recoverable errors back into `std::exit(1)` and reintroduce the descriptor leak
— the worst possible regressions for a library. That risk buys nothing.

## If you do re-vendor

1. Diff the new `src/cedarpp.h` against this copy first, and confirm that the
   upstream `$Id:` revision actually changed. If it did not, stop.
2. Re-apply every row of the modification table above.
3. Verify that no reachable `_err()` call site came back:
   `grep -n '_err (__FILE__' pycedar/core/cedar/src/cedarpp.h`
4. Update the note at the top of `cedarpp.h` and this file.
5. Run `pytest`. The suite includes randomized insert/delete consistency checks
   that exercise the double-array rebalancing paths where upstream bugs live.
