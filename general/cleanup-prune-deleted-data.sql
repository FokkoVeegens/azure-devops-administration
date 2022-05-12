-- Source: https://jessehouwing.net/tfs-clean-up-your-project-collection/
-- Cleans up data that is deleted. This is normally done by jobs in Azure DevOps, but these don't run very frequently

EXEC prc_CleanupDeletedFileContent 1

-- 500 is the batch size, default is 100. Increase this and it might be faster, but will consume a lot of resources (disk activity and TempDB space!)
EXEC prc_DeleteUnusedFiles 1, 0, 500
