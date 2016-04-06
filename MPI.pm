package MPI;

use strict;

our $FMT1 = "%-15s : %s\n";
our $FMT2 = "      %s\n";
our $FMT3 = "      %-30s : %s\n";

sub new
{
  my ($class, %args) = @_;
  my ($opts, $bin, $args) = @args{qw (opts bin args)};

  my $mpirun = $class->mpirun (%args);

  my $self = bless {%args, mpirun => $mpirun}, $class; 
  return $self;
}

sub class
{
  my ($class, %args) = @_;
  my ($opts, $bin, $arch, $schd, $mpmd) = @args{qw (opts bin arch schd mpmd)};

  my ($mpirun, $version);

  if ($opts->{serial})
    {
      ($mpirun, $class, $version) = ('', 'MPI::Serial', '');
      eval "use $class\n";
      $@ && die ($@);
    }
  else
    {
      ($mpirun, $class, $version) = $arch->grokmpirun (
                                                         opts => $opts, bin  => $bin, 
                                                         schd => $schd, mpmd => $mpmd,
                                                      );
    }

  if (wantarray ()) 
    {
      return ($class, $version);
    }
  else
    {
      return $class;
    }
}

sub spawn
{
  my %args = @_;

  my ($cmd, $pid)  = @args{qw (cmd pid)};

  $$pid = fork ();

  unless (defined ($$pid))
    {
      warn ("Fork failed : $!\n");
      return 0;
    }

  exec ("exec $cmd")
    unless ($$pid);


  waitpid ($$pid, 0);

  my $c = $?;

  $$pid = 0;

  if ($c)
    {
      if ($c & 127) 
        {
          warn (sprintf ("`%s' received signal %d\n", $cmd, $c & 127));
        }
      else 
        {
          warn (sprintf ("`%s' exited with value %d\n", $cmd, $c >> 8));
        }
      return 0;
    }

  return 1;
}

sub mpirun
{
  use File::Basename;

  my ($class, %args) = @_;
  my ($opts, $bin, $arch, $schd, $mpmd) = @args{qw (opts bin arch schd mpmd)};
  my ($mpirun, $c) = $arch->grokmpirun (opts => $opts, bin => $bin, schd => $schd, mpmd => $mpmd);

  (my $mpikind = $class) =~ s/^MPI:://o;
  if ($opts->{'mpirun-name'}{$mpikind})
    {
      if ('File::Spec'->file_name_is_absolute ($opts->{'mpirun-name'}{$mpikind}))
        {
          $mpirun = $opts->{'mpirun-name'}{$mpikind};
        }
      else
        {
          $mpirun = 'File::Spec'->catfile (&dirname ($mpirun), $opts->{'mpirun-name'}{$mpikind}); 
        }
    }

  unless (-f $mpirun)
    {
      die ("`$mpirun' does not exist\n");
    }

  return $mpirun;
}

