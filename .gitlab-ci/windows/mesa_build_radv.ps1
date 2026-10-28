# Minimal RADV-only Windows MSVC build, official style.
# Variant of mesa_build.ps1: same dirs, same MSVC init, same install/test flow.
# Only the meson driver/feature flags are reduced to RADV.
# See .gitlab-ci/build/gitlab-ci.yml job windows-msvc-radv.

# Clear CI_COMMIT_MESSAGE and CI_COMMIT_DESCRIPTION for please meson
# when the commit message is complicated
$env:CI_COMMIT_MESSAGE=""
$env:CI_COMMIT_DESCRIPTION=""

# force the CA cert cache to be rebuilt, in case Meson tries to access anything
Write-Host "Refreshing Windows TLS CA cache"
(New-Object System.Net.WebClient).DownloadString("https://github.com") >$null

$env:PYTHONUTF8=1

Get-Date
Write-Host "Compiling Mesa (RADV-only)"
$builddir = New-Item -Force -ItemType Directory -Name "_build"
$installdir = New-Item -Force -ItemType Directory -Name "_install"
$builddir=$builddir.FullName
$installdir=$installdir.FullName
$sourcedir=$PWD

Remove-Item -Recurse -Force $builddir
Remove-Item -Recurse -Force $installdir
New-Item -ItemType Directory -Path $builddir
New-Item -ItemType Directory -Path $installdir

Write-Output "*" > $builddir\.gitignore
Write-Output "*" > $installdir\.gitignore

Write-Output builddir:$builddir
Write-Output installdir:$installdir
Write-Output sourcedir:$sourcedir

$vcvars_ver_arg="$args"
$MyPath = $MyInvocation.MyCommand.Path | Split-Path -Parent
. "$MyPath\mesa_init_msvc.ps1" "$vcvars_ver_arg"

$depsInstallPath="C:\mesa-deps"

# RADV needs glslangValidator (meson.build: with_bvh). Present in the
# Dockerfile_build image via mesa_deps_vulkan_sdk.ps1, but missing on
# bare machines. Bootstrap the official SDK instead of failing at
# meson.build find_program with a bare ERROR.
if (-not (Get-Command glslangValidator -ErrorAction SilentlyContinue)) {
  Write-Host "glslangValidator not found, installing Vulkan SDK"
  . "$MyPath\mesa_deps_vulkan_sdk.ps1"
  if (!$?) {
    Write-Host "Failed to install Vulkan SDK"
    Exit 1
  }
  $env:PATH = "C:\VulkanSDK\$env:VULKAN_SDK_VERSION\Bin;$env:PATH"
}
& glslangValidator --version
if (!$?) {
  Write-Host "glslangValidator still not available"
  Exit 1
}

Push-Location $builddir

meson setup `
--default-library=shared `
--buildtype=release `
--wrap-mode=nodownload `
-Db_ndebug=false `
-Db_vscrt=mt `
-Dc_args=/wd4319 `
--cmake-prefix-path="$depsInstallPath" `
--pkg-config-path="$depsInstallPath\lib\pkgconfig;$depsInstallPath\share\pkgconfig" `
--prefix="$installdir" `
-Dllvm=enabled `
-Dshared-llvm=disabled `
-Dvulkan-drivers=amd `
-Dgallium-drivers="" `
-Dplatforms=windows `
-Dopengl=false `
-Dgles1=disabled `
-Dgles2=disabled `
-Dglx=disabled `
-Degl=disabled `
-Dgbm=disabled `
-Dglvnd=disabled `
-Dgallium-va=disabled `
-Dgallium-d3d10umd=false `
-Dgallium-mediafoundation=disabled `
-Dgallium-rusticl=false `
-Dmicrosoft-clc=disabled `
-Dspirv-to-dxil=false `
-Dbuild-tests=true `
-Dwerror=true `
-Dwarning_level=2 `
$env:EXTRA_MESON_ARGS `
$sourcedir && `
meson install && `
meson test --num-processes 32 --print-errorlogs

$buildstatus = $?
Pop-Location

Get-Date

if (!$buildstatus) {
  Write-Host "Mesa build or test failed"
  Exit 1
}

Get-ChildItem -Recurse -Filter "ci" | Get-ChildItem -Include "*.txt","*.toml" | Copy-Item -Destination $installdir
