#!/bin/bash
# Imports students to an OpenStack project, from a Canvas Course.
#
# Syntax:
#      importStudents.sh [-v] [-h] [-i|--ignore=file] CourseCode OS_DOMAIN OS_PROJECT
# 
#
#
# Description
#      Imports students from <coursecode>, into the OS_domain/OS_project, unless email address
#      is found in ignorefile.
#      It tries to identify the course ID (canvas value), based on course code. If the provided
#      course code returns >1 entry, the tool aborts and list its findings.
#      You then need to narrow the scope, usually enough by adding semester and
#      year. i.e, DV1619, can become 'DV1619 HT20', or 'DV1619H19'. If you need
#      spaces, use "'" around the string.
#    
#      Once, it has found the course id, it retreives all students, their email
#      address and name. This is probably just active students.
#    
#      Next, based on email address, it extracts the first part, before the '@' and
#      uses that as username. It then checks if a user with that name exists, if it
#      does, no user is created. Otherwise, a user is created, and a random
#      password is assigned. Note, that if created, the user is forced to change
#      password on the first login.
#    
#      Irrespective if the user was created or not, the user is added as a member
#      to the OS_project.
#    
#      Once all users have been processed, the username - passwords are printed.
#      To be shared with the users in someway.
#
#
## Requires a CANVAS token in TOKEN
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



VERBOSE=false
IGNOREFILE=
created=0
added=0

PASSWDFILE=$(mktemp)

while getopts vhi:-: OPT; do
    if [ "$OPT" = "-" ]; then
	OPT="${OPTARG%%=*}"       # extract long option name
	OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
	OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
    fi
    
    case "${OPT}" in
	i | ignore)
	    needs_arg;
	    IGNOREFILE="$OPTARG"
	    ;;
        h)
            echo "usage: $0 [-v] [--ignore=<filename>] <COURSECODE> <DOMAIN> <PROJECT>" >&2
            exit 2
            ;;

        v) 
	    VERBOSE=true
            ;;
        *)
            if [ "$OPTERR" != 1 ] || [ "${optspec:0:1}" = ":" ]; then
                echo "Non-option argument: '-${OPTARG}'" >&2
            fi
            ;;
    esac
done



shift $((OPTIND-1)) # remove parsed options and args from $@ list

courseCode=$1
domain=$2
project=$3

if [ -z $TOKEN ]; then
    echo "Your missing the Canvas API token. Grab one from your Profile page."
    exit;
fi

if [ -z "$courseCode" ]; then
    echo "Your missing the course ID, find it from Canvas."
    exit;
fi

if [ -z "$domain" ]; then
    echo "Your missing the OpenStack domain."
    exit;
fi

if [ -z "$project" ]; then
    echo "Your missing the OpenStack project."
    exit;
fi

echo -n "$courseCode -> $domain/$project $OS_USERNAME ($maxEntries) "

if [ -z "$IGNOREFILE" ]; then
    echo -e "No ignore file provided, all will be added. Unless they already exist."
else
    echo -e "$IGNOREFILE"
fi;




#echo "curl -H \"Authorization: Bearer $TOKEN\" \"https://$site.instructure.com/api/v1/courses/$courseID/users\" "
if [ "$VERBOSE" = true ]; then
    echo "Collecting data from Canvas."
fi

#Trying to find ID
courseData=$(curl -H "Authorization: Bearer $TOKEN" -s  "https://$site.instructure.com/api/v1/courses?enrollment_type=teacher&state=available&per_page=$maxEntries" | jq -r '.[] | {name, id}' |  jq "[.[]] | @tsv" | sed 's/\\t/*/g' | tr -d '"' | grep "$courseCode")
courseID=$(echo "$courseData" | awk -F'*' '{print $2}')
courseString=$(echo "$courseData" | awk -F'*' '{print $1}')

found=$(echo "$courseID" | wc -l )
if [ "$VERBOSE" = true ]; then
    echo "found $found"
fi

