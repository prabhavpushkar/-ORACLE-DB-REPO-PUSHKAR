----STEPS TO CONVERT PHYSICAL ACTIVE STANDBY DATABASE INTO READ-WRITE-MODE FOR APP TESTING AND ROLLBACK CHANGES POST ACTIVITY-
--STEPS - 
-a) Ensure primary and standby are in complete sync before starting this activity

SELECT ARCH.THREAD# “Thread”, ARCH.SEQUENCE# “Last Sequence Received”, APPL.SEQUENCE# “Last Sequence Applied”,
(ARCH.SEQUENCE# – APPL.SEQUENCE#) “Difference”
FROM (SELECT THREAD# ,SEQUENCE# FROM V$ARCHIVED_LOG WHERE (THREAD#,FIRST_TIME ) IN (SELECT THREAD#,MAX(FIRST_TIME) FROM V$ARCHIVED_LOG GROUP BY THREAD#)) ARCH,
(SELECT THREAD# ,SEQUENCE# FROM V$LOG_HISTORY WHERE (THREAD#,FIRST_TIME ) IN (SELECT THREAD#,MAX(FIRST_TIME)
FROM V$LOG_HISTORY GROUP BY THREAD#)) APPL
WHERE ARCH.THREAD# = APPL.THREAD#;

-b) Configure Flash Recovery Area ( FRA ) and allocate enough space to it as per test window-

ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE=500G;
 ALTER SYSTEM SET DB_RECOVERY_FILE_DEST=’+FRA’;
 
 col name format a10
clear breaks
clear computes
select name
, round(space_limit / 1024 / 1024) size_mb
, round(space_used / 1024 / 1024) used_mb
, decode(nvl(space_used,0),0,0,round((space_used/space_limit) * 100)) pct_used
from v$recovery_file_dest
order by name
/

--c) Cancel redo apply and enable flashback-
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
ALTER DATABSAE FLASHBACK ON;

--d) create a GRP (GUARANTEED RESTORE POINT)
SELECT NAME,TIME, DATABASE_INCARNATION#, GUARANTEE_FLASHBACK_DATABASE, STORAGE_SIZE FROM V$RESTORE_POINT WHERE
GUARANTEE_FLASHBACK_DATABASE=’YES’;
CREATE RESTORE POINT GRPTEST GUARANTEE FLASHBACK DATABASE;

--e) STOP All standby database instances with srvctl and open any one instance in mount state - 
srvctl stop database -d dbname
srvctl start instance -i <instance_name> -d <dbname> -o mount

--f) open standby in read-write and start all instances.
ALTER DATABASE ACTIVATE STANDBY DATABASE;
ALTER DATABASE OPEN;
srvctl stop database -d dbname
srvctl start database -d dbname

--g) Once the activity is over. Shutdown all instances of standby and start standby in mount mode from 1st instance.
--Flashback the standby with restore point created.
STARTUP MOUNT FORCE;
FLASHBACK DATABASE TO RESTORE POINT GRPTEST;

--h) Convert database to active standby again - 
ALTER DATABASE CONVERT TO PHYSICAL STANDBY;
STARTUP MOUNT FORCE;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT;
ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;

--I) DROP GRP AND DISABLE FLASHBACK -
DROP RESTORE POINT GRPTEST;
ALTER DATABASE FLASHBACK OFF;


