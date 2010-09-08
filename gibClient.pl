#!/usr/bin/perl

#use File::stat;
use File::Find;
use Digest::SHA1 qw/sha1_hex/;
use Compress::Zlib;
use IO::Socket;
use IO::Select;
use Sys::Hostname;
use strict;
use warnings;
use bytes;

my @dirStack;
my %dirs;
my %sha1s;

my $debug = 1;

sub wanted
{
  print STDOUT "$_\n" if $debug >= 2;
  my ($s, $dir);
  $dir = $dirStack[0];
  return if (!defined $dir);
  $s = \$dirs{$dir};
  my @st = lstat $_;
  $$s .=  $st[0]."\t";
  $$s .=  $st[1]."\t";
  $$s .=  sprintf "%06o\t", $st[2];
  $$s .=  $st[3]."\t";
  $$s .=  $st[4]."\t";
  $$s .=  $st[5]."\t";
  $$s .=  $st[6]."\t";
  $$s .=  $st[7]."\t";
  $$s .=  $st[8]."\t";
  $$s .=  $st[9]."\t";
  $$s .=  $st[10]."\t";
  $$s .=  $st[11]."\t";
  $$s .=  $st[12]."\t";
  $$s .=  $_."\t";
  if (-r $_)
  {
    if (-l $_)
    {
      $$s .= "->".readlink;
    }
    elsif (-f $_)
    {
      open my $inFH, "<$_";
      binmode $inFH;
      my $sha1 = Digest::SHA1->new;
      $sha1->add(sprintf "blob %d\0", $st[7]);
      while (!eof $inFH)
      {
        my $data;
        read $inFH, $data, 1024;
        $sha1->add($data);
      }
      my $shahex = $sha1->hexdigest;
      $sha1s{$shahex} = "$dir/$_";
      $$s .= $shahex;
      close $inFH;
    } elsif (-d $_) {
      $$s .= ">$dir/$_<";
    } else {
      $$s .= "<->";
    }
  } else {
    $$s .= "<->";
  }
  $$s .= "\n";
  #$dirStack[0] = $s;
}

sub preprocess
{
  print STDOUT ">$File::Find::dir<\n" if $debug >= 1;
  unshift @dirStack, $File::Find::dir;
  $dirs{$File::Find::dir} = "";
  return @_;
}

my $numRedos = 0;

sub postprocess
{
  print STDOUT "<$File::Find::dir>\n" if $debug >= 1;
  print ">$File::Find::dir<\n";
  print $dirs{$File::Find::dir};
  print "<$File::Find::dir>\n";
  my $redo = &sendToServer;
  shift @dirStack;
  if ($redo == 1)
  {
    warn "Too many redo's" if $numRedos > 3;
    return if $numRedos > 3;
    $numRedos++;
    find({ bydepth => 1, wanted => \&wanted, preprocess => \&preprocess, postprocess => \&postprocess} , $File::Find::dir);
    $numRedos--;
  }
}

my $sock = IO::Socket::INET->new('PeerHost' => 'localhost', 'PeerPort' => 6182) || die "Cannot connect to Gib server";
select $sock;
print hostname()."\n";
#for my $s (qw{/lib})
for my $s (qw{/dev /bin /boot /etc /lib /opt /home /prod})
{
  next if (! -d $s);
  find({ bydepth => 1, wanted => \&wanted, preprocess => \&preprocess, postprocess => \&postprocess} , $s);
  my @st = lstat $s;
  my $root = "";
  $root .=  $st[0]."\t";
  $root .=  $st[1]."\t";
  $root .=  sprintf "%06o\t", $st[2];
  $root .=  $st[3]."\t";
  $root .=  $st[4]."\t";
  $root .=  $st[5]."\t";
  $root .=  $st[6]."\t";
  $root .=  $st[7]."\t";
  $root .=  $st[8]."\t";
  $root .=  $st[9]."\t";
  $root .=  $st[10]."\t";
  $root .=  $st[11]."\t";
  $root .=  $st[12]."\t";
  $root .=  "$s\t";
  $root .=  ">$s<\n";
  print $root;

}
print "\cD\n";
$sock->flush;
select STDOUT;

sub sendToServer
{
  #my $sock = shift;
  my @serverWant;
  while (<$sock>)
  {
    last if (/\cD/);
    /^\[([0-9a-f]{40})\]$/ or die "not a valid entry: $_";
    push @serverWant, $1;
  }
  my $select = IO::Select->new();
  $select->add($sock);
  select $sock;
  binmode $sock;
  foreach my $sha1 (@serverWant)
  {
    my $d = deflateInit("-Level" => Z_BEST_COMPRESSION);
    open(my $inFH, "<$sha1s{$sha1}") || die $!;
    print STDOUT "[$sha1] $sha1s{$sha1}\n";
    print "[$sha1]\n";
    binmode $inFH;
    while (!eof $inFH)
    {
      my $data;
      read $inFH, $data, 1024;
      my ($out, $status) = $d->deflate($data);
      $status == Z_OK or die "deflation failed\n" ;
      print $out;
    }
    my ($out, $status) = $d->flush();
    $status == Z_OK or die "deflation failed\n" ; 
    print $out;
    $sock->flush();
  #  my ($ready) = $select->can_read(0);
  #  while (defined $ready)
  #  {
  #   # select STDOUT;
  #    $_ = <$sock>;
  #    last if (!defined $_);
  #    print STDOUT $_;
  #  #  select $sock;
  #    ($ready) = $select->can_read(0);
  #  }
  }
  #print STDOUT "[----------------------------------------]\n".("0"x1024)."\n";
  #print "[----------------------------------------]\n".("0"x1024)."\n";
  print "\cD\n";
  $sock->flush;
  select STDOUT;
  my $redo = 0;
  while (<$sock>)
  {
    last if (/\cD/);
    print $_;
    if ($_ =~ /Redo$/)
    {
      $redo = 1;
    }
  }
  select $sock;
  return $redo;
}
