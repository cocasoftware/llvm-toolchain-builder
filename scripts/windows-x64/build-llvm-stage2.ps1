#Requires -Version 7.0
# =============================================================================
# LLVM Windows Stage 2 Build — full toolchain using Stage 1 clang-cl + libc++.
#
# Uses the MSVC-built Stage 1 clang as the host compiler to produce a
# self-hosted LLVM toolchain with libc++ as the default C++ stdlib.
# This gives users a toolchain that does not require MSVC C++ headers/libs
# for C++ compilation (only Windows SDK for C and linking).
#
# Environment variables:
#   LLVM_VERSION    — LLVM version to build (default: 21.1.1)
#   VARIANT         — main or p2996 (default: main)
#   STAGE1_DIR      — Stage 1 toolchain directory (required)
#   INSTALL_PREFIX  — Stage 2 installation directory
#   BUILD_DIR       — CMake build directory (short path recommended)
#   NPROC           — parallel build jobs
#   PYTHON_DIR      — Python installation for LLDB bindings
# =============================================================================
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Configuration ─────────────────────────────────────────────────────────────
$LLVM_VERSION   = if ($env:LLVM_VERSION)   { $env:LLVM_VERSION }   else { '21.1.1' }
$VARIANT        = if ($env:VARIANT)        { $env:VARIANT }        else { 'main' }
$STAGE1_DIR     = if ($env:STAGE1_DIR)     { $env:STAGE1_DIR }     else { throw "STAGE1_DIR is required" }
$INSTALL_PREFIX = if ($env:INSTALL_PREFIX)  { $env:INSTALL_PREFIX } else { 'C:\coca-toolchain' }
$BUILD_DIR      = if ($env:BUILD_DIR)      { $env:BUILD_DIR }      else { 'C:\b2' }
$NPROC          = if ($env:NPROC)          { [int]$env:NPROC }     else { $env:NUMBER_OF_PROCESSORS }
$LLVM_SRC       = if ($env:LLVM_SRC)       { $env:LLVM_SRC }      else { 'C:\llvm-src' }
$P2996_SRC      = if ($env:P2996_SRC)      { $env:P2996_SRC }     else { 'C:\llvm-p2996' }
$PYTHON_DIR     = if ($env:PYTHON_DIR)     { $env:PYTHON_DIR }    else { '' }

function Log($msg) {
    Write-Host "===> $(Get-Date -Format 'HH:mm:ss') [Stage2] $msg" -ForegroundColor Cyan
}

function LogError($msg) {
    Write-Host "===> $(Get-Date -Format 'HH:mm:ss') ERROR: $msg" -ForegroundColor Red
}

# ── 0. Validate Stage 1 toolchain ─────────────────────────────────────────────
function Test-Stage1Toolchain {
    Log "Validating Stage 1 toolchain at $STAGE1_DIR..."

    $clangCl = Join-Path $STAGE1_DIR 'bin\clang-cl.exe'
    $lldLink = Join-Path $STAGE1_DIR 'bin\lld-link.exe'
    $llvmAr  = Join-Path $STAGE1_DIR 'bin\llvm-ar.exe'
    $llvmRanlib = Join-Path $STAGE1_DIR 'bin\llvm-ranlib.exe'

    foreach ($tool in @($clangCl, $lldLink, $llvmAr)) {
        if (-not (Test-Path $tool)) {
            throw "Stage 1 tool not found: $tool"
        }
    }

    & $clangCl --version
    Log "Stage 1 toolchain validated"
}

# ── 1. Setup MSVC environment (still needed for Windows SDK headers/libs) ─────
function Invoke-VsDevShell {
    Log "Setting up MSVC environment (for Windows SDK)..."

    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        throw "vswhere.exe not found — Visual Studio is required for Windows SDK"
    }

    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsPath) {
        throw "No Visual Studio installation with C++ tools found"
    }

    $vcvarsall = Join-Path $vsPath "VC\Auxiliary\Build\vcvarsall.bat"
    if (-not (Test-Path $vcvarsall)) {
        throw "vcvarsall.bat not found at $vcvarsall"
    }

    $envBefore = @{}
    Get-ChildItem env: | ForEach-Object { $envBefore[$_.Name] = $_.Value }

    $tempFile = [System.IO.Path]::GetTempFileName()
    cmd /c "`"$vcvarsall`" x64 >nul 2>&1 && set > `"$tempFile`""

    Get-Content $tempFile | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            $name = $matches[1]
            $value = $matches[2]
            if ($envBefore[$name] -ne $value) {
                Set-Item -Path "env:$name" -Value $value
            }
        }
    }
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    Log "MSVC environment loaded (Windows SDK available)"
}

