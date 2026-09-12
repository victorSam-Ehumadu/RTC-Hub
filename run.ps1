# Launches the app without having to retype the --dart-define flags.
#
#   .\run            live, against Supabase (needs env.json)
#   .\run demo       offline UI walkthrough, no project and no keys
#   .\run -Release   release build
#
# Anything after the mode is passed straight through to `flutter run`, so
# `.\run demo -d chrome` works.
#
# Flutter has no per-project default-arguments file, which is the only reason
# this script exists.

param(
    [Parameter(Position = 0)]
    [string]$Mode = 'live',

    [switch]$Release,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$flags = @()

if ($Mode -eq 'demo') {
    $flags += '--dart-define=DEMO=true'
    Write-Host 'DEMO mode - canned data, Supabase is never contacted.' -ForegroundColor Yellow
    Write-Host 'Bypasses RLS by construction; never use it to show an access rule works.' -ForegroundColor DarkGray
}
else {
    if (-not (Test-Path 'env.json')) {
        Write-Host 'env.json not found.' -ForegroundColor Red
        Write-Host 'Copy env.example.json to env.json and fill in the project URL and anon key,'
        Write-Host 'or run  .\run demo  to browse the UI with no backend.'
        exit 1
    }

    $cfg = Get-Content 'env.json' -Raw | ConvertFrom-Json
    if ($cfg.SUPABASE_URL -match 'your-project-id' -or $cfg.SUPABASE_ANON_KEY -match 'your-anon-key') {
        Write-Host 'env.json still holds the placeholder values from env.example.json.' -ForegroundColor Red
        Write-Host 'Ask the project owner for the real URL and anon key (never service_role).'
        exit 1
    }

    $flags += '--dart-define-from-file=env.json'
    Write-Host "LIVE mode - $($cfg.SUPABASE_URL)" -ForegroundColor Green
}

if ($Release) { $flags += '--release' }
if ($Rest)    { $flags += $Rest }

Write-Host "flutter run $($flags -join ' ')`n" -ForegroundColor DarkGray
& flutter run @flags
