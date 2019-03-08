#!/bin/bash
codename=a018

resourceGroup=$codename-rg
location=southeastasia
vnet=$codename-vnet
nsg=$codename-nsg

internalLb=$codename-lb-internal
publicLb=$codename-lb
publicLbIp=$codename-lb-ip
sku=Basic
backendPool=$codename-pool
backendAsPool=$codename-as-pool

vmAvailSet=$codename-as
vmCount=2
vmImage=CentOS

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

echo "Creating Internal Load Balancer and NAT rule ..."

az network lb create \
    --resource-group $resourceGroup \
    --vnet-name $vnet --subnet default \
    --name $internalLb \
    --sku $sku \
    --private-ip-address 10.0.0.4 \
    --backend-pool-name $backendPool \
    --output table

az network lb inbound-nat-rule create \
    --resource-group $resourceGroup \
    --lb-name $internalLb \
    --name HTTP --protocol TCP --frontend-port 80 --backend-port 80 \
    --output table

echo "Creating Network Security Group ..."

az network nsg create \
    --resource-group $resourceGroup \
    --name $nsg \
    --output table

echo "Creating Availability Set ..."

az vm availability-set create \
    --resource-group $resourceGroup \
    --name $vmAvailSet \
    --output table


echo "Creating Public Load Balancer Backend Pool ($backendAsPool) ..."

az network lb address-pool create \
    --resource-group $resourceGroup \
    --lb-name $publicLb \
    --name $backendAsPool

echo "Creating Internal Load Balancer Backend Pool ($backendAsPool) ..."

az network lb address-pool create \
    --resource-group $resourceGroup \
    --lb-name $internalLb \
    --name $backendAsPool


# 準備參數值用來讓 NIC 可加入到多個 load balancer 的 backend pool
publicId="$(az network lb address-pool show --resource-group $resourceGroup --lb-name $publicLb --name $backendPool --query id | sed -e 's/^"//' -e 's/"$//')"
internalId="$(az network lb address-pool show --resource-group $resourceGroup --lb-name $internalLb --name $backendPool --query id | sed -e 's/^"//' -e 's/"$//')"
publicId2="$(az network lb address-pool show --resource-group $resourceGroup --lb-name $publicLb --name $backendAsPool --query id | sed -e 's/^"//' -e 's/"$//')"
internalId2="$(az network lb address-pool show --resource-group $resourceGroup --lb-name $internalLb --name $backendAsPool --query id | sed -e 's/^"//' -e 's/"$//')"
nicBackendPools="$publicId $internalId $publicId2 $internalId2"

for i in $(seq 1 $vmCount);
do
    
    vmName=$codename-vm$i
    publicNic=$vmName-nic
    internalNic=$vmName-nic-internal

    echo "Creating NIC for Virtual Machine $i in Availability Set ..."

    az network nic create \
        --resource-group $resourceGroup \
        --vnet-name $vnet --subnet default \
        --lb-address-pools $nicBackendPools \
        --name $publicNic \
        --network-security-group $nsg \
        --output table

    echo "Creating Virtual Machine $i in Availability Set ..."

    az vm create \
        --resource-group $resourceGroup \
        --name $vmName \
        --image $vmImage \
        --size Standard_B2s \
        --generate-ssh-keys \
        --availability-set $vmAvailSet \
        --nics $publicNic \
        --no-wait \
        --output table

done


echo "Creating Virtual Machine Scale Set ..."

az vmss create \
    --resource-group $resourceGroup \
    --name $vmss \
    --image $vmImage \
    --vm-sku Standard_B2s \
    --instance-count 0 \
    --vnet-name $vnet --subnet default \
    --load-balancer $publicLb \
    --backend-pool-name $backendPool \
    --output table

echo "Hacking VMSS NIC configuration ..."
# 更新 VMSS 的 NIC 設定，支援多個 Load Balancer 的 Backend Pool

backendPoolId="$(az network lb address-pool show --resource-group $resourceGroup --lb-name $internalLb --name $backendPool --query id | sed -e 's/^"//' -e 's/"$//')"
json=$(printf '{"resourceGroup":"%s","id":"%s"}' "$resourceGroup" "$backendPoolId")

az vmss update \
    --resource-group $resourceGroup \
    --name $vmss \
    --add virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].ipConfigurations[0].loadBalancerBackendAddressPools $json 

echo "Upgrading VMSS ..."

az vmss update-instances \
    --resource-group $resourceGroup \
    --name $vmss \
    --instance-ids "*"

echo "Scaling VMSS ..."

az vmss scale \
    --resource-group $resourceGroup \
    --name $vmss \
    --new-capacity 2 \
    --no-wait \
    --output table


