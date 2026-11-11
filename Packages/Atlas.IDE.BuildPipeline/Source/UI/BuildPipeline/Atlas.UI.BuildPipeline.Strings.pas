unit Atlas.UI.BuildPipeline.Strings;

// Oberflächentexte des Moduls Build-Pipeline auf Deutsch und Englisch (#1455). Die Sprache
// bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu, ein Sprachwechsel braucht
// daher keine eigene Meldung. Kerntexte bleiben in `Atlas.UI.Strings`.

interface

{$SCOPEDENUMS ON}

type
  TAtlasBuildPipelineTextId = (
    ReleaseCheckCommand, ReleaseNoProject, ReleaseNoConfiguration, ReleaseUnreadable, ReleaseClean, ReleaseFindings,
    ReleaseBlocked, ReleaseOverridden, ReleaseBlockReason, ReleaseOn, ReleaseOff, ReleaseIssueDebugDefine,
    ReleaseIssueDebugInfo, ReleaseIssueDebugInfoInExe, ReleaseIssueStackFrames, ReleaseIssueAssertions,
    ReleaseIssueRangeChecks, ReleaseIssueOverflowChecks, ReleaseIssueMemoryLeaks, ReleaseIssueVersionMissing,
    ReleaseIssueVersionUnchanged, ReleaseIssueOutputFolder, GateFindings, GateBlocked, GateOverridden, GateTimedOut,
    GateBlockReason, BuildSummaryClean, BuildSummaryCounts, BuildSummaryRejected, BuildSummaryRejectedCodes,
    BuildSummaryFailed, BuildSummaryBaselined, SettingsBuildZeroHints, SettingsReleaseGuard,
    SettingsBuildGate, SettingsBuildGateOff, SettingsBuildGateWarn, SettingsBuildGateBlock, SettingsReleaseConfigs,
    SettingsReleaseChecksTitle, SettingsReleaseCheckDebugDefine, SettingsReleaseCheckDebugInfo,
    SettingsReleaseCheckStackFrames, SettingsReleaseCheckAssertions, SettingsReleaseCheckRangeChecks,
    SettingsReleaseCheckOverflowChecks, SettingsReleaseCheckMemoryLeaks, SettingsReleaseCheckVersionInfo,
    SettingsReleaseCheckOutputFolder, SettingsReleaseNotChecked, SettingsReleaseExpectOff, SettingsReleaseExpectOn,
    SettingsBuildGateTimeout, SettingsBuildSummary, SettingsBuildWarningsAsErrors, McpRefusedCancelled,
    McpRefusedShutdown, McpRefusedBusy, McpRefusedForeignBuild, McpRefusedDebugging, McpRefusedKind,
    McpRefusedProjectClosed, McpRefusedConfiguration, McpRefusedPlatform, McpBuildException);

  TAtlasBuildPipelineStrings = class
  public
    class function Text(AId: TAtlasBuildPipelineTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasBuildPipelineTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasBuildPipelineTextId] of string = (
    ('Release-Build prüfen',
     'Release-Build prüfen: Kein Projekt geöffnet.',
     'Release-Build prüfen: %s hat keine Release-Konfiguration („Release“ oder build.releaseConfigs).',
     'Release-Wächter: Die Optionen von %s sind in der IDE nicht lesbar.',
     'Release-Wächter: %s (%s, %s) ohne Befund.',
     'Release-Wächter: %d Befund(e) in %s (%s, %s):',
     'Release-Wächter: Build abgebrochen (build.gate = block). Ein zweiter Build binnen 10 s läuft trotzdem.',
     'Release-Wächter: bewusst übergangen, der Build läuft trotz der Befunde.',
     '%d Befund(e) des Release-Wächters',
     'an',
     'aus',
     'Symbol DEBUG ist definiert. Ändern: Projekt › Optionen › Erzeugen › Delphi-Compiler › Bedingte Definitionen (%s, %s).',
     'Debug-Informationen sind %s (Soll: %s). Ändern: Projekt › Optionen › Erzeugen › Delphi-Compiler › Compilieren › Debuggen › Debug-Informationen (%s, %s).',
     'Debug-Informationen werden in die Ausgabedatei gelinkt. Ändern: Projekt › Optionen › Erzeugen › Delphi-Compiler › Linken › Debug-Informationen (%s, %s).',
     'Stack-Frames sind %s (Soll: %s). Ändern: Projekt › Optionen › Erzeugen › Delphi-Compiler › Compilieren › Codeerzeugung › Stack-Frames (%s, %s).',
     'Assertions sind %s (Soll: %s). Ändern: Projekt › Optionen › Erzeugen › Delphi-Compiler › Compilieren › Debuggen › Assertion (%s, %s).',
     'Bereichsprüfung ist %s (Soll: %s). Ändern: Projekt › Optionen › Erzeugen › Delphi-Compiler › Compilieren › Laufzeitfehler › Bereichsprüfung (%s, %s).',
     'Überlaufprüfung ist %s (Soll: %s). Ändern: Projekt › Optionen › Erzeugen › Delphi-Compiler › Compilieren › Laufzeitfehler › Überlaufprüfung (%s, %s).',
     'ReportMemoryLeaksOnShutdown := True gilt auch im Release. Ändern: Zuweisung in {$IFDEF DEBUG} … {$ENDIF} setzen.',
     'Keine Versionsinformationen. Ändern: Projekt › Optionen › Anwendung › Versionsinformationen › Versionsinformationen in Projekt aufnehmen (%s, %s).',
     'Version %s wie beim letzten Release-Build. Ändern: Projekt › Optionen › Anwendung › Versionsinformationen › Versionsnummer erhöhen (%s, %s).',
     'Ausgabeordner %s wie in Debug. Ändern: Projekt › Optionen › Erzeugen › Delphi-Compiler › Ausgabeverzeichnis (%s, %s).',
     'Prüfung vor dem Compile: %d Fehler in %s (%d geänderte Unit(s) geprüft):',
     'Prüfung vor dem Compile: Compile abgebrochen (build.gate = block). Ein zweiter Compile ohne Änderung binnen 10 s läuft trotzdem.',
     'Prüfung vor dem Compile: bewusst übergangen, der Compile läuft trotz der Fehler.',
     'Prüfung vor dem Compile: Zeitlimit von %d ms (build.gateTimeoutMs) überschritten, der Compile läuft ungeprüft. Dieser Hinweis erscheint einmal je Sitzung.',
     '%d Fehler der Prüfung vor dem Compile',
     'Build %s erfolgreich: 0 Fehler, 0 Warnungen, 0 Hinweise',
     'Build %s erfolgreich, aber %s',
     'Build %s gilt als gescheitert: %s (build.zeroHints)',
     'Build %s gilt als gescheitert: %s; %s zählt als Fehler (build.warningsAsErrors)',
     'Build %s fehlgeschlagen: %d Fehler',
     ' (%d weitere in der Basislinie)',
     'Build nur ohne Warnungen und Hinweise als erfolgreich werten (build.zeroHints)',
     'Release-Build-Wächter: vor make und build in einer Release-Konfiguration die Projektoptionen prüfen (build.releaseGuard)',
     'Prüfung vor dem Compile und Release-Wächter (build.gate)',
     'keine Prüfung vor dem Compile, Release-Wächter meldet nur (off)',
     'melden (warn)',
     'Build abbrechen (block)',
     'Release-Konfigurationen, durch Komma getrennt; „Release“ gilt immer (build.releaseConfigs)',
     'Prüfungen (build.releaseChecks)',
     'Symbol DEBUG definiert',
     'Debug-Informationen',
     'Stack-Frames',
     'Assertions',
     'Bereichsprüfung',
     'Überlaufprüfung',
     'ReportMemoryLeaksOnShutdown := True ohne {$IFDEF DEBUG}',
     'Versionsinformationen fehlen oder unverändert seit dem letzten Release-Build',
     'Ausgabeordner gleich dem der Konfiguration Debug',
     'nicht prüfen',
     'prüfen, Soll: aus',
     'prüfen, Soll: an',
     'Zeitlimit der Prüfung vor dem Compile in ms (build.gateTimeoutMs)',
     'Zusammenfassung nach jedem Build (build.summary)',
     'Codes, die als Fehler zählen (build.warningsAsErrors, z. B. W1035, H2164)',
     'Ein Teilnehmer hat den Build abgebrochen',
     'Atlas wurde in der IDE beendet',
     'Atlas baut in der IDE schon ein Projekt',
     'In der IDE läuft schon ein Build oder eine Compilerprüfung',
     'In der IDE läuft der Debugger',
     'Nur make, build und check sind möglich',
     'Das Projekt %s ist in der IDE nicht offen',
     'Das Projekt kennt die Konfiguration %s nicht',
     'Die Plattform %s ist im Projekt nicht aktiviert',
     'Build in der IDE fehlgeschlagen: %s'),
    ('Check release build',
     'Check release build: No project is open.',
     'Check release build: %s has no release configuration (“Release” or build.releaseConfigs).',
     'Release guard: The options of %s cannot be read in the IDE.',
     'Release guard: %s (%s, %s) has no findings.',
     'Release guard: %d finding(s) in %s (%s, %s):',
     'Release guard: Build cancelled (build.gate = block). A second build within 10 s runs anyway.',
     'Release guard: deliberately overridden, the build runs despite the findings.',
     '%d release guard finding(s)',
     'on',
     'off',
     'Symbol DEBUG is defined. Change: Project › Options › Building › Delphi Compiler › Conditional defines (%s, %s).',
     'Debug information is %s (expected: %s). Change: Project › Options › Building › Delphi Compiler › Compiling › Debugging › Debug information (%s, %s).',
     'Debug information is linked into the output file. Change: Project › Options › Building › Delphi Compiler › Linking › Debug information (%s, %s).',
     'Stack frames are %s (expected: %s). Change: Project › Options › Building › Delphi Compiler › Compiling › Code generation › Stack frames (%s, %s).',
     'Assertions are %s (expected: %s). Change: Project › Options › Building › Delphi Compiler › Compiling › Debugging › Assertions (%s, %s).',
     'Range checking is %s (expected: %s). Change: Project › Options › Building › Delphi Compiler › Compiling › Runtime errors › Range checking (%s, %s).',
     'Overflow checking is %s (expected: %s). Change: Project › Options › Building › Delphi Compiler › Compiling › Runtime errors › Overflow checking (%s, %s).',
     'ReportMemoryLeaksOnShutdown := True also applies in release. Change: put the assignment inside {$IFDEF DEBUG} … {$ENDIF}.',
     'No version information. Change: Project › Options › Application › Version Info › Include version information in project (%s, %s).',
     'Version %s as in the last release build. Change: Project › Options › Application › Version Info › increase the version number (%s, %s).',
     'Output folder %s as in Debug. Change: Project › Options › Building › Delphi Compiler › Output directory (%s, %s).',
     'Check before compiling: %d error(s) in %s (%d changed unit(s) checked):',
     'Check before compiling: compile cancelled (build.gate = block). A second compile without changes within 10 s runs anyway.',
     'Check before compiling: deliberately overridden, the compile runs despite the errors.',
     'Check before compiling: time limit of %d ms (build.gateTimeoutMs) exceeded, the compile runs unchecked. This notice appears once per session.',
     '%d error(s) of the check before compiling',
     'Build %s succeeded: 0 errors, 0 warnings, 0 hints',
     'Build %s succeeded, but %s',
     'Build %s counts as failed: %s (build.zeroHints)',
     'Build %s counts as failed: %s; %s counts as an error (build.warningsAsErrors)',
     'Build %s failed: %d error(s)',
     ' (%d more in the baseline)',
     'Count a build as successful only without warnings and hints (build.zeroHints)',
     'Release build guard: check the project options before make and build in a release configuration (build.releaseGuard)',
     'Check before compiling and release guard (build.gate)',
     'no check before compiling, release guard only reports (off)',
     'report (warn)',
     'cancel the build (block)',
     'Release configurations, separated by commas; “Release” always counts (build.releaseConfigs)',
     'Checks (build.releaseChecks)',
     'Symbol DEBUG defined',
     'Debug information',
     'Stack frames',
     'Assertions',
     'Range checking',
     'Overflow checking',
     'ReportMemoryLeaksOnShutdown := True without {$IFDEF DEBUG}',
     'Version information missing or unchanged since the last release build',
     'Output folder same as in the Debug configuration',
     'do not check',
     'check, expected: off',
     'check, expected: on',
     'Time limit of the check before compiling in ms (build.gateTimeoutMs)',
     'Summary after every build (build.summary)',
     'Codes that count as errors (build.warningsAsErrors, e.g. W1035, H2164)',
     'A participant cancelled the build',
     'Atlas was shut down in the IDE',
     'Atlas is already building a project in the IDE',
     'A build or compiler check is already running in the IDE',
     'The debugger is running in the IDE',
     'Only make, build and check are possible',
     'The project %s is not open in the IDE',
     'The project has no configuration %s',
     'The platform %s is not enabled in the project',
     'Build in the IDE failed: %s'));

{ TAtlasBuildPipelineStrings }

class function TAtlasBuildPipelineStrings.Text(AId: TAtlasBuildPipelineTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasBuildPipelineStrings.Fmt(AId: TAtlasBuildPipelineTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
