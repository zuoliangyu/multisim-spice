# Locate multisim.exe (newest version first) and print its path; with -Open, also launch it on a netlist.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File find-multisim.ps1 [-Open <netlist.cir>]
# Exit 1 if Multisim is not found.

param([string]$Open)

$exe = $null

# 1) Registry: <version>\MSI Parts\Core\Path holds the install dir
foreach ($rk in "HKLM:\SOFTWARE\WOW6432Node\National Instruments\Circuit Design Suite",
                "HKLM:\SOFTWARE\National Instruments\Circuit Design Suite") {
  foreach ($v in Get-ChildItem $rk -ErrorAction SilentlyContinue | Sort-Object PSChildName -Descending) {
    $core = Get-ItemProperty (Join-Path $v.PSPath "MSI Parts\Core") -ErrorAction SilentlyContinue
    if ($core.Path -and (Test-Path (Join-Path $core.Path "multisim.exe"))) {
      $exe = Join-Path $core.Path "multisim.exe"
      break
    }
  }
  if ($exe) { break }
}

# 2) Wildcard scan of Program Files on every local drive
if (-not $exe) {
  $exe = Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    foreach ($pf in "Program Files (x86)", "Program Files") {
      Get-ChildItem (Join-Path $_.Root "$pf\National Instruments\Circuit Design Suite *\multisim.exe") -ErrorAction SilentlyContinue
    }
  } | Sort-Object { $_.Directory.Name } -Descending | Select-Object -First 1 -ExpandProperty FullName
}

if (-not $exe) {
  Write-Error "multisim.exe not found"
  exit 1
}
$exe
if ($Open) {
  $cir = (Resolve-Path $Open -ErrorAction Stop).Path
  Start-Process -FilePath $exe -ArgumentList "`"$cir`""
}
exit 0
