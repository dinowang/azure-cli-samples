#!/bin/bash
codename=a010

resourceGroup=$codename-rg
location=southeastasia
vnet=$codename-vnet
nsg=$codename-nsg

internalLb=$codename-lb-internal
publicLb=$codename-lb
publicLbIp=$codename-lb-ip
sku=Standard

vmAvailSet=$codename-as
vmss=$codename-vmss
vmCount=2
# vmImage=Win2019Datacenter
vmImage=CentOS


az group create \
    --name $resourceGroup \
    --location $location

az network vnet create \
    --resource-group $resourceGroup \
    --name $vnet \
    --subnet-name default \
    --subnet-prefixes 10.0.0.0/24

az network public-ip create \
    --resource-group $resourceGroup \
    --name $publicLbIp \
    --sku $sku

az network lb create \
    --resource-group $resourceGroup \
    --vnet-name $vnet \
    --name $publicLb \
    --sku $sku \
    --public-ip-address $publicLbIp \
    --backend-pool-name $vmss

az network lb inbound-nat-rule create \
    --resource-group $resourceGroup \
    --lb-name $publicLb \
    --name HTTP --protocol TCP --frontend-port 80 --backend-port 80

az network lb create \
    --resource-group $resourceGroup \
    --vnet-name $vnet --subnet default \
    --name $internalLb \
    --sku $sku \
    --private-ip-address 10.0.0.4 \
    --backend-pool-name $vmss 

az network lb inbound-nat-rule create \
    --resource-group $resourceGroup \
    --lb-name $internalLb \
    --name HTTP --protocol TCP --frontend-port 80 --backend-port 80

az network nsg create \
    --resource-group $resourceGroup \
    --name $nsg

az vm availability-set create \
    --resource-group $resourceGroup \
    --name $vmAvailSet 


az network lb address-pool create \
    --resource-group $resourceGroup \
    --lb-name $publicLb \
    --name $vmAvailSet

az network lb address-pool create \
    --resource-group $resourceGroup \
    --lb-name $internalLb \
    --name $vmAvailSet

publicId="$(az network lb address-pool show --resource-group $resourceGroup --lb-name $publicLb --name $vmAvailSet --query id | sed -e 's/^"//' -e 's/"$//')"
internalId="$(az network lb address-pool show --resource-group $resourceGroup --lb-name $internalLb --name $vmAvailSet --query id | sed -e 's/^"//' -e 's/"$//')"
nicBackendPools="$publicId $internalId"

for i in $(seq 1 $vmCount);
do
    vmName=$codename-vm$i
    publicNic=$vmName-nic
    internalNic=$vmName-nic-internal

    # az network nic create \
    #     --resource-group $resourceGroup \
    #     --vnet-name $vnet --subnet default \
    #     --lb-address-pools $codename-as \
    #     --lb-name $internalLb \
    #     --name $internalNic \
    #     --network-security-group $nsg

    # az network nic create \
    #     --resource-group $resourceGroup \
    #     --vnet-name $vnet --subnet default \
    #     --lb-address-pools $codename-as \
    #     --lb-name $publicLb \
    #     --name $publicNic \
    #     --network-security-group $nsg
            
    # az vm create \
    #     --resource-group $resourceGroup \
    #     --name $vmName \
    #     --image $vmImage \
    #     --size Standard_B2s \
    #     --generate-ssh-keys \
    #     --availability-set $vmAvailSet \
    #     --nics $internalNic $publicNic \
    #     --admin-username $adminName \
    #     --admin-password $adminPwd \
    #     --no-wait

    az network nic create \
        --resource-group $resourceGroup \
        --vnet-name $vnet --subnet default \
        --lb-address-pools $nicBackendPools \
        --name $publicNic \
        --network-security-group $nsg
            
    az vm create \
        --resource-group $resourceGroup \
        --name $vmName \
        --image $vmImage \
        --size Standard_B2s \
        --generate-ssh-keys \
        --availability-set $vmAvailSet \
        --nics $publicNic \
        --admin-username $adminName \
        --admin-password $adminPwd \
        --no-wait

done


# az network lb address-pool create \
#     --resource-group $resourceGroup \
#     --lb-name $publicLb \
#     --name $vmss

# az network lb address-pool create \
#     --resource-group $resourceGroup \
#     --lb-name $internalLb \
#     --name $vmss

az vmss create \
    --resource-group $resourceGroup \
    --name $vmss \
    --image $vmImage \
    --vm-sku Standard_B2s \
    --instance-count 0 \
    --vnet-name $vnet --subnet default \
    --load-balancer $publicLb \
    --backend-pool-name $vmAvailSet \
    --admin-username $adminName \
    --admin-password $adminPwd \
    --no-wait

backendPoolId="$(az network lb address-pool show --resource-group $resourceGroup --lb-name $internalLb --name $vmss --query id | sed -e 's/^"//' -e 's/"$//')"
json=$(printf '{"resourceGroup":"%s","id":"%s"}' "$resourceGroup" "$backendPoolId")

az vmss update \
    --resource-group $resourceGroup \
    --name $vmss \
    --add virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].ipConfigurations[0].loadBalancerBackendAddressPools $json

az vmss scale \
    --resource-group $resourceGroup \
    --name $vmss \
    --new-capacity 2 \
    --no-wait


