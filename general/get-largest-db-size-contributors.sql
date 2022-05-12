-- Source: https://jessehouwing.net/tfs-clean-up-your-project-collection/
-- Gets largest content contributors by type
-- Tweaked to get INT result for MB's (more readability)

SELECT Owner = 
    CASE
        WHEN OwnerId = 0 THEN 'Generic' 
        WHEN OwnerId = 1 THEN 'VersionControl'
        WHEN OwnerId = 2 THEN 'WorkItemTracking'
        WHEN OwnerId = 3 THEN 'TeamBuild'
        WHEN OwnerId = 4 THEN 'TeamTest'
        WHEN OwnerId = 5 THEN 'Servicing'
        WHEN OwnerId = 6 THEN 'UnitTest'
        WHEN OwnerId = 7 THEN 'WebAccess'
        WHEN OwnerId = 8 THEN 'ProcessTemplate'
        WHEN OwnerId = 9 THEN 'StrongBox'
        WHEN OwnerId = 10 THEN 'FileContainer'
        WHEN OwnerId = 11 THEN 'CodeSense'
        WHEN OwnerId = 12 THEN 'Profile'
        WHEN OwnerId = 13 THEN 'Aad'
        WHEN OwnerId = 14 THEN 'Gallery'
        WHEN OwnerId = 15 THEN 'BlobStore'
        WHEN OwnerId = 255 THEN 'PendingDeletion'
    END,
    CONVERT(INT, ROUND((SUM(CompressedLength) / 1024.0 / 1024.0), 0)) AS BlobSizeInMB
FROM tbl_FileReference AS r
JOIN tbl_FileMetadata AS m
    ON r.ResourceId = m.ResourceId
    AND r.PartitionId = m.PartitionId
WHERE r.PartitionId = 1
GROUP BY OwnerId
ORDER BY 2 DESC
