package MPI::CrayMPICH;

use strict;

use base qw (MPI);
use FileHandle;

sub mpirun_options
{
  my ($self) = @_;
  my $opts = $self->{opts};
  my $arch = $self->{arch};
  
# Cray requires the -j option when HT is on

  my $ht = $arch->ht_level (tasks => $opts->{nnp}, openmp => $opts->{openmp});
  my @ht_opts = $ht ? ('-j', $ht) : ();

  return ({opt => '-n', val => $opts->{np}}, 
          {opt => '-N', val => $opts->{nnp}},
          -d => $opts->{openmp}, @ht_opts);
}

sub mpirank_variable_name
{
  return ('ALPS_APP_PE', 'PMI_FORK_RANK');
}

sub mpmd_extra_args
{
  my $self = shift;
  my ($mpmd, $opts, $arch) = @{$self}{qw (mpmd opts arch)};

  return map 
           {
             my $mpmd = $_;
             my $ht = $arch->ht_level (tasks => $mpmd->{nnp}, openmp => $mpmd->{openmp});
             my @ht_opts = $ht ? ('-j', $ht) : ();
             (':', -n => $mpmd->{np}, -N => $mpmd->{nnp}, -d => $mpmd->{openmp}, @ht_opts, 
              'env', "OMP_NUM_THREADS=$mpmd->{openmp}", 
              @{$opts->{'prefix-command'}}, 
              $mpmd->{bin}, @{ $mpmd->{args} })
           }
         @{ $mpmd };
}

sub wrap
{
  my ($self, @args) = @_;
  my ($opts, $bin, $arch, $schd) = @{$self}{qw (opts bin arch schd)};

  my $wrapstdeo = "$MPI::AUTO::BASEDIR/lib/wrapstdeo.so";
  $arch->preload ($wrapstdeo);
  
  return $self->SUPER::wrap (@args);
}

1;
