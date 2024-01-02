<#
.TITLE
Service Account Finder (SAF)

.DESCRIPTION
This Script is based and inspired on Phil Robeson philrobeson@yahoo.com
(https://www.reddit.com/r/sysadmin/comments/c7m821/finding_where_an_ad_service_account_is_being_used/)
Check active Directory for servers and then check Win32_Service for any service account. create a report after

.OUTPUTS
service accounts on a table in C:\temp\report.html

.INFO
Version:        1.3.0
Author:         Antoine Fortin
Co-Author:      Olivier Magny
Date:           02/01/2024
#>

#-------------------------------------------------------[Progress bar]----------------------------------------------------------
$Counter = 0
$OnlineComputersCNT = 0
$ComputersCNT = 0
Write-Progress -Id 1 -Activity "Starting Script" -PercentComplete $Counter

#------------------------------------------------------[Request Elevatated Priviledge]-------------------------------------------
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
Write-Host 'Fetchings Servers...'
$Computers = Get-ADComputer -Filter {enabled -eq $true -and operatingsystem -like "*server*"} -properties Name, DNSHostName, Enabled, Operatingsystem |select Name, DNSHostName, Enabled, Operatingsystem

$Counter += 10
#---------------------------------------------------------[Define String]--------------------------------------------------------
$OnlineComputersNames = @()
$ComputersCNT = (30/($Computers.Count))

#---------------------------------------------------------[Test connectivity for each Servers]-----------------------------------
Write-Progress -Id 1 -Activity "Test Connection" -PercentComplete $Counter
Write-Host 'Testing Connection...'
foreach ($Server in $Computers){
    $Hostname =$Server.DNSHostName
    Write-Progress -Id 1 -Activity "Test Connection" -Status "$Hostname" -PercentComplete $Counter
    $Counter += $ComputersCNT
    $Pingtest = Test-Connection -ComputerName $Hostname -Quiet -Count 1 -ErrorAction SilentlyContinue
    if($Pingtest){
        $OnlineComputersNames += $Server.Name
     }
}

$OnlineComputersCNT = (30/($OnlineComputersNames.count))
#---------------------------------------------------------[Display values]-------------------------------------------------------

Write-Host 'Servers Fetched :'
$OnlineComputerNames = $OnlineComputersNames|Sort
Write-Host $OnlineComputerNames

#---------------------------------------------------------[HTML content]---------------------------------------------------------
$HTML = @"
<title>Service Account Script</title>
<style>
    html {margin: 0;background: linear-gradient(45deg, #49a09d, #5f2c82);font-family: sans-serif;font-weight: 100;}
    table {width: 800px;border-collapse: collapse;overflow: hidden;box-shadow: 0 0 20px rgba(0,0,0,0.1);}
    th,td {padding: 15px;background-color: rgba(255,255,255,0.2);color: #fff;}
    th {background-color: #55608f;text-align: left;}
    tbody {tr {&:hover {background-color: rgba(255,255,255,0.3);}}td {position: relative;&:hover {&:before {content: "";position: absolute;left: 0;right: 0;top: -9999px;bottom: -9999px;background-color: rgba(255,255,255,0.2);z-index: -1;}}}}
    h1,h2 {color: white;}
</style>
"@

#---------------------------------------------------------[Define the report file path]------------------------------------------
$Report = "C:\temp\report.html"
if ((Test-Path -Path $Report) -eq $false) {New-Item $Report -Force} 
Clear-Content -Path "$Report"

#---------------------------------------------------------[Loop through each computer]-------------------------------------------
ForEach ($SRV in $OnlineComputersNames) {
    Write-Progress -Id 1 -Activity "Generating Report" -Status "$SRV" -PercentComplete $Counter
    $Counter += $OnlineComputersCNT
    $Services = Get-WmiObject -ComputerName $SRV -Class Win32_Service -ErrorAction SilentlyContinue | Where-Object {
        $_.StartName -notin @("LocalSystem", "NT AUTHORITY\NetworkService", "NT AUTHORITY\Network Service", "NT AUTHORITY\LocalService", "NT AUTHORITY\Local Service", $null)}
        if ($Services.Count -gt 0) {
        $Services | Sort | Select-Object -Property StartName, Name, DisplayName | ConvertTo-Html -Property StartName, Name, DisplayName -Head $HTML -Body "<H2>$SRV</H2>" | Out-File -Append -FilePath $Report
    }
}

#---------------------------------------------------------[Open the report]------------------------------------------------------
Write-Progress -Activity "Report Generated" -Completed
Invoke-Item $Report
Write-Host @("Report Generated. location $Report")
Start-Sleep -Seconds 15

