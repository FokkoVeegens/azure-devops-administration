-- This query retrieves the size of the build artifacts and logs per Build Pipeline (Definition)
-- It is not yet optimized for big databases, so be careful when executing these
-- The queries are based on a query written by Jesse Houwing and it can be found here: https://jessehouwing.net/tfs-clean-up-your-project-collection/

DECLARE @partitionId INT = 1
DECLARE @toreplace VARCHAR(255) = 'vstfs:///Build/Build/'
 
-- Build Artifacts

SELECT p.ProjectName,
       d.BuildPipelineId,
       d.BuildPipelineName,
       SUM(CAST(ci.FileLength AS DECIMAL(38)))/1024.0/1024.0 AS ArtifactSizeInMb,
       d.IsDeleted
FROM tbl_Container c
       LEFT OUTER JOIN (
            SELECT  ci.FileId,
                    ci.DataspaceId,
                    MAX(ci.FileLength) AS FileLength,
                    MAX(ci.ContainerId) AS ContainerId
            FROM    tbl_ContainerItem ci
            WHERE   ci.PartitionId = @partitionId
            GROUP BY ci.FileId, ci.DataspaceId
            ) AS ci ON ci.ContainerId = c.ContainerId
       INNER JOIN Build.tbl_Build b on CASE CHARINDEX('?', c.ArtifactUri)
                                          WHEN 0 THEN REPLACE(c.ArtifactUri, @toreplace, '')
                                          ELSE CONVERT(int, LEFT(REPLACE(c.ArtifactUri, @toreplace, ''), CHARINDEX('?', c.ArtifactUri) - LEN(@toreplace) - 1))
                                       END = b.BuildId
       INNER JOIN AnalyticsModel.tbl_BuildPipeline d ON b.DefinitionId = d.BuildPipelineId
       INNER JOIN AnalyticsModel.tbl_Project p ON d.ProjectSK = p.ProjectSK
WHERE c.ArtifactUri LIKE 'vstfs:///Build/Build/%'
GROUP BY p.ProjectName,
         d.BuildPipelineId,
         d.BuildPipelineName,
         d.IsDeleted

-- Build logs

SELECT p.ProjectName,
       d.BuildPipelineId,
       d.BuildPipelineName,
       SUM(CAST(ci.FileLength AS DECIMAL(38)))/1024.0/1024.0 AS LogsSizeInMb,
       d.IsDeleted
FROM tbl_Container c
       LEFT OUTER JOIN (
            SELECT  ci.FileId,
                    ci.DataspaceId,
                    MAX(ci.FileLength) AS FileLength,
                    MAX(ci.ContainerId) AS ContainerId
            FROM    tbl_ContainerItem ci
            WHERE   ci.PartitionId = @partitionId
            GROUP BY ci.FileId, ci.DataspaceId
            ) AS ci ON ci.ContainerId = c.ContainerId
       INNER JOIN Build.tbl_Build b ON CASE CHARINDEX('?', c.SecurityToken)
                                          WHEN 0 THEN REPLACE(c.SecurityToken, @toreplace, '')
                                          ELSE CONVERT(int, LEFT(REPLACE(c.SecurityToken, @toreplace, ''), CHARINDEX('?', c.SecurityToken) - LEN(@toreplace) - 1)) 
                                       END = b.BuildId
       INNER JOIN AnalyticsModel.tbl_BuildPipeline d ON b.DefinitionId = d.BuildPipelineId
       INNER JOIN AnalyticsModel.tbl_Project p ON d.ProjectSK = p.ProjectSK
WHERE c.ArtifactUri LIKE 'pipelines://build/%'
GROUP BY p.ProjectName,
         d.BuildPipelineId,
         d.BuildPipelineName,
         d.IsDeleted
