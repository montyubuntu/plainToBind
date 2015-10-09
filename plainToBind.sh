#!/bin/bash

AUTHINFO="December 2014; J Sikkema, 'plainToBind.sh' Tool that performs ip / fqdn lookups from file and echoes bind formatted strings to stdout."

if [ $USER == "root" ]; then
    USERID=`id -u $SUDO_USER`
    HOMEDIR="/home/$SUDO_USER"
else
    USERID=`id -u $USER`
    HOMEDIR="$HOME"
fi

MYPATH=$(cd ${0%/*} && pwd)
if [ -r $MYPATH/plaintobind.conf ]; then
    source $MYPATH/plaintobind.conf
else
    echo "plaintobind.conf not found, exiting.."
    exit 1
fi

VERSION="1.0"
VALIDATED_INDEX="$TMP_DIR/dnsMatchIndex_"$USERID"_"$TIMESTAMP".txt"
UNVALIDATED_INDEX="$TMP_DIR/dnsUmatchIndex_"$USERID"_"$TIMESTAMP".txt"
VERIFY_INDEX="$TMP_DIR/dnsDumpIndex_"$USERID"_"$TIMESTAMP".txt"
IPV4_REGEX='[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
IPV6_REGEX='(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))'

show_help () {
    echo -e "Usage: ${0##*/} [OPTION]... [FILE]...\n
Performs ip / fqdn lookups from input file and writes formatted lines to stdout in DNS(bind) friendly format.\n
  -h -?             shows this help info.\n
  -v                activates verbose output.\n
  -s                numeric sort in stdout.\n
  -o                writes outputfile to /home/userdir/\n
  -f                specify input file instead of /somedir/{latestfile}.* (always use this flag as the last argument.)\n
  -i                runs ${0##*/} in no ipv6 mode - does not check for presence of ipv6calc binary \n
  -V                prints version info and exits."
}

print_verbose () {
    if [ $VERBOSE == 1 ]; then
        echo -e "$1\n"
    fi
}

validate_platform () {
    print_verbose "Validating OS and necessary binaries..."
    
    if [[ ! `uname` == 'Linux' ]]; then
        echo "Error: OS `uname` not supported, exiting."
        exit 1
    fi
    
    if [[ -z `bash --version | grep "version 4"` ]]; then
        echo "Warning: Your bash version may be invalid, version 4.x or higher is required."
    fi

    if [ ! -x `which dig` ]; then
        echo "Error: DiG binary not found or set in user enviroment, exiting..."
        exit 1
    fi
    
    if [ $NO_IPV6 == 0 ]; then
        if [[ -z `which ipv6calc` ]]; then
            echo "Error: ipv6calc binary not found, exiting."
            exit 1
        fi
    fi

    print_verbose "OS and dependencies validated."
}

get_inputfile () {
    if [ -z $DNSFILE ]; then
        unset DNSFILE
        DNSFILE=`find $BASEDIR -maxdepth 1 -xdev -not -path '*/\.*' -type f -name '*\.*' -exec ls -1rt {} \+ | tail -1`
        notify_msg="$(echo "No input file given, assuming input file is:")"
        echo "$notify_msg "$DNSFILE""; printf 'Is this ok? y/n :'
        read arg
        case $arg in
            y|\Y)
                ;;
            n|\N)
                echo "Please specify file location with ${0##*/} -f /path_to_file/input_file.txt"
                exit 0
                ;;
            *)
                echo "Please type 'y'=yes or 'n'=no"
                exit 0
                ;;
        esac
    fi
}

