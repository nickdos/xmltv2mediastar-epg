#!/usr/bin/perl -w
#
# Converts XMLTV format to the EPG format for the Medistar PVR.
# 
# copyright (c) 2006 Nick dos Remedios - nick at remedios-cole.id.au
# 
# Project home: http://code.google.com/p/xmltv2mediastar-epg/
#
# xmltv2mediastar is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# xmltv2mediastar is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with Cambia Sequence; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
# 
# $Id$
#
use strict;
use XML::TreePP;
use Date::Parse;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use POSIX qw(strftime);
use Getopt::Std;
use Data::Dumper;

my %opts = ();              # hash to store input args
getopts("dhi:o:t",\%opts); # load the args into %opts

my $input_file    = ($opts{'i'}) ? $opts{'i'} : $ARGV[0];
my $EPG_file_name = ($opts{'o'}) ? $opts{'o'} : "ICE_EPG.DAT";
my $debug         = $opts{'d'} if $opts{'d'};    # print out debugging when set to true (1) 
my $t_offset      = $opts{'t'} if $opts{'t'};

if ((!%opts && ! -r $ARGV[0]) || $opts{'h'}) {
    usage();
}

# Parse the XMLTV file
my $tpp = XML::TreePP->new();
$tpp->set( force_array => [ 'category' ] );  # force array ref for some fields
my $xmltv_ref = $tpp->parsefile( $input_file );

# Normalise the XMLTV data structure (munge it)
my $programmes_ref = munge_programme($xmltv_ref);

# print out message to terminal screen
print "Total programmes = ", $#{ $programmes_ref } + 1, "\n";

# format the data for the output file
my $EPG_data = format_EPG($programmes_ref);

if (-e $EPG_file_name) {
    # output file  already exists, so rename it
    rename $EPG_file_name, "$EPG_file_name.$$";
}

# print it to file (in current directory) UTF-8 uncoding
#open EPG, "> $EPG_file_name" or die "Can't write to output file $EPG_file_name: $!\n";
open EPG, ">:utf8", $EPG_file_name or die "Can't write to output file $EPG_file_name: $!\n";
print EPG $EPG_data, "\n";
close EPG or die "Can't close EPG filehandle: $!\n";

###############################################################################
#
# Subroutines go here
#
###############################################################################

sub get_lcn {
    #
    # Channel name to LCN mapping
    #
    my $LCN = { # FTA digital channels
                '2'     => '0002',
                'ABC ACT' => '0002',
                'ABC-Can' => '0002',
                '57'    => '0002',        # ICE id
                '2-2'   => '0021',
                'ABC2'  => '0021',
                '58'    => '0021',        # ICE id
                '7'     => '0006,0007',
                'PrimS' => '0006,0007',
                'Prime-Can' => '0006,0007',
                'Prime Southern, Canberra/Wollongong/Sth Coast' => '0006,0007',
                '56'    => '0006,0007',   # ICE id
                '9'     => '0008,0009',
                'WIN'   => '0008,0009',
                'WIN-Can' => '0008,0009',
                'WIN Television NSW' => '0008,0009',
                '54'    => '0008,0009',   # ICE id
                '10a'   => '0005,0010',
                '10'    => '0010,0005',
                'Ten-Can' => '0010,0005',
                '10Cap' => '0010,0005',
                'Southern Cross TEN Capital, Canberra' => '0010,0005',
                '55'    => '0010,0005',   # ICE id
                'SBS'   => '0003,1283',
                'SBS-Can'   => '0003,1283',
                'SBS Eastern' => '0003,1283',
                '59'    => '0003,1283',   # ICE id
                'SBS-2' => '0033,1281',
                'SBS-NEWS' => '0033,1281',
                'SBSD'  => '0033,1281',
                'SBS News' => '0033,1281',
                '60'    => '0033,1281',   # ICE id
                # SelecTV channels for DT-820
                'FashionTV'   => '1286', 
                'EuroNews'    => '1291',
                'BBC'         => '1283',
                'CNNI'        => '1284',
                'Bloomberg'   => '1288',
                'Cartoon Net' => '1293',
                'NGEO'        => '1316',
                'MTV'         => '1314',
                'VH1'         => '1321',
                'TCM'         => '1318',
                'MOV1'        => '1322', 
                'MOVX'        => '1323',
                'MOVG'        => '1315', 
                'MOV2'        => '1317', 
                'A1'          => '1325',
                'E!'          => '1324', 
                'Ovation'     => '1326',
               };
    
    return $LCN;    
}

