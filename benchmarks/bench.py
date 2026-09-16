#!/usr/bin/env python3
"""Micro benchmarks for the operations pycedar is used for.

(pycedar の主要操作に対するマイクロベンチマーク)

Run it against two builds to see whether a change actually paid off:

```shell
$ python benchmarks/bench.py --label before
$ python benchmarks/bench.py --label after
```

The builtin ``dict`` row is a reference point, not a target: a trie buys prefix
search and memory locality, not faster point lookups.
(組み込み ``dict`` は目標値ではなく基準点。トライの利点は接頭辞検索とメモリ効率)
"""

import argparse
import random
import string
import sys
import timeit

import pycedar


def build_keys(count, seed, min_length, max_length):
    """Generate ``count`` distinct random keys. (重複のないランダムキーを生成)"""
    randomizer = random.Random(seed)
    alphabet = string.ascii_lowercase
    keys = set()
    while len(keys) < count:
        length = randomizer.randint(min_length, max_length)
        keys.add(''.join(randomizer.choices(alphabet, k=length)))
    return sorted(keys)


def measure(statement, variables, operations, number, repeat):
    """Return the best per-operation time in nanoseconds. (1操作あたりの最良値/ns)"""
    timings = timeit.repeat(statement, globals=variables, number=number, repeat=repeat)
    return min(timings) / (number * operations) * 1e9


def collect(args):
    """Run every case and return ``(name, ns_per_op)`` pairs. (各計測の実行)"""
    keys = build_keys(args.keys, args.seed, args.min_length, args.max_length)
    probe = keys[:args.probes]
    prefixes = sorted({key[:2] for key in keys})[:args.probes]

    trie = pycedar.dict()
    for index, key in enumerate(keys):
        trie[key] = index + 1
    baseline = {key: index + 1 for index, key in enumerate(keys)}

    scope = {
        'trie': trie,
        'baseline': baseline,
        'probe': probe,
        'prefixes': prefixes,
        'raw': trie.trie,
    }
    cases = [
        ('builtin dict: d[key]', 'for k in probe: baseline[k]', len(probe)),
        ('dict: d[key]', 'for k in probe: trie[k]', len(probe)),
        ('dict: d.get(key)', 'for k in probe: trie.get(k)', len(probe)),
        ('dict: key in d', 'for k in probe: k in trie', len(probe)),
        ('dict: d[key] = value', 'for k in probe: trie[k] = 1', len(probe)),
        ('dict: d.set(key, value)', 'for k in probe: trie.set(k, 1)', len(probe)),
        ('dict: d.update(key, delta)', 'for k in probe: trie.update(k, 0)', len(probe)),
        ('dict: d.setdefault(key)', 'for k in probe: trie.setdefault(k, 1)', len(probe)),
        ('dict: d.get_node(key)', 'for k in probe: trie.get_node(k)', len(probe)),
        ('trie: exact_match_search', 'for k in probe: raw.exact_match_search(k)', len(probe)),
        ('trie: common_prefix_predict', 'for p in prefixes: raw.common_prefix_predict(p)', len(prefixes)),
    ]

    results = [(name, measure(statement, scope, operations, args.number, args.repeat))
               for name, statement, operations in cases]
    # Iteration is measured separately: one call walks the whole trie.
    # (走査は1回で全体を巡るため別枠で計測する)
    results.append(('dict: list(d.items()) per key',
                    measure('list(trie.items())', scope, len(keys), 1, args.repeat)))
    return keys, results


def report(label, keys, results):
    """Print the table, with rich when it is installed. (rich があれば表で出力)"""
    heading = 'pycedar %s -- %s, %d keys' % (pycedar.__version__, label, len(keys))
    try:
        from rich.console import Console
        from rich.table import Table
    except ImportError:
        print(heading)
        print('-' * len(heading))
        for name, nanoseconds in results:
            print('%-34s %10.0f ns/op' % (name, nanoseconds))
        return

    table = Table(title=heading)
    table.add_column('operation')
    table.add_column('ns/op', justify='right')
    for name, nanoseconds in results:
        table.add_row(name, '%.0f' % nanoseconds)
    Console().print(table)


def main(argv=None):
    """Entry point. (エントリポイント)"""
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('--keys', type=int, default=20000,
                        help='number of keys to insert (default: %(default)s)')
    parser.add_argument('--probes', type=int, default=2000,
                        help='number of keys used per timed loop (default: %(default)s)')
    parser.add_argument('--min-length', type=int, default=4,
                        help='shortest generated key (default: %(default)s)')
    parser.add_argument('--max-length', type=int, default=16,
                        help='longest generated key (default: %(default)s)')
    parser.add_argument('--number', type=int, default=20,
                        help='timeit loops per repetition (default: %(default)s)')
    parser.add_argument('--repeat', type=int, default=5,
                        help='timeit repetitions, the best is reported (default: %(default)s)')
    parser.add_argument('--seed', type=int, default=0,
                        help='random seed for key generation (default: %(default)s)')
    parser.add_argument('--label', default='run',
                        help='label shown in the report heading (default: %(default)s)')
    args = parser.parse_args(argv)

    keys, results = collect(args)
    report(args.label, keys, results)
    return 0


if __name__ == '__main__':
    sys.exit(main())
