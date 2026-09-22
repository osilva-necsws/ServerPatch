# 7-Zip Update via Pipeline

## Overview

This automated process updates or installs 7-Zip on Windows servers. It is designed to ensure a consistent version of 7-Zip across the environment, which is required by various other automation scripts (such as Apache proxy configuration and package creation) for extracting archive files.

## Process Flow

The 7-Zip update process performs the following steps:
1. **Detection**: Checks common installation paths (`C:\Program Files\7-Zip\` or `C:\Program Files (x86)\7-Zip\`) for an existing installation and identifies the current version.
2. **Process Cleanup**: Checks for and forcefully closes any running 7-Zip processes (File Manager or Command Line) to prevent file locks during the upgrade.
3. **Download**: Retrieves the specified 7-Zip installer executable from Artifactory.
3. **Silent Installation**: Runs the installer using the `/S` (silent) switch. This works for both fresh installations and upgrades.
4. **Verification**: Confirms the installation was successful by verifying the `7z.exe` executable exists in the expected location and recording the new version number.
5. **Reporting**: Generates an artifact and includes the update status in the final pipeline execution report.

## Configuration

### GitLab CI/CD Variables (`.gitlab-ci.yml`)

The following variable controls the version of 7-Zip deployed:

| Variable | Default Value | Description |
| :--- | :--- | :--- |
| `cpu_Patch7Zip` | `https://artifactory.cyp.caci.co.uk:8051/artifactory/softwareRepo/tools-generic-local/7zip/latest/7z-x64.exe` | Artifactory URL for the 7-Zip installer (direct download link) |

## How to Run the Update

1. **Access GitLab**: Navigate to the **CPUTomcat** project.
2. **Start Pipeline**: Go to **Build** -> **Pipelines** and click **Run pipeline**.
3. **Select Action**: Choose `Patch 7-Zip` from the `ACTION` dropdown menu.
4. **Target Servers**: Enter the `SERVER_GROUP_TAG` (e.g., `cyp-gen-windows`) to target specific runners.
5. **Execute**: Click **Run pipeline**.

## Verified Versions

The pipeline has been tested and verified with the following versions:
- **Installer**: `7z-x64.exe` (x64 version)
- **Verified Upgrade**: Upgrading from version `26.01` to `26.02`.

## Troubleshooting

- **Download Failures**: Ensure the `cpu_Patch7Zip` URL is accessible from the target server and that the filename on Artifactory matches the URL exactly.
- **Installer Failures**: Check the job logs in GitLab. The script captures the installer's exit code.
- **Path Issues**: The script expects 7-Zip to be installed in standard Program Files directories. If a non-standard path is used, the verification step might report a failure even if the installation succeeded.
