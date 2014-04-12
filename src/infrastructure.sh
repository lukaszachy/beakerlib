# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Name: infrastructure.sh - part of the BeakerLib project
#   Description: Mounting, backup & service helpers
#
#   Author: Petr Muller <pmuller@redhat.com>
#   Author: Jan Hutar <jhutar@redhat.com>
#   Author: Petr Splichal <psplicha@redhat.com>
#   Author: Ales Zelinka <azelinka@redhat.com>
#   Author: Karel Srot <ksrot@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2008-2013 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

: <<'=cut'
=pod

=head1 NAME

BeakerLib - infrastructure - mounting, backup and service helpers

=head1 DESCRIPTION

BeakerLib functions providing checking and mounting NFS shares, backing up and
restoring files and controlling running services.

=head1 FUNCTIONS

=cut

. $BEAKERLIB/logging.sh
. $BEAKERLIB/testing.sh

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Internal Stuff
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

__INTERNAL_rlRunsInBeaker() {
	if [ -n "$JOBID" ] && [ -n "$TESTID" ]
	then
	  return 0
	else
	  return 1
	fi
}

__INTERNAL_CheckMount(){
    local MNTPATH="$1"
    local MNTHOST="$2"

    # if a host was specified, the semantics is "is PATH mounted on HOST?"
    # if a host is not specified, the semantics is "is PATH mounted somewhere?"
    if [ -z "$MNTHOST" ]
    then
      mount | grep "on ${MNTPATH%/} type"
      return $?
    else
      mount | grep "on ${MNTPATH%/} type" | grep -E "^$MNTHOST[ :/]"
      return $?
    fi
}

__INTERNAL_Mount(){
    local SERVER=$1
    local MNTPATH=$2
    local WHO=$3

    if __INTERNAL_CheckMount "$MNTPATH"
    then
        rlLogInfo "$WHO already mounted: success"
        return 0
    elif [ ! -d "$MNTPATH" ]
    then
        rlLogInfo "$WHO creating directory $MNTPATH"
        mkdir -p "$MNTPATH"
    fi
    rlLogInfo "$WHO mounting $SERVER on $MNTPATH"
    mount "$SERVER" "$MNTPATH"
    if [ $? -eq 0 ]
    then
        rlLogInfo "$WHO success"
        return 0
    else
        rlLogWarning "$WHO failure"
        return 1
    fi
}

