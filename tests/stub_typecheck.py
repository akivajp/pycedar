"""Type-level assertions for the pycedar-stubs package, checked by mypy in CI.

(pycedar-stubs の型レベルの検証サンプル。CI の mypy ジョブから実行される)

This file is never imported or run by pytest; it exists so the CI job
``stub-types`` can pin the stub's behavior: the constructor's class-object
argument must bind the ``Generic`` parameter (``pycedar.dict()`` is
``dict[str]``, ``pycedar.dict(bytes)`` is ``dict[bytes]``) and every key
position must follow that parameterization rather than falling back to the
``str | bytes`` union or ``Any``.

(このファイルは pytest からは実行されない。CI の stub-types ジョブがスタブの
 挙動を固定するために存在する: コンストラクタのクラスオブジェクト引数から
 Generic パラメータが束縛され、各キー位置が共用型や Any にフォールバック
 しないことを検査する)
"""

import pycedar

d: pycedar.dict[str] = pycedar.dict()
s: pycedar.dict[str] = pycedar.dict(str)
b: pycedar.dict[bytes] = pycedar.dict(bytes)

d.set('a', 1)
s.set('b', 2)
b.set(b'c', 3)

d_get: int = d.get('a')
s_items: list[tuple[str, int]] = list(s.items())
b_keys: list[bytes] = list(b.keys())
d_val: int = d['a']
s_val: int = s.setdefault('x')
b_val: int = b.pop(b'c')