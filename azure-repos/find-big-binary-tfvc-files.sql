-- Source: https://www.marcusfelling.com/blog/2020/how-to-reduce-the-size-of-your-tfs-azure-devops-server-collection-databases/
-- Query for Big Binary TFVC Files, including the last update of project
DECLARE @partitionId INT = 1 
SELECT p.project_name, 
       SUM (CONVERT(BIGINT, fm.CompressedLength, 2)) AS TotalProjectBytes,
          p.last_update
FROM   tbl_FileReference fr 
INNER LOOP JOIN   tbl_FileMetadata fm 
ON     fm.PartitionId = fr.PartitionId 
       AND fm.ResourceId = fr.ResourceId 
JOIN   tbl_Dataspace ds 
ON     ds.PartitionId = fr.PartitionId 
       AND ds.DataspaceId = fr.DataspaceId 
LEFT JOIN   tbl_projects p 
ON     p.PartitionId = fr.PartitionId 
       AND p.project_id = ds.DataspaceIdentifier 
WHERE  fr.PartitionId = @partitionId 
       AND fr.OwnerId = 1 
       AND fr.FileName IS NULL
GROUP BY p.project_name, p.last_update
OPTION (OPTIMIZE FOR (@partitionId UNKNOWN))
