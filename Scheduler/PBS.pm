package Scheduler::PBS;

use strict;
use base qw (Scheduler);

sub jobid
{
  return $ENV{PBS_JOBID};
}

1;
