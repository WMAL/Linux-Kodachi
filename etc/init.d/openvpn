#!/bin/sh -e

### BEGIN INIT INFO
# Provides:          openvpn
# Required-Start:    $network $remote_fs $syslog
# Required-Stop:     $network $remote_fs $syslog
# Should-Start:      network-manager
# Should-Stop:       network-manager
# X-Start-Before:    $x-display-manager gdm kdm xdm wdm ldm sdm nodm
# X-Interactive:     true
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Openvpn VPN service
# Description: This script will start OpenVPN tunnels as specified
#              in /etc/default/openvpn and /etc/openvpn/*.conf
### END INIT INFO

# Original version by Robert Leslie
# <rob@mars.org>, edited by iwj and cs
# Modified for openvpn by Alberto Gonzalez Iniesta <agi@inittab.org>
# Modified for restarting / starting / stopping single tunnels by Richard Mueller <mueller@teamix.net>

. /lib/lsb/init-functions

test $DEBIAN_SCRIPT_DEBUG && set -v -x

DAEMON=/usr/sbin/openvpn
DESC="virtual private network daemon"
CONFIG_DIR=/etc/openvpn
test -x $DAEMON || exit 0
test -d $CONFIG_DIR || exit 0

# Source defaults file; edit that file to configure this script.
AUTOSTART="all"
STATUSREFRESH=10
OMIT_SENDSIGS=0
if test -e /etc/default/openvpn ; then
  . /etc/default/openvpn
fi

start_vpn () {
    if grep -q '^[	 ]*daemon' $CONFIG_DIR/$NAME.conf ; then
      # daemon already given in config file
      DAEMONARG=
    else
      # need to daemonize
      DAEMONARG="--daemon ovpn-$NAME"
    fi

    if grep -q '^[	 ]*status ' $CONFIG_DIR/$NAME.conf ; then
      # status file already given in config file
      STATUSARG=""
    elif test $STATUSREFRESH -eq 0 ; then
      # default status file disabled in /etc/default/openvpn
      STATUSARG=""
    else
      # prepare default status file
      STATUSARG="--status /run/openvpn/$NAME.status $STATUSREFRESH"
    fi

    # tun using the "subnet" topology confuses the routing code that wrongly
    # emits ICMP redirects for client to client communications
    SAVED_DEFAULT_SEND_REDIRECTS=0
    if grep -q '^[[:space:]]*dev[[:space:]]*tun' $CONFIG_DIR/$NAME.conf && \
       grep -q '^[[:space:]]*topology[[:space:]]*subnet' $CONFIG_DIR/$NAME.conf ; then
        # When using "client-to-client", OpenVPN routes the traffic itself without
        # involving the TUN/TAP interface so no ICMP redirects are sent
        if ! grep -q '^[[:space:]]*client-to-client' $CONFIG_DIR/$NAME.conf ; then
            sysctl -w net.ipv4.conf.all.send_redirects=0 > /dev/null

            # Save the default value for send_redirects before disabling it
            # to make sure the tun device is created with send_redirects disabled
            SAVED_DEFAULT_SEND_REDIRECTS=$(sysctl -n net.ipv4.conf.default.send_redirects)

            if [ "$SAVED_DEFAULT_SEND_REDIRECTS" -ne 0 ]; then
              sysctl -w net.ipv4.conf.default.send_redirects=0 > /dev/null
            fi
        fi
    fi

    log_progress_msg "$NAME"
    STATUS=0

    start-stop-daemon --start --quiet --oknodo \
        --pidfile /run/openvpn/$NAME.pid \
        --exec $DAEMON -- $OPTARGS --writepid /run/openvpn/$NAME.pid \
        $DAEMONARG $STATUSARG --cd $CONFIG_DIR \
        --config $CONFIG_DIR/$NAME.conf || STATUS=1

    [ "$OMIT_SENDSIGS" -ne 1 ] || ln -s /run/openvpn/$NAME.pid /run/sendsigs.omit.d/openvpn.$NAME.pid

    # Set the back the original default value of send_redirects if it was changed
    if [ "$SAVED_DEFAULT_SEND_REDIRECTS" -ne 0 ]; then
      sysctl -w net.ipv4.conf.default.send_redirects=$SAVED_DEFAULT_SEND_REDIRECTS > /dev/null
    fi
}
stop_vpn () {
  start-stop-daemon --stop --quiet --oknodo \
      --pidfile $PIDFILE --exec $DAEMON --retry 10
  if [ "$?" -eq 0 ]; then
    rm -f $PIDFILE
    [ "$OMIT_SENDSIGS" -ne 1 ] || rm -f /run/sendsigs.omit.d/openvpn.$NAME.pid
    rm -f /run/openvpn/$NAME.status 2> /dev/null
  fi
}

case "$1" in
start)
  log_daemon_msg "Starting $DESC"

  # first create /run directory so it's present even
  # when no VPN are autostarted by this script, but later
  # by systemd openvpn@.service
  mkdir -p /run/openvpn

  # autostart VPNs
  if test -z "$2" ; then
    # check if automatic startup is disabled by AUTOSTART=none
    if test "x$AUTOSTART" = "xnone" -o -z "$AUTOSTART" ; then
      log_warning_msg " Autostart disabled."
      exit 0
    fi
    if test -z "$AUTOSTART" -o "x$AUTOSTART" = "xall" ; then
      # all VPNs shall be started automatically
      for CONFIG in `cd $CONFIG_DIR; ls *.conf 2> /dev/null`; do
        NAME=${CONFIG%%.conf}
        start_vpn
      done
    else
      # start only specified VPNs
      for NAME in $AUTOSTART ; do
        if test -e $CONFIG_DIR/$NAME.conf ; then
          start_vpn
        else
          log_failure_msg "No such VPN: $NAME"
          STATUS=1
        fi
      done
    fi
  #start VPNs from command line
  else
    while shift ; do
      [ -z "$1" ] && break
      if test -e $CONFIG_DIR/$1.conf ; then
        NAME=$1
        start_vpn
      else
       log_failure_msg " No such VPN: $1"
       STATUS=1
      fi
    done
  fi
  log_end_msg ${STATUS:-0}

  ;;
