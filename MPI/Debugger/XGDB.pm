package MPI::Debugger::XGDB;

use strict;
use base qw (MPI::Debugger);

sub run
{
  use File::Copy;

  my ($self, %args) = @_;

  my ($mpi, $mpikind, $mpirun, $np, $mpiargs, $bin, $args, $opts) = 
    @args{qw (mpi mpikind mpirun np mpiargs bin args opts)}; 

  my $arch = $self->{arch};
  my $path = $self->{path};

  unlink ('.start.gdb');

  my $gmkpack;
  if ($opts->{'debug-try-gmkpack'})
    {   
      $gmkpack = $arch->readbin (section => '.gmkpack', perl => 1, bin => $bin);

      if ($gmkpack)
        {   
          if ($opts->{verbose})
            {   
              printf($MPI::FMT1, 'Pack', $gmkpack->{pack});
            }   
          if (-f "$gmkpack->{pack}/.gdb/.gdbinit")
            {
              &copy ("$gmkpack->{pack}/.gdb/.gdbinit", '.start.gdb');
            }
        }
    }

  'FileHandle'->new ('>>.start.gdb')->print (<< "EOF");
file $bin
start @$args
EOF

  my ($mpirank) = $mpi->mpirank_variable_name ();

  my @opts = split (m/\s+/o, $opts->{'debugger-options'});

  my @cmd = ($mpirun, $np->{opt}, $np->{val}, @$mpiargs, $path, 
             $opts->{'x11-display'} ? ('--display' => $opts->{'x11-display'}) : (),
             $opts->{'x11-direct'}  ? ('--direct') : (),
             @{$opts->{'x11-f-proxy'}||[]} ? ('--f-proxy' => @{$opts->{'x11-f-proxy'}}) : (),
             @{$opts->{'x11-b-proxy'}||[]} ? ('--b-proxy' => @{$opts->{'x11-b-proxy'}}) : (),
             '--', '--mpirank', $mpirank, @opts, '--', $bin, @$args);

  if ($opts->{verbose})
    {
      printf($MPI::FMT1, 'XGDB command', join (' ', @cmd));
    }

  my $c = 1;
 
  unless ($opts->{dryrun})
    {
      $c = ! system (@cmd);
    }

  unlink ('.start.gdb');

  return $c;
}

1;
