#!/usr/bin/env python
# -*- coding: utf-8 -*-

from Cython.Distutils import build_ext
from setuptools import find_packages
from setuptools import setup
from setuptools import Extension

ext_modules=[
    Extension(
        'pycedar',
        ['pycedar/pycedar.pyx'],
        include_dirs = ['./cedar/src'],
        language='c++',
    )
]

setup(
    name = 'pycedar',
    version = '0.0.4',
    cmdclass = {'build_ext': build_ext},
    ext_modules = ext_modules,
    packages = find_packages(),
    description = 'Python binding of cedar (implementation of efficiently-updatable double-array trie) using Cython',
    url = 'https://github.com/akivajp/pycedar',
    author = 'Akiva Miura',
    author_email = 'akiva.miura@gmail.com',
    license = 'GPLv2, GPLv2.1 and BSD',
)

