#!/bin/bash

gcc -DLINUX -shared src/wrapstdeo.c -g -o lib/wrapstdeo.so -fPIC -ldl
gcc -DLINUX -shared src/wrapinit.c  -g -o lib/wrapinit.so  -fPIC -ldl
gcc -DLINUX -shared src/autobind.c  -g -o lib/autobind.so  -fPIC -ldl

