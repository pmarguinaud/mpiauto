package Getopt::Configurable;

use Data::Dumper;
use Getopt::Long qw ();
use FileHandle;
use constant 
  {  
    TYPE =>   0, NAME =>   1, DESC =>   2, REQD =>   3, DEFL =>   4, OPDF =>   5, 
  };
use constant 
  {  
    BOOL => 101, ARGS => 102, GRPS => 103,
  };
use base qw (Exporter);
our @EXPORT = qw (BOOL ARGS GRPS);
use strict;

sub new
{
  my ($class, %args) = @_;
  my $OPTS = $args{OPTS};

  my @OPTS_S = grep { $_->[TYPE] == ARGS } @$OPTS;
  my @OPTS_F = grep { $_->[TYPE] == BOOL } @$OPTS;

  return bless {OPTS_S => \@OPTS_S, OPTS_F => \@OPTS_F, %args}, $class;
}

sub clone
{
  use Storable qw ();
  return map { ref ($_) ? &Storable::dclone ($_) : $_ } @_;
}

sub help
{
  use Tools::Frame;
  my $self = shift;

  my $width = $ENV{COLUMNS} || 80;

  die (
    &frame (" Usage   : $self->{APP}{name} [option1 option2 ...] $self->{APPH}", $width, 0) . "\n\n"
  . join ('', map { 
                    my $str = '';
                    my ($name, $desc) = ($_->[NAME], $_->[DESC]); 
                    $desc =~ s/\s*\n\s*/ /go;
                    if ($_->[TYPE] == GRPS)
                      {
                        $str = &frame ($desc, $width) . "\n";
                      }
                    else
                      {
                        my $type = ''; my $ref = ref ($_->[DEFL]);
                        if ($_->[TYPE] == BOOL)
                          {
                            $type = 'FLAG';
                          }
                        elsif (! $ref)
                          {
                            $type = 'STR';
                          }
                        elsif ($ref eq 'ARRAY')
                          {
                            $type = 'LIST';
                          }
                        elsif ($ref eq 'HASH')
                          {
                            $type = 'HASH';
                          }
                        $name = sprintf ("    --%-20s : %-4s : ", $name, $type);
                        my @desc;
                        while (length ($desc))
                          {
                            push @desc, substr ($desc, 0, $width-length($name), '');
                          }
                        $str = join ("\n", $name . shift (@desc), (map { (' ' x length($name)) . $_ } @desc), '', '');
                      }
                    $str
                  } (@{ $self->{OPTS} }))
  . "\n"
  );  
}

sub get_op
{
  my $val = shift;
  my $op = '=';

  if (defined ($val))
    {
      $val =~ s/^(\+=|=\+|-=|=)\s*//o;
      $op = $1 ? $1 : $op;
    }

  return ($op, $val);
}

sub is_op
{
  my $val = shift;
  return $val =~ m/^(\+=|=\+|-=|=)$/o;
}

sub mix_opts
{
  my ($name, $defl, $op, $val) = @_;

  my $ref = ref ($defl) || '';

  my $scv = sub
    {
      my ($name, $op, $defl, $val) = @_;

      (my $o, $val) = &get_op ($val);
      $op = $op || $o;

      unless (defined ($defl)) 
        {
          $defl = '';
        }
         if ($op eq '+=') { $defl = $defl ? "$defl $val" : $val }
      elsif ($op eq '=+') { $defl = $defl ? "$val $defl" : $val }
      elsif ($op eq '-=') { $defl =~ s/\s*$val\s*/ /g;          }
      elsif ($op eq '=')  { $defl = $val                        }
      $_[2] = $defl;
    };

  if ($ref eq 'ARRAY')
    {
         if ($op eq '+=') { @$defl = (@$defl, @$val)            }
      elsif ($op eq '=+') { @$defl = (@$val, @$defl)            }
      elsif ($op eq '-=') { my %val = map { ($_, 1) } @$val; 
                            @$defl = grep { ! $val{$_} } @$defl }
      elsif ($op eq '=')  { @$defl = @$val                      }
    }
  elsif ($ref eq 'HASH')
    {
         if ($op eq '+=') { 
                            for my $k (keys (%$val))
                              { 
                                $scv->($name, undef, $defl->{$k}, $val->{$k});
                              }
                          }
      elsif ($op eq '=+') { %$defl = (%$val, %$defl)            }
      elsif ($op eq '-=') { delete @{$defl}{keys (%$val)}       }
      elsif ($op eq '=')  { 
                            %$defl = ();
                            for my $k (keys (%$val))
                              { 
                                $scv->($name, undef, $defl->{$k}, $val->{$k});
                              }
                          }
    }
  elsif ($ref eq 'CODE')
    {
      $val->($name, $op, $defl, $val);
    }
  else
    {
      $scv->($name, $op, $defl, $val);
    }

  return $defl;
}


