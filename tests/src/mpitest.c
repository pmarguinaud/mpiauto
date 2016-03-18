#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <mpi.h>

#include <sched.h>

char * getcpumask (char *buffer, size_t size)
{
  cpu_set_t mask;
  unsigned int ncpu;
  int icpu;
  
  ncpu = sysconf (_SC_NPROCESSORS_CONF);
  
  sched_getaffinity (0, sizeof (mask), &mask);

  for (icpu = 0; icpu < ncpu; icpu++) 
    buffer[icpu] = CPU_ISSET (icpu, &mask) ? '1' : '0';

  buffer[ncpu] = '\0';

  return buffer;
}

int main (int argc, char **argv)
{
  int rank;
  int size;
  int icpu;
  unsigned int ncpu;
  FILE * fp = NULL;
  char f[256];
  char host[255];
  int nomp = omp_get_max_threads ();

  MPI_Init (&argc,&argv);

  ncpu = sysconf (_SC_NPROCESSORS_CONF);

  MPI_Comm_rank (MPI_COMM_WORLD, &rank);
  MPI_Comm_size (MPI_COMM_WORLD, &size);

  sprintf (f, "mpitest.%6.6d.txt", rank);
  fp = fopen (f, "w");

  MPI_Barrier (MPI_COMM_WORLD) ;

  if (gethostname (host, 255) != 0)
       strcpy (host, "unknown");

  fprintf (fp, " rank = %6d", rank);
  fprintf (fp, " host = %s",  host);
  fprintf (fp, " ncpu = %2d", ncpu);
  fprintf (fp, " nomp = %2d", nomp);

  {
    char buffer[1024];
    fprintf (fp, " mask = %s", getcpumask (buffer, sizeof (buffer)));
  }

#pragma omp parallel 
  {
    char buffer[1024];
    int iomp = omp_get_thread_num ();
    int i;
    for (i = 0; i < nomp; i++)
      {
        if (i == iomp)
          {
#pragma omp critical
            fprintf (fp, "\n                                                    mask = %s iomp = %2d", 
                     getcpumask (buffer, sizeof (buffer)), iomp);
          }
#pragma omp barrier
      }
#pragma omp barrier
  }

  fprintf (fp, "\n");

  fclose (fp);


  MPI_Finalize ();

  return 0;
}

