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
              '--kill-on-bad-exit=1');

  if ($opts->{'use-slurm-bind'})
    {
      $ENV{OMP_PROC_BIND} = 'true';
      my $arch = $self->{arch};
      my @bind = $arch->bind_node (tasks  => $opts->{nnp},    nodes   => $opts->{nn},
                                   openmp => $opts->{openmp}, verbose => $opts->{'arch-bind-verbose'},
                                   proc   => $opts->{proc});


      if (@bind)
        {
# Convert binary mask to hexadecimal

          my @mask_cpu;
          for (@bind)
            {
              chomp;
              my @mask = split (m/:/o, reverse ($_));
              my @X;
              for my $mask (@mask)
                {
                  my @x = split (m//o, $mask);
                  for (0 .. $#x)
                    {
                      $X[$_] = $X[$_] || $x[$_] || 0;
                    }
                }
              @X = (('0') x (scalar (@X) % 4), @X);
     
              my $mask_cpu = '0x';
              while (@X)
                {
                  $mask_cpu .= sprintf ('%1.1X', 2 * (2 * (2 * $X[0] + $X[1]) + $X[2]) + $X[3]);
                  splice (@X, 0, 4);
                }
              push @mask_cpu, $mask_cpu;
            }
     
          for (@mask_cpu) 
            {   
              s/^0x0+/0x/o;
            }
     
          push @opts, '--cpu_bind=mask_cpu:' . join (',', @mask_cpu);

        }

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
