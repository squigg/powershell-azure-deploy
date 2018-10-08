Azure Deployment
=============

Automated Azure deployment of DotNet Core app with PowerShell

## Prerequisites

- PowerShell 5.x on Windows with `AzureRm` module available
- Microsoft Azure account with valid subscription

## Usage

- Clone repository to a local folder
- Edit global configuration file in `Config\Global.json` with Azure subscription name and default region
- Edit app specific configurations in `Config` folder if desired
- Run `Deploy.ps1` to build the Azure environment, test, package and deploy the app:
```
    .\Deploy.ps1 DotNetCoreHelloWorld
``` 
- Run `Monitor.ps1` to monitor the production environment:
```
    .\Monitor.ps1 DotNetCoreHelloWorld
``` 

#### Deploy Script Options

- `-SkipAzureBuild` skips the Azure environment build stage
- `-File` accepts a file path to a ZIP file to deploy instead of building from source 

#### Monitor Script Options

- `-Period` number of seconds history to gather for metrics
- `-Metrics` a list of [valid metrics](https://docs.microsoft.com/en-us/azure/monitoring-and-diagnostics/monitoring-supported-metrics#microsoftwebsites-excluding-functions)
to be gathered for the app (note that additional metrics may need to be added to `Get-MetricAggregateType` to be properly supported) 

## Overview

- Application specific settings stored in JSON files for easy script re-use 
- Builds environment from Azure Resource Manager templates for flexibility and idempotent execution
- DotNet package tested and built from source GitHub repository or folder
- Uses Azure Web Services slots for blue/green deployment from staging -> production
- Tests API endpoints at every stage of deployment with auto-rollback on failure

### Future Work

- Azure Web Services are already load-balanced within a region, however a Traffic Manager in
front of the Azure Web Services in multiple regions would be required for global load-balancing and auto-failover 
- Use of Azure DevOps Pipelines to orchestrate cloud-based build, test and release steps upon Git commits
- Lots of production-ready configuration changes to Azure Web Apps including storage of logs, auto-scaling 

## Tests
Tests are run using [Pester](https://github.com/Pester/Pester/wiki) (v4.4+)
```powershell
Install-Module -Name Pester -Force -SkipPublisherCheck
Invoke-Pester
```
