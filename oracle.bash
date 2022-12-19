#!/bin/bash

# Script for configuring and automating database backup
# Copyright (C) 2010
# Ralf Lange
# ORACLE Deutschland GmbH
#
# a description is at the end of this file
# call this script without parameters for help

if [ -n $HOME ]; then
  export HOME=/home/oracle
fi

# make sure that PATH, ORACLE_SID and LD_LIBRARY_PATH
# for the database to backup get set in this section
if [ -f ${HOME}/11gR2_sourceme.bash ]; then
  source ${HOME}/11gR2_sourceme.bash 
else
  ORACLE_BASE=/u01/app/oracle
  ORACLE_HOME=${ORACLE_BASE}/product/11.2.0/dbhome_1
  ORACLE_SID=orcl
  PATH=${ORACLE_HOME}/bin:${PATH}
  LD_LIBRARY_PATH=${ORACLE_HOME}/lib:${ORACLE_HOME}/ctx/lib
fi

# data pump compression is enterprise edition only
#ENTERPRISE_EDITION=yes/no
ENTERPRISE_EDITION=yes

# specify, if a RMAN catalog will be used
# MAKE_USE_OF_RMAN_CATALOG=yes/no
MAKE_USE_OF_RMAN_CATALOG=yes

# Connect information for the RMAN Catalog
RMAN_SID=rman
RMAN_ACCOUNT=rman
RMAN_PW=rman

# You want to be able to bring back the database
# to any state of the previous <n> days
RECOVERY_WINDOW_SIZE=14

# always have a full backup with the state
# of the database <n> days before now
TRAIL_DAYS=4

# The output of this script is logged here
CRONLOG=${HOME}/bin/cronlog.txt

# keep track of the times for the last
# full backup and the last incremental backup
TIMESTAMPDIR=${HOME}/bin/.timestamps
FULLBACKUP_TIMESTAMP_FILE=${TIMESTAMPDIR}/rmanfull
DAILYBACKUP_TIMESTAMP_FILE=${TIMESTAMPDIR}/rmandaily
PIDFILE=${TIMESTAMPDIR}/pidfile

# RUN_COMPARE has to match the string that is given back
# from "srvctl status database -d <ORCL_SID"
# unfortunately that is language dependend
#RUN_COMPARE="wird ausgeführt"
RUN_COMPARE="is running"

# usually no configuration needed below next line
##############################################################

# reliable way to get the full path to this script
#MYFULLPATH=`which $0`
MYFULLPATH=`readlink -f $0`
#echo $MYFULLPATH

n=0
n=$(($n+1)); D_LIST[n]="$n"; DAY_LIST[n]="Monday"     # 1
n=$(($n+1)); D_LIST[n]="$n"; DAY_LIST[n]="Tuesday"    # 2
n=$(($n+1)); D_LIST[n]="$n"; DAY_LIST[n]="Wednesday"  # 3
n=$(($n+1)); D_LIST[n]="$n"; DAY_LIST[n]="Thursday"   # 4
n=$(($n+1)); D_LIST[n]="$n"; DAY_LIST[n]="Friday"     # 5
n=$(($n+1)); D_LIST[n]="$n"; DAY_LIST[n]="Saturday"   # 6
n=$(($n+1)); D_LIST[n]="$n"; DAY_LIST[n]="Sunday"     # 7

RMAN_CREDENTIALS=${RMAN_ACCOUNT}/${RMAN_PW}
CATALOG_CONNECT="connect catalog ${RMAN_CREDENTIALS}@${RMAN_SID}"

# if the timestamp dir does not exist, create it
if [ ! -d ${TIMESTAMPDIR} ];then
  echo "*** `date` creating timestampdir \"$TIMESTAMPDIR\""
  mkdir -p ${TIMESTAMPDIR}
fi >> ${CRONLOG} 2>&1

# check if we have been started from cron or the command line
if tty>&/dev/null; then
   # we have been started from the commandline
   IS_TERMINAL=1
   STARTED_BY="from commandline"
   FULL_TAG="full backup"
else
   # we have been started by cron
   IS_TERMINAL=0
   STARTED_BY="by cron"
   FULL_TAG="weekly full"
fi

case "$ENTERPRISE_EDITION" in
   [Yy][Ee][Ss]) COMPRESSION="compression=all";;
   [Nn][Oo])     unset COMPRESSION;;
   *)            unset COMPRESSION;
esac

case "$MAKE_USE_OF_RMAN_CATALOG" in
   [Yy][Ee][Ss]) RMAN_CATALOG=1;;
   [Nn][Oo])     unset RMAN_CATALOG;;
   *)            unset RMAN_CATALOG;
esac

# testfunc
testfunc()
{
echo -n "Press Return to exit "
read line
exit
}

