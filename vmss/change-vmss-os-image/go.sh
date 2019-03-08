#!/bin/bash
codename=a020

resourceGroup=$codename-rg
location=southeastasia
vnet=$codename-vnet
nsg=$codename-nsg

publicLb=$codename-lb
publicLbIp=$codename-lb-ip
sku=Basic
backendPool=$codename-pool

vmCount=2
vmImage=Win2012Datacenter
vmNewImage=2012-R2-Datacenter

vmss=$codename-vmss

echo "Creating Resource Group ..."

az group create \
    --name $resourceGroup \
    --location $location \
    --output table

echo "Creating Virtual Network ..."

az network vnet create \
    --resource-group $resourceGroup \
    --name $vnet \
    --subnet-name default \
    --subnet-prefixes 10.0.0.0/24 \
    --output table

echo "Creating Public IP ..."

az network public-ip create \
    --resource-group $resourceGroup \
    --name $publicLbIp \
    --sku $sku \
    --output table

echo "Creating Public Load Balancer and NAT rule ..."

az network lb create \
    --resource-group $resourceGroup \
    --vnet-name $vnet \
    --name $publicLb \
    --sku $sku \
    --public-ip-address $publicLbIp \
    --backend-pool-name $backendPool \
    --output table

az network lb inbound-nat-rule create \
    --resource-group $resourceGroup \
    --lb-name $publicLb \
    --name HTTP --protocol TCP --frontend-port 80 --backend-port 80 \
    --output table

echo "Creating Network Security Group ..."

az network nsg create \
    --resource-group $resourceGroup \
    --name $nsg \
    --output table

echo "Creating Virtual Machine Scale Set ..."

az vmss create \
    --resource-group $resourceGroup \
    --name $vmss \
    --image $vmImage \
    --vm-sku Standard_B2s \
    --instance-count $vmCount \
    --vnet-name $vnet --subnet default \
    --load-balancer $publicLb \
    --backend-pool-name $backendPool \
    --output table

echo "Changing VMSS image reference ..."

az vmss update \
    --resource-group $resourceGroup \
    --name $vmss \
    --set virtualMachineProfile.storageProfile.imageReference.sku=$vmNewImage

ids=$(az vmss list-instances \
      --resource-group $resourceGroup \
      --name $vmss \
      --query [].instanceId \
      --output tsv)

echo $ids | while read id;
do

    echo "Upgrading VMSS $id ..."

    az vmss update-instances \
        --resource-group $resourceGroup \
        --name $vmss \
        --instance-ids $id

done
