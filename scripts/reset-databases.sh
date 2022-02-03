#!/bin/bash
# Resets non-dockerized Postgres and Redis databses.
#

echo "Do you really want to reset the Postgres and Redis databases?"
echo "This will completely reset Swiftarr, deleting all users and user data."

read -p "Are you sure? " -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
	# Find install location
	if test -f "/usr/local/opt/postgresql/bin/dropdb"; then
		POSTGRES_DIR="/usr/local/opt/postgresql/bin"
	elif test -f "/opt/homebrew/opt/postgresql/bin/dropdb"; then
		POSTGRES_DIR="/opt/homebrew/opt/postgresql/bin"
	else
		echo "Couldn't find postgres install location"
		exit 1
	fi

    # postgres
    echo "Postgres dropdb is going to ask for the password for user 'swiftarr'."
#	/Library/PostgreSQL/14/bin/dropdb -U swiftarr swiftarr && echo "db deleted successfully" || echo "dropdb failed. You may not want to continue?"
	if $POSTGRES_DIR/dropdb -U swiftarr swiftarr  ; then
		echo "db deleted successfully"
	else
		echo "dropdb failed. You may not want to continue?"
		exit 1
	fi

    echo "Postgres createdb is going to ask for the password for user 'swiftarr'."
#	/Library/PostgreSQL/14/bin/createdb -U swiftarr swiftarr && echo "swiftarr db created successfully."
	if $POSTGRES_DIR/createdb -U swiftarr swiftarr ; then
		echo "swiftarr db created successfully."
	else
		echo "createdb failed. You may not want to continue?"
		exit 1
	fi
	
	# redis
	echo "Telling redis to flushall"
	redis-cli flushall
else
	echo "Ok. Exiting without doing anything."
fi

