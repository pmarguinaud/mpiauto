package MPI::NECSX;

use strict;
use base qw (MPI);

sub mpirun_options
{
  my ($self) = @_;
  my $opts = $self->{opts};
  return ({opt => '-np',  val => $opts->{np}}, 
          {opt => '-nnp', val => $opts->{nnp}});
}

sub mpirank_variable_name
{
  return ('MPIRANK');
}

sub collectenv
{
  return \%ENV;
}

1;
