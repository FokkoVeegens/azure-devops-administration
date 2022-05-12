-- Retrieves the total size of the TFVC repos in a collection
-- Warning: this script might run for a while and consume quite some resources; please run this first in a test environment!
-- This query is based on the query provided by Andrew Kanieski: https://www.andrewkanieski.com/post/azure-devops-tfvc-cleanup/

SELECT proj.ProjectName,
        SUM(ROUND(CAST(CAST(meta.FileLength AS FLOAT) / 1024 / 1024 AS FLOAT), 2) ) SizeInMb
FROM tbl_FileMetadata meta
       LEFT JOIN tbl_FileReference ref ON ref.ResourceId = meta.ResourceId
       LEFT JOIN tbl_Version ver ON ver.FileId = ref.FileId AND ver.ItemType = 2
       LEFT JOIN AnalyticsModel.tbl_Project proj ON proj.ProjectSK = CONVERT(UNIQUEIDENTIFIER, REPLACE(SUBSTRING(UPPER(ver.FullPath), 3, CHARINDEX('\', ver.FullPath, 3) - 3), '"', '-'))
WHERE ver.FullPath IS NOT NULL
GROUP BY proj.ProjectName
