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

For a library loaded into a Python process that is unacceptable, so **two** of
the five `_err()` call sites were converted to throw instead. The Cython
declarations in `pycedar.pxd` carry `except +`, which turns the exception into a
Python one.

| Change | Reason |
| --- | --- |
| `#include <stdexcept>` | Needed by the two `throw` sites below. |
| `update()`: inserting a zero-length key throws `std::runtime_error` instead of calling `_err()` | Surfaces as a Python exception. `pycedar` rejects empty keys with `KeyError` before reaching this, so it is a backstop. |
| `_realloc_array()`: a failed `realloc` throws `std::runtime_error` instead of calling `_err()` | Surfaces as a Python exception rather than killing the interpreter. |
| `_consult()` synced with upstream revision 1916 (2017-07-12) | Upstream bug fix, applied in [#2](https://github.com/akivajp/pycedar/pull/2). |

The original lines are kept as comments next to the replacements, so the delta
against upstream stays readable.

### Known gap: three `_err()` call sites were left alone

| Function | Reachable from pycedar? |
| --- | --- |
| `dump()` | **No.** `pycedar.pxd` does not declare it. |
| `shrink_tail()` — `malloc` failure | **Yes**, via `save()`, whose `shrink` argument defaults to `True`. |
| `open()` — `malloc` failure | **Yes**, via `dict.load()` / `base_trie.open()`. |

So on out-of-memory during a save or a load, cedar still prints to stderr and
calls `std::exit(1)` rather than raising. Converting those two sites the same
way as the others would be a genuine improvement: `save` and `open` already
carry `except +` in `pycedar.pxd`, so the exception would propagate to Python
without any further change.
(OOM 時に save / load がプロセスごと落ちる。この2箇所も同様に変換すれば Python 例外になる)

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

That was judged not to be worth a change to the core data structure on its own.
It remains a reasonable thing to fold in alongside the `_err()` work described
above, should anyone pick that up.

## If you do re-vendor

1. Diff the new `src/cedarpp.h` against this copy first, and confirm that the
   upstream `$Id:` revision actually changed. If it did not, stop.
2. Re-apply every row of the modification table above.
3. Verify that no reachable `_err()` call site came back:
   `grep -n '_err (__FILE__' pycedar/core/cedar/src/cedarpp.h`
4. Update the note at the top of `cedarpp.h` and this file.
5. Run `pytest`. The suite includes randomized insert/delete consistency checks
   that exercise the double-array rebalancing paths where upstream bugs live.
