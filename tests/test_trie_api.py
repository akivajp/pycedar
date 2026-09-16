"""Tests for the low level trie / node API.

(低水準のトライ・ノード API に対するテスト)

``pycedar.dict`` wraps these classes; the tests below exercise them directly so
that the primitive layer documented in the README stays covered.
(``pycedar.dict`` はこれらのラッパーであり、README に記載した低水準層を直接検証する)
"""

import os

import pytest

import pycedar


NO_VALUE = pycedar.base_trie.NO_VALUE
NO_PATH = pycedar.base_trie.NO_PATH

WORDS = (('apple', 1), ('applet', 2), ('apply', 3), ('banana', 4))


@pytest.fixture
def trie():
    """A populated ``str_trie``. (データを投入した ``str_trie``)"""
    obj = pycedar.str_trie()
    for key, value in WORDS:
        obj.set(key, value)
    return obj


def enumerate_trie(obj, from_id=0, length=0):
    """Walk a trie with ``begin`` / ``next``. (``begin``/``next`` による走査)"""
    results = []
    value, node_id, node_length = obj.begin(from_id, length)
    while value != NO_PATH:
        results.append((obj.suffix(node_id, node_length), value))
        value, node_id, node_length = obj.next(node_id, node_length, from_id)
    return results


### sentinels (番兵値)

def test_sentinel_constants():
    assert NO_VALUE == -1
    assert NO_PATH == -2
    # The specialised classes inherit them. (特殊化クラスにも継承される)
    assert pycedar.str_trie.NO_VALUE == NO_VALUE
    assert pycedar.bytes_trie.NO_PATH == NO_PATH


### exact match (完全一致)

def test_exact_match_search_returns_value_length_and_id(trie):
    value, length, node_id = trie.exact_match_search('apple')
    assert value == 1
    assert length == len('apple')
    assert trie.suffix(node_id, length) == 'apple'


def test_exact_match_search_misses(trie):
    # A key that is only a prefix carries no value. (接頭辞だけのキーは値を持たない)
    assert trie.exact_match_search('app')[0] in (NO_VALUE, NO_PATH)
    # A key off the trie entirely. (トライ上に経路が無いキー)
    assert trie.exact_match_search('zebra')[0] in (NO_VALUE, NO_PATH)


### set / update / erase (登録・更新・削除)

def test_set_returns_the_stored_value():
    obj = pycedar.str_trie()
    assert obj.set('cedar', 7) == 7
    assert obj.exact_match_search('cedar')[0] == 7
    # Re-setting overwrites. (再設定は上書き)
    assert obj.set('cedar', 8) == 8
    assert obj.exact_match_search('cedar')[0] == 8


def test_update_registers_then_accumulates():
    obj = pycedar.str_trie()
    assert obj.update('counter', 0) == 0
    assert obj.update('counter', 5) == 5
    assert obj.update('counter', 2) == 7


def test_set_and_update_reject_empty_keys():
    obj = pycedar.str_trie()
    with pytest.raises(KeyError):
        obj.set('', 1)
    with pytest.raises(KeyError):
        obj.update('', 1)


def test_erase_reports_whether_the_key_existed(trie):
    assert trie.erase('apply') == 0
    assert trie.exact_match_search('apply')[0] in (NO_VALUE, NO_PATH)
    # Erasing twice, or erasing an unknown key, is a soft failure.
    # (二重削除や未知キーの削除は戻り値で失敗を通知)
    assert trie.erase('apply') == -1
    assert trie.erase('never registered') == -1


### prefix queries (接頭辞検索)

def test_common_prefix_search_returns_full_keys(trie):
    """``common_prefix_search`` yields every key that prefixes the query.

    (``common_prefix_search`` は問い合わせの接頭辞となる全キーを返す)
    """
    results = trie.common_prefix_search('applet')
    assert [key for key, _value, _id in results] == ['apple', 'applet']
    assert [value for _key, value, _id in results] == [1, 2]


