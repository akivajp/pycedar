#!/bin/bash

if [ $(uname) = 'Linux' ]; then
  XARGS_FLAGS="-r"
else
  XARGS_FLAGS=""
fi

rm -rfv build
rm -rfv dist
find . -name '*.c' -or -name '*.cpp' -or -name '*.pyc' -or -name '*.so' -or -name '*.egg-info' | xargs ${XARGS_FLAGS} rm -rv

