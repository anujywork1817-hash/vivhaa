# Runs golang-migrate against the local Postgres instance via Docker,
# so no local `migrate` CLI install is required.
#
# Usage:
#   .\scripts\migrate.ps1 up
#   .\scripts\migrate.ps1 down 1
#   .\scripts\migrate.ps1 version
#   .\scripts\migrate.ps1 create add_profiles_table
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Command,

    [Parameter(Position=1, ValueFromRemainingArguments=$true)]
    [string[]]$Rest
)

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

$envFile = Join-Path $RootDir ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim())
        }
    }
}

$DbHost = if ($env:DB_HOST) { $env:DB_HOST } else { "localhost" }
$DbPort = if ($env:DB_PORT) { $env:DB_PORT } else { "5432" }
$DbUser = if ($env:DB_USER) { $env:DB_USER } else { "postgres" }
$DbPassword = if ($env:DB_PASSWORD) { $env:DB_PASSWORD } else { "postgres" }
$DbName = if ($env:DB_NAME) { $env:DB_NAME } else { "myapp" }
$DbSslMode = if ($env:DB_SSLMODE) { $env:DB_SSLMODE } else { "disable" }

if ($Command -eq "create") {
    $Name = $Rest[0]
    if (-not $Name) { throw "usage: .\scripts\migrate.ps1 create <name>" }
    docker run --rm -v "${RootDir}/migrations:/migrations" migrate/migrate `
        create -ext sql -dir /migrations -seq $Name
    exit 0
}

$ContainerDbHost = $DbHost
if ($DbHost -eq "localhost" -or $DbHost -eq "127.0.0.1") {
    $ContainerDbHost = "host.docker.internal"
}

$Dsn = "postgres://${DbUser}:${DbPassword}@${ContainerDbHost}:${DbPort}/${DbName}?sslmode=${DbSslMode}"

docker run --rm --add-host=host.docker.internal:host-gateway `
    -v "${RootDir}/migrations:/migrations" migrate/migrate `
    -path=/migrations -database $Dsn $Command @Rest
