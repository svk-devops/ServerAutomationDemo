#region Var setup
$resourceGroupName = 'ServerAutomationDemo'
$region = 'West Europe'
$localVMAdminPw = '!user-2010' ## a single password for demo purposes
$projectName = 'ServerAutomationDemo' ## common term used through set up
$subscriptionName = 'SVK Dev/Test'
$subscriptionId = 'c80eb516-ac45-4df1-ae1f-c8c17bf10a72'
$tenantId = '6726ea9f-344c-4609-9af9-35e8d9d1663f'
$orgName = 'SVK-Azure-DevOps'
$gitHubRepoUrl = "https://github.com/svk-devops/ServerAutomationDemo"

#endregion

#region Login
az login
az account set --subscription $subscriptionName
#endregion

#region Install the Azure CLI DevOps extension
az devops configure --defaults organization=https://dev.azure.com/$orgName
#endregion

#region Create the resource group to put everything in
az group create --location $region --name $resourceGroupName
#endregion

#region Create the service principal
$projectName = 'ServerAutomationDemo'
$spIdUri = "https://$projectName"
$sp = az ad sp create-for-rbac --name $spIdUri | ConvertFrom-Json
$sp
appId       : 0d5cc907-cea4-4f40-826b-12d93d55d572
displayName : ServerAutomationDemo
name        : https://ServerAutomationDemo
password    : 210fc320-ddb1-4276-b24e-019906bdc88d
tenant      : 6726ea9f-344c-4609-9af9-35e8d9d1663f
#endregion

#region Key vault

## Create the key vault. Enabling for template deployment because we'll be using it during an ARM deployment
## via an Azure DevOps pipeline later
$kvName = "$projectNameSKV"
$keyVault = az keyvault create --location $region --name $kvName --resource-group $resourceGroupName --enabled-for-template-deployment true | ConvertFrom-Json

# ## Create the key vault secrets
az keyvault secret set --name "$projectName-AppPw" --value $sp.password --vault-name $kvName
az keyvault secret set --name StandardVmAdminPassword --value $localVMAdminPw --vault-name $kvName

## Give service principal created earlier access to secrets. This allows the steps in the pipeline to read the AD application's pw and the default VM password
$null = az keyvault set-policy --name $kvName --spn $spIdUri --secret-permissions get list
#endregion

#region Instal the Pester test runner extension in the org
az devops extension install --extension-id PesterRunner --publisher-id Pester
#endregion

#region Create the Azure DevOps project
az devops project create --name $projectName
az devops configure --defaults project=$projectName
#endregion

#region Create the service connections
## Run $sp.password and copy it to the clipboard
$sp.Password
az devops service-endpoint azurerm create --azure-rm-service-principal-id $sp.appId --azure-rm-subscription-id $subscriptionId --azure-rm-subscription-name $subscriptionName --azure-rm-tenant-id $tenantId --name 'ARM'

## Create service connection for GitHub for CI process in pipeline
$gitHubServiceEndpoint = az devops service-endpoint github create --github-url $gitHubRepoUrl --name 'GitHub' | ConvertFrom-Json
## paste in the GitHub token when prompted 
## when prompted, use the value of $sp.password for the Azure RM service principal key
#endregion

#region Create the variable group
$varGroup = az pipelines variable-group create --name $projectName --authorize true --variables foo=bar | ConvertFrom-Json ## dummy variable because it won't allow creation without it

Read-Host "Now link the key vault $kvName to the variable group $projectName in the DevOps web portal and create a '$projectName-AppPw' and StandardVmAdminPassword variables with a password of your choosing."
#endregion

## Create the pipeline

## set the PAT to avoid getting prompted --doesn't work...
# export AZURE_DEVOPS_EXT_GITHUB_PAT=$gitHubAccessToken ## in CMD??
### [System.Environment]::SetEnvironmentVariable("AZURE_DEVOPS_EXT_GITHUB_PAT", $gitHubAccessToken ,"Machine") ???
az pipelines create --name $projectName --repository $gitHubRepoUrl --branch master --service-connection $gitHubServiceEndpoint.id --skip-run

## Add the GitHub PAT here interactively

## Replace the application ID generated in YAML
$sp.appId
##   - name: application_id
##    value: "REMEMBERTOFILLTHISIN"

#region Cleanup

## Remove the SP
$spId = ((az ad sp list --all | ConvertFrom-Json) | ? { $spIdUri -in $_.serviceprincipalnames }).objectId
az ad sp delete --id $spId

## Remove the resource group
az group delete --name $resourceGroupName --yes --no-wait

## remove project
$projectId = ((az devops project list | convertfrom-json).value | where { $_.name -eq $projectName }).id
az devops project delete --id $projectId --yes 

#endregion