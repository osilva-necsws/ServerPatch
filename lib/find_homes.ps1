function find_webtier($webtier_home)
{
    write-host -f green -Nonewline 'Locating Childview WebTier : '
    $Install_path=(gwmi win32_service|?{$_.name -eq "CACI"}).pathname
    if ([string]::IsNullOrWhiteSpace($Install_path)) {
        write-host -f cyan 'Service Not found'
        $webtier_home = new_webtier_home
    } else {
        $webtier_home=$install_path.split("WebTier",2)[0] + 'WebTier'
        if ([string]::IsNullOrWhiteSpace($webtier_home)) {
            write-host -f darkcyan 'Directory Not found'
            write-host -f red 'Service installed but Unable to locate ChildView WebTier installation'
            write-host -f red 'Possible bespoke installation - Contact CACI for support'
            exit
        }
        write-host -f cyan 'Found'
     }
return $webtier_home
}
