#!/usr/bin/perl

require Net::Daemon;
package GibDaemon;
use strict;
use warnings;
use Digest::SHA1 qw/sha1_hex/;
use Compress::Zlib;
use POSIX qw/strftime/;

@GibDaemon::ISA = qw/Net::Daemon/;

sub saveDir
{
  my $dirSave = shift;
  #print $dirSave;
  my $sha1 = Digest::SHA1->new;
  $dirSave = sprintf("backuptree %d\0", length($dirSave)).$dirSave;
  $sha1->add($dirSave);
  my $shahex = $sha1->hexdigest;
  my ($dir, $file) = $shahex =~ /^(..)(.*)$/;
  if (!-e "$ENV{GIB_DIR}/objects/$dir/$file")
  {
    mkdir "$ENV{GIB_DIR}/objects/$dir" if (!-d "$ENV{GIB_DIR}/objects/$dir");
    open(my $ouFH, ">$ENV{GIB_DIR}/objects/$dir/$file")|| die $!;
    print $ouFH compress($dirSave);
    close $ouFH;
  }
  #print $shahex."\n";
  return $shahex;
}

sub dieAndDel
{
  my $error = shift;
  my $sha1 = shift;
  my ($dir, $file) = $sha1 =~ /^(..)(.*)$/;
  unlink "$ENV{GIB_DIR}/objects/$dir/$file";
  die $error;
}

sub redoAndDel
{
  my $error = shift;
  my $sha1 = shift;
  my $success = shift;
  my ($dir, $file) = $sha1 =~ /^(..)(.*)$/;
  unlink "$ENV{GIB_DIR}/objects/$dir/$file";
  warn $error;
  $$success = "Redo";
}

sub saveFile
{
  my ($sha1, $size, $inFH, $firstData, $success) = @_;
  my ($dir, $file) = $sha1 =~ /^(..)(.*)$/;
  my $d = deflateInit("-Level" => Z_BEST_COMPRESSION);
  my $i = inflateInit() || die "Cannot create inflator";
  mkdir "$ENV{GIB_DIR}/objects/$dir" if (!-d "$ENV{GIB_DIR}/objects/$dir");
  open(my $ouFH, ">$ENV{GIB_DIR}/objects/$dir/$file") or die $!;
  binmode $inFH;
  binmode $ouFH;
  $$success = "Success";
#  my $out = ($data);
  my $result;
  my $sha1digest = Digest::SHA1->new;
  my $data = $d->deflate(sprintf "blob %d\0", $size);
  $sha1digest->add(sprintf "blob %d\0", $size);
  print $ouFH $data;
  $data = $firstData;
#  my $rb;
#  $inFH->blocking(0);
  if ($firstData eq "")
  {
  $data .= <$inFH>;
#  while ($rb == 0)
#  {
#    $rb = read($inFH, $data, 1024);
#    last if (defined $rb);
#    redo if ($! =~ /Resource temporarily unavailable/);
#    die $!;
#  }
  }
#  print STDOUT "->$rb $! $?\n";
  my $istatus;
  my $outData;
  #while (!eof $inFH)
  while (1)
  {
    #my $data;
    ($outData, $istatus) = $i->inflate(\$data);
    $result = $data if ($istatus == Z_STREAM_END);
    $sha1digest->add($outData);
    my ($out, $dstatus) = $d->deflate($outData);
    $dstatus == Z_OK or &dieAndDel("deflation failed", $sha1) ;
    print $ouFH $out;
    last if ($istatus == Z_STREAM_END);
    &dieAndDel("Bad inflation: $istatus", $sha1) if ($istatus != Z_OK);
    $data = <$inFH>;
    #last if (eof $inFH);
    #last if read($inFH, $data, 1024) == 0;
#    $rb = 0;
#    while ($rb == 0)
#    {
#    $rb = read($inFH, $data, 1024);
#    last if (defined $rb);
#    redo if ($! =~ /Resource temporarily unavailable/);
#    die $!;
#    }
#  print STDOUT "->$rb $! $?\n";
  }
  my $out = $d->flush();
  print $ouFH $out;
  close $ouFH;
  #&dieAndDel("Size mismatch: ".($i->total_out())." != $size", $sha1) if ($i->total_out() != $size);
  &redoAndDel("Size mismatch: ".($i->total_out())." != $size", $sha1, $success) if ($i->total_out() != $size);
  my $shahex = $sha1digest->hexdigest;
  #&dieAndDel("SHA-1 mismatch: $sha1 != $shahex", $sha1) if ($sha1 ne $shahex);
  &redoAndDel("SHA-1 mismatch: $sha1 != $shahex", $sha1, $success) if ($sha1 ne $shahex);
#  $inFH->blocking(1);
  return $result;
}