stop)
  log_daemon_msg "Stopping $DESC"

  if test -z "$2" ; then
    for PIDFILE in `ls /run/openvpn/*.pid 2> /dev/null`; do
      NAME=`echo $PIDFILE | cut -c14-`
      NAME=${NAME%%.pid}
      stop_vpn
      log_progress_msg "$NAME"
    done
  else
    while shift ; do
      [ -z "$1" ] && break
      if test -e /run/openvpn/$1.pid ; then
        PIDFILE=`ls /run/openvpn/$1.pid 2> /dev/null`
        NAME=`echo $PIDFILE | cut -c14-`
        NAME=${NAME%%.pid}
        stop_vpn
        log_progress_msg "$NAME"
      else
        log_failure_msg " (failure: No such VPN is running: $1)"
      fi
    done
  fi
  log_end_msg 0
  ;;
# Only 'reload' running VPNs. New ones will only start with 'start' or 'restart'.
reload|force-reload)
 log_daemon_msg "Reloading $DESC"
  for PIDFILE in `ls /run/openvpn/*.pid 2> /dev/null`; do
    NAME=`echo $PIDFILE | cut -c14-`
    NAME=${NAME%%.pid}
# If openvpn if running under a different user than root we'll need to restart
    if egrep '^[[:blank:]]*user[[:blank:]]' $CONFIG_DIR/$NAME.conf > /dev/null 2>&1 ; then
      stop_vpn
      start_vpn
      log_progress_msg "(restarted)"
    else
      kill -HUP `cat $PIDFILE` || true
    log_progress_msg "$NAME"
    fi
  done
  log_end_msg 0
  ;;

# Only 'soft-restart' running VPNs. New ones will only start with 'start' or 'restart'.
soft-restart)
 log_daemon_msg "$DESC sending SIGUSR1"
  for PIDFILE in `ls /run/openvpn/*.pid 2> /dev/null`; do
    NAME=`echo $PIDFILE | cut -c14-`
    NAME=${NAME%%.pid}
    kill -USR1 `cat $PIDFILE` || true
    log_progress_msg "$NAME"
  done
  log_end_msg 0
 ;;

restart)
  shift
  $0 stop ${@}
  $0 start ${@}
  ;;
cond-restart)
  log_daemon_msg "Restarting $DESC."
  for PIDFILE in `ls /run/openvpn/*.pid 2> /dev/null`; do
    NAME=`echo $PIDFILE | cut -c14-`
    NAME=${NAME%%.pid}
    stop_vpn
    start_vpn
  done
  log_end_msg 0
  ;;
status)
  GLOBAL_STATUS=0
  if test -z "$2" ; then
    # We want status for all defined VPNs.
    # Returns success if all autostarted VPNs are defined and running
    if test "x$AUTOSTART" = "xnone" ; then
      # Consider it a failure if AUTOSTART=none
      log_warning_msg "No VPN autostarted"
      GLOBAL_STATUS=1
    else
      if ! test -z "$AUTOSTART" -o "x$AUTOSTART" = "xall" ; then
        # Consider it a failure if one of the autostarted VPN is not defined
        for VPN in $AUTOSTART ; do
          if ! test -f $CONFIG_DIR/$VPN.conf ; then
            log_warning_msg "VPN '$VPN' is in AUTOSTART but is not defined"
            GLOBAL_STATUS=1
          fi
        done
      fi
    fi
    for CONFIG in `cd $CONFIG_DIR; ls *.conf 2> /dev/null`; do
      NAME=${CONFIG%%.conf}
      # Is it an autostarted VPN ?
      if test -z "$AUTOSTART" -o "x$AUTOSTART" = "xall" ; then
        AUTOVPN=1
      else
        if test "x$AUTOSTART" = "xnone" ; then
          AUTOVPN=0
        else
          AUTOVPN=0
          for VPN in $AUTOSTART; do
            if test "x$VPN" = "x$NAME" ; then
              AUTOVPN=1
            fi
          done
        fi
      fi
      if test "x$AUTOVPN" = "x1" ; then
        # If it is autostarted, then it contributes to global status
        status_of_proc -p /run/openvpn/${NAME}.pid openvpn "VPN '${NAME}'" || GLOBAL_STATUS=1
      else
        status_of_proc -p /run/openvpn/${NAME}.pid openvpn "VPN '${NAME}' (non autostarted)" || true
      fi
    done
  else
    # We just want status for specified VPNs.
    # Returns success if all specified VPNs are defined and running
    while shift ; do
      [ -z "$1" ] && break
      NAME=$1
      if test -e $CONFIG_DIR/$NAME.conf ; then
        # Config exists
        status_of_proc -p /run/openvpn/${NAME}.pid openvpn "VPN '${NAME}'" || GLOBAL_STATUS=1
      else
        # Config does not exist
        log_warning_msg "VPN '$NAME': missing $CONFIG_DIR/$NAME.conf file !"
        GLOBAL_STATUS=1
      fi
    done
  fi
  exit $GLOBAL_STATUS
  ;;
*)
  echo "Usage: $0 {start|stop|reload|restart|force-reload|cond-restart|soft-restart|status}" >&2
  exit 1
  ;;
esac

exit 0

# vim:set ai sts=2 sw=2 tw=0:
