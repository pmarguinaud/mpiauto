package ARCH::Linux;

use FileHandle;
use POSIX qw (ceil floor);
use Data::Dumper;

use strict;
use base qw (ARCH);

sub do_ldd
{
  my ($class, $bin, $opts) = @_;

  my $ce = $opts->{'container-exec'}; $ce = $ce ? "$ce " : "";

  my @ldd = map { split (m/\s*=>\s*/o, $_) } grep { m/=>/o } split (m/\n/o, `$ce ldd $bin`);
  for (@ldd)
    {
      s/^\s*//o;
      s/\s*\(0x\w+\)\s*$//o;
    }

  return @ldd;
}

sub setup_umpi
{
  my ($arch, %args) = @_;

  my ($bin, $opts, $schd) = @args{qw (bin opts schd)};

  my $umpi = $arch->readbin (section => '.umpi', bin => $bin, perl => 1);
  
  die ("Cannot read UMPI info in `$bin'\n")
    unless ($umpi);
  
  if ($opts->{'umpi-verbose'})
    {
      printf($MPI::FMT1, 'UMPI prefix', $umpi->{prefix});
    }
  
  my $prefix = $umpi->{prefix};
  
  my $label = $opts->{'umpi-mpi-label'};

  unless ($opts->{serial})
    {
      die ("Option `umpi-mpi-label' is mandatory for UMPI executables\n")
        unless ($label);
    }
  
  my $libpath = $label ? "$prefix/lib/$label" : "$prefix/lib";
  
  die ("File does not exist: `$libpath/libumpi.so\n")
    unless (-f "$libpath/libumpi.so");
  
  if ($ENV{LD_LIBRARY_PATH})
    {
      $ENV{LD_LIBRARY_PATH} = "$libpath:$ENV{LD_LIBRARY_PATH}";
    }
  else
    {
      $ENV{LD_LIBRARY_PATH} = $libpath;
    }

  if ($opts->{verbose})
    {
      printf($MPI::FMT1, 'LD_LIBRARY_PATH', $ENV{LD_LIBRARY_PATH});
    }
  
  my $ldd = $arch->ldd (bin => $bin, sym => 1, reload => 1);
  
  if ($opts->{'umpi-verbose'})
    {
      printf($MPI::FMT1, 'UMPI ldd', '');
      for (sort keys (%$ldd))
        {
          printf($MPI::FMT3, $_, $ldd->{$_});
        }
    }

  return $ldd;
}