__INTERNAL_rlCleanupGenFinal()
{
    local newfinal="$__INTERNAL_CLEANUP_FINAL".tmp
    if [ -e "$newfinal" ]; then
        rm -f "$newfinal" || return 1
    fi
    touch "$newfinal" || return 1

    # head
    cat > "$newfinal" <<EOF
#!/bin/bash
EOF

    # environment
    # - env variables (incl. BEAKERLIB_DIR)
    #   NOTE: even works around possible single quotes in variables
    env | sed -r -e "s/'/'\\\''/g" -e "s/^([^=]+)=(.*)$/export \1='\2'/" \
         >> "$newfinal"
    # - functions
    declare -f >> "$newfinal"

    # journal/phase start
    cat >> "$newfinal" <<EOF
rlJournalStart
rlPhaseStartCleanup
EOF

    # body
    cat "$__INTERNAL_CLEANUP_BUFF" >> "$newfinal"

    # tail
    cat >> "$newfinal" <<EOF
rlPhaseEnd
rlJournalEnd
EOF

    chmod +x "$newfinal" || return 1
    # atomic move
    mv "$newfinal" "$__INTERNAL_CLEANUP_FINAL" || return 1
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# rlMount
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head2 Mounting

=head3 rlMount

Create mount point (if neccessary) and mount a NFS share.

    rlMount server share mountpoint

=over

=item server

NFS server hostname.

=item share

Shared directory name.

=item mountpoint

Local mount point.

=back

Returns 0 if mounting the share was successful.

=cut

rlMount() {
    local SERVER=$1
    local REMDIR=$2
    local LOCDIR=$3
    __INTERNAL_Mount "$SERVER:$REMDIR" "$LOCDIR" "[MOUNT $LOCDIR]"
    return $?
}

# backward compatibility
rlMountAny() {
    rlLogWarning "rlMountAny is deprecated and will be removed in the future. Use 'rlMount' instead"
    rlMount "$1" "$2" "$2";
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# rlCheckMount
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head3 rlCheckMount

Check either if a directory is a mountpoint, if it is a mountpoint to a
specific server, or if it is a mountpoint to a specific export on a specific
server.

    rlCheckMount mountpoint
    rlCheckMount server mountpoint
    rlCheckMount server share mountpoint

=over

=item mountpoint

Local mount point.

=item server

NFS server hostname

=item share

Shared direcotry name

=back

With one parameter, returns 0 when specified directory exists and is a
mountpoint. With two parameters, returns 0 when specific directory exists, is a
mountpoint and an export from specific server is mounted there. With three
parameters, returns 0 if a specific shared directory is mounted on a given
server on a given mountpoint

=cut

rlCheckMount() {
    local LOCPATH=""
    local REMPATH=""
    local SERVER=""
    local MESSAGE="a mount point"

    case $# in
      1)  LOCPATH="$1" ;;
      2)  LOCPATH="$2"
          SERVER="$1"
          MESSAGE="$MESSAGE to $SERVER" ;;
      3)  LOCPATH="$3"
          REMPATH=":$2"
          SERVER="$1"
          MESSAGE="$MESSAGE to ${SERVER}${REMPATH}" ;;
      *)  rlLogError "rlCheckMount: Bad parameter count"
          return 1 ;;
    esac

    if __INTERNAL_CheckMount "${LOCPATH}" "${SERVER}${REMPATH}"; then
        rlLogDebug "rlCheckMount: Directory $LOCPATH is $MESSAGE"
        return 0
    else
        rlLogDebug "rlCheckMount: Directory $LOCPATH is not $MESSAGE"
        return 1
    fi
}

# backward compatibility
rlAnyMounted() {
    rlLogWarning "rlAnyMounted is deprecated and will be removed in the future. Use 'rlCheckMount' instead"
    rlCheckMount "$1" "$2" "$2"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# rlAssertMount
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head3 rlAssertMount

Assertion making sure that given directory is a mount point, if it is a
mountpoint to a specific server, or if it is a mountpoint to a specific export
on a specific server.

    rlAssertMount mountpoint
    rlAssertMount server mountpoint
    rlAssertMount server share mountpoint

=over

=item mountpoint

Local mount point.

=item server

NFS server hostname

=item share

Shared directory name

=back

With one parameter, returns 0 when specified directory exists and is a
mountpoint. With two parameters, returns 0 when specific directory exists, is a
mountpoint and an export from specific server is mounted there. With three
parameters, returns 0 if a specific shared directory is mounted on a given
server on a given mountpoint. Asserts PASS when the condition is true.

=cut

rlAssertMount() {
    local LOCPATH=""
    local REMPATH=""
    local SERVER=""
    local MESSAGE="a mount point"

    case $# in
      1)  LOCPATH="$1" ;;
      2)  LOCPATH="$2"
          SERVER="$1"
          MESSAGE="$MESSAGE to $SERVER" ;;
      3)  LOCPATH="$3"
          REMPATH=":$2"
          SERVER="$1"
          MESSAGE="$MESSAGE to ${SERVER}${REMPATH}" ;;
      *)  rlLogError "rlAssertMount: Bad parameter count"
          return 1 ;;
    esac

    __INTERNAL_CheckMount "${LOCPATH}" "${SERVER}${REMPATH}"
    __INTERNAL_ConditionalAssert "Mount assert: Directory $LOCPATH is $MESSAGE" $?
    return $?
}



# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# rlFileBackup
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head2 Backup and Restore

=head3 rlFileBackup