# ── 2. Obtain source code ────────────────────────────────────────────────────
function Get-LLVMSource {
    switch ($VARIANT) {
        'main' {
            if (Test-Path (Join-Path $LLVM_SRC 'llvm')) {
                Log "Using existing LLVM source at $LLVM_SRC"
            } else {
                Log "Cloning LLVM $LLVM_VERSION..."
                $null = & git clone --depth 1 --branch "llvmorg-$LLVM_VERSION" "https://github.com/llvm/llvm-project.git" $LLVM_SRC 2>&1
                if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
            }
            return $LLVM_SRC
        }
        'p2996' {
            if (Test-Path (Join-Path $P2996_SRC 'llvm')) {
                Log "Using existing p2996 source at $P2996_SRC"
            } else {
                Log "Cloning clang-p2996..."
                $null = & git clone --depth 1 --branch p2996 "https://github.com/nekomiya-kasane/clang-p2996.git" $P2996_SRC 2>&1
                if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
            }
            return $P2996_SRC
        }
        default { throw "Unknown variant '$VARIANT'" }
    }
}

# ── 3. Configure Python & SWIG ──────────────────────────────────────────────
function Find-PythonForLLDB {
    if ($PYTHON_DIR -and (Test-Path (Join-Path $PYTHON_DIR 'python.exe'))) {
        return $PYTHON_DIR
    }
    $pyExe = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pyExe) {
        $pyDir = Split-Path $pyExe.Source
        Log "Found Python at: $pyDir"
        return $pyDir
    }
    Log "WARNING: Python not found — LLDB Python bindings will be disabled"
    return $null
}

function Find-SWIG {
    $swigExe = Get-Command swig.exe -ErrorAction SilentlyContinue
    if ($swigExe) {
        Log "Found SWIG at: $($swigExe.Source)"
        return $swigExe.Source
    }
    Log "WARNING: SWIG not found — LLDB Python bindings will be disabled"
    return $null
}

