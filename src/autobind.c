#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <ctype.h>
#include <dlfcn.h>

#ifdef _OPENMP
#include <omp.h>
#endif

#include <sched.h>

#define LINUX_BIND_TXT "linux_bind.txt"

static void linux_bind ()
{
  int irank;
  char * srank; 
  char * sMPIAUTORANK;
  FILE * fp = fopen (LINUX_BIND_TXT, "r");
  int i;
  size_t len  = 256;
  char * buf = (char*)malloc (len);

  sMPIAUTORANK = getenv ("MPIAUTORANK");
  if (sMPIAUTORANK == NULL)
    return;

  srank = getenv (sMPIAUTORANK);
  if (srank == NULL)
    return;

  sscanf (srank, "%d", &irank);

  if (fp == NULL)
    {
      fprintf (stderr, "`" LINUX_BIND_TXT "' was not found\n");
      goto end;
    }

  for (i = 0; i < irank+1; i++)
    {
      if (getline (&buf, &len, fp) == -1)
        {
          fprintf (stderr, "Unexpected EOF while reading `" LINUX_BIND_TXT "'\n");
          goto end;
        }
    }

#ifdef _OPENMP
#pragma omp parallel 
#endif
  {
    char * c;
    cpu_set_t mask;
    int iomp = 
#ifdef _OPENMP
      omp_get_thread_num ()
#else
      1
#endif
    ;
    int jomp, icpu;

    for (jomp = 0, c = buf; jomp < iomp; jomp++)
      {
        while (*c && isdigit (*c))
          c++;
        while (*c && (! isdigit (*c)))
          c++;
        if (*c == '\0')
          {
            fprintf (stderr, "Unexpected end of line while reading `" LINUX_BIND_TXT "'\n");
            goto end_parallel;
          }
      }

    CPU_ZERO (&mask);

    for (icpu = 0; isdigit (*c); icpu++, c++)
      if (*c != '0')
        CPU_SET (icpu, &mask);
     
    sched_setaffinity (0, sizeof (mask), &mask);

end_parallel:

    c = NULL;

  }

end:

  if (fp != NULL)
    fclose (fp);

  free (buf);
}

static int done = 0;

static void leave_mpi_init ()
{
  if (done++ > 0)
    return;
  linux_bind ();
}

/* Wrap MPI initialization routines */

int MPI_Init (int * argc, char *** argv)
{
  int (*_MPI_Init)(int *, char ***) = dlsym (RTLD_NEXT, "MPI_Init");
  int ierror;
  
  ierror = _MPI_Init (argc, argv);
  leave_mpi_init ();

  return ierror;
}

int MPI_Init_thread (int * argc, char *** argv, int required, int * provided)
{
  int (*_MPI_Init_thread)(int *, char ***, int, int *) = dlsym (RTLD_NEXT, "MPI_Init_thread");
  int ierror;
  
  ierror = _MPI_Init_thread (argc, argv, required, provided);
  leave_mpi_init ();

  return ierror;
}

void mpi_init_thread_ (int * required, int * provided, int * ierror)
{
  void (*_mpi_init_thread_) (int *, int *, int *) = dlsym (RTLD_NEXT, "mpi_init_thread_");
  _mpi_init_thread_ (required, provided, ierror);
  leave_mpi_init ();
}

void mpi_init_ (int * ierror)
{
  void (*_mpi_init_) (int *) = dlsym (RTLD_NEXT, "mpi_init_");
  _mpi_init_ (ierror);
  leave_mpi_init ();
}
