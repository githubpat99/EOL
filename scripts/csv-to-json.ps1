$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$csvPath = Join-Path $root 'demografie_teamleiter.csv'
$jsonPath = Join-Path $root 'demografie.json'
$years = 2026..2036

$rows = @(Import-Csv -Path $csvPath -Delimiter ';' -Encoding UTF8)
if ($rows.Count -eq 0) { throw 'Die CSV enthält keine Datenzeilen.' }

$employees = [ordered]@{}
$seen = @{}
foreach ($row in $rows) {
    $fachgebiet = ([string]$row.Fachgebiet).Trim()
    $team = ([string]$row.Team).Trim()
    $name = ([string]$row.Name).Trim()
    if (-not $fachgebiet -or -not $team -or -not $name) {
        throw 'Fachgebiet, Team und Name dürfen nicht leer sein.'
    }

    $key = "$team|$name|$fachgebiet"
    if ($seen.ContainsKey($key)) { throw "Doppelte Zeile: $key" }
    $seen[$key] = $true

    $jahre = [ordered]@{}
    foreach ($year in $years) {
        $raw = ([string]$row.$year).Trim()
        $value = 0.0
        if ($raw -and -not [double]::TryParse($raw.Replace(',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
            throw "Ungültiger Wert für $key / $year`: $raw"
        }
        if ($value -lt 0 -or $value -gt 1) { throw "Wert außerhalb 0-1 für $key / $year`: $value" }
        $jahre[[string]$year] = $value
    }

    if (-not $employees.Contains($team + '|' + $name)) {
        $employees[$team + '|' + $name] = [ordered]@{ name = $name; team = $team; fachgebiete = [Collections.Generic.List[object]]::new() }
    }
    $employees[$team + '|' + $name].fachgebiete.Add([ordered]@{ name = $fachgebiet; jahre = $jahre })
}

$json = @($employees.Values) | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($jsonPath, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
Write-Host "demografie.json erzeugt: $($rows.Count) Fachgebietszeilen, $($employees.Count) Mitarbeitende"
