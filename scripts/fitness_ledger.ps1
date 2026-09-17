param(
    [ValidateSet('status', 'confirm', 'start', 'finish', 'correct-duration', 'rebuild-log')] [string]$Action = 'status',
    [double]$StartPercent = -1,
    [double]$EndPercent = -1,
    [double]$ConsumedBeforeResetPercent = 0,
    [string]$Model = 'unknown',
    [string]$Reasoning = 'unknown',
    [double]$ModelFactor = -1,
    [string]$StartedAt = '',
    [double]$DurationMinutes = -1,
    [switch]$Provisional,
    [string]$ProjectRoot = '',
    [string]$LedgerPath = '',
    [string]$LogPath = '',
    [string]$NotesPath = ''
)

if (-not $LedgerPath) {
    $search = if ($ProjectRoot) { (Resolve-Path -LiteralPath $ProjectRoot).Path } else { (Get-Location).Path }
    $projectConfig = $null
    $agentsMarker = $null
    while ($true) {
        $candidate = Join-Path $search 'SPEC\project.json'
        if (Test-Path -LiteralPath $candidate) { $projectConfig = $candidate; break }
        $agentsCandidate = Join-Path $search 'AGENTS.md'
        if (-not $agentsMarker -and (Test-Path -LiteralPath $agentsCandidate)) {
            $agentsText = Get-Content -LiteralPath $agentsCandidate -Raw -Encoding utf8
            if ($agentsText -match '(?i)five-hour-fitness') { $agentsMarker = $agentsCandidate }
        }
        $parent = Split-Path -Parent $search
        if (-not $parent -or $parent -eq $search) { break }
        $search = $parent
    }
    if ($projectConfig) {
        $config = Get-Content -LiteralPath $projectConfig -Raw -Encoding utf8 | ConvertFrom-Json
        $projectRoot = Split-Path -Parent (Split-Path -Parent $projectConfig)
        $logsDir = if ($config.logsDir) { [string]$config.logsDir } else { 'Логи' }
    } elseif ($agentsMarker) {
        $projectRoot = Split-Path -Parent $agentsMarker
        $logsDir = 'Логи'
    } else {
        $projectRoot = if ($ProjectRoot) { $search } else { (Get-Location).Path }
        $logsDir = 'Логи'
    }
    $LedgerPath = Join-Path (Join-Path $projectRoot $logsDir) 'five-hour-fitness.json'
}

$ledgerDirectory = Split-Path -Parent $LedgerPath
if (-not (Test-Path -LiteralPath $ledgerDirectory)) { New-Item -ItemType Directory -Path $ledgerDirectory -Force | Out-Null }
if (-not $LogPath) { $LogPath = Join-Path $ledgerDirectory 'five-hour-fitness-log.md' }
if (-not $NotesPath) { $NotesPath = Join-Path $ledgerDirectory 'five-hour-fitness-notes.md' }

$BenchmarkName = 'DeepSWE'
$BenchmarkVersion = 'v1.1'
$BenchmarkSnapshot = '2026-09-03'
$BenchmarkFactorMethod = 'best-configuration-cost-per-success'
$BenchmarkReferenceConfiguration = 'gpt-5.6-sol[max]'
$BenchmarkSource = 'https://deepswe.datacurve.ai/'
$BenchmarkArtifact = 'https://deepswe.datacurve.ai/artifacts/v1.1/leaderboard-live.json'

