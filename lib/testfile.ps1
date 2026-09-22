
$postgresconf = Get-Content "E:\CACI\DBTier\PostgreSQL\14.12\data\postgresql.conf"

$commented_listener= Select-String -InputObject $postgresconf -Pattern '^[#listen_addresses]*' -AllMatches
$listener= Select-String -InputObject $postgresconf -Pattern '^listen_addresses.*' -AllMatches
$listener.Matches.Count
# #listen_addresses = 'localhost'

$postgresconf -replace "#listen_addresses = 'localhost'", "listen_addresses = '*'" | Set-Content c:\caci\test.txt

# (\W|^)stock\stips(\W|$)
