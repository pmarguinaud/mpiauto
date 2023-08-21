package ARCH::Linux;

use FileHandle;
use POSIX qw (ceil floor);
use Data::Dumper;

use strict;
use base qw (ARCH);

sub do_ldd
{
  my ($class, $bin) = @_;

  my @ldd = map { split (m/\s*=>\s*/o, $_) } grep { m/=>/o } split (m/\n/o, `ldd $bin`);
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

  $ldd = $arch->ldd (bin => $bin, sym => 1);

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
      local $ENV{PATH} = &dirname ($mpirun) . ":$ENV{PATH}";
      `$mpirun --version 2>&1`;
    };

  for ($version)
    {
      m/\bOpen\s*MPI\b.*(\d+(?:\.\d+)+)/io 
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

sub cpuinfo
{
  my ($class, %opts) = @_;

  if ($opts{proc})
    {
      my $conf;
      for my $dir ($MPI::AUTO::BASEDIR, "$ENV{HOME}/.mpiautorc")
        {
          $conf = "$dir/$opts{proc}.conf";
          last if (-f $conf);
        }
      my $cpuinfo = -f $conf ? do ($conf) : undef;
      return $cpuinfo;
    }

  my @cpuinfo = do { my $fh = 'FileHandle'->new ('</proc/cpuinfo'); <$fh> };
  chomp for (@cpuinfo);

  my @processor   = map { m/^processor\s*:\s*(\d+)$/o;       defined ($1) ? ($1) : () } @cpuinfo;
  my @physical_id = map { m/^physical\s+id\s*:\s*(\d+)$/o;   defined ($1) ? ($1) : () } @cpuinfo;
  my @core_id     = map { m/^core\s+id\s*:\s*(\d+)$/o;       defined ($1) ? ($1) : () } @cpuinfo;

  @processor   = &uniq (@processor);
  @physical_id = &uniq (@physical_id);
  @core_id     = &uniq (@core_id);

  return {
           nthreadpercore => scalar (@processor) / (scalar (@core_id) * scalar (@core_id)),
           ncpus          => scalar (@core_id) * scalar (@core_id),
           nsockets       => scalar (@physical_id),
         };
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

  my $nthreads = $cpuinfo->{ncpus} * $cpuinfo->{nthreadpercore};

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

sub bind_node
{
  my ($class, %opts) = @_;

  my $cpuinfo = $class->cpuinfo (%opts);

  die ("Could not retrieve cpuinfo\n")
    unless ($cpuinfo);


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
      push @line, join (':', map { 1 } (1 .. $opts{openmp})) . "\n";

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