# read a time value from the command line
time_input()
{
idiot_counter=0
while true;do
  read line
  case "$line" in
    [01][0-9]:[0-5][0-9]) break;;
    2[0-3]:[0-5][0-9])    break;;
    *) 
      idiot_counter=$(($(($idiot_counter+1))%3));
      if [[ $idiot_counter == 0 ]];then
        echo "***"
        echo "*** EPIC FAIL !"
        echo "*** the format for the time is hh:mm"
        echo "*** Here is a hint:"
        echo "*** examples for valid times are 04:12 or 23:10"
        echo "***"
      fi
      echo -n "please specify a time in the format hh:mm : "
      ;;
  esac
done
}

rmanfull()
{
if (( $IS_TERMINAL ));then
  export STUPID_STRING=`cat /dev/urandom|tr -dc "a-zA-Z0-9"|fold -w 9|head -n 1`
  echo "*** Wait until the command finishes. All output is redirected to the logfile."
  echo "*** To review the result of this command, you can inspect the logfile"
  echo "*** by typing"
  echo "less +/${STUPID_STRING} ${CRONLOG}"
  echo "Find-Tag:${STUPID_STRING}" >> ${CRONLOG}
fi
exec 3<&1            # save stdout to file descriptor 3
exec 1>>${CRONLOG}   # redirect stdout
exec 2>&1            # redirect stderr
echo "****************************************"
echo "*** RMAN full backup initiated ${STARTED_BY}"
STARTTIME="`date`"
echo "*** $STARTTIME"

if srvctl status database -d ${ORACLE_SID}|grep "${RUN_COMPARE}" &> /dev/null;then
  RUNNING=1; # true
  echo "Instance ${ORACLE_SID} is running"
else
  RUNNING=0; # false
  echo "Starting instance ${ORACLE_SID}"
  srvctl start database -d ${ORACLE_SID}
fi;

if [[ ${RMAN_CATALOG} ]] && srvctl status database -d ${RMAN_SID}|grep -q "${RUN_COMPARE}"; then
  RMAN_DB_UP=1; # true
  echo "Instance ${RMAN_SID} is running"
  CATALOG_CONNECT_COMMAND=${CATALOG_CONNECT}
else
  RMAN_DB_UP=0; # false
  unset CATALOG_CONNECT_COMMAND
fi;

echo " ORACLE_SID : $ORACLE_SID"
echo "ORACLE_HOME : $ORACLE_HOME"
echo "       PATH : $PATH"
ORACLE_SID=${ORACLE_SID} rman target / > /dev/null 2>&1 << EOF
spool log to '${CRONLOG}' append;
set echo on;
${CATALOG_CONNECT_COMMAND}
run {
  backup check logical as compressed backupset database tag '${FULL_TAG}';
  backup check logical as compressed backupset archivelog all not backed up delete all input;
  delete noprompt obsolete;
  host 'date &> ${FULLBACKUP_TIMESTAMP_FILE}';
}
set echo off;
spool log off;
EOF
if (( $RMAN_DB_UP ));then
ORACLE_SID=${RMAN_SID} expdp ${RMAN_CREDENTIALS} \
             ${COMPRESSION} reuse_dumpfiles=y \
             directory=data_pump_dir dumpfile=rman_catalog.dmp
fi

if (( ! $RUNNING ));then
  echo "stopping instance ${ORACLE_SID} after backup"
  srvctl stop database -d ${ORACLE_SID}
fi;
echo "*** end of RMAN full backup"
echo -e "*** Start : $STARTTIME\n***   End : `date`"
echo -e "****************************************\n\n"
exec 1>&3            # restore stdout
exec 3>&-            # close temporary fd 3
exec 2>&1            # redirect stderr to stdout
}

