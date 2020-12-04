#!/bin/bash


### BEGIN INIT INFO
# Provides:   openttd
# Required-Start: $local_fs $remote_fs
# Required-Stop:  $local_fs $remote_fs
# Should-Start:   $network
# Should-Stop:    $network
# Default-Start:  2 3 4 5
# Default-Stop:   0 1 6
# Short-Description:    OPENTTD server
# Description:    Init script for openttd server. 
### END INIT INFO

# =================
# Created by Frodus
# =================

if [[ $EUID -ne 0 ]];
then
    exec sudo "$BASH_SOURCE" "$@"
fi

# User that should run the server
USERNAME="ubuntu"

# Name to use for the screen instance
SCREEN="server_screen"

# Path to openttd server config directory  (CONFIGPATH can not end with a /)
CONFIGPATH="/${USERNAME}/openttd-1.10.3$"

# When saving your world, this is the filename.
SAVEGAME="myGame"

# Get the current login username
ME=`whoami`

# Get TimeStamp
TIMESTAMP=$SAVEGAME-`date +"%Y-%m-%d_%H:%M"`

# Checks if config file is ok.
if [ "$USERNAME" == "" ]
then
	echo "Configuration file is not correct!"
	echo "Make sure that you have renamed config.example to config and that you have edited/inserted all the fields"
	exit
fi

# Makes sure that the correct user is starting and stopping the server
as_user() {
	if [ $ME == $USERNAME ] ; then
		bash -c "$1"
	else
		su $USERNAME -s /bin/bash -c "$1"
	fi
}

# Function to start the server
openttd_start() {
	pidfile=${CONFIGPATH}/${SCREEN}.pid
	check_permissions

	# Starts the server in a screen and saves the ID of the prossess to a pidfile
	as_user " screen -dmS $SCREEN openttd -D"
	as_user " screen -list | grep '\.$SCREEN' | cut -f1 -d'.' > $pidfile"

	# Waiting for the server to start
	sec=0
	until is_running 
	do
		sleep 1
		sec=$sec+1
		if [[ $sec -eq 10 ]]
		then
			echo "Server using to long time to start... Lets wait 60 sec before abort..."
		fi
		if [[ $sec -ge 60 ]]
		then
			echo "Failed to start, aborting."
			exit 1
		fi
	done	
	echo "OPENTTD is now running!"
}

# Stops the server
openttd_stop() {
	pidfile=${CONFIGPATH}/${SCREEN}.pid
	# Stops the server
	sleep 10
	echo "Tries to stop server..."
	# Sending "exit" to the admin consol
	openttd_toConsol exit
	sleep 0.5
	# Waiting for the server to stop
	sec=0
	isInStop=1
	while is_running
	do
		sleep 1 
		sec=$sec+1
		if [[ $sec -eq 5 ]]
		then
			echo "Server using longer time then expected to shutdown. Lets wait 60 sec before abort..."
		fi
		if [[ $sec -ge 60 ]]
		then
			echo "Could not stop server during this 60 sec"
			echo "Check if server still runs by typing: 'screen -list' "
			echo "If nothing is listed the server is not running..."
			echo "If one or more screen are listed: type 'screen -r <The numbers in front of $SCREEN listed>'"
			echo "Now you can stop the server manualy by type: 'exit'"
			exit 1
		fi
	done
	as_user " rm $pidfile"
	unset isInStop
	is_running
	echo "OPENTTD is now shut down."
}

# Checks if you can create pidfile
check_permissions() {
	as_user "touch $pidfile"
	if ! as_user "test -w '$pidfile'" ; then 
		echo "Check Permissions!! Unable to create pidfile. Please correct the permissions and try again."
	fi
}

# Checks if openttd screen exist.
is_running() {
	pidfile=${CONFIGPATH}/${SCREEN}.pid

	if [ -r "$pidfile" ]
	then
		pid=$(head -1 $pidfile)
		if ps ax | grep -v grep | grep ${pid} | grep "${SCREEN}" > /dev/null
		then
			return 0
		else 
			if [ -z "$isInStop" ]
			then
				if [ -z "$roguePrinted" ]
				then
					roguePrinted=1
					#echo "Pidfile found!"
				fi
			fi
			return 1
		fi
	else
		if ps ax | grep -v grep | grep "${SCREEN} ${SERVICE}" > /dev/null
		then
			echo "No pidfile found, but server seems to be running."
			echo "Trying to creating new pidfile."
			
			pid=$(ps ax | grep -v grep | grep "${SCREEN} ${SERVICE}" | cut -f1 -d' ')
			check_permissions
			as_user "echo $pid > $pidfile"

			return 0
		else
			return 1
		fi
	fi
}
# Send comands to the consol
openttd_toConsol() {
	if is_running
	then
			as_user "screen -p 0 -S $SCREEN -X stuff '$1 $2'`echo -ne '\015'`"
	else
			echo "OPENTTD not running.."
	fi
}
openttd_save() {
	openttd_toConsol save $SAVEGAME
	echo 'Saved game: '$SAVEGAME
}
openttd_load() {
	openttd_toConsol load $SAVEGAME
	echo 'Loaded game: '$SAVEGAME
}
force_exit() {  # Kill the server running (messily) in an emergency
	echo ""
	echo "SIGINIT CALLED - FORCE EXITING!"
	openttd_stop
}
trap force_exit SIGINT
case "$1" in
	status)
		# Is server running?
		if is_running; then
			echo "OPENTTD is running"
		else
			echo "OPENTTD is not running"
		fi
		;;
	start)
		# Start the OPENTTD server
		if is_running; then
			echo "Server is already running..."
		else
			openttd_start
			openttd_load
		fi
		;;
	stop)
		# Stops the OPENTTD server
		if is_running; then
			openttd_save
			openttd_stop
		else
			echo "No running server."
		fi
		;;
	restart)
		# Restarts the OPENTTD server
		if is_running; then
			openttd_save
			openttd_stop
		else
			echo "No running server, starting it..."
		fi
		openttd_start
		openttd_load
		;;
	save)
		# Saves the current running game
		if is_running; then
			openttd_save
		fi
		;;
	autosave)
		# Creates timestamped saves
		if is_running; then
			openttd_save
			openttd_toConsol save $TIMESTAMP
			echo 'Auto saved game at: '$TIMESTAMP
		fi
		;;
	load)
		# Loads the saved game
		if is_running; then
			openttd_load
		fi
		;;
	help|--help|-h)
		echo "Usage: $0 COMMAND"
		echo 
		echo "Available commands:"
		echo -e "   status \t\t Shows the current status of the server"
		echo -e "   start \t\t Starts the server and load the game"
		echo -e "   stop \t\t Stops the server and save the game"
		echo -e "   restart \t\t Saves the game and restarts the server"
		echo -e "   save \t\t Saves the running game"
		echo -e "   autosave \t\t Saves the running game and adds a timestamp"
		echo -e "   load \t\t Loads the saved game"
		;;
	*)
		echo "No such command, see $0 help"
		exit 1
		;;
	esac
exit 0
