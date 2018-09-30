#Requires -Version 5.0

class tempdb {

    ##  SQL server name or alias.
    [ValidateNotNullOrEmpty()]
    [System.String]
    $ServerName = $env:COMPUTERNAME

    ##  SQL instance name, default "MSSQLSERVER".
    [ValidateNotNullOrEmpty()]
    [System.String]
    $InstanceName = "MSSQLSERVER"

    ##  Credential used during setup.
    [ValidateNotNullOrEmpty()]
    [System.Management.Automation.PSCredential]
    $SetupCredential

    ##  Credential type "WindowsUser", or "SqlLogin".
    [ValidateSet("WindowsUser", "SqlLogin")]
    [System.String]
    $LoginType = "WindowsUser"

    ##  Logical name of the tempdb devices.
    [ValidateNotNullOrEmpty()]
    [System.String] 
    $LogicalName = "tempdev"

    ##  tempdb size in Megabytes.
    [ValidateNotNullOrEmpty()]
    [System.Int32] 
    $Size

    ##  The number of tempdb files to allocate.
    [AllowNull()]
    [System.Int16] 
    $Files = 4

    ##  Allow the setup to determine the number of files to allocate.
    [System.Boolean]
    $DynamicAlloc = $false

    ##  Internal use, to determine whether the required state is met.
    [System.Boolean]
    $IsValid = $null

    tempdb(
        [System.String]
        $ServerName
    ) {
        $this.ServerName = $ServerName
    }

    ##  get the current state of the tempdb object.
    [tempdb] Get() {

        Try {
            Write-Verbose "getting properties of tempdb."

            ##  create tempdb object.
            $classParameters = @{
                TypeName     = [tempdb]
                ArgumentList = $this.ServerName
                ErrorAction  = "Stop"
            }
            Write-Verbose "Creating result Object."
            $result = New-Object @classParameters

            $result.SetupCredential = $this.SetupCredential
            $result.LoginType = $this.LoginType          

            if($global:SQLServer) {

                ##  get global smo server object.
                Write-Host "VERBOSE: Using the global SQL Management Object." -ForegroundColor Magenta
                $SQLServer = $global:SQLServer

            }
            else {

                ##  create smo server object
                $ConnectionParameters = @{
                    ServerName = $this.ServerName
                    SetupCredential = $this.SetupCredential
                    LoginType = $this.LoginType
                }
                $SQLServer = Connect-SQL @ConnectionParameters

            }
            
            if ($SQLServer) {
                
                Write-Verbose "get tempdb object."
                $tempdb = $SQLServer.Databases["tempdb"].FileGroups["PRIMARY"]
    
                Write-Verbose "get the number of files based on current config."
                $result.Files = $tempdb.Files.Count
    
                $FileSize = 0
                Write-Verbose "get the total size of tempdb and LogicalName."
                foreach ($file in $tempdb.Files | Sort-Object -Property ID) {
                    $FileSize += $file.Size
                    if($($file.Name -replace '[^a-zA-Z-]','') -ne $this.LogicalName){
                        $result.LogicalName = "...Invalid!"
                    }
                }
                $result.size = $FileSize/1Kb
            }
            else {
                $message = "Connect-SQL: Failed!"
                Throw $message
            }
    
            ## ALL DONE
            Write-Verbose "Return the results object."

            Return $result
    
        }
        Catch [System.Exception] {
            $message = $_.Exception.GetBaseException().Message
            Throw $message
        }
   
    }

