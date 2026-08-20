import random
import string

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
