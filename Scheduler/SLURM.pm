package Scheduler::SLURM;

use strict;
use base qw (Scheduler);
use MPI::AUTO::Session;
use List::Util qw (uniq);

sub jobid
{
  $ENV{SLURM_JOBID};
}

sub find_free_nodes
{
  my ($class, %args) = @_;

  my $nn = $args{nn};

  my @nodelist = $class->expand_nodelist ($ENV{SLURM_NODELIST});

  my $jobid = $class->jobid ();

  my $session = $args{session} 
              ? 'MPI::AUTO::Session'->open (jobid => $jobid) 
              : 'MPI::AUTO::Session'->empty ();

  my @nn = grep { ! $session->{data}{nodes}{$_} } @nodelist;

  if (scalar (@nn) < $nn)
    {
      if (@nn)
        {
          die ("Unable to find $nn nodes; list of available nodes is : @nn\n")
        }
      else
       {
          die ("Unable to find $nn nodes; no nodes are available\n");
       }
    }

  @nn = @nn[0..$nn-1];

  @{ $session->{data}{nodes} }{@nn} = (1) x scalar (@nn);

  $session->close ();

  return @nn;
}

sub free_used_nodes
{
  my $class = shift;

  my $jobid = $class->jobid ();

  my $session = 'MPI::AUTO::Session'->open (jobid => $jobid);

  my @nn = $class->expand_nodelist ($ENV{SLURM_NODELIST});
  @{ $session->{data}{nodes} }{@nn} = (0) x scalar (@nn);

  $session->close ();
}

