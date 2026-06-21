#!/usr/bin/env bash

source /home/ankit/dev/emsdk/emsdk_env.sh

emcc "$1" \
  -o "static/wasm/$(basename "$1" .c).js" \
  -sEXPORTED_FUNCTIONS=_main \
  -sEXPORTED_RUNTIME_METHODS=ccall