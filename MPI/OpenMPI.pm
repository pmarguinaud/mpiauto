package MPI::OpenMPI;

use strict;
use base qw (MPI);

sub mpirun_options
{
  my ($self) = @_;
  my $opts = $self->{opts};
  return ({opt => '-np',       val => $opts->{np}}, 
          {opt => '-npernode', val => $opts->{nnp}});
}

sub mpirun_cyclic_option
{
  return '--bynode';
}

sub mpirank_variable_name
{
  return ('OMPI_COMM_WORLD_RANK');
}

sub run
{
  my ($self) = @_;

  my ($opts, $mpmd) = @{$self}{qw (opts mpmd)};

  my $ummf = $opts->{'use-mpi-machinefile'};

  if ($opts->{distribution} eq 'cyclic')
    {
      $opts->{'use-mpi-machinefile'} = 1;
    }

  if ($opts->{'use-openmpi-bind'})
    {
      $ENV{OMP_PROC_BIND} = 'true';
    }

  my $c = $self->SUPER::run (@_);

  $opts->{'use-mpi-machinefile'} = $ummf;

  return $c;
}

sub machinefile_entry
{
  my ($class, %args) = @_;
  my ($node, $p1, $p2) = @args{qw (node p1 p2)};

  my @entry;
  for my $p ($p1 .. $p2)
    {
      push @entry, sprintf ("rank %5d=$node slot=1\n", $p);
    }

  return join ('', @entry);
}

sub machinefile_options
{
  my ($class, %args) = @_;

  my $machinefile = $class->get_machinefile (%args);

  return ('-rankfile' => $machinefile);
}

sub mpmd_extra_args
{
  my $self = shift;
  my ($mpmd, $opts) = @{$self}{qw (mpmd opts)};
  return map 
           {
             my $mpmd = $_;
             (':', -np => $mpmd->{np}, -npernode => $mpmd->{nnp}, -x => "OMP_NUM_THREADS=$mpmd->{openmp}", @{$opts->{'prefix-command'}}, $mpmd->{bin}, @{ $mpmd->{args} })
           }
         @{ $mpmd };
}

1;
