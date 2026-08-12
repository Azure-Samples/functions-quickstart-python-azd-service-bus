$ErrorActionPreference = "Stop"

Write-Host "Running post-provision script..." -ForegroundColor Yellow

$outputs = azd env get-values --output json | ConvertFrom-Json
$ServiceBusNamespace = $outputs.SERVICE_BUS_CONNECTION__fullyQualifiedNamespace
$ServiceBusQueueName = $outputs.SERVICE_BUS_QUEUE_NAME

Write-Host "Creating/updating src/local.settings.json..." -ForegroundColor Yellow

@{
    "IsEncrypted" = $false
    "Values" = @{
        "AzureWebJobsStorage" = "UseDevelopmentStorage=true"
        "FUNCTIONS_WORKER_RUNTIME" = "python"
        "ServiceBusConnection__fullyQualifiedNamespace" = "$ServiceBusNamespace"
        "ServiceBusQueueName" = "$ServiceBusQueueName"
    }
} | ConvertTo-Json | Out-File -FilePath ".\src\local.settings.json" -Encoding ascii -Force

Write-Host "src/local.settings.json has been created/updated successfully!" -ForegroundColor Green
Write-Host "Creating/updating send-message.ps1..." -ForegroundColor Yellow

"az rest --method POST --uri 'https://$ServiceBusNamespace/$ServiceBusQueueName/messages' --headers 'Content-Type=application/atom+xml;type=entry;charset=utf-8' --body 'Hello from the CLI' --resource 'https://servicebus.azure.net'" | Out-File -FilePath ".\send-message.ps1" -Encoding ascii -Force

Write-Host "send-message.ps1 has been created successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Service Bus Namespace: $ServiceBusNamespace" -ForegroundColor Cyan
Write-Host "Service Bus Queue: $ServiceBusQueueName" -ForegroundColor Cyan
Write-Host ""
Write-Host "You can now run the function locally with 'cd src && func start'" -ForegroundColor Green
Write-Host "Send test messages with './send-message.ps1'" -ForegroundColor Green