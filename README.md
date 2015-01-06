plainToBind
===========

plainToBind.sh is a simple tool that performs ip / fqdn lookups from file and echoes bind formatted strings to stdout.
This is a tool written in shell language (bash). It reads ip addr and fqdn records from inputfile and parses them to bind friendly format. In addition: it also checks if records are existing in DNS.

The inputfile should be a plain text file. Every single line must contain an fqdn and ip address string only. It does not matter in which order these strings are placed.**

For validating records on the DNS server, it uses tcp queries in order to get a 100% valid answer.

It does not support CNAME, TXT and SRV records. (yet)

**Make sure to use a field separator like {whitespace}.

Tip: set a $PATH variable ":/home/username/usr/bin" in your .bashrc and create a s.link here to"/path_to_/plainToBind.sh".

Or create an alias in you .bashrc: alias plainToBind='/path_to_/plainToBind.sh'

 
You can explore and use several options at your own leisure, (plainToBind.sh -?):

Usage: plainToBind.sh [OPTION]... [FILE]...


Performs ip / fqdn lookups from input file and writes formatted lines to stdout in DNS(bind) friendly format.

 

  -h -?             shows this help info.

 

  -v                activates verbose output.

 

  -s                numeric sort in dns stdout.

 

  -o                writes outputfile to /home/userdir/

 

  -f                specify input file instead of /somedir/{latestfile}.* (always use this flag as the last argument)
 


  -i                runs plainToBind.sh in no ipv6 mode - does not check for presence of ipv6calc binary

 

  -V                prints version info and exits.

 
The tool automatically assumes the rfs file resides in /somedir/ and asks for user confirmation:

$./plainToBind.sh   
No input file given, assuming input file is: /somedir/dnsfile.txt

 
Use the -f flag if the file resides anywhere else:
$./plainToBind.sh -f /home/user/dnsfile.txt

 
Always use the 'f' operand as the last argument character. This function reads any character or string immediately after the 'f' character:
$./plainToBind.sh -fv /home/user/dnsfile.txt
cat: v: No such file or directory
Error: v does not contain lines in {ipaddr}[whitespace]{fqdn} format, exiting...

 
Prerequisites:

(The tool checks if the prerequisites are met, but we list these anyway:)

-OS: Linux (Any linux version, the tool is extensively tested on Ubuntu 12.04.4 LTS)

-Bash version 4 or greater. (Older versions might cause unexpected behavior due not implementing string operators.)

-ipv6calc 0.92.0 or greater. (Older versions may also work, this is not guaranteed.)

-DiG 9.8.1 or greater. (Older versions might work aswell.)