rmandaily()
{
if (( $IS_TERMINAL ));then
  export STUPID_STRING=`cat /dev/urandom|tr -dc "a-zA-Z0-9"|fold -w 9|head -n 1`
  echo "*** Wait until the command finishes. All output is redirected to the logfile."
  echo "*** To review the result of this command, you can inspect the logfile"
  echo "*** by typing"
  echo "less +/${STUPID_STRING} ${CRONLOG}"
  echo "Find-Tag:${STUPID_STRING}" >> ${CRONLOG}
fi
exec 3<&1            # save stdout to file descriptor 3
exec 1>>${CRONLOG}   # redirect stdout
exec 2>&1            # redirect stderr
echo "****************************************"
echo "*** RMAN incremental backup initiated ${STARTED_BY}"
STARTTIME="`date`"
echo "*** $STARTTIME"

if srvctl status database -d ${ORACLE_SID}|grep "${RUN_COMPARE}" &> /dev/null;then
  RUNNING=1; # true
  echo "Instance ${ORACLE_SID} is running"
else
  RUNNING=0; # false
  echo "Starting instance ${ORACLE_SID}"
  srvctl start database -d ${ORACLE_SID}
fi;

if [[ ${RMAN_CATALOG} ]] && srvctl status database -d ${RMAN_SID}|grep -q "${RUN_COMPARE}"; then
  RMAN_DB_UP=1; # true
  echo "Instance ${RMAN_SID} is running"
  CATALOG_CONNECT_COMMAND=${CATALOG_CONNECT}
else
  RMAN_DB_UP=0; # false
  unset CATALOG_CONNECT_COMMAND
fi;

echo " ORACLE_SID : $ORACLE_SID"
echo "ORACLE_HOME : $ORACLE_HOME"
echo "       PATH : $PATH"
ORACLE_SID=${ORACLE_SID} rman target / > /dev/null 2>&1 << EOF
spool log to '${CRONLOG}' append;
set echo on;
${CATALOG_CONNECT_COMMAND}
run {
  recover check logical copy of database with tag 'basis backup' until time 'sysdate-${TRAIL_DAYS}';
  backup check logical incremental level 1 for recover of copy with tag 'basis backup' database;
  backup check logical as compressed backupset archivelog all not backed up delete all input;
  host 'date &> ${DAILYBACKUP_TIMESTAMP_FILE}';
}
set echo off;
spool log off;
EOF
if (( $RMAN_DB_UP ));then
  ORACLE_SID=${RMAN_SID} expdp ${RMAN_CREDENTIALS} \
                ${COMPRESSION} reuse_dumpfiles=y \
                directory=data_pump_dir dumpfile=rman_catalog.dmp
fi

if (( ! $RUNNING ));then
  echo "stopping instance ${ORACLE_SID} after backup"
  srvctl stop database -d ${ORACLE_SID}
fi;
echo "*** end of RMAN incremental backup"
echo -e "*** Start : $STARTTIME\n***   End : `date`"
echo -e "****************************************\n\n"
exec 1>&3            # restore stdout
exec 3>&-            # close temporary fd 3
exec 2>&1            # redirect stderr to stdout
}

backupcheck()
{
if (( $IS_TERMINAL ));then
  export STUPID_STRING=`cat /dev/urandom|tr -dc "a-zA-Z0-9"|fold -w 9|head -n 1`
  echo "*** Wait until the command finishes. All output is redirected to the logfile."
  echo "*** To review the result of this command, you can inspect the logfile"
  echo "*** by typing"
  echo "less +/${STUPID_STRING} ${CRONLOG}"
  echo "Find-Tag:${STUPID_STRING}" >> ${CRONLOG}
fi
exec 3<&1            # save stdout to file descriptor 3
exec 1>>${CRONLOG}   # redirect stdout
exec 2>&1            # redirect stderr
FLIST=`find ${DAILYBACKUP_TIMESTAMP_FILE} -mmin +1500`
if [ $FLIST ];then
  echo "*** `date`: incremental Backup needs to be made"
  rmandaily
else
  echo "*** `date`: no incremental backup necessary"
fi
FLIST=`find ${FULLBACKUP_TIMESTAMP_FILE} -mmin +10140`
if [ $FLIST ];then
  echo "*** `date`: full Backup needs to be made"
  rmanfull
else
  echo "*** `date`: no full backup necessary"
fi
exec 1>&3            # restore stdout
exec 3>&-            # close temporary fd 3
exec 2>&1            # redirect stderr to stdout
}

catalogbackup()
{
if (( $IS_TERMINAL ));then
  export STUPID_STRING=`cat /dev/urandom|tr -dc "a-zA-Z0-9"|fold -w 9|head -n 1`
  echo "*** Wait until the command finishes. All output is redirected to the logfile."
  echo "*** To review the result of this command, you can inspect the logfile"
  echo "*** by typing"
  echo "less +/${STUPID_STRING} ${CRONLOG}"
  echo "Find-Tag:${STUPID_STRING}" >> ${CRONLOG}
fi
exec 3<&1            # save stdout to file descriptor 3
exec 1>>${CRONLOG}   # redirect stdout
exec 2>&1            # redirect stderr
echo "****************************************"
echo "*** RMAN catalog data pump export"
STARTTIME="`date`"
echo "*** $STARTTIME"
# check and save status of instance ${ORACLE_SID}
if srvctl status database -d ${ORACLE_SID}|grep "${RUN_COMPARE}" &> /dev/null;then
  ORCL_RUNNING=1; # true
  echo "Instance ${ORACLE_SID} is running"
else
  ORCL_RUNNING=0; # false
  echo "Starting instance ${ORACLE_SID}"
  srvctl start database -d ${ORACLE_SID}
fi;

# check and save status of instance ${RMAN_SID}
if srvctl status database -d ${RMAN_SID}|grep "${RUN_COMPARE}" &> /dev/null;then
  RMAN_RUNNING=1; # true
  echo "Instance ${RMAN_SID} is running"
else
  RMAN_RUNNING=0; # false
  echo "Starting instance ${RMAN_SID}"
  srvctl start database -d ${RMAN_SID}
fi;

# resync RMAN catalog
echo "*** resyncing RMAN catalog"
ORACLE_SID=${ORACLE_SID} rman target / &> /dev/null << EOF
spool log to '${CRONLOG}' append;
set echo on;
${CATALOG_CONNECT}
resync catalog;
set echo off;
spool log off;
EOF

# export the RMAN catalog
echo "*** data pump export of RMAN catalog"
ORACLE_SID=${RMAN_SID} expdp ${RMAN_CREDENTIALS} \
             ${COMPRESSION} reuse_dumpfiles=y \
             directory=data_pump_dir dumpfile=rman_catalog.dmp

# put back ${ORACLE_SID} instance to preserved status
if (( ! $ORCL_RUNNING ));then
  echo "stopping instance ${ORACLE_SID} after backup"
  srvctl stop database -d ${ORACLE_SID}
fi;
# put back RMAN instance to preserved status
if (( ! $RMAN_RUNNING ));then
  echo "stopping instance ${RMAN_SID} after backup"
  srvctl stop database -d ${RMAN_SID}
fi;
echo "*** end of RMAN catalog data pump export"
echo -e "*** Start : $STARTTIME\n***   End : `date`"
echo -e "****************************************\n\n"
exec 1>&3            # restore stdout
exec 3>&-            # close temporary fd 3
exec 2>&1            # redirect stderr to stdout
}

