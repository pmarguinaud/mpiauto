#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

static void __attribute__((constructor)) wrap_stdeo ()
{
  char * MPIAUTOWRAP = getenv ("MPIAUTOWRAP");
  char * MPIAUTOWRAPSTDEO = getenv ("MPIAUTOWRAPSTDEO");
  char * _MPIAUTORANK = getenv ("_MPIAUTORANK");

  char MPIAUTOSTDOUT[32];
  char MPIAUTOSTDERR[32];
  int mpirank;

  if ((MPIAUTOWRAP == NULL) || (_MPIAUTORANK == NULL))
    return;

  mpirank = atoi (getenv (_MPIAUTORANK));

  if (MPIAUTOWRAPSTDEO)
    {   
      int fd = fileno (stdout);
      sprintf (MPIAUTOSTDOUT, "stdeo.%d", mpirank);
      freopen (MPIAUTOSTDOUT, "w", stdout);
      freopen (MPIAUTOSTDOUT, "w", stderr);
    }   
  else
    {   
      sprintf (MPIAUTOSTDOUT, "stdout.%d", mpirank);
      sprintf (MPIAUTOSTDERR, "stderr.%d", mpirank);
      freopen (MPIAUTOSTDOUT, "w", stdout);
      freopen (MPIAUTOSTDERR, "w", stderr);
    }   

  setvbuf (stdout, NULL, _IONBF, 0);
  setvbuf (stderr, NULL, _IONBF, 0);

}
