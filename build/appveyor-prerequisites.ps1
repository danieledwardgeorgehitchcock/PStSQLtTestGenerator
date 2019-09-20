Add-AppveyorTest -Name "appveyor.prerequisites" -Framework NUnit -FileName "appveyor-prerequisites.ps1" -Outcome Running
$sw = [system.diagnostics.stopwatch]::startNew()

Install-Module PSFramework -Force -SkipPublisherCheck
Write-PSFMessage -Level Host -Message "Installing dbatools"
Install-Module dbatools -Force -SkipPublisherCheck
Write-PSFMessage -Level Host -Message "Installing Pester"
Install-Module Pester -Force -SkipPublisherCheck
Write-PSFMessage -Level Host -Message "Installing PSScriptAnalyzer"
Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck

. "$PSScriptRoot\appveyor-constants.ps1"

Write-PSFMessage -Level Host -Message "Create Unit Tests Folder"
if (-not (Test-Path -Path $unittestfolder)) {
    $null = New-Item -Path $unittestfolder -ItemType Directory
}

Write-PSFMessage -Level Host -Message "Setup Database"
$server = Connect-DbaInstance -SqlInstance $instance

if ($server.Databases.Name -notcontains $database) {
    # Create the database
    $query = "CREATE DATABASE $($database)"
    $server.Query($query)

    # Refresh the server object
    $server.Refresh()

    Invoke-DbaQuery -SqlInstance $instance -Database $database -File "$PSScriptRoot\..\tests\functions\database.sql"

    $server.Databases.Refresh()

    if ($server.Databases[$database].Tables.Name -notcontains 'Person') {
        Stop-PSFFunction -Message "Database creation unsuccessful!"
        return
    }
}

$sw.Stop()
Update-AppveyorTest -Name "appveyor-prerequisites" -Framework NUnit -FileName "appveyor-prerequisites.ps1" -Outcome Passed -Duration $sw.ElapsedMilliseconds