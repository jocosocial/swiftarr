#!/bin/bash
# Resets non-dockerized Postgres and Redis databses.
#

echo "Do you really want to reset the Postgres and Redis databases?"
echo "This will completely reset Swiftarr, deleting all users and user data."

read -p "Are you sure? " -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
    # postgres
    echo "Postgres dropdb is going to ask for the password for user 'swiftarr'."
	/Library/PostgreSQL/14/bin/dropdb -U swiftarr swiftarr && echo "db deleted successfully" || echo "dropdb failed. You may not want to continue?"
    echo "Postgres createdb is going to ask for the password for user 'swiftarr'."
	/Library/PostgreSQL/14/bin/createdb -U swiftarr swiftarr && echo "swiftarr db created successfully."
	
	# redis
	echo "Telling redis to flushall"
	redis-cli flushall
else
	echo "Ok. Exiting without doing anything."
fi