sub saveRoot
{
  my $root = shift;
  my $indexFile = shift;
  my $index = "";
  my %rootInfo;
  if (-e "$ENV{GIB_DIR}/$indexFile.index")
  {
    open(my $inFH, "<", "$ENV{GIB_DIR}/$indexFile.index") 
        || die "cannot open index for read";
    $index = <$inFH> || "";
    close $inFH;
    my ($dir, $file) = $index =~ /^(..)(.*)$/;
    die if (!-e "$ENV{GIB_DIR}/objects/$dir/$file");
    open $inFH, "<$ENV{GIB_DIR}/objects/$dir/$file";
    while (<$inFH>)
    {
      last if ($_ =~ /^$/);
      my ($k, $v) = split /\t/, $_, 2;
      $rootInfo{$k} = $v;
    }
  }
  my $date = strftime '%a, %e %b %Y %H:%M:%S %z', localtime;
  $root = "previous\t$index\ntime\t$date\n\n$root";

  my $sha1 = Digest::SHA1->new;
  $root = sprintf("backup %d\0", length($root)).$root;
  $sha1->add($root);
  my $shahex = $sha1->hexdigest;
  my ($dir, $file) = $shahex =~ /^(..)(.*)$/;
  if (!-e "$ENV{GIB_DIR}/objects/$dir/$file")
  {
    mkdir "$ENV{GIB_DIR}/objects/$dir" if (!-d "$ENV{GIB_DIR}/objects/$dir");
    open my $ouFH, ">$ENV{GIB_DIR}/objects/$dir/$file" || die $!;
    print $ouFH compress($root);
    close $ouFH;
  }
  open(my $ouFH, ">", "$ENV{GIB_DIR}/$indexFile.index") || die "cannot open index";
  print $ouFH "$shahex";
  #$self->Debug( $shahex." (root)\n");
  return $shahex;
}

sub Run ($)
{
  my $self = shift;
  my $sock = $self->{'socket'};
  my $current = undef;
  my %doneDirs;
  my $currentDir = "";
  my $rootDir = "";
  my %needed;
  my $index = $sock->getline();
  $index =~ s/[^\w]//g;
  $sock->timeout(10);
  while (my $line = $sock->getline())
  {
    last if ($line =~ /\cD/);
    if ($line =~ /^>(.*)<$/)
    {
      die "Opened new directory while one was already opened"
        if (defined $current);
      $current = $1;
      #print $line;
      next;
    }
    if ($line =~ /^<(.*)>$/)
    {
      die "Closed a directory without it opened"
        if ((!defined $current) or ($1 ne $current));
      $current = undef;
      #print $line;
      my $redo = &requestFiles($self, $sock, %needed);
      %needed = ();
      $doneDirs{$1} = &saveDir($currentDir)
        if ($redo == 0);
      # We should come up with a way to count and stop more than x redo's.
      $currentDir = "";
      next;
    }
    my @st = split /\t/, $line;
    if (scalar @st != 15)
    {
      $sock->close() && die "Did not get enough paramaters for line items $line";
    }
    if ($st[14] =~ /^[0-9a-f]{40}$/)
    {
      chomp $st[14];
      my ($dir, $file) = $st[14] =~ /^(..)(.*)$/;
      if (! -e "$ENV{GIB_DIR}/objects/$dir/$file")
      {
        if (!exists $needed{$st[14]})
        {
#        $sock->print("[$st[14]]\n");
        # Queue a needed file
        $self->Debug("Q: [$st[14]]");
        $needed{$st[14]} = $st[7];
        }
      }
    }
    if ($st[14] =~ /^>(.*)<$/)
    {
      $st[14] = $doneDirs{$1} || die "$1 has not been sent";
      $line = join "\t", @st;
      $line .= "\n";
    }
    if (defined $current)
    {
      $currentDir .= $line;
    } else {
      $rootDir .= $line;
    }
  }
  sub requestFiles
  {
    my $self = shift;
    my $sock = shift;
    my %needed = @_;
    my $redo = 0;
    foreach (keys %needed)
    {
      # Ask for the needed files
      $sock->print("[$_]\n");
      $self->Debug("A: [$_]");
    }
    $sock->print("\cD\n");
    $sock->flush;
    my $lastData = $sock->getline();
    while ($sock->connected())
    {
      #print $lastData;
      last if ($lastData =~ /^\cD/);
      $lastData .= $sock->getline() if ($lastData !~ /^\[([0-9a-f]{40}|-{40})\]$/m);
      if ($lastData !~ /^\[([0-9a-f]{40}|-{40})\]$/m)
      {
        die "Mismatched data stream : $lastData" 
      }
      my $sha1 = $1;
      if ($sha1 =~ /-{40}/)
      {
        while ($lastData = $sock->getline())
        {
          last if ($lastData =~ /^\cD/);
        }
        last;
      }
      $self->Debug("saving [$sha1]");
      $lastData =~ s/^.*?\n//m;
      die "Uneeded file: $sha1" if (!exists $needed{$sha1});
      my $success;
      $lastData = saveFile($sha1, $needed{$sha1}, $sock, $lastData, \$success);
      delete $needed{$sha1};
      $sock->print("[$sha1]\t$success\n");
      $redo = 1 if ($success ne "Success");
      #print "got\n";
      last if (keys(%needed) == 0);
    }
    if (keys(%needed) != 0)
    {
      print $sock "Failure: did not recieve all requested files\n";
      die "Failure: did not recieve all requested files ".(scalar keys(%needed))."\n";
    }
    $lastData .= $sock->getline() if ($lastData !~ /\n$/m);
    die "Unexpected continuation" if ($lastData !~ /^\cD$/);
    $sock->print("\cD\n");
    return $redo;
  }
  #print $rootDir;
  my $rootsha = &saveRoot($rootDir, $index);
  print $sock "Success\n\cD\n";
  $self->Log('notice', "Success $index");
#  $sock->close();
}

package main;

die "GIB_DIR not defined, dofus" if (!defined $ENV{GIB_DIR});
mkdir "$ENV{GIB_DIR}/objects" if (! -e "$ENV{GIB_DIR}/objects");

my $server = GibDaemon->new({'localport' => 6182, 'pidfile' => 'none'}, \@ARGV);
$server->Bind();
