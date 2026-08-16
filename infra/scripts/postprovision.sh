#!/bin/bash
set -e

echo "Running post-provision script..."
output=$(azd env get-values)

while IFS= read -r line; do
    if [[ $line == SERVICE_BUS_CONNECTION__fullyQualifiedNamespace* ]]; then
        ServiceBusNamespace=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
    elif [[ $line == SERVICE_BUS_QUEUE_NAME* ]]; then
        ServiceBusQueueName=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
    fi
done <<< "$output"

echo "Creating/updating src/local.settings.json..."

cat > ./src/local.settings.json << EOF
{
    "IsEncrypted": false,
    "Values": {
        "AzureWebJobsStorage": "UseDevelopmentStorage=true",
        "FUNCTIONS_WORKER_RUNTIME": "python",
        "ServiceBusConnection__fullyQualifiedNamespace": "$ServiceBusNamespace",
        "ServiceBusQueueName": "$ServiceBusQueueName"
    }
}
EOF

echo "src/local.settings.json has been created/updated successfully!"
echo "Creating/updating send-message.sh..."
echo "az rest --method POST --uri \"https://$ServiceBusNamespace/$ServiceBusQueueName/messages\" --headers \"Content-Type=application/atom+xml;type=entry;charset=utf-8\" --body \"Hello from the CLI\" --resource \"https://servicebus.azure.net\"" > ./send-message.sh
chmod +x ./send-message.sh

echo "send-message.sh has been created successfully!"
echo ""
echo "Service Bus Namespace: $ServiceBusNamespace"
echo "Service Bus Queue: $ServiceBusQueueName"
echo ""
echo "You can now run the function locally with 'cd src && func start'"
echo "Send test messages with './send-message.sh'"