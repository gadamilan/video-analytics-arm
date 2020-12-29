#!/bin/bash

######################################################################################################################
echo "Logging in with Managed Identity...."
az login --identity --output "none"

echo "Installing Azure Iot extension..."
az extension add --name azure-iot

######################################################################################################################
# Configure IoT Hub for an edge device
echo "Registering edge device with IoT Hub..."
if test -z "$(az iot hub device-identity list -n $IOTHUB_NAME | grep "deviceId" | grep $DEVICE_NAME)"; then
    echo "Creating device identity..."
    az iot hub device-identity create --hub-name $IOTHUB_NAME --device-id $DEVICE_NAME --edge-enabled -o none    
else
    echo "Device identity already exists..."
fi

# Get the connection string for the edge device
DEVICE_CONNECTION_STRING=$(az iot hub device-identity connection-string show --device-id $DEVICE_NAME --hub-name $IOTHUB_NAME --query='connectionString')

######################################################################################################################
# Check if there is a need to deploy a virtual edge device

if [ "$USE_EXISTING_DEVICE" = "No" ]; then

    # Deploy the IoT Edge runtime on the VM
    az vm show -n $DEVICE_NAME -g $DEVICE_RESOURCE_GROUP &> /dev/null
    if [ $? -ne 0 ]; then
        echo -e "Deploying a VM that will act as the IoT Edge device the samples..."
        CLOUD_INIT_FILE='./cloud-init.yml'
        curl -s $CLOUD_INIT_URL > $CLOUD_INIT_FILE

        # here be dragons
        # sometimes a / is present in the connection string and it breaks sed
        # this escapes the /
        DEVICE_CONNECTION_STRING=${DEVICE_CONNECTION_STRING//\//\\/} 
        sed -i "s/xDEVICE_CONNECTION_STRINGx/${DEVICE_CONNECTION_STRING//\"/}/g" $CLOUD_INIT_FILE   

        sed -i "s/\$DEVICE_USER/$DEVICE_USERNAME/g" $CLOUD_INIT_FILE        

        az vm create \
        --resource-group $DEVICE_RESOURCE_GROUP \
        --name $DEVICE_NAME \
        --image Canonical:UbuntuServer:18.04-LTS:latest \
        --admin-username $DEVICE_USERNAME \
        --admin-password $DEVICE_PASSWORD \
        --custom-data $CLOUD_INIT_FILE \
        --size $DEVICE_SIZE \
        --output none

        echo "VM deployment complete..."
    else
        echo -e "A VM named $DEVICE_NAME was found in ${DEVICE_RESOURCE_GROUP}"
    fi
fi

######################################################################################################################
# Get AMS account information to use in deployment manifest

# echo "Setting up AMS service principal..."
# SPN="$AMS_ACCOUNT_NAME-access-sp" # this is the default naming convention used by `az ams account sp`

# if test -z "$(az ad sp list --display-name $SPN --query="[].displayName" -o tsv)"; then
#     AMS_CONNECTION=$(az ams account sp create -o yaml --resource-group $DEVICE_RESOURCE_GROUP --account-name $AMS_ACCOUNT_NAME)
# else
#     AMS_CONNECTION=$(az ams account sp reset-credentials -o yaml --resource-group $DEVICE_RESOURCE_GROUP --account-name $AMS_ACCOUNT_NAME)
# fi

# echo $AMS_CONNECTION

AAD_TENANT_ID="aad_tenant_id"
AAD_SERVICE_PRINCIPAL_ID="aad_service_principal_id"
AAD_SERVICE_PRINCIPAL_SECRET="aad_service_principal_secret"
SUBSCRIPTION_ID="subscription_id"

# Capture config information
# re="AadTenantId:\s([0-9a-z\-]*)"
# AAD_TENANT_ID=$([[ "$AMS_CONNECTION" =~ $re ]] && echo ${BASH_REMATCH[1]})

# re="AadClientId:\s([0-9a-z\-]*)"
# AAD_SERVICE_PRINCIPAL_ID=$([[ "$AMS_CONNECTION" =~ $re ]] && echo ${BASH_REMATCH[1]})

# re="AadSecret:\s([0-9a-z\-]*)"
# AAD_SERVICE_PRINCIPAL_SECRET=$([[ "$AMS_CONNECTION" =~ $re ]] && echo ${BASH_REMATCH[1]})

# re="SubscriptionId:\s([0-9a-z\-]*)"
# SUBSCRIPTION_ID=$([[ "$AMS_CONNECTION" =~ $re ]] && echo ${BASH_REMATCH[1]})

# AMS account may have a standard streaming endpoint in stopped state. 
# A Premium streaming endpoint is recommended when recording multiple days worth of video

echo -e "Updating the Media Services account to use one Premium streaming endpoint..."
az ams streaming-endpoint scale --resource-group $DEVICE_RESOURCE_GROUP --account-name $AMS_ACCOUNT_NAME -n default --scale-units 1

echo "Kicking off the async start of the Premium streaming endpoint..."
az ams streaming-endpoint start --resource-group $DEVICE_RESOURCE_GROUP --account-name $AMS_ACCOUNT_NAME -n default --no-wait

######################################################################################################################
# Set up deployment manifest

echo "Setting up deployment manfiest file..."

DEPLOYMENT_MANIFEST_FILE='./va-deployment-manifest.json'
APPDATA_FOLDER_ON_DEVICE="/var/lib/azuremediaservices"

curl -s $DEPLOYMENT_MANIFEST_URL > $DEPLOYMENT_MANIFEST_FILE

sed -i "s/\$INPUT_VIDEO_FOLDER_ON_DEVICE/\/home\/$DEVICE_USERNAME\/samples\/input/" $DEPLOYMENT_MANIFEST_FILE
sed -i "s/\$SUBSCRIPTION_ID/$SUBSCRIPTION_ID/" $DEPLOYMENT_MANIFEST_FILE
sed -i "s/\$RESOURCE_GROUP/$DEVICE_RESOURCE_GROUP/" $DEPLOYMENT_MANIFEST_FILE
sed -i "s/\$AMS_ACCOUNT/$AMS_ACCOUNT_NAME/" $DEPLOYMENT_MANIFEST_FILE
sed -i "s/\$AAD_TENANT_ID/$AAD_TENANT_ID/" $DEPLOYMENT_MANIFEST_FILE
sed -i "s/\$AAD_SERVICE_PRINCIPAL_ID/$AAD_SERVICE_PRINCIPAL_ID/" $DEPLOYMENT_MANIFEST_FILE
sed -i "s/\$AAD_SERVICE_PRINCIPAL_SECRET/$AAD_SERVICE_PRINCIPAL_SECRET/" $DEPLOYMENT_MANIFEST_FILE
sed -i "s/\$OUTPUT_VIDEO_FOLDER_ON_DEVICE/\/var\/media/" $DEPLOYMENT_MANIFEST_FILE
sed -i "s/\$APPDATA_FOLDER_ON_DEVICE/${APPDATA_FOLDER_ON_DEVICE//\//\\/}/" $DEPLOYMENT_MANIFEST_FILE

######################################################################################################################
# Deploy the modules on the edge device

echo "Deploying modules on edge device..."
az iot edge set-modules --hub-name $IOTHUB_NAME --device-id $DEVICE_NAME --content $DEPLOYMENT_MANIFEST_FILE

######################################################################################################################