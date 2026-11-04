unit Atlas.Core.BuildPipeline.ReleaseGuard;

// Release-Build-Wächter (#533), ohne VCL und Open Tools API: Vor einem Build
// in einer Release-Konfiguration prüft Atlas typische Fehlgriffe in den
// Projektoptionen und meldet sie im Meldungsfenster; mit build.gate = block
// (#529) bricht ein Verstoß den Build ab. Die Optionen liest die IDE-Schicht
// aus der laufenden IDE (#396), nicht aus der .dproj auf der Platte; hier
// liegen nur Entscheidung und Prüfungen, testbar mit gefälschten Optionen.
//
// - Release gilt: Konfiguration „Release“ oder in build.releaseConfigs
//   gelistet (Groß-/Kleinschreibung egal). Geprüft wird vor make und build,
//   auch für Aufträge (Claude Code #261, Schnellaktion „Öffnen und bauen“
//   #764), nie bei der Hintergrundprüfung (#548), Syntaxprüfung, Clean oder
//   Code Insight.
// - Prüfungen (build.releaseChecks), je an/aus, die Compileroptionen mit
//   Sollwert; fehlt eine Option, gilt die Vorgabe des Compilers ($D+, $C+,
//   $W-, $R-, $Q-):
//     debugDefine     Symbol DEBUG in den bedingten Symbolen (DCC_Define)
//     debugInfo       Debug-Informationen (DCC_DebugInformation) und, mit
//                     Sollwert aus, „Mit Debug-Informationen linken“
//                     (DCC_DebugInfoInExe)
//     stackFrames     Stack-Frames (DCC_GenerateStackFrames)
//     assertions      Assertions (DCC_AssertionsAtRuntime)
//     rangeChecks     Bereichsprüfung (DCC_RangeChecking)
//     overflowChecks  Überlaufprüfung (DCC_IntegerOverflowCheck)
//     memoryLeaks     ReportMemoryLeaksOnShutdown := True im Projektquelltext
//                     außerhalb von {$IFDEF DEBUG} bzw. {$IF DEFINED(DEBUG)}
//     versionInfo     keine Versionsinformationen oder dieselbe Version wie
//                     beim letzten erfolgreichen Release-Build derselben
//                     Konfiguration und Plattform (nicht mit automatisch
//                     erhöhter Build-Nummer)
//     outputFolder    Ausgabeordner (DCC_ExeOutput, $(Platform) und $(Config)
//                     eingesetzt) gleich dem der Konfiguration Debug
//   Packages prüft der Wächter ohne memoryLeaks und outputFolder.
// - Textform von build.releaseChecks: durch Komma getrennt „name“ (an),
//   „-name“ (aus), mit Sollwert „name=off“ bzw. „name=on“ (auch „-name=on“).
//   Fehlende Namen gelten mit ihrer Vorgabe (alle an, Sollwerte aus);
//   unbekannte entfallen. Normalized schreibt alle in fester Reihenfolge.
// - Bewusst übergehen (wie #529): Ein zweiter Build desselben Projekts mit
//   denselben Verstößen binnen OverrideMs läuft trotz block; die Meldung sagt
//   das.
// - Regel-IDs (gemeinsam mit dem Prüfregel-Framework #41, soweit sinnvoll):
//   release-debug-define, release-debug-info, … (RuleIds).
// - Die Version jedes erfolgreichen Release-Builds merkt sich die IDE-Schicht
//   in der Projekt-Zusammenfassung (#592, Abschnitt "release").

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.PipelineSettings;

