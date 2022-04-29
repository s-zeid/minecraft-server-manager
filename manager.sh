#!/bin/bash
# vim: set fdm=marker:

# Minecraft server management script
# 
# Copyright (c) 2013-2019 S. Zeid.  Released under the X11 License.  
# <https://code.s.zeid.me/minecraft-server-manager>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
# 
# Except as contained in this notice, the name(s) of the above copyright holders
# shall not be used in advertising or otherwise to promote the sale, use or
# other dealings in this Software without prior written authorization.

SCRIPT=$0
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_PID=$$

# Configuration file parsing #########################################{{{1

# Select user configuration file, using the -c/--config command-line
# flag first, then the default value `./manager.conf`, where .
# is the directory in which this script is contained.
if grep -qe '^-\(c\|-config=\).\+' <<< "$1"; then
 USER_CONFIG_FILE=$(sed -e 's/^-\(c\|-config=\)//' <<< "$1")
 shift
elif [ "$1" = "-c" -o "$1" = "--config" ]; then
 USER_CONFIG_FILE=$2
 shift 2
fi
if [ -z "$USER_CONFIG_FILE" ]; then
 USER_CONFIG_FILE="$SCRIPT_DIR"/manager.conf
fi

# For each array-type configuration option, declare two arrays:
# a defaults one and a user one.  The user one will then be
# copied to the end of the defaults one, and the defaults array
# will then be re-used as the final value.
declare -a JAVA_OPTS JAVA_OPTS_USER
declare -a GAME_OPTS GAME_OPTS_USER
declare -a EXTRA_WINDOWS EXTRA_WINDOWS_USER
declare -a PATH_VARS PATH_VARS_USER

