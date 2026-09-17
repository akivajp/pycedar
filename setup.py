#!/usr/bin/env python3

from pathlib import Path

from Cython.Build import cythonize
from setuptools import Extension
from setuptools import setup
from setuptools.command.build_ext import build_ext as _build_ext

MAIN_PACKAGE = 'pycedar'
BASE_PATH = Path(__file__).resolve().parent

# cedar's inner loops rely on signed integer arithmetic. If the optimizer is
# allowed to treat signed overflow as undefined behaviour, dense insertion can
# fail to terminate. The flag is GNU/clang specific, so it is applied only after
# inspecting the distutils compiler type (never on MSVC).
# (最適化器が符号付きオーバーフローをUB扱いすると密な挿入が停止しなくなる。
#  gcc/clang 専用フラグなのでコンパイラ種別を見てから付与する)
UNIX_EXTRA_COMPILE_ARGS = ['-fno-strict-overflow']


class build_ext(_build_ext):
    """Apply toolchain specific compile flags. (ツールチェイン別のフラグ出し分け)"""

    def build_extensions(self):
        if self.compiler.compiler_type == 'unix':
            for ext in self.extensions:
                # Append without clobbering flags set elsewhere.
                # (他所で設定されたフラグを壊さないよう重複を避けて追記する)
                args = list(ext.extra_compile_args or [])
                for arg in UNIX_EXTRA_COMPILE_ARGS:
                    if arg not in args:
                        args.append(arg)
                ext.extra_compile_args = args
        super().build_extensions()


extensions = [
    Extension(
        'pycedar',
        ['pycedar/pycedar.pyx'],
        include_dirs=['pycedar/core/cedar/src'],
        language='c++',
    ),
]

version = (BASE_PATH / MAIN_PACKAGE / 'VERSION').read_text(encoding='utf-8').strip()
long_description = (BASE_PATH / 'README.md').read_text(encoding='utf-8')

# The module holds no global mutable Python state and every Python object it
# touches is managed by Cython's reference counting, so it is safe to declare
# as free-threading compatible (PEP 703). This only tells a free-threaded
# interpreter that the module does not require the GIL; under a GIL build the
# directive changes nothing. Concurrent operations on the *same* trie were
# never thread-safe (cedar mutates its arrays in place) and remain so.
# (モジュールはグローバルな可変状態を持たず、Python オブジェクトは Cython の
#  参照カウントで管理されるため、フリースレッド対応として宣言する。GIL 版での
#  挙動は不変。同一トライへの並行操作は従来どおりスレッドセーフではない)
compiler_directives = {
    'language_level': 3,
    'freethreading_compatible': True,
}

setup(
    name='pycedar',
    version=version,
    cmdclass={'build_ext': build_ext},
    ext_modules=cythonize(extensions, compiler_directives=compiler_directives),
    # The extension itself is a top-level module (pycedar.<abi>.so), so its
    # type stubs ship as the PEP 561 stub-only package pycedar-stubs, which
    # installers place beside it and type checkers pick up automatically.
    # (拡張本体はトップレベルモジュールのため、型スタブは PEP 561 の
    #  stub-only パッケージ pycedar-stubs として同梱する)
    packages=['pycedar', 'pycedar-stubs'],
    package_data={
        'pycedar': [
            '*.pyx',
            '*.pxd',
            'VERSION',
            'core/cedar/AUTHORS',
            'core/cedar/BSD',
            'core/cedar/COPYING',
            'core/cedar/GPL',
            'core/cedar/LGPL',
            'core/cedar/THANKS',
            'core/cedar/src/cedarpp.h',
        ],
        'pycedar-stubs': ['__init__.pyi'],
    },
    license_files=[
        'pycedar/core/cedar/BSD',
        'pycedar/core/cedar/COPYING',
        'pycedar/core/cedar/GPL',
        'pycedar/core/cedar/LGPL',
    ],
    python_requires='>=3.9',
    description='Python binding of cedar (implementation of efficiently-updatable double-array trie) using Cython',
    long_description=long_description,
    long_description_content_type='text/markdown',
    url='https://github.com/akivajp/pycedar',
    author='Akiva Miura',
    author_email='akiva.miura@gmail.com',
    license='GPLv2, LGPLv2.1 and BSD-2-Clause',
    project_urls={
        'Source': 'https://github.com/akivajp/pycedar',
        'Changelog': 'https://github.com/akivajp/pycedar/blob/master/CHANGELOG.md',
        'Issue Tracker': 'https://github.com/akivajp/pycedar/issues',
    },
    classifiers=[
        'Programming Language :: Python :: 3 :: Only',
        'Programming Language :: Python :: 3.9',
        'Programming Language :: Python :: 3.10',
        'Programming Language :: Python :: 3.11',
        'Programming Language :: Python :: 3.12',
        'Programming Language :: Python :: 3.13',
        'Programming Language :: Python :: 3.14',
        'Operating System :: POSIX',
        'Operating System :: Microsoft :: Windows',
        'Topic :: Utilities',
        'Typing :: Typed',
    ],
)
