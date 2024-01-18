<#
.TITLE
Service Account Finder (SAF)

.DESCRIPTION
This Script is based and inspired on Phil Robeson philrobeson@yahoo.com
(https://www.reddit.com/r/sysadmin/comments/c7m821/finding_where_an_ad_service_account_is_being_used/)
Check active Directory for servers and then check Win32_Services for any service account and scheduled tasks. create a html report.

.OUTPUTS
service accounts and scheduled tasks on a table in C:\temp\report.html

.INFO
Version:        2.0.1
Author:         Antoine Fortin
Co-Author:      Olivier Magny
Date:           18/01/2024
#>

#-------------------------------------------------------[Progress bar]----------------------------------------------------------
$Counter = 0
$OnlineComputersCNT = 0
$ComputersCNT = 0
Write-Progress -Id 1 -Activity "Starting Script" -PercentComplete $Counter

#------------------------------------------------------[Request Elevatated Privilege]-------------------------------------------
Write-Progress -Id 1 -Activity "Check Elevatated Priviledge" -Status "Checking..." -PercentComplete $Counter
if (-not (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
$arguments = "& '" + $myInvocation.MyCommand.Definition + "'"
Start-Process powershell -Verb runAs -ArgumentList $arguments
exit
}

$Counter += 10
#------------------------------------------------[Install RSAT ActiveDirectory if Needed]----------------------------------------
Write-Progress -Id 1 -Activity "Active Directory RSAT" -Status "Checking..." -PercentComplete $Counter
$RSAT = Get-WindowsCapability -Name "Rsat.ActiveDirectory*" -Online 
if (($RSAT.State) -eq "NotPresent") {
    Write-Progress -Id 1 -Activity "Active Directory RSAT" -Status "Installing..." -PercentComplete $Counter
    Get-WindowsCapability -Name "Rsat.ActiveDirectory*" -Online | Add-WindowsCapability -Online
}

$Counter += 10
#----------------------------------------------------------[Test ADWS port]------------------------------------------------------
Write-Progress -Id 1 -Activity "Test ADWS port" -Status "Checking..." -PercentComplete $Counter
$DC = $Env:userdnsdomain
if (([System.Net.Sockets.TcpClient]::new().ConnectAsync("$DC", 9389).Wait(100) -eq $false)) {
Write-host "Unable to reach DC with Active Directory Web Services"
Write-host "Check Firewall"
Start-Sleep -Seconds 15
exit
}

$Counter += 10
#---------------------------------------------------------[Retrive Servers in AD]------------------------------------------------
Write-Progress -Id 1 -Activity "Retrive Servers in Active Directory" -Status "Checking..." -PercentComplete $Counter
$Computers = Get-ADComputer -Filter {enabled -eq $true -and operatingsystem -like "*server*"} -properties Name, DNSHostName, Enabled, Operatingsystem |select Name, DNSHostName, Enabled, Operatingsystem

$Counter += 10
#---------------------------------------------------------[Define String]--------------------------------------------------------
class OnlineComputer {
    [string] $Name
    [bool] $WinRM
}
$OnlineComputers = [System.Collections.Generic.List[OnlineComputer]]::new()

$ComputersCNT = (20/($Computers.Count))

#---------------------------------------------------------[Test connectivity for each Servers]-----------------------------------
Write-Progress -Id 1 -Activity "Test Connection" -PercentComplete $Counter

foreach ($Server in $Computers){
    $Hostname =$Server.DNSHostName
    Write-Progress -Id 1 -Activity "Test Connection" -Status "$Hostname" -PercentComplete $Counter
   
    $Counter += $ComputersCNT
   
    $Pingtest = Test-Connection -ComputerName $Hostname -Quiet -Count 1 -ErrorAction SilentlyContinue
    if($Pingtest){
        $OnlineComputer = New-Object OnlineComputer
        $OnlineComputer.Name = $Server.Name
        if (([System.Net.Sockets.TcpClient]::new().ConnectAsync("$Hostname", 5985).Wait(100) -eq $True)) {
            $OnlineComputer.WinRM = $True
        }
        $OnlineComputers.Add($OnlineComputer)
    }
}

$OnlineComputersCNT = (40/($OnlineComputers.count))

#---------------------------------------------------------[HTML content]---------------------------------------------------------
$HTML = @"
<title>Service Account Script</title>
<style>
    html {margin: 0;background: linear-gradient(45deg, #49a09d, #5f2c82);font-family: sans-serif;font-weight: 100;}
    table {width: 800px;border-collapse: collapse;overflow: hidden;box-shadow: 0 0 20px rgba(0,0,0,0.1);}
    th,td {padding: 15px;background-color: rgba(255,255,255,0.2);color: #fff;}
    th {background-color: #55608f;text-align: left;}
    tbody {tr {&:hover {background-color: rgba(255,255,255,0.3);}}td {position: relative;&:hover {&:before {content: "";position: absolute;left: 0;right: 0;top: -9999px;bottom: -9999px;background-color: rgba(255,255,255,0.2);z-index: -1;}}}}
    h1,h2,h3 {color: white;}
    h1 {margin-top: 30px;}
</style>
"@

#---------------------------------------------------------[Define the report file path]------------------------------------------
$Report = "C:\temp\report.html"
if ((Test-Path -Path $Report) -eq $false) {New-Item $Report -Force} 
Clear-Content -Path "$Report"
if ($OnlineComputer.WinRM -eq $True -le 0) {
    ConvertTo-Html -Head $HTML -PreContent "<h1>No Servers Found</h1>" | Out-File -Append -FilePath $Report
} 

#---------------------------------------------------------[Loop through each computer]-------------------------------------------
ForEach ($OnlineComputer in $OnlineComputers) {
    if ($OnlineComputer.WinRM -eq $True) {
        Write-Progress -Id 1 -Activity "Generating Report" -Status $OnlineComputer.Name -PercentComplete $Counter -CurrentOperation "Services"
        
        $Services = Get-WmiObject -ComputerName "SVCAPPDEV.prosol.ca" -Class Win32_Service -ErrorAction SilentlyContinue | Where-Object {
            $_.StartName -notin @("LocalSystem", "NT AUTHORITY\NetworkService", "NT AUTHORITY\Network Service", "NT AUTHORITY\LocalService", "NT AUTHORITY\Local Service", $null)
        }
        
        if ($Services.Count -gt 0) {
            $Services | Sort-Object | Select-Object -Property StartName, Name, DisplayName | ConvertTo-Html -Property StartName, Name, DisplayName -Head $HTML -Body "<H2>$($OnlineComputer.Name)</H2>" -PreContent "<h3>Services</h3>" | Out-File -Append -FilePath $Report
        }
        
        $Counter += ($OnlineComputersCNT/2)

        Write-Progress -Id 1 -Activity "Generating Report" -Status $OnlineComputer.Name -PercentComplete $Counter -CurrentOperation "Scheduled Tasks"

        $Tasks = Get-ScheduledTask -CimSession $OnlineComputer.Name -ErrorAction SilentlyContinue | Select-Object pscomputername,TaskName, @{Name="RunAs";Expression={ $_.principal.userid }},state | Where-Object {
            $_.RunAs -notin @("SYSTEM", "LOCAL SERVICE", "NETWORK SERVICE", "", $null) -and 
            $_.TaskName -notlike @("*Optimize Start Menu*") -and 
            $_.TaskName -notlike @("*User_Feed_Synchronization*")
        }
        
        if ($Services.Count -le 0 -and $Tasks.Count -gt 0) {
                    ConvertTo-Html -Body "<H2>$($OnlineComputer.Name)</H2>" | Out-File -Append -FilePath $Report
        }    
        
        if ($Tasks.Count -gt 0) {
            $Tasks | Sort-Object  | Select-Object -Property pscomputername,TaskName,RunAs,state | ConvertTo-Html -Property pscomputername,TaskName,RunAs,state -Head $HTML -PreContent "<h3>Tasks</h3>"  | Out-File -Append -FilePath $Report
        }

        $Counter += ($OnlineComputersCNT/2)
    }      
}

#---------------------------------------------------------[Open the report]------------------------------------------------------
Write-Progress -Activity "Report Generated" -PercentComplete 100 -Completed
Invoke-Item $Report
Write-Host @("Report Generated. location $Report")
Start-Sleep -Seconds 15