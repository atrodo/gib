#!/usr/bin/perl

#use File::stat;
use File::Find;
use Digest::SHA1 qw/sha1_hex/;
use Compress::Zlib;

die "GIB_DIR not defined, dofus" if (!defined $ENV{GIB_DIR});

sub wanted
{
  #my $sha1 = $File::Find::name;
  return if $File::Find::name !~ m[^.*([0-9a-f][0-9a-f])/([0-9a-f]*)$]; #]
  #$sha1 =~ s[^.*([0-9a-f][0-9a-f])/([0-9a-f]*)$][$1$2]; #]
  $sha1 = $1.$2;
  #warn $sha1."\n";
  my $i = inflateInit() || die "Cannot create inflator";
  my $sha1digest = Digest::SHA1->new;
  open(my $inFH, "<", $File::Find::name) || die $!;
  binmode $inFH;
    my ($output, $status) ;
    while (read($inFH, $input, 4096))
    {
        ($output, $status) = $i->inflate(\$input) ;
    
    #    print $output 
    $sha1digest->add($output)
            if $status == Z_OK or $status == Z_STREAM_END ;
    
        last if $status != Z_OK ;
    }
    
    warn "$sha1 : inflation failed: $status\n"
        unless $status == Z_STREAM_END ;
    my $shahex = $sha1digest->hexdigest;
    warn "$sha1 : bad hash\n"
        unless $sha1 eq $shahex;

}

find({ bydepth => 1, wanted => \&wanted, } , "$ENV{GIB_DIR}/objects");
#find({ bydepth => 1, wanted => \&wanted, preprocess => \&preprocess, postprocess => \&postprocess} , $ENV{GIB_DIR});
