-- Source: https://jessehouwing.net/tfs-clean-up-your-project-collection/
-- Specifies per content type which are the largetst contributors to FileContainers
-- First run get-largest-content-contributors.sql to find out if FileContainers are indeed the largest contributor

DECLARE @partitionId INT = 1

SELECT  CASE
            WHEN ArtifactUri LIKE 'vstfs:///%'
            THEN SUBSTRING(ArtifactUri, 10, CHARINDEX('/', ArtifactUri, 10) - 10)
            ELSE ArtifactUri
        END,
        SUM(cast(ci.FileLength as decimal(38)))/1024.0/1024.0 AS SizeInMb,
        COUNT(*) AS Records,
        d.DataspaceIdentifier        
FROM    tbl_Container c
JOIN    (
            SELECT  ci.FileId,
                    ci.DataspaceId,
                    MAX(ci.FileLength) AS FileLength,
                    MAX(ci.ContainerId) AS ContainerId
            FROM    tbl_ContainerItem ci
            WHERE   ci.PartitionId = @partitionId
            GROUP BY ci.FileId, ci.DataspaceId
        ) AS ci
ON      ci.ContainerId = c.ContainerId
JOIN    tbl_Dataspace d
ON      d.DataspaceId = ci.DataspaceId
WHERE   c.PartitionId = @partitionId
        AND d.PartitionId = @partitionId
GROUP BY CASE
            WHEN ArtifactUri LIKE 'vstfs:///%'
            THEN SUBSTRING(ArtifactUri, 10, CHARINDEX('/', ArtifactUri, 10) - 10)
            ELSE ArtifactUri
        END,
        d.DataspaceIdentifier
ORDER BY SizeInMb DESC
