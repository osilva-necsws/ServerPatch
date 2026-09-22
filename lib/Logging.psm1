Function LogWrite
{
  [CmdletBinding( )]
   Param (
     [string]$logstring,
     [Parameter()]
     [switch]$loginfo,
     [Parameter()]
     [switch]$logwarn,
     [Parameter()]
     [switch]$logfail,
     [Parameter()]
     [switch]$logout,
     [string]$logfile = "install_$(get-date -f dd-MM-yyyy).log",
     [string]$errid = "OK"
   )

   $log_file_full=$log_path.ToString() + "\" + $logfile

   if ($errid -ne "OK") {
        $logstring = LogWrite_error $errid
        $logfail = $true
    }
   $caller = $MyInvocation.PSCommandPath | Split-Path -leaf
   $addcontent = $(get-date -f HH:mm:ss) + '[' + $caller + '] : ' + $logstring.ToString()
   $showcontent = $(get-date -f HH:mm:ss) + ' : ' + $logstring.ToString()
   Add-content $log_file_full -value $addcontent
   $outcolour="Green"
   if ($loginfo) {$outcolour="White"}
   if ($logwarn) {$outcolour="Yellow"}
   if ($logfail) {$outcolour="Red"}
   if ($debug -or $logout) {write-host -f $outcolour $showcontent}
}

Export-ModuleMember -Function LogWrite

Function LogWrite_error
{
  Param (
     [string]$errid
  )
  switch ($errid) {
    "abend" {$error_text = "Fatal error has occurred, Please contact CACI"}
    default {$error_text =  "Unhandled Error Number $errid"}
  }
  return $error_text
}

Export-ModuleMember -Function LogWrite_error