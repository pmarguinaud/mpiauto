package MPI::IntelMPI::Slurm;

use strict;
use base qw (MPI::Slurm);

sub run
{
  use File::Basename;
  use File::Spec;
  my $self = shift;
  my $srun = $self->{mpirun};
  my $prefix = &dirname (&dirname ($srun));
  local $ENV{I_MPI_PMI_LIBRARY} = 'File::Spec'->canonpath ("$prefix/lib64/libpmi.so");
  $self->SUPER::run (@_);
}

1;