function Add-DefaultProperty($Object, [string]$Name, $Value) {
    if (-not $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}
function Resolve-ModelFactor([string]$ModelName, [double]$ExplicitFactor) {
    if ($ExplicitFactor -gt 0) { return [math]::Round($ExplicitFactor, 3) }
    if ($ModelName -match '(?i)gpt-5\.6-luna|\bluna\b') { return 9.7 }
    return 1.0
}
function Resolve-FactorStatus([string]$ModelName) {
    if ($ModelName -match '(?i)gpt-5\.6-sol|\bsol\b|gpt-5\.6-luna|\bluna\b') { return 'benchmark-derived' }
    return 'fallback'
}
function Format-Number([double]$Value) {
    return $Value.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
}
function Format-Duration([int]$Seconds) {
    $span = [timespan]::FromSeconds($Seconds)
    $hours = [int][math]::Floor($span.TotalHours)
    return '{0:D2}:{1:D2}:{2:D2}' -f $hours, $span.Minutes, $span.Seconds
}
function Convert-ToDateTimeOffset($Value) {
    if ($Value -is [datetimeoffset]) { return $Value }
    if ($Value -is [datetime]) { return [datetimeoffset]$Value }
    return [datetimeoffset]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

if (Test-Path -LiteralPath $LedgerPath) {
    $ledger = Get-Content -LiteralPath $LedgerPath -Raw -Encoding utf8 | ConvertFrom-Json
} else {
    $ledger = [pscustomobject]@{
        schemaVersion = 4; pendingConfirmation = $false; pendingExercises = $null; activeSession = $null
        cumulativeFiveHourPercent = 0.0; cumulativeExercisePercent = 0.0; totalEstimatedCalories = 0.0
        assigned = [pscustomobject]@{ pushUps = 0; squats = 0; abdominalRepetitions = 0; dumbbellCurlsPerArm = 0 }
        modelConversionFactors = [pscustomobject]@{ 'gpt-5.6-sol' = 1.0; 'gpt-5.6-luna' = 9.7 }
        sessions = @()
    }
}
Add-DefaultProperty $ledger 'activeSession' $null
Add-DefaultProperty $ledger 'totalEstimatedCalories' 0.0
Add-DefaultProperty $ledger 'cumulativeFiveHourPercent' 0.0
Add-DefaultProperty $ledger 'cumulativeExercisePercent' ([double]$ledger.cumulativeFiveHourPercent)
Add-DefaultProperty $ledger 'modelConversionFactors' ([pscustomobject]@{ 'gpt-5.6-sol' = 1.0; 'gpt-5.6-luna' = 9.7 })
$ledger.schemaVersion = 4

function Save-Ledger {
    $json = $ledger | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($LedgerPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
function Ensure-LogIds {
    $rowNumber = 0
    foreach ($session in @($ledger.sessions)) {
        if (-not $session.PSObject.Properties['startedAt']) { continue }
        $rowNumber++
        if (-not $session.PSObject.Properties['logId']) {
            $session | Add-Member -NotePropertyName logId -NotePropertyValue ('S{0:D3}' -f $rowNumber)
        }
    }
}
function Get-AutoTime($Session, [datetimeoffset]$Started) {
    if ($Session.PSObject.Properties['autoDurationSeconds']) { return Format-Duration ([int]$Session.autoDurationSeconds) }
    if ($Session.PSObject.Properties['measurementFinishedAt']) {
        $measured = Convert-ToDateTimeOffset $Session.measurementFinishedAt
        return Format-Duration ([int][math]::Round(($measured - $Started).TotalSeconds))
    }
    if (([string]$Session.durationSource) -notmatch '^codex-ui') {
        if ($Session.PSObject.Properties['durationSeconds']) { return Format-Duration ([int]$Session.durationSeconds) }
        return Format-Duration ([int][math]::Round(([double]$Session.durationMinutes) * 60))
    }
    return ''
}
function Get-UiTime($Session) {
    if ($Session.PSObject.Properties['uiDurationSeconds']) { return Format-Duration ([int]$Session.uiDurationSeconds) }
    if ($Session.PSObject.Properties['uiDurationMinutes']) { return Format-Duration ([int][math]::Round(([double]$Session.uiDurationMinutes) * 60)) }
    if (([string]$Session.durationSource) -match '^codex-ui') {
        if ($Session.PSObject.Properties['durationSeconds']) { return Format-Duration ([int]$Session.durationSeconds) }
        return Format-Duration ([int][math]::Round(([double]$Session.durationMinutes) * 60))
    }
    return ''
}
function Write-Log {
    Ensure-LogIds
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Five-hour fitness log')
    $lines.Add('')
    $lines.Add('| ID | Date | Started | Finished | Auto time | UI time | Model | Reasoning | Start | End | Used | Sol eq. | Push-ups | Squats | Abs | Arms | kcal |')
    $lines.Add('|---|---|---:|---:|---:|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
    foreach ($session in @($ledger.sessions)) {
        if (-not $session.PSObject.Properties['startedAt']) { continue }
        $started = Convert-ToDateTimeOffset $session.startedAt
        $finished = Convert-ToDateTimeOffset $session.finishedAt
        $raw = if ($session.PSObject.Properties['rawDeltaPercent']) { [double]$session.rawDeltaPercent } else { [double]$session.deltaPercent }
        $equivalent = if ($session.PSObject.Properties['exerciseEquivalentPercent']) { [double]$session.exerciseEquivalentPercent } else { $raw }
        $auto = Get-AutoTime $session $started
        $ui = Get-UiTime $session
        $row = '| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} | {13} | {14} | {15} | {16} |' -f $session.logId, $started.ToString('dd.MM.yyyy'), $started.ToString('HH:mm:ss'), $finished.ToString('HH:mm:ss'), $auto, $ui, ([string]$session.model).Replace('|','/'), ([string]$session.reasoning).Replace('|','/'), (Format-Number ([double]$session.startPercent)), (Format-Number ([double]$session.endPercent)), (Format-Number $raw), (Format-Number $equivalent), $session.exercises.pushUps, $session.exercises.squats, $session.exercises.abdominalRepetitions, $session.exercises.dumbbellCurlsPerArm, (Format-Number ([math]::Round([double]$session.estimatedCalories, 0, [MidpointRounding]::AwayFromZero)))
        $lines.Add($row)
    }
    [IO.File]::WriteAllText($LogPath, ($lines -join [Environment]::NewLine) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
function Write-CalibrationNote($Session) {
    $status = Resolve-FactorStatus ([string]$Session.model)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('## ' + [string]$Session.logId)
    $lines.Add('')
    $lines.Add('- Benchmark: ' + $BenchmarkName)
    $lines.Add('- Benchmark version: ' + $BenchmarkVersion)
    $lines.Add('- Benchmark snapshot: ' + $BenchmarkSnapshot)
    $lines.Add('- Factor method: ' + $BenchmarkFactorMethod)
    $lines.Add('- Reference configuration: ' + $BenchmarkReferenceConfiguration)
    $lines.Add('- Applied factor: ' + (Format-Number ([double]$Session.modelFactor)))
    $lines.Add('- Factor status: ' + $status)
    $lines.Add('- Model: ' + [string]$Session.model)
    $lines.Add('- Reasoning: ' + [string]$Session.reasoning)
    $lines.Add('- Usage delta: ' + (Format-Number ([double]$Session.rawDeltaPercent)))
    $lines.Add('- Sol equivalent: ' + (Format-Number ([double]$Session.exerciseEquivalentPercent)))
    $lines.Add('- Source: ' + $BenchmarkSource)
    $lines.Add('- Artifact: ' + $BenchmarkArtifact)
    $block = ($lines -join [Environment]::NewLine) + [Environment]::NewLine + [Environment]::NewLine
    if (Test-Path -LiteralPath $NotesPath) {
        $existing = Get-Content -LiteralPath $NotesPath -Raw -Encoding utf8
        if ($existing -match ('(?m)^## ' + [regex]::Escape([string]$Session.logId) + '\s*$')) { return }
        $content = $existing.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block
    } else {
        $content = '# Five-hour fitness notes' + [Environment]::NewLine + [Environment]::NewLine + $block
    }
    [IO.File]::WriteAllText($NotesPath, $content, [Text.UTF8Encoding]::new($false))
}

if ($Action -eq 'confirm') {
    $ledger.pendingConfirmation = $false; $ledger.pendingExercises = $null
    Save-Ledger
    $ledger | ConvertTo-Json -Depth 10
    exit 0
}
if ($Action -eq 'rebuild-log') {
    Write-Log; Save-Ledger
    [pscustomobject]@{ rows = @($ledger.sessions | Where-Object { $_.PSObject.Properties['startedAt'] }).Count; logPath = $LogPath } | ConvertTo-Json
    exit 0
}
if ($Action -eq 'correct-duration') {
    if ($DurationMinutes -le 0) { throw 'DurationMinutes must be greater than zero.' }
    $sessions = @($ledger.sessions)
    if ($sessions.Count -eq 0) { throw 'There is no completed session to correct.' }
    $session = $sessions[-1]
    $roundedDuration = [math]::Round($DurationMinutes, 1)
    $session | Add-Member uiDurationMinutes $roundedDuration -Force
    $session | Add-Member uiDurationSeconds ([int][math]::Round($DurationMinutes * 60)) -Force
    $session | Add-Member uiDurationSource 'codex-ui' -Force
    if ($Model -ne 'unknown') { $session.model = $Model }
    if ($Reasoning -ne 'unknown') { $session.reasoning = $Reasoning }
    Write-Log; Save-Ledger
    [pscustomobject]@{ uiDurationMinutes = $roundedDuration; uiDurationSeconds = [int][math]::Round($DurationMinutes * 60); durationSource = 'codex-ui'; logPath = $LogPath } | ConvertTo-Json
    exit 0
}
if ($Action -eq 'start') {
    if ($ledger.pendingConfirmation -and -not $Provisional) { throw 'Previous exercise assignment has not been confirmed.' }
    if ($StartPercent -lt 0 -or $StartPercent -gt 100) { throw 'StartPercent must be between 0 and 100.' }
    $startTime = if ($StartedAt) { Convert-ToDateTimeOffset $StartedAt } else { [datetimeoffset]::Now }
    $factor = Resolve-ModelFactor $Model $ModelFactor
    $ledger.activeSession = [pscustomobject]@{ startedAt = $startTime.ToString('o'); startPercent = $StartPercent; model = $Model; reasoning = $Reasoning; modelFactor = $factor }
    Save-Ledger
    $ledger.activeSession | ConvertTo-Json -Depth 4
    exit 0
}
if ($Action -eq 'finish') {
    if ($EndPercent -lt 0 -or $EndPercent -gt 100) { throw 'EndPercent must be between 0 and 100.' }
    $wasPending = [bool]$ledger.pendingConfirmation
    if ($ledger.activeSession) {
        $start = [double]$ledger.activeSession.startPercent
        $startTime = Convert-ToDateTimeOffset $ledger.activeSession.startedAt
        $sessionModel = [string]$ledger.activeSession.model
        $sessionReasoning = [string]$ledger.activeSession.reasoning
        $factor = if ($ledger.activeSession.PSObject.Properties['modelFactor']) { [double]$ledger.activeSession.modelFactor } else { Resolve-ModelFactor $sessionModel $ModelFactor }
    } else {
        if ($StartPercent -lt 0 -or $StartPercent -gt 100) { throw 'No active session. StartPercent is required.' }
        $start = $StartPercent
        $startTime = if ($StartedAt) { Convert-ToDateTimeOffset $StartedAt } else { [datetimeoffset]::Now }
        $sessionModel = $Model; $sessionReasoning = $Reasoning
        $factor = Resolve-ModelFactor $sessionModel $ModelFactor
    }
    $finishedAt = [datetimeoffset]::Now
    if ($ConsumedBeforeResetPercent -lt 0 -or $ConsumedBeforeResetPercent -gt 100) { throw 'ConsumedBeforeResetPercent must be between 0 and 100.' }
    $windowReset = $EndPercent -lt $start
    $rawDelta = if ($windowReset) { $ConsumedBeforeResetPercent + $EndPercent } else { $EndPercent - $start }
    $equivalent = [math]::Round($rawDelta * $factor, 3)
    $ledger.cumulativeFiveHourPercent = [math]::Round(([double]$ledger.cumulativeFiveHourPercent + $rawDelta), 3)
    $ledger.cumulativeExercisePercent = [math]::Round(([double]$ledger.cumulativeExercisePercent + $equivalent), 3)
    $total = [double]$ledger.cumulativeExercisePercent
    $targets = [pscustomobject]@{
        pushUps = [int][math]::Floor(($total * 0.25) + 0.5)
        squats = [int][math]::Floor(($total * 0.50) + 0.5)
        abdominalRepetitions = [int][math]::Floor(($total * 0.50) + 0.5)
        dumbbellCurlsPerArm = [int][math]::Floor(($total * 0.25) + 0.5)
    }
    $exercise = [pscustomobject]@{
        pushUps = $targets.pushUps - [int]$ledger.assigned.pushUps
        squats = $targets.squats - [int]$ledger.assigned.squats
        abdominalRepetitions = $targets.abdominalRepetitions - [int]$ledger.assigned.abdominalRepetitions
        dumbbellCurlsPerArm = $targets.dumbbellCurlsPerArm - [int]$ledger.assigned.dumbbellCurlsPerArm
    }
    $ledger.assigned = $targets
    $calories = [int][math]::Round(($exercise.pushUps * 0.5) + ($exercise.squats * 0.4) + ($exercise.abdominalRepetitions * 0.3) + ($exercise.dumbbellCurlsPerArm * 0.3), 0, [MidpointRounding]::AwayFromZero)
    $ledger.totalEstimatedCalories = [math]::Round(([double]$ledger.totalEstimatedCalories + $calories), 1)
    $durationSeconds = [int][math]::Round(($finishedAt - $startTime).TotalSeconds)
    $duration = [math]::Round($durationSeconds / 60, 1)
    $totalAssigned = $exercise.pushUps + $exercise.squats + $exercise.abdominalRepetitions + $exercise.dumbbellCurlsPerArm
    $ledger.pendingConfirmation = ($totalAssigned -gt 0) -or ($Provisional -and $wasPending)
    $ledger.pendingExercises = if ($totalAssigned -gt 0) { $exercise } else { $null }
    $ledger.activeSession = $null
    $session = [pscustomobject]@{
        startedAt = $startTime.ToString('o'); finishedAt = $finishedAt.ToString('o')
        durationMinutes = $duration; durationSeconds = $durationSeconds; autoDurationMinutes = $duration; autoDurationSeconds = $durationSeconds; durationSource = 'ledger-timer'
        model = $sessionModel; reasoning = $sessionReasoning; modelFactor = $factor
        benchmark = $BenchmarkName; benchmarkVersion = $BenchmarkVersion; benchmarkSnapshot = $BenchmarkSnapshot
        factorMethod = $BenchmarkFactorMethod; factorReference = $BenchmarkReferenceConfiguration
        factorStatus = Resolve-FactorStatus $sessionModel; benchmarkSource = $BenchmarkSource; benchmarkArtifact = $BenchmarkArtifact
        startPercent = $start; endPercent = $EndPercent; deltaPercent = $rawDelta; rawDeltaPercent = $rawDelta; exerciseEquivalentPercent = $equivalent
        windowResetDuringSession = $windowReset; consumedBeforeResetPercent = $ConsumedBeforeResetPercent
        exercises = $exercise; estimatedCalories = $calories
    }
    $ledger.sessions = @($ledger.sessions) + $session
    Write-Log; Save-Ledger; Write-CalibrationNote $session
    [pscustomobject]@{
        rawDeltaPercent = $rawDelta; modelFactor = $factor; exerciseEquivalentPercent = $equivalent
        durationMinutes = $duration; durationSeconds = $durationSeconds; durationTime = Format-Duration $durationSeconds; model = $sessionModel; reasoning = $sessionReasoning
        exercises = $exercise; estimatedCalories = $calories; durationSource = 'ledger-timer'
        pendingConfirmation = $ledger.pendingConfirmation; logPath = $LogPath
    } | ConvertTo-Json -Depth 6
    exit 0
}
$ledger | ConvertTo-Json -Depth 10
