#!/usr/bin/perl -w
#
# Converts XMLTV format to the EPG format for the Medistar PVR.
#
# copyright (c) 2006 Nick dos Remedios - nick at remedios-cole.id.au
# 
# version 0.01, NdR 02 Aug 2006
#
use strict;
use XML::Twig;
use Date::Parse;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use POSIX qw(strftime);
use Data::Dumper;

our ($programmes_ref, $channels_ref);    # global variables
my $EPG_file_name = "ICE_EPG.DAT";

my $twig = new XML::Twig( keep_encoding => 1, 
                          twig_handlers => { channel   => \&channel,
                                             programme => \&programme,
                                           },
                         );

$twig->parsefile( $ARGV[0] );    # build the twig

print "Total programmes = ", $#{ $programmes_ref } + 1, "\n";

my $EPG_data = format_EPG($programmes_ref);

if (-e $EPG_file_name) {
    # output file  already exists
    rename $EPG_file_name, "$EPG_file_name.$$";
}

open EPG, "> $EPG_file_name" or die "Can't write to output file $EPG_file_name: $!\n";
print EPG $EPG_data, "\n";
close EPG or die "Can't close EPG filehandle: $!\n";

sub channel {
    #
    # get a mapping for XMLTV channel IDs and LCN for Mediastar EPG
    #
    my( $t, $channel) = @_;
    my $channel_ref;
    my %LCN = ( '2'     => '0002',
                '2-2'   => '0021',
                '7'     => '0006,0007',
                '9'     => '0008,0009',
                '10a'   => '0005,0010',
                '10'    => '0010,0005',
                'SBS'   => '0003,1283',
                'SBS-2' => '0033,1281',
               );
                                
    my $id     = $channel->att('id');
    my $LCN_id = (split /\./, $id)[2];  # e.g. freesd.Canberra.2 -> 2
    my $name   = $channel->first_child('display-name')->text;
    $channels_ref->{$id} = $LCN{$LCN_id};
    
    $t->purge;
}

sub programme {
    #
    # parse the programme GI and add to the data structure $programmes_ref
    #
    my( $t, $programme) = @_; # all handlers get called with those arguments
    my $prog_ref;
    
    $prog_ref->{channel}   = $programme->att('channel');
    $prog_ref->{start}     = $programme->att('start');
    $prog_ref->{stop}      = $programme->att('stop');
    $prog_ref->{title}     = $programme->first_child('title')->text
                             if $programme->first_child('title');
    $prog_ref->{subtitle}  = $programme->first_child('sub-title')->text
                             if $programme->first_child('sub-title');
    $prog_ref->{desc}      = $programme->first_child('desc')->text
                             if $programme->first_child('desc');
    $prog_ref->{rating}    = $programme->first_child('rating')->first_child('value')->text
                             if $programme->first_child('rating');
    $prog_ref->{category}  = $programme->first_child('category')->text
                             if $programme->first_child('category');
    $prog_ref->{aspect}    = $programme->first_child('video')->first_child('aspect')->text
                             if $programme->first_child('video');
    $prog_ref->{subtitles} = ($programme->first_child('subtitles')) ? 2 : 0;
    
    $prog_ref->{unix_start} = date2epoch($prog_ref->{start});
    $prog_ref->{gmt_start}  = POSIX::strftime("%Y%m%d%H%M%S", (gmtime $prog_ref->{unix_start}));
    @{ $prog_ref->{gmt_start_list} }  = gmtime($prog_ref->{unix_start});
    $prog_ref->{unix_stop}  = date2epoch($prog_ref->{stop});
    $prog_ref->{duration}   = ($prog_ref->{unix_stop} - $prog_ref->{unix_start}) / 60;
    
    $prog_ref->{channel_name} = $channels_ref->{$prog_ref->{channel}};
    
    push @{ $programmes_ref }, $prog_ref;    # add it to the global array ref

    $t->purge;
}

sub format_EPG {
    #
    # produce the Mediastar ICE_EPG.DAT output text
    # (15 column tab separated text file)
    #
    my ($data) = @_;
    my ($epg);
    
    for my $p (@{ $data }) {
        $epg .= convert_epg_date(@{ $p->{gmt_start_list} }) . "\t";  # col 1
       #$epg .= $p->{gmt_start}                             . "\t";  # col 1
        my $ice_id = (split /\,/, $p->{channel_name})[0];
        $epg .= sprintf("%d", $ice_id)                      . "\t";  # col 2
        $epg .= $p->{channel_name}                          . "\t";  # col 3
        $epg .= get_event_id($p->{title})                   . "\t";  # col 4
        $epg .= $p->{duration}                              . "\t";  # col 5
        $epg .= ($p->{title}) ? $p->{title}. "\t" :           "\t";  # col 6
        $epg .= ($p->{subtitle}) ? $p->{subtitle}. "\t" :     "\t";  # col 7
        $epg .= ($p->{category}) ? category_to_num($p->{category}) . "\t" :  "\t";  # col 8
       #$epg .= ($p->{category}) ? $p->{category} . "\t" :    "\t";  # col 8
        $epg .= "1\t";                                               # col 9
        $epg .= "1\t";                                               # col 10
        $epg .= "1\t";                                               # col 11
        $epg .= "1\t";                                               # col 12
        $epg .= "1\t";                                               # col 13
        $epg .= ($p->{rating}) ? rating_to_num($p->{rating}) . "\t" : "\t";  # col 14
        $epg .= ($p->{desc}) ? $p->{desc} . "\t"                    : "\t";  # col 15
        $epg .= "\n";
    }
    
    return $epg;
}

