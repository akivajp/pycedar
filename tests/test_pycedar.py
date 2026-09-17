"""Tests for the ``pycedar.dict`` high level API.

(``pycedar.dict`` の高水準 API に対するテスト)
"""

import os
import random
import string
import tempfile

import pytest

import pycedar


def test_dict_crud_and_iteration():
    trie = pycedar.dict()
    trie['nineteen'] = 19
    trie['twenty'] = 20
    trie['twenty one'] = 21

    assert len(trie) == 3
    assert trie['twenty'] == 20
    assert trie.get('missing') == -1
    assert trie.get('missing', None) is None
    assert set(trie) == {'nineteen', 'twenty', 'twenty one'}
    assert dict(trie.items()) == {
        'nineteen': 19,
        'twenty': 20,
        'twenty one': 21,
    }

    del trie['twenty']
    assert 'twenty' not in trie
    with pytest.raises(KeyError):
        _ = trie['twenty']


def test_prefix_queries_and_zero_results():
    trie = pycedar.dict()
    trie['a'] = 1
    trie['ab'] = 2
    trie['abc'] = 3

    assert list(trie.find_keys('a')) == ['a', 'ab', 'abc']
    assert list(trie.find_keys('missing')) == []
    assert trie.trie.common_prefix_predict('missing') == []
    assert trie.trie.common_prefix_search('missing') == []
    matches = trie.trie.common_prefix_search('abcd')
    assert [item[0] for item in matches] == ['a', 'ab', 'abc']
    assert [item[1] for item in matches] == [1, 2, 3]


def test_unicode_and_bytes_tries():
    text_trie = pycedar.dict()
    text_trie['中文'] = 1
    text_trie['中国'] = 2
    assert set(text_trie.find_keys('中')) == {'中文', '中国'}

    bytes_trie = pycedar.dict(bytes)
    bytes_trie[b'cedar'] = 3
    assert bytes_trie[b'cedar'] == 3
    assert bytes_trie.root is not None
    assert list(bytes_trie.find_keys(b'ced')) == [b'cedar']


def test_empty_keys_are_rejected():
    trie = pycedar.dict()
    with pytest.raises(KeyError):
        trie[''] = 1


def test_clear_reuses_the_trie():
    trie = pycedar.dict()
    trie['before'] = 1

    trie.clear()
    trie['after'] = 2

    assert list(trie.items()) == [('after', 2)]


def test_save_load_round_trip_and_missing_file(tmp_path):
    trie = pycedar.dict()
    trie['nineteen'] = 19
    trie['twenty'] = 20
    data_path = tmp_path / 'words.dat'

    assert trie.save(str(data_path)) == 0
    restored = pycedar.dict()
    assert restored.load(str(data_path)) == 0
    assert dict(restored.items()) == dict(trie.items())

    before = dict(restored.items())
    assert restored.load(str(tmp_path / 'missing.dat')) == -1
    assert dict(restored.items()) == before


def test_randomized_mapping_agrees_with_python_dict():
    randomizer = random.Random(0)
    expected = {}
    trie = pycedar.dict()
    alphabet = string.ascii_lowercase

    for index in range(1000):
        key = ''.join(randomizer.choices(alphabet, k=randomizer.randint(1, 20)))
        expected[key] = index
        trie[key] = index

    assert len(trie) == len(expected)
    assert dict(trie.items()) == expected


### package metadata (パッケージメタデータ)

def test_version_is_exposed():
    """``__version__`` must be a usable version string. (版文字列が公開されていること)"""
    assert isinstance(pycedar.__version__, str)
    assert pycedar.__version__
    # 'unknown' is the documented fallback for a non-installed in-place build.
    # (未インストールの in-place ビルドでは 'unknown' になる仕様)
    if pycedar.__version__ != 'unknown':
        assert pycedar.__version__[0].isdigit()


### constructor (コンストラクタ)

def test_dict_rejects_unsupported_key_type():
    with pytest.raises(TypeError):
        pycedar.dict(int)


def test_dict_exposes_its_key_type():
    assert pycedar.dict().type is str
    assert pycedar.dict(bytes).type is bytes


