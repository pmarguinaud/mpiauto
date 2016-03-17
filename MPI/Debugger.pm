package MPI::Debugger;

use strict;

sub new
{
  use File::Basename;

  my ($class, %args) = @_;
  my $path = $args{path};

  if (&basename ($path) eq 'ddt')
    {
      $class = 'MPI::Debugger::DDT';
    }
  elsif (&basename ($path) eq 'xgdb')
    {
      $class = 'MPI::Debugger::XGDB';
    }

  eval "use $class";
  $@ && die ($@);

  my $self = bless {%args}, $class;
  return $self;
}

1;