sub munge_programme {
    #
    # Process the XMLTV data structure 
    #
    my ($xmltv_ref)  = @_;
    my $prog_ref     = $xmltv_ref->{tv}->{programme};
    my $tv_generator = $xmltv_ref->{tv}->{'-generator-info-name'};
    my ($all_p_ref);
    my $lcn_ref = get_lcn();    # get the hash ref of LCN mappings
    #print Dumper("munge_programme", $prog_ref );

    for my $p (@{ $prog_ref }) {
        # Get values for the XML fields...
        my $prog_ref;
        $prog_ref->{channel}   = $p->{-channel};    # attribute
        $prog_ref->{start}     = $p->{-start};      # attribute
        $prog_ref->{stop}      = $p->{-stop};       # attribute
        $prog_ref->{title}     = (ref $p->{title} eq "HASH") 
                                   ? $p->{title}->{content}    
                                   : $p->{title};
        $prog_ref->{sub_title} = (ref $p->{'sub-title'} eq "HASH") 
                                   ? $p->{'sub-title'}->{content} 
                                   : $p->{'sub-title'};
        $prog_ref->{desc}      = (ref $p->{desc} eq "HASH") 
                                   ? $p->{desc}->{content} 
                                   : $p->{desc};
        $prog_ref->{category}  = (ref $p->{category} eq "HASH") 
                                   ? $p->{category}->{content} 
                                   : $p->{category}->[0];
        
        $prog_ref->{rating}    = $p->{rating}->{value};
       #$prog_ref->{ice_id}    = $p->{'episode-num'}->[0]->{content};
        $prog_ref->{event_id}  = $p->{'episode-num'}->{content};
        $prog_ref->{aspect}    = $p->{video}->{aspect};
        $prog_ref->{subtitles} = $p->{subtitles}->{type};
        
        # Munge values for output...
        ($prog_ref->{gmt_start},
         $prog_ref->{duration})  = get_times($prog_ref->{start}, $prog_ref->{stop}, $tv_generator);
        $prog_ref->{epg_start}   = encode($prog_ref->{gmt_start});
        $prog_ref->{title}       = substr($prog_ref->{title}, 0, 30);    # only grab first 30 characters
        $prog_ref->{sub_title}   = substr($prog_ref->{sub_title}, 0, 500) if $prog_ref->{sub_title};
        $prog_ref->{desc}        = substr($prog_ref->{desc}, 0, 505) if $prog_ref->{desc};
        $prog_ref->{desc}        =~ s/(\r|\n)/ /gsm if $prog_ref->{desc};
        $prog_ref->{channel}     = (split /\./, $prog_ref->{channel})[2] || $prog_ref->{channel};
        $prog_ref->{lcn}         = $lcn_ref->{$prog_ref->{channel}};
        $prog_ref->{ice_id}      = (split /\,/, $prog_ref->{lcn})[0]  if $prog_ref->{lcn};
        $prog_ref->{ice_id}      = sprintf("%d", $prog_ref->{ice_id}) if $prog_ref->{lcn};
        $prog_ref->{event_id}    = ($prog_ref->{event_id}) 
                                     ? $prog_ref->{event_id}              # IceTV data
                                     : get_event_id($prog_ref->{title});  # others
        $prog_ref->{category}    = category_to_num($prog_ref->{category});
        $prog_ref->{rating}      = rating_to_num($prog_ref->{rating});
        
        push @{ $all_p_ref }, $prog_ref;   # add it to the array ref
    }
    
    return $all_p_ref;
}

sub format_EPG {
    #
    # produce the Mediastar ICE_EPG.DAT output text
    # (15 column tab separated text file)
    #
    my ($data) = @_;
    my ($epg);
    #print Dumper($data);
    for my $p (@{ $data }) {
        next if !$p->{lcn};      # skip channels not defined with LCN
        $epg .= $p->{epg_start}                             . "\t";  # col 1
        $epg .= $p->{ice_id}                                . "\t";  # col 2
        $epg .= $p->{lcn}                                   . "\t";  # col 3
        $epg .= $p->{event_id}                              . "\t";  # col 4
        $epg .= $p->{duration}                              . "\t";  # col 5
        $epg .= ($p->{title})     ? $p->{title}     . "\t" :  "\t";  # col 6
        $epg .= ($p->{sub_title}) ? $p->{sub_title} . "\t" :  "\t";  # col 7
        $epg .= ($p->{category})  ? $p->{category}  . "\t" :  "\t";  # col 8
        $epg .= "1\t";                                               # col 9
        $epg .= "1\t";                                               # col 10
        $epg .= "1\t";                                               # col 11
        $epg .= "1\t";                                               # col 12
        $epg .= "1\t";                                               # col 13
        $epg .= ($p->{rating}) ? $p->{rating}       . "\t" :  "\t";  # col 14
        $epg .= ($p->{desc})   ? $p->{desc}                :  ""  ;  # col 15
        $epg .= "\n";
    }
    
    return $epg;
}