def test_root_node_is_available_for_every_key_type():
    """Regression: ``root`` used to be assigned only on the ``str`` branch.

    (回帰テスト: ``root`` が ``str`` 分岐でしか代入されていなかった不具合)
    """
    for key_type, key in ((str, 'cedar'), (bytes, b'cedar')):
        trie = pycedar.dict(key_type)
        trie[key] = 1
        assert trie.root is not None
        # These all go through ``root`` and used to raise for bytes.
        # (いずれも ``root`` 経由。bytes では従来例外になっていた)
        assert list(trie.items()) == [(key, 1)]
        assert list(trie.keys()) == [key]
        assert list(trie.values()) == [1]
        assert [n.key() for n in trie.nodes()] == [key]


### key / value handling (キーと値の扱い)

def test_key_type_is_enforced():
    text = pycedar.dict()
    raw = pycedar.dict(bytes)

    with pytest.raises(TypeError):
        text[b'bytes key'] = 1
    with pytest.raises(TypeError):
        raw['text key'] = 1


@pytest.mark.parametrize('call', [
    lambda d, key: d.get(key),
    lambda d, key: d.set(key, 1),
    lambda d, key: d.setdefault(key, 1),
    lambda d, key: d.update(key, 1),
    lambda d, key: d.get_node(key),
])
def test_accessors_reject_the_wrong_key_type(call):
    """These used to be typed with a fused ``str``/``bytes`` parameter.

    (これらは以前 fused 型で宣言されており、型検査を dispatch が担っていた)

    The fused declaration was dropped for speed, so the check now happens in the
    trie below; this pins that it still happens.
    (高速化のため fused 宣言を外したので、検査が維持されていることを固定する)
    """
    text = pycedar.dict()
    raw = pycedar.dict(bytes)

    with pytest.raises(TypeError):
        call(text, b'bytes key')
    with pytest.raises(TypeError):
        call(raw, 'text key')
    with pytest.raises(TypeError):
        call(text, 123)


def test_values_must_be_c_int_sized_integers():
    trie = pycedar.dict()

    trie['max'] = 2 ** 31 - 1
    assert trie['max'] == 2 ** 31 - 1

    with pytest.raises(OverflowError):
        trie['too big'] = 2 ** 31
    with pytest.raises(TypeError):
        trie['not an int'] = 'x'


@pytest.mark.parametrize('reserved', [
    pycedar.base_trie.NO_VALUE,     # -1
    pycedar.base_trie.NO_PATH,      # -2
])
def test_reserved_values_are_rejected(reserved):
    """cedar's sentinels cannot be stored, through any writer.

    (cedar の番兵値はどの書き込み経路からも格納できない)

    Before 0.3.0 they were accepted and silently corrupted the trie: ``-1``
    made a key invisible to every lookup while leaving it visible to
    iteration, and ``-2`` ended traversal early, hiding every key after it.
    (0.3.0 以前は受け付けてしまい、-1 は検索から不可視、-2 は走査を打ち切っていた)
    """
    trie = pycedar.dict()

    for write in (lambda: trie.__setitem__('key', reserved),
                  lambda: trie.set('key', reserved),
                  lambda: trie.setdefault('key', reserved)):
        with pytest.raises(ValueError):
            write()

    # Nothing was stored by the rejected writes. (拒否された書き込みは何も残さない)
    assert 'key' not in trie
    assert len(trie) == 0


def test_update_rejects_a_delta_that_lands_on_a_reserved_value():
    """The result is what matters, not the delta.

    (判定対象はデルタではなく加算結果)
    """
    trie = pycedar.dict()
    trie['counter'] = 1

    with pytest.raises(ValueError):
        trie.update('counter', -3)          # 1 + (-3) == -2

    # The delta is rolled back, so the value is untouched.
    # (デルタは巻き戻され、値は元のまま)
    assert trie['counter'] == 1

    # Any result that is not reserved goes through.
    # (予約値でない結果なら通る)
    assert trie.update('counter', -4) == -3