setupbackup()
{
echo "****************************************"
echo "*** implementing backup strategy"
STARTTIME="`date`"
echo -e "*** $STARTTIME\n"

cat << EOF
this is going to happen:
  we bring up the database ${ORACLE_SID} in archivelog mode. This is needed for
    online backups
  the recovery window of RMAN gets configured, compressed backupsets are set
    as default for RMAN backups and the controlfile is backed up with every
    backup
  cron is configured so that daily incremental and weekly full backups are
    performed automatically
  the times for the weekly full and the daily incremental backup are queried
    together with the day for the weekly full backup
  if another database will be used for the RMAN catalog, the catalog owner is
    created in the database, granted read/write access to the data_pump_dir
    and given the recovery_catalog_owner_role. The RMAN catalog is created and
    the database is registered in the catalog.

  you will be asked for permission before "${ORACLE_SID}" is shut down

  the current crontab is backed up (in case there is one)
EOF
export STUPID_STRING="k4JgHrt"
if [ -e /dev/urandom ];then
  export STUPID_STRING=`cat /dev/urandom|tr -dc "a-zA-Z0-9"|fold -w 9|head -n 1`
fi
echo "*** to avoid accidental execution, type \"${STUPID_STRING}\" if you want to continue"
idiot_counter=0
while true; do
  read line
  case $line in
    ${STUPID_STRING}) break;;
    *)
      idiot_counter=$(($(($idiot_counter+1))%2));
      if [[ $idiot_counter == 0 ]];then
        echo -e "***\n*** YOU FAIL !\n***\n*** exiting..."; exit;
      fi
      ;;
  esac
done

echo -e "\n\n*** enforcing archivelog mode for ${ORACLE_SID}"
ORCL_RUNNING=0; # false
if srvctl status database -d ${ORACLE_SID}|grep "${RUN_COMPARE}" &> /dev/null;then
  ORCL_RUNNING=1; # true
  echo "Instance ${ORACLE_SID} is running"
  echo -n "Can we restart the database to enforce archivelog mode ? (yes/[no]) "
  read line
  case $line in
    yes) srvctl stop database -d ${ORACLE_SID};;
    *) echo "exiting."; exit 1;;
  esac
fi
echo "Starting instance ${ORACLE_SID} in mount status"
srvctl start database -d ${ORACLE_SID} -o mount
sqlplus / as sysdba << EOF
alter database archivelog;
alter database open;
EOF

export CRONTAB_TMP_FILE=`mktemp -t crontab_tmp_file.XXXXXXXXXXX` || {
  echo "*** Creation of ${CRONTAB_TMP_FILE} failed";
  exit 1;
}

## Begin of this while
while true; do
cat << EOF

*** RMAN Recovery Window
*** This value defines the interval in days between the current time
*** and the earliest time the database can be restored and recovered to.
*** The database can be restored and recovered to any point in time in
*** this interval
***
EOF
while true; do
  echo -n "please specify the length of the recovery window in days : "
  read line
  case $line in
    [1-9])           RECOVERY_WINDOW_SIZE=$line; break;;
    [1-9][0-9]*)
       if [[ $line -gt 30 ]] ;then
         echo -e "proportional disk space is needed with increasing"
         echo "recovery window size. $line is a fairly great number"
         echo -n "are you sure you want to keep this value ? (yes/[no]) "
         read nline
         case $nline in
           [Yy][Ee][Ss]) ;;
           *) continue;;
         esac
       fi
       RECOVERY_WINDOW_SIZE=$line;
       break;
       ;;
    *) echo "please specify a value in days";;
  esac
