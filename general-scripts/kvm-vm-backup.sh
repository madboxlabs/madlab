#!/bin/bash
#
# This script backs up a list of VMs.
# An overview of the process is as follows:
# * invokes a "snapshot" which transfers VM disk I/O to new "snapshot" image file(s).
# * copy (and encrypt if applicable) the VM's image file(s) to a backup
# * invoke a "blockcommit" which merges (or "pivots") the snapshot image back
#   to the VM's primary image file(s)
# * delete the snapshot image file(s)
# * make a copy of the VM define/XML file
# * delete old images and XMLs, retaining images for x dates where x = IMAGECNT
#
# Note: On CentOS 7 snapshotting requires the "-ev" version of qemu.
#       yum install centos-release-qemu-ev qemu-kvm-ev libvirt
#
# The script uses gzip to compress the source image (e.g. qcow2) on the fly 
# to the destination backup image. bzip2 was also tested, but bzip2 (and 
# other compression utilities) provide better compression (15-20%) but gzip
# is 7-10 times faster.
# 
# The script uses gpg symmetric encryption to encrypt the source image. The 
# encryption password is set using the ENCPASS field, and items must be decrypted
# before they are unzipped. Encrypted files will have an extension of .gz.gpg. By 
# leaving the ENCPASS field blank you can disable this feature.
#
# If the process fails part way through the snapshot, copy, or blockcommit, 
# the VM may be left running on the snapshot file which is Not desirable.
#

# define an emergency mail recipient
EMR=backups@madbox.co.uk
# encryption password. if left blank, files are not encrypted
ENCPASS="!c0k3z3r0!"
HOST="$(hostname)"
SHCMD="$(basename -- $0)"
BACKUPROOT=/run/media/steve/f087ea94-42f8-4cfe-8b48-f850a8bfcb85/backup/kvm/
IMAGECNT=3
[ ! -f $BACKUPROOT/logs ] && mkdir -p $BACKUPROOT/logs
DATE="$(date +%Y-%m-%d.%H%M%S)"
LOG="$BACKUPROOT/logs/qemu-backup.$(date +%Y-%m-%d).log"
ERRORED=0
BREAK=false
SNAPPREFIX=snaptemp-

#Optionally list all VMs and back them all up
DOMAINS=$(virsh list --all | tail -n +3 | awk '{print $2}')
#DOMAINS="myVMa myVMb"

# extract the date coding in filename (note: filename format must be YYYY-MM-DD)
dtmatch () { sed -n -e 's/.*\(2[0-1][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\).*/\1/p'; }

echo "$SHCMD: Starting backups on $(date +'%d-%m-%Y %H:%M:%S')"  >> $LOG
for DOMAIN in $DOMAINS; do
	BREAK=false

        echo "---- VM Backup start $DOMAIN ---- $(date +'%d-%m-%Y %H:%M:%S')"  >> $LOG

        VMSTATE=$(virsh list --all | grep [[:space:]]$DOMAIN[[:space:]] | awk '{print $3}')
        if [[ $VMSTATE != "shut" ]]; then
                echo "Skipping $DOMAIN , because it is not running." >> $LOG
                continue
        fi

        BACKUPFOLDER=$BACKUPROOT/$DOMAIN
        [ ! -d $BACKUPFOLDER ] && mkdir -p $BACKUPFOLDER
        TARGETS=$(virsh domblklist $DOMAIN --details | grep disk | awk '{print $3}')
        IMAGES=$(virsh domblklist $DOMAIN --details | grep disk | awk '{print $4}')

	# check to make sure the VM is running on a standard image, not
	# a snapshot that may be from a backup that previously failed
        for IMAGE in $IMAGES; do
                set -o noglob
                if [[ $IMAGE == *${SNAPPREFIX}* ]]; then
                        set +o noglob
                	ERR="$SHCMD: Error VM $DOMAIN is running on a snapshot disk image: $IMAGE"
			echo $ERR >> $LOG
			echo "$ERR
Host:       $HOST
Disk Image: $IMAGE
Domain:     $DOMAIN
Command:    virsh domblklist $DOMAIN --details" | mail -s "$SHCMD snapshot Exception for $DOMAIN" $EMR
                	BREAK=true
			ERRORED=$(($ERRORED+1))
			break
                fi
		set +o noglob
        done
	[ $BREAK == true ] && continue

	# gather all the disks being used by the VM so they can be collectively snapshotted
        DISKSPEC=""
        for TARGET in $TARGETS; do
                set -o noglob
                if [[ $TARGET == *${SNAPPREFIX}* ]]; then
                        set +o noglob
                	ERR="$SHCMD: Error VM $DOMAIN is running on a snapshot disk image: $TARGET"
			echo $ERR >> $LOG
			echo "$ERR
Host:       $HOST
Disk Image: $IMAGE
Domain:     $DOMAIN
Command:    $CMD" | mail -s "$SHCMD snapshot Exception for $DOMAIN" $EMR
			BREAK=true
                	break
                fi
                set +o noglob
                DISKSPEC="$DISKSPEC --diskspec $TARGET,snapshot=external"
        done
	[ $BREAK == true ] && continue

	# transfer the VM to snapshot disk image(s)
        CMD="virsh snapshot-create-as --domain $DOMAIN --name ${SNAPPREFIX}$DOMAIN-$DATE --no-metadata --atomic --disk-only $DISKSPEC >> $LOG 2>&1"
        echo "Command: $CMD" >> $LOG 2>&1
        eval "$CMD"
        if [ $? -ne 0 ]; then
                ERR="Failed to create snapshot for $DOMAIN"
		echo $ERR >> $LOG
		echo "$ERR
