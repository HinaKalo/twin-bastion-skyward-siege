param(
    [Parameter(Position = 0)]
    [string]$Mode = "play"
)
$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
switch ($Mode.ToLower()) {
    "test"   { & godot --headless --path $Root --script res://tests/run_tests.gd }
    "editor" { & godot --path $Root --editor }
    "build"  { & "$Root\build_windows.ps1" }
    default  { & godot --path $Root }
}
