# OpenStack-EDU-Tools

Tools that allow us to create users, projects, etc. within OpenStack
related to Education. 

All scripts assume that you have sourced an environment file (openrc)
that has the appropriate credentials.


importStudents.sh [-v] [-h] [-i|--ignore=file] <coursecode> <OS_domain> <OS_project>
  Imports students from <coursecode>, into the OS_domain/OS_project, unless
  email address is found in ignorefile.
  It tries to identify the course ID (canvas value), based on course code. If the provided
  course code returns >1 entry, the tool aborts and list its findings.
  You then need to narrow the scope, usually enough by adding semester and
  year. i.e, DV1619, can become 'DV1619 HT20', or 'DV1619H19'. If you need
  spaces, use "'" around the string.

  Once, it has found the course id, it retreives all students, their email
  address and name. This is probably just active students.

  Next, based on email address, it extracts the first part, before the '@' and
  uses that as username. It then checks if a user with that name exists, if it
  does, no user is created. Otherwise, a user is created, and a random
  password is assigned. Note, that if created, the user is forced to change
  password on the first login.

  Irrespective if the user was created or not, the user is added as a member
  to the OS_project.

  Once all users have been processed, the username - passwords are printed.
  To be shared with the users in someway.

  Requires Openstack credentials to be sourced.
  Requires Canvas Token to be sourced. 

removeStudents.sh [-v] [-h] [-i|--ignore=file] [-p] OS_DOMAIN OS_PROJECT
 
  Removes the users that have the member role in the OS_PROJECT found in the OS_DOMAIN.
  If purge enabled, users are also removed from OpenStack, if this was their last project.
  If users have other roles, they are not touched.
  If user email is found in ignore, they are not touched. (ATM, only username is checked)

  ASSUMES; roles Admin, member and reader.
  Requires Openstack credentials to be sourced.