Host:    $HOST
Domain:  $DOMAIN
Command: $CMD" | mail -s "$SHCMD snapshot Exception for $DOMAIN" $EMR
		ERRORED=$(($ERRORED+1))
                continue
        fi

	# copy/back/compress the VM's disk image(s)
        for IMAGE in $IMAGES; do
		echo "Copying $IMAGE to $BACKUPFOLDER" >> $LOG
		ZFILE="$BACKUPFOLDER/$(basename -- $IMAGE)-$DATE.gz"
		# determine whether the gzip is to be encrypted or not
		if [ -z "${ENCPASS}" ]; then 
			CMD="gzip < $IMAGE > $ZFILE 2>> $LOG"
		else
			exec {pwout}> /tmp/agspw.$$
			exec {pwin}< /tmp/agspw.$$
			rm /tmp/agspw.$$
			echo $ENCPASS >&$pwout
			ZFILE="$ZFILE.gpg"
			CMD="gzip < $IMAGE --to-stdout | gpg --batch --yes -o $ZFILE --passphrase-fd $pwin -c >> $LOG"
		fi
		echo "Command: $CMD" >> $LOG
		SECS=$(printf "%.0f" $(/usr/bin/time -f %e sh -c "$CMD" 2>&1))
		printf '%s%dh:%dm:%ds\n' "Duration: " $(($SECS/3600)) $(($SECS%3600/60)) $(($SECS%60)) >> $LOG
		# clear fds if necessary
		if [ -n "${ENCPASS}" ]; then 
			exec {pwout}>&-
			exec {pwin}<&-
			unset pwout pwin
		fi
		BYTES=$(stat -c %s $IMAGE) 
		printf "%s%'d\n" "Source MB: " $(($BYTES/1024/1024)) >> $LOG
		printf "%s%'d\n" "kB/Second: " $(($BYTES/$SECS/1024)) >> $LOG
		ZBYTES=$(stat -c %s $ZFILE) 
		printf "%s%'d\n" "Destination MB: " $(($ZBYTES/1024/1024)) >> $LOG
		printf "%s%d%s\n" "Compression: " $((($BYTES-$ZBYTES)*100/$BYTES)) "%" >> $LOG
        done

	# Update the VM's disk image(s) with any changes recorded in the snapshot 
	# while the copy process was running.  In qemu lingo this is called a "pivot"
        BACKUPIMAGES=$(virsh domblklist $DOMAIN --details | grep disk | awk '{print $4}')
        for TARGET in $TARGETS; do
                CMD="virsh blockcommit $DOMAIN $TARGET --active --pivot >> $LOG 2>&1"
                echo "Command: $CMD" >> $LOG 
                eval "$CMD"

                if [ $? -ne 0 ]; then
			ERR="Could not merge changes for disk of $TARGET of $DOMAIN. VM may be in an invalid state."
                        echo $ERR >> $LOG
			echo "$ERR
Host:    $HOST
Domain:  $DOMAIN
Command: $CMD" | mail -s "$SHCMD blockcommit Exception for $DOMAIN" $EMR
                        BREAK=true
			ERRORORED=$(($ERRORED+1))
			break
                fi
        done
	[ $BREAK == true ] && continue

	# Now that the VM's disk image(s) have been successfully committed/pivoted to
	# back to the main disk image, remove the temporary snapshot image file(s)
        for BACKUP in $BACKUPIMAGES; do
                set -o noglob
                if [[ $BACKUP == *${SNAPPEFIX}* ]]; then
                        set +o noglob
			CMD="rm -f $BACKUP >> $LOG 2>&1"
                	echo " Deleting temporary image $BACKUP" >> $LOG
                	echo "Command: $CMD" >> $LOG
			eval "$CMD"
                fi
                set +o noglob
        done

	# capture the VM's definition in use at the time the backup was done
        CMD="virsh dumpxml $DOMAIN > $BACKUPFOLDER/$DOMAIN-$DATE.xml 2>> $LOG"
        echo "Command: $CMD" >> $LOG 
        eval "$CMD"

	# Tracks whether xmls have been cleared
	DDEL='no'
	# check image retention count
	for IMAGE in $IMAGES; do 
		COUNT=`find $BACKUPFOLDER -type f -name $(basename -- $IMAGE)-'*'.gz'*' -print | dtmatch | sort -u | wc -l`
		if [ $COUNT -gt $IMAGECNT  ]; then
			echo "$SHCMD: Count for BACKUPFOLDER ($BACKUPFOLDER) for image ($(basename -- $IMAGE)) too high ($COUNT), deleting historical files over $IMAGECNT..."
			LIST=`find $BACKUPFOLDER -type f -name $(basename -- $IMAGE)-'*'.gz'*' -print | dtmatch | sort -ur | sed -e "1,$IMAGECNT"d`
			
			# make sure LIST has a value otherwise fgrep will allow the entire find
			# result to be passed to xarg rm
			if [ -n "$LIST" ]; then
				# Delete the specific images in the dates list
				find $BACKUPFOLDER -type f -name $(basename -- $IMAGE)-'*' | fgrep "$LIST" | xargs rm
				# Only delete old xmls once
				if [[ $DDEL == 'no' ]]; then
					# Delete the xmls in the dates list
					find $BACKUPFOLDER -type f -name $DOMAIN-'*' | fgrep "$LIST" | xargs rm
					DDEL='yes'
				fi
			fi
		fi
	done

        echo "---- Backup done $DOMAIN ---- $(date +'%d-%m-%Y %H:%M:%S') ----" >> $LOG
done
echo "$SHCMD: Finished backups at $(date +'%d-%m-%Y %H:%M:%S')
====================" >> $LOG

exit $ERRORED