@pytest.mark.parametrize('key_type, key', [(str, 'a\x00b'), (bytes, b'a\x00b')])
def test_keys_containing_a_nul_byte_are_rejected(key_type, key):
    """cedar terminates its tail entries with NUL, so such a key corrupts it.

    (cedar は tail の要素を NUL で終端するため、この種のキーは構造を壊す)

    Before 0.4.0 the write was accepted. It did not merely read back wrong:
    inserting one and then inserting a key sharing its prefix corrupted memory
    and crashed the interpreter with SIGSEGV.
    (0.4.0 以前は受理されていた。読み出しが狂うだけでなく、接頭辞を共有する
     キーを続けて入れるとメモリ破壊で SIGSEGV に至っていた)
    """
    trie = pycedar.dict(key_type)

    for write in (lambda: trie.__setitem__(key, 1),
                  lambda: trie.set(key, 1),
                  lambda: trie.setdefault(key, 1),
                  lambda: trie.update(key, 1)):
        with pytest.raises(ValueError):
            write()

    assert len(trie) == 0


def test_the_sequence_that_used_to_segfault_now_raises():
    """Pins the exact reproduction of the crash. (クラッシュ再現手順を固定する)"""
    trie = pycedar.dict()

    with pytest.raises(ValueError):
        trie['a\x00b'] = 7
    # The second insert shares the prefix; this is what used to corrupt memory.
    # (接頭辞を共有する2件目の挿入がメモリ破壊の引き金だった)
    trie['ac'] = 8

    assert trie['ac'] == 8
    assert dict(trie.items()) == {'ac': 8}


def test_other_values_including_negatives_round_trip():
    trie = pycedar.dict()
    values = (-2 ** 31, -3, 0, 1, 2 ** 31 - 1)
    for index, value in enumerate(values):
        trie['key %d' % index] = value

    # Rejecting the sentinels is what makes these two agree for every input.
    # (番兵値を拒否するからこそ len() と走査結果が常に一致する)
    assert len(trie) == len(values)
    assert len(list(trie.items())) == len(values)
    assert sorted(trie.values()) == sorted(values)


def test_the_not_found_marker_can_no_longer_collide_with_a_stored_value():
    """``get`` returning ``NO_VALUE`` is now unambiguous. (戻り値が一意に定まる)"""
    trie = pycedar.dict()
    trie['present'] = 5
    assert trie.get('absent') == pycedar.base_trie.NO_VALUE
    with pytest.raises(ValueError):
        trie['impostor'] = pycedar.base_trie.NO_VALUE


def test_zero_is_a_valid_value():
    trie = pycedar.dict()
    trie['zero'] = 0
    assert 'zero' in trie
    assert trie['zero'] == 0


### accessors (アクセサ)

def test_set_and_get_helpers():
    trie = pycedar.dict()
    assert trie.set('twenty', 20) == 20
    assert trie.get('twenty') == 20
    assert trie.get('missing') == pycedar.base_trie.NO_VALUE
    assert trie.get('missing', 'fallback') == 'fallback'


def test_setdefault_only_sets_once():
    trie = pycedar.dict()
    assert trie.setdefault('eighteen', 18) == 18
    assert trie.setdefault('eighteen', 99) == 18
    assert trie['eighteen'] == 18


def test_update_accumulates_a_delta():
    trie = pycedar.dict()
    assert trie.update('counter') == 0       # registers with value 0 (値0で登録)
    assert trie.update('counter', 5) == 5
    assert trie.update('counter', 3) == 8
    assert trie['counter'] == 8


def test_deleting_a_missing_key_raises():
    trie = pycedar.dict()
    trie['present'] = 1
    with pytest.raises(KeyError):
        del trie['absent']


def test_empty_key_is_rejected_by_every_writer():
    trie = pycedar.dict()
    for write in (lambda: trie.set('', 1),
                  lambda: trie.update('', 1),
                  lambda: trie.__setitem__('', 1)):
        with pytest.raises(KeyError):
            write()


### traversal (走査)

