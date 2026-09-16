# pycedar

![version](https://img.shields.io/pypi/v/pycedar.svg)
![python](https://img.shields.io/pypi/pyversions/pycedar.svg)
![license](https://img.shields.io/pypi/l/pycedar.svg)

``cedar``（効率的に更新可能なダブル配列トライの実装）の Cython による Python バインディングです。

The English README is available at [README.md](README.md).

``cedar`` の公式サイト: http://www.tkl.iis.u-tokyo.ac.jp/~ynaga/cedar/

## 動作環境

* Python 3.9 以降
* POSIX 互換の 64bit プラットフォーム（Linux, macOS）
* ソースからビルドする場合は C++ コンパイラ

Linux および macOS 上の CPython 3.9 〜 3.14 で動作を検証しています。

## インストール

### PyPI のリリース版からインストールする

```shell
$ pip install --user pycedar
```

### GitHub の master からインストールする

```shell
$ pip install --user https://github.com/akivajp/pycedar/archive/master.zip
```

## 使い方

### ダブル配列トライに基づく dict ライクなクラスを使う

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
>>> d.get('twenty four')       # 既定値は base_trie.NO_VALUE
-1
>>> d.get('twenty four', None) is None
True
```

接頭辞検索はジェネレータを返します。

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

ノードを使うと、トライ上の位置を保持したまま、そこを起点に検索できます。

```python
>>> n = d.get_node('twenty')
>>> n.key()
'twenty'
>>> n.value()
20
>>> [child.key() for child in n.find_nodes(' t')]
[' three', ' two']

>>> d.get_node('twenty ') is None    # 経路はあるが値を持たない
True
```

保存と読み込み:

```python
>>> d.save('test.dat')
0
>>> d2 = pycedar.dict()
>>> d2.setdefault('eighteen', 18)
18
>>> list(d2.items())
[('eighteen', 18)]
>>> d2.load('test.dat')              # トライ像全体を置き換える
0
>>> list(d2.items())
[('nineteen', 19), ('twenty', 20), ('twenty one', 21), ('twenty three', 23), ('twenty two', 22)]
>>> d2.setdefault('eighteen', 18)
18
>>> list(d2.items())
[('eighteen', 18), ('nineteen', 19), ('twenty', 20), ('twenty one', 21), ('twenty three', 23), ('twenty two', 22)]
```

### bytes をキーにする

``pycedar.dict`` はキーの型でパラメータ化されており、型は厳密に検査されます。

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

``str`` のキーは cedar に渡る前に UTF-8 へエンコードされます。したがって低水準
API が返す長さは文字数ではなく**バイト長**です。

### より低水準のデータ構造を使う

``pycedar.dict`` はトライクラスの薄いラッパーにすぎません。cedar 本来の
セマンティクスが必要な場合は、トライクラスを直接使えます。

```python
>>> t = pycedar.str_trie()
>>> t.set('apple', 1)
1
>>> t.set('applet', 2)
2
>>> t.set('apply', 3)
3

>>> t.exact_match_search('apple')      # (値, 長さ, ノードID)
(1, 5, 259)
>>> t.exact_match_search('app')[0]     # 接頭辞は値を持たない
-1

>>> t.common_prefix_search('applet')   # 問い合わせの接頭辞となる全キー
[('apple', 1, 259), ('applet', 2, 368)]
>>> [key for key, value, node_id in t.common_prefix_predict('app')]
['le', 'let', 'ly']

>>> t.erase('apply')
0
>>> t.erase('apply')                   # 既に削除済み
-1
>>> t.num_keys()
2
```

2 種類の接頭辞検索の違いに注意してください。

* ``common_prefix_search(key)`` は ``key`` の**接頭辞になっている完全なキー**を返します。
* ``common_prefix_predict(key)`` は ``key`` で始まる全キーの**残りの接尾辞**を返します。

トライ（または部分木）の列挙には ``begin`` / ``next`` を使います。

```python
>>> result, from_id, pos = t.traverse('app')   # 部分木を特定する
>>> value, node_id, length = t.begin(from_id, pos)
>>> while value != pycedar.base_trie.NO_PATH:
...     print(t.suffix(node_id, length), value)
...     value, node_id, length = t.next(node_id, length, from_id)
apple 1
applet 2
```

## API リファレンス

### ``pycedar.base_trie``

全トライクラスの基底クラスです。直接インスタンス化することは想定していません。

| メンバー | 説明 |
| --- | --- |
| ``NO_VALUE`` | ``-1``。ノードは存在するが値を持たない場合に返る。 |
| ``NO_PATH`` | ``-2``。経路が存在しない場合に返り、走査の終端条件としても使われる。 |
| ``root`` | トライ根の ``node`` オブジェクト。 |
| ``clear(reuse=True)`` | 全キーを破棄する。 |
| ``capacity()``, ``size()``, ``length()``, ``total_size()``, ``unit_size()``, ``nonzero_size()``, ``nonzero_length()``, ``num_keys()`` | cedar の内部統計。``num_keys()`` は登録済みキー数。 |
| ``begin(from_id=0, length=0)`` | 列挙を開始する。``(値, ノードID, 長さ)`` を返す。 |
| ``next(node_id, length, root=0)`` | 列挙を進める。``(値, ノードID, 長さ)`` を返す。 |
| ``open(filepath, mode='rb', offset=0, size=0)`` | トライ像を読み込む。成功で ``0``、失敗で ``-1``。 |
| ``save(filepath, mode='wb', shrink=True)`` | トライ像を書き出す。成功で ``0``、失敗で ``-1``。 |

### ``pycedar.str_trie`` / ``pycedar.bytes_trie`` / ``pycedar.unicode_trie``

それぞれ ``str`` キー、``bytes`` キー、``unicode`` キー向けの ``base_trie`` の
特殊化です。Python 3 では ``unicode`` は ``str`` と同一のため、
``unicode_trie`` は ``str_trie`` と同じ挙動になり、後方互換のためだけに残されています。

``base_trie`` のメンバーに加えて、以下を持ちます。

| メソッド | 説明 |
| --- | --- |
| ``set(key, value)`` | ``key`` を ``value`` で登録する。格納した値を返す。空キーでは ``KeyError``。 |
| ``update(key, delta=0)`` | 必要なら ``key`` を登録し、値に ``delta`` を加算する。新しい値を返す。 |
| ``erase(key, from_id=0)`` | ``key`` を削除する。成功で ``0``、未登録なら ``-1``。 |
| ``exact_match_search(key, from_id=0)`` | ``(値, 長さ, ノードID)`` を返す。未発見時の値は ``NO_VALUE`` / ``NO_PATH``。 |
| ``common_prefix_search(key, from_id=0, max_size=-1)`` | ``key`` の接頭辞となる全キーについて ``(キー, 値, ノードID)`` のリストを返す。 |
| ``common_prefix_predict(key, from_id=0, max_size=-1)`` | ``key`` で始まる全キーについて ``(接尾辞, 値, ノードID)`` のリストを返す。 |
| ``traverse(key, from_id=0, pos=0)`` | ``from_id`` から ``key`` を辿る。``(値, ノードID, 位置)`` を返す。 |
| ``suffix(node_id, length=0)`` | ``node_id`` で終わるキーを復元する。 |

``max_size`` は返す結果数の上限で、``-1`` は無制限を意味します。``from_id`` を
指定すると検索範囲を部分木に限定できます。

### ``pycedar.node``

トライ上の位置を指すカーソルです。``base_trie.root``、``dict.root``、
``dict.get_node()``、``dict.nodes()``、``node.find_nodes()`` から取得できます。

| メンバー | 説明 |
| --- | --- |
| ``id``, ``length``, ``root`` | 読み取り専用の位置情報。 |
| ``key()`` | このノードが表すキー（``root`` からの相対）。 |
| ``value()`` | このノードに格納された値。 |
| ``track()`` | ``(id, length, root)`` を返す。 |
| ``traverse(key)`` | ``key`` 以下の部分木について ``(値, ノードID, 長さ)`` を yield するジェネレータ。 |
| ``find_nodes(key)`` | ``key`` 以下の部分木について ``node`` を yield するジェネレータ。 |
| ``get_node(key)`` | ``key`` に対応する ``node``。存在しないか値を持たない場合は ``None``。 |

### ``pycedar.dict``

トライに対する ``dict`` ライクなファサードです。``pycedar.dict(key_type)`` は
``str``（既定）または ``bytes`` を受け付けます。

| メンバー | 説明 |
| --- | --- |
| ``trie``, ``root``, ``type`` | 内部のトライ、その根の ``node``、キーの型。 |
| ``d[key]`` | 値。存在しなければ ``KeyError``。 |
| ``d[key] = value`` | キーを登録する。空キーでは ``KeyError``。 |
| ``del d[key]`` | キーを削除する。存在しなければ ``KeyError``。 |
| ``key in d``, ``len(d)``, ``iter(d)`` | 所属判定、キー数、キーの走査。 |
| ``get(key, default=NO_VALUE)`` | 値、または ``default``。 |
| ``set(key, value)`` | キーを登録する。格納した値を返す。 |
| ``setdefault(key, value=0)`` | 未登録のときだけ登録する。実際の値を返す。 |
| ``update(key, delta=0)`` | キーの値に ``delta`` を加算する。未登録なら登録する。 |
| ``clear()`` | 全キーを破棄する。 |
| ``keys()``, ``values()``, ``items()``, ``nodes()`` | トライ全体に対するジェネレータ。 |
| ``find(prefix)``, ``find_keys(prefix)``, ``find_values(prefix)`` | ``prefix`` に限定したジェネレータ。 |
| ``get_node(key)`` | ``key`` に対応する ``node``、または ``None``。 |
| ``save(filepath, mode='wb', shrink=True)`` | トライ像を書き出す。``0`` / ``-1`` を返す。 |
| ``load(filepath, mode='rb')`` | 保存済みのトライ像で置き換える。``0`` / ``-1`` を返す。 |

``pycedar.__version__`` でインストール済みパッケージのバージョンを取得できます。

## 制約事項

### 値は C の ``int`` 幅で、うち 2 つは予約されている

値は C の ``int`` として格納されるため、``-2**31 .. 2**31-1`` に収まる必要が
あります。これを超えると ``OverflowError`` になります。

次の 2 つの値は cedar の番兵値と衝突するため、格納してはいけません。

* **``-1``（``NO_VALUE``）** — キーは格納され走査にも現れますが、``in``、
  ``get()``、``d[key]`` のいずれからも「存在しない」と報告されます。
* **``-2``（``NO_PATH``）** — この値は走査の終端条件そのものであるため、
  ``items()``、``keys()``、``values()``、``find()`` などが**そのキーで静かに停止し、
  それ以降のトライに到達しなくなります**。

値を非負に限れば、いずれの問題も回避できます。それ以外の値は、負数を含めて
通常どおり往復します。

### シリアライズ形式はプラットフォーム依存であり、検証機構を持たない

cedar ネイティブの ``.dat`` 形式は、書き出したマシンのポインタ幅とバイト
オーダーに依存し、完全性の検証機構を一切持ちません。互換性のあるプラット
フォーム上で pycedar が生成した、信頼できる入手元のファイルのみを読み込んで
ください。

### I/O の失敗は戻り値で通知される

``save()`` / ``load()`` / ``open()`` は例外を送出せず、成功で ``0``、失敗で
``-1`` を返します。必ず戻り値を確認してください。

唯一の例外がメモリ不足で、``save()`` と ``load()`` は ``-1`` を返すのではなく
``MemoryError`` を送出します。``load()`` が失敗した場合、cedar は新しい配列を
確保する前に既存の配列を解放するため、**トライは空になります**。インスタンス
自体は有効なまま再利用できます。詳細は
[``pycedar/core/cedar/README.md``](pycedar/core/cedar/README.md) を参照してください。

## 開発

```shell
$ python -m pip install --upgrade pip
$ python -m pip install . pytest
$ pytest
```

``pycedar.pyx`` を編集しながらその場でビルドし直す場合:

```shell
$ python -m pip install "Cython>=3.1,<4" setuptools
$ python setup.py build_ext --inplace
```

``./clean.sh`` でビルド生成物を削除できます。

### ベンチマーク

``benchmarks/bench.py`` が主要な操作の実行時間を計測します。変更に効果があった
かどうかは、2 つのビルドで実行して比較してください。

```shell
$ python benchmarks/bench.py --label before
$ python benchmarks/bench.py --label after
```

``rich`` が入っていれば表形式で、無ければプレーンテキストで出力します。
指定できる項目は ``--help`` を参照してください。

## リリース手順

バージョンは [``pycedar/VERSION``](pycedar/VERSION) の 1 箇所のみで管理します。

1. ``pycedar/VERSION`` と ``CHANGELOG.md`` を更新する。
2. コミットして ``master`` に push する。
3. 対応するタグを push する（例: ``git tag v0.2.0 && git push origin v0.2.0``）。

[リリースワークフロー](.github/workflows/release.yml) がタグと
``pycedar/VERSION`` の一致を検証し、``cibuildwheel`` で sdist と Linux/macOS 向け
wheel をビルドして、Trusted Publishing により PyPI へ公開します。

## ライセンス

pycedar は ``cedar`` 本体と同じ条件で配布されます（GPLv2、LGPLv2.1、
BSD-2-Clause）。ライセンス文書は
[``pycedar/core/cedar/``](pycedar/core/cedar/) 以下に同梱しています。

## クレジット

``cedar`` は Naoki Yoshinaga 氏によるものです。``pycedar/core/cedar/`` に同梱
しているコピーにはローカル変更があります。変更内容とその理由、2022 年の上流
tarball をあえて取り込まなかった判断の経緯、より新しい版へ同期する際に再適用
すべき内容は
[``pycedar/core/cedar/README.md``](pycedar/core/cedar/README.md) に記録しています。

各リリースの貢献者は [CHANGELOG.md](CHANGELOG.md) を参照してください。