sub expand_nodelist
{
  my ($class, $nodelist) = @_;
  
  my @nodelist;
  
  while ($nodelist)
    {   
      if ($nodelist =~ s/^([\w-]+)(?:,|$)//o)
        {   
          push @nodelist, $1; 
        }   
      elsif ($nodelist =~ s/^([\w-]+)\[([^\[\]]*)\],?//o)
        {   
          my ($pref, $list) = ($1, $2);
          my @list = sort { $a <=> $b }
                     map 
                       {   
                         my ($x, $y);
                         if (m/^(\d+)-(\d+)$/o)
                           {   
                             ($x, $y) = ($1, $2);
                           }   
                         else
                           {   
                             ($x, $y) = ($_, $_);
                           }   
                         ($x .. $y) 
                       }   
                      split (m/,/o, $list);
          push @nodelist, map { "${pref}$_" } @list;
        }
    }

  return @nodelist;
}

sub compact_nodelist
{
  my ($class, @nodelist) = @_;

  my (@pref, @list);

  for my $node (@nodelist)
     {
       $node =~ m/^(\S+?)(\d+)$/o;
       push @pref, $1;
       push @list, $2;
     }
  
  my @uref = &uniq (@pref);

  my @nd;

  for my $pref (@uref)
    {
      my @i = grep { $pref[$_] eq $pref } (0 .. $#pref);
      my @l = @list[@i];
      push @nd, $class->compact_nodelist_pref ($pref, @l);
    }

  return join (',', @nd);
}
    

sub compact_nodelist_pref
{
  my $class = shift;

  my ($pref, @list) = @_;

  my (@L, $i, $j);
  
  my $sub = sub
    {
      if ($list[$i] + ($j-$i) != $list[$j])
        {   
          push @L, [$i, $j-1];
          $i = $j; 
        }   
    };  
  
  for ($j = 0; $j <= $#list; $j++)
    {   
      $i = $j unless ($j);
      $sub->();
    }   
  push @L, [$i, $j-1];
  
  my @N = map 
             {   
               my ($n1, $n2) = @list[$_->[0],$_->[1]];
               $n1 == $n2 ? $n1 : "$n1-$n2"
             } @L;

  if ((scalar (@N) == 1) && ($N[0] =~ m/^\d+$/o))
    {
      return "$pref$N[0]";
    }
  else
    {
      return $pref . '[' . join (',', @N) . ']';
    }

}

sub nodelist
{
  my ($class) = @_;

  my $nodelist = $ENV{SLURM_JOB_NODELIST};
  my $numnodes = $ENV{SLURM_JOB_NUM_NODES};

  my @nodelist;

  while ($nodelist)
    {
      $nodelist =~ s/^([\w-]+)//o;
      my $name = $1;
      if ($nodelist =~ s/^\[(.*?)\]//o)
        {
          my $range = $1;
          my @range = split (m/,/o, $range);
          for my $range (@range)
            {
              if ($range =~ m/^(\d+)-(\d+)$/o)
                {
                  my ($min, $max) = ($1, $2);
                  push @nodelist, map { "$name$_" } ($min .. $max);
                }
              else
                {
                  push @nodelist, "$name$range";
                }
            }
        }
      else
        {
          push @nodelist, $name;
        }
      $nodelist =~ s/^,//o;
    }

  die ("Node count mismatch\n")
    if (scalar (@nodelist) != $numnodes);

  return @nodelist;
}

sub eq
{
  use Storable;
  local $Storable::canonical = 1;
  my @s = map { &Storable::nfreeze (\$_) } @_;
  my $eq = 1;
  for (@s)
    {
      $eq &&= $s[0] eq $_;
    }
  return $eq;
}

sub stringify
{
  my ($h, $k) = @_;
  return defined $h->{$k} ? $h->{$k} : 'undef';
}

sub setup_env
{
  my ($class, %args) = @_;

  my ($opts, $mpmd) = @args{qw (opts mpmd)};

  return
    unless ($opts->{'fix-slurm-env'});

  my ($np, $nn) = ($opts->{np}, $opts->{nn});

  for (@$mpmd)
    {
      $np += $_->{np};
      $nn += $_->{nn};
    }

  my @var = qw (SLURM_NTASKS SLURM_NPROCS SLURM_TASKS_PER_NODE SLURM_NNODES SLURM_NODELIST 
                SLURM_JOB_NODELIST SLURM_JOB_NUM_NODES SLURM_CPUS_PER_TASK);

  my (%env1, %env2);
  for my $var (grep { exists $ENV{$_} } @var)
    {
      $env1{$var} = $env2{$var} = $ENV{$var};
    }

  $env1{SLURM_NTASKS} = $np;
  $env1{SLURM_NPROCS} = $np;
  $env1{SLURM_TASKS_PER_NODE} = join (',', "$opts->{nnp}(x$opts->{nn})", map { "$_->{nnp}(x$_->{nn})" } @$mpmd);

  if ($opts->{'use-session'} || $opts->{'fix-slurm-env-nodes'})
    {
      $env1{SLURM_NNODES} = $env1{SLURM_JOB_NUM_NODES} = $nn;
      my @nodelist = $class->find_free_nodes (nn => $nn, session => $opts->{'use-session'});
      $env1{SLURM_NODELIST} = $env1{SLURM_JOB_NODELIST} = $class->compact_nodelist (@nodelist);
    }
  delete $env1{SLURM_CPUS_PER_TASK};



  if (! &eq (\%env1, \%env2))
    {
      my ($var_length)  = sort { $b <=> $a } map { length ($_) } @var;
      my ($env1_length) = sort { $b <=> $a } map { length ($_) } ('undef', @env1{grep { exists $env1{$_} } @var});
      my ($env2_length) = sort { $b <=> $a } map { length ($_) } ('undef', @env2{grep { exists $env2{$_} } @var});

      $var_length++;
      $env1_length++;
      $env2_length++;

      if ($opts->{verbose})
        {
          printf($MPI::FMT1, 'Warning', 'Slurm environment was modified');
          for my $var (@var)
            {
              printf($MPI::FMT2, sprintf ("%-${var_length}s = %-${env2_length}s -> %-${env1_length}s\n", $var, 
                                          &stringify (\%env2, $var), &stringify (\%env1, $var)))
                if (! &eq ($env1{$var}, $env2{$var}));
            }
        }
     }


  for my $var (@var)
    {
      if (defined $env1{$var})
        {
          $ENV{$var} = $env1{$var};
        }
      else
        {
          delete $ENV{$var};
        }
    }


}

sub cleanup_env
{
  my ($class, %args) = @_;

  my ($opts) = @args{qw (opts)};

  if ($opts->{'use-session'})
    {
      $class->free_used_nodes ();
    }

}

1;