done

cat << EOF

*** RMAN incrementally updatable backup
*** This is cool. RMAN can update a full backup with an incremental
*** backup, thereby rolling forward the full backup in time. 
*** The incremental backup used for update does not need to be the
*** latest available. If you specify a value of for example 3 days
*** here, you will always have a full backup with the state of the
*** database of 3 days before the current time. Since we do weekly
*** full backups in addition to the incrementally updatable backups,
*** there is no use specifying a value of more than 7 here.
*** Also, greater values here increase the size of the daily
*** incremental backups.
EOF
echo -e "\nHow many days should the incrementally updatable\nfull backup trail the current time ?"
while true; do
  echo -n "Enter a number between 1 and 7 : "
  read line
  case $line in
    [1-7]) TRAILDAYS=$line; break;;
    *)      echo "must be between 1 and 7";
        ;;
  esac
done

echo -e "\n*** the RMAN Recovery Window is set to $RECOVERY_WINDOW_SIZE days"
echo "*** We keep a full backup at $TRAILDAYS days behind current time"
echo -n "*** are the above values o.k.? ([yes]/no) "
read line
case $line in
  "")  break;;
  [Yy][Ee][Ss]) break;;
  *)        ;;
esac
done
## End of this while

# hack alert !
# we are changing THIS file
chmod u+rw "$MYFULLPATH"
sed --in-place -e "s+^TRAIL_DAYS=[0-9][0-9]*[\t ]*\$+TRAIL_DAYS=$TRAILDAYS+" "$MYFULLPATH"

while true; do
  echo -ne "\ntype in the time for DAILY BACKUPS as hh:mm : "
  time_input
  DMM=${line##*:}
  DHH=${line%%:*}
  echo -ne "\ntype in the time for WEEKLY FULL BACKUPS as hh:mm : "
  time_input
  WMM=${line##*:}
  WHH=${line%%:*}
  echo -e "\nand now the weekday for the weekly backup"
  while true; do
    echo -n "type 1..7 for monday..sunday : "
    read line
    case $line in
      [1-7]) DAY=$line; break;;
      *)     for n in `seq 1 7`;do
               echo "type $n for ${DAY_LIST[$n]}";
             done
    esac
  done
  echo "***       Daily backup scheduled at ${DHH}:${DMM}"
  echo "*** Weekly full backup scheduled at ${WHH}:${WMM}"
  echo "***   Weekly full backup happens on ${DAY_LIST[$DAY]}"
  echo -n "*** are the above values o.k.? ([yes]/no) "
  read line
  case $line in
    "")  break;;
    [Yy][Ee][Ss]) break;;
    *)        ;;
  esac
done

# BEGIN of RMAN Catalog configuration
if [[ ${RMAN_CATALOG} ]]; then
  idiot_counter=0
  echo "*** Will another database be used for the RMAN Catalog ?"
  while true; do
    echo -n "*** Please answer yes or no: "
    read line
    case $line in
      [Nn][Oo])     WILL_USE_CATALOG=0; break;;
      [Yy][Ee][Ss]) WILL_USE_CATALOG=1; break;;
      *)
        idiot_counter=$(($(($idiot_counter+1))%3));
        if [[ $idiot_counter == 0 ]];then
          echo -e "***\n*** YOU FAIL !\n***\n*** exiting..."; exit;
        fi
        ;;
    esac
  done
  
  if (( WILL_USE_CATALOG));then
    echo "configuring RMAN catalog"
    if srvctl status database -d ${RMAN_SID}|grep "${RUN_COMPARE}" &> /dev/null;then
      RMAN_DB_UP=1; # true
      echo "Instance ${RMAN_SID} is running"
    else
      RMAN_DB_UP=0; # false
      echo "Starting instance ${RMAN_SID}"
      srvctl start database -d ${RMAN_SID}
    fi;
    
    echo "create Catalog owner \"${RMAN_ACCOUNT}\" and"
    echo "grant read,write on directory data_pump_dir to ${RMAN_ACCOUNT}";
    ORACLE_SID=${RMAN_SID} sqlplus / as sysdba << EOF
    --Create Catalog Owner
    create user ${RMAN_ACCOUNT} identified by ${RMAN_PW}
    temporary tablespace temp
    default tablespace sysaux
    quota unlimited on sysaux;
    --Grant
    grant recovery_catalog_owner to ${RMAN_ACCOUNT};
    grant read,write on directory data_pump_dir to ${RMAN_ACCOUNT};
EOF
    
    CATALOG_CONNECT_COMMAND=${CATALOG_CONNECT}
    rman << EOF
    set echo on;
    ${CATALOG_CONNECT_COMMAND}
    create catalog;
    connect target /
    register database;
