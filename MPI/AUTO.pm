package MPI::AUTO;

use Data::Dumper;
use FileHandle;
use FindBin qw ($Bin);

use Env::Tmp;
use ARCH;
use MPI;
use Scheduler;
use Getopt::Configurable qw (ARGS BOOL GRPS);
use MPI::Debugger;

our $BASEDIR;

{
  no warnings;
  
  sub INIT
  {
    use File::Basename;
    
    our $BASEDIR = $INC{'MPI/AUTO.pm'};
    for (1 .. 2)
      {
        $BASEDIR = &dirname ($BASEDIR);
      }
  }

}

use strict;

sub new
{
  my $class = shift;
  return bless {@_}, $class;
}

sub shift_arglist
{
  my $args = shift;
  for my $i (0 .. $#{$args})
    {
      return splice (@$args, 0, $i)
        if ($args->[$i] eq '--');
    }
  return splice (@$args, 0, scalar (@$args));
}

sub check_nn_np_nnp
{
  my ($opts, $bin, $args) = @_;

  for (@{$opts}{qw (nn np nnp)})
    {
      if (defined ($_))
        {
          die ("nn, np, nnp take only integer values\n")
            unless (m/^\d+$/o);
        }
    }

  if (defined ($opts->{nnp}))
    {
      die ("nnp should be 1 or greater\n")
        if ($opts->{nnp} == 0);
    }
  
  if (defined ($opts->{nn}))
    {
      if (defined ($opts->{np}) && (! defined ($opts->{nnp})))
        {
          $opts->{nnp} = $opts->{nn} ? $opts->{np} / $opts->{nn} : 1;
        }
      elsif (defined ($opts->{nnp}) && (! defined ($opts->{np})))
        {
          $opts->{np} = $opts->{nnp} * $opts->{nn};
        }
      elsif (defined ($opts->{nnp}) && (defined ($opts->{np})))
        {
          if ($opts->{'mpi-allow-odd-dist'})
            {
              die ("np should be <= nn * nnp\n")
                unless ($opts->{np} <= $opts->{nn} * $opts->{nnp});
            }
          else
            {
              die ("np should be equal to nn * nnp\n")
                unless ($opts->{np} == $opts->{nn} * $opts->{nnp});
            }
        }
      else
        {
          $opts->{nnp} = 1;
          $opts->{np}  = $opts->{nn};
        }
    }
  else
    {
      $opts->{np} = 1
        unless (defined ($opts->{np}));

      $opts->{nnp} = $opts->{np}
        unless (defined ($opts->{nnp}));
      
      if ($opts->{nnp})
        {
          $opts->{nn} = $opts->{np} / $opts->{nnp};
        }
      else # then np must be 0 too; we set nn to 0 as well
        {
          $opts->{nn} = 0;
        }
    }

  if ($opts->{'mpi-allow-odd-dist'})
    {
      my @args = &shift_arglist ($args);
# Number of extra tasks to run on a single node
      my $re = $opts->{nn} * $opts->{nnp} - $opts->{np};
      if ($opts->{nn} * $opts->{nnp} != $opts->{np})
        {
          my $np = $opts->{np};
          $opts->{nn}  = $opts->{nn} - 1;
          $opts->{np}  = $opts->{nn} * $opts->{nnp};
          $np = $np - $opts->{np};
          unshift (@$args, @args, '--', 
              '-nn', 1, '-np', $np, '-openmp', $opts->{openmp}, 
              '-proc', $opts->{proc}, '-distribution', $opts->{distribution}, 
              '--', $bin, @args);
        }
      else
        {
          unshift (@$args, @args);
        }
    }
  else
    {
      die ("nn should divide np\n")
        if (int ($opts->{nnp}) != $opts->{nnp});
      die ("nnp should divide np\n")
        if (int ($opts->{nn}) != $opts->{nn});
    }
  
  
  if ($opts->{nn} && $opts->{np} && $opts->{nnp})
    {
      die (sprintf ("Inconsistent values for nn = %d, nnp = %d, np = %d\n", 
                    $opts->{nn}, $opts->{nnp}, $opts->{np}))
        if (($opts->{nn} * $opts->{nnp}) != $opts->{np});
    }
  
  unless ($opts->{nnp} && $opts->{np})
    {
      die ("At least two of the following options : `nn np nnp' should be explicit\n")
        if ($opts->{nn} != 0);
    }
}
  

sub parse_mpmd
{
  use Getopt::Long;

  my ($opts, $args) = @_;

  my @mpmd;

  while (@$args)
    {
      (@$args && (shift (@$args) eq '--')) or die ("Junk in argument list 1\n");
      my @opts = &shift_arglist ($args);
      (@$args && (shift (@$args) eq '--')) or die ("Junk in argument list\n");
      my ($bin, @args) = &shift_arglist ($args);
      $bin or die ("Junk in argument list\n");

      local @ARGV = @opts;

      my %opts = (np => undef, nnp => undef, nn => undef, openmp => $ENV{OMP_NUM_THREADS} || 1, 
                  proc => $opts->{proc}, distribution => 'block', 'mpi-allow-odd-dist' => $opts->{'mpi-allow-odd-dist'});

      &GetOptions (
                     'np=s'               => \$opts{np},   
                     'nnp=s'              => \$opts{nnp}, 
                     'nn=s'               => \$opts{nn},   
                     'openmp=s'           => \$opts{openmp},
                     'proc=s'             => \$opts{proc}, 
                     'distribution=s'     => \$opts{distribution},
                     'mpi-allow-odd-dist' => \$opts{'mpi-allow-odd-dist'},
                  );


      &check_nn_np_nnp (\%opts, $bin, $args);

      my $mpmd = {%opts, bin => $bin, args => \@args};
      push @mpmd, $mpmd if ($opts{nn} > 0);

    }

  return @mpmd;
}

  
sub run
{
  my $self = shift;

  my $env = 'Env::Tmp'->new ();

  $ENV{PATH} = "$Bin:$ENV{PATH}";
  
  my @OPTS = ( 
    [ GRPS, '',                      'Dimensions (number of nodes, tasks, etc...)',                                                      ],
    [ ARGS, 'nn',                    'Number of nodes',                                            0,                      undef,   '=', ], 
    [ ARGS, 'np',                    'Number of MPI tasks',                                        0,                      undef,   '=', ], 
    [ ARGS, 'nnp',                   'Number of MPI tasks per node',                               0,                      undef,   '=', ], 
    [ ARGS, 'openmp',                'Number of OpenMP threads per task 
                                      (default to OMP_NUM_THREADS)',                               0, $ENV{OMP_NUM_THREADS} || 1,   '=', ], 
         
    [ ARGS, 'distribution',          "`block' or `cyclic'",                                        0,                    'block',   '=', ],
    [ ARGS, 'proc',                  'Processor type (default is to look at environment
                                      (/proc/cpuinfo for instance)',                               0,                         '',   '=', ], 
    [ BOOL, 'mpi-allow-odd-dist',    'Usually nn should divided np, or nnp should divide np,       
                                      with this flag, we try to have extra tasks running
                                      on a single node',                                           0,                          0,    '', ], 
    [ BOOL, 'serial',                'Run binary as a serial executable',                          0,                          0,    '', ], 
    [ BOOL, 'serial-mpi',            'Binary is a serial executable, but launched by mpirun',      0,                          0,    '', ], 

    [ GRPS, '',                      'Help and test options',                                                                            ],
    [ BOOL, 'dryrun',                'Do all usual processing, but do not call mpirun',            0,                          0,    '', ], 
    [ BOOL, 'help',                  'Show help message',                                          0,                          0,    '', ],  
    [ BOOL, 'verbose',               'Be verbose',                                                 0,                          0,    '', ],  
         
    [ GRPS, '',                      'MPI customization',                                                                                ],
    [ ARGS, 'prefix-command',        'Prefix command (valgrind, a user provided MPI 
                                      wrapper, etc...); these commands may be stacked',            0,                         [],  '+=', ], 
    [ ARGS, 'prefix-mpirun',         'Prefix mpirun with a command; eg: /usr/bin/time -f 
                                      "time=%e"',                                                  0,                         [],  '+=', ], 
    [ ARGS, 'mpirun-name',           'MPI launcher basename for a particular MPI : mpiexec, 
                                      mpirun, etc...; for instance : --mpirun-name 
                                      IntelMPI="mpiexec.hydra"',                                   0,                         {},  '+=', ], 
    [ ARGS, 'mpi-special-opts',      'Options to be passed to a particular MPI; for instance,
                                      --mpi-special-opts OpenMPI="--mca mpi_abort_print_stack 1"
                                      would pass "--mca mpi_abort_print_stack 1" to the OpenMPI
                                      mpirun',                                                     0,                         {},  '+=', ], 
    [ ARGS, 'mpi-special-env',       'Environment variables to be passed for a particular MPI;
                                      for instance, --mpi-special-env 
                                      IntelMPI="I_MPI_DAPL_PROVIDER=ofa-v2-mlx4_0-1u" would set
                                      I_MPI_DAPL_PROVIDER to "ofa-v2-mlx4_0-1u" when IntelMPI is
                                      used',                                                       0,                         {},  '+=', ], 
    [ BOOL, 'use-mpi-machinefile',   'Generate machine file and use it',                           0,                          0,    '', ],  
           
    [ BOOL, 'mpi-stdin-null',        'Connect mpirun stdin to /dev/null',                          0,                          0,    '', ], 
    [ BOOL, 'use-session',           'Allow mpiauto session mechanism',                            0,                          0,    '', ], 
    [ ARGS, 'init-timeout',          'Set a timeout on MPI_INIT',                                  0,                          0,   '=', ], 
    [ ARGS, 'init-timeout-restart',  'Number of times to restart after a MPI_INIT timeout',        0,                          0,   '=', ], 
    [ BOOL, 'init-timeout-control',  'Control MPI startup; if srun/mpirun fails to connect
                                      to compute nodes, then kill it',                             0,                          0,    '', ], 

    [ ARGS, 'mpi-alloc',             'MPI ressource allocator',                                    0,                         '',   '=', ], 
    [ GRPS, '',                      'Debugger options',                                                                                 ],
    [ BOOL, 'debug',                 'Start debugger',                                             0,                          0,    '', ], 
    [ BOOL, 'debugger-x11-proxy',    'Debugger requires X11 proxy',                                0,                          0,    '', ], 
    [ BOOL, 'debug-try-gmkpack',     'Try to read session from gmkpack',                           0,                          0,    '', ], 
    [ ARGS, 'debugger-path',         'Path to debugger',                                           0,                         '',   '=', ],
    [ ARGS, 'debugger-break',        'Break at specified location',                                0,                          0,    '', ], 
    [ ARGS, 'debugger-options',      'Extra options passed to debugger',                           0,                         '',    '', ], 
        
    [ GRPS, '',                      'X11 options',                                                                                      ],
    [ ARGS, 'x11-display',           'Display for X11 applications',                               0,                         '',   '=', ],
    [ BOOL, 'x11-direct',            'X11 without ssh proxy',                                      0,                          0,   '=', ],
    [ BOOL, 'x11-proxy',             'Setup X11 proxy',                                            0,                          0,    '', ],
    [ ARGS, 'x11-f-proxy',           'Forward proxy list for X11',                                 0,                         [],   '=', ],
    [ ARGS, 'x11-b-proxy',           'Backward proxy list for X11',                                0,                         [],   '=', ],
        
    [ GRPS, '',                      'Configuration options',                                                                            ],
    [ ARGS, 'config',                'Load config file',                                           0,                         '',   '=', ],
    [ ARGS, 'site',                  'Try to load site-specific config files',                     0,                         '',   '=', ],
        
    [ GRPS, '',                      'Wrapper options',                                                                                  ],
    [ BOOL, 'wrap',                  'Use wrapper script',                                         0,                          0,    '', ], 
    [ BOOL, 'wrap-stdeo',            'Join stdout and stderr in wrapper',                          0,                          0,    '', ], 
    [ BOOL, 'wrap-stdeo-pack',       'Print stdeo/stdout/stderr only when different',              0,                          0,    '', ], 
    [ BOOL, 'wrap-stdeo-silent',     'Do not print stdeo/stdout/stderr',                           0,                          0,    '', ], 
    [ BOOL, 'wrap-verbose',          'Verbose wrapper script',                                     0,                          0,    '', ],  
    [ ARGS, 'wrap-output-format',    'Wrapper std|eo|out|err filename format; for instance :
                                      $STDEO.$MPIRANK',                                            0,          '$STDEO.$MPIRANK',   '=', ],
    [ ARGS, 'wrap-directory',        'Wrapper directory for temporary files; must be visible
                                      from all nodes',                                             0,                        '.',   '=', ],
        
    [ ARGS, 'wrap-env',              'Environment variables to be passed to MPI processes
                                      through the wrapper',                                        0,                         {},  '+=', ], 
    [ GRPS, '',                      'Slurm options',                                                                                    ],
    [ BOOL, 'use-slurm-mpi',         'Use Slurm MPI launcher when possible',                       0,                          1,    '', ],
    [ BOOL, 'fix-slurm-env',         'Fix Slurm environment',                                      0,                          1,    '', ],
    [ BOOL, 'fix-slurm-env-nodes',   'Fix Slurm environment; set node number and list variables',  0,                          1,    '', ],
        
    [ GRPS, '',                      'Grib API options',                                                                                 ],
    [ BOOL, 'setup-grib_api-env',    'Setup grib_api environment from ldd info',                   0,                          1,    '', ],
        
    [ GRPS, '',                      'Binding options',                                                                                  ],
    [ BOOL, 'use-slurm-bind',        'Use Slurm binding',                                          0,                          0,    '', ],
    [ BOOL, 'use-arch-bind',         'Generate a configuration file for binding',                  0,                          0,    '', ],
    [ BOOL, 'arch-bind-verbose',     'Print binding file',                                         0,                          0,    '', ],
    [ BOOL, 'use-openmpi-bind',      'Let OpenMPI handle the binding',                             0,                          0,    '', ],
    [ BOOL, 'use-intelmpi-bind',     'Let IntelMPI handle the binding',                            0,                          0,    '', ],
  
    [ GRPS, '',                      'UMPI options',                                                                                     ],
    [ ARGS, 'umpi-mpi-label',        'UMPI backend label',                                         0,                         '',   '=', ],
    [ BOOL, 'umpi-verbose',          'UMPI verbose',                                               0,                          0,    '', ],
  );
  
  my ($arch, $schd);
  
  my ($mpiclass, $mpiversion, %mpiclass) = ('', '');
  my $opts;
  
  my $goc = 'Getopt::Configurable'->new 
    (
      APP  => {version => $mpiversion, class => $mpiclass, name => 'mpiauto', prefix => 'MPI'},
      APPH => "-- program1 [arg1,1 arg1,2 ...] -- -np ... -nnp ... -- program2 [arg2,1 arg2,2 ...] -- ...",
      ARGV => [@_],
      OPTS => \@OPTS,
      FMT1 => $MPI::FMT1,
      FMT2 => $MPI::FMT2,
      FMT3 => $MPI::FMT3,
    );
  
  my ($bin, @args, @mpmd);
  
  while (1)
    {
      my $c  = $mpiclass;
  
      $opts = $goc->parse ();

# Post-process options
  
      $opts->{'x11-proxy'} ||= $opts->{'debugger-x11-proxy'} && $opts->{debug};  
      $opts->{'wrap'}      &&= (! $opts->{debug});                            # wrapper disabled for debugger

#

      ($bin, my @arglist) = $goc->argv ();

# Check nn, np, nnp
      &check_nn_np_nnp ($opts, $bin, \@arglist);

      @args = &shift_arglist (\@arglist);

# Look for extra options, binaries, arguments
      
      @mpmd = &parse_mpmd ($opts, \@arglist);

      
      $bin or $goc->help ();

      if ($opts->{'serial-mpi'})
        {
          unshift (@args, $bin);
          $bin = "$Bin/bin/mpilaunch.x";
        }
      
      $arch ||= 'ARCH'->class (bin => $bin);
      $schd ||= 'Scheduler'->class (opts => $opts);
  
      ($mpiclass, $mpiversion) = 'MPI'->class (
                                                 opts => $opts,  bin  => $bin, 
                                                 args => \@args, arch => $arch, 
                                                 schd => $schd,  mpmd => \@mpmd,
                                              );
      @{ $goc->{APP} }{qw (class version)} = ($mpiclass, $mpiversion);
  
      last
        if ($c eq $mpiclass);
  
      $mpiclass{$mpiclass}++;
  
      die ("Cannot choose MPI type among " . join (', ', sort keys (%mpiclass)))
        if ($mpiclass{$mpiclass} > 1);
        
    }

  if ($opts->{verbose})
    {
      use FindBin qw ($Bin);

      my $show_version = "$Bin/.git/refs/heads/show_version";
      if (-f "$show_version")
        {
          my $version = do { my $fh = 'FileHandle'->new ("<$show_version"); local $/ = undef; <$fh> };
          chomp ($version);
          printf($MPI::FMT1, 'Version', $version);
        }

      printf($MPI::FMT1, 'Arch', $arch);
      printf($MPI::FMT1, 'Scheduler', $schd);
      printf($MPI::FMT1, 'MPI', $mpiclass);
      printf($MPI::FMT1, 'Binary', $bin);
      printf($MPI::FMT1, 'Args', join (' ', @args));
      $goc->verbose ();
      for my $mpmd (@mpmd)
        {
          printf($MPI::FMT1, 'Binary', $mpmd->{bin});
          printf($MPI::FMT1, 'Args', join (' ', @{ $mpmd->{args} }));
          for my $opt (qw (nn np nnp openmp proc distribution))
            {
              printf($MPI::FMT3, "--$opt", $mpmd->{$opt});
            }
        }
    }
  
  
  my $mpi = $mpiclass->new (opts => $opts, bin => $bin, args => \@args, arch => $arch, schd => $schd, mpmd => \@mpmd);
  
  my $x11;
  if ($opts->{'x11-proxy'})
    {
      use X11::Proxy;
      $x11 = 'X11::Proxy'->new (%$opts);
      my $display = $x11->start ();
      if ($opts->{verbose})
        {
          printf($MPI::FMT1, 'Display', $display);
        }
      $ENV{DISPLAY} = $display;
    }
  elsif ($opts->{'x11-display'})
    {
      (my $DISPLAY = $opts->{'x11-display'}) =~ s/^\w+@//o;
      $ENV{DISPLAY} = $DISPLAY;
    }
  
  my $c = $mpi->run (opts => $opts, bin => $bin, args => \@args);
  
  if ($opts->{'x11-proxy'})
    {
      $x11->stop ();
    }
  
  return $c;
}


1;