def test_find_variants_share_the_same_prefix_scope():
    trie = pycedar.dict()
    for key, value in (('twenty', 20), ('twenty one', 21), ('twenty two', 22), ('thirty', 30)):
        trie[key] = value

    assert list(trie.find('twenty')) == [('twenty', 20), ('twenty one', 21), ('twenty two', 22)]
    assert list(trie.find_keys('twenty')) == ['twenty', 'twenty one', 'twenty two']
    assert list(trie.find_values('twenty')) == [20, 21, 22]
    # An empty prefix scans everything. (空の接頭辞は全件走査)
    assert len(list(trie.find(''))) == 4


def test_empty_dict_traversal_yields_nothing():
    trie = pycedar.dict()
    assert list(trie) == []
    assert list(trie.items()) == []
    assert list(trie.keys()) == []
    assert list(trie.values()) == []
    assert list(trie.nodes()) == []
    assert list(trie.find('anything')) == []
    assert len(trie) == 0
    assert bool(trie) is False


def test_get_node_returns_none_for_non_terminal_prefixes():
    trie = pycedar.dict()
    trie['twenty'] = 20
    trie['twenty one'] = 21

    assert trie.get_node('twenty').value() == 20
    # 'twenty ' is a valid path but carries no value. (経路はあるが値を持たない)
    assert trie.get_node('twenty ') is None
    assert trie.get_node('nothing like this') is None


def test_nodes_can_be_traversed_relative_to_a_subtree():
    trie = pycedar.dict()
    for key, value in (('twenty', 20), ('twenty two', 22), ('twenty three', 23)):
        trie[key] = value

    root = trie.get_node('twenty')
    # Keys from a sub-node are relative to that node. (部分木からのキーは相対表現)
    assert sorted(n.key() for n in root.find_nodes(' t')) == [' three', ' two']


### round trip (永続化)

def test_save_and_load_preserve_unicode_keys(tmp_path):
    trie = pycedar.dict()
    trie['日本語'] = 1
    trie['日本'] = 2
    path = tmp_path / 'ja.dat'

    assert trie.save(str(path)) == 0
    restored = pycedar.dict()
    assert restored.load(str(path)) == 0
    assert dict(restored.items()) == {'日本': 2, '日本語': 1}


def test_save_to_an_unwritable_path_reports_failure(tmp_path):
    trie = pycedar.dict()
    trie['key'] = 1
    # cedar reports I/O failures through the return code, not an exception.
    # (cedar は I/O 失敗を例外ではなく戻り値で通知する)
    assert trie.save(str(tmp_path / 'missing dir' / 'x.dat')) == -1


def test_loading_a_corrupt_file_is_reported_and_leaves_the_trie_usable(tmp_path):
    path = tmp_path / 'garbage.dat'
    path.write_bytes(b'this is not a cedar image')

    trie = pycedar.dict()
    assert trie.load(str(path)) == -1
    # The instance must remain usable afterwards. (失敗後もインスタンスは使用可能)
    trie['still works'] = 1
    assert trie['still works'] == 1


def test_load_merges_into_an_existing_trie(tmp_path):
    """``load`` replaces the trie image, then new keys can be added.

    (``load`` はトライ像を置き換え、その後に追記できる)
    """
    source = pycedar.dict()
    source['nineteen'] = 19
    path = tmp_path / 'merge.dat'
    assert source.save(str(path)) == 0

    target = pycedar.dict()
    target['eighteen'] = 18
    assert target.load(str(path)) == 0
    assert dict(target.items()) == {'nineteen': 19}

    target.setdefault('eighteen', 18)
    assert dict(target.items()) == {'eighteen': 18, 'nineteen': 19}


### randomized consistency (ランダム整合性)

def test_randomized_insert_and_delete_agrees_with_python_dict():
    randomizer = random.Random(1234)
    expected = {}
    trie = pycedar.dict()
    alphabet = string.ascii_lowercase[:6]

    for index in range(2000):
        key = ''.join(randomizer.choices(alphabet, k=randomizer.randint(1, 8)))
        if randomizer.random() < 0.3 and expected:
            victim = randomizer.choice(list(expected))
            del expected[victim]
            del trie[victim]
        else:
            # Offset by 1 so that no value hits the reserved sentinels.
            # (番兵値に当たらないよう 1 以上にずらす)
            expected[key] = index + 1
            trie[key] = index + 1

    assert len(trie) == len(expected)
    assert dict(trie.items()) == expected


