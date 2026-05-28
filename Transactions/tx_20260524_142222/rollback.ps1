# Auto-generated rollback script for tx_20260524_142222
$ErrorActionPreference = 'Stop'
$AppRoot = 'C:\Users\admin\Desktop\驱动检测安装'
. (Join-Path $AppRoot 'engine\Initialize-Engine.ps1')
Invoke-DriverRollback -TxId 'tx_20260524_142222'
