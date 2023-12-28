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
Version:        1.0.0
Author:         Antoine Fortin
Co-Author:      Olivier Magny
Date:           28/12/2023
#>

#---------------------------------------------------------[Retrive Servers in AD]--------------------------------------------------------
Write-Host 'Fetchings Servers...'
$Computers = Get-ADComputer -Filter {enabled -eq $true -and operatingsystem -like "*server*"} -properties *|select Name, DNSHostName, Enabled, Operatingsystem

#---------------------------------------------------------[Define String]--------------------------------------------------------
$OnlineComputerNames = @()

#---------------------------------------------------------[Test connectivity for each Servers]-------------------------------------------------------
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

#---------------------------------------------------------[HTML content]-------------------------------------------------------
$HTML = @"
<title>Service Account Script</title>
<style>
    body {background-color:#FFFFF}
    table {Border-width:thin;border-style:solid;border-color:Black;border-collapse:collapse;}
    th {border-width:1px;padding:2px;border-style:solid;border-color:black;background-color:ThreeDShadow;color:white}
    td {border-width:1px;padding:2px;border-style:solid;border-color:black;background-color:Transparent}
</style>
"@

#---------------------------------------------------------[Define the report file path]-------------------------------------------------------
$Report = "C:\temp\report.html"
Clear-Content -Path "$Report"


#---------------------------------------------------------[Loop through each computer]-------------------------------------------------------
Write-Host 'Generating Report...'
ForEach ($SRV in $OnlineComputerNames) {
    Get-WmiObject -ComputerName $SRV -Class Win32_Service -ErrorAction SilentlyContinue | Where-Object {
        $_.StartName -notin @("LocalSystem", "NT AUTHORITY\NetworkService", "NT AUTHORITY\Network Service", "NT AUTHORITY\LocalService", "NT AUTHORITY\Local Service", $null)
    } if($_)|Sort | Select-Object -Property StartName, Name, DisplayName | ConvertTo-Html -Property StartName, Name, DisplayName -Head $HTML -Body "<H2>$SRV</H2>" | Out-File -Append -FilePath $Report
}

#---------------------------------------------------------[Open the report]-------------------------------------------------------
Invoke-Item $Report
Write-Host @("Report Generated. location $Report")