def test_common_prefix_predict_returns_suffixes(trie):
    """``common_prefix_predict`` yields the part *after* the query.

    (``common_prefix_predict`` は問い合わせより後ろの部分を返す)
    """
    results = trie.common_prefix_predict('app')
    assert [key for key, _value, _id in results] == ['le', 'let', 'ly']
    assert [value for _key, value, _id in results] == [1, 2, 3]


def test_prefix_queries_honour_max_size(trie):
    assert len(trie.common_prefix_search('applet', 0, 1)) == 1
    assert len(trie.common_prefix_predict('app', 0, 2)) == 2


def test_prefix_queries_with_no_match_return_empty_lists(trie):
    """Regression: a zero-sized result used to index an empty vector.

    (回帰テスト: 0 件の結果で空 vector を参照していた不具合)
    """
    assert trie.common_prefix_search('zebra') == []
    assert trie.common_prefix_predict('zebra') == []
    empty = pycedar.str_trie()
    assert empty.common_prefix_search('anything') == []
    assert empty.common_prefix_predict('') == []


### traversal (走査)

def test_traverse_locates_a_subtree(trie):
    value, from_id, pos = trie.traverse('app')
    assert value != NO_PATH
    assert pos == len('app')
    # Enumerating from that node only yields the matching subtree.
    # (そのノードからの列挙は部分木のみを返す)
    assert enumerate_trie(trie, from_id, pos) == [('apple', 1), ('applet', 2), ('apply', 3)]


def test_traverse_reports_a_missing_path(trie):
    assert trie.traverse('zebra')[0] == NO_PATH


def test_begin_and_next_enumerate_every_key(trie):
    assert enumerate_trie(trie) == [
        ('apple', 1), ('applet', 2), ('apply', 3), ('banana', 4),
    ]


def test_begin_on_an_empty_trie_reports_no_path():
    assert pycedar.str_trie().begin(0, 0)[0] == NO_PATH


### statistics (統計情報)

def test_statistics_grow_with_the_content():
    obj = pycedar.str_trie()
    assert obj.num_keys() == 0
    before = obj.total_size()

    for key, value in WORDS:
        obj.set(key, value)

    assert obj.num_keys() == len(WORDS)
    assert obj.total_size() >= before
    assert obj.unit_size() > 0
    assert obj.capacity() >= obj.size()
    assert obj.nonzero_size() <= obj.size()
    assert obj.nonzero_length() <= obj.length()


def test_clear_resets_the_trie(trie):
    trie.clear()
    assert trie.num_keys() == 0
    assert enumerate_trie(trie) == []
    # Still usable after clearing. (クリア後も再利用できる)
    trie.set('reused', 1)
    assert trie.exact_match_search('reused')[0] == 1


### persistence (永続化)

def test_trie_level_save_and_open_round_trip(trie, tmp_path):
    path = tmp_path / 'trie.dat'
    assert trie.save(str(path)) == 0

    restored = pycedar.str_trie()
    assert restored.open(str(path)) == 0
    assert enumerate_trie(restored) == list(WORDS)


def test_opening_a_missing_file_reports_failure(tmp_path):
    assert pycedar.str_trie().open(str(tmp_path / 'nope.dat')) == -1


def test_allocation_failure_while_opening_raises_and_leaves_a_usable_trie(tmp_path):
    """Regression: cedar used to call ``std::exit(1)`` on an allocation failure.

    (回帰テスト: 確保失敗時に cedar が ``std::exit(1)`` でプロセスごと落としていた)

    ``open`` sizes its arrays from the ``size`` argument when one is given, so an
    absurd value makes the internal ``malloc`` fail without consuming memory.
    (``size`` を与えると配列長がそこから決まるので、巨大値で確保だけを失敗させられる)
    """
    source = pycedar.str_trie()
    source.set('keep', 1)
    path = tmp_path / 'trie.dat'
    assert source.save(str(path)) == 0

    target = pycedar.str_trie()
    target.set('discarded', 1)

    with pytest.raises(MemoryError):
        target.open(str(path), 'rb', 0, 2 ** 60)

    # The previous contents are gone, but the trie must be valid and reusable
    # rather than half-built. (中身は失われるが、壊れた状態ではなく空の有効な状態になる)
    assert target.num_keys() == 0
    assert enumerate_trie(target) == []
    target.set('after', 2)
    assert target.exact_match_search('after')[0] == 2

    # A subsequent well-formed load still works.
    # (その後の正常な読み込みも成功する)
    assert target.open(str(path)) == 0
    assert target.exact_match_search('keep')[0] == 1


