# Run the bundled ngspice in batch mode on a netlist and flag known failure patterns.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File check.ps1 <netlist.cir> ["<cmd>; <cmd>; ..."]
#   The optional second argument holds ngspice control commands separated by ';',
#   e.g. "meas ac f3db when vdb(out)=-3; meas ac g1k find vdb(out) at=1k".
#   Unless the netlist has its own .control block, a temporary copy is simulated with
#   ".control / run / <cmds> / .endc" inserted before .end; the netlist itself is never modified.
# Prints the full ngspice output; last line is CHECK: PASS or CHECK: FAIL (exit 0 / 1).

param(
  [Parameter(Mandatory = $true)][string]$Netlist,
  [string]$Commands = ""
)

$ng = Join-Path $PSScriptRoot "..\vendor\Spice64\bin\ngspice_con.exe"
$src = (Resolve-Path $Netlist -ErrorAction Stop).Path
$text = [IO.File]::ReadAllText($src)
$cmds = @($Commands -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# Batch mode prints .op results by itself, but refuses .tran/.ac/.dc without .print lines,
# so wrap the analysis in a control block unless the netlist brings its own.
$isOpOnly = ($text -match '(?im)^\s*\.op\b') -and ($text -notmatch '(?im)^\s*\.(tran|ac|dc|noise|tf|pz)\b')
$inject = ($text -notmatch '(?im)^\s*\.control\b') -and ($cmds.Count -gt 0 -or -not $isOpOnly)

$run = $src
if ($inject) {
  $block = (@(".control", "run") + $cmds + @(".endc")) -join "`r`n"
  if ($text -match '(?im)^\s*\.end\s*$') {
    $text = [regex]::Replace($text, '(?im)^\s*\.end\s*$', ($block + "`r`n.end"))
  } else {
    $text = $text.TrimEnd() + "`r`n" + $block + "`r`n.end`r`n"
  }
  $run = Join-Path (Split-Path $src) (".check_" + [IO.Path]::GetFileName($src))
  [IO.File]::WriteAllText($run, $text, (New-Object Text.UTF8Encoding $false))
}

try {
  $out = & $ng -b $run 2>&1 | ForEach-Object { "$_" }
  $code = $LASTEXITCODE
} finally {
  if ($inject) { Remove-Item $run -ErrorAction SilentlyContinue }
}
$out

# ngspice can exit 0 after a singular-matrix fallback, so the exit code alone is not enough
$bad = 'error|singular matrix|can''t find|can''t parse|unknown|no convergence|timestep too small|aborted|stepping failed|\bnan\b|\binf\b'
$hits = $out | Select-String -Pattern $bad
if ($code -ne 0 -or $hits) {
  ""
  "----- problems (ngspice exit code $code) -----"
  $hits | ForEach-Object { $_.Line.Trim() }
  "CHECK: FAIL"
  exit 1
}
if ($inject -and $cmds.Count -eq 0) { "NOTE: simulation ran, but no measurement commands were given; specs are not verified" }
if (-not $inject -and $cmds.Count -gt 0) { "NOTE: netlist has its own .control block; the commands argument was ignored" }
"CHECK: PASS"
exit 0
