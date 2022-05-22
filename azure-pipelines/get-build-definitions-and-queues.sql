-- Retrieves all build definitions and the Agent Queues they use

select d.DefinitionId,
		d.DefinitionName,
		q.QueueName
from Build.tbl_Definition d
	left outer join Task.tbl_Queue q on d.QueueId = q.QueueId
where d.Deleted = 0
