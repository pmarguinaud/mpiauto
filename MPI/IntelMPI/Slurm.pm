package MPI::IntelMPI::Slurm;

use strict;
use base qw (MPI::Slurm);

# Partial node: srun runs with --overlap --cpu-bind=none (see MPI::Slurm);
# the binding is done by linux_bind

sub partial_node_env
{
  return (I_MPI_PIN => 'off');
}

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