def test_readme_example_still_behaves_as_documented(tmp_path):
    """Pins the exact sequence shown in the README. (README の例を固定する)"""
    d = pycedar.dict()
    assert len(d) == 0
    assert bool(d) is False
    assert list(d) == []

    d['nineteen'] = 19
    d.set('twenty', 20)
    d['twenty one'] = 21
    d['twenty two'] = 22
    d['twenty three'] = 23
    d['twenty four'] = 24

    assert len(d) == 6
    assert bool(d) is True
    assert list(d) == [
        'nineteen', 'twenty', 'twenty four',
        'twenty one', 'twenty three', 'twenty two',
    ]
    assert list(d.values()) == [19, 20, 24, 21, 23, 22]
    assert d['twenty four'] == 24
    assert 'twenty four' in d

    del d['twenty four']
    assert 'twenty four' not in d
    assert d.get('twenty three') == 23
    assert d.get('twenty four') == -1
    assert d.get('twenty four', None) is None

    assert list(d.find('tw')) == [
        ('twenty', 20), ('twenty one', 21),
        ('twenty three', 23), ('twenty two', 22),
    ]
    assert list(d.find('twenty t')) == [('twenty three', 23), ('twenty two', 22)]
    assert list(d.find_keys('twenty')) == [
        'twenty', 'twenty one', 'twenty three', 'twenty two',
    ]
    assert list(d.find_values('twenty')) == [20, 21, 23, 22]

    n = d.get_node('twenty')
    assert n.key() == 'twenty'
    assert n.value() == 20
    assert [child.key() for child in n.find_nodes(' t')] == [' three', ' two']
    assert d.get_node('twenty ') is None

    path = tmp_path / 'test.dat'
    assert d.save(str(path)) == 0
    d2 = pycedar.dict()
    assert d2.setdefault('eighteen', 18) == 18
    assert list(d2.items()) == [('eighteen', 18)]
    assert d2.load(str(path)) == 0
    assert list(d2.items()) == [
        ('nineteen', 19), ('twenty', 20), ('twenty one', 21),
        ('twenty three', 23), ('twenty two', 22),
    ]
    assert d2.setdefault('eighteen', 18) == 18
    assert list(d2.items()) == [
        ('eighteen', 18), ('nineteen', 19), ('twenty', 20),
        ('twenty one', 21), ('twenty three', 23), ('twenty two', 22),
    ]


def test_pop():
    trie = pycedar.dict()
    trie['apple'] = 1
    trie['banana'] = 2

    assert trie.pop('apple') == 1
    assert 'apple' not in trie
    # missing key without a default raises KeyError (既定値を省略した場合は KeyError)
    with pytest.raises(KeyError):
        trie.pop('apple')
    # with a default it is returned instead (既定値を渡すとその値が返る)
    assert trie.pop('apple', 'missing') == 'missing'
    assert trie.pop('apple', None) is None
    # a falsy default must not be confused with the omitted one
    # (偽値のデフォルトは省略と混同されない)
    assert trie.pop('apple', 0) == 0


def test_popitem_returns_sorted_order_first():
    trie = pycedar.dict()
    trie['banana'] = 2
    trie['apple'] = 1
    trie['cherry'] = 3

    assert trie.popitem() == ('apple', 1)
    assert 'apple' not in trie
    assert trie.popitem() == ('banana', 2)
    assert trie.popitem() == ('cherry', 3)
    assert len(trie) == 0
    # empty trie raises KeyError (空のトライでは KeyError)
    with pytest.raises(KeyError):
        trie.popitem()


def test_dumps_loads_roundtrip():
    trie = pycedar.dict()
    trie['apple'] = 1
    trie['applet'] = 2
    trie['中文'] = 3

    image = trie.dumps()
    other = pycedar.dict()
    assert other.loads(image) == 0
    assert dict(other.items()) == dict(trie.items())
    # loads() replaces the whole contents (loads() は中身を丸ごと置き換える)
    other.setdefault('eighteen', 18)
    assert other.loads(image) == 0
    assert list(other.items()) == [('apple', 1), ('applet', 2), ('中文', 3)]