Create a backup of files or directories (recursive). Can be used
multiple times to add more files to backup. Backing up an already
backed up file overwrites the original backup.

    rlFileBackup [--clean] [--namespace name] file [file...]

=over

=item --clean

If this option is provided (have to be first option of the command),
then file/dir backuped using this command (provided in next
options) will be (recursively) removed before we will restore it.

=item --namespace name

Specifies the namespace to use.
Namespaces can be used to separate backups and their restoration.

=item file

Files and/or directories to be backed up.

=back

Returns 0 if the backup was successful.

=head4 Example with --clean:

    touch cleandir/aaa
    rlFileBackup --clean cleandir/
    touch cleandir/bbb
    ls cleandir/
    aaa   bbb
    rlFileRestore
    ls cleandir/
    aaa

=cut

rlFileBackup() {
    local backup status file path dir failed selinux acl

    local OPTS clean="" namespace=""

    # getopt will cut off first long opt when no short are defined
    OPTS=$(getopt -o "cn:" -l "clean,namespace:" -- "$@")
    [ $? -ne 0 ] && return 1

    eval set -- "$OPTS"
    while true; do
        case "$1" in
            '--clean') shift; clean=1 ;;
            '--namespace') shift; namespace="$1"; shift ;;
            --) shift; break ;;
        esac
    done;

    # check parameter sanity
    if [ -z "$1" ]; then
        rlLogError "rlFileBackup: Nothing to backup... supply a file or dir"
        return 2
    fi

    # check if we have '--clean' option and save items if we have
    if [ "$clean" ]; then
        rlLogDebug "rlFileBackup: Adding '$@' to the clean list"
        local tmp="__INTERNAL_BACKUP_CLEAN_$(echo -n "$namespace" | od -A n -t x1 -v | tr -d ' ')"
        local file
        for file in "$@"; do
            ###rlLogDebug "rlFileBackup: ... '$@'"
            if [ -z "${!tmp}" ]; then
                eval $tmp="\$file"
            else
                eval $tmp="\$$tmp\\\n\$file"
            fi
        done
    fi

    # set the backup dir
    if [ -z "$BEAKERLIB_DIR" ]; then
        rlLogError "rlFileBackup: BEAKERLIB_DIR not set, run rlJournalStart first"
        return 3
    fi

    # backup dir to use, append namespace if defined
    backup="$BEAKERLIB_DIR/backup${namespace:+-$namespace}"

    # create backup dir (unless it already exists)
    if [ -d "$backup" ]; then
        rlLogDebug "rlFileBackup: Backup dir ready: $backup"
    else
        if mkdir "$backup"; then
            rlLogDebug "rlFileBackup: Backup dir created: $backup"
        else
            rlLogError "rlFileBackup: Creating backup dir failed"
            return 4
        fi
    fi

    # do the actual backup
    status=0
    # detect selinux & acl support
    if selinuxenabled
    then
      selinux=true
    else
      selinux=false
    fi

    if setfacl -m u:root:rwx $BEAKERLIB_DIR &>/dev/null
    then
      acl=true
    else
      acl=false
    fi

    local file
    for file in "$@"; do
        # convert relative path to absolute, remove trailing slash
        file="$(echo "$file" | sed "s|^\([^/]\)|$PWD/\1|" | sed 's|/$||')"
        # follow symlinks in parent dir
        path="$(dirname "$file")"
        path="$(readlink -n -f "$path")"
        file="$path/$(basename "$file")"

        # bail out if the file does not exist
        if ! [ -e "$file" ]; then
            rlLogError "rlFileBackup: File $file does not exist."
            status=8
            continue
        fi

        # create path
        if ! mkdir -p "${backup}${path}"; then
            rlLogError "rlFileBackup: Cannot create ${backup}${path} directory."
            status=5
            continue
        fi

        # copy files
        if ! cp -fa "$file" "${backup}${path}"; then
            rlLogError "rlFileBackup: Failed to copy $file to ${backup}${path}."
            status=6
            continue
        fi

        # preserve path attributes
        dir="$path"
        failed=false
        while true; do
            $acl && { getfacl --absolute-names "$dir" | setfacl --set-file=- "${backup}${dir}" || failed=true; }
            $selinux && { chcon --reference "$dir" "${backup}${dir}" || failed=true; }
            chown --reference "$dir" "${backup}${dir}" || failed=true
            chmod --reference "$dir" "${backup}${dir}" || failed=true
            touch --reference "$dir" "${backup}${dir}" || failed=true
            [ "$dir" == "/" ] && break
            dir=$(dirname "$dir")
        done
        if $failed; then
            rlLogError "rlFileBackup: Failed to preserve all attributes for backup path ${backup}${path}."
            status=7
            continue
        fi

        # everything ok
        rlLogDebug "rlFileBackup: $file successfully backed up to $backup"
    done

    return $status
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# rlFileRestore
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head3 rlFileRestore