# ── 4. Build LLVM Stage 2 ───────────────────────────────────────────────────
function Build-LLVMStage2 {
    param([string]$SourceDir)

    Log "Configuring LLVM Stage 2 (variant=$VARIANT, compiler=Stage1 clang-cl)..."

    New-Item -ItemType Directory -Path $BUILD_DIR -Force | Out-Null

    $stage1Bin = Join-Path $STAGE1_DIR 'bin'
    $clangCl   = Join-Path $stage1Bin 'clang-cl.exe'
    $lldLink   = Join-Path $stage1Bin 'lld-link.exe'
    $llvmAr    = Join-Path $stage1Bin 'llvm-ar.exe'
    $llvmRanlib = Join-Path $stage1Bin 'llvm-ranlib.exe'
    $llvmNm    = Join-Path $stage1Bin 'llvm-nm.exe'

    # Projects — same as Stage 1 (full-featured)
    $projects = 'clang;lld;clang-tools-extra;lldb;mlir;polly;flang'
    # Runtimes — add libcxx (Windows does not support libunwind/libcxxabi)
    $runtimes = 'compiler-rt;libcxx;openmp;flang-rt'
    $targets  = 'X86;AArch64;ARM;WebAssembly;RISCV;NVPTX;AMDGPU;BPF'

    $pyDir = Find-PythonForLLDB
    $swigExe = Find-SWIG
    $enablePython = ($null -ne $pyDir) -and ($null -ne $swigExe)

    $cmakeArgs = @(
        '-G', 'Ninja',
        '-S', (Join-Path $SourceDir 'llvm'),
        '-B', $BUILD_DIR,
        '-DCMAKE_BUILD_TYPE=Release',
        "-DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX",
        # Stage 1 clang-cl as host compiler
        "-DCMAKE_C_COMPILER=$clangCl",
        "-DCMAKE_CXX_COMPILER=$clangCl",
        "-DCMAKE_AR=$llvmAr",
        "-DCMAKE_RANLIB=$llvmRanlib",
        "-DCMAKE_NM=$llvmNm",
        "-DCMAKE_LINKER=$lldLink",
        '-DLLVM_USE_LINKER=lld',
        '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL',
        # libc++ as default C++ stdlib for the built clang
        '-DCLANG_DEFAULT_CXX_STDLIB=libc++',
        '-DCLANG_DEFAULT_RTLIB=compiler-rt',
        '-DCLANG_DEFAULT_LINKER=lld',
        # Projects & runtimes
        "-DLLVM_ENABLE_PROJECTS=$projects",
        "-DLLVM_ENABLE_RUNTIMES=$runtimes",
        "-DLLVM_TARGETS_TO_BUILD=$targets",
        # Feature flags
        '-DLLVM_INSTALL_UTILS=ON',
        '-DLLVM_ENABLE_ASSERTIONS=OFF',
        '-DLLVM_INCLUDE_TESTS=OFF',
        '-DLLVM_INCLUDE_BENCHMARKS=OFF',
        '-DLLVM_INCLUDE_EXAMPLES=OFF',
        '-DLLVM_INCLUDE_DOCS=OFF',
        '-DLLVM_ENABLE_BINDINGS=ON',
        '-DLLVM_INSTALL_TOOLCHAIN_ONLY=OFF',
        '-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF',
        # Optional deps — OFF for portability
        '-DLLVM_ENABLE_ZLIB=OFF',
        '-DLLVM_ENABLE_ZSTD=OFF',
        '-DLLVM_ENABLE_LIBXML2=OFF',
        '-DLLVM_ENABLE_TERMINFO=OFF',
        '-DLLVM_ENABLE_LIBEDIT=OFF',
        '-DLLVM_ENABLE_DIA_SDK=OFF',
        # Clang
        '-DCLANG_ENABLE_STATIC_ANALYZER=ON',
        '-DCLANG_ENABLE_ARCMT=ON',
        # LLDB
        '-DLLDB_ENABLE_CURSES=OFF',
        '-DLLDB_ENABLE_LIBEDIT=OFF',
        '-DLLDB_ENABLE_LZMA=OFF',
        '-DLLDB_ENABLE_LIBXML2=OFF',
        '-DLLDB_ENABLE_LUA=OFF',
        '-DLLDB_ENABLE_FBSDVMCORE=OFF',
        # Polly
        '-DPOLLY_ENABLE_GPGPU_CODEGEN=OFF',
        # compiler-rt
        '-DCOMPILER_RT_BUILD_SANITIZERS=ON',
        '-DCOMPILER_RT_BUILD_XRAY=OFF',
        '-DCOMPILER_RT_BUILD_LIBFUZZER=ON',
        '-DCOMPILER_RT_BUILD_PROFILE=ON',
        '-DCOMPILER_RT_BUILD_MEMPROF=OFF',
        '-DCOMPILER_RT_BUILD_ORC=ON',
        # OpenMP
        '-DRUNTIMES_CMAKE_ARGS=-DLIBOMP_HAVE_RTM_INTRINSICS=TRUE;-DLIBOMP_HAVE_IMMINTRIN_H=TRUE;-DLIBOMP_HAVE_ATTRIBUTE_RTM=TRUE',
        # libc++ — build both shared and static on Windows
        '-DLIBCXX_ENABLE_SHARED=ON',
        '-DLIBCXX_ENABLE_STATIC=ON',
        '-DLIBCXX_INSTALL_MODULES=ON'
    )

    # LLDB Python bindings
    if ($enablePython) {
        $pyExe = Join-Path $pyDir 'python.exe'
        $pyVer = & $pyExe -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
        $pyVerMajMin = $pyVer.Trim()
        $pyInclude = (& $pyExe -c "import sysconfig; print(sysconfig.get_path('include'))").Trim()
        $pyLibDir = (& $pyExe -c "import sysconfig; print(sysconfig.get_config_var('installed_base'))").Trim()
        $pyLib = Join-Path $pyLibDir "libs\python$($pyVerMajMin.Replace('.',''))`.lib"
        $pyPureVer = $pyVerMajMin.Replace('.','')

        Log "LLDB Python: $pyExe (version $pyVerMajMin)"

        $cmakeArgs += @(
            '-DLLDB_ENABLE_PYTHON=ON',
            "-DPython3_EXECUTABLE=$pyExe",
            "-DPython3_INCLUDE_DIR=$pyInclude",
            "-DPython3_LIBRARY=$pyLib",
            "-DSWIG_EXECUTABLE=$swigExe",
            "-DLLDB_PYTHON_HOME=../tools/python",
            "-DLLDB_PYTHON_EXT_SUFFIX=.cp${pyPureVer}-win_amd64.pyd",
            '-DMLIR_ENABLE_BINDINGS_PYTHON=ON'
        )
    } else {
        $cmakeArgs += '-DLLDB_ENABLE_PYTHON=OFF'
    }

    # Configure
    Log "Running cmake configure..."
    & cmake @cmakeArgs
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed (exit code $LASTEXITCODE)" }

    # Build
    Log "Building LLVM Stage 2 (this will take a long time, -j$NPROC)..."
    & cmake --build $BUILD_DIR -- "-j$NPROC"
    if ($LASTEXITCODE -ne 0) { throw "CMake build failed (exit code $LASTEXITCODE)" }

    # Install
    Log "Installing to $INSTALL_PREFIX..."
    & cmake --install $BUILD_DIR
    if ($LASTEXITCODE -ne 0) { throw "CMake install failed (exit code $LASTEXITCODE)" }

    Log "Stage 2 build and install complete"
}