def test_dumps_loads_bytes_dict_and_empty_trie():
    bytes_trie = pycedar.dict(bytes)
    bytes_trie[b'cedar'] = 3
    image = bytes_trie.dumps()

    rebuilt = pycedar.dict(bytes)
    assert rebuilt.loads(image) == 0
    assert rebuilt[b'cedar'] == 3
    assert rebuilt.type is bytes

    empty = pycedar.dict()
    image = empty.dumps()
    rebuilt = pycedar.dict()
    assert rebuilt.loads(image) == 0
    assert len(rebuilt) == 0


def test_dumps_matches_the_file_format():
    trie = pycedar.dict()
    trie['apple'] = 1

    image = trie.dumps()
    # The image loads through the file path, and a file saved by save() loads
    # through loads(). (イメージは load() で読める。save() のファイルも loads() で
    #  読める。両者は相互運用できる)
    with tempfile.TemporaryDirectory() as tmpdir:
        path = os.path.join(tmpdir, 'test.dat')
        with open(path, 'wb') as fp:
            fp.write(image)
        rebuilt = pycedar.dict()
        assert rebuilt.load(path) == 0
        assert rebuilt['apple'] == 1

        with open(path, 'wb') as fp:
            assert trie.save(path) == 0
        rebuilt = pycedar.dict()
        assert rebuilt.loads(open(path, 'rb').read()) == 0
        assert rebuilt['apple'] == 1


def test_loads_rejects_malformed_images():
    trie = pycedar.dict()
    trie['apple'] = 1
    # a malformed image is rejected without touching the contents, unlike a
    # failed load(), which leaves the trie empty
    # (不正なイメージは中身に触れずに拒否される。load() と異なり中身は保持される)
    assert trie.loads(b'') == -1
    assert trie.loads(b'\x00\x00\x00\x00') == -1
    assert trie['apple'] == 1
    assert len(trie) == 1
    # the instance keeps working afterwards (インスタンスはそのまま使える)
    trie['after'] = 2
    assert trie['after'] == 2


def test_pickle_roundtrip():
    import copy
    import pickle

    trie = pycedar.dict()
    trie['apple'] = 1
    trie['中文'] = 2

    rebuilt = pickle.loads(pickle.dumps(trie))
    assert rebuilt.type is str
    assert dict(rebuilt.items()) == dict(trie.items())
    # the rebuilt dict enforces the same key type (復元後も同じ型検査が働く)
    with pytest.raises(TypeError):
        rebuilt[b'bytes key'] = 3

    bytes_trie = pycedar.dict(bytes)
    bytes_trie[b'cedar'] = 3
    rebuilt = pickle.loads(pickle.dumps(bytes_trie))
    assert rebuilt.type is bytes
    assert rebuilt[b'cedar'] == 3

    # the low level tries pickle too (低水準のトライも pickle 化できる)
    trie = pycedar.str_trie()
    trie.set('apple', 1)
    rebuilt = pickle.loads(pickle.dumps(trie))
    assert rebuilt.exact_match_search('apple')[0] == 1


def test_copy_independent_from_original():
    import copy

    trie = pycedar.dict()
    trie['apple'] = 1

    for shallow_or_deep in (copy.copy, copy.deepcopy):
        clone = shallow_or_deep(trie)
        assert clone['apple'] == 1
        clone['apple'] = 9
        assert trie['apple'] == 1