Restore backed up files to their original location.
C<rlFileRestore> does not remove new files appearing after backup
has been made.  If you don\'t want to leave anything behind just
remove the whole original tree before running C<rlFileRestore>,
or see C<--clean> option of C<rlFileBackup>.

    rlFileRestore [--namespace name]

=over

=item --namespace name

Specifies the namespace to use.
Namespaces can be used to separate backups and their restoration.

=back

Returns 0 if backup dir is found and files are restored successfully.

=cut

rlFileRestore() {
    local OPTS namespace=""

    # getopt will cut off first long opt when no short are defined
    OPTS=$(getopt -o "n:" -l "namespace:" -- "$@")
    [ $? -ne 0 ] && return 1

    eval set -- "$OPTS"
    while true; do
        case "$1" in
            '--namespace') shift; namespace="$1"; shift ;;
            --) shift; break ;;
        esac
    done;

    # check for backup dir first, append namespace if defined
    backup="$BEAKERLIB_DIR/backup${namespace:+-$namespace}"
    if [ -d "$backup" ]; then
        rlLogDebug "rlFileRestore: Backup dir ready: $backup"
    else
        rlLogError "rlFileRestore: Cannot find backup in $backup"
        return 1
    fi

    # clean up if required
    local tmp="__INTERNAL_BACKUP_CLEAN_$(echo -n "$namespace" | od -A n -t x1 -v | tr -d ' ')"
    if [ -n "${!tmp}" ]; then
        local oldIFS="$IFS"
        IFS=$'\x0A'
        local path
        for path in $(echo -e "${!tmp}"); do
            if rm -rf "$path"; then
                rlLogDebug "rlFileRestore: Cleaning $path successful"
            else
                rlLogError "rlFileRestore: Failed to clean $path"
            fi
        done
        IFS="$oldIFS"
    fi

    # if destination is a symlink, remove the file first
    local filecheck
    for filecheck in $( find "$backup" | cut --complement -b 1-"${#backup}")
    do
      if [ -L "/$filecheck" ]
      then
        rm -f "/$filecheck"
      fi
    done

    # restore the files
    if cp -fa "$backup"/* /
    then
      rlLogDebug "rlFileRestore: Restoring files from $backup successful"
    else
      rlLogError "rlFileRestore: Failed to restore files from $backup"
      return 2
    fi

    return 0
}



# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# rlServiceStart
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head2 Services

Following routines implement comfortable way how to start/stop
system services with the possibility to restore them to their
original state after testing.

=head3 rlServiceStart

Make sure the given C<service> is running with fresh
configuration. (Start it if it is stopped and restart if it is
already running.) In addition, when called for the first time, the
current state is saved so that the C<service> can be restored to
its original state when testing is finished, see
C<rlServiceRestore>.

    rlServiceStart service [service...]

=over

=item service

Name of the service(s) to start.

=back

Returns number of services which failed to start/restart; thus
zero is returned when everything is OK.

=cut

rlServiceStart() {
    # at least one service has to be supplied
    if [ $# -lt 1 ]; then
        rlLogError "rlServiceStart: You have to supply at least one service name"
        return 99
    fi

    local failed=0

    local service
    for service in "$@"; do
        service $service status
        local status=$?

        # if the original state has not been saved yet, do it now!
        local wasRunning="__INTERNAL_SERVICE_STATE_${service//[^a-zA-Z]/}"
        if [ -z "${!wasRunning}" ]; then
            # was running
            if [ $status == 0 ]; then
                rlLogDebug "rlServiceStart: Original state of $service saved (running)"
                eval $wasRunning=true
            # was stopped
            elif [ $status == 3 ]; then
                rlLogDebug "rlServiceStart: Original state of $service saved (stopped)"
                eval $wasRunning=false
            # weird exit status (warn and suppose stopped)
            else
                rlLogWarning "rlServiceStart: service $service status returned $status"
                rlLogWarning "rlServiceStart: Guessing that original state of $service is stopped"
                eval $wasRunning=false
            fi
        fi

        # if the service is running, stop it first
        if [ $status == 0 ]; then
            rlLog "rlServiceStart: Service $service already running, stopping first."
            if ! service $service stop; then
                # if service stop failed, inform the user and provide info about service status
                rlLogWarning "rlServiceStart: Stopping service $service failed."
                rlLogWarning "Status of the failed service:"
                service $service status 2>&1 | while read line; do rlLog "  $line"; done
                ((failed++))
            fi
        fi

        # finally let's start the service!
        if service $service start; then
            rlLog "rlServiceStart: Service $service started successfully"
        else
            # if service start failed, inform the user and provide info about service status
            rlLogError "rlServiceStart: Starting service $service failed"
            rlLogError "Status of the failed service:"
            service $service status 2>&1 | while read line; do rlLog "  $line"; done
            ((failed++))
        fi
    done

    return $failed
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# rlServiceStop
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head3 rlServiceStop

Make sure the given C<service> is stopped. Stop it if it is
running and do nothing when it is already stopped. In addition,
when called for the first time, the current state is saved so that
the C<service> can be restored to its original state when testing
is finished, see C<rlServiceRestore>.

    rlServiceStop service [service...]

=over

=item service

Name of the service(s) to stop.

=back

Returns number of services which failed to become stopped; thus
zero is returned when everything is OK.

=cut

rlServiceStop() {
    # at least one service has to be supplied
    if [ $# -lt 1 ]; then
        rlLogError "rlServiceStop: You have to supply at least one service name"
        return 99
    fi

    local failed=0

    local service
    for service in "$@"; do
        service $service status
        local status=$?

        # if the original state has not been saved yet, do it now!
        local wasRunning="__INTERNAL_SERVICE_STATE_${service//[^a-zA-Z]/}"
        if [ -z "${!wasRunning}" ]; then
            # was running
            if [ $status == 0 ]; then
                rlLogDebug "rlServiceStop: Original state of $service saved (running)"
                eval $wasRunning=true
            # was stopped
            elif [ $status == 3 ]; then
                rlLogDebug "rlServiceStop: Original state of $service saved (stopped)"
                eval $wasRunning=false
            # weird exit status (warn and suppose stopped)
            else
                rlLogWarning "rlServiceStop: service $service status returned $status"
                rlLogWarning "rlServiceStop: Guessing that original state of $service is stopped"
                eval $wasRunning=false
            fi
        fi

        # if the service is stopped, do nothing
        if [ $status == 3 ]; then
            rlLogDebug "rlServiceStop: Service $service already stopped, doing nothing."
            continue
        fi

        # finally let's stop the service!
        if service $service stop; then
            rlLogDebug "rlServiceStop: Service $service stopped successfully"
        else
            # if service stop failed, inform the user and provide info about service status
            rlLogError "rlServiceStop: Stopping service $service failed"
            rlLogError "Status of the failed service:"
            service $service status 2>&1 | while read line; do rlLog "  $line"; done
            ((failed++))
        fi
    done

    return $failed
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# rlServiceRestore
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head3 rlServiceRestore

Restore given C<service> into its original state (before the first
C<rlServiceStart> or C<rlServiceStop> was called).

    rlServiceRestore service [service...]

=over

=item service

Name of the service(s) to restore to original state.

=back

Returns number of services which failed to get back to their
original state; thus zero is returned when everything is OK.

=cut

rlServiceRestore() {
    # at least one service has to be supplied
    if [ $# -lt 1 ]; then
        rlLogError "rlServiceRestore: You have to supply at least one service name"
        return 99
    fi

    local failed=0

    local service
    for service in "$@"; do
        # if the original state has not been saved, then something's wrong
        local wasRunning="__INTERNAL_SERVICE_STATE_${service//[^a-zA-Z]/}"
        if [ -z "${!wasRunning}" ]; then
            rlLogError "rlServiceRestore: Original state of $service was not saved, nothing to do"
            ((failed++))
            continue
        fi

        if ${!wasRunning}
        then
          wasStopped=false
        else
          wasStopped=true
        fi

        rlLogDebug "rlServiceRestore: Restoring $service to original state ($( if $wasStopped; then echo "stopped"; else echo "running"; fi ))"

        # find out current state
        service $service status
        local status=$?
        if [ $status == 0 ]; then
            isStopped=false
        elif [ $status == 3 ]; then
            isStopped=true
        # weird exit status (warn and suppose stopped)
        else
            rlLogWarning "rlServiceRestore: service $service status returned $status"
            rlLogWarning "rlServiceRestore: Guessing that current state of $service is stopped"
            isStopped=true
        fi

        # if stopped and was stopped -> nothing to do
        if $isStopped; then
            if $wasStopped; then
                rlLogDebug "rlServiceRestore: Service $service is already stopped, doing nothing"
                continue
            fi
        # if running, we have to stop regardless original state
        else
            if service $service stop; then
                rlLogDebug "rlServiceRestore: Service $service stopped successfully"
            else
                # if service stop failed, inform the user and provide info about service status
                rlLogError "rlServiceRestore: Stopping service $service failed"
                rlLogError "Status of the failed service:"
                service $service status 2>&1 | while read line; do rlLog "  $line"; done
                ((failed++))
                continue
            fi
        fi

        # if was running then start again
        if ! $wasStopped; then
            if service $service start; then
                rlLogDebug "rlServiceRestore: Service $service started successfully"
            else
                # if service start failed, inform the user and provide info about service status
                rlLogError "rlServiceRestore: Starting service $service failed"
                rlLogError "Status of the failed service:"
                service $service status 2>&1 | while read line; do rlLog "  $line"; done
                ((failed++))
                continue
            fi
        fi
    done

    return $failed
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# rlSEBooleanOn
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head2 SELinux Boolean

Following routines implement comfortable way how to set and unset
SELinux booleans with the possibility to restore them to their
original state after testing.

=head3 rlSEBooleanOn

Set the given SELinux boolean(s) to true. In addition, when called
for the first time, the current state is saved so that the boolean
can be restored to its original state when testing is finished, see
C<rlSEBooleanRestore>.

    rlSEBooleanOn boolean [boolean...]

=over

=item boolean

SELinux boolean to set to true

=back

Returns number of booleans which failed to be set. Therefore, 0 is
returned in the case of success.

=cut

rlSEBooleanOn() {
  if [ -z "$1" ]
  then
    rlLogError "rlSEBooleanOn: Missing arguments"
    return 1
  fi

  local FAILURES=0
  local STATUSFILE="$BEAKERLIB_DIR/sebooleans" && touch "$STATUSFILE"
  rlLog "rlSEBooleanOn: Setting SELinux booleans on: $*"
  while [ -n "$1" ]
  do
    # if we didn't save the status yet, save it now
	  grep -q "^$1 " "$STATUSFILE" ||  getsebool "$1" >> "$STATUSFILE"
	  # now switch the boolean on
	  if ! setsebool "$1" on
    then
      FAILURES=$(( FAILURES + 1 ))
      rlLogError "rlSEBooleanOn: Setting boolean to true failed: $1"
    fi
	  shift
  done

  return $FAILURES
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# rlSEBooleanOff
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head3 rlSEBooleanOff

Set the given SELinux boolean(s) to false. In addition, when called
for the first time, the current state is saved so that the boolean
can be restored to its original state when testing is finished, see
C<rlSEBooleanRestore>.

    rlSEBooleanOff boolean [boolean...]

=over

=item boolean

SELinux boolean to set to false

=back

Returns number of booleans which failed to be set. Therefore, 0 is
returned in the case of success.

=cut

rlSEBooleanOff() {
  if [ -z "$1" ]
  then
    rlLogError "rlSEBooleanOff: Missing arguments"
    return 1
  fi

  local FAILURES=0
  local STATUSFILE="$BEAKERLIB_DIR/sebooleans" && touch "$STATUSFILE"
  rlLog "rlSEBooleanOff: Setting SELinux booleans off: $*"

  while [ -n "$1" ]
  do
    # if we didn't save the status yet, save it now
    grep -q "^$1 " "$STATUSFILE" || getsebool "$1" >> "$STATUSFILE"
    # now switch the boolean on
    if ! setsebool "$1" off
    then
      FAILURES=$(( FAILURES + 1 ))
      rlLogError "rlSEBooleanOn: Setting boolean to true failed: $1"
    fi
    shift
  done

  return $FAILURES
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# rlSEBooleanRestore
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head3 rlSEBooleanRestore

Restore given C<boolean> into its original state (before the first
C<rlSEBooleanOn> or C<rlSEBooleanOff> was called). If no boolean is
provided in an argument, all booleans modified with previous 
C<rlSEBooleanOn> or C<rlSEBooleanOff> calls are restored.

    rlSEBooleanRestore [boolean...]

=over

=item boolean

SELinux boolean(s) to restore to original state.

=back

Returns number of booleans which failed to get back to their
original state; thus zero is returned when everything is OK.

=cut

rlSEBooleanRestore() {
  local FAILURES=0
  local STATUSFILE="$BEAKERLIB_DIR/sebooleans"
  local RECORD

  if [ ! -f "$STATUSFILE" ]
  then
    rlLogError "Cannot restore SELinux booleans, saved states are not available"
    return 99
  fi

  if [ -z "$1" ]
  then
    # no booleans specified, restoring all booleans
    rlLog "rlSEBooleanRestore: Restoring all used SELinux booleans"
    while read RECORD
    do
      # restore original boolean status saved in a STATUSFILE
      local BOOLEAN="$( echo "$RECORD" | cut -d ' ' -f 1 )"
      local STATE="$( echo "$RECORD" | cut -d ' ' -f 3 )"
      if ! setsebool "$BOOLEAN" "$STATE"
      then
        FAILURES=$(( FAILURES + 1 ))
        rlLogError "rlSEBooleanRestore: Failed to restore a state of a boolean: $BOOLEAN"
      fi
    done < $STATUSFILE
  else
    # restoring only specified booleans
    rlLog "rlSEBooleanRestore: Restoring original status: $*"
    while [ -n "$1" ]
    do
      # process all passed booleans
      RECORD="$( grep "^$1 " "$STATUSFILE" )"
      if [ -z "$RECORD" ]
      then
        FAILURES=$(( FAILURES + 1 ))
        rlLogError "rlSEBooleanRestore: Failed to restore SELinux boolean $1, original state was not saved"
      else
        # restore original boolean status saved in a STATUSFILE
        local BOOLEAN="$( echo "$RECORD" | cut -d ' ' -f 1 )"
        local STATE="$( echo "$RECORD" | cut -d ' ' -f 3 )"
        if ! setsebool "$BOOLEAN" "$STATE"
        then
          FAILURES=$(( FAILURES + 1 ))
          rlLogError "rlSEBooleanRestore: Failed to restore a state of a boolean: $BOOLEAN"
        fi
      fi
      shift
    done
  fi

  return $FAILURES
}

: <<'=cut'
=pod

=head2 Cleanup management

Cleanup management works with a so-called cleanup buffer, which is a temporary
representation of what should be run at cleanup time, and a final cleanup
script (executable), which is generated from this buffer and wraps it using
BeakerLib essentials (journal initialization, cleanup phase, ...).
The cleanup script must always be updated on an atomic basis (filesystem-wise)
to allow an asynchronous execution by a third party (ie. test watcher).

The test watcher usage is mandatory for the cleanup management system to work
properly as it is the test watcher that executes the actual cleanup script.
Limited, catastrophe-avoiding mechanism is in place even when the test is not
run in test watcher, but that should be seen as a backup and such situation
is to be avoided whenever possible.

Since the cleanup script runs as a separate script, the environment
IS NOT SHARED, except for BEAKERLIB_DIR, which is exported explicitly upon
cleanup script generation - that means no other variables are shared between
the test and the cleanup script, therefore make sure to add only fully expanded
strings, not variable names.

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# rlCleanupAppend
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head3 rlCleanupAppend

Appends a string to the cleanup buffer and recreates the cleanup script.

    rlCleanupAppend string

=over

=back

Returns 0 if the operation was successful, 1 otherwise.

=cut

rlCleanupAppend() {
    if [ ! -f "$__INTERNAL_CLEANUP_BUFF" ]; then
        rlLogError "rlCleanupAppend: cleanup metadata not initialized"
        return 1
    elif [ $# -lt 1 ]; then
        rlLogError "rlCleanupAppend: not enough arguments"
        return 1
    elif [ -z "$__INTERNAL_TESTWATCHER_ACTIVE" ]; then
        rlLogWarning "rlCleanupAppend: Running outside of the test watcher"
        rlLogWarning "rlCleanupAppend: Check your 'run' target in the test Makefile"
        rlLogWarning "rlCleanupAppend: Cleanup will be executed only if rlJournalEnd is called properly"
    fi

    echo "$1" >> "$__INTERNAL_CLEANUP_BUFF" || return 1

    __INTERNAL_rlCleanupGenFinal || return 1
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# rlCleanupPrepend
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head3 rlCleanupPrepend

Prepends a string to the cleanup buffer and recreates the cleanup script.

    rlCleanupPrepend string

=over

=back

Returns 0 if the operation was successful, 1 otherwise.

=cut

rlCleanupPrepend() {
    if [ ! -f "$__INTERNAL_CLEANUP_BUFF" ]; then
        rlLogError "rlCleanupPrepend: cleanup metadata not initialized"
        return 1
    elif [ $# -lt 1 ]; then
        rlLogError "rlCleanupPrepend: not enough arguments"
        return 1
    elif [ -z "$__INTERNAL_TESTWATCHER_ACTIVE" ]; then
        rlLogWarning "rlCleanupPrepend: Running outside of the test watcher"
        rlLogWarning "rlCleanupPrepend: Check your 'run' target in the test Makefile"
        rlLogWarning "rlCleanupPrepend: Cleanup will be executed only if rlJournalEnd is called properly"
    fi

    local tmpbuff="$__INTERNAL_CLEANUP_BUFF".tmp
    echo "$1" > "$tmpbuff" || return 1
    cat "$__INTERNAL_CLEANUP_BUFF" >> "$tmpbuff" || return 1
    mv -f "$tmpbuff" "$__INTERNAL_CLEANUP_BUFF" || return 1

    __INTERNAL_rlCleanupGenFinal || return 1
}



# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# AUTHORS
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head1 AUTHORS

=over

=item *

Petr Muller <pmuller@redhat.com>

=item *

Jan Hutar <jhutar@redhat.com>

=item *

Petr Splichal <psplicha@redhat.com>

=item *

Ales Zelinka <azelinka@redhat.com>

=item *

Karel Srot <ksrot@redhat.com>

=back

=cut
