# Strip mode-only diffs from a patch file (old mode / new mode without ---/+++)
param(
    [string]$InputFile = "patches/_cleaned.patch",
    [string]$OutputFile = "patches/_content.patch"
)

$content = Get-Content -Path $InputFile -Raw
$lines = $content -split "`r`n|`n"

$result = @()
$i = 0
while ($i -lt $lines.Count) {
    $line = $lines[$i]
    
    # Check if this is a diff header followed by mode change only
    if ($line -match "^diff --git " -and $i + 2 -lt $lines.Count) {
        $next1 = $lines[$i + 1].Trim()
        $next2 = $lines[$i + 2].Trim()
        
        if ($next1 -match "^old mode " -and $next2 -match "^new mode ") {
            # This is a mode-only diff (diff + old mode + new mode, no ---/+++)
            # Skip this and the next 2 lines
            $i += 3
            
            # Also skip any trailing empty lines between mode diffs
            while ($i -lt $lines.Count -and ($lines[$i].Trim() -eq "" -or $lines[$i] -match "^\s*$")) {
                $i++
            }
            continue
        }
    }
    
    $result += $line
    $i++
}

$result -join "`r`n" | Set-Content -Path $OutputFile -NoNewline
Write-Host "Stripped mode-only diffs. Result: $($result.Count) lines"
