package MPI::Debugger::DDT;

use strict;
use base qw (MPI::Debugger);

sub run
{
  use File::Copy;

  my ($self, %args) = @_;
  
  my ($mpikind, $mpirun, $np, $mpiargs, $bin, $args, $opts) = 
    @args{qw (mpikind mpirun np mpiargs bin args opts)}; 

  $np = $np->{val};

  my $arch = $self->{arch};

  my $path = $self->{path};

  my @path = split (m,/,o, $path);
  pop (@path) for (1 .. 2);
  my $version = $path[-1];


# Lookup configuration file

  my @CONF;
  for (my $c = "MPI::$mpikind"; $c; )
    {
      (my $d = $c) =~ s/^MPI(?:::)?//o;

      last unless ($d);

      my @conf = ("$ENV{HOME}/.mpiautorc/ddt/config.$d.ddt", "$MPI::AUTO::BASEDIR/ddt/config.$d.ddt");

      for my $conf (@conf)
        {
          if (&copy ($conf, 'config.ddt'))
            {
              if ($opts->{verbose})
                {
                  printf($MPI::FMT1, 'DDT config', $conf);
                }
              goto FOUND;
            }
        }

      push @CONF, @conf;

      {
        no strict 'refs';
        ($c) = @{"$c\::ISA"};
      }
    }

  die ("Cannot find any valid configuration file; tried : @CONF\n");

FOUND:

  my @config = do { my $fh = 'FileHandle'->new ('<config.ddt'); <$fh> };

  my $ARGUMENTS        = join (' ', @$args);
  my $MPI_ARGUMENTS    = join (' ', @$mpiargs);
  my $APPLICATION_NAME = $bin;
  my $MPIRUN           = $mpirun;

  for (@config)
    {
      s/__MPIRUN__/$MPIRUN/g;
      s/__APPLICATION_NAME__/$APPLICATION_NAME/g;
      s/__ARGUMENTS__/$ARGUMENTS/g;
      s/__MPI_ARGUMENTS__/$MPI_ARGUMENTS/g;
    }
  'FileHandle'->new ('>config.ddt')->print (join ('', @config));

  my $gmkpack;
  if ($opts->{'debug-try-gmkpack'})
    {
      $gmkpack = $arch->readbin (section => '.gmkpack', perl => 1, bin => $bin);

      if ($gmkpack)
        {
          if ($opts->{verbose})
            {
              printf($MPI::FMT1, 'Pack', $gmkpack->{pack});
            }
          $gmkpack->{bin} ||= '';
          my @session = ("$gmkpack->{pack}/.ddt/session.$gmkpack->{bin}.ddt", "$gmkpack->{pack}/.ddt/session.ddt");
          for my $session (@session)
            {
              if (-f $session)
                {
                  &copy ($session, 'session.ddt');
                  if ($opts->{verbose})
                    {
                      printf($MPI::FMT1, 'DDT session', $session);
                    }
                  last;
                }
            }
        }
      elsif (exists $ENV{MPIAUTODDTPACK})
        {
          my $pack = $ENV{MPIAUTODDTPACK};
          if ($opts->{verbose})
            {
              printf($MPI::FMT1, 'Pack', $pack);
            }
          my $session = "$pack/.ddt/session.ddt";
          if (-f $session)
            {
              &copy ($session, 'session.ddt');
              if ($opts->{verbose})
                {
                  printf($MPI::FMT1, 'DDT session', $session);
                }
            }
        }
    }

  my @session = -f 'session.ddt' ? (-ddtsession => 'session.ddt') : ();

  my @np      = $np       ? (-np => $np)                        : ();

  my $config_opt;

  if ($version ge '4')
    {
      $config_opt = '-systemconfig';
    }
  else
    {
      $config_opt = '-config';
    }
 
  my @cmd = ($self->{path}, '-noqueue', $config_opt, 'config.ddt', 
             ($opts->{'debugger-break'} ? ('-break-at' => $opts->{'debugger-break'}) : ()),
             @session, @np, $bin, @$args);

  if ($opts->{verbose})
    {
      printf($MPI::FMT1, 'DDT command', join (' ', @cmd));
    }

  my $c = 1;
 
  unless ($opts->{dryrun})
    {
      $c = ! system (@cmd);
    }

  return $c;
}

1;