EOF
    # put back ${RMAN_SID} instance to preserved status
    if (( ! $RMAN_DB_UP ));then
      echo "stopping instance ${RMAN_SID} after backup setup"
      srvctl stop database -d ${RMAN_SID}
    fi;
  fi;
fi;
# END of RMAN Catalog configuration

echo "configuring RMAN parameters"
rman << EOF
connect target /
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF ${RECOVERY_WINDOW_SIZE} DAYS;
CONFIGURE BACKUP OPTIMIZATION ON;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE DEVICE TYPE DISK PARALLELISM 1 BACKUP TYPE TO COMPRESSED BACKUPSET;
EOF

# put back ${ORACLE_SID} instance to preserved status
if (( ! $ORCL_RUNNING ));then
  echo "stopping instance ${ORACLE_SID} after backup setup"
  srvctl stop database -d ${ORACLE_SID}
fi;

if [[ `crontab -l |wc|awk '{print $1}'` != 0 ]];then
CRONTAB_BACKUP="${HOME}/crontab_`date +%Y%m%d_%H:%M:%S`.txt"
crontab -l > ${CRONTAB_BACKUP}
fi

cat << EOF > "${CRONTAB_TMP_FILE}"
# Every ${DAY_LIST[$DAY]} at ${WHH}:${WMM} RMAN Full Backup
${WMM##0} ${WHH##0} * * ${D_LIST[$DAY]} "$MYFULLPATH" rmanfull

# Daily Incremental Backup at ${DHH}:${DMM}
${DMM##0} ${DHH##0} * * * "$MYFULLPATH" rmandaily

# Check if backups have been made.
# The script starts an incremental backup
# if the last daily backup has been made more
# than 25 hours ago, and a full backup if the
# last weekly backup was made more than one
# week+1h ago
30 * * * * "$MYFULLPATH" backupcheck
EOF
crontab "${CRONTAB_TMP_FILE}"
rm -f "${CRONTAB_TMP_FILE}"

echo -e "\n\n****************************************"
echo "*** new crontab file:"
crontab -l
echo -e "\n*** backup strategy implemented"
echo -e "*** Start : $STARTTIME\n***   End : `date`"
echo -e "****************************************\n\n"
}

long_usage()
{
cat << EOF
Prerequisites:

  Oracle 11gR2 configured with Oracle Restart
  Oracle Enterprise Linux, RedHat Linux, openSUSE, SLES

What this script does:

  rmanfull: Full Online Database Backup. Backup of Archivelogs. Deletion of
     obsolete backups. If the database is down, it is started, the backup is
     made, the database is stopped again. If the RMAN Catalog database is
     online, a connection to the RMAN Catalog is made and the RMAN Catalog is
     exported via Data Pump after the backup.

  rmandaily: Daily Incremental Database Backup. An incrementally updatable full
     backup is updated with the incremental backup from <N> days before today.
     <N> is configurable in this script (TRAIL_DAYS). Backup of archivelogs,
     deletion of obsolete backups. If the database is down, it is started, the
     backup is made, and the database is stopped again. If the RMAN Catalog
     database is online, a connection to RMAN Catalog is made and the
     RMAN Catalog is exported via Data Pump after the backup.

  backupcheck: determines if an incremental backup or a full backup needs
     to be made. If the last incremental backup has been made more than 25h
     ago, an incremental backup is initiated. If the last full backup has been
     made more than a week and one hour before, a full backup is initiated.

  catalogbackup: Initiates a data pump export of the RMAN catalog. First a
     resync catalog is performed, then the data pump export is made.
     The database and the RMAN catalog database are started if they were not
     online at invocation time of this script and are brought back to their
     original state after the export.
     Since data pump compression is a feature of the Enterprise Edition,
     the value of ENTERPRISE_EDITION in this script determines, if compression
     is used.
  
  setupbackup: This command creates the RMAN Catalog owner in the RMAN Catalog
     database, gives the RMAN Catalog user the grants RECOVERY_CATALOG_OWNER
     and read,write on the DATA_PUMP_DIRECTORY, creates the RMAN Catalog and
     registers the Database. RMAN is configured for compressed backupsets as
     default, controlfile autobackups and the length of the recovery window is
     configured. Finally, an existing crontab is saved to the HOME directory of
     the calling user and three cronjobs are defined in the new crontab:
     weekly full backups, daily incremental backups and hourly checks if the
     required backups did execute.
     This command prompts for input of the day and time for the weekly full
     backup, the time for the daily backup, the length of the recovery window
     and the number of days a incrementally updatable backup should stay
     behind the current time.
EOF
}

usage()
{
cat << EOF
Usage: `basename $MYFULLPATH` {rmanfull|rmandaily|backupcheck|catalogbackup|setupbackup}
EOF
echo "type \"yes\" for long description"
read line
case $line in
  yes) long_usage;;
  *)
