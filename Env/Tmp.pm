package Env::Tmp;

use strict;

sub new 
{
  my $class = shift;
  return bless {env => {%ENV}}, $class;
}

sub restore 
{
  my ($self) = @_;
  my %env_n = %ENV;
  my %env_b = %{$self->{env}};
  my %keys = ();
  $keys{$_} = 1 for ((keys %env_n), (keys %env_b));
  for (keys %keys) 
    {
      ( exists $env_n{$_} ) && 
      ( exists $env_b{$_} ) &&
      ( $env_n{$_} ne $env_b{$_} ) && do {
         $ENV{$_} = $env_b{$_};
      };

      ( exists $env_n{$_} ) &&
      ( ! exists $env_b{$_} ) && do {
         delete $ENV{$_};
      };

      ( ! exists $env_n{$_} ) &&
      ( exists $env_b{$_} ) && do {
         $ENV{$_} = $env_b{$_};
      };
    }
}

sub DESTROY
{
  my $self = shift;
  return $self->restore ();
}

1;
