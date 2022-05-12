-- This will shrink a log file of a database for which the Recovery model is set to Full
-- The script might need several runs before the desired amount of space is freed up
-- Keep in mind that running it several times will overwrite the existing transaction log backups
-- WARNING! Replace "MYDB" with the name of your database everywhere in this script using search and replace functionality of your editor
-- WARNING! Replace "C:\MYPATH" with the path on disk to the location where you want to store the transaction log backup
-- WARNING! Check if the Log File name on line 13 matches the name of your own log file name

Use [master] 
BACKUP LOG [MYDB] TO  DISK = N'C:\MYPATH\MYDB.TRN' WITH NOFORMAT, INIT,  NAME = N'MYDB-Transaction Log Backup', SKIP, NOREWIND, NOUNLOAD,  STATS = 10
GO
USE [MYDB]
GO
DBCC SHRINKFILE (N'MYDB_log' , 0, TRUNCATEONLY)
GO
