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
Version:        1.1.0
Author:         Antoine Fortin
Co-Author:      Olivier Magny
Date:           28/12/2023
#>

#
if (-not (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
# Prompt the user to elevate the script
$arguments = "& '" + $myInvocation.MyCommand.Definition + "'"
Start-Process powershell -Verb runAs -ArgumentList $arguments
exit
}

#---------------------------------------------------------[Retrive Servers in AD]------------------------------------------------
Write-Host 'Fetchings Servers...'
$Computers = Get-ADComputer -Filter {enabled -eq $true -and operatingsystem -like "*server*"} -properties *|select Name, DNSHostName, Enabled, Operatingsystem

#---------------------------------------------------------[Define String]--------------------------------------------------------
$OnlineComputerNames = @()

#---------------------------------------------------------[Test connectivity for each Servers]-----------------------------------
foreach ($Server in $Computers){
    $Hostname =$Server.DNSHostName
    $Pingtest = Test-Connection -ComputerName $Hostname -Quiet -Count 1 -ErrorAction SilentlyContinue
    if($Pingtest){
        $OnlineComputerNames += $Server.Name
     } 
}

#---------------------------------------------------------[Display values]-------------------------------------------------------

Write-Host 'Servers Fetched :'
$OnlineComputerNames = $OnlineComputerNames|Sort
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
Clear-Content -Path "$Report"


#---------------------------------------------------------[Loop through each computer]-------------------------------------------
Write-Host 'Generating Report...'
ForEach ($SRV in $OnlineComputerNames) {
    $Services = Get-WmiObject -ComputerName $SRV -Class Win32_Service -ErrorAction SilentlyContinue | Where-Object {
        $_.StartName -notin @("LocalSystem", "NT AUTHORITY\NetworkService", "NT AUTHORITY\Network Service", "NT AUTHORITY\LocalService", "NT AUTHORITY\Local Service", $null)}
    if ($Services.Count -gt 0) {
    $Services | Sort | Select-Object -Property StartName, Name, DisplayName | ConvertTo-Html -Property StartName, Name, DisplayName -Head $HTML -Body "<H2>$SRV</H2>" | Out-File -Append -FilePath $Report
    }
}

#---------------------------------------------------------[Open the report]------------------------------------------------------
Invoke-Item $Report
Write-Host @("Report Generated. location $Report")