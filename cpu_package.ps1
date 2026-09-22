param (
   [string]$packname="Noname"
)

$basedir = Resolve-Path -Path "$PSScriptRoot"
# Add 7Zip command if executable exists - used for Jar pom.xml file extraction.
$7zExe = "$basedir\lib\7za.exe"
if (test-path $7zExe){
    set-alias 7zextract $7zExe
    $7zAvail=$true
} else {
    $7zAvail=$false
}



& $7zExe a -r "$($packname)_nopacks.zip" lib logs resource tools *.bat about.txt

& $7zExe a -r "$($packname)_packs.zip" lib logs package resource tools *.bat about.txt