sub conf
{
  use File::Spec;

  my ($self, %args) = @_;

  my ($class, $version, $config, $site) = @args{qw (class version config site)};

  my @site = ('');
  $site && push (@site, ".$site");

  my @CONF = ();

  my $lc = sub 
    { 
      my $f = shift;

      $f = 'File::Spec'->rel2abs ($f);

      my $c;
      if ($f && (-f $f))
        {
          $c = do ($f);
          $@ && die ($@); 
          push @CONF, $f;
        }
      else
        {
          $c = {};
        }

      $c 
    };

  my $prefix = $self->{APP}{prefix};
  my @isa;
  for (my $c = $class; $c; )
    {
      (my $d = $c) =~ s/^$prefix(?:::)?//;
      unshift @isa, $d ? ".$d" : '';
      {
        no strict 'refs';
        ($c) = @{"$c\::ISA"};
      }
    }

  my @version = split (m/\./o, $version);
  for my $i (1 .. $#version)
     {
       $version[$i] = "$version[$i-1].$version[$i]";
     }

  my $name = $self->{APP}{name};

  my @conf = map 
               { 
                 my $isa = $_;
                 map 
                   {
                     my $site = $_;
                     (
                       $lc->("$MPI::AUTO::BASEDIR/$name$site$isa.conf"), 
                       (map { $lc->("$MPI::AUTO::BASEDIR/$name$site$isa.$_.conf") } @version), 
                       $lc->("$ENV{HOME}/.${name}rc/${name}$site$isa.conf"),
                       (map { $lc->("$ENV{HOME}/.${name}rc/${name}$site$isa.$_.conf") } @version), 
                     ) 
                   } @site
               } @isa;

  if ($config)
    {
      my $c = $lc->($config);
      if ((! %$c) && ($config !~ m,^/,o))
        {
          $c = $lc->("$ENV{HOME}/.${name}rc/$config");
        }
      push @conf, $c;
    }

  for my $opts (@{ $args{opts} })
    {
      for my $opt (@$opts)
        {
          my ($name, $defl, $op_defl) = @{$opt}[NAME, DEFL, OPDF];


          if ($name eq 'site')
            {
              $defl = $site;
            }

          for my $conf (@conf)
            {
              if (exists $conf->{opts}->{$name})
                {
                  my ($op, $val) = @{ $conf->{opts}{$name} };
                  $defl    = &mix_opts ($name, $defl, $op, $val);
                  $op_defl = $op;
                }
            }

          $opt->[DEFL] = $defl;
          $opt->[OPDF] = $op_defl;

        }
    }

  

  $self->{conf} = \@CONF;
}

sub grokconfig
{
  my $self = shift;

  my $name = $self->{APP}{name};
  my $var = uc ($name) . 'CONFIG';

  my $config_glob = "$MPI::AUTO::BASEDIR/$name.conf";

  my $config_user = $ENV{$var};

  my $site = '';

  if (-f $config_glob)
    {
      my $conf = do $config_glob;
      $site ||= $conf->{site};
    }

# Find config option
  for (my $argi = 0; $argi < @{ $self->{ARGV} }; $argi++)
    {
      if ($self->{ARGV}[$argi] eq '--config')
        {
          $config_user = $self->{ARGV}[$argi+1];
        }
      elsif ($self->{ARGV}[$argi] eq '--site')
        {
          $site = $self->{ARGV}[$argi+1];
        }
      elsif ($self->{ARGV}[$argi] eq '--')
        {
          last;
        }
    }

  return ($config_user, $site);
}

sub parse
{
  my $self = shift;

  @{ $self->{opts_s} } = &clone (@{ $self->{OPTS_S} });
  @{ $self->{opts_f} } = &clone (@{ $self->{OPTS_F} });

  my ($config, $site) = $self->grokconfig ();

  $self->conf (class  => $self->{APP}{class}, version => $self->{APP}{version}, 
               opts => [\@{ $self->{opts_s} }, \@{ $self->{opts_f} }], 
               site => $site, config => $config);

  my %opts = (map { ($_->[NAME], $_->[DEFL]) } (@{ $self->{opts_s} }, @{ $self->{opts_f} }));

# Parse options 

  my $ref2ext = sub { my $ref = ref ($_[0]); my %ext = (ARRAY => '@', HASH => '%'); $ref ? $ext{$ref} : '' };


  local @ARGV = @{ $self->{ARGV} };
  &Getopt::Long::GetOptions (
        map ({ my $N = $_->[NAME]; ($N . '=s' . $ref2ext->($_->[DEFL]), \$opts{$N}) } @{ $self->{opts_s} }),
        map ({ my $N = $_->[NAME]; ($N . '!',                           \$opts{$N}) } @{ $self->{opts_f} }),
  ) or $self->help ();
  $self->{argv} = [@ARGV];

  for my $opt (@{ $self->{opts_s} }) 
    {
      my ($name, $defl, $op_defl) = @{$opt}[NAME, DEFL, OPDF];
      my $op;
      my $ref = ref ($opts{$name});
      if ($ref eq 'HASH')
        {
          $op = delete $opts{$name}{op} || $op_defl || '+=';
        }
      elsif ($ref eq 'ARRAY')
        {
          if (@{ $opts{$name} } && (&is_op ($opts{$name}[0])))
            {
              $op = shift (@{ $opts{$name} });
            }
          else
            {
              $op = $op_defl || '=';
            }
        }
      else
        {
          ($op, $opts{$name}) = &get_op ($opts{$name});
        }

      $opts{$name} = &mix_opts ($name, $defl, $op, $opts{$name});

    }
  
  $opts{help} && $self->help ();
    
  $self->{opts} = \%opts;

  return $self->{opts};
}

sub argv
{
  my $self = shift;
  return @{ $self->{argv} };
}

sub verbose
{
  use Tools::Frame;
  my $self = shift;

  my ($FMT1, $FMT2, $FMT3) = @{$self}{qw (FMT1 FMT2 FMT3)};

  printf($FMT1, 'Config', '');
  print map { sprintf ($FMT2, "- $_") } @{ $self->{conf} };
  printf($FMT1, 'Options',  '');
  for (@{ $self->{OPTS} })
    {
      if ($_->[TYPE] != GRPS)
        {
          my $opt = $_->[NAME];
          my $val = $self->{opts}{$opt};
          local 
            $Data::Dumper::Terse    = 1, 
            $Data::Dumper::Indent   = 0, 
            $Data::Dumper::Sortkeys = 1
          ;
          my $ref = ref ($val) || '';
             if ($ref eq 'ARRAY') { $val = &Dumper ($val)     }
          elsif ($ref eq 'HASH')  { $val = &Dumper ($val)     }
          elsif ($_->[TYPE] == BOOL)
                                  { $val = $val ? 'true' : 'false' }
          elsif (defined ($val))  { $val = "$val";            }
          else                    { $val = "undef";           }
          printf($FMT3, "--$opt", $val);
        }
    }
}




1;

