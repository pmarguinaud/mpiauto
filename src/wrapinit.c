#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/types.h>
#include <time.h>

static void alarm_handler (int signum)
{
  char * MPIAUTOTIMEOUTLOCKA = getenv ("MPIAUTOTIMEOUTLOCKA");
  if (MPIAUTOTIMEOUTLOCKA != NULL)
    unlink (MPIAUTOTIMEOUTLOCKA);

  printf ("Timeout detected on MPI_Init\n");
  fflush (stdout);

  /* Suicide */
  kill (0, SIGTERM);
}

static int level = 0;
static struct sigaction alarm_action_old;
static time_t t0;

static void enter_mpi_init ()
{
  struct sigaction alarm_action_new;
  char * MPIAUTOTIMEOUT;
  int timeout;

  if (level++ != 0)
    return;

  MPIAUTOTIMEOUT = getenv ("MPIAUTOTIMEOUT");
  if (MPIAUTOTIMEOUT == NULL)
    return;

  sscanf (MPIAUTOTIMEOUT, "%d", &timeout);

  fprintf (stderr, "MPIAUTOTIMEOUT is set to %d seconds\n", timeout);
  fflush (stderr);
  
  /* Prepare a new SIGALARM handler */

  alarm_action_new.sa_handler = alarm_handler;
  alarm_action_new.sa_flags   = 0;
  sigfillset (&alarm_action_new.sa_mask);
  sigdelset (&alarm_action_new.sa_mask, SIGTERM);
  sigaction (SIGALRM, &alarm_action_new, &alarm_action_old);

  /* Set off alarm */

  alarm (timeout);

  /* Record current time */

  t0 = time (NULL);
}

static void leave_mpi_init ()
{
  time_t t1;

  if (--level != 0)
    return;

  /* Remove alarm */

  alarm (0);

  /* Restore old SIGALARM handler */

  sigaction (SIGALRM, &alarm_action_old, NULL);

  /* See how long it took */

  t1 = time (NULL);

  printf ("MPI_Init took %d seconds\n", t1-t0);
  fflush (stdout);

  char * MPIAUTOTIMEOUTLOCKB = getenv ("MPIAUTOTIMEOUTLOCKB");
  unlink (MPIAUTOTIMEOUTLOCKB);
}

/* Wrap MPI initialization routines */

int MPI_Init (int * argc, char *** argv)
{
  int (*_MPI_Init)(int *, char ***) = dlsym (RTLD_NEXT, "MPI_Init");
  int ierror;
  
  enter_mpi_init ();
  ierror = _MPI_Init (argc, argv);
  leave_mpi_init ();

  return ierror;
}

int MPI_Init_thread (int * argc, char *** argv, int required, int * provided)
{
  int (*_MPI_Init_thread)(int *, char ***, int, int *) = dlsym (RTLD_NEXT, "MPI_Init_thread");
  int ierror;
  
  enter_mpi_init ();
  ierror = _MPI_Init_thread (argc, argv, required, provided);
  leave_mpi_init ();

  return ierror;
}

void mpi_init_thread_ (int * required, int * provided, int * ierror)
{
  void (*_mpi_init_thread_) (int *, int *, int *) = dlsym (RTLD_NEXT, "mpi_init_thread_");
  enter_mpi_init ();
  _mpi_init_thread_ (required, provided, ierror);
  leave_mpi_init ();
}

void mpi_init_ (int * ierror)
{
  void (*_mpi_init_) (int *) = dlsym (RTLD_NEXT, "mpi_init_");
  enter_mpi_init ();
  _mpi_init_ (ierror);
  leave_mpi_init ();
}
