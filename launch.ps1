param(
    [Parameter(Position = 0)]
    [string]$Mode = "play",
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)
$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
switch ($Mode.ToLower()) {
    "test"    { & godot --headless --path $Root --script res://tests/run_tests.gd }
    "balance" { & godot --headless --path $Root --script res://tests/balance_sim.gd -- @Rest }
    "shots"   { & godot --path $Root --script res://tools/screenshot_tour.gd -- @Rest }
    "editor"  { & godot --path $Root --editor }
    "build"   { & "$Root\build_windows.ps1" }
    default   { & godot --path $Root }
}
