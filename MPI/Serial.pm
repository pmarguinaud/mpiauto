package MPI::Serial;

use base qw (MPI);
use strict;

sub mpirun_options
{
  my $self = shift;
  return ({opt => '', val => ''},
          {opt => '', val => ''});
}

sub mpirun
{
  my ($class, %args) = @_;
  my ($bin, $arch) = @args{qw (bin arch)};

  my $ldd = $arch->ldd (bin => $bin, sym => 1);

  if (exists $ldd->{'libumpi.so'})
    {
      $arch->setup_umpi (%args);
    }

  return '';
}


1;
