# SuicideLabs-AOAG

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

### Startup time

On my laptop with 4 cores and 32GB of RAM:

 -  The domain controller comes up in about 15 minutes

### Redeploying

 -  Delete the VMs in Hyper-V manager

 -  You may also need to delete the VHDX files;
    you can do so with this command:

        do { rm C:\Lability\VMVirtualHardDisks\AOAGLAB-* -ErrorAction SilentlyContinue -Force; sleep 2} while (ls C:\Lability\VMVirtualHardDisks\AOAGLAB-*)

 -  Then just redeploy as above

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