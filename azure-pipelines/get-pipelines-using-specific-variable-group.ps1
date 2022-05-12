$org = "https://dev.azure.com/myorg"
$project = "My First Project"
$vargroupname = "Name of my vargroup"

$vargroupid = (az pipelines variable-group list --org $org --project $project --group-name $vargroupname | ConvertFrom-Json).id
$pipelines = az pipelines release definition list --org $org --project $project | ConvertFrom-Json

foreach ($pipeline in $pipelines)
{
    $extpipeline = az pipelines release definition show --org $org --project $project --name $pipeline.name | ConvertFrom-Json
    if ($extpipeline.variableGroups -contains $vargroupid)
    {
        Write-Host "Found in $($pipeline.name)" -ForegroundColor Green
    }
    else {
        Write-Host $pipeline.name
    }
}
