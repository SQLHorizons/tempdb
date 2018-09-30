#Requires -Modules SQLServer
#Requires -Version 5.0

$VerbosePreference = "Continue"
$DebugPreference = "Continue"


##  get private function definition files.
$Private = @(Get-ChildItem -Path D:/.source/repos/tempdb/private/*.ps1 -ErrorAction Stop)

##  dot source the private files
Foreach ($import in $Private) {
    Try {
        Write-Verbose -Message "Import function $($import.Name)"
        . $import.FullName
    }
    Catch {
        Write-Error -Message "Failed to import function $($import.FullName): $PSItem"
    }
}

##  get class definition files.
$Classes = @(Get-ChildItem -Path D:/.source/repos/tempdb/classes/*.ps1 -ErrorAction Stop)

##  dot source the classes files
Foreach ($import in $Classes) {
    Try {
        Write-Verbose "Import class $($import.Name)"
        . $import.FullName
    }
    Catch {
        Write-Error -Message "Failed to import class $($import.FullName): $PSItem"
    }
}

##  parameter inputs from json manifest file
$tempdbParam = @{
    ServerName = "db-oc21"
    LoginType = "SQLLogin"
    LogicalName = "tempdev"
    Size = 128
    Files = 4
}

##  credential input
##  $Credential = Get-Credential


##  create tempdb object.
$classParameters = @{
    TypeName     = [tempdb]
    ArgumentList = $tempdbParam.ServerName
    ErrorAction  = "Stop"
}
Write-Verbose "Creating tempdb Object."
$tempdb = New-Object @classParameters

##  get credentials, this is a test and needs further work.
##  connect locally so don't need a credential.
##  $tempdb.SetupCredential = Test-Credential

##  values for temporary database.
$tempdb.LoginType = $tempdbParam.LoginType
$tempdb.SetupCredential = $Credential
$tempdb.LogicalName = $tempdbParam.LogicalName
$tempdb.Size = $tempdbParam.Size
$tempdb.Files = $tempdbParam.Files

##  set the state of the temporary database.
$tempdb.Set()
