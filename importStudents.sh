#!/bin/bash

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



courseCode=$1
domain=$2
project=$3
ignore=$4

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

if [ -z "$ignore" ]; then
    echo -e "No ignore file provided, all will be added. Unless they already exist."
else
    echo -e "$ignore."
fi;




#echo "curl -H \"Authorization: Bearer $TOKEN\" \"https://$site.instructure.com/api/v1/courses/$courseID/users\" "
echo "Collecting data from Canvas."

#Trying to find ID
courseData=$(curl -H "Authorization: Bearer $TOKEN" -s  "https://$site.instructure.com/api/v1/courses?enrollment_type=teacher&state=available&per_page=$maxEntries" | jq -r '.[] | {name, id}' |  jq "[.[]] | @tsv" | sed 's/\\t/*/g' | tr -d '"' | grep "$courseCode")
courseID=$(echo "$courseData" | awk -F'*' '{print $2}')
courseString=$(echo "$courseData" | awk -F'*' '{print $1}')

found=$(echo "$courseID" | wc -l )
echo "found $found"

if [[ "$found" -gt "1" ]]; then
    echo "Too many matches, narrow your Course code."
    echo "Add semester, i.e. 'CourseCode HT22'"
    exit;
fi

if [ -z "$courseID" ]; then
    echo "Did not find a course. Check your syntax,|$courseID|."
    exit;
fi

echo "Course ID: $courseID - $courseString"


data1=$(curl -H "Authorization: Bearer $TOKEN" -s  "https://$site.instructure.com/api/v1/courses/$courseID")
name=$(echo $data1 | jq '.name')
echo "Course: $name"

data=$(curl -H "Authorization: Bearer $TOKEN" -s  "https://$site.instructure.com/api/v1/courses/$courseID/users?per_page=10") #$maxEntries")

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

echo "$emStrip" | while read line; do 
    read -r EMAIL NAME <<<"$(echo "$line")"
    NAME=$(echo "$NAME" | tr -d '"')
    EMAIL=$(echo "$EMAIL" | tr -d '"')
    uname=$(echo "$EMAIL" | awk -F'@' '{print $1}') 
    
#    echo -n "'$NAME' -- '$EMAIL' -- $uname "
    
    echo -n "$uname "
    res=$(openstack user show "$uname" --domain "$domain" 2>/dev/null )
    if [ -z "$res" ]; then
	echo -n " creating user "
	dstring=$(date +'%Y-%m-%d %H:%M')
	passwdString=$(echo $RANDOM | md5sum | head -c 12)
	rs=$(openstack user create --domain "$domain" --project "$project" --email "$EMAIL" --password "$passwdString" --description "$NAME autocreated $dstring importStudents, $domain,$project,$OS_USERNAME" --no-ignore-change-password-upon-first-use $uname )
	if grep -qi "error" <<< "$rs"; then
	    echo "Some error occured."
	else
	    if [ -z "$GenString" ]; then
		GenString=$(echo -e "$uname $passwdString\n")
	    else
		GenString=$(echo -e "$GenString$uname $passwdString")
	    fi
	fi	
    else
	echo -n " user exists "
    fi

    echo -n " adding member role to $project"
    openstack role add --user-domain "$domain" --user "$uname" --project "$project" member
    
    echo "."
done

echo "User Password"
echo "$GenString"
