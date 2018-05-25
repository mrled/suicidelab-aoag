# SuicideLab-AOAG

A definition for a Hyper-V lab environment for configuring SQL Server AlwaysOn Availability Groups,
built with Lability.

## Deploying the lab

Before my first deployment, I had to do:

    Install-LabModule -Scope AllUsers -ConfigurationData AOAGLAB.ConfigData.psd1 -ModuleType DscResource

But that appears to have a bug in it -
it installs the modules to `.\Program Files\WindowsPowerShell\Modules`.
The help for that command indicates it should be installing to the machine PS modules directory under `$env:SystemDrive`,
so we have to move all those modules to the system dir after installing them.
Make sure to install them to a versioned folder like `Program Files\WindowsPowerShell\Modules\<ModuleName>\<Version>` -
don't just copy the contents to `Program Files\WindowsPowerShell\Modules\<ModuleName>` !!

Once that has been done once on a workstation, it should not be necessary to do it again.

Thereafter, you have to simply run the lab script:

    .\Deploy-AOAGLAB.ps1

### WARNING: The EDGE1 server and network adapters

The EDGE1 server is the gateway for the private network.
As such, it needs two NICs -
one on the private network,
and one on an "external" Hyper-V switch.

This is defined in the configuration data like this:

    Lability_SwitchName          = @('Wifi-HyperV-VSwitch', 'AOAGLAB-CORPNET')

However, the order of those switches is not deterministic :/.

This means that you will need to ensure that the EDGE1 server NICs come up in the correct order.
You can see this in the Hyper-V manager app,
by selecting the VM and then clicking on the Networking tab.
Ensure that the adapter attached to your external VSwitch has an external VSwitch IP address,
while the adapter attached to the private VSwitch has the address assigned in the config data.

See also:
<https://github.com/VirtualEngine/Lability/issues/176>

### Startup time

On my laptop with 4 cores and 32GB of RAM:

 -  The domain controller comes up in about 15 minutes

## Debugging tips

Sometimes the VMs just don't come up.
Here are some things to try:

1.  For looking at the errors on your Lability host,
    I use the included Show-ErrorReport script.

     -  You can just run the script as is and it will show all the errors

            .\Show-ErrorReport.ps1

     -  You can also filter the error list and pass the filtered list to the script.
        I tend to call it like this, to filter out some expected errors:

            .\Show-ErrorReport.ps1 -ErrorList $($Error |? {
                $_ -NotMatch 'CustomMedia.json' -and
                $_ -NotMatch 'HKLM:\\SOFTWARE\\Microsoft\\PowerShell\\3\\DSC'})
            | less.exe

2.  If it's sitting at the "Hyper-V" boot screen with a spinner for a long time
    (5+ minutes for simple examples, longer for more complex networks),
    hard-reset the VM and see if it comes up

3.  Check the log in C:\Bootstrap

4.  Check the DSC logs in Event Viewer

5.  I have had problems with AutomaticCheckpointEnabled; see
    <https://github.com/VirtualEngine/Lability/issues/294>

Finally, some links that might be helpful:

    -  A good general Lability guide -
    Lability doesn't have great documentation on its own,
    but links to this and other guides in its readme.
    <https://blog.kilasuit.org/2016/04/13/building-a-lab-using-hyper-v-and-lability-the-end-to-end-example/>

    -  Notes on how DSC resources are added to Lability VMs
    <https://github.com/VirtualEngine/Lability/issues/172>

## TODO

1.  I want to enable Windows Event Forwarding.
    I will use the domain controller as the collector
    (because it comes up first).

     -  [Configure Computers to Forward and Collect Events](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/cc748890(v=ws.11))
     -  [Create a new subscription](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/cc722010%28v%3dws.10%29)
     -  [Event Subscriptions](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/cc749183(v=ws.11))
     -  [Windows Event Collector](https://msdn.microsoft.com/en-us/library/bb427443(v=vs.85).aspx)
     -  [Setting up a Source Initiated Subscription](https://msdn.microsoft.com/en-us/library/bb870973(v=vs.85).aspx)
     -  [Creating a Collector Initiated Subscription](https://msdn.microsoft.com/en-us/library/bb513652(v=vs.85).aspx)
     -  [Use Windows Event Forwarding to help with intrusion detection](https://docs.microsoft.com/en-us/windows/security/threat-protection/use-windows-event-forwarding-to-assist-in-intrusion-detection)
     -  [Wecutil.exe](https://msdn.microsoft.com/en-us/library/windows/desktop/bb736545(v=vs.85).aspx)
     -  [Monitoring what matters – Windows Event Forwarding for everyone (even if you already have a SIEM.)](https://blogs.technet.microsoft.com/jepayne/2015/11/23/monitoring-what-matters-windows-event-forwarding-for-everyone-even-if-you-already-have-a-siem/)
     -  [DIY Client Monitoring – Setting up Tiered Event Forwarding](https://blogs.msdn.microsoft.com/canberrapfe/2015/09/21/diy-client-monitoring-setting-up-tiered-event-forwarding/)
     -  [The Windows Event Forwarding Survival Guide](https://hackernoon.com/the-windows-event-forwarding-survival-guide-2010db7a68c4)
     -  [Loggly - Logging - The Ultimate Guide - Centralizing Windows Logs](https://www.loggly.com/ultimate-guide/centralizing-windows-logs/)
     -  [Powershell/xWindowsEventForwarding](https://github.com/PowerShell/xWindowsEventForwarding)
     -  [nsacyber/Event-Forwarding-Guidance](https://github.com/nsacyber/Event-Forwarding-Guidance/tree/master/Subscriptions/samples)
     -  [palantir/windows-event-forwarding](https://github.com/palantir/windows-event-forwarding)

