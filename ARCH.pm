package ARCH;

use strict;

my $uname;

sub class
{

# SUPER-UX unix 18.1  SX-9A
# SUPER-UX unix 17.1  SX-8R
# Linux login0 2.6.32-220.23.1.bl6.Bull.28.8.x86_64 #1 SMP Thu Jul 5 17:34:18 CEST 2012 x86_64 x86_64 x86_64 GNU/Linux
# Linux yukisc2 2.6.16.60-0.69.1-smp #1 SMP Fri Sep 17 17:07:54 UTC 2010 x86_64 x86_64 x86_64 GNU/Linux
# AIX c2a182-hf0 1 7 00CCC1D64C00

  my ($class, %args) = @_;
  my ($bin) = @args{qw (bin)};

# my $C = do { my $fh = 'FileHandle'->new ("<$bin"); 
#              $fh or die ("Cannot open <$bin\n");
#              $fh->read (my $buf, 1); $buf };
  my %bclass = (chr (4) => 'ARCH::NECSX', chr (127) => 'ARCH::Linux', chr (1) => 'ARCH::AIX');

  my @uclass = (
                  [qr/^SUPER-UX.*SX-\d+\w*$/o, 'ARCH::NECSX'], 
                  [qr/^Linux/o,                'ARCH::Linux'],
                  [qr/^AIX/o,                  'ARCH::AIX'  ],
               );

  $uname ||= `uname -a`;
  chomp ($uname);

  for (@uclass)
    {
      my ($qr, $arch) = @$_; 
      if ($uname =~ $qr)
        {
          eval "use $arch";
          $@ && die ($@);
          return $arch;
        }
    }

  return undef;
}

sub readbin
{
  die ("`readbin' not available\n");
}

sub bind : method
{

}

sub bind_node 
{
  return ();
}

my %ldd_cache;

sub ldd
{
  use File::stat;

  my ($class, %args) = @_;

  my ($bin, $sym, $reload) = @args{qw (bin sym reload)};

  %ldd_cache = ()
    if ($reload);

  $sym ||= 0;
  $sym &&= 1;

  my $st = stat ($bin);

  die ("Cannot access `$bin'\n")
    unless ($st);

  my $stamp = $st->mtime () . '.' . $st->size ();

  my @ldd;

  if ($ldd_cache{$bin} && ($ldd_cache{$bin}{stamp} eq $stamp))
    {
      @ldd = @{ $ldd_cache{$bin}{ldd} };
    }
  else
    {
      @ldd = $class->do_ldd ($bin);
      $ldd_cache{$bin} = {ldd => [@ldd], stamp => $stamp};
    }

  if ($sym)
    {
      for (@ldd)
        {
          s/\.so\.\d+$/.so/o;
        }
    }
  
  return {@ldd};
}

sub setup_umpi
{

}

sub preload
{
  die;
}

sub which
{
  my ($arch, $bin) = @_;

  my @path = split (m/:/o, $ENV{PATH});

  for my $path (@path)
    {
      if (-f "$path/$bin")
        {
          return "$path/$bin";
        }
    }

  return undef;

}

1;
