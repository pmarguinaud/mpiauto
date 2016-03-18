#!/bin/bash

MPILIST="BULLXMPI1242 BULLXMPI1291 INTELMPI411036 INTELMPI500028 INTELMPI512150"

mkdir -p bin

for MPI in $MPILIST
do
  set -x
  $HOME/install/gmkpack_support/wrapper/$MPI/mpicc /usr/bin/gcc -fopenmp -g -o bin/mpitest.$MPI.x src/mpitest.c
done


