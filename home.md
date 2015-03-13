# XMLTV2Mediastar-EPG #

This project started with a single Perl script that converts XMLTV data to
the EPG (electronic programme guide) data file format used by the Mediastar
DT-920PVR, DT-820PVR and Arion 9300 PVR. Windows users may want to first try the
[PVR-Tools converter](http://pvr-tools.com/) (Win-32 executable - easier to install).

The Perl script requires the following pre-requisites:

  * Perl 5.6 or later (Windows users try [ActivePerl](http://www.activestate.com/Products/ActivePerl/))

To run the script via the command line:
```
  $ ./xmltv2epg.pl xmltv.xml
```
where xmltv.xml is the input XMLTV file containing TV guide data. An output file is created with the file name "ICE\_EPG.DAT". Copy this file into the "/PVR/ICEEPG" directory on your PVR.

Sources for XMLTV data in Australia can be found on:

> http://www.cse.unsw.edu.au/~willu/xmltv/index.html

This software is made freely available under the Gnu Public License (GPL)
version 2.

Nick dos Remedios (nickdos at gmail.com), August 2006.