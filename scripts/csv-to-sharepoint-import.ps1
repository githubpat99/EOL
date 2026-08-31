$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'demografie_teamleiter.csv'
$targetPath = Join-Path $root 'demografie_powerapps_import.csv'
$years = 2026..2036

$sourceRows = @(Import-Csv -Path $sourcePath -Delimiter ';' -Encoding UTF8)
if ($sourceRows.Count -eq 0) { throw 'Die CSV enthält keine Datenzeilen.' }

$importRows = foreach ($row in $sourceRows) {
    $fachgebiet = ([string]$row.Fachgebiet).Trim()
    $team = ([string]$row.Team).Trim()
    $mitarbeiter = ([string]$row.Name).Trim()
    if (-not $fachgebiet -or -not $team -or -not $mitarbeiter) {
        throw 'Fachgebiet, Team und Name dürfen nicht leer sein.'
    }

    foreach ($year in $years) {
        $rawValue = ([string]$row.$year).Trim()
        $pensum = 0.0
        if ($rawValue -and -not [double]::TryParse($rawValue.Replace(',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$pensum)) {
            throw "Ungültiger Wert für $team / $mitarbeiter / $fachgebiet / $year`: $rawValue"
        }
        if ($pensum -lt 0 -or $pensum -gt 1) {
            throw "Pensum außerhalb 0-1 für $team / $mitarbeiter / $fachgebiet / $year`: $pensum"
        }

        [pscustomobject][ordered]@{
            Titel = "$team | $mitarbeiter | $fachgebiet | $year"
            Team = $team
            Mitarbeiter = $mitarbeiter
            Fachgebiet = $fachgebiet
            Planjahr = $year
            Pensum = $pensum.ToString('0.####', [Globalization.CultureInfo]::InvariantCulture)
        }
    }
}

$importRows | Export-Csv -Path $targetPath -Delimiter ';' -NoTypeInformation -Encoding UTF8
Write-Host "SharePoint-Importdatei erzeugt: $($importRows.Count) Datensätze"
