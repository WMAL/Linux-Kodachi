#!/bin/sh -e

# Start or stop Postfix
#
# LaMont Jones <lamont@debian.org>
# based on sendmail's init.d script

### BEGIN INIT INFO
# Provides:          postfix mail-transport-agent
# Required-Start:    $local_fs $remote_fs $syslog $named $network $time
# Required-Stop:     $local_fs $remote_fs $syslog $named $network
# Should-Start:      postgresql mysql clamav-daemon postgrey spamassassin saslauthd dovecot
# Should-Stop:       postgresql mysql clamav-daemon postgrey spamassassin saslauthd dovecot
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Postfix Mail Transport Agent
# Description:       postfix is a Mail Transport agent
### END INIT INFO

PATH=/bin:/usr/bin:/sbin:/usr/sbin
DAEMON=/usr/sbin/postfix
NAME=Postfix
TZ=
unset TZ

test -x $DAEMON && test -f /etc/postfix/main.cf || exit 0

. /lib/lsb/init-functions
#DISTRO=$(lsb_release -is 2>/dev/null || echo Debian)

enabled_instances() {
	postmulti -l -a | awk '($3=="y") { print $1}'
}

running() {
    INSTANCE="$1"
    if [ "X$INSTANCE" = X ]; then
	    POSTCONF="postconf"
    else
	    POSTCONF="postmulti -i $INSTANCE -x postconf"
    fi

    queue=$($POSTCONF -hx queue_directory 2>/dev/null || echo /var/spool/postfix)
    daemondir=$($POSTCONF -hx daemon_directory 2>/dev/null || echo /usr/lib/postfix/sbin)
    if [ -f ${queue}/pid/master.pid ]; then
	pid=$(sed 's/ //g' ${queue}/pid/master.pid)
	# what directory does the executable live in.  stupid prelink systems.
	dir=$(ls -l /proc/$pid/exe 2>/dev/null | sed 's/.* -> //; s/\/[^\/]*$//')
	if [ "X$dir" = "X${daemondir}" ]; then
	    echo y
	fi
    fi
}

case "$1" in
    start)
	log_daemon_msg "Starting Postfix Mail Transport Agent" postfix
	RET=0
	# for all instances that are not already running, handle chroot setup if needed, and start
	for INSTANCE in $(enabled_instances); do
	    RUNNING=$(running $INSTANCE)
	    if [ "X$RUNNING" = X ]; then
		/usr/lib/postfix/configure-instance.sh $INSTANCE
		CMD="/usr/sbin/postmulti -- -i $INSTANCE -x ${DAEMON}"
		if ! start-stop-daemon --start --exec $CMD quiet-quick-start; then
		    RET=1
		fi
	    fi
	done
	log_end_msg $RET
    ;;

    stop)
	log_daemon_msg "Stopping Postfix Mail Transport Agent" postfix
	RET=0
	# for all instances that are not already running, handle chroot setup if needed, and start
	for INSTANCE in $(enabled_instances); do
	    RUNNING=$(running $INSTANCE)
	    if [ "X$RUNNING" != X ]; then
		CMD="/usr/sbin/postmulti -i $INSTANCE -x ${DAEMON}"
		if ! ${CMD} quiet-stop; then
		    RET=1
		fi
	    fi
	done
	log_end_msg $RET
    ;;

    restart)
        $0 stop
        $0 start
    ;;

    force-reload|reload)
	log_action_begin_msg "Reloading Postfix configuration"
	if ${DAEMON} quiet-reload; then
	    log_action_end_msg 0
	else
	    log_action_end_msg 1
	fi
    ;;

    status)
	ALL=1
	ANY=0
	# for all instances that are not already running, handle chroot setup if needed, and start
	for INSTANCE in $(enabled_instances); do
	    RUNNING=$(running $INSTANCE)
	    if [ "X$RUNNING" != X ]; then
	    	ANY=1
	    else
	    	ALL=0
	    fi
	done
	# handle the case when postmulti returns *no* configured instances
	if [ $ANY = 0 ]; then
	   ALL=0
	fi
	if [ $ALL = 1 ]; then
	   log_success_msg "postfix is running"
	   exit 0
	elif [ $ANY = 1 ]; then
	   log_success_msg "some postfix instances are running"
	   exit 0
	else
	   log_success_msg "postfix is not running"
	   exit 3
	fi
    ;;

    flush|check|abort)
	${DAEMON} $1
    ;;

    *)
	log_action_msg "Usage: /etc/init.d/postfix {start|stop|restart|reload|flush|check|abort|force-reload|status}"
	exit 1
    ;;
esac

exit 0