sub encode {
    #
    # Encode input number to the text code for EPG
    #
    my ($input)  = @_;
    my $output = "";
    my %code   = ( ' ' => 'z', 0 => 'a', 1 => 'b', 2 => 'c', 3 => 'd', 4 => 'e', 
                     5 => 'f', 6 => 'g', 7 => 'h', 8 => 'i', 9 => 'j',
                 );
    my @digits = split //, $input;    # split on every character
    
    for my $i (@digits)  {
        # substitute the letter code for each number and append to $output
        $output .= $code{$i};
    }
    
    if (length $output eq 14) {
        # if entire time field is passed in, don't encode the beginning 2 and end 0
        $output =~ s/^./2/;
        $output =~ s/.$/0/;
    }
    
    return $output;
}

sub get_times {
    #
    # process the start, stop and durations times
    #
    my (%input_time, %dates, $tv_generator);
    ($input_time{start}, $input_time{stop}, $tv_generator) = @_;
    my ($gmt_time, $is_gmt, $duration);
    
    for my $key (keys %input_time) {
        # either start or stop
        if ($input_time{$key} =~ /(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\s+\+(\d{4})/) {
            # e.g. "20060805142000 +0000" or "20060805142000 +1000"
            $dates{$key} = str2time("$1-$2-$3T$4:$5:$6");    # standard internet format
            my $gmt_offset  = "$7";
            $is_gmt = ($gmt_offset eq "0000") ? 1 : 0;
        }
        elsif ($input_time{$key} =~ /(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/) {
            # e.g. "20060805142000"
            $dates{$key} = str2time("$1-$2-$3T$4:$5:$6");     # standard internet format
            $is_gmt = 1 if ($tv_generator =~ /Wktivoguide/i); # for http://minnie.tuhs.org/tivo-bin/xmlguide.pl data
        }
        else {
            die "Date format not recognised: $input_time{$key}.\n";
        }
    }
    
    $duration = ($dates{stop} - $dates{start}) / 60;
    
    if ($is_gmt) {
        # GMT times -> use localtime conversion
        $gmt_time = POSIX::strftime("%Y%m%d%H%M%S", (localtime $dates{start}));
    }
    else {
        # Local times -> use gmtime conversion
        $gmt_time = POSIX::strftime("%Y%m%d%H%M%S", (gmtime $dates{start}));
    }
    
    return ($gmt_time, $duration);
}

sub get_event_id {
    #
    # generate a unique id (5 digit int) for a given title via MD5 hash
    #
    my ($title) = @_;
    no warnings;
    my $digest = md5_hex($title);
    my $hex    = hex($digest);
    my $id     = substr $hex, 2, 5;
    
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
    my %ratings = ( 'G' => 7, 'P' => 3, 'C' => 5, 'PG' => 9, 'M' => 11, 'MA' => 13, 'AV' => 15, 'AV' => 18 );
    my $rating = ($ratings{$input}) ? $ratings{$input} : 0;
    $output = ($rating) ? $rating : $output;
    
    return $output;
}

sub category_to_num {
    #
    # Map descriptive sections to integers - not used
    #
    # TODO - work out how to handle multiple categories (can Mediastar?)
    #
    my ($input) = @_;
    my $output = 1;
    $input = lc $input;    # force lower case
    # Categories - ETSI EN 300 468 V1.7.1 table 28
    # http://webapp.etsi.org/action/OP/OP20060428/en_300468v010701o.pdf
    # combined fields 1 & 2 as hex
    my %categories = ( 'movie'         => '0x10', 'game show'  => '0x30',
                       'drama'         => '0x10', 'news'       => '0x20',
                       'childrens'     => '0x50', 'food'       => '0xA5',
                       'music'         => '0x60', 'comedy'     => '0x14',
                       'documentary'   => '0x23', 'soap'       => '0x15',  
                       'shopping'      => '0xA6', 'lifestyle'  => '0xA0',
                       'religion'      => '0x73', 'sport'      => '0x40',
                       'entertainment' => '0x32', 'travel'     => '0xA1', 
                       'reality'       => '0x34', 'business'   => '0x22',
                       'educational'   => '0x54', 'arts'       => '0x70',
                       'fantasy'       => '0x13', 'talk show'  => '0x33',
                       'action'        => '0x12', 'nature'     => '0x91', 
                       'crime'         => '0x11',      
                       'science and technology' => '0x92',
                       'current affairs'        => '0x20',
                     );
    
    if (! exists $categories{$input}) {
        warn "Unrecognised category: $input\n" if 0;
    }
    else {
        # convert hex to decimal
        my $category = hex($categories{$input});
        $output = ($category) ? $category : $output;
    }
    
    return $output;
}

sub usage {
    #
    # print Usage message
    #
    my $filename = (split(/\//,$0))[-1];
	print STDERR << "EOF";

Usage: $filename [-dh] -i input_xmltv_file [-o output_file ]

-h      : this (help) message
-d      : print debugging messages 
-i file : input XMLTV file (or filename as only arg to script)
-o file : output EPG file (default: ICE_EPG.DAT)

example: $filename -i xmltv.xml -o ICE_EPG.ABC.DAT 
	
EOF
exit;
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
