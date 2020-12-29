# Video Analytics ARM Template

ARM template to get started with Video Analytics in Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fgadamilan%2Fvideo-analytics-arm%2Fmain%2Fdeploy.json)

## Using command line

az deployment group create --resource-group va-sample --template-file deploy-rg.json

az deployment sub create --location southcentralus --template-file deploy-sub.json --parameters resourceGroupName=va-sample