def test_stub_covers_public_api():
    """The stub must keep up with the runtime API.
    (スタブが実装の公開APIから取り残されないことを保証する)"""
    import re
    from pathlib import Path

    stub_path = Path(__file__).resolve().parent.parent / 'pycedar-stubs' / '__init__.pyi'
    if not stub_path.is_file():
        # Not available when running against an installed wheel without stubs.
        pytest.skip('pycedar-stubs is not available in this checkout')

    stub = stub_path.read_text(encoding='utf-8')
    blocks = _split_stub_blocks(stub)

    # Curated module-level names; the module namespace also leaks import
    # artifacts (sys, PackageNotFoundError) that are not API.
    # (モジュールレベルの名前。モジュール名前空間には import の副産物が
    #  露出しているが API ではない)
    for name in ('dict', 'base_trie', 'str_trie', 'bytes_trie', 'unicode_trie', 'node'):
        assert name in blocks, 'class %s is missing from the stub' % name
    assert '__version__: str' in stub, '__version__ is missing from the stub'

    # Names that are readable at runtime but are deliberately not documented
    # API, so the stub leaves them out.
    # (実行時には読めるが文書化済みAPIではないため、スタブから意図的に除外)
    skips = {
        # implementation detail exposed by Cython's readonly declaration
        # (Cython の readonly 宣言により露出している内部実装)
        ('dict', 'fallback_cast'),
    }
    documented_dunders = {
        'dict': {'__len__', '__contains__', '__iter__', '__getitem__',
                 '__setitem__', '__delitem__', '__reduce__'},
        'base_trie': {'__reduce__'},
        'str_trie': {'__reduce__'},
        'bytes_trie': '__reduce__',
        'unicode_trie': {'__reduce__'},
        'node': {'__repr__', '__str__'},
    }
    documented_dunders['bytes_trie'] = {'__reduce__'}

    for cls_name, cls in (
        ('dict', pycedar.dict),
        ('base_trie', pycedar.base_trie),
        ('str_trie', pycedar.str_trie),
        ('bytes_trie', pycedar.bytes_trie),
        ('unicode_trie', pycedar.unicode_trie),
        ('node', pycedar.node),
    ):
        expected = {name for name in dir(cls) if not name.startswith('_')}
        expected |= {d for d in documented_dunders.get(cls_name, set()) if hasattr(cls, d)}
        expected -= {name for cls_key, name in skips if cls_key == cls_name}
        # Subclasses inherit from base_trie; members declared only on the base
        # class's stub block count as covered.
        # (サブクラスは base_trie を継承する。基底クラスのブロックに宣言が
        #  あるメンバはカバー扱いにする)
        search_text = blocks.get(cls_name, '')
        if cls_name in ('str_trie', 'bytes_trie', 'unicode_trie'):
            search_text += blocks.get('base_trie', '')
        missing = sorted(
            name for name in expected
            if not re.search(r'\b%s\b\s*[:=(]' % re.escape(name), search_text)
        )
        assert not missing, (
            'the stub does not cover %s of pycedar.%s; update pycedar-stubs/__init__.pyi'
            % (missing, cls_name)
        )


def _split_stub_blocks(stub_text):
    """Split the stub into {class name: block text}. (スタブをクラスごとのブロックに分割する)"""
    import re
    parts = re.split(r'(?m)^class (\w+)', stub_text)
    return {parts[i]: parts[i + 1] for i in range(1, len(parts), 2)}


def test_concurrent_tries_are_independent():
    """Smoke test for free-threaded builds: concurrent workers, each on its own
    trie, must not interfere. Under the GIL this only passes trivially; on a
    free-threaded interpreter it exercises real parallelism.
    (フリースレッド版向けスモークテスト。別々のトライを並行操作しても互いに
     干渉しないこと。GIL 版では自明に通るが、フリースレッド版では実並行を
     行使する)"""
    import threading

    def worker(index, results):
        d = pycedar.dict()
        for i in range(500):
            key = 'k%d' % ((i + index) % 250)
            d[key] = i
            # reads must observe the writes made on this same trie
            # (同一トライへの書き込みが読み出しから観測できること)
            if d.get(key) != i:
                results.append((index, 'read mismatch', key))
                return
            if i % 50 == 0:
                d.pop(key)
                if key in d:
                    results.append((index, 'pop failed', key))
                    return
        results.append((index, None, None))

    # d[key] stores a C int; values above 255 exercise real int storage
    d = pycedar.dict()
    d['probe'] = 257
    assert d['probe'] == 257

    results = []
    threads = [threading.Thread(target=worker, args=(i, results)) for i in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    failures = [(i, reason) for i, reason, _ in results if reason is not None]
    assert not failures, failures
