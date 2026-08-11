param(
  [int]$Port = 5500
)

$root = $PSScriptRoot
$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()

$mime = @{
  ".html" = "text/html; charset=utf-8"
  ".js"   = "application/javascript; charset=utf-8"
  ".css"  = "text/css; charset=utf-8"
  ".png"  = "image/png"
  ".jpg"  = "image/jpeg"
  ".jpeg" = "image/jpeg"
  ".svg"  = "image/svg+xml"
  ".ico"  = "image/x-icon"
  ".json" = "application/json; charset=utf-8"
  ".mp3"  = "audio/mpeg"
  ".woff" = "font/woff"
  ".woff2"= "font/woff2"
}

Write-Host "Serving '$root' at $prefix (Ctrl+C to stop)"
Write-Host "Open: ${prefix}Wedding%20Invitation.dc.html"

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    $localPath = [System.Uri]::UnescapeDataString($request.Url.LocalPath)
    if ($localPath -eq "/") { $localPath = "/Wedding Invitation.dc.html" }

    $filePath = Join-Path $root ($localPath.TrimStart("/"))
    $fullRoot = (Resolve-Path $root).Path
    $resolved = $null
    if (Test-Path -LiteralPath $filePath) {
      $resolved = (Resolve-Path -LiteralPath $filePath).Path
    }

    if ($resolved -and $resolved.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path -LiteralPath $filePath -PathType Container)) {
      $ext = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()
      $contentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "application/octet-stream" }
      $bytes = [System.IO.File]::ReadAllBytes($filePath)
      $response.ContentType = $contentType
      $response.ContentLength64 = $bytes.Length
      $response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $response.StatusCode = 404
      $notFound = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $localPath")
      $response.OutputStream.Write($notFound, 0, $notFound.Length)
    }
    $response.OutputStream.Close()
  }
} finally {
  $listener.Stop()
  $listener.Close()
}