def _open_file_descriptor_count():
    """Descriptors held by this process, or ``None`` if it cannot be measured.

    (このプロセスが保持するFD数。測れない環境では ``None``)
    """
    try:
        return len(os.listdir('/proc/self/fd'))
    except OSError:
        return None


def test_failed_loads_do_not_leak_file_descriptors(tmp_path):
    """Regression: ``open`` used to return -1 without closing the file.

    (回帰テスト: ``open`` が ``fclose`` せずに -1 を返し FD を漏らしていた)
    """
    path = tmp_path / 'garbage.dat'
    path.write_bytes(b'this is not a cedar image')

    trie = pycedar.str_trie()
    # Warm up, so that one-off allocations are not counted as a leak.
    # (初回限りの確保を漏れと数えないよう先に1回実行する)
    assert trie.open(str(path)) == -1

    before = _open_file_descriptor_count()
    if before is None:
        pytest.skip('open file descriptors cannot be counted on this platform')

    for _ in range(200):
        assert trie.open(str(path)) == -1

    assert _open_file_descriptor_count() == before


### specialised classes (特殊化クラス)

def test_bytes_trie_round_trip():
    obj = pycedar.bytes_trie()
    obj.set(b'cedar', 1)
    obj.set(b'cedarpp', 2)

    assert obj.exact_match_search(b'cedar')[0] == 1
    assert [key for key, _v, _i in obj.common_prefix_search(b'cedarpp')] == [b'cedar', b'cedarpp']
    assert obj.suffix(obj.exact_match_search(b'cedar')[2], 5) == b'cedar'

    with pytest.raises(TypeError):
        obj.set('str key', 1)


def test_unicode_trie_handles_multibyte_keys():
    obj = pycedar.unicode_trie()
    obj.set('日本語', 1)
    obj.set('日本', 2)

    assert obj.exact_match_search('日本語')[0] == 1
    # cedar keys are UTF-8 byte strings, so lengths are byte lengths.
    # (cedar のキーは UTF-8 バイト列なので長さはバイト長)
    assert obj.exact_match_search('日本')[1] == len('日本'.encode('utf-8'))
    assert sorted(key for key, _v, _i in obj.common_prefix_predict('日本')) == ['', '語']


def test_str_trie_rejects_wrong_key_types(trie):
    with pytest.raises(TypeError):
        trie.set(b'bytes key', 1)
    with pytest.raises(TypeError):
        trie.exact_match_search(b'bytes key')


### node objects (ノードオブジェクト)

def test_trie_exposes_a_root_node(trie):
    assert isinstance(trie.root, pycedar.node)
    assert trie.root.track() == (0, 0, 0)


def test_node_key_value_and_track(trie):
    target = trie.root.get_node('apple')
    assert target.key() == 'apple'
    assert target.value() == 1
    node_id, length, root = target.track()
    assert length == len('apple')
    assert root == 0
    assert trie.suffix(node_id, length) == 'apple'


def test_node_get_node_returns_none_when_absent(trie):
    assert trie.root.get_node('zebra') is None
    # A path without a value is also reported as absent.
    # (値を持たない経路も「存在しない」扱いになる)
    assert trie.root.get_node('app') is None


def test_node_find_nodes_walks_a_subtree(trie):
    target = trie.root.get_node('apple')
    # Keys are relative to the node the walk started from.
    # (キーは走査を開始したノードからの相対表現)
    assert [child.key() for child in target.find_nodes('')] == ['', 't']


def test_node_repr_and_str(trie):
    target = trie.root.get_node('apple')
    assert repr(target).startswith('pycedar.node(')
    assert 'id=' in repr(target)
    assert str(target) == repr('apple')