# Convenience functions to add values to the arrays.  These are
# used in the config files.
function default_java_opt() {
 JAVA_OPTS[${#JAVA_OPTS[@]}]="$1"
}
function java_opt() {
 JAVA_OPTS_USER[${#JAVA_OPTS_USER[@]}]="$1"
}
function default_game_opt() {
 GAME_OPTS[${#GAME_OPTS[@]}]="$1"
}
function game_opt() {
 GAME_OPTS_USER[${#GAME_OPTS_USER[@]}]="$1"
}
function default_extra_window() {
 EXTRA_WINDOWS[${#EXTRA_WINDOWS[@]}]="$1"
}
function extra_window() {
 EXTRA_WINDOWS_USER[${#EXTRA_WINDOWS_USER[@]}]="$1"
}

# Load user settings
[ -e "$USER_CONFIG_FILE" ] && . "$USER_CONFIG_FILE"

# Load default settings
. "$SCRIPT_DIR"/manager.conf.defaults

# Convert JAVA_PATH to absolute path
if ! (printf '%s\n' "$JAVA_PATH" | grep -q -e '/'); then
 JAVA_PATH=$(which "$JAVA_PATH")
fi
abspath() {
 printf '%s\n' \
  "$(cd "$(dirname -- "$1")"; printf '%s' "$(pwd)")/$(basename -- "$1")"
}
JAVA_PATH=$(abspath "$JAVA_PATH")

# Append user Java options to $JAVA_OPTS
# so that the defaults come first
for (( i = 0; i < ${#JAVA_OPTS_USER[@]}; i++ )); do
 default_java_opt "${JAVA_OPTS_USER[i]}"
done
# Append user game options to $GAME_OPTS
# so that the defaults come first
for (( i = 0; i < ${#GAME_OPTS_USER[@]}; i++ )); do
 default_game_opt "${GAME_OPTS_USER[i]}"
done
# Append user extra windows to $EXTRA_WINDOWS
# so that the defaults come first
for (( i = 0; i < ${#EXTRA_WINDOWS_USER[@]}; i++ )); do
 default_extra_window "${EXTRA_WINDOWS_USER[i]}"
done

# Remove "The" and "server" from STATUS_LEFT
STATUS_LEFT=${STATUS_LEFT#The }
STATUS_LEFT=${STATUS_LEFT#the }
STATUS_LEFT=${STATUS_LEFT% server}

# Helper functions ###################################################{{{1

function echo_error() {
 echo "$SCRIPT: error: $@"
}
function echo_warning() {
 echo "$SCRIPT: warning: $@"
}

function tmux() {
 env tmux -L "$SOCKET_NAME" "$@"
}

function tmux-option() {
 if [ "$1" = "--debug" -o "$MINECRAFT_SERVER_MANAGER_DEBUG" = "1" ]; then
  shift
  tmux set-option -t "$SESSION_NAME" "$@"
 else
  tmux set-option -t "$SESSION_NAME" "$@" > /dev/null
 fi
}

function setup-tmux() {
 tmux bind-key -n C-c detach-client
 tmux-option status-bg "$STATUS_BG"
 tmux-option status-fg "$STATUS_FG"
 tmux-option status-position "$STATUS_POSITION"
 tmux-option status-left "$STATUS_LEFT "
 tmux-option status-left-length 12
 tmux-option status-right "$STATUS_RIGHT"
 tmux-option status-right-length 37
 tmux-option -w window-status-current-format 'on #H'
 tmux-option -w window-status-format 'on #H (window #I)'
 tmux-option -w window-status-separator ' '
}

function manager() {
 "$SCRIPT" "$@"
}

function is_running() {
 if [ -f "$PID_FILE" ]; then
  if (ps -p $(cat "$PID_FILE" 2>/dev/null) -o args= | grep -q -F "$JAR_PATH"); then
   # is running
   return 0
  else
   # the PID file does not exist
   return 2
  fi
 else
  # not running
  return 1
 fi
 # unknown error
 return 127
}

function watch_loop() {
 while true; do
  if is_running; then
   (tmux wait-for "$RANDOM$$$TMUX_NAME$RANDOM$SCRIPT_PID")
  else
   if [ $# -gt 0 ]; then
    "$@"
   fi
   break
  fi
 done
}

# Commands ###########################################################{{{1

cd "$BASE_PATH"

case "$1" in
 foreground)
  is_running; R=$?
  if [ $R -ne 0 ]; then
   manager start; X=$?
   if [ $X -ne 0 ]; then
    echo_error "could not start $FRIENDLY_NAME"
    exit $X
   fi
  fi
  is_running; R=$?
  if [ $R -eq 0 ]; then
   trap 'manager stop; exit' INT TERM QUIT
   watch_loop
  fi
  
  ;;
 start)
  is_running; R=$?
  if [ $R -ne 0 ]; then
   BASE_PATH_ESC="`sed -r "s/( \\\"'\\\$)/\\\\\\\\\1/g" <<< "$BASE_PATH"`"
   JAVA_PATH_ESC="`sed -r "s/( \\\"'\\\$)/\\\\\\\\\1/g" <<< "$JAVA_PATH"`"
   JAR_PATH_ESC="`sed -r "s/( \\\"'\\\$)/\\\\\\\\\1/g" <<< "$JAR_PATH"`"
   WORLD_PATH_ESC="`sed -r "s/( \\\"'\\\$)/\\\\\\\\\1/g" <<< "$WORLD_PATH"`"
   JAVA_OPTS_ESC=""
   for (( i = 0; i < ${#JAVA_OPTS[@]}; i++)); do
    JAVA_OPTS_ESC+="`sed -r "s/( \\\"'\\\$)/\\\\\\\\\1/g" <<< "${JAVA_OPTS[i]}"` "
   done
   GAME_OPTS_ESC=""
   for (( i = 0; i < ${#GAME_OPTS[@]}; i++)); do
    GAME_OPTS_ESC+="`sed -r "s/( \\\"'\\\$)/\\\\\\\\\1/g" <<< "${GAME_OPTS[i]}"` "
   done
   rm -f "$PID_FILE"
   tmux new-session -d -s "$SESSION_NAME" -n "$WINDOW_NAME" -d "cd $BASE_PATH_ESC; exec $JAVA_PATH_ESC -Xms$MIN_MEMORY -Xmx$MAX_MEMORY $JAVA_OPTS_ESC -jar $JAR_PATH_ESC -W $WORLD_PATH_ESC $GAME_OPTS_ESC"
   if [ $? -gt 0 ]; then
    exit 1
   fi
   sleep $SLEEP_AFTER_START_SECONDS
   setup-tmux
   tmux list-panes -s -t "$SESSION_NAME" -F '#{pane_pid}' | tee "$PID_FILE" > /dev/null
   for ((i = 0; i < ${#EXTRA_WINDOWS[@]}; i++)); do
    tmux new-window -d -c "$BASE_PATH" "${EXTRA_WINDOWS[i]}"
    r=$?
    if [ $r -ne 0 ]; then
     echo_warning "warning: failed to open tmux window with the command" \
                  " \`${EXTRA_WINDOW[i]}\`:  tmux exited with code $r"
    fi
   done
  else
   echo_error "$FRIENDLY_NAME is already running (PID $(cat "$PID_FILE"))."
   exit 1
  fi
  ;;
  
 stop)
  tmux send-keys -t "$SESSION_NAME" 'stop' C-m
  while true; do
   ps -p `cat "$PID_FILE" 2>/dev/null` &> /dev/null
   if [ $? -ne 0 ]; then
    break
   fi
  done
  rm -f "$PID_FILE"
  if [ -n "`tmux list-sessions 2>/dev/null`" ]; then
   tmux kill-server
  fi
  ;;
 
 status)
  is_running; R=$?
  if [ $R -eq 0 ]; then
   echo "$FRIENDLY_NAME is running (PID $(cat "$PID_FILE"))."
  elif [ $R -eq 1 ]; then
   echo "$FRIENDLY_NAME is not running."
  elif [ $R -eq 2 ]; then
   echo_error "the PID file does not exist"
  else
   echo_error "unknown error while determining server status"
  fi
  exit $R
  ;;
  
 restart)
  manager stop
  sleep 0.1
  manager start
  ;;
 
 backup)
  "$0" backup-worlds
  "$0" backup-plugins
  "$0" backup-log
  ;;
 
 backup-worlds)
  tmux send-keys -t "$SESSION_NAME" 'save-off' C-m &>/dev/null
  tmux send-keys -t "$SESSION_NAME" 'save-all' C-m &>/dev/null
  DIR="$BACKUP_PATH/worlds/`date +%Y-%m-%dT%H-%M-%S`"
  mkdir -p "$DIR"
  DIR=`cd "$DIR"; pwd`
  CURDIR="$PWD"
  cd "$WORLD_PATH"
  for world in ./*; do
   world="`basename "$world"`"
   tar -cf "$DIR/$world.tar.xz" -I "$SCRIPT_DIR/compressor" "$world"
  done
  cd "$CURDIR"
  tmux send-keys -t "$SESSION_NAME" 'save-on' C-m &>/dev/null
  ;;
 
 backup-plugins)
  tmux send-keys -t "$SESSION_NAME" 'save-off' C-m &>/dev/null
  tmux send-keys -t "$SESSION_NAME" 'save-all' C-m &>/dev/null
  DIR="$BACKUP_PATH/plugins"
  mkdir -p "$DIR"
  DIR=`cd "$DIR"; pwd`
  FILE="$DIR/plugins_`date +%Y-%m-%dT%H-%H-%S`.tar.xz"
  CURDIR="$PWD"
  cd "$(dirname "$PLUGIN_PATH")"
  tar -cJf "$FILE" "$(basename "$PLUGIN_PATH")"
  cd "$CURDIR"
  tmux send-keys -t "$SESSION_NAME" 'save-on' C-m &>/dev/null
  ;;
 
 backup-log)
  LOG="$BASE_PATH/server.log"
  DIR="$BACKUP_PATH/logs"
  mkdir -p "$DIR"
  DIR=`cd "$DIR"; pwd`
  FILE="$DIR/server_`date +%Y-%m-%dT%H-%H-%S`.log"
  cp "$LOG" "$FILE" && xz "$FILE"
  if [ $? -eq 0 ]; then
   cp /dev/null "$LOG"
   echo "Previous logs rolled to $FILE.xz" > "$LOG"
  else
   echo_error "Problem backing up server.log"
   exit 1
  fi
  ;;
 
 cmd)
  shift
  CMD=$@
  tmux send-keys -t "$SESSION_NAME" C-u "$CMD" C-m
  ;;
 
 cmd-capture)
  shift
  CMD=$@
  # $LOG_RE matches:
  # - "[yyyy-MM-dd HH:MM:SS] [message type (if present)] "
  # - "yyyy-MM-dd HH:MM:SS [message type (if present)] "
  # - "[HH:MM:SS] [message type (if present)] "
  # - "HH:MM:SS [message type (if present)] "
  # - "[HH:MM:SS message type (if present)] "
  LOG_PREFIX_RE="^(\[?([0-9]{4}-[0-9]{2}-[0-9]{2} )?[0-9]{2}:[0-9]{2}:[0-9]{2}\]?( \[?[^]]+\]?)?\]?:? )"
  LOG_START=$((`wc -l "$LOG_FILE" | cut -d' ' -f1` + 1))  # output starts here
  tmux send-keys -t "$SESSION_NAME" C-u "$CMD" C-m
  sleep "0.25" >/dev/null 2>&1 || sleep 1  # float is in quotes to trick checkbashisms(1)
  OUT="`tail -n +"$LOG_START" "$LOG_FILE" | sed -r -e "s/$LOG_PREFIX_RE//"`"  # read and remove prefix
  printf '%s\n' "$OUT"
  ;;
 
 console)
  tmux attach -t "$SESSION_NAME"
  ;;
 
 setup-tmux)
  setup-tmux
  ;;
 
 tmux-option)
  shift
  tmux-option "$@"
  ;;
 
 tmux-options)
  shift
  tmux show-options -t "$SESSION_NAME" "$@"
  ;;
 
 dump-config)
  cat <<END
# General options #

  FRIENDLY_NAME:  $FRIENDLY_NAME
      BASE_PATH:  $BASE_PATH
      JAVA_PATH:  $JAVA_PATH
       JAR_PATH:  $JAR_PATH
       PID_FILE:  $PID_FILE
       LOG_FILE:  $LOG_FILE
     WORLD_PATH:  $WORLD_PATH
    PLUGIN_PATH:  $PLUGIN_PATH
    BACKUP_PATH:  $BACKUP_PATH

# tmux options #

    STATUS_LEFT:  $STATUS_LEFT
   STATUS_RIGHT:  $STATUS_RIGHT
STATUS_POSITION:  $STATUS_POSITION
      STATUS_BG:  $STATUS_BG
      STATUS_FG:  $STATUS_FG

# Advanced tmux options #

    SOCKET_NAME:  $SOCKET_NAME
   SESSION_NAME:  $SESSION_NAME
    WINDOW_NAME:  $WINDOW_NAME
END
  ;;
 
 *)
  echo "Usage: $0 \\"
  echo "        [-c config-file|--config=config-file] \\"
  echo "        {start|stop|restart|status"
  echo "         |backup{|-worlds|-plugins|-log}"
  echo "         |cmd{|-capture}|console"
  echo "         |setup-tmux|tmux-option|tmux-options|dump-config}"
  exit 1
 
esac

exit 0
