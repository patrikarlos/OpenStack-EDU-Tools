#!/bin/bash
# Removes users from a OpenStack project.
#
# Syntax:
#      removeStudents.sh [-v] [-h] [-i|--ignore=file] [-p] OS_DOMAIN OS_PROJECT
#
# Removes the users that have the member role in the OS_PROJECT found in the OS_DOMAIN.
# If purge enabled, users are also removed from OpenStack, if this was their last project.
# If users have other roles, they are not touched.
# If user email is found in ignore, they are not touched. (ATM, only username is checked)
#
#
## ASSUMES; roles Admin, member and reader.
## Requires Openstack credentials to be sourced.

##
## Hard settings..
#What's the educational institutes name(site) at Instructure?
site=bth
##Change this to a larger number, if you have many students/courses.
##Used due to Canvas pagination, normally canvas returns the equivalent of 10.
##This changes it to maxEntries. However, be carefull. 
maxEntries=10000;

die() { echo "$*" >&2; exit 2; }  # complain to STDERR and exit with error
needs_arg() { if [ -z "$OPTARG" ]; then die "No arg for --$OPT option"; fi; }



PURGE=false
VERGOSE=false
IGNOREFILE=
while getopts pvhi:-: OPT; do
    if [ "$OPT" = "-" ]; then
	OPT="${OPTARG%%=*}"       # extract long option name
	OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
	OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
    fi
    
    case "${OPT}" in
	p | purge)
	    PURGE=true
	    ;;
	i | ignore)
	    needs_arg;
	    IGNOREFILE="$OPTARG"
	    ;;
        h)
            echo "usage: $0 [-v] [-p|--purge] [--ignore=<filename>] <DOMAIN> <PROJECT>" >&2
            exit 2
            ;;
        v)
	    VERBOSE=true
#            echo "Parsing option: '-${optchar}'" >&2
            ;;
        *)
            if [ "$OPTERR" != 1 ] || [ "${optspec:0:1}" = ":" ]; then
                echo "Non-option argument: '-${OPTARG}'" >&2
            fi
            ;;
    esac
done

shift $((OPTIND-1)) # remove parsed options and args from $@ list

domain=$1
project=$2

echo -n "$domain/$project"

if [ $VERBOSE ]; then
echo -n "OS_user=$OS_USERNAME ($maxEntries)"
fi

if [ "$PURGE" = true ]; then
    echo -n ", purging students"
fi

if [ "$IGNOREFILE" ]; then
    echo ", using $IGNOREFILE."
else
    echo ", no ignore file."
fi

if [ -z "$domain" ]; then
    echo "Your missing the OpenStack domain."
    exit;
fi

if [ -z "$project" ]; then
    echo "Your missing the OpenStack project."
    exit;
fi


removedCNT=0
ignoredCNT=0
purgedCNT=0
otherroleCNT=0

Students=$(openstack user list --domain $domain --project $project -f csv | tail -n +2| tr -d '"' | tr ',' ' ')
noStud=$(echo "$Students" | wc -l)

echo "Got $noStud to parse."
while read Q; do
#    echo "$Q"
    read -r UUID uname <<<"$(echo "$Q")"

    #grab email
    UEMAIL=$(openstack user show --domain EDU $uname -f shell --prefix OSUS_ | grep OSUS_email | awk -F'=' '{print $2}' | tr -d '"')

    
    if [ "$IGNOREFILE" ]; then
	if [ $VERBOSE ]; then
	    echo "Checking $UEMAIL in $IGNOREFILE";
	fi
	ignoreIt=$(grep "$UEMAIL" $IGNOREFILE)
	if [ ! -z "$ignoreIt" ]; then
	    if [ $VERBOSE ]; then
		echo "Ignoring $uname, found in $IGNOREFILE"
	    fi
	    ((ignoredCNT++))
	    continue;       
	fi
    fi
	    
    
    echo -n "$uname ($UUID) :"
    
#    echo -e " Removing; openstack role remove --user-domain $domain --project $project --user $uname  member"
    out=$(openstack role remove --user-domain $domain --project $project --user $uname member 2>&1)
    if [ ! -z "$out" ]; then
	if [[ "$out" == *"not find role"* ]]; then
	    uroles=$(openstack role assignment list --user-domain $domain --project $project --user $uname -f value --names -c Role | tr '\n' ' ')
	    echo -n " User does not have the member role ($uroles):"

	    ((otherroleCNT++))
	else
	    echo "OpenStack returned<begin>"
	    echo "$out"
	    echo "<end>"
	fi
    else
	echo -n " Removed role:"
	((removedCNT++))
    fi


    remData=$(openstack role assignment list --user-domain $domain  --user "$uname" --names -f csv | tail -n +2 )
    remTotal=$(echo "$remData" | wc -l )
    remMember=$(echo "$remData" | grep -i member | wc -l )
    remAdmin=$(echo "$remData" | grep -i admin | wc -l )

    if [ "$PURGE" = true ]; then 
	if [ "$remTotal" -eq 1 ]; then
#	    echo -e "\t\tCandidate to purge.\n"
	    rem=$(openstack user delete --domain $domain $uname)
	    if [ ! -z "$rem" ]; then
		echo " $rem"
	    else
		echo " purged."
		((purgedCNT++))
	    fi
	else
	    echo " retained."
	fi
    else
	echo ""
    fi

#    remData=$(openstack role assignment list --user-domain $domain  --user "$uname" --names -f csv | tail -n +2 )
#    remTotal=$(echo "$remData" | wc -l )
#    remMember=$(echo "$remData" | grep -i member | wc -l )
#    remAdmin=$(echo "$remData" | grep -i admin | wc -l )
#    echo " Still have $remTotal, $remAdmin as admin, and $remMember as member.\n"
  
#    echo ""
done < <(echo "$Students" )

echo "Removed: $removedCNT"
echo "Purged:  $purgedCNT"
echo "Ignored: $ignoredCNT"
echo "Other role: $otherroleCNT"