sub convert_epg_date {
    #
    # Convert unix epoch time to EPG column 1 date format
    #
    # gmtime = ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday)
    # Code 1: 14 digit time code in UTC/GMT (thanks angelrose, dave, and temporary1 :) )
    # As 2yyymmddhhmm 
    #  with a=q=0 b=r=1 c=s=2 d=t=3 e=u=4 f=v=5 g=w=6 h=x=7 i=y=8 j=z=9 Upper or lowercase) First '2' is fixed.
    #
    my @gmtime = @_;
    my $epg_data;

    my $YY  = encode(1900 + $gmtime[5]);
    $YY     = substr $YY, 1, 3;    # 2006 -> 006
    my $MM  = encode(sprintf "%02d", $gmtime[4] + 1);
    my $DD  = encode(sprintf "%02d", $gmtime[3]);
    my $hh  = encode(sprintf "%02d", $gmtime[2]);
    my $mm  = encode(sprintf "%02d", $gmtime[1]);
    $epg_data .= "2". $YY . $MM . $DD . $hh . $mm . "a0";
    
    if (length $epg_data != 14) {
        die "Oops, date conversion error: length of $epg_data not 14.\n";
    }
    
    return $epg_data;
}

sub encode {
    #
    # encode input number to the text code for EPG
    # Todo: might need to also use the second encding set ?
    #
    my ($input)  = @_;
    #print "encode 1: $input\n";
    my $output = "";
    my %code   = ( ' ' => 'z', 0 => 'a', 1 => 'b', 2 => 'c', 3 => 'd', 4 => 'e', 
                     5 => 'f', 6 => 'g', 7 => 'h', 8 => 'i', 9 => 'j',
                 );
    my @digits = split //, $input;
    
    for my $i (@digits)  {
        $output .= $code{$i};
    }
    
    return $output;
}

sub date2epoch {
    #
    # Convert date as 20060808002500 to unixtime
    #
    my ($date)     = @_;
    my $epoch_date = 0;
    my $date_str;
    
    if ($date =~ /(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/) {
        $date_str = "$1-$2-$3T$4:$5:$6";    # standard internet format
    } else {
        die "Date format not recognised: $date.\n";
    }
    
    $epoch_date = str2time($date_str);
    return $epoch_date;
}

sub get_event_id {
    #
    # generate a unique id (5 digit int) for a given title via MD5 hash
    #
    my ($title) = @_;
    
    no warnings ;
    my $id;
    my $digest = md5_hex($title);
    my $hex = hex($digest);
    $id = substr $hex, 2, 5;
    
    return $id;
}

sub rating_to_num {
    #
    # Map descriptive sections to integers - To Do
    #
    my ($input) = @_;
    my $output = 1;
    $input = uc $input;    # force upper case
    # 0(unrated) 9 (PG) 12 (MA) 15(AV) 18(AV)
    my %ratings = ( 'G' => 0, 'PG' => 9, 'MA' => 12, 'AV' => 15, 'AV' => 18 );
    my $rating = $ratings{$input};
    $output = ($rating) ? $rating: $output;
    return $output;
}

sub category_to_num {
    #
    # Map descriptive sections to integers - not used
    #
    my ($input) = @_;
    my $output = 1;
    $input = lc $input;    # force upper case
    # 0(unrated) 9 (PG) 12 (MA) 15(AV) 18(AV)
    my %categories = ( 'movie' => "0x10", 'drama' => 1, 'childrens' => 1, 'music' => 1, 
                       'documentary' => 1, 'game show' => 1, 'news' => 1, 'food' => 1,
                       'shopping' => 1, 'comedy' => 1, 'soap' => 1, 'lifestyle' => 1,
                       'current affairs' => 1, 'religion' => 1, 'entertainment' => 1, 
                       'reality' => 1, 'science and technology' => 1);
    my $category = hex($categories{$input}) if $categories{$input};
    $output = ($category) ? $category: $output;
    return $output;
}

__DATA__
<programme channel="freesd.Canberra.2" start="20060731015500" stop="20060731035500">
    <title>Fanny By Gaslight</title>
    <desc>(PG)</desc>
    <rating system="CTVA"><value>PG</value></rating>
    <category>Movie</category>
</programme>

2QQfRSqwctAAQ0	2	0002	15609	10	Lights, Camera, Action, Wiggles!			1	1	1	2	1	0	The Wiggles want to make TV for children their way: full of fun, music and entertainment transmitted from their very own Network Wiggles.

1) Time in UTC
2) ICE unique ID
3) LCN
4) Event ID
5) Duration in minutes
6) Series/program name
7) Episode Name
8) Program category/content type
9) Colour information (b&w, colour, unknown)
10) Closed captions
11) Defintion (HD, SD etc)
12) Repeat
13) Aspect Ratio
14) Rating
15) Description
