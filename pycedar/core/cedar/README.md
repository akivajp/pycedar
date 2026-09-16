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
| `#include <stdexcept>` | Needed by the `throw` sites below. |
| `update()`: inserting a zero-length key throws `std::runtime_error` instead of calling `_err()` | Surfaces as a Python exception. `pycedar` rejects empty keys with `KeyError` before reaching this, so it is a backstop. |
| `_realloc_array()`: a failed `realloc` throws `std::runtime_error` instead of calling `_err()` | Surfaces as a Python exception rather than killing the interpreter. |
| `shrink_tail()`: a failed `malloc` throws `std::runtime_error` instead of calling `_err()` | Reached through `save()`, whose `shrink` argument defaults to `True`. Nothing has been mutated at that point, so the trie survives intact. |
| `open()`: a failed `malloc` calls `fclose()`, then `clear(true)`, then throws `std::runtime_error` | Reached through `load()`. Unlike the site above, `clear(false)` has already dropped the previous contents, so the object has to be reset to a valid empty trie before the exception escapes. |
| `_consult()` synced with upstream revision 1916 (2017-07-12) | Upstream bug fix, applied in [#2](https://github.com/akivajp/pycedar/pull/2). |

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

Allocation failures surface as `RuntimeError`, because that is what
`std::runtime_error` maps to under Cython's `except +`. `MemoryError` would be
the more idiomatic Python exception; unifying on it would mean changing
`_realloc_array()` too, which is a behaviour change in an existing code path and
has not been done.
(確保失敗は `RuntimeError` になる。`MemoryError` へ統一するには既存経路の変更が要るため未実施)

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

Once the `_consult()` fix landed, the remaining delta against upstream is only:

1. the deliberate local patches listed above,
2. comment wording,
3. the formatting of `clear()` (upstream splits the `_array = 0;` assignments
   onto their own line; behaviour is identical).

There is **no functional difference left to gain**. Re-vendoring wholesale would
mean re-applying the patches by hand, and silently losing them would convert
recoverable errors into `std::exit(1)` — the worst possible regression for a
library. That risk buys nothing.

The only concrete benefit of syncing (2) and (3) would be silencing six
compiler warnings observed in the release build:

```
5 x -Wmisleading-indentation   (from the clear() formatting)
1 x -Wunused-local-typedefs    (upstream suppresses it with #pragma GCC diagnostic)
```

That was judged not to be worth a change to the core data structure on its own,
and it was deliberately left out of the `_err()` work described above so that
the diff stayed limited to the error paths. It is still available to anyone who
wants a warning-free build.

## If you do re-vendor

1. Diff the new `src/cedarpp.h` against this copy first, and confirm that the
   upstream `$Id:` revision actually changed. If it did not, stop.
2. Re-apply every row of the modification table above.
3. Verify that no reachable `_err()` call site came back:
   `grep -n '_err (__FILE__' pycedar/core/cedar/src/cedarpp.h`
4. Update the note at the top of `cedarpp.h` and this file.
5. Run `pytest`. The suite includes randomized insert/delete consistency checks
   that exercise the double-array rebalancing paths where upstream bugs live.