sub grokmpirun
{
  use File::Basename;

  my ($arch, %args) = @_;

  my ($bin, $opts, $schd, $mpmd) = @args{qw (bin opts schd mpmd)};

  my @libmpi = ('libmpi.so', 'libmpi_mt.so', 'libmpi_dbg.so', 'libmpi_dbg_mt.so', 
                'libmpich_cray.so', 'libmpich_intel.so', 'libmpich_gnu_48.so');

  my ($ldd, $libmpi);

  $ldd = $arch->ldd (bin => $bin, sym => 1, opts => $opts);

  $libmpi ||= $ldd->{$_} for (@libmpi);

  if ((! $libmpi) && (exists $ldd->{'libumpi.so'}))
    {
      $ldd = $arch->setup_umpi (%args);
    }
  
  $libmpi ||= $ldd->{$_} for (@libmpi);

  $libmpi or die ("Cannot find libmpi in $bin\n");

  my $dirmpi = $libmpi;

  for (1 .. 2)
    {
      $dirmpi = &dirname ($dirmpi);
    }
  
  my $version = '';
  my $mpikind = '';
  my $mpirun  = '';

  if (&basename ($libmpi) =~ m/^libmpich_\w+\.so$/o)
    {
      if ($mpirun = $arch->which ('aprun'))
        {
          $mpikind = "CrayMPICH";
          $version = `$mpirun --version 2>&1`;
          ($version) = ($version =~ m/aprun \(ALPS\) (\d+(?:\.\d+)*)/goms);
          goto FOUND;
        }
      die ("Cannot find aprun in $ENV{PATH}\n");
      $mpirun = 'aprun';
      $mpikind = "CrayMPICH";
      $version = 1.0;
      goto FOUND;
    }
  elsif (-f "$dirmpi/bin/mpirun")
    {
      $mpirun = "$dirmpi/bin/mpirun";
    }
  elsif (-f "$dirmpi/../bin/mpirun")
    {
      $mpirun = "$dirmpi/../bin/mpirun";
    }
  
  die ("Cannot find mpirun in $bin\n")
    unless (-f $mpirun);

  $version = do
    {
      my $ce = $opts->{'container-exec'};
      $ce = $ce ? "$ce ": "";
      local $ENV{PATH} = &dirname ($mpirun) . ":$ENV{PATH}";
      `$ce $mpirun --version 2>&1`;
    };

  for ($version)
    {
      m/\bOpen\s*MPI\b.*?(\d+(?:\.\d+)+\w*)/io 
        && do 
        { 
          $mpikind = 'OpenMPI';  
          $version = $1;
          last; 
        };
      m/\bIntel\s*Corporation/io
        && do 
        {
          $mpikind = 'IntelMPI'; 
if (0) {
          my $mpiexec = &dirname ($mpirun) . '/mpiexec.hydra';
          $mpirun = $mpiexec
            if (-f $mpiexec); 
}
          if ($mpirun =~ m,impi/+(\d+(?:\.\d+)+)/,o)
            {
              $version = $1;
            }
          elsif ($version =~ m/.*Version\s+(\S+)\s+Update\s+(\S+)\s+/io)
            {
              $version = "$1.$2";
            }
          elsif ($version =~ m/.*Version\s+(\S+)\s/io)
            {
              $version = $1;
            }
          last; 
        };
    }

  die ("Cannot find mpi kind\n")
    unless ($mpikind);

  if ($opts->{'use-slurm-mpi'} && $schd->isa ('Scheduler::SLURM'))
    {
      if ($mpirun = $arch->which ('srun'))
        {
          $mpikind = "$mpikind\::Slurm";
          $version = `$mpirun --version 2>&1`;
          ($version) = ($version =~ m/slurm\s+(\d+(?:\.\d+)+)/o);
        }
    }

FOUND:


  eval "use MPI::$mpikind";
  $@ && die ($@);

  return ($mpirun, "MPI::$mpikind", $version);
}

sub readbin
{
  use File::Basename;

  my ($class, %args) = @_;
  my ($section, $bin, $perl) = @args{qw (section bin perl)};
 
  my $f = $section . '.' . &basename ($bin);

  my $c = ! system ("readelf -p $section $bin > $f");

  my $X;

  if ($c && (-s $f))
    {
      $X = do { local $/ = undef; my $fh = 'FileHandle'->new ("<$f"); <$fh> };
      if ($perl)
        {
          $X =~ s/^.*?__PERL__//goms;
          $X =~ s/\^J//goms;
          $X = eval $X;
          if ($@)
            {
              die ($@);
            }
        }
    }

  unlink ($f);

  return $X;
}



sub uniq
{
  my $i = 1;
  my %x;
  for (@_)
    {
      next if (exists $x{$_});
      $x{$_} = $i++;
    }
  return sort { $x{$a} <=> $x{$b} } keys (%x);
}

# Parse a Linux CPU list ("0-3,8,10-11") into a list of CPU numbers

sub parse_cpulist
{
  my $str = shift;
  my @l;
  return @l unless (defined ($str));
  $str =~ s/\s+//go;
  for my $r (split (m/,/o, $str))
    {
      if ($r =~ m/^(\d+)-(\d+)$/o)
        {
          push @l, ($1 .. $2);
        }
      elsif ($r =~ m/^(\d+)$/o)
        {
          push @l, $1;
        }
    }
  return @l;
}

