#!/bin/bash

rm -rf build
rm -rf dist
find . -name '*.c' -or -name '*.cpp' -or -name '*.so' -or -name '*.egg-info' | xargs -r rm -r