type
{$SCOPEDENUMS ON}
  /// <summary>Art eines Verstoßes; bestimmt Text und Hinweis, wo die Option zu ändern ist.</summary>
  TAtlasReleaseIssue = (DebugDefine, DebugInfo, DebugInfoInExe, StackFrames, Assertions, RangeChecks, OverflowChecks,
    MemoryLeaks, VersionMissing, VersionUnchanged, OutputFolder);
  /// <summary>Ergebnis einer Prüfung vor dem Build.</summary>
  TAtlasReleaseOutcome = (Passed, Reported, Blocked, Overridden);
{$SCOPEDENUMS OFF}

  /// <summary>Einstellungen des Wächters, aus den Plugin-Einstellungen zusammengesetzt.</summary>
  TAtlasReleaseSettings = record
    /// <summary>build.releaseGuard: aus = keine Prüfung, kein Befehl.</summary>
    Enabled: Boolean;
    Gate: TAtlasBuildGate;
    /// <summary>build.releaseConfigs: Konfigurationen, die zusätzlich zu „Release“ als Release gelten.</summary>
    Configurations: TArray<string>;
    Checks: TAtlasReleaseChecks;
    class function Create(AEnabled: Boolean; const AGate, AConfigurations, AChecks: string): TAtlasReleaseSettings;
      static;
    /// <summary>Gilt AConfiguration als Release?</summary>
    function IsRelease(const AConfiguration: string): Boolean;
  end;

  /// <summary>Projektoptionen, wie die IDE sie für den Build verwendet (Rohwerte mit Erbe; '' = nicht gesetzt).
  /// </summary>
  TAtlasReleaseOptions = record
    /// <summary>Absoluter Pfad der .dproj.</summary>
    Project: string;
    Configuration: string;
    Platform: string;
    /// <summary>Bedingte Symbole (DCC_Define) mit geerbten Werten.</summary>
    Defines: TArray<string>;
    /// <summary>DCC_DebugInformation: 0/false = aus, 1 (begrenzt), 2/true = an.</summary>
    DebugInformation: string;
    /// <summary>DCC_DebugInfoInExe („Mit Debug-Informationen linken“).</summary>
    DebugInfoInExe: string;
    /// <summary>DCC_GenerateStackFrames.</summary>
    StackFrames: string;
    /// <summary>DCC_AssertionsAtRuntime.</summary>
    Assertions: string;
    /// <summary>DCC_RangeChecking.</summary>
    RangeChecks: string;
    /// <summary>DCC_IntegerOverflowCheck.</summary>
    OverflowChecks: string;
    /// <summary>VerInfo_IncludeVerInfo.</summary>
    IncludeVersionInfo: string;
    /// <summary>VerInfo_AutoGenVersion bzw. VerInfo_AutoIncVersion (Build-Nummer automatisch erhöhen).</summary>
    AutoIncrementVersion: string;
    /// <summary>VerInfo_Keys („FileVersion=1.2.0.0;…“).</summary>
    VersionKeys: string;
    /// <summary>VerInfo_MajorVer, VerInfo_MinorVer, VerInfo_Release, VerInfo_Build.</summary>
    MajorVersion: string;
    MinorVersion: string;
    ReleaseVersion: string;
    BuildVersion: string;
    /// <summary>DCC_ExeOutput der geprüften Konfiguration.</summary>
    OutputFolder: string;
    /// <summary>Gibt es die Konfiguration Debug? Nur dann gilt DebugOutputFolder.</summary>
    HasDebugConfiguration: Boolean;
    /// <summary>DCC_ExeOutput der Konfiguration Debug für dieselbe Plattform.</summary>
    DebugOutputFolder: string;
    /// <summary>Package (.dpk): ohne memoryLeaks und outputFolder.</summary>
    IsPackage: Boolean;
    /// <summary>Projektquelltext (.dpr) und sein Text, auch ungespeichert; '' = unbekannt.</summary>
    SourceFile: string;
    Source: string;
    /// <summary>Version des letzten erfolgreichen Release-Builds derselben Konfiguration und Plattform; '' = keiner.
    /// </summary>
    LastVersion: string;
  end;

  TAtlasReleaseFinding = record
    Issue: TAtlasReleaseIssue;
    Check: TAtlasReleaseCheck;
    /// <summary>Gefundener Wert (Symbol, Option, Version, Ordner); '' ohne.</summary>
    Value: string;
    /// <summary>Sollwert der Compileroption (nur für Optionen mit Sollwert).</summary>
    Expected: Boolean;
    /// <summary>Fundstelle im Projektquelltext (memoryLeaks); Zeile ab 1, sonst 0.</summary>
    FileName: string;
    Line: Integer;
  end;

  TAtlasReleaseFindings = TArray<TAtlasReleaseFinding>;

  TAtlasReleaseGuard = class
  public const
    /// <summary>Zweiter Build mit denselben Verstößen in dieser Zeit läuft trotz block (wie #529).</summary>
    OverrideMs = 10000;
    DebugConfiguration = 'Debug';
    RuleIds: array[TAtlasReleaseCheck] of string = ('release-debug-define', 'release-debug-info',
      'release-stack-frames', 'release-assertions', 'release-range-checks', 'release-overflow-checks',
      'release-memory-leaks', 'release-version-info', 'release-output-folder');
    /// <summary>Name der Option in den Projektoptionen je Verstoß (für Meldung und Protokoll).</summary>
    OptionNames: array[TAtlasReleaseIssue] of string = ('DCC_Define', 'DCC_DebugInformation', 'DCC_DebugInfoInExe',
      'DCC_GenerateStackFrames', 'DCC_AssertionsAtRuntime', 'DCC_RangeChecking', 'DCC_IntegerOverflowCheck',
      'ReportMemoryLeaksOnShutdown', 'VerInfo_IncludeVerInfo', 'VerInfo_Keys', 'DCC_ExeOutput');
  public
    /// <summary>Prüft der Wächter diesen Lauf? Eingeschaltet, Release, make oder build, keine Hintergrundprüfung.
    /// </summary>
    class function Applies(const ASettings: TAtlasReleaseSettings; const AProject: TAtlasCompileProject): Boolean;
      static;
    /// <summary>Wert einer Schalter-Option: true/1/2 = an, false/0 = aus, sonst ADefault.</summary>
    class function IsOn(const AValue: string; ADefault: Boolean): Boolean; static;
    /// <summary>Version aus FileVersion in VerInfo_Keys, sonst aus Major.Minor.Release.Build (Vorgabe 1.0.0.0);
    /// '' ohne Versionsinformationen.</summary>
    class function VersionOf(const AOptions: TAtlasReleaseOptions): string; static;
    /// <summary>Ausgabeordner mit eingesetztem $(Platform) und $(Config), ohne „.\“ vorn und „\“ hinten; '' =
    /// Projektordner (".").</summary>
    class function ResolveFolder(const AFolder, AConfiguration, APlatform: string): string; static;
    /// <summary>Zeile (ab 1) des ersten ReportMemoryLeaksOnShutdown := True außerhalb von {$IFDEF DEBUG}; 0 =
    /// keine. Kommentare und Strings zählen nicht.</summary>
    class function LeakReportLine(const ASource: string): Integer; static;
    /// <summary>Alle Verstöße der eingeschalteten Prüfungen.</summary>
    class function Evaluate(const ASettings: TAtlasReleaseSettings;
      const AOptions: TAtlasReleaseOptions): TAtlasReleaseFindings; static;
    /// <summary>Schlüssel für „bewusst übergehen“: Projekt, Konfiguration, Plattform und Verstöße.</summary>
    class function FindingsKey(const AOptions: TAtlasReleaseOptions;
      const AFindings: TAtlasReleaseFindings): string; static;
  end;

  TAtlasReleaseSettingsFunc = reference to function: TAtlasReleaseSettings;
  /// <summary>Optionen des Projekts aus der IDE; False, wenn das Projekt nicht lesbar ist (dann keine Prüfung).
  /// </summary>
  TAtlasReleaseReadFunc = reference to function(const AProject: TAtlasCompileProject;
    out AOptions: TAtlasReleaseOptions): Boolean;
  /// <summary>Meldet das Ergebnis (Meldungsfenster, Projekt-Zusammenfassung); liefert bei Blocked den Grund für
  /// den Abbruch.</summary>
  TAtlasReleaseReportFunc = reference to function(const AOptions: TAtlasReleaseOptions;
    const AFindings: TAtlasReleaseFindings; AOutcome: TAtlasReleaseOutcome): string;
  /// <summary>Erfolgreicher Release-Build mit AVersion (Grundlage von „unveränderte Version“).</summary>
  TAtlasReleaseRememberProc = reference to procedure(const AOptions: TAtlasReleaseOptions; const AVersion: string);

  /// <summary>Teilnehmer an den Compile-Ereignissen (#527): prüft vor dem Build und merkt nach dem Erfolg die
  /// Version.</summary>
  TAtlasReleaseGuardParticipant = class(TAtlasCompileParticipant)
  private type
    TPending = record
      Options: TAtlasReleaseOptions;
      Version: string;
    end;
  private
    FSettings: TAtlasReleaseSettingsFunc;
    FRead: TAtlasReleaseReadFunc;
    FReport: TAtlasReleaseReportFunc;
    FRemember: TAtlasReleaseRememberProc;
    FClock: TAtlasClockFunc;
    FPending: TList<TPending>;
    FBlockedKey: string;
    FBlockedAt: Int64;
    function Now_: Int64;
    function PendingIndex(const AFileName: string): Integer;
    function OutcomeOf(const ASettings: TAtlasReleaseSettings; const AOptions: TAtlasReleaseOptions;
      const AFindings: TAtlasReleaseFindings): TAtlasReleaseOutcome;
    procedure DropPending(const AFileName: string);
    procedure AddPending(const AOptions: TAtlasReleaseOptions);
  public
    /// <summary>AClock nil = Uhr des Systems (ms).</summary>
    constructor Create(const ASettings: TAtlasReleaseSettingsFunc; const ARead: TAtlasReleaseReadFunc;
      const AReport: TAtlasReleaseReportFunc; const ARemember: TAtlasReleaseRememberProc;
      const AClock: TAtlasClockFunc);
    destructor Destroy; override;
    function CancelCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean; override;
    procedure ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean; ADurationMs: Int64);
      override;
  end;

