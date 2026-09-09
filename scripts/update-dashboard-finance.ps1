param(
    [string]$SourceDirectory = (Join-Path $PSScriptRoot '..\..\Prognose'),
    [string]$OutputFile = (Join-Path $PSScriptRoot '..\dashboard_finance_data.json'),
    [string]$SnWorkbook,
    [string]$ZpWorkbook,
    [switch]$SelectFiles
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-WorksheetCellNumber {
    param(
        [Parameter(Mandatory)][string]$Workbook,
        [Parameter(Mandatory)][string]$WorksheetPath,
        [Parameter(Mandatory)][string]$Cell
    )

    $archive = [IO.Compression.ZipFile]::OpenRead($Workbook)
    try {
        $entry = $archive.GetEntry($WorksheetPath)
        if (-not $entry) { throw "Worksheet $WorksheetPath fehlt in $Workbook." }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { [xml]$worksheet = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $namespace = [Xml.XmlNamespaceManager]::new($worksheet.NameTable)
        $namespace.AddNamespace('x', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
        $node = $worksheet.SelectSingleNode("//x:c[@r='$Cell']/x:v", $namespace)
        if (-not $node) { throw "Zelle $Cell fehlt in $Workbook." }
        return [double]::Parse($node.InnerText, [Globalization.CultureInfo]::InvariantCulture)
    }
    finally {
        $archive.Dispose()
    }
}

function Get-WorksheetCellText {
    param(
        [Parameter(Mandatory)][string]$Workbook,
        [Parameter(Mandatory)][string]$WorksheetPath,
        [Parameter(Mandatory)][string]$Cell
    )

    $archive = [IO.Compression.ZipFile]::OpenRead($Workbook)
    try {
        $entry = $archive.GetEntry($WorksheetPath)
        if (-not $entry) { throw "Worksheet $WorksheetPath fehlt in $Workbook." }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { [xml]$worksheet = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $namespace = [Xml.XmlNamespaceManager]::new($worksheet.NameTable)
        $namespace.AddNamespace('x', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
        $cellNode = $worksheet.SelectSingleNode("//x:c[@r='$Cell']", $namespace)
        if (-not $cellNode) { throw "Zelle $Cell fehlt in $Workbook." }
        $valueNode = $cellNode.SelectSingleNode('./x:v', $namespace)
        if (-not $valueNode) { return '' }
        if ($cellNode.t -ne 's') { return $valueNode.InnerText }

        $stringsEntry = $archive.GetEntry('xl/sharedStrings.xml')
        if (-not $stringsEntry) { throw "Shared Strings fehlen in $Workbook." }
        $reader = [IO.StreamReader]::new($stringsEntry.Open())
        try { [xml]$strings = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $stringsNamespace = [Xml.XmlNamespaceManager]::new($strings.NameTable)
        $stringsNamespace.AddNamespace('x', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
        $items = $strings.SelectNodes('//x:si', $stringsNamespace)
        $item = $items[[int]$valueNode.InnerText]
        return (($item.SelectNodes('.//x:t', $stringsNamespace) | ForEach-Object { $_.InnerText }) -join '')
    }
    finally {
        $archive.Dispose()
    }
}

function Get-WorksheetPeriods {
    param(
        [Parameter(Mandatory)][string]$Workbook,
        [Parameter(Mandatory)][string]$WorksheetPath
    )

    $archive = [IO.Compression.ZipFile]::OpenRead($Workbook)
    try {
        $stringsEntry = $archive.GetEntry('xl/sharedStrings.xml')
        $reader = [IO.StreamReader]::new($stringsEntry.Open())
        try { [xml]$strings = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $stringsNamespace = [Xml.XmlNamespaceManager]::new($strings.NameTable)
        $stringsNamespace.AddNamespace('x', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
        $sharedStrings = @()
        foreach ($item in $strings.SelectNodes('//x:si', $stringsNamespace)) {
            $sharedStrings += (($item.SelectNodes('.//x:t', $stringsNamespace) | ForEach-Object { $_.InnerText }) -join '')
        }

        $entry = $archive.GetEntry($WorksheetPath)
        if (-not $entry) { throw "Worksheet $WorksheetPath fehlt in $Workbook." }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { [xml]$worksheet = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $namespace = [Xml.XmlNamespaceManager]::new($worksheet.NameTable)
        $namespace.AddNamespace('x', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
        $periods = @()
        foreach ($cellNode in $worksheet.SelectNodes('//x:sheetData/x:row/x:c[starts-with(@r,"A")]', $namespace)) {
            $valueNode = $cellNode.SelectSingleNode('./x:v', $namespace)
            if (-not $valueNode) { continue }
            $value = if ($cellNode.t -eq 's') { $sharedStrings[[int]$valueNode.InnerText] } else { $valueNode.InnerText }
            if ($value -match '^\d{4}-\d{2}$') { $periods += $value }
        }
        return @($periods | Sort-Object -Unique)
    }
    finally {
        $archive.Dispose()
    }
}

function Set-CustomerActualCost {
    param($Data, [string]$Customer, [double]$Value)
    $row = $Data.customers | Where-Object customer -like $Customer
    if (-not $row) { throw "Kunde '$Customer' fehlt in der Finanz-JSON." }
    $row.actual_cost = $Value
}

function Set-ProportionalPlanCosts {
    param($Data, [string]$Product, [long]$PlanTotal)
    $rows = @($Data.customers | Where-Object product -eq $Product)
    $actualTotal = ($rows | Measure-Object actual_cost -Sum).Sum
    if ($actualTotal -le 0) { throw "Keine Ist-Kosten für $Product vorhanden." }
    $allocated = 0L
    for ($index = 0; $index -lt $rows.Count; $index++) {
        $value = if ($index -eq $rows.Count - 1) {
            $PlanTotal - $allocated
        } else {
            [long][Math]::Round($PlanTotal * $rows[$index].actual_cost / $actualTotal)
        }
        $rows[$index].plan_cost = $value
        $allocated += $value
    }
}

function Select-CostWorkbook {
    param([string]$Title, [string]$InitialDirectory, [string]$ExpectedFileName)
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = [Windows.Forms.OpenFileDialog]::new()
    $dialog.Title = $Title
    $dialog.Filter = 'Excel-Arbeitsmappen (*.xlsm)|*.xlsm'
    $dialog.FileName = $ExpectedFileName
    if (Test-Path -LiteralPath $InitialDirectory) { $dialog.InitialDirectory = (Resolve-Path -LiteralPath $InitialDirectory).Path }
    try {
        if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw 'Dateiauswahl wurde abgebrochen.' }
        return $dialog.FileName
    }
    finally {
        $dialog.Dispose()
    }
}

if ($SelectFiles) {
    $SnWorkbook = Select-CostWorkbook 'SN-Kostensicht auswaehlen' $SourceDirectory 'SN_Kostensicht.xlsm'
    $ZpWorkbook = Select-CostWorkbook 'ZP-Kostensicht auswaehlen' (Split-Path -Parent $SnWorkbook) 'ZP_Kostensicht.xlsm'
}

if (-not $SnWorkbook) { $SnWorkbook = Join-Path $SourceDirectory 'SN_Kostensicht.xlsm' }
if (-not $ZpWorkbook) { $ZpWorkbook = Join-Path $SourceDirectory 'ZP_Kostensicht.xlsm' }
foreach ($workbook in @($snWorkbook, $zpWorkbook)) {
    if (-not (Test-Path -LiteralPath $workbook)) { throw "Quelldatei fehlt: $workbook" }
}

$data = Get-Content -LiteralPath $OutputFile -Raw -Encoding utf8 | ConvertFrom-Json
$sheet = 'xl/worksheets/sheet4.xml'
$periodValue = Get-WorksheetCellText $zpWorkbook $sheet 'B4'
$budgetYear = [int](Get-WorksheetCellNumber $zpWorkbook $sheet 'B3')
if ($periodValue -notmatch '^\s*1\s+bis\s+(\d{1,2})\s*$') {
    throw "Importierte Perioden '$periodValue' haben nicht das erwartete Format '1 bis n'."
}
$closedMonth = [int]$Matches[1]
if ($closedMonth -lt 1 -or $closedMonth -gt 12) { throw "Ungueltiger Abschlussmonat: $closedMonth" }
$monthlySheet = 'xl/worksheets/sheet5.xml'
$expectedPeriods = @(1..$closedMonth | ForEach-Object { '{0}-{1:00}' -f $budgetYear, $_ })
$snPeriods = @(Get-WorksheetPeriods $snWorkbook $monthlySheet)
$zpPeriods = @(Get-WorksheetPeriods $zpWorkbook $monthlySheet)
if (Compare-Object $expectedPeriods $snPeriods) {
    throw "SN-Perioden stimmen nicht mit dem erwarteten Stand 1 bis $closedMonth ueberein: $($snPeriods -join ', ')."
}
if (Compare-Object $expectedPeriods $zpPeriods) {
    throw "ZP-Perioden stimmen nicht mit dem erwarteten Stand 1 bis $closedMonth ueberein: $($zpPeriods -join ', ')."
}
$monthNames = @('Jan.', 'Feb.', ('M' + [char]0x00E4 + 'r.'), 'Apr.', 'Mai', 'Jun.', 'Jul.', 'Aug.', 'Sep.', 'Okt.', 'Nov.', 'Dez.')
$data.metadata.sap_period = 'Jan.' + [char]0x2013 + $monthNames[$closedMonth - 1] + " $budgetYear"
$data.metadata.budget_year = $budgetYear
Set-CustomerActualCost $data 'KStA SG' (Get-WorksheetCellNumber $snWorkbook $sheet 'D30')
Set-CustomerActualCost $data 'Cantone Ticino' (Get-WorksheetCellNumber $snWorkbook $sheet 'D31')
$snMunicipalities = (Get-WorksheetCellNumber $snWorkbook $sheet 'D32') + (Get-WorksheetCellNumber $snWorkbook $sheet 'D33')
Set-CustomerActualCost $data 'Gemeinden SN' $snMunicipalities
Set-CustomerActualCost $data 'KStA ZH*Steuern' (Get-WorksheetCellNumber $zpWorkbook $sheet 'D22')
Set-CustomerActualCost $data 'Gemeinden ZH' (Get-WorksheetCellNumber $zpWorkbook $sheet 'D23')

Set-ProportionalPlanCosts $data 'SN' ([long]$data.annual.SN.'2026'.full_cost)
Set-ProportionalPlanCosts $data 'ZP' ([long]$data.annual.ZP_STE.'2026'.full_cost)

$latestExtract = [Math]::Max((Get-Item -LiteralPath $snWorkbook).LastWriteTime.Date.Ticks, (Get-Item -LiteralPath $zpWorkbook).LastWriteTime.Date.Ticks)
$data.metadata.sap_extract_date = [DateTime]::new($latestExtract).ToString('yyyy-MM-dd')
$data.metadata.dashboard_updated = (Get-Date).ToString('yyyy-MM-dd')
$data | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputFile -Encoding utf8

Write-Output "Finanzdaten aktualisiert: $OutputFile"
Write-Output "SAP-Periode: $($data.metadata.sap_period); Abzug: $($data.metadata.sap_extract_date)"
Write-Output "Periodenpruefung: SN und ZP sind identisch und lueckenlos."
