# qudong - CIODIY driver mirror repository

GitHub: https://github.com/yanbai9188-oss/qudong

## Structure

```
qudong/
  manifest.json          # same as driver_packages.json (schema v3)
  driver_packages.json   # fallback raw manifest
  packages/              # ZIP files for GitHub Release v1.0.0
  Drivers/               # optional: expanded INF folders (LFS or Release)
```

## Publish Release v1.0.0

1. Create repo `yanbai9188-oss/qudong` on GitHub (public recommended)
2. Copy `driver_packages.json` to repo root as `manifest.json`
3. Run locally:

```powershell
cd "驱动检测安装"
.\scripts\Populate-DriversLibrary.ps1
.\qudong-repo\Build-ReleasePackages.ps1
```

4. Upload `qudong-repo\packages\*.zip` to GitHub Release `v1.0.0`
5. Update SHA256 in manifest after upload (Build script prints hashes)

## Local offline use

After `Populate-DriversLibrary.ps1`, use **Install local library** in Driver Booster
or copy entire project folder to USB for post-reinstall offline install.
