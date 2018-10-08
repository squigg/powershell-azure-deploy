#Requires -Modules DotNet
#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="4.0.0" }

InModuleScope DotNet {

    Mock Write-Host

    Describe 'Test-DotNetApp' {

        Mock Invoke-DotNetTestCommand

        It 'Should run dotnet test command with correct parameters' {
            Test-DotNetApp -Source 'Source' -Project 'Project'
            Assert-MockCalled Invoke-DotNetTestCommand -Times 1 -ParameterFilter {$Project -eq 'Source\Project'}
        }
        It 'Should run dotnet test command with default UnitTests project parameter' {
            Test-DotNetApp -Source 'Source'
            Assert-MockCalled Invoke-DotNetTestCommand -Times 1 -ParameterFilter {$Project -eq 'Source\UnitTests'}
        }
    }

    Describe 'New-DotNetAppRelease' {

        Mock Invoke-DotNetPublishCommand
        Mock Compress-Archive
        Mock Get-Date { 201801010000 }

        $Source = $TestDrive
        $Dest = "$TestDrive\201801010000.zip"
        New-Item $Dest -Force

        It 'Should run dotnet publish command with correct parameters' {
            New-DotNetAppRelease -Source $TestDrive -Project 'Project'
            Assert-MockCalled Invoke-DotNetPublishCommand -Times 1 -ParameterFilter {$OutputDir -eq "$Source\publish" -and $Project -eq "$Source\Project.csproj"}
        }

        It 'Should create ZIP file from publish folder and save in source folder' {
            New-DotNetAppRelease -Source $TestDrive -Project 'Project'
            Assert-MockCalled Compress-Archive -Times 1 -ParameterFilter {$Path -eq "$Source\publish\*" -and $DestinationPath -eq $Dest}
        }

        It 'Should return FileInfo for created ZIP file' {
            $Result = New-DotNetAppRelease -Source $TestDrive -Project 'Project'
            $Result.FullName | Should -Be $Dest
            $Result | Should -BeOfType [System.IO.FileInfo]
        }
    }
}
