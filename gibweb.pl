#!/usr/bin/perl

use strict;
use warnings;
use CGI;
use Compress::Zlib;

$ENV{GIB_DIR} = "/mnt/hdd3/gib";
die "GIB_DIR not defined, dofus" if (!defined $ENV{GIB_DIR});
die "$ENV{GIB_DIR}/objects" if (! -e "$ENV{GIB_DIR}/objects");

my $q = new CGI;
print $q->header;

sub inflate
{
  my $sha1 = shift;
  my $x = inflateInit()
     or die "Cannot create a inflation stream\n" ;

  my ($dir, $file) = $sha1 =~ /^(..)(.*)$/;
  open my $inFH, "<$ENV{GIB_DIR}/objects/$dir/$file" or die $!;
  my $input = '' ;
  my $output;
  binmode $inFH;

  my ($stream, $status) ;
  while (read($inFH, $input, 4096))
  {
    ($stream, $status) = $x->inflate(\$input);
    $output .= $stream if $status == Z_OK or $status == Z_STREAM_END;
    last if $status != Z_OK ;
  }

  die "inflation failed: $status\n" unless $status == Z_STREAM_END;
  my ($type, $size, $data) = $output =~ m/^(\w*)\s(\d*)\0(.*)$/s;
  die "Mismatch" unless $size == length $data;
  return { type => $type, size => $size, data => $data};
}

sub process
{
  my $input = shift;
  my $data = $input->{data};
  if ($input->{type} eq "backup")
  {
    my ($prev) = $data =~ m/previous\t(\X{40})$/m;
    my ($time) = $data =~ m/time\t(.*)$/m;
    print $q->h2($time);
    print $q->h2("Previous: ".$q->a({-href=>"?id=$prev"}, $prev) );
    $data =~ s/^.*\n\n(.*)$/$1/s;
    print $q->h3("Directories:");
    print $q->start_table;
    my @items = split /\n/m, $data;
    @items = sort {$a->[13] cmp $b->[13]} map {[split /\t/, $_]} @items;
    #@items = map {\@{split /\t/, $_}} @items;
    #map {print ref $_} @items;
    #@items = sort {$a->[13] <=> $b->[13]} @items;
    #foreach my $item (sort {$a->[13] <=> $b->[13]} split /\n/m, $data)
    foreach my $item (@items)
    {
      #my @s = split /\t/, $item;
      my @s = @$item;
      print $q->Tr(
        $q->td($s[2]),
        $q->td($q->a({-href=>"?id=".$s[14]}, $s[13])),
      );
    }
    print $q->end_table;
    return;
  }
  if ($input->{type} eq "backuptree")
  {
    print $q->h3("Directories:");
    print $q->start_table;
    #foreach my $item (split /\n/m, $data)
    my @items = split /\n/m, $data;
    @items = sort {$a->[13] cmp $b->[13]} map {[split /\t/, $_]} @items;
    #@items = map {[split /\t/, $_]} @items;
    #map {print "".$_} @items;
    #@items = sort {$a->[13] cmp $b->[13]} @items;
    ##foreach my $item (sort {$a->[13] <=> $b->[13]} split /\n/m, $data)
    foreach my $item (@items)
    {
      #my @s = split /\t/, $item;
      my @s = @$item;
      print $q->Tr(
        $q->td($s[2]),
        $q->td(
          ($s[14] eq "<->"
            ? $s[13]
            : $q->a({-href=>"?id=".$s[14]}, $s[13])
          )),
      );
    }
    print $q->end_table;
    return;
  }
}

unless ($q->param("id"))
{
  foreach my $index(glob "$ENV{GIB_DIR}/*.index")
  {
    $index =~ s[$ENV{GIB_DIR}/][];
    print $q->start_html,
      $q->h3(
        $q->a({-href=>"?id=$index"}, "$index")
      ),
      $q->end_html;
    }

}

if ($q->param("id") =~ m/\.index$/)
{
  open my $inFH, "<$ENV{GIB_DIR}/".$q->param("id") || die $!;
  my $sha1 = <$inFH>;
  close $inFH;
  my $input = &inflate($sha1);
  #print $input->{data};
  &process($input);
}

if ($q->param("id") =~ m/^\X{40}$/)
{
  #open my $inFH, "<$ENV{GIB_DIR}/".$q->param("id") || die $!;
  #my $sha1 = <$inFH>;
  #close $inFH;
  my $input = &inflate($q->param("id"));
  #print $input->{data};
  &process($input);
}
