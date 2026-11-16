package MPI::Slurm;

use strict;
use base qw (MPI);

sub mpirank_variable_name
{
  return ('SLURM_PROCID');
}

sub mpirun_cyclic_option
{
  return '--distribution=cyclic';
}

sub mpirun_options
{
  my ($self) = @_;
  my $opts = $self->{opts};
  my @opts = ({opt => '--ntasks',          val => $opts->{np}}, 
              {opt => '--ntasks-per-node', val => $opts->{nnp}},
              '--kill-on-bad-exit=1', '--export=ALL');

# Partial node: let this step share the CPUs of the job with other steps,
# without Slurm binding; masks are applied by linux_bind

  if ($self->{arch}->partial_node ())
    {
      push @opts, '--overlap', '--cpu-bind=none';
    }

  return @opts;
}

sub run
{
  my ($self) = @_;

  my ($opts, $mpmd) = @{$self}{qw (opts mpmd)};

  my $ummf = $opts->{'use-mpi-machinefile'};

  if (@$mpmd)
    {
      $opts->{'use-mpi-machinefile'} = 1;
    }

  my $c = $self->SUPER::run ();

  $opts->{'use-mpi-machinefile'} = $ummf;

  return $c;
}

sub machinefile_entry
{
  my ($class, %args) = @_;
  my ($node, $p1, $p2) = @args{qw (node p1 p2)};
  return join ("\n", (($node) x ($p2 - $p1 + 1), ''));
}

sub machinefile_options
{
  my ($class, %args) = @_;

  my $np = 0;

  for my $d (@{ $args{dist} })
    {
      $np += $d->{np};
    }


  my $machinefile = $class->get_machinefile (%args);

  $ENV{SLURM_HOSTFILE} = $machinefile;

  return ('--distribution=arbitrary', '--ntasks', $np);
}

1;
