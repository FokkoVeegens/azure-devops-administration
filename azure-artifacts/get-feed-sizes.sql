-- Source: https://stackoverflow.com/questions/58743312/is-there-any-way-to-find-the-feed-size-in-azure-artifacts
-- Changes made to the above solution:
--   * Get Team Project info along with the other data
--   * Rounded the size to 1 decimal
--   * Added column names
--   * Added column to indicate if a feed has been deleted

-- First part retrieves storage usage per feed

SELECT ISNULL(proj.project_name, '**Collection Feed**') TeamProject,
       f.FeedName Feed,
       FORMAT(ROUND(SUM(CAST(list.BlockFileLength AS DECIMAL(38)))/1024.0/1024.0, 1), '0.0') SizeInMb,
       CASE 
         WHEN f.DeletedDate IS NULL THEN 'FALSE' 
	 ELSE 'TRUE' 
       END IsDeleted
FROM BlobStore.tbl_Blob blob
   INNER JOIN BlobStore.tbl_BlockList list ON list.BlobId = blob.BlobId
   INNER JOIN Feed.tbl_PackageVersionIndex fd ON '0x'+fd.StorageId = CONVERT(VARCHAR(MAX),blob.BlobId ,1) 
   INNER JOIN Feed.tbl_Feed f ON fd.FeedId = f.FeedId
   INNER JOIN Feed.tbl_PackageIndex p ON p.PackageId = fd.PackageId
   LEFT OUTER JOIN dbo.tbl_Dataspace d ON f.DataspaceId = d.DataspaceId
   LEFT OUTER JOIN dbo.tbl_Projects proj ON d.DataspaceIdentifier = proj.project_id
GROUP BY proj.project_name,
         f.FeedName,
	 CASE WHEN f.DeletedDate IS NULL THEN 'FALSE' ELSE 'TRUE' END
ORDER BY SizeInMb DESC

-- Second part retrieves storage usage per individual package

SELECT f.FeedName,
	p.PackageName,
	SUM(CAST(list.BlockFileLength AS DECIMAL(38))) / 1024.0 / 1024.0 AS SizeInMb,
	(
		SELECT COUNT(pvi.PackageVersionId)
		FROM Feed.tbl_PackageVersionIndex pvi
		WHERE pvi.FeedId = f.FeedId
			AND pvi.PackageId = p.PackageId
		) AS Versions
FROM BlobStore.tbl_Blob blob
	INNER JOIN BlobStore.tbl_BlockList list ON list.BlobId = blob.BlobId
	INNER JOIN Feed.tbl_PackageVersionIndex fd ON '0x' + fd.StorageId = CONVERT(VARCHAR(MAX), blob.BlobId, 1)
	INNER JOIN Feed.tbl_Feed f ON fd.FeedId = f.FeedId
	INNER JOIN Feed.tbl_PackageIndex p ON p.PackageId = fd.PackageId
GROUP BY f.FeedName,
	p.PackageName,
	f.FeedId,
	p.PackageId
ORDER BY SizeInMb DESC
