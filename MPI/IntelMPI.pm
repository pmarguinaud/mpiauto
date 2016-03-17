package MPI::IntelMPI;

use strict;
use base qw (MPI);

sub mpirun_options
{
  my ($self) = @_;
  my $opts = $self->{opts};
  return ({opt => '-np',  val => $opts->{np}}, 
          {opt => '-ppn', val => $opts->{nnp}});
}

sub mpirank_variable_name
{
  return ('PMI_RANK');
}

sub run
{
  my $self = shift;
  my ($opts, $mpmd) = @{$self}{qw (opts mpmd)};
  my $ummf = $opts->{'use-mpi-machinefile'};

# Delete this variable, because otherwise IntelMPI distribution goes cyclic
  delete $ENV{SLURM_CPUS_PER_TASK};

  if ($opts->{'use-intelmpi-bind'})
    {
      $ENV{OMP_PROC_BIND} = 'true';
    }

# IntelMPI does not support MPMD with non-uniform nnp
# we have to generate a machine file as a workaround

  if ($opts->{distribution} eq 'cyclic')
    {
      $opts->{'use-mpi-machinefile'} = 1;
    }

  if (! $ummf)
    {
      for my $d (@$mpmd)
        {
          if (($d->{nnp} != $opts->{nnp}) || ($d->{distribution} eq 'cyclic'))
            {
              $opts->{'use-mpi-machinefile'} = 1;
              last;
            }
        }
      
    }

  my $dirmpi = &File::Basename::dirname ($self->{mpirun});
  local $ENV{PATH} = "$dirmpi:$ENV{PATH}";

  my $c = $self->SUPER::run (@_);

  $opts->{'use-mpi-machinefile'} = $ummf;

  return $c;
}

sub machinefile_entry
{
  my ($class, %args) = @_;
  my ($node, $p1, $p2) = @args{qw (node p1 p2)};
  return $p1 == $p2 ? "$node\n" : sprintf ("%s:%d\n", $node, $p2-$p1+1);
}

sub machinefile_options
{
  my ($class, %args) = @_;

  my $machinefile = $class->get_machinefile (%args);

  return ('-machinefile' => $machinefile);
}

sub mpmd_extra_args
{
  my $self = shift;
  my ($mpmd, $opts) = @{$self}{qw (mpmd opts)};

  for (@{ $mpmd })
    {
      my $class = ref ($self);
      die ("$class only supports uniform nnp distribution")
        if ($_->{nnp} != $opts->{nnp});
    }

  return map 
           {
             my $mpmd = $_;
             (':', -np => $mpmd->{np}, '-env', 'OMP_NUM_THREADS', $mpmd->{openmp}, @{$opts->{'prefix-command'}}, $mpmd->{bin}, @{ $mpmd->{args} })
           }
         @{ $mpmd };
}

1;
