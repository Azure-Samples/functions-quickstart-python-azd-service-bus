$ErrorActionPreference = "Stop"

Write-Host "Running post-provision script..." -ForegroundColor Yellow

$outputJson = azd env get-values --output json
if ($LASTEXITCODE -ne 0) {
    throw "Failed to get environment values from azd."
}

$outputs = $outputJson | ConvertFrom-Json
$ServiceBusNamespace = $outputs.SERVICE_BUS_CONNECTION__fullyQualifiedNamespace
$ServiceBusQueueName = $outputs.SERVICE_BUS_QUEUE_NAME

if ([string]::IsNullOrWhiteSpace($ServiceBusNamespace) -or [string]::IsNullOrWhiteSpace($ServiceBusQueueName)) {
    throw "SERVICE_BUS_CONNECTION__fullyQualifiedNamespace or SERVICE_BUS_QUEUE_NAME is missing from the azd environment."
}

$settingsPath = Join-Path "src" "local.settings.json"
if (Test-Path $settingsPath) {
    # Never overwrite an existing local.settings.json; it may contain your own values.
    $existingSettings = $null
    $existingJson = Get-Content $settingsPath -Raw
    try {
        if (-not [string]::IsNullOrWhiteSpace($existingJson)) {
            $existingSettings = $existingJson | ConvertFrom-Json
        }
    }
    catch [System.ArgumentException] {
        $existingSettings = $null
    }

    if ($existingSettings -isnot [System.Management.Automation.PSCustomObject]) {
        Write-Host "  ServiceBusConnection__fullyQualifiedNamespace = $ServiceBusNamespace" -ForegroundColor Cyan
        Write-Host "  ServiceBusQueueName = $ServiceBusQueueName" -ForegroundColor Cyan
        throw "src/local.settings.json isn't valid JSON and was not changed. Fix the file, or delete it and run 'azd provision' again to recreate it. The provisioned values are shown above."
    }

    $existingValues = $existingSettings.Values
    if ($existingValues -is [System.Management.Automation.PSCustomObject] -and
        $existingValues.ServiceBusConnection__fullyQualifiedNamespace -eq $ServiceBusNamespace -and
        $existingValues.ServiceBusQueueName -eq $ServiceBusQueueName) {
        Write-Host "src/local.settings.json already exists and references the provisioned resources." -ForegroundColor Green
    }
    else {
        Write-Host "src/local.settings.json already exists and was not changed. Update these values in it to use the provisioned resources:" -ForegroundColor Yellow
        Write-Host "  ServiceBusConnection__fullyQualifiedNamespace = $ServiceBusNamespace" -ForegroundColor Cyan
        Write-Host "  ServiceBusQueueName = $ServiceBusQueueName" -ForegroundColor Cyan
    }
}
else {
    Write-Host "Creating src/local.settings.json..." -ForegroundColor Yellow
    [ordered]@{
        "IsEncrypted" = $false
        "Values" = [ordered]@{
            "AzureWebJobsStorage" = "UseDevelopmentStorage=true"
            "FUNCTIONS_WORKER_RUNTIME" = "python"
            "ServiceBusConnection__fullyQualifiedNamespace" = "$ServiceBusNamespace"
            "ServiceBusQueueName" = "$ServiceBusQueueName"
        }
    } | ConvertTo-Json | Out-File -FilePath $settingsPath -Encoding utf8
    Write-Host "src/local.settings.json has been created successfully!" -ForegroundColor Green
}

Write-Host "Creating/updating send-message.ps1..." -ForegroundColor Yellow

@"
az rest --method POST --uri 'https://$ServiceBusNamespace/$ServiceBusQueueName/messages' --headers 'Content-Type=application/atom+xml;type=entry;charset=utf-8' --body 'Hello from the CLI' --resource 'https://servicebus.azure.net'
exit `$LASTEXITCODE
"@ | Out-File -FilePath ".\send-message.ps1" -Encoding utf8 -Force

Write-Host "send-message.ps1 has been created successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Service Bus Namespace: $ServiceBusNamespace" -ForegroundColor Cyan
Write-Host "Service Bus Queue: $ServiceBusQueueName" -ForegroundColor Cyan
Write-Host ""
Write-Host "Running locally and sending test messages from your machine require VNET_ENABLED=false." -ForegroundColor Yellow
Write-Host "You can now run the function locally with 'cd src && func start'" -ForegroundColor Green
Write-Host "Send test messages with './send-message.ps1'" -ForegroundColor Green