    ##  set the current state of the tempdb object.
    [void] Set() {

        Try {
            Write-Verbose "setting properties of tempdb."

            if($global:SQLServer) {

                ##  get global smo server object.
                Write-Host "VERBOSE: Using the global SQL Management Object." -ForegroundColor Magenta
                $SQLServer = $global:SQLServer

            }
            else {

                ##  create smo server object
                $ConnectionParameters = @{
                    ServerName = $this.ServerName
                    SetupCredential = $this.SetupCredential
                    LoginType = $this.LoginType
                }
                $SQLServer = Connect-SQL @ConnectionParameters

            }
    
            if ($SQLServer) {

                ##  clear log of completed transactions.
                $SQLServer.Databases["tempdb"].Checkpoint()

                Write-Verbose "get tempdb and log object."
                $tempdb = $SQLServer.Databases["tempdb"].FileGroups["PRIMARY"]
                $tLog   = $SQLServer.Databases["tempdb"].LogFiles["templog"]
    
                if ($this.DynamicAlloc) {
                    $Parameters = @{
                        ComputerName = $this.ServerName
                        Class        = "Win32_ComputerSystem"
                        ErrorAction  = "Stop"
                    }
    
                    Write-Verbose "Getting the number of files based on processor count."
                    $this.Files = (Get-WmiObject @Parameters).NumberOfLogicalProcessors; 
                    if ($this.Files -gt 8) {$this.Files = 8};
                }

                ##  get the individual file size based on number of files needed.
                $FileSize = [math]::Ceiling(($this.Size * 1Kb) / $this.Files)
                Write-Debug "Desired state of individual file size is: $FileSize Kb"

                ##  check that the tempdb file count matches the state.
                switch ($tempdb.Files.Count) {
                    {$_ -gt $this.Files} {
                        ##  it is not possible to reduce the number of files in normal operation, Throw exception.

                        ##  get fileID of the last file.
                        $fileID = ($tempdb.Files.ID | Measure-Object -Maximum).Maximum
                        do{
                            ##  get last file object.
                            $file = $tempdb.Files.ItemByID($fileID)

                            if($file){
                                Write-Verbose "Removing file $($file.ID), name $($file.Name)."
                                if($file.ID -le 2){
                                    $message = "Cannot remove file id: $($file.ID)"
                                    Throw $message
                                }
                                else{
                                    Write-Verbose "Shrinking file $($file.Name) to 0 Mb."
                                    $file.Shrink($($FileSize /1Kb), 3)
                                    Write-Verbose "Drop file $($file.Name)."
                                    $file.Drop()
                                }
                            }

                            $fileID -= 1
                        } while($fileID-1 -gt $($this.Files))
                    }
                    {$_ -eq $this.Files} {
                        ##  this is the valid state so no action is taken.
                        Write-Debug "There are $($tempdb.Files.Count) Files: Do Nothing..."
                    }
                    {$_ -lt $this.Files} {
                        ##  the number of file may be increased to meet the state, if there is disk space.
                        Write-Verbose "There are $($tempdb.Files.Count) Files: Fix..."

                        ##  get fileID for new file.
                        $fileID = ($tempdb.Files.ID | Measure-Object -Maximum).Maximum +1
                                
                        do{
                            ##  create new file object.
                            $fileParameters  = @{
                                TypeName     = "Microsoft.SqlServer.Management.SMO.DataFile"
                                ArgumentList = $tempdb, "$($this.LogicalName)$($fileID)"
                                ErrorAction  = "Stop"
                            }

                            $file = New-Object @fileParameters

                            $file.FileName = "$($tempdb.Parent.PrimaryFilePath)\$($this.LogicalName)$fileID.ndf"
                            Write-Verbose "Creating tempdb file: $($this.LogicalName)$fileID."
                            $file.Create()

                            $fileID += 1
                        } while($fileID-1 -le $($this.Files))
                    }   
                }

                ##  set the state of the primary files.
                foreach ($file in $tempdb.Files | Sort-Object -Property ID) {
                    Write-Verbose "Working on file id: $($file.ID), file $($file.Name)."
                
                    ##  check if logical file name is correct and set state.
                    if($file.Name -ne "$($this.LogicalName)$($file.ID)"){
                        Write-Verbose "Rename logical file: $($file.Name) to $($this.LogicalName)$($file.ID)"
                        $file.Rename("$($this.LogicalName)$($file.ID)")
                    }

                    ##  check size of tempdb files and set state.
                    switch ($file.Size) {
                        {$_ -gt $FileSize} {
                            ##  file larger than desired state, attempt to shrink file size.
                            Write-Verbose "Shrinking file $($file.Name) to $($FileSize /1Kb) Mb"
                            $file.Shrink($($FileSize /1Kb), 0)
                        }
                        {$_ -eq $FileSize} {
                            ##  this is the valid state so no action is taken.
                            Write-Verbose "The tempdb file $($file.Name) is $($FileSize /1Kb) Mb"
                        }
                        {$_ -lt $FileSize} {
                            ##  file smaller than desired state, attempt to increase file size.
                            Write-Verbose "Increase file $($file.Name) to $($FileSize /1Kb) Mb"
                            $file.Size = $FileSize
                        }   
                    }
                    $file.GrowthType = "none"
                    $file.Alter()
                }

                ##  set the state of the transaction log files.
                Write-Verbose "Working on log file id: $($tLog.ID), file $($tLog.Name)..."

                ##  check size of tempdb log file and set state.
                switch ($tLog.Size) {
                    {$_ -gt $FileSize} {
                        ##  file larger than desired state, attempt to shrink file size.
                        Write-Verbose "Shrinking file $($tLog.Name) to $($FileSize /1Kb) Mb"
                        $tLog.Shrink($($FileSize /1Kb), 0)
                    }
                    {$_ -eq $FileSize} {
                        ##  this is the valid state so no action is taken.
                        Write-Verbose "The tempdb file $($tLog.Name) is $($FileSize /1Kb) Mb"
                    }
                    {$_ -lt $FileSize} {
                        ##  file smaller than desired state, attempt to increase file size.
                        Write-Verbose "Increase file $($tLog.Name) to $($FileSize /1Kb) Mb"
                        $tLog.Size = $FileSize
                    }   
                }
                $tLog.GrowthType = "none"
                $tLog.Alter()
            }
    
            ## ALL DONE
            $this.IsValid = $true
            Write-Verbose "State IsValid: $($this.IsValid)."

            Return
    
        }
        Catch [System.Exception] {
            $message = $_.Exception.GetBaseException().Message
            Throw $message
        }

    }

    ##  test the current state of the tempdb object.
    [Boolean] Test() {

        Try {
            Write-Verbose "testing properties of tempdb."

            $result = $this.Get()

            ##  test state.
            Write-Verbose "LogicalName status: $($this.LogicalName -eq $result.LogicalName)"
            $this.IsValid = ($this.LogicalName -eq $result.LogicalName)
            Write-Verbose "tempdb size status: $($this.Size -eq $result.Size)"
            $this.IsValid = $this.IsValid -and ($this.Size -eq $result.Size)
            Write-Verbose "tempdb file count status: $($this.Files -eq $result.Files)"
            $this.IsValid = $this.IsValid -and ($this.Files -eq $result.Files)

            ## ALL DONE
            Write-Verbose "Return the state of the test."

            Return $this.IsValid
        }
        Catch [System.Exception] {
            $message = $_.Exception.GetBaseException().Message
            Throw $message
        }

    }
}