esac
}

dbms_scheduler_test()
{
  /bin/date >> /home/oracle/joblog.txt
}

adminsetup()
{
sqlplus / as sysdba << EOF
set serveroutput on

CREATE OR REPLACE package etk as 
   g_interval      varchar2(50):='freq=minutely';
   g_startdate     timestamp with time zone:=systimestamp;
   g_script        varchar2(50):='/home/oracle/bin/oracle.bash';
   g_scriptcommand varchar2(50):='test';
   g_osuser        varchar2(50):='oracle';
   g_ospasswd      varchar2(50):='wrhkxaN4HhB7jwb3W';

   procedure execute_admin_job;
   procedure setup;
end etk;
/


CREATE OR REPLACE package body etk as

   job_rec        sys.dba_scheduler_jobs%rowtype;
   program_rec    sys.dba_scheduler_programs%rowtype;
   credential_rec sys.dba_scheduler_credentials%rowtype;
   jname          sys.dba_scheduler_jobs.job_name%TYPE:='ETK_ADMIN_JOB';
   pname          sys.dba_scheduler_programs.program_name%TYPE:='ETK_ADMIN_PROG';
   cname          sys.dba_scheduler_credentials.credential_name%TYPE:='ETK_ORACLE';
   cursor c_scheduler_job is
      select * from dba_scheduler_jobs
      where owner='SYS' and job_name=jname;
   cursor c_scheduler_program is
      select * from dba_scheduler_programs
      where owner='SYS' and program_name=pname;
   cursor c_scheduler_credential is
      select * from dba_scheduler_credentials
      where owner='SYS' and username=g_osuser and credential_name=cname;

   function is_archivelogmode return boolean as
      numrows number;
      retval boolean:=TRUE;
   begin
      select count(*) into numrows from v\$database where log_mode!='ARCHIVELOG';
      if numrows > 0 then
         retval:=FALSE;
      end if;
      return retval;
   end is_archivelogmode;
   
   procedure execute_admin_job as
   begin
      --create_immediate_external_job('ETK_EXTERNAL_IMMEDIATE_JOB',command);
      dbms_output.put_line('teststring');
   end execute_admin_job;

   procedure setup as

   begin
      dbms_output.put_line('.');
      dbms_output.put_line('*** start of etk.setup()');
      -- exit if database is not in archivelog mode
      if not is_archivelogmode() then
         dbms_output.put_line('DB is not in archivelog mode. Aborting');
         return;
      end if;
      
      -- delete administration jobs/program/credential if present
      jname := 'ETK_ADMIN_JOB';
      open c_scheduler_job;
      loop
         fetch c_scheduler_job into job_rec;
         exit when c_scheduler_job%notfound;
         dbms_output.put_line('dbms_scheduler.drop_job('''||job_rec.job_name||''',true,false);');
         dbms_scheduler.drop_job(job_rec.job_name, true, false);
      end loop;
      close c_scheduler_job;

      pname:='ETK_ADMIN_PROG';
      open c_scheduler_program;
      loop
         fetch c_scheduler_program into program_rec;
         exit when c_scheduler_program%notfound;
         dbms_output.put_line('dbms_scheduler.drop_program('''||program_rec.program_name||''',true);');
         dbms_scheduler.drop_program(program_rec.program_name,true);
      end loop;
      close c_scheduler_program;

      cname:='ETK_ORACLE';
      open c_scheduler_credential;
      loop
         fetch c_scheduler_credential into credential_rec;
         exit when c_scheduler_credential%notfound;
         dbms_output.put_line('dbms_scheduler.drop_credential('''||credential_rec.credential_name||''',true);');
         dbms_scheduler.drop_credential(credential_rec.credential_name,true);
      end loop;
      close c_scheduler_credential;

    -- create administration jobs
    dbms_output.put_line('dbms_scheduler.create_program(program_name=>''ETK_ADMIN_PROG''');
    dbms_output.put_line(',                             program_type=>''EXECUTABLE''');
    DBMS_OUTPUT.PUT_LINE(',                             program_action=>'''||g_script||'''');
    DBMS_OUTPUT.PUT_LINE(',                             number_of_arguments=>1');
    dbms_output.put_line(',                             enabled=>false);');
    dbms_scheduler.create_program(program_name=>'ETK_ADMIN_PROG'
                                 ,program_type=>'EXECUTABLE'
                                 ,PROGRAM_ACTION=>g_script
                                 ,NUMBER_OF_ARGUMENTS=>1
                                 ,ENABLED=>FALSE);
    DBMS_OUTPUT.PUT_LINE('dbms_scheduler.define_program_argument(program_name=>''ETK_ADMIN_PROG''');
    DBMS_OUTPUT.PUT_LINE('                                      ,argument_position=>''1''');
    DBMS_OUTPUT.PUT_LINE('                                      ,argument_name=>''COMMAND''');
    dbms_output.put_line('                                      ,argument_type=>''VARCHAR2''');
    DBMS_OUTPUT.PUT_LINE('                                      ,default_value=>'''||g_scriptcommand||'''');
    dbms_output.put_line('                                      ,OUT_ARGUMENT=>FALSE);');
    dbms_scheduler.define_program_argument(program_name=>'ETK_ADMIN_PROG'
                                          ,argument_position=>'1'
                                          ,argument_name=>'COMMAND'
                                          ,argument_type=>'VARCHAR2'
                                          ,default_value=>g_scriptcommand
                                          ,OUT_ARGUMENT=>FALSE);
    DBMS_OUTPUT.PUT_LINE('dbms_scheduler.enable(name=>''ETK_ADMIN_PROG'');');                                    
    DBMS_SCHEDULER.ENABLE(NAME=>'ETK_ADMIN_PROG');                                    

    dbms_output.put_line('dbms_scheduler.create_job(job_name=>''ETK_ADMIN_JOB''');
    dbms_output.put_line(',                         program_name=>''ETK_ADMIN_PROG''');
    dbms_output.put_line(',                         start_date=>'||g_startdate);
    dbms_output.put_line(',                         end_date=>NULL');
    DBMS_OUTPUT.PUT_LINE(',                         repeat_interval=>'''||g_interval||'''');
    dbms_output.put_line(',                         enabled=>false)');
    dbms_scheduler.create_job(job_name=>'ETK_ADMIN_JOB'
                             ,program_name=>'ETK_ADMIN_PROG'
                             ,start_date=>g_startdate
                             ,end_date=>null
                             ,repeat_interval=>g_interval
                             ,enabled=>false);
    dbms_scheduler.create_credential(credential_name=>'ETK_ORACLE'
                                    ,username=>g_osuser
                                    ,password=>g_ospasswd);                                    
    DBMS_SCHEDULER.SET_ATTRIBUTE(NAME=>'ETK_ADMIN_JOB'
                                ,ATTRIBUTE=>'CREDENTIAL_NAME'
                                ,value=>'ETK_ORACLE');
    dbms_scheduler.enable(name=>'ETK_ADMIN_JOB');

   end setup;

end etk;
/

begin
   etk.setup;
end;
/

EOF
}

case "$1" in
    testfunc) ;;
    rmanfull) ;;
    rmandaily) ;;
    backupcheck) ;;
    catalogbackup) ;;
    setupbackup) ;;
    test) ;;
    adminsetup) ;;
    *)
    usage; exit;
esac

if (( ! $IS_TERMINAL ));then
  exec 3<&1            # save stdout to file descriptor 3
  exec 1>>${CRONLOG}   # redirect stdout
  exec 2>&1            # redirect stderr
fi

# exit, if another operation from this script is
# on the fly
if ( set -o noclobber; echo "$$" > "${PIDFILE}") 2> /dev/null; 
then
   trap 'rm -f "${PIDFILE}"; exit $?' INT TERM EXIT
else
   PID=$(cat ${PIDFILE})
   if ps -p ${PID} &> /dev/null ;then
     echo "****************************************"
     echo "*** `basename ${MYFULLPATH}` called ${STARTED_BY}"
     echo "*** `date` : Failed to acquire lockfile: ${PIDFILE}." 
     echo -e "*** Held by process with PID ${PID}\n"
     exit
   else
     rm ${PIDFILE}
     if ( set -o noclobber; echo "$$" > "${PIDFILE}") 2> /dev/null; 
     then
        trap 'rm -f "${PIDFILE}"; exit $?' INT TERM EXIT
     else
        if ps -p ${PID} &>/dev/null ;then
          echo "****************************************"
          echo "*** `basename ${MYFULLPATH}` called ${STARTED_BY}"
          echo "*** `date` : Failed to acquire lockfile: ${PIDFILE}." 
          echo -e "*** Held by process with PID ${PID})\n"
          exit
        fi
     fi
   fi
fi
if (( ! $IS_TERMINAL ));then
  exec 1>&3            # restore stdout
  exec 3>&-            # close temporary fd 3
  exec 2>&1            # redirect stderr to stdout
fi

case "$1" in
    testfunc)
      testfunc
      ;;
    rmanfull)
      rmanfull
      ;;
    rmandaily)
      rmandaily
      ;;
    backupcheck)
      backupcheck
      ;;
    catalogbackup)
      catalogbackup
      ;;
    setupbackup)
      setupbackup
      ;;
    test)
      dbms_scheduler_test
      ;;
    adminsetup)
      adminsetup
      ;;
    *)
      usage;
esac

rm -f "${PIDFILE}"
trap - INT TERM EXIT

exit

