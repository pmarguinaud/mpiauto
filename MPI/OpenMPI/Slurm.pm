package MPI::OpenMPI::Slurm;

use strict;
use base qw (MPI::Slurm);

sub mpirun_options
{
  my $self = shift;
  my @opts = $self->SUPER::mpirun_options (@_);
  return (@opts, '--resv-ports');
}

1;
