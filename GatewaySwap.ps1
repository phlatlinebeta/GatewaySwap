##########################################
# Default Gateway Changer
# Version 1.0
# Written by github.com/phlatlinebeta
##########################################
# How to Use:
# First change the global variables below
# Run the script as an admin. The script will try once to ping $PingTest, if it fails to ping
# that address then it will change the default gateway address on all computers that have a 
# DHCP leases and a computer object in AD. The script will also change the Default gateway on
# the host computer running the script and change the router (option 003) on your DHCP server
# scope settings.
# I suggest setting the script to run as a scheduled task every 10 minutes.
# PS. This script needs to run as ADMIN to apply changes to DHCP Scope settings
##########################################
#Global Variables that you need to change
$DHCPServer = "MyDHCPServer"  # Name of your DHCP Server
$DHCPScopeID = "192.168.1.0"  # Name of your DHCP Scope
$BackupDefaultGateway = "192.168.1.2"
$StaticServers = @("Server1","Server2","PrintServer1")  # Use this to add static IP addresses (windows) that you also want their gateway changed, example "Server1,"Server2","Server3"
$MyIPSubnet = "192.168.1."  # This is needed to find which NIC has an assigned Default Gateway
$PingTest = "8.8.8.8"  # What you will ping to check your internet connection (8.8.8.8 is google's DNS server)
$EmailTo = "helpdesk@mycompany.com"  # What email address you want alerted
$EmailFrom = "madeupgmailaccount@gmail.com"  # email settings
$SMTPServer = "smtp.gmail.com"  # email settings
$SMTPPort = 587  # email settings
$SMTPUsername = "madeupgmailaccount@gmail.com"  # email settings
$SMTPPassword = "PASSWORD4madeupgmailaccount"  # email settings
##########################################



Function ListADComputerDHCPLeases()
{
# Function Instruction: This function will generate a list of DHCP leases that have a matching Computer Object in Active Directory
# this function returns an array of those computers -jml2016
# Example usage: $MyArray = ListADComputerDHCPLeases

    #$DHCPServer = ""  #Declared this globally instead of inside the function
    #$DHCPScopeID = ""  #Declared this globally instead of inside the function
    
    # Load the Microsoft Active Directory Module
    Import-Module ActiveDirectory
    #Get a list of all DHCP leases(fully qualified domain names)
    $DHCPComputers = Get-DhcpServerv4Lease -Computername $DHCPServer -ScopeId $DHCPScopeID | ForEach-Object {$_.HostName}
    # Get a list of all computer names(fully qualified domain names)
    $ADComputers = Get-ADComputer -Filter * | ForEach-Object {$_.DNSHostName}
    # $myarray will be used to load all computers that are both in AD and have DHCP leases
    $myarray = @()
    # Parse all the DHCP computers and check each one against the computers found in AD
    ForEach ($value in $DHCPComputers)
    {
        if ($value.length -ne 0)  # skip DHCP leases that have no DNS name
        {
            if ($ADComputers -contains $value)
            {
                #Write-Host "$value is found in AD"
                $myarray+=$value
            }
            else
            {
                #Write-Host "$value not found in AD " $value.length -BackgroundColor DarkMagenta
            }
        }
    }
    return $myarray
}

Function ChangeDefaultGateway ($NewDefaultGateway, $ComputerName)
{
    #Function Instructions: This fucntion will change the default gateway on computer $ComputerName to $NewDefaultGateway
    #function requires variable $MyIPSubnet to be defined as "XXX.XXX.XXX."

    
    #$MyIPSubnet = ""  #Declared this globally instead of inside the function
    $Returnvalue=""  #Used to return what NIC/IP had their gateway changed from what to what
    $NICs = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -ComputerName "$ComputerName" -Filter “IPEnabled=TRUE”
    foreach($NIC in $NICs) 
    {
        if($NIC.DefaultIPGateway -match $MyIPSubnet) # fetch the NIC that already has a gateway address
        {
            $Returnvalue = "Changing Gateway for " + $ComputerName + " on " + $NIC.IPAddress[0] + " " + $NIC.Description + " from " + $NIC.DefaultIPGateway[0] + " to " + $NewDefaultGateway + "`r`r"
            write-host $Returnvalue -BackgroundColor DarkCyan #DEBUG
            $null = $NIC.SetGateways($NewDefaultGateway)  # Changes the gateway on $NIC 
        }
    }
    return $Returnvalue 
}

Function PingIt ($Server)
{
    #Funciton Instructions: Pings Server, returns 0 if ping fails, 1 if pings succeeds

    if(!(Test-Connection -Cn $Server -Count 1 -quiet))
    {
        return 0
    }
    ELSE
    {
        return 1
    }
}

Function SendEmail($EmailSubject, $EmailBody, $EmailAttachment)
{
    #Function Instructions: Sends an email using variables declared at the top of the script
    # Functions needs to be passed $EmailSubject and $EmailBody, $EmailAttachment is optional

    $SMTPMessage = New-Object System.Net.Mail.MailMessage($EmailFrom,$EmailTo,$EmailSubject,$EmailBody)
    if (!($EmailAttachment -eq $NULL))
    { 
        $attachment = New-Object System.Net.Mail.Attachment($EmailAttachment)
        $SMTPMessage.Attachments.Add($EmailAttachment)
    }
    $SMTPClient = New-Object Net.Mail.SmtpClient($SmtpServer, $SMTPPort) 
    $SMTPClient.EnableSsl = $true 
    $SMTPClient.Credentials = New-Object System.Net.NetworkCredential($SMTPUsername, $SMTPPassword); 
    $SMTPClient.Send($SMTPMessage)
}



##########################################
# Main
##########################################
If (PingIT $PingTest)
{
    #Ping Success - Internet Working
    Write-Host "Connection working"
    
}
Else
{
    #Ping Fail - Internet Offline - Switch Gateways/ISPs
    CLS
    Write-Host "Internet Connection offline. Changing Gateways...(this may take a min)" -BackgroundColor Red -ForegroundColor Black
    $Results = @()
    $ThisComputerName = $env:computername
    $Results += ChangeDefaultGateway $BackupDefaultGateway $ThisComputerName  #Change default gateway on host server running this script
    
    # \/ Change the DHCP Server's Scope Option to use the new default gateway as option 003 Router \/
    Set-DhcpServerv4OptionValue -ComputerName $DHCPServer -ScopeId $DHCPScopeID -Router $BackupDefaultGateway
    $Results += "Changed option 003 Router on DHCP Server:" + $DHCPServer + " ScopeID:" + $DHCPScopeID + " to " + $BackupDefaultGateway + "`r`r"

    $Computers = ListADComputerDHCPLeases  #Fills array with all DHCP leases that are computer objects in AD
    ForEach ($value in $StaticServers)
    {
        $Results += ChangeDefaultGateway $BackupDefaultGateway $value  # Change each static server's default gateway
    }
    ForEach ($value in $Computers)
    {
        $Results += ChangeDefaultGateway $BackupDefaultGateway $value   #Change each computer's default gateway
    }
    SendEmail "Error:Internet Outage" $Results

}



