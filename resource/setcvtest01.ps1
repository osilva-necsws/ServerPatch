$mypath = "D:\CACI\DBTier"
$myacl = Get-Acl $mypath
$myaclentry = "NT SERVICE\OracleServiceCVTEST01","FullControl","Allow"
$myaccessrule = New-Object System.Security.AccessControl.FileSystemAccessRule($myaclentry)
$myacl.SetAccessRule($myaccessrule)
Get-ChildItem -Path "$mypath" -Recurse -Force | Set-Acl -AclObject $myacl -Verbose