sub run
{
  my ($self) = @_;

  my ($opts, $bin, $args, $arch, $schd, $mpmd) = @{$self}{qw (opts bin args arch schd mpmd)};

# Prepare wrapper

  my $wrap = $opts->{wrap};
  if ($wrap && $opts->{debug})
    {
      $wrap = 0;
    }

# It is necessary to use the wrapper when a machine file is used 
# and different executables are used

  $wrap ||= ($opts->{'use-mpi-machinefile'} && @$mpmd);

  if ($wrap)
    {
      $self->wrap ();
      my @std = grep { m/^std(?:err|out|eo)\.\d+$/o } (<stderr.*>, <stdout.*>, <stdeo.*>);
      unlink ($_) for (@std);
    }

  $self->setup_env ();

  my $c = 1;

  my ($MPIAUTORANK, $_MPIAUTORANK) = $self->mpirank_variable_name ();
  $_MPIAUTORANK ||= $MPIAUTORANK;
  @ENV{qw (MPIAUTORANK _MPIAUTORANK)} = ($MPIAUTORANK, $_MPIAUTORANK);

  {
    my $restart = $opts->{'init-timeout-restart'};
    my $timeout = $opts->{'init-timeout'};

# Time-out library 

    if ($timeout)
      {
        my $wrapinit = "$MPI::AUTO::BASEDIR/lib/wrapinit.so";
        if (-f $wrapinit)
          { 
            $arch->preload ($wrapinit);
          }
        else
          {
            $timeout = 0;
          }
      }

RESTART:
    my ($lockA, $lockB);
    if ($timeout)
      {
        $ENV{MPIAUTOTIMEOUT} = $timeout;
        use File::Temp;
        use File::Spec;

        sub fh { 'File::Temp'->new (UNLINK => 0, TEMPLATE => '.mpiautotimeout.XXXX', SUFFIX => '.lock')->filename () };

        $lockA = $ENV{MPIAUTOTIMEOUTLOCKA} = 'File::Spec'->rel2abs (&fh ());
        $lockB = $ENV{MPIAUTOTIMEOUTLOCKB} = 'File::Spec'->rel2abs (&fh ());

        if ($opts->{'init-timeout-control'})
          {
            $SIG{ALRM} = sub { 
# Kill mpirun or srun if process still exists and has failed to go through MPI_Init
# we assume here that a timeout occured in MPI_Init on master node
                               kill (15, $self->{cmd_pid}) 
                                 if ($self->{cmd_pid} && (-f $lockB)) 
                             };
            alarm ($timeout * 2);
          }
      }
      
    $c = $self->do_run ($opts, $mpmd, $schd, $arch, $bin, $args);

    if ($timeout)
      {

        delete $SIG{ALRM}
          if ($opts->{'init-timeout-control'});

        if (-f $lockA)
          {
# Executable was not blocked in MPI_Init; something else happened
            unlink ($lockA);
          }
        elsif ($restart)
          {
# Timeout in MPI_Init; restart
            printf($MPI::FMT2, 'MPI_Init timeout...')
              if ($opts->{verbose});

            $self->show_stdeo (opts => $opts, schd => $schd)
              if ($wrap);

            $restart--;
            goto RESTART;
          }
      }
  }


  $self->show_stdeo (opts => $opts, schd => $schd)
    if ($wrap && (! $opts->{dryrun}));

  $self->cleanup_env ();

  return $c;
}

sub state
{
  use Storable;
  use File::Temp;
  use File::Spec;

  my $self = shift;
  
  my $fh = 'File::Temp'->new (UNLINK => 1, TEMPLATE => '.mpiautoXXXXX');

  my @mods;

  while (my ($pm, $path) = each (%INC))
    {
      substr ($path, length ($path) - length ($pm), length ($pm), '');
      $path = 'File::Spec'->canonpath ($path);

      next unless ($path eq $MPI::AUTO::BASEDIR);

      $pm =~ s/\.pm$//o;
      $pm =~ s,/,::,go;

      push @mods, $pm;
    }

  &Storable::nstore ([$self, \@_, \@mods], $fh->filename ());

  return $fh;
}

