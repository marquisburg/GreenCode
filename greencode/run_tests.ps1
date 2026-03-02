param(
  [string]$CompilerPath = ".\greencode.exe",
  [ValidateSet("all", "smoke", "negative")]
  [string]$Suite = "all",
  [switch]$Build,
  [switch]$SkipAst,
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

function Invoke-AstSuite {
  param(
    [Parameter(Mandatory = $true)] [string]$Root,
    [Parameter(Mandatory = $true)] [string]$OutDir
  )

  $methasm = Join-Path $Root "..\bin\methasm.exe"
  $nasm = "nasm"
  $gcc = "gcc"
  $src = Join-Path $Root "tests\ast_selftest.masm"
  $asm = Join-Path $OutDir "ast_selftest.s"
  $obj = Join-Path $OutDir "ast_selftest.o"
  $entryObj = Join-Path $OutDir "masm_entry_ast.o"
  $gcObj = Join-Path $OutDir "gc_ast.o"
  $exe = Join-Path $OutDir "ast_selftest.exe"

  if (-not (Test-Path $methasm)) {
    return [pscustomobject]@{ Passed = $false; Detail = "Missing methasm compiler at '$methasm'" }
  }
  if (-not (Test-Path $src)) {
    return [pscustomobject]@{ Passed = $false; Detail = "Missing AST self-test source '$src'" }
  }

  & $methasm $src -o $asm 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    return [pscustomobject]@{ Passed = $false; Detail = "AST self-test MethASM compile failed" }
  }

  & $nasm -f win64 $asm -o $obj 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    return [pscustomobject]@{ Passed = $false; Detail = "AST self-test NASM assemble failed" }
  }

  & $gcc -c (Join-Path $Root "..\src\runtime\masm_entry.c") -o $entryObj 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    return [pscustomobject]@{ Passed = $false; Detail = "AST self-test masm_entry compile failed" }
  }

  & $gcc -c (Join-Path $Root "..\src\runtime\gc.c") -o $gcObj 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    return [pscustomobject]@{ Passed = $false; Detail = "AST self-test GC compile failed" }
  }

  & $gcc -nostartfiles $obj $entryObj $gcObj -o $exe -lkernel32 -lshell32 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    return [pscustomobject]@{ Passed = $false; Detail = "AST self-test link failed" }
  }

  & $exe 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    return [pscustomobject]@{ Passed = $false; Detail = "AST self-test runtime failed (exit $LASTEXITCODE)" }
  }

  return [pscustomobject]@{ Passed = $true; Detail = "" }
}

$allCases = @(
  [pscustomobject]@{
    Name = "simple_valid"
    Input = "tests\simple.gc"
    ShouldSucceed = $true
    OutputMustMatch = @("function main\(\) -> int32", "return 0;")
  },
  [pscustomobject]@{
    Name = "hello_valid"
    Input = "tests\hello.gc"
    ShouldSucceed = $true
    OutputMustMatch = @("function main\(\) -> int32", "return 0;")
  },
  [pscustomobject]@{
    Name = "expr_arithmetic"
    Input = "tests\test_expr.gc"
    ShouldSucceed = $true
    OutputMustMatch = @("function main\(\) -> int32", "return 17;")
  },
  [pscustomobject]@{
    Name = "expr_precedence"
    Input = "tests\test_expr_precedence.gc"
    ShouldSucceed = $true
    OutputMustMatch = @("function main\(\) -> int32", "return 11;")
  },
  [pscustomobject]@{
    Name = "expr_parentheses"
    Input = "tests\test_expr_parentheses.gc"
    ShouldSucceed = $true
    OutputMustMatch = @("function main\(\) -> int32", "return 14;")
  },
  [pscustomobject]@{
    Name = "expr_unary_chain"
    Input = "tests\test_expr_unary.gc"
    ShouldSucceed = $true
    OutputMustMatch = @("function main\(\) -> int32", "return 2;")
  },
  [pscustomobject]@{
    Name = "expr_left_assoc"
    Input = "tests\test_expr_left_assoc.gc"
    ShouldSucceed = $true
    OutputMustMatch = @("function main\(\) -> int32", "return 12;")
  },
  [pscustomobject]@{
    Name = "expr_whitespace"
    Input = "tests\test_expr_whitespace.gc"
    ShouldSucceed = $true
    OutputMustMatch = @("function main\(\) -> int32", "return 16;")
  },
  [pscustomobject]@{
    Name = "expr_div_zero"
    Input = "tests\test_expr_div_zero.gc"
    ShouldSucceed = $false
    StderrMustMatch = @("Parse/codegen failed")
  },
  [pscustomobject]@{
    Name = "expr_unbalanced"
    Input = "tests\test_expr_unbalanced.gc"
    ShouldSucceed = $false
    StderrMustMatch = @("Parse/codegen failed")
  },
  [pscustomobject]@{
    Name = "expr_trailing_op"
    Input = "tests\test_expr_trailing_op.gc"
    ShouldSucceed = $false
    StderrMustMatch = @("Parse/codegen failed")
  },
  [pscustomobject]@{
    Name = "missing_semicolon"
    Input = "tests\test_return.gc"
    ShouldSucceed = $false
    StderrMustMatch = @("Parse/codegen failed|Lexer failed")
  },
  [pscustomobject]@{
    Name = "return_without_value"
    Input = "tests\test_ret.gc"
    ShouldSucceed = $false
    StderrMustMatch = @("Parse/codegen failed|Lexer failed")
  },
  [pscustomobject]@{
    Name = "missing_paren"
    Input = "tests\test_paren.gc"
    ShouldSucceed = $false
    StderrMustMatch = @("Parse/codegen failed|Lexer failed")
  },
  [pscustomobject]@{
    Name = "minimal_invalid"
    Input = "tests\test_minimal.gc"
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

if (-not $SkipAst) {
  $ast = Invoke-AstSuite -Root $scriptRoot -OutDir $outDir
  if ($ast.Passed) {
    Write-Host "[PASS] ast_selftest"
    $pass++
  } else {
    Write-Host "[FAIL] ast_selftest :: $($ast.Detail)"
    $fail++
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
