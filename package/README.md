# Package Folder #

## Expected content ##
```powershell
    Directory: C:\gitroot\deployment-dev\package


Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a----        27/06/2024     14:39       14100870 apache-tomcat-9.0.90.zip                       # Apache Tomcat - For Webtier tomcat upgrades
-a----        01/02/2023     10:03        5846332 FileHandler.war                                # FileHandler War file for deployment into tomcat.
-a----        27/06/2024     14:25      120824511 jdk1.8.0_412.zip                               # Latest Anmazon corretto JDK pack
-a----        29/11/2023     16:30       81560356 ODAC19.20Xcopy_x86.zip                         # Oracle ODAC drivers
-a----        27/06/2024     14:15      349701060 postgresql-14.12-2-windows-x64-binaries.zip    # PostgreSQL installation pack
-a----        27/06/2024     15:05            990 README.md                                      # This Readme
-a----        27/06/2024     12:57     4502503095 WINDOWS.X64_192300_db_home.zip                 # Upgraded Oracle home (Minus DBCA templates)
```

## Tomcat pack ##
Pack details file : [pack_tomcat.xml](pack_tomcat.xml)  
Grab the latest zip file - Usually named __64-bit Windows zip__ (Not windows MSI file)  
Remove all but bin and lib folders, and the files in the root directory (Read-mes and Release notices).  
> :warning: Add ojdbc8.jar file into the lib folder for Oracle support.

All packs are compressed in the folder to maintain the right folder structure.

```powershell
cd apache-tomcat-9.0.90
"c:\Program Files\7-zip\7z.exe" a -r "../apache-tomcat-9.0.90.zip" *
Get-FileHash -Algorithm md5 ../apache-tomcat-9.0.90.zip
```

## Oracle home pack ##
Pack details file : [pack_oracle_dbhome.xml](pack_oracle_dbhome.xml)  
- Build an Oracle 19.3.0 home, rename it to the vversion number and install it.
- Replace the OPatch folder with the latest patch set from Oracle
- Apply the database and OVMJ patches to the 19.x.x home
- Remove the DBCA templates content to reduce the size a little.

```powershell
cd ../product/19.23.0/dbhome_1
"c:\Program Files\7-zip\7z.exe" a -r "../WINDOWS.X64_192300_db_home.zip" *
Get-FileHash -Algorithm md5 ../WINDOWS.X64_192300_db_home.zip
```
## Amazon Corretto JDK 8 ##
Pack details file : [pack_jdk8.xml](pack_jdk8.xml)  
Use the following Powershell script to download the 3 JDK's
The automation only currently handles the JDK 8 installation.

```powershell
Invoke-WebRequest -Uri "https://corretto.aws/downloads/latest/amazon-corretto-17-x64-windows-jdk.zip" -OutFile "JDK17.zip"
Invoke-WebRequest -Uri "https://corretto.aws/downloads/latest/amazon-corretto-11-x64-windows-jdk.zip" -OutFile "JDK11.zip"
Invoke-WebRequest -Uri "https://corretto.aws/downloads/latest/amazon-corretto-8-x64-windows-jdk.zip" -OutFile "JDK8.zip"
```  

## PostgreSQL Package ##
Pack details file : [pack_postgres_home.xml](pack_postgres_home.xml)  
DOwnload the package from [Postgres Binaries only source](https://www.enterprisedb.com/download-postgresql-binaries)  
