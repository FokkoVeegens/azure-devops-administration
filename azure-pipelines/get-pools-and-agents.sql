-- Gets all Agent Pools and Agents in the Pools
-- In newer environments, Tfs_Configuration will be named AzureDevOps_Configuration

use Tfs_Configuration
select p.PoolId,
		p.PoolName,
		case p.PoolType when 1 then 'automation' when 2 then 'deployment' else 'unknown' end as TypeOfPool,
		a.AgentId, 
		a.AgentName, 
		a.AgentVersion, 
		a.Enabled,
		c.Value ComputerName,
		u.Value UserProfileDir,
		h.Value AgentHomeDir
from Task.tbl_AgentPool p
	inner join Task.tbl_Agent a on p.PoolId = a.PoolId
	left outer join Task.tbl_AgentCapability c on a.AgentId = c.AgentId and c.Name = 'Agent.ComputerName'
	left outer join Task.tbl_AgentCapability u on a.AgentId = u.AgentId and u.Name = 'USERPROFILE'
	left outer join Task.tbl_AgentCapability h on a.AgentId = h.AgentId and h.Name = 'Agent.HomeDirectory'
order by PoolName, AgentName
