-- Source: https://developercommunity.visualstudio.com/content/problem/382983/tfs-2018-update-2-database-growing-too-large.html
-- Added an order by

-- Finds biggest contributors to the TeamTest content of the database

SELECT B.DefinitionName, B.DefinitionID, A.AttachmentType, SUBSTRING(a.filename,len(a.filename)-CHARINDEX('.',REVERSE(a.filename))+2,999)as Extension, COUNT(A.AttachmentId) [numAttachments], SUM(FM.CompressedLength)/1024.0/1024.0/1024.0 [GB]
FROM Build.tbl_Definition B
JOIN tbl_BuildConfiguration BC ON BC.BuildDefinitionID = B.DefinitionID
JOIN tbl_TestRun TR ON TR.BuildConfigurationID = BC.BuildConfigurationID
JOIN tbl_Attachment A ON A.TestRunId = TR.TestRunId
JOIN tbl_FileReference FR ON FR.FileId = A.TfsFileId
JOIN tbl_FileMetadata FM ON FM.PartitionId = FR.PartitionId and FM.ResourceId = FR.ResourceId
WHERE FR.PartitionId = 1/*there seems to only ever be one partitionID, and this improves query performance*/
AND A.CreationDate < DATEADD(DAY, -60, GETUTCDATE()) /*is older than the B.RetentionPolicy indicates it should be*/
GROUP BY B.DefinitionName, B.DefinitionID, A.AttachmentType, SUBSTRING(a.filename,len(a.filename)-CHARINDEX('.',REVERSE(a.filename))+2,999)
order by GB desc