validate_inputfile () {
    print_verbose "Validating source file: "$DNSFILE". Checking for non-ascii stuff and file permission settings."
    
    if [ ! -r $DNSFILE ]; then
        echo "Error: Cannot stat inputfile "$DNSFILE" or not readable, exiting..."
        exit 1
    fi
    
    if [[ count_index="$(cat -s "$DNSFILE" | wc -w)" -le 1 ]]; then
        echo "Error: "$DNSFILE" does not contain lines in {ipaddr}[whitespace]{fqdn} format, exiting..."
        exit 1
    fi
    
    if [[ sanity_check="$(grep -P -c "[\x80-\xFF]" "$DNSFILE")" -ge 1 ]]; then
        echo "Error: $sanity_check line(s) found that contain non-ascii characters in "$DNSFILE" exiting.."
        exit 1
    fi
    
    print_verbose "Source file validation ok!"
}

validate_dns () {
    print_verbose "Checking "$DNSSERVER" for existing DNS records..."
    
    read_index="$(cat -s "$VERIFY_INDEX" | grep -v '^$')"
    touch "$VALIDATED_INDEX"; touch "$UNVALIDATED_INDEX"
    digopts="+tcp +nocmd +nottl +nostats +noadditional +noauthority +nocomments"
    for line in $read_index; do
        if [[ -n $line ]]; then
           dns_nxdomain="$(host -T -t ANY $line $DNSSERVER | grep Host | grep NXDOMAIN)"
        fi
        if [[ -z $dns_nxdomain ]]; then
            echo "Q: $line" >> "$VALIDATED_INDEX"
            dig $digopts "$line" any @$DNSSERVER $digopts -x "$line" @$DNSSERVER >> "$VALIDATED_INDEX" 2> /dev/null
            echo ">>>==========--->" >> "$VALIDATED_INDEX"
        else 
            echo "$line" >> "$UNVALIDATED_INDEX"
        fi
    done
    
    print_verbose "DNS checking finished."
}

plaintext_parser () {
    print_verbose "Reading $DNSFILE and reformatting lines with ip4 / ip6 and fqdn records. All lines should contain an ip address and fqdn record only."
    
    IFS=$'\n'
    for line in `cat -s "$DNSFILE" | grep -v '^$'`; do
        ip4split="$(echo $line | grep -Eo ".$IPV4_REGEX." | tr -d "[:blank:]")"
        ip6split="$(echo $line | grep -Eo "$IPV6_REGEX" | tr -d "[:blank:]")"
        fqdnsplit="$(echo ${line,,} | grep -Eo "[[:space:]].{1,63}\.[a-zA-Z0-9-]{1,63}\.[a-zA-Z]{2,63}\.?$|^.{1,63}\.[a-zA-Z0-9-]{1,63}\.[a-zA-Z]{2,63}\.?[[:space:]]" | tr -d "[:blank:]")"
        if [[ -n $ip4split ]]; then
            if [[ -n "$(echo $fqdnsplit | grep -E "\.$")" ]]; then
                echo -e "${ip4split##*.}\t\tPTR\t${fqdnsplit}" >> "$OUTFILE";
            else
                echo -e "${ip4split##*.}\t\tPTR\t${fqdnsplit}" | sed -e 's/$/./' >> "$OUTFILE";
            fi
        elif [[ -n $ip6split ]]; then
            if [[ -n "$(echo $fqdnsplit | grep -E "\.$")" ]]; then
                echo -e "`ipv6calc --in ipv6addr --out revnibbles.arpa $ip6split|cut -d . -f 1-20`\t\tPTR\t\t${fqdnsplit}" >> "$OUTFILE";
            else
                echo -e "`ipv6calc --in ipv6addr --out revnibbles.arpa $ip6split|cut -d . -f 1-20`\t\tPTR\t\t${fqdnsplit}" | sed -e 's/$/./' >> "$OUTFILE";
            fi
        fi
    done
     
    for line in `cat -s "$DNSFILE" | grep -v '^$'`; do
        ip4split="$(echo $line | grep -Eo "$IPV4_REGEX" | tr -d "[:blank:]")"; echo $ip4split >> "$VERIFY_INDEX"
        ip6split="$(echo $line | grep -Eo "$IPV6_REGEX" | tr -d "[:blank:]")"; echo $ip6split >> "$VERIFY_INDEX"
        fqdnsplit="$(echo ${line,,} | grep -Eo "[[:space:]].{1,63}\.[a-zA-Z0-9-]{1,63}\.[a-zA-Z]{2,63}\.?$|^.{1,63}\.[a-zA-Z0-9-]{1,63}\.[a-zA-Z]{2,63}\.?[[:space:]]"| tr -d "[:blank:]")"; echo $fqdnsplit >> "$VERIFY_INDEX"
        if [[ -n $ip4split ]]; then
            echo -e "${fqdnsplit%%.*}\tA\t$ip4split"|sed -e 's/^[ \t]*//' -e 's/ *$//' >> "$OUTFILE"; 
        elif [[ -n $ip6split ]]; then
            echo -e "${fqdnsplit%%.*}\tAAAA\t`ipv6calc --in ipv6addr --out ipv6addr $ip6split`"|sed -e 's/^[ \t]*//' -e 's/ *$//' >> "$OUTFILE";
        else
            echo "Warning no ip addresses found on $line, name type CNAME, SRV or TXT are not supported by this tool."
        fi
    done
    unset IFS

    print_verbose "Parsing of ip adresses and hostnames done."
}