implementation

uses
  System.Diagnostics,
  Atlas.Text.Chars,
  Atlas.Core.Versions.Project;

{ TAtlasReleaseSettings }

class function TAtlasReleaseSettings.Create(AEnabled: Boolean; const AGate, AConfigurations,
  AChecks: string): TAtlasReleaseSettings;
begin
  Result.Enabled := AEnabled;
  Result.Gate := TAtlasBuildPipelineSettings.GateOf(AGate);
  Result.Configurations := TAtlasBuildPipelineSettings.ConfigurationList(AConfigurations);
  Result.Checks := TAtlasReleaseChecks.Parse(AChecks);
end;

function TAtlasReleaseSettings.IsRelease(const AConfiguration: string): Boolean;
var
  Name: string;
begin
  Result := SameText(Trim(AConfiguration), TAtlasBuildPipelineSettings.ReleaseConfiguration);
  if Result or (Trim(AConfiguration) = '') then
  begin
    Exit;
  end;
  for Name in Configurations do
  begin
    if SameText(Name, Trim(AConfiguration)) then
    begin
      Exit(True);
    end;
  end;
end;

{ TAtlasReleaseGuard }

class function TAtlasReleaseGuard.Applies(const ASettings: TAtlasReleaseSettings;
  const AProject: TAtlasCompileProject): Boolean;