sub slurp
{
  my $f = shift;
  my $fh = 'FileHandle'->new ("<$f");
  return unless ($fh);
  local $/ = undef;
  my $s = <$fh>;
  $s =~ s/\s+$//o if (defined ($s));
  return $s;
}

# CPUs this process may run on (its affinity mask), from /proc/self/status

sub allowed_cpus
{
  my $status = &slurp ('/proc/self/status');
  return unless (defined ($status));
  my ($list) = ($status =~ m/^Cpus_allowed_list:\s*(\S+)/mo);
  return &parse_cpulist ($list);
}

# All online CPUs of the node

sub online_cpus
{
  return &parse_cpulist (&slurp ('/sys/devices/system/cpu/online'));
}

# The process may use only part of the node (numactl, taskset, cpuset)

sub partial_node
{
  my $class = shift;
  my @allowed = &allowed_cpus ();
  my @online  = &online_cpus ();
  return 0 unless (@allowed && @online);
  return scalar (@allowed) < scalar (@online) ? 1 : 0;
}

# Topology of the allowed CPUs: a list of cores, each core being the list of
# its allowed hardware threads (OS CPU numbers, sorted). Cores are sorted by
# their first allowed CPU. Returns nothing if sysfs is not available.

sub allowed_cores
{
  my @allowed = &allowed_cpus ();
  return unless (@allowed);

  my %core;
  for my $cpu (@allowed)
    {
      my $t = "/sys/devices/system/cpu/cpu$cpu/topology";
      my $pkg  = &slurp ("$t/physical_package_id");
      my $core = &slurp ("$t/core_id");
      return unless (defined ($pkg) && defined ($core));
      push @{ $core{"$pkg:$core"} }, $cpu;
    }

  my @cores = map { [sort { $a <=> $b } @$_] } values (%core);
  @cores = sort { $a->[0] <=> $b->[0] } @cores;

  return @cores;
}

sub read_proc_conf
{
  my ($class, %opts) = @_;
  my $conf;
  for my $dir ($MPI::AUTO::BASEDIR, "$ENV{HOME}/.mpiautorc")
    {
      $conf = "$dir/$opts{proc}.conf";
      last if (-f $conf);
    }
  return -f $conf ? do ($conf) : undef;
}

# Returns a hash describing the CPUs available to the job:
#  ncpus          : number of cores
#  nthreadpercore : number of hardware threads used per core
#  map            : (optional) map->[$core][$thread] = OS CPU number; when
#                   absent, CPU numbers follow the usual numbering
#                   (thread * ncpus + core)
#  width          : (optional) length of the masks written in linux_bind.txt
#
# When the process may use the whole node and a processor description is
# given (--proc), this description is used unchanged. Otherwise, the
# topology is taken from /proc/self/status and sysfs; --proc then only caps
# the number of hardware threads used per core.

sub cpuinfo
{
  my ($class, %opts) = @_;

  my $conf = $opts{proc} ? $class->read_proc_conf (%opts) : undef;

  return $conf
    if ($conf && (! $class->partial_node ()));

  my @cores = &allowed_cores ();

  if (@cores)
    {
      my ($ntpc) = sort { $a <=> $b } map { scalar (@$_) } @cores;
      $ntpc = $conf->{nthreadpercore}
        if ($conf && $conf->{nthreadpercore} && ($conf->{nthreadpercore} < $ntpc));

      my ($max) = sort { $b <=> $a } map { @{$_}[0 .. $ntpc-1] } @cores;

      return {
               nthreadpercore => $ntpc,
               ncpus          => scalar (@cores),
               map            => [map { [@{$_}[0 .. $ntpc-1]] } @cores],
               width          => $max + 1,
             };
    }

  return $conf if ($conf);

  my @cpuinfo = do { my $fh = 'FileHandle'->new ('</proc/cpuinfo'); <$fh> };
  chomp for (@cpuinfo);

  my @processor   = map { m/^processor\s*:\s*(\d+)$/o;       defined ($1) ? ($1) : () } @cpuinfo;
  my @physical_id = map { m/^physical\s+id\s*:\s*(\d+)$/o;   defined ($1) ? ($1) : () } @cpuinfo;
  my @core_id     = map { m/^core\s+id\s*:\s*(\d+)$/o;       defined ($1) ? ($1) : () } @cpuinfo;

  @processor   = &uniq (@processor);
  @physical_id = &uniq (@physical_id);
  @core_id     = &uniq (@core_id);

  return {
           nthreadpercore => scalar (@processor) / (scalar (@physical_id) * scalar (@core_id)),
           ncpus          => scalar (@physical_id) * scalar (@core_id),
           nsockets       => scalar (@physical_id),
         };
}

