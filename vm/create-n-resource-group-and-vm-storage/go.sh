#!/bin/bash

start=$1
count=$2
prefix=
location=southeastasia

function create {
    group=group$seq
    groupRg=${group}-rg

    groupStor=post201906${group}stor

    groupVm=${group}
    groupIp=${group}-publicip
    groupVnet=${group}-vnet
    groupNsg=${group}-nsg
    groupNic=${group}-nic
    dataDiskSizeGB=10
    userName=${group}admin

    # 隨機 12 位密碼
    # password=$(pwgen -cnys1 12 1)
    password=$(curl -s "https://www.passwordrandom.com/query?command=password&scheme=CvvCVCvV%23-NNN")

    # 建立資源群組
    json=$(az group create --name ${groupRg} --tags "phase=201906" --location ${location})
    # echo $json | jq

    # 建立儲存體 比賽結果上傳用
    json=$(az storage account create --resource-group ${groupRg} --name ${groupStor} --sku Standard_LRS --kind BlobStorage --access-tier Hot --tags "phase=201906" --location ${location})
    json=$(az storage account show --resource-group ${groupRg} --name ${groupStor})
    # echo $json | jq
    blobEndPoint=$(echo $json | jq -r .primaryEndpoints.blob)
    storageKey2=$(az storage account keys list --resource-group ${groupRg} --account-name ${groupStor} | jq -r .[1].value)

    # 產生 storage container "upload"
    json=$(az storage container create \
        --account-name ${groupStor} \
        --account-key "${storageKey2}" \
        --name upload \
        --public-access off)

    # 建立稍後給虛擬網卡使用的 public ip
    json=$(az network public-ip create --resource-group ${groupRg} --name ${groupIp} --allocation-method Static --sku Basic --location ${location})
    # echo $json | jq
    ip=$(echo $json | jq -r .publicIp.ipAddress)
    ipId=$(echo $json | jq -r .publicIp.id)

    # 建立虛擬網路
    json=$(az network vnet create --resource-group ${groupRg} --name ${groupVnet} --subnet-name default --location ${location})
    
    # 建立 NSG 與規則
    json=$(az network nsg create --resource-group ${groupRg} --name ${groupNsg} --location ${location})
    json=$(az network nsg rule create --resource-group ${groupRg} --nsg-name ${groupNsg} --name AllowRDP --priority 100 --protocol TCP --access Allow --direction Inbound --source-port-ranges 3389 --destination-port-ranges 3389)
    
    # 建立虛擬網卡
    json=$(az network nic create --resource-group ${groupRg} --name ${groupNic} --vnet-name ${groupVnet} --subnet default --public-ip-address ${ipId} --network-security-group ${groupNsg} --location ${location})
    # nicId=$(echo $json | jq -r .id)

    # 建立虛擬機器
    json=$(az vm create \
        --resource-group "${groupRg}" \
        --size Standard_DS11 \
        --image "microsoft-ads:windows-data-science-vm:windows2016:19.02.02" \
        --name "${groupVm}" \
        --nics "${groupNic}" \
        --storage-sku StandardSSD_LRS \
        --data-disk-sizes-gb ${dataDiskSizeGB} \
        --os-disk-name "${groupVm}-osdisk" \
        --authentication-type password \
        --admin-username "${userName}" \
        --admin-password "${password}" \
        --nsg-rule RDP \
        --location ${location})

    # 讓虛擬網路支援 storage 的 service endpoint (將 storage 整合至虛擬網路)
    json=$(az network vnet subnet update \
        --resource-group ${groupRg} \
        --vnet-name ${groupVnet} \
        --name default \
        --service-endpoints "Microsoft.Storage")

    # 將虛擬網路設定至 storage 的 service endpoint 定義中
    json=$(az storage account network-rule add \
        --resource-group ${groupRg} \
        --account-name ${groupStor} \
        --vnet-name ${groupVnet} \
        --subnet default)

    # 設定是否允許外網存取 storage (Selected network only)
    json=$(az storage account update \
        --name ${groupStor} \
        --default-action Deny)

    # 產生給比賽學員存取用的 SAS 簽章
    # sasToken=$(az storage account generate-sas \
    #     --account-name "${groupStor}" \
    #     --account-key "${storageKey2}" \
    #     --services b \
    #     --resource-types co \
    #     --permissions acdlpruw \
    #     --expiry 2019-07-01T00:00Z | sed -e 's/^"//' -e 's/"$//')

    sasToken=$(az storage container generate-sas \
        --account-name "${groupStor}" \
        --account-key "${storageKey2}" \
        --name upload \
        --policy-name user-upload \
        --permissions rwdl \
        --expiry 2019-07-01T00:00Z \
        --output tsv)

    echo -e "${group}","${ip}","${userName}","${password}","${blobEndPoint}upload?${sasToken}" >> go.log
}

echo Group,IP,User,Password,Blob Storage SAS URI > go.log

for seq in $(seq -f "%02g" $start $((start + count - 1)))
do
    create &
done
