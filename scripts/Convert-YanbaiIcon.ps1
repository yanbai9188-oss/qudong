#requires -Version 5.1
# Create multi-size ICO for Inno Setup / Windows shell
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$png = Join-Path $root 'ui\yanbai_icon.png'
$ico = Join-Path $root 'ui\yanbai.ico'

if (-not (Test-Path $png)) { throw "Missing PNG: $png" }

Add-Type -AssemblyName System.Drawing

function New-SquareBitmap {
    param([System.Drawing.Bitmap]$Source, [int]$Size)
    $bmp = New-Object System.Drawing.Bitmap $Size, $Size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.DrawImage($Source, 0, 0, $Size, $Size)
    } finally {
        $g.Dispose()
    }
    return $bmp
}

$src = [System.Drawing.Bitmap]::FromFile($png)
try {
    $sizes = @(256, 48, 32, 16)
    $mem = New-Object System.IO.MemoryStream
    try {
        $writer = New-Object System.IO.BinaryWriter $mem
        $writer.Write([UInt16]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]$sizes.Count)

        $imageData = New-Object System.Collections.Generic.List[byte[]]
        foreach ($s in $sizes) {
            $bmp = New-SquareBitmap -Source $src -Size $s
            try {
                $ms = New-Object System.IO.MemoryStream
                try {
                    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                    $bytes = $ms.ToArray()
                } finally {
                    $ms.Dispose()
                    $bmp.Dispose()
                }
                $imageData.Add($bytes) | Out-Null
            } catch {
                $bmp.Dispose()
                throw
            }
        }

        $offset = 6 + (16 * $sizes.Count)
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $s = $sizes[$i]
            $bytes = $imageData[$i]
            if ($s -ge 256) {
                $writer.Write([byte]0)
                $writer.Write([byte]0)
            } else {
                $writer.Write([byte]$s)
                $writer.Write([byte]$s)
            }
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]32)
            $writer.Write([UInt32]$bytes.Length)
            $writer.Write([UInt32]$offset)
            $offset += $bytes.Length
        }
        foreach ($bytes in $imageData) {
            $writer.Write($bytes)
        }
        $writer.Flush()
        [System.IO.File]::WriteAllBytes($ico, $mem.ToArray())
        Write-Host "Created valid ICO: $ico ($((Get-Item $ico).Length) bytes)"
    } finally {
        $mem.Dispose()
    }
} finally {
    $src.Dispose()
}
