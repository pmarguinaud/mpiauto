package ARCH::NECSX;

use strict;
use base qw (ARCH);

sub do_ldd
{
  return ();
}

sub grokmpirun
{
  use File::Spec;
  my $mpirun;
  for my $PATH (split (m/:/o, $ENV{PATH}))
    {
      $mpirun = 'File::Spec'->canonpath ("$PATH/mpirun");
      last if (-f $mpirun);
      $mpirun = undef;
    }

  die ("Cannot find mpirun\n")
    unless ($mpirun);

  eval "use MPI::NECSX";
  $@ && die ($@);

  return ($mpirun, 'MPI::NECSX', '');
}

1;