if [[ "$found" -gt "1" ]]; then
    echo "Too many matches, narrow your Course code."
    echo "Add semester, i.e. 'CourseCode HT22'"
    exit;
fi

if [ -z "$courseID" ]; then
    echo "Did not find a course. Check your syntax,|$courseID|."
    exit;
fi

echo "Course ID: $courseID - $courseString  ($PASSWDFILE)"


data1=$(curl -H "Authorization: Bearer $TOKEN" -s  "https://$site.instructure.com/api/v1/courses/$courseID")
name=$(echo $data1 | jq '.name')
if [ "$VERBOSE" = true ]; then
    echo "Course: $name"
fi

#TEST
#data=$(curl -H "Authorization: Bearer $TOKEN" -s  "https://$site.instructure.com/api/v1/courses/$courseID/users?per_page=10") #$maxEntries")

##PRODUCTION
data=$(curl -H "Authorization: Bearer $TOKEN" -s  "https://$site.instructure.com/api/v1/courses/$courseID/users?per_page=$maxEntries")

emails=$(echo "$data" | jq ".[].email" | tr -d '"')
names=$(echo "$data" | jq ".[].name" | tr -d '"')

emname=$(echo "$data" | jq ".[] | {email,name}"  | jq "[.[]] | @csv" | tr -d '\\' | tr ',' ' ' )
#echo "emname:" 
#echo "$emname"
emStrip=$(echo "$emname" | sed  's/\"\"/\"/g')
#echo "$emStrip" | hexdump -c

#
#OSDATA=$(openstack project show $OS_PROJECT_ID -f shell)
#
#name=$(echo "$OSDATA" | grep name | awk -F'=' '{print $2}' | tr -d '"' )
#desc=$(echo "$OSDATA" | grep description | awk -F'=' '{print $2}' | tr -d '"' )
#
#echo "OpenStack"
#echo "$name  - $desc "
#
cnt=$(echo "$emStrip" | wc -l)


echo "Have $cnt students to check, storing passwords in $PASSWDFILE."

##Data found at the end, as input to the while loop. 
while read line; do 
    read -r EMAIL NAME <<<"$(echo "$line")"
    NAME=$(echo "$NAME" | tr -d '"')
    EMAIL=$(echo "$EMAIL" | tr -d '"')
    uname=$(echo "$EMAIL" | awk -F'@' '{print $1}') 
    
#    echo -n "'$NAME' -- '$EMAIL' -- $uname "
    if [ "$IGNOREFILE" ]; then
#	echo "Checking ignore $uname"
	ignoreIt=$(grep "$EMAIL" $IGNOREFILE)
	if [ ! -z "$ignoreIt" ]; then
	    if [ "$VERBOSE" = true ]; then
		echo "$uname : Ignoring found in $IGNOREFILE"
	    fi
	    continue;
	fi
    fi
    
    echo -n "$uname :"
    res=$(openstack user show "$uname" --domain "$domain" 2>/dev/null )
    if [ -z "$res" ]; then
	dstring=$(date +'%Y-%m-%d %H:%M')
	passwdString=$(echo $RANDOM | md5sum | head -c 12)
	rs=$(openstack user create --domain "$domain" --project "$project" --email "$EMAIL" --password "$passwdString" --description "$NAME autocreated $dstring importStudents, $domain,$project,$OS_USERNAME" --no-ignore-change-password-upon-first-use $uname )
	if grep -qi "error" <<< "$rs"; then
	    echo -n " Some error occured."
	else
	    echo -n " created user:"
	    if [ "$VERBOSE" = true ]; then
		echo -n " |$EMAIL - $uname - $passwdString| "
	    fi

	    echo "$EMAIL - $uname - $passwdString" >> $PASSWDFILE
	   
	    ((created++))
	fi	
    else
	echo -n " user exists:"
    fi

    echo -e " adding member role to $project"
    openstack role add --user-domain "$domain" --user "$uname" --project "$project" member
    ((added++))
done < <(echo "$emStrip")

echo "Created $created users"
echo "Added $added users, $PASSWDFILE"
