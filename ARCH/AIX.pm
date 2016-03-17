package ARCH::AIX;

use strict;
use base qw (ARCH);

sub do_ldd
{
  use File::Basename;

  my ($class, $bin) = @_;

  my @ldd = split (m/\n/o, `ldd $bin`);
  shift (@ldd);
  
  for (@ldd)
    {
      s/^\s*//o;
      s/\(.*$//o;
    }
  
  @ldd = map { (&basename ($_), $_) } @ldd;

  return @ldd;
}

sub grokmpirun
{
  use File::Basename;

  my ($arch, %args) = @_;

  my ($bin, $opts, $schd) = @args{qw (bin opts schd)};

  my $ldd = $arch->ldd (bin => $bin, sym => 1);
  
  (my $libmpi = $ldd->{'libmpi_r.a'})
    or die ("Cannot find libmpi.so in $bin\n");
  
  my $dirmpi = $libmpi;
  
  for (1 .. 2)
    {
      $dirmpi = &dirname ($dirmpi);
    }
  
  my $mpirun = "$dirmpi/bin/poe";
  
  die ("Cannot find mpirun in $bin\n")
    unless (-f $mpirun);
  
  eval "use MPI::POE";
  $@ && die ($@);

  return ($mpirun, "MPI::POE", '');
}


1;
