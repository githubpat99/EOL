$root = $PSScriptRoot
$port = 8000
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$port/")
$listener.Start()

function Send-Response($context, [int]$status, [string]$contentType, [byte[]]$body) {
    $context.Response.StatusCode = $status
    $context.Response.Headers.Add('Access-Control-Allow-Origin', '*')
    $context.Response.Headers.Add('Access-Control-Allow-Methods', 'GET, PUT, OPTIONS')
    $context.Response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
    $context.Response.ContentType = $contentType
    $context.Response.ContentLength64 = $body.Length
    $context.Response.Headers.Add('Cache-Control', 'no-store')
    $context.Response.OutputStream.Write($body, 0, $body.Length)
    $context.Response.Close()
}

function Send-Json($context, [int]$status, $payload) {
    $body = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress))
    Send-Response $context $status 'application/json; charset=utf-8' $body
}

function Get-ContentType($extension) {
    switch ($extension.ToLowerInvariant()) {
        '.html' { return 'text/html; charset=utf-8' }
        '.json' { return 'application/json; charset=utf-8' }
        '.css' { return 'text/css; charset=utf-8' }
        '.js' { return 'text/javascript; charset=utf-8' }
        default { return 'application/octet-stream' }
    }
}

Write-Host "Dashboard geoeffnet unter http://127.0.0.1:$port/sn_zp_demografie_planung.html"
Write-Host 'Beenden mit Strg+C'

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            if ($context.Request.HttpMethod -eq 'OPTIONS') {
                Send-Response $context 204 'text/plain; charset=utf-8' ([byte[]]::new(0))
                continue
            }

            if ($context.Request.HttpMethod -eq 'PUT' -and $context.Request.Url.AbsolutePath -eq '/api/demografie') {
                $reader = [IO.StreamReader]::new($context.Request.InputStream, [Text.Encoding]::UTF8)
                $jsonText = $reader.ReadToEnd()
                $reader.Close()
                try {
                    $data = $jsonText | ConvertFrom-Json
                    if ($data -isnot [Array] -or $data.Count -eq 0) { throw 'Die Daten muessen ein nicht-leeres JSON-Array sein' }
                    foreach ($employee in $data) {
                        if ([string]::IsNullOrWhiteSpace([string]$employee.name) -or [string]::IsNullOrWhiteSpace([string]$employee.team)) {
                            throw 'Jeder Mitarbeiter benoetigt Name und Team'
                        }
                        if ($null -eq $employee.fachgebiete) { throw 'Jeder Mitarbeiter benoetigt Fachgebiete' }
                    }
                    $target = Join-Path $root 'demografie.json'
                    $temporary = Join-Path $root ("demografie.{0}.tmp" -f [guid]::NewGuid())
                    $jsonText | Set-Content -Path $temporary -Encoding UTF8
                    Move-Item -Path $temporary -Destination $target -Force
                    Send-Json $context 200 @{ ok = $true; file = 'demografie.json' }
                } catch {
                    Send-Json $context 400 @{ error = $_.Exception.Message }
                }
                continue
            }

            if ($context.Request.HttpMethod -eq 'GET') {
                $relativePath = [Uri]::UnescapeDataString($context.Request.Url.AbsolutePath.TrimStart('/'))
                if ([string]::IsNullOrWhiteSpace($relativePath)) { $relativePath = 'sn_zp_demografie_planung.html' }
                $file = Join-Path $root $relativePath
                $rootPath = [IO.Path]::GetFullPath($root)
                $filePath = [IO.Path]::GetFullPath($file)
                if ($filePath.StartsWith($rootPath) -and (Test-Path $filePath -PathType Leaf)) {
                    $body = [IO.File]::ReadAllBytes($filePath)
                    $context.Response.Headers.Add('Last-Modified', ([IO.File]::GetLastWriteTimeUtc($filePath)).ToString('R'))
                    Send-Response $context 200 (Get-ContentType ([IO.Path]::GetExtension($filePath))) $body
                } else {
                    Send-Json $context 404 @{ error = 'Datei nicht gefunden' }
                }
                continue
            }

            Send-Json $context 405 @{ error = 'Methode nicht erlaubt' }
        } catch {
            try { Send-Json $context 500 @{ error = $_.Exception.Message } } catch { }
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