sub do_run
{
  my $self = shift;
  my ($opts, $mpmd, $schd, $arch, $bin, $args) = @_;

  if ($opts->{'mpi-alloc'})
    {
      my $ctx = $self->state (@_);
      my $cmd = "$opts->{'mpi-alloc'} $MPI::AUTO::BASEDIR/mpiauto.do_run " . 'File::Spec'->rel2abs ($ctx);

      printf($MPI::FMT1, 'Alloc command', $cmd)
        if ($opts->{verbose});

      return &spawn (cmd => $cmd, pid => \$self->{cmd_pid});
    }


  (my $mpikind = ref ($self)) =~ s/^MPI:://o;

# Set MPI environment

  my %env = map { 
                  my @x; 
                  if (s/=$//o) 
                    {  
                      @x = ($_, "");
                    } 
                  else 
                    { 
                      @x = split (m/=/o, $_);  
                    } 
                  @x 
                }
            split (m/,(?=\w+=)/o, $opts->{'mpi-special-env'}{$mpikind} || '');


  if ($opts->{verbose} && %env)
    {
       my $modf = 0;

       for my $var (sort keys (%env))
         {
           if (defined ($ENV{$var}) && ($ENV{$var} ne $env{$var}))
             {
               printf($MPI::FMT1, 'Warning', "$var='$ENV{$var}', but mpiauto recommends $var='$env{$var}'");
             }
           else
             {
               printf($MPI::FMT1, 'Remark', 'MPI environment was modified')
                 unless ($modf++);
               printf($MPI::FMT3, $var, "'$env{$var}'");
               $ENV{$var} = $env{$var};
             }
         }
    }

# Get mpi arguments

  my ($np, $nnp, @mpiargs) = ($self->mpirun_options (), split (m/\s+/o, $opts->{'mpi-special-opts'}{$mpikind} || ''));

  if (($opts->{'distribution'} eq 'cyclic') && (! $opts->{'use-mpi-machinefile'}))
    {
      push @mpiargs, $self->mpirun_cyclic_option ();
    }

  my @cmd;

# Prepare machine file if requested

  if ($opts->{'use-mpi-machinefile'})
    {

      my @nodelist = $schd->nodelist ();
      unshift (@mpiargs, $self->machinefile_options (opts => $opts, nodelist => \@nodelist, dist => $self->mpmd_dist ()));
      if (@$mpmd)
        {
          @cmd = ($self->{mpirun}, @mpiargs, @{$opts->{'prefix-command'}});
        }
      else
        {
          @cmd = ($self->{mpirun}, @mpiargs, @{$opts->{'prefix-command'}}, $bin, @$args);
        }
    }
  else
    {
      unshift (@mpiargs, $nnp->{opt}, $nnp->{val});
      @cmd = ($self->{mpirun}, $np->{opt}, $np->{val}, @mpiargs, @{$opts->{'prefix-command'}}, $bin, @$args, $self->mpmd_extra_args ());
    }

  if ($opts->{'mpi-stdin-null'})
    {
      push @cmd, "< /dev/null";
    }

  if (@{ $opts->{'prefix-mpirun'} })
    {
      unshift (@cmd, @{ $opts->{'prefix-mpirun'} });
    }

  printf($MPI::FMT1, 'MPI command', join (' ', @cmd))
    if ($opts->{verbose});

  my $c = 1;

# Set up environment

  $schd->setup_env (mpmd => $mpmd, opts => $opts);

# Binding

  if ($opts->{'use-arch-bind'})
    {
      $arch->bind (tasks  => $opts->{nnp},    nodes        => $opts->{nn}, 
                   openmp => $opts->{openmp}, verbose      => $opts->{'arch-bind-verbose'},
                   proc   => $opts->{proc},   distribution => $opts->{'distribution'});
      for (@{ $mpmd })
        {
          $arch->bind (tasks  => $_->{nnp},    nodes        => $_->{nn},
                       openmp => $_->{openmp}, verbose      => $opts->{'arch-bind-verbose'}, 
                       proc   => $_->{proc},   distribution => $_->{'distribution'},
                       append => 1);
        }
    }

# Set OpenMP environment

  $ENV{OMP_NUM_THREADS} = $opts->{openmp};

  unless ($opts->{dryrun})
    {
      if ($opts->{debug})
        {
          my $dbg = 'MPI::Debugger'->new (path => $opts->{'debugger-path'}, arch => $arch);
          $c = $dbg->run (mpikind => $mpikind, mpirun => $self->{mpirun}, np => $np, 
                          mpiargs => \@mpiargs, bin => $bin, args => $args, opts => $opts,
                          mpi => $self);
        }
      else
        {
          $c = &spawn (cmd => "@cmd", pid => \$self->{cmd_pid});
        }
    }

  $schd->cleanup_env (opts => $opts);

  return $c;
}
 
sub show_stdeo
{
  my ($self, %args) = @_;

  my ($opts, $schd) = @args{qw (opts schd)};

# Sort stdout/stderr if wrapper is on

  my $fmt = $opts->{'wrap-output-format'};

  my @std = grep { m/^std(?:err|out|eo)\.\d+$/o } (<stderr.*>, <stdout.*>, <stdeo.*>);
  my (%rnk, %std);

  for (@std)
    {
      m/^(std(?:err|out|eo))\.(\d+)$/o;
      $std{$_} = $1;
      $rnk{$_} = $2;
    }

  @std = sort { ($rnk{$a} <=> $rnk{$b}) or ($a cmp $b) } @std;

# Rename & cat outputs 

  my ($TXT, @REN) = (''); # $TXT contains the contents of the last file
                          # @REN is the list of file names with the same contents

  for my $std (@std)
    {

      my $ren;
      if ($fmt)
        {
          my $JOBID   = $schd->jobid ();
          my $STDEO   = $std{$std};
          my $MPIRANK = $rnk{$std};
          $ren = eval "\"$fmt\"";
          if ($@)
            {
              die ("Error while parsing wrap-output-format `$fmt' : $@");
            }
          rename ($std, $ren)
            if ($std ne $ren);
        }
      else
        {
          $ren = $std;
        }

      if (! $opts->{'wrap-stdeo-silent'})
        {
          my $txt = do { local $/ = undef; my $fh = 'FileHandle'->new ("<$ren"); <$fh> };

          if ($opts->{'wrap-stdeo-pack'})
            {

              if (@REN && ($TXT ne $txt))
                {
                  my $t = $REN[0] eq $REN[-1] ? $REN[0] : "$REN[0] .. $REN[-1]";
                  use Tools::Frame qw (frame);
                  print
                    &Tools::Frame::frame ($t, 80),
                    $TXT;
                  @REN = ();
                }

              ($TXT, @REN) = ($txt, @REN, $ren);

              if ($std eq $std[-1])
                {
                  my $t = $REN[0] eq $REN[-1] ? $REN[0] : "$REN[0] .. $REN[-1]";
                  use Tools::Frame qw (frame);
                  print
                    &Tools::Frame::frame ($t, 80),
                    $txt;
                }

            }
          else
            {
              use Tools::Frame qw (frame);
              print
                &Tools::Frame::frame ($ren, 80),
                $txt;
            }
      }
    }

}

sub mpmd_dist
{
  my ($self) = @_;
  my ($opts, $bin, $args) = @{$self}{qw (opts bin args)};

  return [
           {np => $opts->{np}, nnp => $opts->{nnp}, nn => $opts->{nn}, 
            openmp => $opts->{openmp}, bin => $self->{bin}, args => $args,
            distribution => $opts->{distribution}, proc => $opts->{proc}},
           @{ $self->{mpmd} || [] },
         ];
}

sub wrap
{
  use File::Path;
  use Data::Dumper;

  my ($self) = @_;
  my ($opts, $bin, $arch, $schd) = @{$self}{qw (opts bin arch schd)};

  my $mpienv  = {%{ $self->collectenv () }, %{$opts->{'wrap-env'}}};

  my $dir = $opts->{'wrap-directory'} || '.';
  (-d $dir) or &mkpath ($dir);

  my $RUNID = 0;
  while (-f "$dir/env.$RUNID.pl")
    {
      $RUNID++;
    }

  if (%$mpienv)
    {
      local $Data::Dumper::Terse = 1;
      'FileHandle'->new (">$dir/env.$RUNID.pl")->print (&Dumper ($mpienv));
    }

  my $mpmd = $self->mpmd_dist ();
  my @exec;

  if ((@$mpmd > 1) && $opts->{'use-mpi-machinefile'})
    {
      my $rank = 0;
      for (@$mpmd)
        {
          my ($rank1, $rank2) = ($rank, $rank + $_->{np} - 1);
          my $rankid = $rank1 == $rank2 ? $rank1 : "$rank1-$rank2";

          my $mpmdpl = "$dir/mpmd.$rankid.pl";

          'FileHandle'->new (">$mpmdpl")->print (&Dumper ($_));

          push @exec, 
            '--exec', "$rankid=$mpmdpl";

          $rank = $rank2 + 1;
        }
    }
  else
    {
      @exec = ('--');
    }
  
  unshift @{ $opts->{'prefix-command'} }, 
            "$MPI::AUTO::BASEDIR/mpiautowrap", 
            (
              ($opts->{'wrap-stdeo'}   ? ('--stdeo'  ) : ()),
              ($opts->{'wrap-verbose'} ? ('--verbose') : ()),
              %$mpienv ? ('--env' => "$dir/env.$RUNID.pl") : (),
              @exec
            );

}

sub collectenv
{
  return {};
}

sub setup_env
{
  use File::Basename;
  use File::Spec;

  my $self = shift;

  my ($opts, $bin, $arch) = @{$self}{qw (opts bin arch)};

  if ($opts->{'setup-grib_api-env'})
    {
  
      my $ldd = $arch->ldd (bin => $bin);

      my ($lib) = grep { m/^libgrib_api(?:-(?:\d+\.)*(\d+))?.so(?:\.(?:\d+\.)*(\d+))?/o } keys (%$ldd);
      
      if ($lib)
        {
          my $prefix = &dirname (&dirname ($ldd->{$lib}));

          printf($MPI::FMT1, 'Grib_api prefix', $prefix)
            if ($opts->{verbose});

          my %env = 
            (
              GRIB_SAMPLES_PATH    => 'File::Spec'->canonpath ("$prefix/ifs_samples/grib1"),
              GRIB_DEFINITION_PATH => 'File::Spec'->canonpath ("$prefix/share/definitions"),
            );

          while (my ($var, $dir) = each (%env))
            {
              if ((-d $dir) && (! $ENV{$var}))
                {
                  $ENV{$var} = $dir;
                  push @{ $self->{setup_env}{var} }, $var;
                }
            }
        }

    }

}

sub cleanup_env
{
  my $self = shift;

  for my $var (@{ $self->{setup_env}{var} })
    {
      delete $ENV{$var};
    }

  delete $self->{setup_env};

}

sub machinefile_options
{
  die ("Machine file is not supported\n");
}

sub get_machinefile
{
  use File::Temp;

  my ($class, %args) = @_;

  my ($opts, $dist, $nodelist) = @args{qw (opts dist nodelist)};
  my @nodelist = @$nodelist;

  my $fh = 'File::Temp'->new (UNLINK => 0, DIR => '.', TEMPLATE => '.mpiauto.machinefileXXXXX');

  my $machinefile = $fh->filename ();

  my $P = 0;
  for my $d (@$dist)
    {
      my ($nn, $np, $nnp, $distrib) = @{$d}{qw (nn np nnp distribution)};
 
      my @nodes = splice (@nodelist, 0, $nn);

      if (scalar (@nodes) != $nn)
        {
          die ("Not enough nodes for MPI distribution\n");
        }

      if ($distrib eq 'block')
        {
          for (my $p  = 0; $p < $np; $p += $nnp)
            {
              (my $node = shift (@nodes)) 
                or die ("Not enough nodes for MPI distribution\n");
              $fh->print ($class->machinefile_entry (node => $node, p1 => $P+$p, p2 => $P+$p+($nnp-1)));
            }
        }
      elsif ($distrib eq 'cyclic')
        {
          my $node = 0;
          my @nnp;

          for (my $p  = 0; $p < $np; $p++)
            {
              $fh->print ($class->machinefile_entry (node => $nodes[$node], p1 => $P+$p, p2 => $P+$p));
              $nnp[$node]++;
              $node = ($node + 1) % scalar (@nodes);
            }

          for (@nnp)
            {
              if ($_ != $nnp)
                {
                  die ("Not enough nodes for MPI distribution\n");
                }
            }

        }
      else
        {
          die ("Unknown distribution: $distrib\n");
        }

      $P += $np;

    }

  $fh->close ();

  return $machinefile;
}


sub mpmd_extra_args
{
  my $self = shift;
  my ($mpmd) = @{$self}{qw (mpmd)};
  die if (@$mpmd);
  return ();
}

sub machinefile_entry
{
  my $class = shift;
  die ("$class cannot use machinefile\n");
}

sub mpirun_cyclic_option
{
  my $class = shift;
  die ("$class cannot run with cyclic distribution\n");
}


1;
