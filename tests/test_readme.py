"""Run the ``python`` examples embedded in the README files as doctests.

(README に埋め込まれた ``python`` 例を doctest として実行する)

This keeps the documentation from drifting away from the actual behaviour.
(ドキュメントが実装から乖離するのを防ぐ)
"""

import doctest
import io
import re
from pathlib import Path

import pytest

import pycedar


REPO_ROOT = Path(__file__).resolve().parent.parent
README_FILES = ('README.md', 'README.ja.md')

# Fenced blocks tagged as python. (python とタグ付けされたコードフェンス)
FENCE_PATTERN = re.compile(r'^```python$(.*?)^```$', re.MULTILINE | re.DOTALL)

# Cython's type error wording varies between releases, so exception details are
# not compared; everything else is.
# (Cython のバージョンで例外メッセージが変わるため詳細は比較しない)
OPTION_FLAGS = doctest.ELLIPSIS | doctest.IGNORE_EXCEPTION_DETAIL


def extract_examples(path):
    """Concatenate every python fence in ``path``. (python フェンスを連結する)"""
    text = path.read_text(encoding='utf-8')
    return '\n'.join(match.group(1) for match in FENCE_PATTERN.finditer(text))


@pytest.mark.parametrize('filename', README_FILES)
def test_readme_examples(filename, tmp_path, monkeypatch):
    path = REPO_ROOT / filename
    if not path.is_file():
        # Not available when running against an installed wheel.
        # (インストール済み wheel に対して実行した場合は存在しない)
        pytest.skip('%s is not available in this checkout' % filename)

    source = extract_examples(path)
    assert '>>> import pycedar' in source, 'no runnable examples found in %s' % filename

    # The examples write files such as test.dat, so run them in a sandbox.
    # (例が test.dat 等を書き出すため作業ディレクトリを隔離する)
    monkeypatch.chdir(tmp_path)

    parser = doctest.DocTestParser()
    test = parser.get_doctest(source, {'pycedar': pycedar}, filename, str(path), 0)
    report = io.StringIO()
    runner = doctest.DocTestRunner(optionflags=OPTION_FLAGS, verbose=False)
    runner.run(test, out=report.write)

    assert runner.failures == 0, '%s examples are out of date:\n%s' % (filename, report.getvalue())
