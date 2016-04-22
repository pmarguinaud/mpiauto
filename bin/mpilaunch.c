#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <mpi.h>

int main (int argc, char **argv)
{
  void * _mpi_init = MPI_Init;

  execv (argv[1], argv + 1);

  perror ("Could not start executable:");

  return 0;
}

