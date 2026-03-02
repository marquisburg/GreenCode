param(
  [string]$CompilerPath = ".\greencode.exe",
  [ValidateSet("all", "smoke", "negative")]
  [string]$Suite = "all",
  [switch]$Build,
  [switch]$KeepOutputs,
  [switch]$StopOnFail
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-Case {
  param(
    [Parameter(Mandatory = $true)] $Case,
    [Parameter(Mandatory = $true)] [string]$Compiler,
    [Parameter(Mandatory = $true)] [string]$OutDir
  )

  $inputPath = Join-Path $scriptRoot $Case.Input
  $outputPath = Join-Path $OutDir ($Case.Name + ".masm")

  if (-not (Test-Path $inputPath)) {
    return [pscustomobject]@{
      Name = $Case.Name
      Passed = $false
      Detail = "Missing input file '$($Case.Input)'"
    }
  }

  $outputText = & $Compiler $inputPath -o $outputPath 2>&1 | Out-String
  $exitCode = $LASTEXITCODE
  $ok = $true
  $detail = ""

  if ($Case.ShouldSucceed) {
    if ($exitCode -ne 0) {
      $ok = $false
      $detail = "Expected success, got exit code $exitCode"
    } elseif (-not (Test-Path $outputPath)) {
      $ok = $false
      $detail = "Expected output file, but it was not created"
    } elseif ($Case.OutputMustMatch) {
      $generated = Get-Content -Raw $outputPath
      foreach ($pattern in $Case.OutputMustMatch) {
        if ($generated -notmatch $pattern) {
          $ok = $false
          $detail = "Output did not match pattern '$pattern'"
          break
        }
      }
    }
  } else {
    if ($exitCode -eq 0) {
      $ok = $false
      $detail = "Expected failure, but command succeeded"
    } elseif ($Case.StderrMustMatch) {
      foreach ($pattern in $Case.StderrMustMatch) {
        if ($outputText -notmatch $pattern) {
          $ok = $false
          $detail = "Error output did not match pattern '$pattern'"
          break
        }
      }
    }
  }

  if (-not $ok -and [string]::IsNullOrWhiteSpace($detail)) {
    $detail = "Failed with exit code $exitCode"
  }

  return [pscustomobject]@{
    Name = $Case.Name
    Passed = $ok
    Detail = $detail
    ExitCode = $exitCode
    Output = $outputText.Trim()
    OutputFile = $outputPath
  }
}

$allCases = @(
  [pscustomobject]@{
    Name = "simple_valid"
    Input = "simple.gc"
    ShouldSucceed = $true
    OutputMustMatch = @("function main\(\) -> int32", "return 0;")
  },
  [pscustomobject]@{
    Name = "hello_valid"
    Input = "hello.gc"
    ShouldSucceed = $true
    OutputMustMatch = @("function main\(\) -> int32", "return 0;")
  },
  [pscustomobject]@{
    Name = "missing_semicolon"
    Input = "test_return.gc"
    ShouldSucceed = $false
    StderrMustMatch = @("Parse/codegen failed|Lexer failed")
  },
  [pscustomobject]@{
    Name = "return_without_value"
    Input = "test_ret.gc"
    ShouldSucceed = $false
    StderrMustMatch = @("Parse/codegen failed|Lexer failed")
  },
  [pscustomobject]@{
    Name = "missing_paren"
    Input = "test_paren.gc"
    ShouldSucceed = $false
    StderrMustMatch = @("Parse/codegen failed|Lexer failed")
  },
  [pscustomobject]@{
    Name = "minimal_invalid"
    Input = "test_minimal.gc"
    ShouldSucceed = $false
    StderrMustMatch = @("Parse/codegen failed|Lexer failed")
  }
)

switch ($Suite) {
  "smoke" {
    $cases = $allCases | Where-Object { $_.ShouldSucceed }
  }
  "negative" {
    $cases = $allCases | Where-Object { -not $_.ShouldSucceed }
  }
  default {
    $cases = $allCases
  }
}

if ($Build) {
  Push-Location $scriptRoot
  try {
    & cmd /c build.bat
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Build failed."
      exit 1
    }
  } finally {
    Pop-Location
  }
}

$resolvedCompiler = if ([System.IO.Path]::IsPathRooted($CompilerPath)) {
  $CompilerPath
} else {
  Join-Path $scriptRoot $CompilerPath
}

if (-not (Test-Path $resolvedCompiler)) {
  Write-Host "Compiler not found at '$resolvedCompiler'."
  Write-Host "Run with -Build or set -CompilerPath."
  exit 1
}

$outDir = Join-Path $scriptRoot ".test-output"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$pass = 0
$fail = 0

foreach ($case in $cases) {
  $result = Invoke-Case -Case $case -Compiler $resolvedCompiler -OutDir $outDir
  if ($result.Passed) {
    Write-Host "[PASS] $($result.Name)"
    $pass++
  } else {
    Write-Host "[FAIL] $($result.Name) :: $($result.Detail)"
    if ($result.Output) {
      Write-Host $result.Output
    }
    $fail++
    if ($StopOnFail) {
      break
    }
  }
}

Write-Host ""
Write-Host ("Suite '{0}' summary: {1}/{2} passed" -f $Suite, $pass, ($pass + $fail))

if (-not $KeepOutputs) {
  Remove-Item -Path $outDir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -gt 0) {
  exit 1
}

exit 0
