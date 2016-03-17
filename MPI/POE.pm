package MPI::POE;

use strict;
use base qw (MPI);

sub mpirun_options
{
  my ($self) = @_;
  my $opts = $self->{opts};
  return ({opt => '-np',       val => $opts->{np}}, 
          {opt => '-npernode', val => $opts->{nnp}});
}

sub mpirank_variable_name
{
  return ('MP_PROCS');
}

1;
