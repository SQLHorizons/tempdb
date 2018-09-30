#Requires -Modules SQLServer
#Requires -Version 5.0

$VerbosePreference = "Continue"
$DebugPreference = "Continue"

##  parameter inputs from json manifest file
$tempdbParam = @{
    ServerName = "db-oc21"
    LoginType = "SQLLogin"
    LogicalName = "tempdev"
    Size = 128
    Files = 4
}

##  credential input
$Credential = Get-Credential

##  dot source the files:
. $PSScriptRoot\Connect-SQL.ps1
. $PSScriptRoot\tempdb.ps1

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

##  get the state of the temporary database.
$tempdb.Get()

##  test the state of the temporary database.
$tempdb.Test()