# ── 5. Post-install ──────────────────────────────────────────────────────────
function Invoke-PostInstall {
    Log "Post-install: bundling dependencies..."

    $binDir = Join-Path $INSTALL_PREFIX 'bin'

    # Bundle MSVC Runtime DLLs
    $vcRedistDlls = @(
        'vcruntime140.dll', 'vcruntime140_1.dll',
        'msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll',
        'concrt140.dll', 'vccorlib140.dll'
    )
    $vcToolsRedist = $env:VCToolsRedistDir
    if ($vcToolsRedist) {
        $redistX64 = Join-Path $vcToolsRedist 'x64\Microsoft.VC143.CRT'
        if (-not (Test-Path $redistX64)) {
            $redistX64 = Join-Path $vcToolsRedist 'x64\Microsoft.VC142.CRT'
        }
        if (Test-Path $redistX64) {
            foreach ($dll in $vcRedistDlls) {
                $src = Join-Path $redistX64 $dll
                if (Test-Path $src) {
                    Copy-Item $src -Destination $binDir -Force
                    Log "  Bundled: $dll"
                }
            }
        }
    }

    # Bundle UCRT
    $winSdkBin = "${env:WindowsSdkVerBinPath}x64\ucrt"
    if (-not (Test-Path $winSdkBin)) { $winSdkBin = "C:\Windows\System32" }
    $ucrtSrc = Join-Path $winSdkBin 'ucrtbase.dll'
    if (Test-Path $ucrtSrc) {
        Copy-Item $ucrtSrc -Destination $binDir -Force
        Log "  Bundled: ucrtbase.dll"
    }

    # Bundle Python for LLDB
    $pyDir = Find-PythonForLLDB
    if ($pyDir) {
        Log "Bundling Python for LLDB..."
        $pyDest = Join-Path $INSTALL_PREFIX 'tools\python'
        New-Item -ItemType Directory -Path $pyDest -Force | Out-Null

        $pyExe = Join-Path $pyDir 'python.exe'
        $pyVer = (& $pyExe -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')").Trim()
        $pyPureVer = $pyVer.Replace('.','')

        Copy-Item (Join-Path $pyDir 'python.exe') -Destination $pyDest -Force
        Copy-Item (Join-Path $pyDir 'pythonw.exe') -Destination $pyDest -Force -ErrorAction SilentlyContinue
        Copy-Item (Join-Path $pyDir "python${pyPureVer}.dll") -Destination $pyDest -Force
        Copy-Item (Join-Path $pyDir 'python3.dll') -Destination $pyDest -Force -ErrorAction SilentlyContinue
        Copy-Item (Join-Path $pyDir "python${pyPureVer}.dll") -Destination $binDir -Force
        Copy-Item (Join-Path $pyDir 'python3.dll') -Destination $binDir -Force -ErrorAction SilentlyContinue

        $pyLibSrc = Join-Path $pyDir 'Lib'
        if (Test-Path $pyLibSrc) {
            $pyLibDest = Join-Path $pyDest 'Lib'
            Copy-Item $pyLibSrc -Destination $pyLibDest -Recurse -Force
            foreach ($d in @('test', 'unittest\test', 'lib2to3\tests', 'tkinter', 'turtledemo', 'idlelib', 'ensurepip\_bundled', '__pycache__')) {
                $path = Join-Path $pyLibDest $d
                if (Test-Path $path) { Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }

        $pyDllsSrc = Join-Path $pyDir 'DLLs'
        if (Test-Path $pyDllsSrc) {
            Copy-Item $pyDllsSrc -Destination (Join-Path $pyDest 'DLLs') -Recurse -Force
        }
        Log "Python bundled"
    }

    # Install Clang Python bindings
    $sourceDir = if ($VARIANT -eq 'p2996') { $P2996_SRC } else { $LLVM_SRC }
    $clangBindings = Join-Path $sourceDir 'clang\bindings\python\clang'
    if ((Test-Path $clangBindings) -and $pyDir) {
        $pyExe2 = Join-Path $pyDir 'python.exe'
        $pyVer2 = (& $pyExe2 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')").Trim()
        $dest = Join-Path $INSTALL_PREFIX "lib\python$pyVer2\site-packages\clang"
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Copy-Item "$clangBindings\*" -Destination $dest -Recurse -Force
        Log "Clang Python bindings installed"
    }

    Log "Post-install complete"
}

# ── 6. Create archive ────────────────────────────────────────────────────────
function New-Archive {
    $archiveName = switch ($VARIANT) {
        'main'  { 'coca-toolchain-win-x86_64' }
        'p2996' { 'coca-toolchain-p2996-win-x86_64' }
    }

    $archivePath = "C:\$archiveName.zip"
    Log "Creating archive: $archivePath"

    $archiveDir = "C:\$archiveName"
    $renamed = $false
    if ($INSTALL_PREFIX -ne $archiveDir) {
        if (Test-Path $archiveDir) { Remove-Item $archiveDir -Recurse -Force }
        Rename-Item -Path $INSTALL_PREFIX -NewName $archiveName
        $renamed = $true
    }

    $sevenZip = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($sevenZip) {
        if (Test-Path $archivePath) { Remove-Item $archivePath -Force }
        $parentDir = Split-Path $archiveDir -Parent
        $leafName = Split-Path $archiveDir -Leaf
        Push-Location $parentDir
        try {
            & 7z a -tzip -mx=5 -mmt=on $archivePath ".\$leafName" | Select-Object -Last 5
            if ($LASTEXITCODE -ne 0) { throw "7z archive creation failed" }
        } finally {
            Pop-Location
        }
    } else {
        Log "WARNING: 7z not found, falling back to Compress-Archive"
        Compress-Archive -Path $archiveDir -DestinationPath $archivePath -Force -CompressionLevel Optimal
    }

    if ($renamed) {
        Rename-Item -Path $archiveDir -NewName (Split-Path $INSTALL_PREFIX -Leaf)
    }

    Log "Archive created: $archivePath"
    $size = (Get-Item $archivePath).Length / 1MB
    Log "Archive size: $([math]::Round($size, 1)) MB"
}

# ── Main ─────────────────────────────────────────────────────────────────────
function Main {
    Log "LLVM Windows Stage 2 build starting"
    Log "  VARIANT:          $VARIANT"
    Log "  LLVM_VERSION:     $LLVM_VERSION"
    Log "  STAGE1_DIR:       $STAGE1_DIR"
    Log "  INSTALL_PREFIX:   $INSTALL_PREFIX"
    Log "  BUILD_DIR:        $BUILD_DIR"
    Log "  NPROC:            $NPROC"

    Test-Stage1Toolchain
    Invoke-VsDevShell

    $sourceDir = Get-LLVMSource
    Log "Source directory: $sourceDir"

    Build-LLVMStage2 -SourceDir $sourceDir
    Invoke-PostInstall
    New-Archive

    # Quick verification
    Log "Quick verification:"
    $clang = Join-Path $INSTALL_PREFIX 'bin\clang.exe'
    if (Test-Path $clang) { & $clang --version }
    $lld = Join-Path $INSTALL_PREFIX 'bin\lld-link.exe'
    if (Test-Path $lld) { & $lld --version 2>&1 | Select-Object -First 1 }

    # Verify libc++ is installed
    $libcxxDll = Join-Path $INSTALL_PREFIX 'bin\c++.dll'
    $libcxxLib = Get-ChildItem (Join-Path $INSTALL_PREFIX 'lib') -Filter 'c++*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($libcxxDll -or $libcxxLib) {
        Log "libc++ installed: OK"
    } else {
        # libc++ may install as libc++.lib / libc++.dll
        $libcxxAlt = Get-ChildItem (Join-Path $INSTALL_PREFIX 'lib') -Filter 'libc++*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($libcxxAlt) {
            Log "libc++ installed: $($libcxxAlt.Name)"
        } else {
            Log "WARNING: libc++ artifacts not found in install prefix"
        }
    }

    Log "LLVM Windows Stage 2 build complete!"
}

Main
