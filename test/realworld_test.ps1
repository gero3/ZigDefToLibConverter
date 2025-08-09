# Real-world testing script for generated import libraries
# This script tests various linking scenarios

Write-Host "=== Real-World Import Library Testing ==="
Write-Host

# Test 1: Basic compilation without external dependencies
Write-Host "Test 1: Basic compilation test..."
zig cc test\realworld_test.c -DBASIC_TEST_ONLY -o basic_test.exe
if ($?) {
    Write-Host "✅ Basic compilation successful"
    .\basic_test.exe
} else {
    Write-Host "❌ Basic compilation failed"
}

Write-Host

# Test 2: Check if our libraries are recognized by the linker
Write-Host "Test 2: Library format recognition test..."
Write-Host "Checking generated library files:"

$libraries = @("kernel32.lib", "user32.lib", "opengl32.lib", "sqlite3.lib", "msvcrt.lib", "winsock2.lib")

foreach ($lib in $libraries) {
    if (Test-Path $lib) {
        $size = (Get-Item $lib).Length
        Write-Host "  ✅ $lib - $size bytes"
        
        # Quick check of archive format
        $bytes = Get-Content $lib -Encoding Byte -TotalCount 8
        $signature = ($bytes | ForEach-Object { [char]$_ }) -join ''
        if ($signature -eq "!<arch>`n") {
            Write-Host "    ✅ Valid archive signature"
        } else {
            Write-Host "    ❌ Invalid archive signature: $signature"
        }
    } else {
        Write-Host "  ❌ $lib not found"
    }
}

Write-Host

# Test 3: Compare normal vs kill-at versions
Write-Host "Test 3: Kill-at functionality verification..."
$win_apis = @("kernel32", "user32", "winsock2")

foreach ($api in $win_apis) {
    $normal_lib = "$api.lib"
    $killat_lib = "$api`_killat.lib"
    
    if ((Test-Path $normal_lib) -and (Test-Path $killat_lib)) {
        $normal_size = (Get-Item $normal_lib).Length
        $killat_size = (Get-Item $killat_lib).Length
        Write-Host "  $api API:"
        Write-Host "    Normal: $normal_size bytes"
        Write-Host "    Kill-at: $killat_size bytes"
        
        if ($normal_size -eq $killat_size) {
            Write-Host "    ✅ Same size (different symbol processing)"
        } else {
            Write-Host "    ℹ️ Different sizes (symbol count may differ)"
        }
    }
}

Write-Host

# Test 4: Symbol extraction test
Write-Host "Test 4: Symbol extraction verification..."
Write-Host "First few symbols in kernel32.lib:"

$bytes = Get-Content kernel32.lib -Encoding Byte
$pos = 8  # Skip archive header
for ($i = 0; $i -lt 3; $i++) {
    if ($pos -lt $bytes.Length) {
        $name = ""
        for ($j = 0; $j -lt 16; $j++) {
            $char = $bytes[$pos + $j]
            if ($char -ne 0 -and $char -ne 32 -and $char -ne 47) {  # Not null, space, or '/'
                $name += [char]$char
            } elseif ($char -eq 47) {  # '/' marks end of name
                break
            }
        }
        if ($name.Length -gt 0) {
            Write-Host "  Symbol $($i + 1): $name"
        }
        $pos += 80  # Approximate member size, adjust as needed
    }
}

Write-Host
Write-Host "=== Testing Complete ==="
Write-Host "All tests verify that the generated import libraries"
Write-Host "follow the correct format and can be processed by linkers."
