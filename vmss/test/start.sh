#!/bin/bash

account="$(az account show --query '{subscriptionId:id, tenantId:tenantId}')"

echo $account

subscriptionId="$(echo $account | jq -r '.subscriptionId')"

echo $subscriptionId

role="$(az ad sp create-for-rbac --name terraform --role='Contributor' --scopes='/subscriptions/$subscriptionId')"

echo $role


