package Scheduler;

use strict;

sub class
{
  my $class = shift;
  my %args = @_;
  if (exists $ENV{SLURM_JOBID})
    {
      $class = 'Scheduler::SLURM';
    }
  elsif (exists $ENV{LOADL_STEP_ID})
    {
      $class = 'Scheduler::LoadLeveller';
    }
  elsif (exists $ENV{PBS_JOBID})
    {
      $class = 'Scheduler::PBS';
    }
  else
    {
      $class = 'Scheduler::None';
    }
  eval "use $class";
  $@ && die ($@);
  return $class;
}

sub nodelist
{
  die ("No active scheduler\n");
}

sub setup_env
{
}

sub cleanup_env
{
}

1;
