# This script retrieves the Json describing a Visual Studio Marketplace extension
# I created this because the page of one of the extensions wouldn't load due to redirect overload
# It's useful for example to retrieve the latest version of the extension
# The data in the $publisher/$extension variables is example data and was not the problematic extension. Replace with your own

$publisher = "ms"
$extension = "vss-code-search"
$outputFile = "C:\temp\extensiondata.json"

$marketplaceUri = "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"

$headers = @{'Accept' = 'application/json;api-version=7.1-preview.1;excludeUrls=true'; 'Content-Type' = 'application/json'}
$payload = "{`"assetTypes`":null,`"filters`":[{`"criteria`":[{`"filterType`":7,`"value`":`"$($publisher).$($extension)`"}],`"direction`":2,`"pageSize`":100,`"pageNumber`":1,`"sortBy`":0,`"sortOrder`":0,`"pagingToken`":null}],`"flags`":2151}"
$response = Invoke-WebRequest -Uri $marketplaceUri -Method POST -Body $payload -Headers $headers
$response.Content | Out-File -FilePath $outputFile
