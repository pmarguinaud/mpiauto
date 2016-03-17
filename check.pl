#!/usr/bin/perl -w

use strict;
use File::Find;

&find ({wanted => sub { if (m/\.pm$/o) { print "$File::Find::name\n"; (my $module = $File::Find::name) =~ s,/,::,go; 
                        $module =~ s/\.pm$//o; $module =~ s/^\.:://o; eval "use $module"; $@ && print $@; } 
                      }, no_chdir => 1}, '.');

system ('perl', '-c', 'mpiauto');
system ('perl', '-c', 'mpiauto.do_run');
system ('perl', '-c', 'mpiautowrap');
system ('perl', '-c', 'x11-proxy');
system ('perl', '-c', 'xgdb');
