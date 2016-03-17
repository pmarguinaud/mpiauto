package Scheduler::LoadLeveller;

use strict;
use base qw (Scheduler);

sub jobid
{
  return $ENV{LOADL_STEP_ID};
}

1;
