package X11::Proxy;

use strict;
use FileHandle;
use Sys::Hostname;
use Data::Dumper;
use POSIX qw (:sys_wait_h SIGKILL);
use Cwd;
use File::Path;
use File::Copy;
use Getopt::Long qw ();

sub slurp
{
  my $file = shift;
  do { local $/ = undef; my $fh = 'FileHandle'->new ("<$file"); <$fh> };
}

sub new
{
  my ($class, %args) = @_;
  for my $x11k (grep { m/^x11-/o } keys (%args)) 
    {
      (my $k = $x11k) =~ s/^x11-(?:proxy-)?//o;
      $args{$k} ||= delete $args{$x11k};
    }
  unless ($args{display})
    {
      die ("`$class' requires display argument\n");
    }
  my $display = $args{display};
  my ($user) = ($display =~ m/^(\w+)\@/o);
  $display =~ s/^\w+\@//o;
  return bless {time => 0, %args, display => $display, user => $user}, $class;
}

sub prefix
{
  my $DISPLAY = shift;
  my $pwd = &cwd ();
  my $prefix = "$pwd/.x11-proxy/$DISPLAY";
  &mkpath ($prefix);
  return $prefix;
}

sub start
{
  my ($self) = @_;
  my $DISPLAY = $self->{display};
  
  my ($rhost, $sn) = ($DISPLAY =~ m/^(\S+):(\S+)$/o);

  unless (defined ($rhost) && defined ($sn))
    {
      ($rhost, $sn) = ($DISPLAY, '0');
    }
  if ($self->{user}) 
    {
      $rhost = "$self->{user}\@$rhost";
    }

  my $lhost = &hostname ();
  my $luser = getpwuid ($<);

  $lhost = "$luser\@$lhost";
  
  my @proxyb = @{ $self->{'b-proxy'} };
  my @proxyf = @{ $self->{'f-proxy'} };
  
  
  my $prefix = &prefix ($DISPLAY);

  my $f_ssh = "$prefix/ssh.sh";
  my $f_env = "$prefix/env.sh";
  my $f_pid = "$prefix/pid.sh";

  if (-f $f_pid)
    {
      die ("Found `$f_pid'; already running ??\n");
    }
  
  my $fh_ssh = 'FileHandle'->new (">$f_ssh");

  $fh_ssh->print (<< "EOF");
#!/bin/bash
echo "export DISPLAY=\$DISPLAY" > $f_env
echo "\$\$"                     > $f_pid
EOF

   if ($self->{time} > 0)
     {
       $fh_ssh->print ("sleep $self->{time}\n");
     }
   else
     {
       $fh_ssh->print (<< 'EOF');
while [ true ]
do
  sleep 3600
done
EOF
     }

  $fh_ssh->close ();

    
  chmod (0755, $f_ssh);
  
  my @sshb = map { ('ssh', '-x', $_) } (@proxyb, $rhost);
  my @sshf = map { ('ssh', '-X', $_) } (@proxyf, $lhost);
  
  my @cmd = 
  (
    @sshb, "DISPLAY=:$sn @sshf \"$f_ssh\""
  );
  
  (my $pid = fork ()) or exec (@cmd);
  
  while (! -f $f_env)
    {
      my $p = waitpid ($pid, &WNOHANG);
      if ($p < 0)
        {
          die ("Failed to create a new process");
        }
      elsif ($p > 0)
        {
          my $c = $?;
          die ("Command `@cmd' exited with status $c");
        }
      sleep (1);
    }

  if ($self->{env})
    {
      if ($self->{env} eq '-')
        {
          my $env = &slurp ($f_env);
          print $env;
        } 
       else
        {
          &copy ($f_env, $self->{env})
            or die ("Cannot copy `$f_env' to `$self->{env}'");
        }
    }

  my $env = &slurp ($f_env);
  my ($display) = ($env =~ m/DISPLAY=(\S+)/o);

  return $display;
}

sub stop
{
  my ($self) = @_;
  my $DISPLAY = $self->{display};
  
  my $prefix = &prefix ($DISPLAY);

  my $f_pid = "$prefix/pid.sh";

  unless (-f $f_pid)
    {
      die ("`$f_pid' was not found; not running ??\n");
    }

  my $pid = do { local $/ = undef; my $fh = 'FileHandle'->new ("<$f_pid"); <$fh> };
  chomp ($pid);

  kill (-&SIGKILL, $pid);

  &rmtree ($prefix);
}

sub parse_opts
{
  my $class = shift;

  use Getopt::Long qw ();
  
  use constant
    {
      NAME => 0, DESC => 1,
      REQD => 2, DEFL => 3,
    };
  
  my @opts_s = (
    [ 'display',               'Display',                                                    1, undef            ],
    [ 'time',                  'Time the proxy should be kept alive',                        0, 3600             ],
    [ 'env',                   'Dump X11 environment to file',                               0, undef            ],
    [ 'f-proxy',               'Forward proxy list',                                         0,  []              ],
    [ 'b-proxy',               'Backward proxy list',                                        0,  []              ],
  );
  
  my @opts_f = (
    [ 'start',                 'Start proxy',                                                0, undef            ],
    [ 'stop',                  'Stop proxy',                                                 0, undef            ],
    [ 'help',                  'Show help message',                                          0, undef            ],
  );
  
  my $help = sub 
  {
    my $width = $ENV{COLUMNS} || 80;
    die (
      " Options :\n"
    . join ('', map { 
                      my ($name, $desc) = ($_->[NAME], $_->[DESC]); 
                      $desc =~ s/\s*\n\s*/ /go;
                      $name = sprintf ("    --%-20s : ", $name); 
                      my @desc;
                      while (length ($desc))
                        {       
                          push @desc, substr ($desc, 0, $width-length($name), '');
                        }       
                      join ("\n", $name . shift (@desc), (map { (' ' x length($name)) . $_ } @desc), '', '') 
                    } (@opts_s, @opts_f))
    );  
  };
  
  my %opts = (map { ($_->[NAME], $_->[DEFL]) } (@opts_s, @opts_f));
  
  my $ref2ext = sub { my $ref = ref ($_[NAME]); my %ext = (ARRAY => '@', HASH => '%'); $ref ? $ext{$ref} : '' }; 
  
  my @argv = @{ $_[0] };

  {
    local @ARGV = @argv;

    &Getopt::Long::GetOptions (
          map ({ my $N = $_->[NAME]; ($N . '=s' . $ref2ext->($_->[3]), \$opts{$N}) } @opts_s),
          map ({ my $N = $_->[NAME]; ($N . '!',                        \$opts{$N}) } @opts_f),
    ) or &help ();

    @argv = @ARGV;
  }
  
  $opts{help} && $help->();

  @{ $_[0] } = @argv;

  return \%opts;
}

1;