begin
  Result := ASettings.Enabled and not AProject.Background and (AProject.FileName <> '') and
    ((AProject.Kind = TAtlasCompileKind.Make) or (AProject.Kind = TAtlasCompileKind.Build)) and
    ASettings.IsRelease(AProject.Configuration);
end;

class function TAtlasReleaseGuard.IsOn(const AValue: string; ADefault: Boolean): Boolean;
begin
  Result := TAtlasProjectVersion.IsOn(AValue, ADefault);
end;

class function TAtlasReleaseGuard.VersionOf(const AOptions: TAtlasReleaseOptions): string;
begin
  Result := TAtlasProjectVersion.FromOptions(AOptions.IncludeVersionInfo, AOptions.VersionKeys, AOptions.MajorVersion,
    AOptions.MinorVersion, AOptions.ReleaseVersion, AOptions.BuildVersion);
end;

class function TAtlasReleaseGuard.ResolveFolder(const AFolder, AConfiguration, APlatform: string): string;
begin
  Result := Trim(AFolder);
  Result := StringReplace(Result, '$(Platform)', APlatform, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(Config)', AConfiguration, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
  while Result.StartsWith('.\') do
  begin
    Result := Copy(Result, 3, MaxInt);
  end;
  while (Length(Result) > 1) and Result.EndsWith('\') do
  begin
    Result := Copy(Result, 1, Length(Result) - 1);
  end;
  if (Result = '') or (Result = '.') then
  begin
    Result := '.';
  end;
end;

{$SCOPEDENUMS ON}
type
  /// <summary>Art eines bedingten Blocks für die Leck-Prüfung.</summary>
  TGuardKind = (Neutral, IfDebug, IfNotDebug);
{$SCOPEDENUMS OFF}

  TGuardFrame = record
    Kind: TGuardKind;
    InElse: Boolean;
  end;

function DirectiveKind(const AExpression: string): TGuardKind;
var
  Text: string;
begin
  Text := UpperCase(StringReplace(StringReplace(AExpression, ' ', '', [rfReplaceAll]), #9, '', [rfReplaceAll]));
  if Pos('NOTDEFINED(DEBUG)', Text) > 0 then
  begin
    Result := TGuardKind.IfNotDebug;
  end
  else if Pos('DEFINED(DEBUG)', Text) > 0 then
  begin
    Result := TGuardKind.IfDebug;
  end
  else
  begin
    Result := TGuardKind.Neutral;
  end;
end;

function FrameGuarded(const AFrame: TGuardFrame): Boolean;
begin
  Result := ((AFrame.Kind = TGuardKind.IfDebug) and not AFrame.InElse) or
    ((AFrame.Kind = TGuardKind.IfNotDebug) and AFrame.InElse);
end;

/// <summary>Zeichen eines qualifizierten Bezeichners (System.ReportMemoryLeaksOnShutdown).</summary>
function IsQualifiedChar(AChar: Char): Boolean;
begin
  Result := TTextChars.IsIdentChar(AChar) or (AChar = '.');
end;

type
  /// <summary>Durchlauf durch den Projektquelltext für die Leck-Prüfung: Kommentare, Zeichenketten und
  /// bedingte Blöcke ({$IFDEF DEBUG} …) werden übersprungen und ihre Zeilen mitgezählt.</summary>
  TLeakScanner = record
  private
    FSource: string;
    FIndex: Integer;
    FLength: Integer;
    FLine: Integer;
    FFrames: TArray<TGuardFrame>;
    function Guarded: Boolean;
    function NextIs(AChar: Char): Boolean;
    procedure CountLines(AFrom, ATo: Integer);
    procedure PushFrame(AKind: TGuardKind);
    procedure HandleDirective(const AText: string);
    procedure SkipBlanks;
    procedure SkipLineComment;
    procedure SkipComment(const AClose: string; AOpenLength: Integer);
    procedure SkipString;
    function ReadQualified: string;
    function ScanWord: Integer;
    function Step: Integer;
  public
    /// <summary>Zeile der ersten ungeschützten Zuweisung True; 0 ohne.</summary>
    function Run(const ASource: string): Integer;
  end;

function TLeakScanner.Guarded: Boolean;
var
  Item: TGuardFrame;
begin
  Result := False;
  for Item in FFrames do
  begin
    if FrameGuarded(Item) then
    begin
      Exit(True);
    end;
  end;
end;

function TLeakScanner.NextIs(AChar: Char): Boolean;
begin
  Result := (FIndex < FLength) and (FSource[FIndex + 1] = AChar);
end;

procedure TLeakScanner.CountLines(AFrom, ATo: Integer);
var
  Position: Integer;
begin
  for Position := AFrom to ATo do
  begin
    if FSource[Position] = #10 then
    begin
      Inc(FLine);
    end;
  end;
end;

procedure TLeakScanner.PushFrame(AKind: TGuardKind);
var
  Frame: TGuardFrame;
begin
  Frame.InElse := False;
  Frame.Kind := AKind;
  FFrames := FFrames + [Frame];
end;

/// <summary>Art des Blocks zu {$IFDEF X}/{$IFNDEF X}: DEBUG schützt, alles andere ist neutral.</summary>
function DefineKind(const AArgument: string; ADebugKind: TGuardKind): TGuardKind;
begin
  if SameText(AArgument, 'DEBUG') then
  begin
    Result := ADebugKind;
  end
  else
  begin
    Result := TGuardKind.Neutral;
  end;
end;

procedure TLeakScanner.HandleDirective(const AText: string);
var
  Space: Integer;
  Name, Argument: string;
begin
  Space := Pos(' ', AText + ' ');
  Name := UpperCase(Copy(AText, 1, Space - 1));
  Argument := Trim(Copy(AText, Space + 1, MaxInt));
  if Name = 'IFDEF' then
  begin
    PushFrame(DefineKind(Argument, TGuardKind.IfDebug));
  end
  else if Name = 'IFNDEF' then
  begin
    PushFrame(DefineKind(Argument, TGuardKind.IfNotDebug));
  end
  else if Name = 'IF' then
  begin
    PushFrame(DirectiveKind(Argument));
  end
  else if Name = 'IFOPT' then
  begin
    PushFrame(TGuardKind.Neutral);
  end
  else if System.Length(FFrames) = 0 then
  begin
    Exit;
  end
  else if Name = 'ELSEIF' then
  begin
    FFrames[High(FFrames)].Kind := DirectiveKind(Argument);
    FFrames[High(FFrames)].InElse := False;
  end
  else if Name = 'ELSE' then
  begin
    FFrames[High(FFrames)].InElse := True;
  end
  else if (Name = 'ENDIF') or (Name = 'IFEND') then
  begin
    SetLength(FFrames, System.Length(FFrames) - 1);
  end;
end;

procedure TLeakScanner.SkipBlanks;
begin
  while (FIndex <= FLength) and CharInSet(FSource[FIndex], [' ', #9, #13, #10]) do
  begin
    if FSource[FIndex] = #10 then
    begin
      Inc(FLine);
    end;
    Inc(FIndex);
  end;
end;

procedure TLeakScanner.SkipLineComment;
begin
  while (FIndex <= FLength) and (FSource[FIndex] <> #10) do
  begin
    Inc(FIndex);
  end;
end;

/// <summary>Kommentar ab FIndex bis AClose; mit $ direkt nach der Öffnung eine Compileranweisung.</summary>
procedure TLeakScanner.SkipComment(const AClose: string; AOpenLength: Integer);
var
  Start, Found: Integer;
begin
  Start := FIndex;
  Found := Pos(AClose, FSource, FIndex + AOpenLength);
  if Found = 0 then
  begin
    Found := FLength;
  end;
  if (FIndex + AOpenLength <= FLength) and (FSource[FIndex + AOpenLength] = '$') then
  begin
    HandleDirective(Trim(Copy(FSource, FIndex + AOpenLength + 1, Found - FIndex - AOpenLength - 1)));
  end;
  CountLines(Start, Found);
  FIndex := Found + System.Length(AClose);
end;

procedure TLeakScanner.SkipString;
begin
  Inc(FIndex);
  while (FIndex <= FLength) and (FSource[FIndex] <> '''') and (FSource[FIndex] <> #10) do
  begin
    Inc(FIndex);
  end;
  // Das Zeilenende zählt die Hauptschleife.
  if (FIndex <= FLength) and (FSource[FIndex] = '''') then
  begin
    Inc(FIndex);
  end;
end;

function TLeakScanner.ReadQualified: string;
var
  Start: Integer;
begin
  Start := FIndex;
  while (FIndex <= FLength) and IsQualifiedChar(FSource[FIndex]) do
  begin
    Inc(FIndex);
  end;
  Result := Copy(FSource, Start, FIndex - Start);
end;

/// <summary>Bezeichner ab FIndex; bei ungeschütztem „ReportMemoryLeaksOnShutdown := True“ dessen Zeile,
/// sonst 0.</summary>
function TLeakScanner.ScanWord: Integer;
var
  Word: string;
  FoundLine: Integer;
begin
  Result := 0;
  Word := UpperCase(ReadQualified);
  if (Word <> 'REPORTMEMORYLEAKSONSHUTDOWN') and (Word <> 'SYSTEM.REPORTMEMORYLEAKSONSHUTDOWN') then
  begin
    Exit;
  end;
  FoundLine := FLine;
  SkipBlanks;
  if (FIndex < FLength) and (FSource[FIndex] = ':') and (FSource[FIndex + 1] = '=') then
  begin
    Inc(FIndex, 2);
    SkipBlanks;
    if SameText(ReadQualified, 'True') and not Guarded then
    begin
      Result := FoundLine;
    end;
  end;
end;

/// <summary>Ein Schritt ab FIndex; liefert die Zeile der Fundstelle oder 0.</summary>
function TLeakScanner.Step: Integer;
begin
  Result := 0;
  if FSource[FIndex] = #10 then
  begin
    Inc(FLine);
    Inc(FIndex);
  end
  else if (FSource[FIndex] = '/') and NextIs('/') then
  begin
    SkipLineComment;
  end
  else if FSource[FIndex] = '{' then
  begin
    SkipComment('}', 1);
  end
  else if (FSource[FIndex] = '(') and NextIs('*') then
  begin
    SkipComment('*)', 2);
  end
  else if FSource[FIndex] = '''' then
  begin
    SkipString;
  end
  else if IsQualifiedChar(FSource[FIndex]) then
  begin
    Result := ScanWord;
  end
  else
  begin
    Inc(FIndex);
  end;
end;

function TLeakScanner.Run(const ASource: string): Integer;
begin
  Result := 0;
  FSource := ASource;
  FFrames := nil;
  FLength := System.Length(ASource);
  FLine := 1;
  FIndex := 1;
  while (Result = 0) and (FIndex <= FLength) do
  begin
    Result := Step;
  end;
end;

class function TAtlasReleaseGuard.LeakReportLine(const ASource: string): Integer;
var
  Scanner: TLeakScanner;
begin
  Scanner := Default(TLeakScanner);
  Result := Scanner.Run(ASource);
end;

function Finding(AIssue: TAtlasReleaseIssue; ACheck: TAtlasReleaseCheck; const AValue: string;
  AExpected: Boolean): TAtlasReleaseFinding;
begin
  Result := Default(TAtlasReleaseFinding);
  Result.Issue := AIssue;
  Result.Check := ACheck;
  Result.Value := AValue;
  Result.Expected := AExpected;
end;

class function TAtlasReleaseGuard.Evaluate(const ASettings: TAtlasReleaseSettings;
  const AOptions: TAtlasReleaseOptions): TAtlasReleaseFindings;
var
  Findings: TAtlasReleaseFindings;

  function Enabled(ACheck: TAtlasReleaseCheck): Boolean;
  begin
    Result := ASettings.Checks.Items[ACheck].Enabled;
  end;

  function Expected(ACheck: TAtlasReleaseCheck): Boolean;
  begin
    Result := ASettings.Checks.Items[ACheck].Expected;
  end;

  procedure Option(AIssue: TAtlasReleaseIssue; ACheck: TAtlasReleaseCheck; const AValue: string;
    ACompilerDefault: Boolean);
  begin
    if Enabled(ACheck) and (IsOn(AValue, ACompilerDefault) <> Expected(ACheck)) then
    begin
      Findings := Findings + [Finding(AIssue, ACheck, AValue, Expected(ACheck))];
    end;
  end;

  procedure CheckDefines;
  var
    Define: string;
  begin
    for Define in AOptions.Defines do
    begin
      if SameText(Trim(Define), 'DEBUG') then
      begin
        Findings := Findings + [Finding(TAtlasReleaseIssue.DebugDefine, TAtlasReleaseCheck.DebugDefine, 'DEBUG',
          False)];
        Break;
      end;
    end;
  end;

  procedure CheckLeaks;
  var
    Line: Integer;
    Item: TAtlasReleaseFinding;
  begin
    Line := LeakReportLine(AOptions.Source);
    if Line > 0 then
    begin
      Item := Finding(TAtlasReleaseIssue.MemoryLeaks, TAtlasReleaseCheck.MemoryLeaks,
        'ReportMemoryLeaksOnShutdown := True', False);
      Item.FileName := AOptions.SourceFile;
      Item.Line := Line;
      Findings := Findings + [Item];
    end;
  end;

  procedure CheckVersion;
  var
    Version: string;
  begin
    Version := VersionOf(AOptions);
    if (Version = '') or (Version = '0.0.0.0') then
    begin
      Findings := Findings + [Finding(TAtlasReleaseIssue.VersionMissing, TAtlasReleaseCheck.VersionInfo, Version,
        False)];
    end
    else if (AOptions.LastVersion <> '') and SameText(Version, AOptions.LastVersion) and
      not IsOn(AOptions.AutoIncrementVersion, False) then
    begin
      Findings := Findings + [Finding(TAtlasReleaseIssue.VersionUnchanged, TAtlasReleaseCheck.VersionInfo, Version,
        False)];
    end;
  end;

  procedure CheckOutput;
  var
    Output: string;
  begin
    Output := ResolveFolder(AOptions.OutputFolder, AOptions.Configuration, AOptions.Platform);
    if SameText(Output, ResolveFolder(AOptions.DebugOutputFolder, DebugConfiguration, AOptions.Platform)) then
    begin
      Findings := Findings + [Finding(TAtlasReleaseIssue.OutputFolder, TAtlasReleaseCheck.OutputFolder, Output,
        False)];
    end;
  end;

begin
  Findings := nil;
  if Enabled(TAtlasReleaseCheck.DebugDefine) then
  begin
    CheckDefines;
  end;
  Option(TAtlasReleaseIssue.DebugInfo, TAtlasReleaseCheck.DebugInfo, AOptions.DebugInformation, True);
  // „Mit Debug-Informationen linken“ zählt nur, wenn keine Debug-Informationen gewollt sind.
  if Enabled(TAtlasReleaseCheck.DebugInfo) and not Expected(TAtlasReleaseCheck.DebugInfo) and
    IsOn(AOptions.DebugInfoInExe, False) then
  begin
    Findings := Findings + [Finding(TAtlasReleaseIssue.DebugInfoInExe, TAtlasReleaseCheck.DebugInfo,
      AOptions.DebugInfoInExe, False)];
  end;
  Option(TAtlasReleaseIssue.StackFrames, TAtlasReleaseCheck.StackFrames, AOptions.StackFrames, False);
  Option(TAtlasReleaseIssue.Assertions, TAtlasReleaseCheck.Assertions, AOptions.Assertions, True);
  Option(TAtlasReleaseIssue.RangeChecks, TAtlasReleaseCheck.RangeChecks, AOptions.RangeChecks, False);
  Option(TAtlasReleaseIssue.OverflowChecks, TAtlasReleaseCheck.OverflowChecks, AOptions.OverflowChecks, False);
  if Enabled(TAtlasReleaseCheck.MemoryLeaks) and not AOptions.IsPackage and (AOptions.Source <> '') then
  begin
    CheckLeaks;
  end;
  if Enabled(TAtlasReleaseCheck.VersionInfo) then
  begin
    CheckVersion;
  end;
  if Enabled(TAtlasReleaseCheck.OutputFolder) and not AOptions.IsPackage and AOptions.HasDebugConfiguration and
    not SameText(AOptions.Configuration, DebugConfiguration) then
  begin
    CheckOutput;
  end;
  Result := Findings;
end;

class function TAtlasReleaseGuard.FindingsKey(const AOptions: TAtlasReleaseOptions;
  const AFindings: TAtlasReleaseFindings): string;
var
  Item: TAtlasReleaseFinding;
begin
  Result := AnsiUpperCase(AOptions.Project) + '|' + UpperCase(AOptions.Configuration) + '|' +
    UpperCase(AOptions.Platform);
  for Item in AFindings do
  begin
    Result := Result + '|' + OptionNames[Item.Issue] + '=' + Item.Value;
  end;
end;

{ TAtlasReleaseGuardParticipant }

constructor TAtlasReleaseGuardParticipant.Create(const ASettings: TAtlasReleaseSettingsFunc;
  const ARead: TAtlasReleaseReadFunc; const AReport: TAtlasReleaseReportFunc;
  const ARemember: TAtlasReleaseRememberProc; const AClock: TAtlasClockFunc);
begin
  inherited Create;
  FSettings := ASettings;
  FRead := ARead;
  FReport := AReport;
  FRemember := ARemember;
  FClock := AClock;
  FPending := TList<TPending>.Create;
end;

destructor TAtlasReleaseGuardParticipant.Destroy;
begin
  FPending.Free;
  inherited;
end;

function TAtlasReleaseGuardParticipant.Now_: Int64;
begin
  if Assigned(FClock) then
  begin
    Result := FClock();
  end
  else
  begin
    Result := TStopwatch.GetTimeStamp div (TStopwatch.Frequency div 1000);
  end;
end;

function TAtlasReleaseGuardParticipant.PendingIndex(const AFileName: string): Integer;
begin
  for Result := 0 to FPending.Count - 1 do
  begin
    if SameText(FPending[Result].Options.Project, AFileName) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

/// <summary>Ausgang der Prüfung; mit build.gate = block lässt derselbe Befund kurz nach dem Abbruch den
/// zweiten Versuch durch (bewusst übergangen).</summary>
function TAtlasReleaseGuardParticipant.OutcomeOf(const ASettings: TAtlasReleaseSettings;
  const AOptions: TAtlasReleaseOptions; const AFindings: TAtlasReleaseFindings): TAtlasReleaseOutcome;
var
  Key: string;
begin
  if Length(AFindings) = 0 then
  begin
    Exit(TAtlasReleaseOutcome.Passed);
  end;
  if ASettings.Gate <> TAtlasBuildGate.Block then
  begin
    Exit(TAtlasReleaseOutcome.Reported);
  end;
  Key := TAtlasReleaseGuard.FindingsKey(AOptions, AFindings);
  if (Key = FBlockedKey) and (Now_ - FBlockedAt <= TAtlasReleaseGuard.OverrideMs) then
  begin
    Result := TAtlasReleaseOutcome.Overridden;
    FBlockedKey := '';
  end
  else
  begin
    Result := TAtlasReleaseOutcome.Blocked;
    FBlockedKey := Key;
    FBlockedAt := Now_;
  end;
end;

procedure TAtlasReleaseGuardParticipant.DropPending(const AFileName: string);
var
  Index: Integer;
begin
  Index := PendingIndex(AFileName);
  if Index >= 0 then
  begin
    FPending.Delete(Index);
  end;
end;

procedure TAtlasReleaseGuardParticipant.AddPending(const AOptions: TAtlasReleaseOptions);
var
  Pending: TPending;
begin
  Pending.Options := AOptions;
  Pending.Version := TAtlasReleaseGuard.VersionOf(AOptions);
  if Pending.Version <> '' then
  begin
    FPending.Add(Pending);
  end;
end;

function TAtlasReleaseGuardParticipant.CancelCompile(const AProject: TAtlasCompileProject;
  out AReason: string): Boolean;
var
  Settings: TAtlasReleaseSettings;
  Options: TAtlasReleaseOptions;
  Findings: TAtlasReleaseFindings;
  Outcome: TAtlasReleaseOutcome;
  Reason: string;
begin
  AReason := '';
  Result := False;
  Settings := FSettings();
  if not TAtlasReleaseGuard.Applies(Settings, AProject) or not FRead(AProject, Options) then
  begin
    Exit;
  end;
  if Options.Project = '' then
  begin
    Options.Project := AProject.FileName;
  end;
  Findings := TAtlasReleaseGuard.Evaluate(Settings, Options);
  Outcome := OutcomeOf(Settings, Options, Findings);
  Reason := FReport(Options, Findings, Outcome);
  DropPending(Options.Project);
  if Outcome = TAtlasReleaseOutcome.Blocked then
  begin
    AReason := Reason;
    Exit(True);
  end;
  AddPending(Options);
end;

procedure TAtlasReleaseGuardParticipant.ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
var
  Index: Integer;
  Pending: TPending;
begin
  Index := PendingIndex(AProject.FileName);
  if Index < 0 then
  begin
    Exit;
  end;
  Pending := FPending[Index];
  FPending.Delete(Index);
  if ASucceeded and Assigned(FRemember) then
  begin
    FRemember(Pending.Options, Pending.Version);
  end;
end;

end.
