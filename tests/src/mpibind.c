/*
 * mpibind.c: check the binding done by linux_bind_ (mpiauto --use-arch-bind)
 *
 * For each rank and each OpenMP thread, print the CPUs the thread may run on
 * before and after linux_bind_, and the CPU it is running on. Rank 0 prints
 * one line per (rank, thread), sorted, on stdout.
 *
 * The exit code is non-zero if, for some thread, the mask after binding is
 * not a subset of the mask before binding (i.e. linux_bind_ asked for CPUs
 * outside the process's cpuset). A thread whose mask did not change while
 * linux_bind.txt is present is flagged UNCHANGED (informational only).
 *
 * Build (inspired by mpitest.c):
 *   mpicc -fopenmp -DLINUX -o mpibind.x mpibind.c ../../src/linux_bind.c
 *
 * Run:
 *   mpiauto --use-arch-bind --np 4 --openmp 2 -- ./mpibind.x [seconds]
 *
 * With an argument, all ranks sleep that many seconds (still bound) before
 * MPI_Finalize, so that several jobs can be observed running together.
 */

#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sched.h>
#include <mpi.h>
#include <omp.h>

#define LINE 512

void linux_bind_ (int *, int *);

/* Format a cpu set as a compact list of ranges: "2-5,130" */

static char * cpulist (const cpu_set_t * set, char * buf, size_t len)
{
  int icpu, n = 0;
  buf[0] = '\0';
  for (icpu = 0; icpu < CPU_SETSIZE; icpu++)
    {
      int jcpu;
      if (! CPU_ISSET (icpu, set))
        continue;
      for (jcpu = icpu; jcpu + 1 < CPU_SETSIZE && CPU_ISSET (jcpu + 1, set); jcpu++);
      if (icpu == jcpu)
        n += snprintf (buf + n, len - n, "%s%d", n ? "," : "", icpu);
      else
        n += snprintf (buf + n, len - n, "%s%d-%d", n ? "," : "", icpu, jcpu);
      if (n >= (int)len)
        {
          strcpy (buf + len - 4, "...");
          break;
        }
      icpu = jcpu;
    }
  return buf;
}

int main (int argc, char * argv[])
{
  int rank, size, nomp, i, err = 0, errg = 0;
  char host[256];
  cpu_set_t * before, * after;
  int * cpu;
  char * text;
  int * lens = NULL, * displs = NULL;
  char * all = NULL;
  int ntext, ltext;

  MPI_Init (&argc, &argv);
  MPI_Comm_rank (MPI_COMM_WORLD, &rank);
  MPI_Comm_size (MPI_COMM_WORLD, &size);

  if (gethostname (host, sizeof (host)) != 0)
    strcpy (host, "unknown");
  host[sizeof (host) - 1] = '\0';

  nomp   = omp_get_max_threads ();
  before = (cpu_set_t *)calloc (nomp, sizeof (cpu_set_t));
  after  = (cpu_set_t *)calloc (nomp, sizeof (cpu_set_t));
  cpu    = (int *)calloc (nomp, sizeof (int));

  /* Masks before binding, per OpenMP thread */

#pragma omp parallel
  {
    sched_getaffinity (0, sizeof (cpu_set_t), &before[omp_get_thread_num ()]);
  }

  linux_bind_ (&rank, &size);

  /* Masks after binding; let each thread spin a little so that
     sched_getcpu reflects the new affinity */

#pragma omp parallel
  {
    int iomp = omp_get_thread_num ();
    volatile double x = 0.;
    int k;
    sched_getaffinity (0, sizeof (cpu_set_t), &after[iomp]);
    for (k = 0; k < 10000000; k++)
      x += k;
    cpu[iomp] = sched_getcpu ();
  }

  /* Build this rank's text: one line per thread */

  ltext = nomp * LINE;
  text  = (char *)malloc (ltext);
  ntext = 0;
  text[0] = '\0';

  for (i = 0; i < nomp; i++)
    {
      char sb[LINE / 3], sa[LINE / 3];
      cpu_set_t inter;
      const char * status = "ok";

      CPU_AND (&inter, &before[i], &after[i]);
      if (! CPU_EQUAL (&inter, &after[i]))
        status = "OUTSIDE";
      else if (CPU_EQUAL (&before[i], &after[i]) && (access ("linux_bind.txt", R_OK) == 0))
        status = "UNCHANGED";

      if (strcmp (status, "OUTSIDE") == 0)
        err = 1;

      ntext += snprintf (text + ntext, ltext - ntext,
                         "%-12s rank=%6d thread=%3d before=%-20s after=%-20s cpu=%4d %s\n",
                         host, rank, i, cpulist (&before[i], sb, sizeof (sb)),
                         cpulist (&after[i], sa, sizeof (sa)), cpu[i], status);
    }

  ntext++; /* include the terminating '\0' */

  /* Gather the texts on rank 0, in rank order */

  if (rank == 0)
    {
      lens   = (int *)malloc (size * sizeof (int));
      displs = (int *)malloc (size * sizeof (int));
    }

  MPI_Gather (&ntext, 1, MPI_INT, lens, 1, MPI_INT, 0, MPI_COMM_WORLD);

  if (rank == 0)
    {
      int tot = 0;
      for (i = 0; i < size; i++)
        {
          displs[i] = tot;
          tot += lens[i];
        }
      all = (char *)malloc (tot);
    }

  MPI_Gatherv (text, ntext, MPI_CHAR, all, lens, displs, MPI_CHAR, 0, MPI_COMM_WORLD);

  MPI_Reduce (&err, &errg, 1, MPI_INT, MPI_MAX, 0, MPI_COMM_WORLD);

  if (rank == 0)
    {
      for (i = 0; i < size; i++)
        fputs (all + displs[i], stdout);
      printf ("mpibind: %s\n", errg ? "FAILED" : "OK");
      fflush (stdout);
    }

  MPI_Bcast (&errg, 1, MPI_INT, 0, MPI_COMM_WORLD);

  if (argc > 1)
    sleep (atoi (argv[1]));

  MPI_Finalize ();

  return errg ? 1 : 0;
}
