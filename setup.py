#!/usr/bin/env python
# -*- coding: utf-8 -*-

from distutils.core import setup
from distutils.extension import Extension
from Cython.Distutils import build_ext

ext_modules=[
    Extension(
        "pycedar",
        ["pycedar/pycedar.pyx"],
        include_dirs = ["./cedar/src"],
        language="c++",
    )
]

setup(
    name = "pycedar",
    version = "0.0.1",
    cmdclass = {"build_ext": build_ext},
    ext_modules = ext_modules
)

