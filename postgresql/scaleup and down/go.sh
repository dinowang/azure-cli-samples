#!/bin/bash
codename=a20190312

resourceGroup=${codename}-rg
dbName=${codename}-pgsql
location=southeastasia


az group create \
    --name ${resourceGroup} \
    --location ${location} 

az postgres server create \
    --resource-group ${resourceGroup} \
    --name ${dbName} \
    --sku-name GP_Gen5_2 \
    --location ${location} \
    --admin-user dino \
    --admin-password 1qaz@WSX3edc 


