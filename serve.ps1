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
  ".mpeg" = "audio/mpeg"
  ".mp4"  = "video/mp4"
  ".woff" = "font/woff"
  ".woff2"= "font/woff2"
}

Write-Host "Serving '$root' at $prefix (Ctrl+C to stop)"
Write-Host "Open: ${prefix}index.html"

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    try {
      $request = $context.Request
      $response = $context.Response

      $localPath = [System.Uri]::UnescapeDataString($request.Url.LocalPath)
      if ($localPath -eq "/") { $localPath = "/index.html" }

      $filePath = Join-Path $root ($localPath.TrimStart("/"))
      $fullRoot = (Resolve-Path $root).Path
      $resolved = $null
      if (Test-Path -LiteralPath $filePath) {
        $resolved = (Resolve-Path -LiteralPath $filePath).Path
      }

      if ($resolved -and $resolved.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path -LiteralPath $filePath -PathType Container)) {
        $ext = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()
        $contentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "application/octet-stream" }
        $fileLen = (Get-Item -LiteralPath $filePath).Length
        $response.Headers.Set("Accept-Ranges", "bytes")
        $response.ContentType = $contentType

        $rangeHeader = $request.Headers["Range"]
        $start = 0
        $end = $fileLen - 1
        $isRange = $false
        if ($rangeHeader -and $rangeHeader -match "bytes=(\d*)-(\d*)") {
          $isRange = $true
          if ($matches[1] -ne "") { $start = [int64]$matches[1] }
          if ($matches[2] -ne "") { $end = [int64]$matches[2] }
          if ($end -ge $fileLen) { $end = $fileLen - 1 }
          if ($start -gt $end -or $start -lt 0) {
            $response.StatusCode = 416
            $response.Headers.Set("Content-Range", "bytes */$fileLen")
            $response.OutputStream.Close()
            continue
          }
        }

        $len = $end - $start + 1
        if ($isRange) {
          $response.StatusCode = 206
          $response.Headers.Set("Content-Range", "bytes $start-$end/$fileLen")
        } else {
          $response.StatusCode = 200
        }
        $response.ContentLength64 = $len

        $fs = [System.IO.File]::OpenRead($filePath)
        try {
          $fs.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
          $buffer = New-Object byte[] 65536
          $remaining = $len
          while ($remaining -gt 0) {
            $toRead = [Math]::Min($buffer.Length, $remaining)
            $read = $fs.Read($buffer, 0, $toRead)
            if ($read -le 0) { break }
            $response.OutputStream.Write($buffer, 0, $read)
            $remaining -= $read
          }
        } finally {
          $fs.Close()
        }
      } else {
        $response.StatusCode = 404
        $notFound = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $localPath")
        $response.ContentLength64 = $notFound.Length
        $response.OutputStream.Write($notFound, 0, $notFound.Length)
      }
      $response.OutputStream.Close()
    } catch {
      Write-Host "Request error: $_"
      try { $context.Response.OutputStream.Close() } catch {}
    }
  }
} finally {
  $listener.Stop()
  $listener.Close()
}
