#Requires -Modules AppAzure
#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="4.0.0" }

InModuleScope AppAzure {

    Mock Write-Host

    Describe "Set-AppAzureSetup" {

        Mock Set-AzureRmContext

        It "Should error if no context" {
            Mock Get-AzureRmContext { Write-Error "Error" }
            {Set-AppAzureSetup -SubscriptionName "Sub" -ErrorAction Stop} | Should -Throw
            Assert-MockCalled Get-AzureRmContext -Times 1
            Assert-MockCalled Set-AzureRmContext -Times 0
        }

        It "Should run Set-AzureRmContext with correct parameter" {
            Mock Get-AzureRmContext { @{Account = "Account"} }
            Set-AppAzureSetup -SubscriptionName "Sub"
            Assert-MockCalled Set-AzureRmContext -Times 1 -ParameterFilter {$Subscription -eq "Sub"}
        }

    }

    Describe "Get-AppAzureConfig" {

        Context "Without files" {

            Mock Get-ChildItem

            It "Should get files with correct filter based on type" {
                Get-AppAzureConfig C:\ -Type App -Name Name -ErrorAction SilentlyContinue
                Assert-MockCalled Get-ChildItem -Times 1 -ParameterFilter {$Filter -eq "Name.App.json" -and $Path -eq "C:\"}
            }

            It "Should error if no file found" {
                {Get-AppAzureConfig C:\ -Type App -Name Name -ErrorAction Stop} | Should -Throw
                Assert-MockCalled Get-ChildItem -Times 1
            }

        }

        Context "With TestDrive" {

            It "Should return JSON from input file" {
                $TestJson = "$($TestDrive)\Name.App.json"
                Set-Content $TestJson -Value "{ `"key`": `"value`" }"
                $Expected = [pscustomobject]@{ key = "value" }
                $Result = Get-AppAzureConfig $($TestDrive) -Type App -Name Name
                $Result | Should -Not -Be $Null
                Compare-Object $Result $Expected | Should -Be $Null
            }
        }

    }

    Describe "Get-AppAzureTemplate" {

        $TestFiles = "$($TestDrive)\Templates\MyTemplate.json","$($TestDrive)\Templates\Another.json"
        $TestFiles | % {New-Item $_ -Force}
        $DirInfo = "$($TestDrive)\Templates" | Get-Item

        It "Should return FileInfo for discovered template" {
            $Params = @{
                Name = "MyTemplate"
                TemplateDir = "$($TestDrive)\Templates"
            }
            $Result = Get-AppAzureTemplate @Params
            $Result | Should -Not -Be $Null
            $Result | Should -BeOfType [System.IO.FileInfo]
        }

        It "Should return FileInfo for discovered template with DirInfo" {
            $Params = @{
                Name = "MyTemplate"
                TemplateDir = $DirInfo
            }
            $Result = Get-AppAzureTemplate @Params
            $Result | Should -Not -Be $Null
            $Result | Should -BeOfType [System.IO.FileInfo]
        }

        It "Should error for missing template" {
            $Params = @{
                Name = "MyMissingTemplate"
                TemplateDir = "$($TestDrive)\Templates"
            }
            { Get-AppAzureTemplate @Params -ErrorAction Stop} | Should -Throw
        }

    }

    Describe "Get-AppAzureTemplateParams" {

        $TestFile = "$($TestDrive)\Template.json"
        $TestJson = @'
            {
                "key": "value",
                "parameters": {
                    "Param1": { "Name": "Name1" },
                    "Param2": { "Name": "Name2" },
                    "Param3": { "Name": "Name3" }
                },
                "anotherkey": "value"
            }
'@
        Set-Content $TestFile -Value $TestJson

        It "Should return params for template with FileInfo" {
            $Result = Get-AppAzureTemplateParams (Get-Item $TestFile)
            $Result | Should -Be Param1,Param2,Param3
        }

        It "Should error for missing template file" {
            { Get-AppAzureTemplateParams "$($TestDrive)\Missing.File" -ErrorAction Stop } | Should -Throw
        }

    }

    Describe "Get-SourceCode" {

        $TestDir = "$($TestDrive)\Source\"
        $TestFiles = "$TestDir\File1.txt", "$TestDir\File2.txt"
        $TestFiles | % {New-Item $_ -Force}

        It "Should copy source to deployment dir for directory" {
            $Result = Get-SourceCode -Source $TestDir
            $Files = Get-ChildItem $Result
            $Files | Should -HaveCount 2
            $Files[0].Name | Should -Be File1.txt
            $Files[1].Name | Should -Be File2.txt
        }

        It "Should clone source to deployment dir for git" {
            Mock New-GitClone {
                Param (
                    [string]$Repository,
                    [string]$Destination
                )
                New-Item $Destination -Force -ItemType "Container"
            }
            $Result = Get-SourceCode -Repository 'RepoUrl'
            $Result | Should -BeOfType [System.IO.DirectoryInfo]
            Assert-MockCalled New-GitClone -Times 1 -ParameterFilter {$Repository -eq 'RepoUrl'}
        }
    }

    Describe "New-AppAzureResourceGroupDeployment" {

        BeforeEach {
            $Config = @{
                AppName = "AppName"
                AppResourceGroup = "AppResourceGroup"
                Key1 = "Value1"
                Key2 = "Value2"
            }
            $TemplateParams = @{
                Key3 = "Value3"
                Key4 = "Value4"
            }
            $CallParams = @{
                Config = $Config
                Template = (New-TemporaryFile).FullName
                TemplateParams = $TemplateParams
            }
        }

        Mock Get-AppAzureTemplateParams { "Key1", "Key2", "Key3" }

        It "Should fail with invalid template" {
            $CallParams.Template = 'Template'
            {New-AppAzureResourceGroupDeployment @CallParams} | Should -Throw
        }

        It "Should fail when test has result" {
            Mock Test-AzureRmResourceGroupDeployment { "Result" }
            {New-AppAzureResourceGroupDeployment @CallParams} | Should -Throw
        }

        It "Should request resource group deployment with correct params" {
            Mock Test-AzureRmResourceGroupDeployment
            Mock New-AzureRmResourceGroupDeployment

            New-AppAzureResourceGroupDeployment @CallParams

            # Correct template params is combination of Config and TemplateParams
            # but limited to keys that exist in the Azure template
            $ExpectedTemplateParams = @{
                Key1 = "Value1"
                Key2 = "Value2"
                Key3 = "Value3"
            }

            $MockParams = @{
                Times = 1
                ParameterFilter = {
                        $ResourceGroupName -eq 'AppResourceGroup' -and
                        $TemplateFile -eq $CallParams.Template -and
                        $Null -eq (Compare-Object $TemplateParameterObject.Keys $ExpectedTemplateParams.Keys)
                }
            }
            Assert-MockCalled Test-AzureRmResourceGroupDeployment @MockParams
            Assert-MockCalled New-AzureRmResourceGroupDeployment @MockParams

        }

    }

    Describe "Test-ApiEndPoint" {

        $TestUri = 'https://site/endpoint'
        Mock Write-Host -ParameterFilter { $ForeGroundColor -eq 'Green'}

        It "Should fail for failed REST method" {
            Mock Invoke-RestMethod { Write-Error "Deliberate failure of REST method" 2>&1 }
            { Test-ApiEndPoint -Uri $TestUri -Expects "Result" -ErrorAction Stop } | Should -Throw
            Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -eq $TestUri }
        }

        It "Should fail for mismatch result type" {
            Mock Invoke-RestMethod { "StringResponse" }
            $Expects = [pscustomobject]@{ Key = 'Value' }
            { Test-ApiEndPoint -Uri $TestUri -Expects $Expects -ErrorAction Stop } | Should -Throw
        }

        It "Should fail for different array result" {
            Mock Invoke-RestMethod { 1,2,3,4 }
            $Expects = 2,3,4,5
            { Test-ApiEndPoint -Uri $TestUri -Expects $Expects -ErrorAction Stop } | Should -Throw
        }

        It "Should succeed for same array result" {
            Mock Invoke-RestMethod { 1,2,3,4 }
            $Expects = 1,2,3,4
            Test-ApiEndPoint -Uri $TestUri -Expects $Expects -ErrorAction Stop
            Assert-MockCalled Write-Host -Times 1
        }

        It "Should fail for different object result" {
            Mock Invoke-RestMethod { [pscustomobject]@{ Key = 'Value2' } }
            $Expects = [pscustomobject]@{ Key = 'Value' }
            { Test-ApiEndPoint -Uri $TestUri -Expects $Expects -ErrorAction Stop } | Should -Throw
        }

        It "Should succeed for same object result" {
            Mock Invoke-RestMethod { [pscustomobject]@{ Key = 'Value' } }
            $Expects = [pscustomobject]@{ Key = 'Value' }
            Test-ApiEndPoint -Uri $TestUri -Expects $Expects -ErrorAction Stop
            Assert-MockCalled Write-Host -Times 1
        }

        It "Should fail for different nested object result" {
            Mock Invoke-RestMethod { [pscustomobject]@{ Key = [pscustomobject]@{ Name = 'Foo' } } }
            $Expects = [pscustomobject]@{ Key = [pscustomobject]@{ Name = 'Bar' } }
            { Test-ApiEndPoint -Uri $TestUri -Expects $Expects -ErrorAction Stop } | Should -Throw
        }

        It "Should succeed for same nested object result" {
            Mock Invoke-RestMethod { [pscustomobject]@{ Key = [pscustomobject]@{ Name = 'Foo' } } }
            $Expects = [pscustomobject]@{ Key = [pscustomobject]@{ Name = 'Foo' } }
            Test-ApiEndPoint -Uri $TestUri -Expects $Expects -ErrorAction Stop
            Assert-MockCalled Write-Host -Times 1
        }

        It "Should fail for different string result" {
            Mock Invoke-RestMethod { "abc" }
            $Expects = "def"
            { Test-ApiEndPoint -Uri $TestUri -Expects $Expects -ErrorAction Stop } | Should -Throw
        }

        It "Should succeed for same string result" {
            Mock Invoke-RestMethod { "abc" }
            $Expects = "abc"
            Test-ApiEndPoint -Uri $TestUri -Expects $Expects -ErrorAction Stop
            Assert-MockCalled Write-Host -Times 1
        }
    }

    Describe "New-AppAzureResourceGroup" {

        Mock New-AzureRmResourceGroup { "Result" }

        It "Should not create new group if it already exists" {
            Mock Get-AzureRmResourceGroup { "GroupFound" }
            New-AppAzureResourceGroup -Name "Name" -Region "Region"
            Assert-MockCalled Get-AzureRmResourceGroup -Times 1 -ParameterFilter {$Name -eq "Name" -and $Location -eq "Region"}
            Assert-MockCalled New-AzureRmResourceGroup -Times 0
        }

        It "Should create new group if it does not already exists" {
            Mock Get-AzureRmResourceGroup
            New-AppAzureResourceGroup -Name "Name" -Region "Region"
            Assert-MockCalled Get-AzureRmResourceGroup -Times 1 -ParameterFilter {$Name -eq "Name" -and $Location -eq "Region"}
            Assert-MockCalled New-AzureRmResourceGroup -Times 1 -ParameterFilter {$Name -eq "Name" -and $Location -eq "Region"}
        }

    }

    Describe "Format-MetricAggregate" {

        It "Should format an average with maximum 3 decimal places" {
            Format-MetricAggregate 0.02323 -Type "Average" | Should -Be "0.023"
            Format-MetricAggregate 0.1 -Type "Average" | Should -Be "0.1"
        }

        It "Should format a total as an integer" {
            Format-MetricAggregate 1.232 -Type "Sum" | Should -Be "1"
            Format-MetricAggregate 1.632 -Type "Sum" | Should -Be "2"
            Format-MetricAggregate 22 -Type "Sum" | Should -Be "22"
            Format-MetricAggregate 2131 -Type "Sum" | Should -Be "2131"
        }

        It "Should format the appropriate property of a measure input" {
            1,2,3 | Measure-Object -Sum -Average | Format-MetricAggregate -Type "Sum" | Should -Be "6"
            1.1,2.1,3.1 | Measure-Object -Sum -Average | Format-MetricAggregate -Type "Sum" | Should -Be "6"
            1,2,3 | Measure-Object -Sum -Average | Format-MetricAggregate -Type "Average" | Should -Be "2"
            1,2,4 | Measure-Object -Sum -Average | Format-MetricAggregate -Type "Average" | Should -Be "2.333"
        }

    }

    Describe "Get-MetricAggregateType" {

        It "Should return correct type for input as string" {
            Get-MetricAggregateType "CpuTime" | Should -Be "Sum"
            Get-MetricAggregateType "AverageResponseTime" | Should -Be "Average"
            Get-MetricAggregateType "Requests" | Should -Be "Sum"
            Get-MetricAggregateType "Http2xx" | Should -Be "Sum"
            Get-MetricAggregateType "Http4xx" | Should -Be "Sum"
            Get-MetricAggregateType "Http5xx" | Should -Be "Sum"
        }

        It "Should accept name from pipeline" {
            "CpuTime" | Get-MetricAggregateType | Should -Be "Sum"
        }

        It "Should return correct type for input as PSMetric" {

            $Metric = New-Object "Microsoft.Azure.Management.Monitor.Models.Metric"
            $Name = New-Object "Microsoft.Azure.Management.Monitor.Models.LocalizableString" -ArgumentList "CpuTime","LocalCpuTime"
            $Metric.Name = $Name
            $PSMetric = New-Object "Microsoft.Azure.Commands.Insights.OutputClasses.PSMetric" -ArgumentList $Metric

            Get-MetricAggregateType $PSMetric | Should -Be "Sum"
        }
    }


    Describe "Get-MetricAggregate" {

        $AverageObject = [pscustomobject]@{
            Data = [pscustomobject]@{Total = 1},[pscustomobject]@{Total = 2},[pscustomobject]@{Total = 4}
            Name = @{ Value = "Name"}
        }

        It "Should accept input as argument" {
            Mock Get-MetricAggregateType {"Average"}
            $Result = Get-MetricAggregate $AverageObject
            $Result | Should -Be "2.333"
        }

        It "Should return average for all values without -Last parameter" {
            Mock Get-MetricAggregateType {"Average"}
            $Result = $AverageObject | Get-MetricAggregate
            $Result | Should -Be "2.333"
        }

        It "Should return sum for all values without -Last parameter" {
            Mock Get-MetricAggregateType {"Sum"}
            $Result = $AverageObject | Get-MetricAggregate
            $Result | Should -Be "7"
        }

        It "Should return sum for last 2 values" {
            Mock Get-MetricAggregateType {"Sum"}
            $Result = $AverageObject | Get-MetricAggregate -Last 2
            $Result | Should -Be "6"
        }

        It "Should return average for last 2 values" {
            Mock Get-MetricAggregateType {"Average"}
            $Result = $AverageObject | Get-MetricAggregate -Last 2
            $Result | Should -Be "3"
        }
    }

}
