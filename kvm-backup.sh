#!/bin/bash

#To exclude a domain, please add to its name "nobackup"
#First shutdown the guest, then use this command: virsh domrename oldname newname.

DATE=`date +%Y%m%d%H%M%S`
LOG=/var/log/kvm-backup.$DATE.LOG
BACKUPROOT=/mnt/bacula/backupvms
XML=/mnt/VMS/XML


DOMAINS=$(virsh list --all | tail -n +3 | awk '{print $2}')

for DOMAIN in $DOMAINS; do
        echo "-----------WORKER START $DOMAIN-----------" >> $LOG
        echo "Starting backup for $DOMAIN on $(date +'%d-%m-%Y %H:%M:%S')"  >> $LOG

        if [[ $DOMAIN == *"nobackup"* ]];then
                echo "Skipping $DOMAIN , because its excluded." >> $LOG
                exit 1
        fi

        VMSTATE=`virsh list --all | grep $DOMAIN | awk '{print $3}'`
        if [[ $VMSTATE != "running" ]]; then
                echo "Skipping $DOMAIN , because its not running." >> $LOG
                exit 1
        fi

        BACKUPFOLDER=$BACKUPROOT/$DOMAIN
        ssh root@10.1.5.8 "mkdir -p $BACKUPFOLDER"
        mkdir -p $XML
        TARGETS=$(virsh domblklist $DOMAIN --details | grep disk | awk '{print $3}')
        IMAGES=$(virsh domblklist $DOMAIN --details | grep disk | awk '{print $4}')
        DISKSPEC=""
        for TARGET in $TARGETS; do
                DISKSPEC="$DISKSPEC --diskspec $TARGET,snapshot=external"
        done

        virsh snapshot-create-as --domain $DOMAIN --name "backup-$DOMAIN" --no-metadata --atomic --disk-only $DISKSPEC >> $LOG
        if [ $? -ne 0 ]; then
                echo "Failed to create snapshot for $DOMAIN" >> $LOG
                exit 1
        fi

        for IMAGE in $IMAGES; do
                NAME=$(basename $IMAGE)
                #if test -f "$BACKUPFOLDER/$NAME"; then
                #echo "Backup exists, merging only changes to image" >> $LOG
                #rsync -apvz --inplace $IMAGE $BACKUPFOLDER/$NAME >> $LOG
                #else
                #echo "Backup does not exist, creating a full sparse copy" >> $LOG
                #rsync -apvz --sparse $IMAGE $BACKUPFOLDER/$NAME >> $LOG
                
                rsync -aP $IMAGE root@10.1.5.8:$BACKUPFOLDER/$NAME >> $LOG
		#rsync -apvP --inplace $IMAGE root@10.1.5.8:$BACKUPFOLDER/$NAME >> $LOG
                #fi

        done

        BACKUPIMAGES=$(virsh domblklist $DOMAIN --details | grep disk | awk '{print $4}')
        for TARGET in $TARGETS; do
                virsh blockcommit $DOMAIN $TARGET --active --pivot >> $LOG

                if [ $? -ne 0 ]; then
                        echo "Could not merge changes for disk of $TARGET of $DOMAIN. VM may be in invalid state." >> $LOG
                        exit 1
                fi
        done

        for BACKUP in $BACKUPIMAGES; do
                if [[ $BACKUP == *"backup-"* ]];then

                echo "deleted temporary image $BACKUP" >> $LOG
                rm -f $BACKUP
                fi
        done

        virsh dumpxml $DOMAIN > $XML/$DOMAIN.xml
        rsync -aP $XML/$DOMAIN.xml root@10.1.5.8:$BACKUPFOLDER >> $LOG
        echo "-----------WORKER END $DOMAIN-----------" >> $LOG
        echo "Finished backup of $DOMAIN at $(date +'%d-%m-%Y %H:%M:%S')" >> $LOG
done

echo "Finished backup at $(date +'%d-%m-%Y %H:%M:%S')" >> $LOG

exit 0