#!/bin/bash

# This script creates a new Edge Device in given IoT Hub and connects it to a Existing VM with IoT Edge runtime installed on it.

printenv

echo "Logging in with Managed Identity"
az login --identity --output "none"

echo "Installing azure iot extension"
az extension add --name azure-iot

# Configure IoT Hub for an edge device
echo "registering device..."
if test -z "$(az iot hub device-identity list -n $IOTHUB_NAME | grep "deviceId" | grep $DEVICE_NAME)"; then
    az iot hub device-identity create --hub-name $IOTHUB_NAME --device-id $DEVICE_NAME --edge-enabled -o none    
fi

DEVICE_CONNECTION_STRING=$(az iot hub device-identity connection-string show --device-id $DEVICE_NAME --hub-name $IOTHUB_NAME --query='connectionString')

# Deploy the IoT Edge runtime on the VM
az vm show -n $DEVICE_NAME -g $DEVICE_RESOURCE_GROUP &> /dev/null
if [ $? -ne 0 ]; then
    echo -e "Deploying a VM that will act as your IoT Edge device for using the samples."
    CLOUD_INIT_FILE='./cloud-init.yml'
    curl -s $CLOUD_INIT_URL > $CLOUD_INIT_FILE

    # here be dragons
    # sometimes a / is present in the connection string and it breaks sed
    # this escapes the /
    DEVICE_CONNECTION_STRING=${DEVICE_CONNECTION_STRING//\//\\/} 
    sed -i "s/xDEVICE_CONNECTION_STRINGx/${DEVICE_CONNECTION_STRING//\"/}/g" $CLOUD_INIT_FILE   

    az vm create \
    --resource-group $DEVICE_RESOURCE_GROUP \
    --name $DEVICE_NAME \
    --image Canonical:UbuntuServer:18.04-LTS:latest \
    --admin-username $DEVICE_USERNAME \
    --admin-password $DEVICE_PASSWORD \
    --custom-data $CLOUD_INIT_FILE \
    --size $DEVICE_SIZE \
    --output none

else
    echo -e "A VM named $DEVICE_NAME was found in ${DEVICE_RESOURCE_GROUP}"
fi
