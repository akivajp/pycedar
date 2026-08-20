#!/usr/bin/env python3

from pathlib import Path

from Cython.Build import cythonize
from setuptools import Extension
from setuptools import setup

MAIN_PACKAGE = 'pycedar'
BASE_PATH = Path(__file__).resolve().parent

extensions = [
    Extension(
        'pycedar',
        ['pycedar/pycedar.pyx'],
        include_dirs=['pycedar/core/cedar/src'],
        extra_compile_args=['-fno-strict-overflow'],
        language='c++',
    ),
]

version = (BASE_PATH / MAIN_PACKAGE / 'VERSION').read_text(encoding='utf-8').strip()
long_description = (BASE_PATH / 'README.md').read_text(encoding='utf-8')

setup(
    name='pycedar',
    version=version,
    ext_modules=cythonize(extensions, compiler_directives={'language_level': 3}),
    packages=['pycedar'],
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
    classifiers=[
        'Programming Language :: Python :: 3 :: Only',
        'Programming Language :: Python :: 3.9',
        'Programming Language :: Python :: 3.10',
        'Programming Language :: Python :: 3.11',
        'Programming Language :: Python :: 3.12',
        'Programming Language :: Python :: 3.13',
        'Programming Language :: Python :: 3.14',
        'Operating System :: POSIX',
        'Topic :: Utilities',
    ],
)