# Convert a mask over "virtual" CPUs (thread * ncpus + core) into a mask over
# OS CPU numbers, using the map built by cpuinfo

sub map_mask
{
  my ($class, $cpuinfo, $mask) = @_;

  return $mask unless ($cpuinfo->{map});

  my $ncpus = $cpuinfo->{ncpus};
  my @x = ('0') x $cpuinfo->{width};

  my @v = split (m//o, $mask);
  for my $v (grep { $v[$_] ne '0' } (0 .. $#v))
    {
      my $core   = $v % $ncpus;
      my $thread = int ($v / $ncpus);
      $x[$cpuinfo->{map}[$core][$thread]] = '1';
    }

  return join ('', @x);
}

sub map_line
{
  my ($class, $cpuinfo, $line) = @_;
  return $line unless ($cpuinfo->{map});
  chomp (my $l = $line);
  return join (':', map { $class->map_mask ($cpuinfo, $_) } split (m/:/o, $l)) . "\n";
}

sub start_verbose
{
  my ($class, $cpuinfo, $nthreads, %opts) = @_;

  if ($opts{verbose})
    {
      my $n1234 = join ('', map { (my $d = $_) =~ s/^.*(.)$/$1/go; $d } (1 .. $nthreads));
      printf (" %6s  %6s  %6s  : %s\n", '', '', '', join (':', ($n1234) x $opts{openmp}));
      my $line = join (':', map { sprintf ("%${nthreads}d", $_) } (1 .. $opts{openmp}));
      printf ("(%6s, %6s, %6s) : %s\n", 'Node', 'Task', 'Rank', $line);
    }

}


sub line_verbose
{
  my ($class, $line, $node, $task, $rank, %opts) = @_;
  if ($opts{verbose})
    {
      my $ll = $line;
      for ($ll)
        {
          s/0/ /go;
          s/1/X/go;
        }
      printf ("(%6d, %6d, %6d) : %s", $node, $task, $rank, $ll);
    }
}

sub bind : method
{
  use Cwd;
  use File::Spec;

  my ($class, %opts) = @_;

  my @line = $class->bind_node (%opts);

  return unless (@line);

  my $cpuinfo  = $class->cpuinfo (%opts);

  die ("Could not retrieve cpuinfo\n")
    unless ($cpuinfo);

  my $nthreads = $cpuinfo->{width} || ($cpuinfo->{ncpus} * $cpuinfo->{nthreadpercore});

  my $fh = 'FileHandle'->new (($opts{append} ? '>>' : '>') . 'linux_bind.txt');
  $class->start_verbose ($cpuinfo, $nthreads, %opts);

  $ENV{EC_LINUX_BIND} = 'File::Spec'->join (&Cwd::cwd (), 'linux_bind.txt');

  if ($opts{distribution} eq 'cyclic')
    {

      my $rank = 1;
      for my $task (1 .. $opts{tasks})
        {
          for my $node (1 .. $opts{nodes})
            {
              my $line = $line[$task-1];
              $class->line_verbose ($line, $node, $task, $rank, %opts);
              $fh->print ($line);
              $rank++;
            }
        }

    }
  else
    {

      my $rank = 1;
      for my $node (1 .. $opts{nodes})
        {
          for my $task (1 .. $opts{tasks})
            {
              my $line = $line[$task-1];
              $class->line_verbose ($line, $node, $task, $rank, %opts);
              $fh->print ($line);
              $rank++;
            }
        }

    }
  
  
  $fh->close ();

}

# Returns hyperthreading level

sub ht_level
{
  my ($class, %opts) = @_;
  my $cpuinfo = $class->cpuinfo (%opts);
  
  my $level = ($opts{tasks} * $opts{openmp}) / $cpuinfo->{ncpus};

  return $level
    if (int ($level) == $level);

  return 0;
}

# Masks per task (one line per task, one mask per OpenMP thread, separated
# by colons), over OS CPU numbers

sub bind_node
{
  my ($class, %opts) = @_;

  my $cpuinfo = $class->cpuinfo (%opts);

  die ("Could not retrieve cpuinfo\n")
    unless ($cpuinfo);

  return map { $class->map_line ($cpuinfo, $_) } $class->bind_node_virtual (%opts, cpuinfo => $cpuinfo);
}

# Same as bind_node, but masks are over virtual CPUs (thread * ncpus + core)

sub bind_node_virtual
{
  my ($class, %opts) = @_;

  my $cpuinfo = $opts{cpuinfo};


  my $cpuspertask  = $cpuinfo->{ncpus} / $opts{tasks};
  my $nthreads     = $cpuinfo->{ncpus} * $cpuinfo->{nthreadpercore};

  if (($cpuspertask * $cpuinfo->{nthreadpercore} == 1) && ($opts{openmp} == 1))
    {
      my @line;
      for my $task (1 .. $opts{tasks})
        {
          my @x = ('0') x ($cpuinfo->{ncpus} * $cpuinfo->{nthreadpercore});
          $x[$task-1] = '1';
          push @line, join ('', @x) . "\n";
        }
      return @line;
    }


  if ($cpuspertask * $cpuinfo->{nthreadpercore} < $opts{openmp})
    {
      return $class->nobind (%opts, cpuinfo => $cpuinfo);
    }

  my @line;

  my @w = (0) x $nthreads;

  for my $task (1 .. $opts{tasks})
    {
      my @thr = map { 
                      my $htoff = ($_-1) * ($cpuinfo->{ncpus});
                      ($htoff + &floor (($task-1) * $cpuspertask) .. $htoff + &ceil ($task * $cpuspertask - 1))
                    } (1 .. $cpuinfo->{nthreadpercore});

      my $ithr = 0;
      push @line, join (':', map 
                               {
                                 my $openmp = $_;
                                 my @x = ('0') x $nthreads;


                                 while ($w[$thr[$ithr]] > 0)
                                   {
                                     die if ($ithr > $#thr);
                                     die if ($thr[$ithr] > $#w);
                                     $ithr++;
                                   }

                                 my $thr = $thr[$ithr];
                                 $x[$thr] = '1';
                                 $w[$thr]++;

                                 join ('', @x)
                               }
                             (0 .. $opts{openmp}-1)) . "\n";
    }

  return @line;
}

sub nobind
{
  my ($class, %opts) = @_; 

  my @line;

  for my $task (1 .. $opts{tasks})
    {   
      # No binding: each thread may run on all the CPUs of the job
      my $all = '1' x ($opts{cpuinfo}{ncpus} * $opts{cpuinfo}{nthreadpercore});
      push @line, join (':', map { $all } (1 .. $opts{openmp})) . "\n";

    }   

  return @line;
}


sub preload
{
  my $class = shift;

  for ($ENV{LD_PRELOAD})
    {
      $_ ||= '';
      $_ = join (':', @_, $_);
      $_ =~ s/^://o;
      $_ =~ s/:$//o;
    }
}


1;