print_output () {
    echo -e "\n=========================Existing dns records:========================"
    
    cat "$VALIDATED_INDEX" | grep -Ev "^$|^;"
    
    echo -e "\n=========================Non existing dns records:========================"
    
    cat -s "$UNVALIDATED_INDEX" | grep -v '^$'
    
    echo -e "\n=========================DNS Bind friendly format:========================"
    
    if [ $SORTED_OUTPUT == 1 ]; then
        cat -s "$OUTFILE" | sort -bn
    else
        cat -s "$OUTFILE"
    fi
    
    if [ $DNSREPORT == 1 ]; then
        echo "Written outputfile to: "$OUTFILE""
    else
        rm -f "$OUTFILE"
    fi
    
    print_verbose "All done, cleaning up self, deleting: "$VALIDATED_INDEX" "$UNVALIDATED_INDEX" "$VERIFY_INDEX""
    
    rm -f "$VALIDATED_INDEX" "$UNVALIDATED_INDEX" "$VERIFY_INDEX"
}

while getopts "h?vsVoif:" arg; do
    case "$arg" in
    h|\?)
        show_help
        exit 0
        ;;
    v)  VERBOSE=1
        ;;
    s)  SORTED_OUTPUT=1
        ;;
    V)  PRINTVERSION=1
        ;;
    o)  DNSREPORT=1
        ;;
    i)  NO_IPV6=1
        ;;
    f)  DNSFILE=$OPTARG
        ;;
    esac
done

shift $((OPTIND-1))

[ "$1" = "--" ] && shift

if [ $PRINTVERSION -eq 1 ]; then
    echo "${0##*/} version $VERSION"
    echo $AUTHINFO
    exit 0
else
    validate_platform
fi

print_verbose "Verbose_mode='$VERBOSE', Input_file='$DNSFILE', Sort_output='$SORTED_OUTPUT', Write_to_outfile='$DNSREPORT', Dns_server='$DNSSERVER' No_ipv6_mode='$NO_IPV6'"

if [ -z $DNSSERVER ]; then
    echo "Error :No DNS Server set in $MYPATH/plain_to_bind.conf, exiting..."
    exit 1
fi

dns_alive="$(dig +short @$DNSSERVER | grep -Eiv "not found|no servers could be reached|connection timed out" | wc -l)"
if [ $dns_alive -eq 0 ]; then
    echo "Error: Failed to connect to $DNSSERVER, exiting..."
    exit 1
else
    get_inputfile
fi

if [[ -r $DNSFILE ]]; then
    validate_inputfile
    plaintext_parser
    validate_dns
    print_output
else
    echo "Error: $DNSFILE not readible, exiting." 
    exit 1
fi

exit
