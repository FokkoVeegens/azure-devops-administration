-- Get the per-project provisioned Agent Queues, with project name and the Agent Pool they are linked to
-- Make sure you check if your Configuration Database (on the last line of the script) is called Tfs_Configuration or differently and change it accordingly

select p.ProjectId,
		p.ProjectName,
		p.IsDeleted ProjectIsDeleted,
		q.QueueId,
		q.QueueName,
		case q.QueueType when 1 then 'automation' when 2 then 'deployment' else 'unknown' end as QueueTypeString,
		ap.PoolId,
		ap.PoolName
from Task.tbl_Queue q
	inner join tbl_Dataspace d on q.DataspaceId = d.DataspaceId
	inner join tbl_Project p on ('vstfs:///Classification/TeamProject/' + convert(varchar(50), d.DataspaceIdentifier)) = p.ProjectUri
	inner join Tfs_Configuration.Task.tbl_AgentPool ap on q.PoolId = ap.PoolId
