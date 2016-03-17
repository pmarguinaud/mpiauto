package Scheduler::None;

use strict;
use base qw (Scheduler);

sub jobid
{
  return getppid ();
}


1;
