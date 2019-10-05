function New-PSTGProcedureParameterTest {
    <#
    .SYNOPSIS
        Function to create procedure tests

    .DESCRIPTION
        The function will collect the parameter(s) of the procedure(s) and create the test

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database or databases to add.

    .PARAMETER Procedure
        Procedure(s) to create tests for

    .PARAMETER OutputPath
        Path to output the test to

    .PARAMETER TemplateFolder
        Path to template folder. By default the internal templates folder will be used

    .PARAMETER TestClass
        Test class name to use for the test

    .PARAMETER InputObject
        Takes the parameters required from a Procedure object that has been piped into the command

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        New-PSTGProcedureParameterTest -Procedure $procedure -OutputPath $OutputPath

        Create a new procedure parameter test

    .EXAMPLE
        $procedures | New-PSTGProcedureParameterTest -OutputPath $OutputPath

        Create the tests using pipelines
    #>

    [CmdletBinding(SupportsShouldProcess)]

    param(
        [DbaInstanceParameter]$SqlInstance,
        [pscredential]$SqlCredential,
        [string]$Database,
        [string[]]$Procedure,
        [string]$OutputPath,
        [string]$TemplateFolder,
        [string]$TestClass,
        [parameter(ParameterSetName = "InputObject", ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        # Check parameters
        if (-not $SqlInstance) {
            Stop-PSFFunction -Message "Please enter a SQL Server instance" -Target $SqlInstance
            return
        }

        if (-not $Database) {
            Stop-PSFFunction -Message "Please enter a database" -Target $Database
            return
        }

        # Check the output path
        if (-not $OutputPath) {
            Stop-PSFFunction -Message "Please enter an output path"
            return
        }

        if (-not (Test-Path -Path $OutputPath)) {
            Stop-PSFFunction -Message "Could not access output path" -Category ResourceUnavailable -Target $OutputPath
        }

        # Check the template folder
        if (-not $TemplateFolder) {
            $TemplateFolder = Join-Path -Path ($script:ModuleRoot) -ChildPath "internal\templates"
        }

        if (-not (Test-Path -Path $TemplateFolder)) {
            try {
                $null = New-Item -Path $OutputPath -ItemType Directory
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the output directory" -Target $OutputPath -ErrorRecord $_
            }
        }

        if (-not $TestClass) {
            $TestClass = "TestBasic"
        }

        $date = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern
        $creator = $env:username

        # Connect to the server
        try {
            $server = Connect-DbaInstance -SqlInstance $Sqlinstance -SqlCredential $SqlCredential
        }
        catch {
            Stop-PSFFunction -Message "Could not connect to '$Sqlinstance'" -Target $Sqlinstance -ErrorRecord $_ -Category ConnectionError
            return
        }

        # Check if the database exists
        if ($Database -notin $server.Databases.Name) {
            Stop-PSFFunction -Message "Database cannot be found on '$SqlInstance'" -Target $Database
        }

        $task = "Collecting objects"
        Write-Progress -ParentId 1 -Activity " Stored Procedure Parameters" -Status 'Progress->' -CurrentOperation $task -Id 2
    }

    process {
        if (Test-PSFFunctionInterrupt) { return }

        if (-not $InputObject -and -not $Procedure -and -not $SqlInstance) {
            Stop-PSFFunction -Message "You must pipe in an object or specify a Procedure"
            return
        }

        if ($Procedure) {
            $InputObject += $server.Databases[$Database].StoredProcedures | Select-Object Schema, Name, Parameters | Where-Object Name -in $Procedure
        }
        else {
            $InputObject += $server.Databases[$Database].StoredProcedures | Select-Object Schema, Name, Parameters, IsSystemObject | Where-Object IsSystemObject -eq $false
        }

        $objectCount = $InputObject.Count
        $objectStep = 1

        if ($objectCount -ge 1) {
            foreach ($input in $InputObject) {
                $task = "Creating procedure $($objectStep) of $($objectCount)"
                Write-Progress -ParentId 1 -Activity "Creating..." -Status 'Progress->' -PercentComplete ($objectStep / $objectCount * 100) -CurrentOperation $task -Id 2

                $testName = "test If stored procedure $($input.Schema).$($input.Name) has the correct parameters"

                # Test if the name of the test does not become too long
                if ($testName.Length -gt 128) {
                    Stop-PSFFunction -Message "Name of the test is too long" -Target $testName
                }

                $fileName = Join-Path -Path $OutputPath -ChildPath "$($testName).sql"
                $date = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern
                $creator = $env:username

                # Get the parameters
                $parameters = $input.Parameters

                if ($parameters.Count -ge 1) {
                    # Import the template
                    try {
                        $script = Get-Content -Path (Join-Path -Path $TemplateFolder -ChildPath "ProcedureParameterTest.template")
                    }
                    catch {
                        Stop-PSFFunction -Message "Could not import test template 'ProcedureParameterTest.template'" -Target $testName -ErrorRecord $_
                    }

                    $paramTextCollection = @()

                    # Loop through the parameters
                    foreach ($parameter in $parameters) {
                        $paramText = "`t('$($parameter.Name)', '$($parameter.DataType.Name)', $($parameter.DataType.MaximumLength), $($parameter.DataType.NumericPrecision), $($parameter.DataType.NumericScale))"
                        $paramTextCollection += $paramText
                    }

                    # Replace the markers with the content
                    $script = $script.Replace("___TESTCLASS___", $TestClass)
                    $script = $script.Replace("___TESTNAME___", $testName)
                    $script = $script.Replace("___SCHEMA___", $input.Schema)
                    $script = $script.Replace("___NAME___", $input.Name)
                    $script = $script.Replace("___CREATOR___", $creator)
                    $script = $script.Replace("___DATE___", $date)
                    $script = $script.Replace("___PARAMETERS___", ($paramTextCollection -join ",`n") + ";")

                    # Write the test
                    if ($PSCmdlet.ShouldProcess("$($input.Schema).$($input.Name)", "Writing Procedure Parameter Test")) {
                        try {
                            Write-PSFMessage -Message "Creating procedure parameter test for procedure '$($input.Schema).$($input.Name)'"
                            $script | Out-File -FilePath $fileName

                            [PSCustomObject]@{
                                TestName = $testName
                                Category = "ProcedureParameter"
                                Creator  = $creator
                                FileName = $fileName
                            }
                        }
                        catch {
                            Stop-PSFFunction -Message "Something went wrong writing the test" -Target $testName -ErrorRecord $_
                        }
                    }
                }
                else {
                    Write-PSFMessage -Message "Procedure $($input.Schema).$($input.Name) does not have any parameters. Skipping..."
                }
            }
        }
    }
}