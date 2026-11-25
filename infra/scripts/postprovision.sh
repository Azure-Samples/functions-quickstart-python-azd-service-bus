#!/bin/bash
set -euo pipefail

echo "Running post-provision script..."

output=$(azd env get-values)

ServiceBusNamespace=""
ServiceBusQueueName=""
while IFS= read -r line; do
    if [[ $line == SERVICE_BUS_CONNECTION__fullyQualifiedNamespace=* ]]; then
        ServiceBusNamespace=$(echo "${line#*=}" | tr -d '"')
    elif [[ $line == SERVICE_BUS_QUEUE_NAME=* ]]; then
        ServiceBusQueueName=$(echo "${line#*=}" | tr -d '"')
    fi
done <<< "$output"

if [ -z "$ServiceBusNamespace" ] || [ -z "$ServiceBusQueueName" ]; then
    echo "SERVICE_BUS_CONNECTION__fullyQualifiedNamespace or SERVICE_BUS_QUEUE_NAME is missing from the azd environment." >&2
    exit 1
fi

settingsPath=./src/local.settings.json

print_settings_values() {
    echo "  ServiceBusConnection__fullyQualifiedNamespace = $ServiceBusNamespace"
    echo "  ServiceBusQueueName = $ServiceBusQueueName"
}

find_python() {
    local candidate
    for candidate in python3 python; do
        if command -v "$candidate" > /dev/null 2>&1 && "$candidate" -c "import json" > /dev/null 2>&1; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

if [ -f "$settingsPath" ]; then
    # Never overwrite an existing local.settings.json; it may contain your own values.
    # Reserve 10 and 11 so unexpected Python failures cannot look like a mismatch.
    if pythonCmd=$(find_python); then
        compareStatus=0
        "$pythonCmd" - "$settingsPath" "$ServiceBusNamespace" "$ServiceBusQueueName" << 'PYEOF' || compareStatus=$?
import json
import sys

path, namespace, queue = sys.argv[1:4]
try:
    with open(path, encoding="utf-8-sig") as settings_file:
        settings = json.load(settings_file)
except (json.JSONDecodeError, UnicodeError):
    sys.exit(11)
except OSError as error:
    print(f"Failed to read {path}: {error}", file=sys.stderr)
    sys.exit(1)
if not isinstance(settings, dict):
    sys.exit(11)

values = settings.get("Values")
if (
    isinstance(values, dict)
    and values.get("ServiceBusConnection__fullyQualifiedNamespace") == namespace
    and values.get("ServiceBusQueueName") == queue
):
    sys.exit(0)
sys.exit(10)
PYEOF

        case $compareStatus in
            0)
                echo "src/local.settings.json already exists and references the provisioned resources."
                ;;
            10)
                echo "src/local.settings.json already exists and was not changed. Update these values in it to use the provisioned resources:"
                print_settings_values
                ;;
            11)
                echo "src/local.settings.json isn't valid JSON and was not changed. Fix the file, or delete it and run 'azd provision' again to recreate it. The provisioned values are:" >&2
                print_settings_values >&2
                exit 1
                ;;
            *)
                echo "Failed to verify src/local.settings.json (Python exit code $compareStatus). The file was not changed." >&2
                exit 1
                ;;
        esac
    else
        echo "src/local.settings.json already exists and was not changed. Python wasn't found, so its values couldn't be verified. Make sure it contains these values:"
        print_settings_values
    fi
else
    echo "Creating src/local.settings.json..."
    cat > "$settingsPath" << EOF
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
    echo "src/local.settings.json has been created successfully!"
fi

echo "Creating/updating send-message.sh..."
echo "az rest --method POST --uri \"https://$ServiceBusNamespace/$ServiceBusQueueName/messages\" --headers \"Content-Type=application/atom+xml;type=entry;charset=utf-8\" --body \"Hello from the CLI\" --resource \"https://servicebus.azure.net\"" > ./send-message.sh
chmod +x ./send-message.sh

echo "send-message.sh has been created successfully!"
echo ""
echo "Service Bus Namespace: $ServiceBusNamespace"
echo "Service Bus Queue: $ServiceBusQueueName"
echo ""
echo "Running locally and sending test messages from your machine require VNET_ENABLED=false."
echo "You can now run the function locally with 'cd src && func start'"
echo "Send test messages with './send-message.sh'"
