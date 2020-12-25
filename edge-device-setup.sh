#!/bin/bash

# This script creates a new Edge Device in given IoT Hub and connects it to a Existing VM with IoT Edge runtime installed on it.

# If an Edge Device with given name already exists, use it else create a new one.
EXISTING_IOTHUB_DEVICE = $(az iot hub device-identity list --hub-name "$IOTHUB_NAME" --query "[?deviceId=='$DEVICE_NAME'].deviceId" -o tsv)
if [ -z "$EXISTING_IOTHUB_DEVICE" ]; then
    echo "$(info) Creating \"$DEVICE_NAME\" device in IoT Hub \"$IOTHUB_NAME\""
    az iot hub device-identity create --hub-name "$IOTHUB_NAME" --device-id "$DEVICE_NAME" --edge-enabled --output "none"
    echo "$(info) Created \"$DEVICE_NAME\" device in IoT Hub \"$IOTHUB_NAME\""
else
    echo "$(info) Using existing IoT Hub Edge Device \"$DEVICE_NAME\""
fi