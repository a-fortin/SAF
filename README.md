# SAF - Service Account Finder

This PowerShell script fetch servers on Active Directory and remotely check service and scheduled task for any uncommon accounts. The goal of this script is to make a html report to help system administrators to find any  where service accounts are use in their Windows server infrastructure.

## Disclaimer 
This script is provided as-is without any warranties. Use it at your own risk.

## Prerequisites
- PowerShell execution policy allows running scripts
- Run PowerShell with administrative privileges
- Domain Administrator access
- RSAT: Active Directory Domain Services and Lightweight Directory Services Tools
- Active Directory Web Services (ADWS) access to servers
- Windows Remote Management (WinRM) access to servers

## Script workflow

```mermaid
graph TD
A[Check Privilege] --> B[Check AD RSAT]
B[Check AD RSAT] --> C[Install if not present]
B --> D[Check ADWS to DC]
C --> D
D --> E[Retrive servers]
D --> F[if unreachable, close script]
E --> G[Check servers connection]
I --> H[Query online servers services]
G --> I[Create and clear report]
I --> K{Report}
H --> J[Query online servers tasks]
J ---> N[Loop]
N ---> H
H ---> L[If exist, add to report]
J ---> L
L --> K
N --> O[When done, invoke report]
O --> K
```