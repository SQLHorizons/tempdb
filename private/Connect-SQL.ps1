#Requires -Version 5.0

<#
    .SYNOPSIS
        Connect to a SQL Server Database Engine and return the server object.

    .PARAMETER SQLServer
        String containing the host name of the SQL Server to connect to.

    .PARAMETER SQLInstanceName
        String containing the SQL Server Database Engine instance to connect to.

    .PARAMETER SetupCredential
        PSCredential object with the credentials to use to impersonate a user when connecting.
        If this is not provided then the current user will be used to connect to the SQL Server Database Engine instance.

    .PARAMETER LoginType
        If the SetupCredential is set, specify with this parameter, which type
        of credentials are set: Native SQL login or Windows user Login. Default
        value is 'WindowsUser'.
#>
function Connect-SQL
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ServerName = $env:COMPUTERNAME,

        [ValidateNotNullOrEmpty()]
        [System.String]
        $SQLInstanceName = "MSSQLSERVER",

        [AllowNull()]
        [System.Management.Automation.PSCredential]
        $SetupCredential,

        [Parameter()]
        [ValidateSet("WindowsUser", "SqlLogin")]
        [System.String]
        $LoginType = "WindowsUser"
    )

    Try {

        Write-Verbose "ServerName: $ServerName"
        Write-Verbose "SQLInstanceName: $SQLInstanceName"
        Write-Verbose "SetupCredential: $SetupCredential"
        Write-Verbose "LoginType: $LoginType"
 
        switch ($SQLInstanceName) {
            ##  check for default instance name.
            {$_ -eq "MSSQLSERVER"} {
                $serverInstance = $ServerName
            }
            ##  check for use of port number.
            {$_ -match "^\d+$"}{
                $serverInstance = "$ServerName,$SQLInstanceName"
            }
            ##  assume named instance is required.
            default { 
                $serverInstance = "$ServerName\$SQLInstanceName"
            }
        }
        Write-Verbose "Create connection on: $serverInstance"

        ##  create smo server object
        $SMO = @{
            TypeName     = "Microsoft.SqlServer.Management.Smo.Server"
            ErrorAction  = "Stop"
        }
        Write-Verbose "Creating SQL Server Management Object."

        ##  open t-sql endpoint with target server.
        $SQLServer = New-Object @SMO
        Write-Verbose "Server Management Object created."

        if ($SetupCredential) {

            if ($LoginType -eq "SqlLogin") {
                $SQLServer.ConnectionContext.LoginSecure = $false
                $SQLServer.ConnectionContext.Login = $SetupCredential.UserName
                $SQLServer.ConnectionContext.set_SecurePassword($SetupCredential.Password)
            }
    
            if ($LoginType -eq "WindowsUser") {
                $SQLServer.ConnectionContext.ConnectAsUser = $true
                $SQLServer.ConnectionContext.ConnectAsUserName = $SetupCredential.UserName
                $SQLServer.ConnectionContext.ConnectAsUserPassword = $SetupCredential.GetNetworkCredential().Password   
            }
        }

        $SQLServer.ConnectionContext.ServerInstance = $serverInstance

        Write-Verbose "Connecting to SQL instance: $serverInstance."
        $SQLServer.ConnectionContext.Connect()

        ## ALL DONE
        if ( $SQLServer.Status -match "^Online$" ) {
            Write-Verbose "Connected to: $serverInstance."
            Return $SQLServer
        }
        else {
            $message = "Failed to connect to server: $serverInstance."
            throw $message
        }

    }
    Catch [System.Exception] {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }

}
