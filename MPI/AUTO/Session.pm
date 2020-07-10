package MPI::AUTO::Session;

use File::Path;
use FileHandle;
use Fcntl qw (:flock);
use Data::Dumper;
use strict;

sub empty
{
  my $class = shift;
  return bless {data => {nodes => {}}}, $class;
}

sub open : method
{
  my $class = shift;
  my %args = @_;

  my $tmp = "$ENV{HOME}/tmp";
  &mkpath ($tmp)
    unless (-d $tmp);

  my $file = "$tmp/mpiauto.$args{jobid}";
  my $lock = 'MPI::AUTO::Session::Lock'->new (name => "$file.lock");
  $lock->lock_ex ();

  my $data = do ($file) || {};

  my $self = bless {data => $data, lock => $lock, file => $file}, $class;

  return $self;
}

sub close : method
{
  my $self = shift;
  return unless ($self->{file});

  local $Data::Dumper::Terse  = 1;
  local $Data::Dumper::Indent = 1;
  'FileHandle'->new (">$self->{file}")->print (&Dumper ($self->{data}));

  $self->{lock}->lock_un ();

}

package MPI::AUTO::Session::Lock;

use strict;
use FileHandle;
use Fcntl qw (LOCK_EX LOCK_UN);

sub new
{
  my $class = shift;
  return bless {@_}, $class;
}

sub lock_ex : method
{
  my $self = shift;
  1 while (! mkdir ($self->{name}));
  $self->{lock} = 1;
}

sub lock_un : method
{
  my $self = shift;
  if ($self->{lock})
    {
      rmdir ($self->{name});
      $self->{lock} = 0;
    }
}

sub DESTROY
{
  my $self = shift;
  $self->lock_un ();
}

sub xx_lock_ex : method
{
  my $self = shift;
  $self->{fh} = 'FileHandle'->new ("+>$self->{name}");
  flock ($self->{fh}, LOCK_EX)
    or die ("Cannot flock $self->{name}: $!");
}

sub xx_lock_un : method
{
  my $self = shift;
  flock ($self->{fh}, LOCK_UN);
}

1;
