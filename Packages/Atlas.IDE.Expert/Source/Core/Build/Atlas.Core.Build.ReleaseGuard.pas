unit Atlas.Core.Build.ReleaseGuard;

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
  Atlas.Core.Build.Events;

type
{$SCOPEDENUMS ON}
  /// <summary>Einzeln abschaltbare Prüfung (build.releaseChecks).</summary>
  TAtlasReleaseCheck = (DebugDefine, DebugInfo, StackFrames, Assertions, RangeChecks, OverflowChecks, MemoryLeaks,
    VersionInfo, OutputFolder);
  /// <summary>Art eines Verstoßes; bestimmt Text und Hinweis, wo die Option zu ändern ist.</summary>
  TAtlasReleaseIssue = (DebugDefine, DebugInfo, DebugInfoInExe, StackFrames, Assertions, RangeChecks, OverflowChecks,
    MemoryLeaks, VersionMissing, VersionUnchanged, OutputFolder);
  /// <summary>build.gate (#529): off und warn melden nur, block bricht den Build ab.</summary>
  TAtlasBuildGate = (Off, Warn, Block);
  /// <summary>Ergebnis einer Prüfung vor dem Build.</summary>
  TAtlasReleaseOutcome = (Passed, Reported, Blocked, Overridden);
{$SCOPEDENUMS OFF}

  TAtlasReleaseCheckSetting = record
    Enabled: Boolean;
    /// <summary>Sollwert der Compileroption (nur für Prüfungen mit Sollwert): True = an.</summary>
    Expected: Boolean;
  end;

  TAtlasReleaseChecks = record
    Items: array[TAtlasReleaseCheck] of TAtlasReleaseCheckSetting;
    /// <summary>Alle an, Sollwerte aus.</summary>
    class function Defaults: TAtlasReleaseChecks; static;
    /// <summary>Liest die Textform (siehe Kopf); fehlende Namen mit Vorgabe, unbekannte entfallen.</summary>
    class function Parse(const AText: string): TAtlasReleaseChecks; static;
    /// <summary>Textform in fester Reihenfolge mit allen Prüfungen.</summary>
    function ToText: string;
    /// <summary>Parse und ToText in einem: einheitliche Schreibweise für die Ablage.</summary>
    class function Normalized(const AText: string): string; static;
  end;

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
    ReleaseConfiguration = 'Release';
    DebugConfiguration = 'Debug';
    CheckNames: array[TAtlasReleaseCheck] of string = ('debugDefine', 'debugInfo', 'stackFrames', 'assertions',
      'rangeChecks', 'overflowChecks', 'memoryLeaks', 'versionInfo', 'outputFolder');
    RuleIds: array[TAtlasReleaseCheck] of string = ('release-debug-define', 'release-debug-info',
      'release-stack-frames', 'release-assertions', 'release-range-checks', 'release-overflow-checks',
      'release-memory-leaks', 'release-version-info', 'release-output-folder');
    /// <summary>Prüfungen mit Sollwert (Compileroptionen).</summary>
    HasTarget: array[TAtlasReleaseCheck] of Boolean = (False, True, True, True, True, True, False, False, False);
    /// <summary>Name der Option in den Projektoptionen je Verstoß (für Meldung und Protokoll).</summary>
    OptionNames: array[TAtlasReleaseIssue] of string = ('DCC_Define', 'DCC_DebugInformation', 'DCC_DebugInfoInExe',
      'DCC_GenerateStackFrames', 'DCC_AssertionsAtRuntime', 'DCC_RangeChecking', 'DCC_IntegerOverflowCheck',
      'ReportMemoryLeaksOnShutdown', 'VerInfo_IncludeVerInfo', 'VerInfo_Keys', 'DCC_ExeOutput');
    GateNames: array[TAtlasBuildGate] of string = ('off', 'warn', 'block');
  public
    /// <summary>"off", "warn" oder "block" (Groß-/Kleinschreibung egal); sonst off.</summary>
    class function GateOf(const AText: string): TAtlasBuildGate; static;
    /// <summary>Konfigurationen durch Komma oder Semikolon getrennt, ohne Leere und Doppelte; Schreibweise der
    /// ersten Nennung.</summary>
    class function ConfigurationList(const AText: string): TArray<string>; static;
    /// <summary>Einheitliche Schreibweise von build.releaseConfigs: Liste durch ", " getrennt.</summary>
    class function NormalizedConfigurations(const AText: string): string; static;
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
  Atlas.Text.Chars;

{ TAtlasReleaseChecks }

class function TAtlasReleaseChecks.Defaults: TAtlasReleaseChecks;
var
  Check: TAtlasReleaseCheck;
begin
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    Result.Items[Check].Enabled := True;
    Result.Items[Check].Expected := False;
  end;
end;

function CheckOf(const AName: string; out ACheck: TAtlasReleaseCheck): Boolean;
var
  Check: TAtlasReleaseCheck;
begin
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
    if SameText(AName, TAtlasReleaseGuard.CheckNames[Check]) then
    begin
      ACheck := Check;
      Exit(True);
    end;
  ACheck := TAtlasReleaseCheck.DebugDefine;
  Result := False;
end;

class function TAtlasReleaseChecks.Parse(const AText: string): TAtlasReleaseChecks;
var
  Part, Name, Target: string;
  Enabled: Boolean;
  Equals: Integer;
  Check: TAtlasReleaseCheck;
begin
  Result := Defaults;
  for Part in AText.Split([',', ';']) do
  begin
    Name := Trim(Part);
    Enabled := True;
    if Name.StartsWith('-') or Name.StartsWith('!') then
    begin
      Enabled := False;
      Name := Trim(Copy(Name, 2, MaxInt));
    end;
    Target := '';
    Equals := Pos('=', Name);
    if Equals > 0 then
    begin
      Target := Trim(Copy(Name, Equals + 1, MaxInt));
      Name := Trim(Copy(Name, 1, Equals - 1));
    end;
    if not CheckOf(Name, Check) then
      Continue;
    Result.Items[Check].Enabled := Enabled;
    if TAtlasReleaseGuard.HasTarget[Check] and (Target <> '') then
      Result.Items[Check].Expected := SameText(Target, 'on') or SameText(Target, 'true') or (Target = '1');
  end;
end;

function TAtlasReleaseChecks.ToText: string;
const
  Targets: array[Boolean] of string = ('=off', '=on');
var
  Check: TAtlasReleaseCheck;
  Item: string;
begin
  Result := '';
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    Item := TAtlasReleaseGuard.CheckNames[Check];
    if not Items[Check].Enabled then
      Item := '-' + Item;
    if TAtlasReleaseGuard.HasTarget[Check] then
      Item := Item + Targets[Items[Check].Expected];
    if Result <> '' then
      Result := Result + ',';
    Result := Result + Item;
  end;
end;

class function TAtlasReleaseChecks.Normalized(const AText: string): string;
begin
  Result := Parse(AText).ToText;
end;

{ TAtlasReleaseSettings }

class function TAtlasReleaseSettings.Create(AEnabled: Boolean; const AGate, AConfigurations,
  AChecks: string): TAtlasReleaseSettings;
begin
  Result.Enabled := AEnabled;
  Result.Gate := TAtlasReleaseGuard.GateOf(AGate);
  Result.Configurations := TAtlasReleaseGuard.ConfigurationList(AConfigurations);
  Result.Checks := TAtlasReleaseChecks.Parse(AChecks);
end;

function TAtlasReleaseSettings.IsRelease(const AConfiguration: string): Boolean;
var
  Name: string;
begin
  Result := SameText(Trim(AConfiguration), TAtlasReleaseGuard.ReleaseConfiguration);
  if Result or (Trim(AConfiguration) = '') then
    Exit;
  for Name in Configurations do
    if SameText(Name, Trim(AConfiguration)) then
      Exit(True);
end;

{ TAtlasReleaseGuard }

class function TAtlasReleaseGuard.GateOf(const AText: string): TAtlasBuildGate;
var
  Gate: TAtlasBuildGate;
begin
  for Gate := Low(TAtlasBuildGate) to High(TAtlasBuildGate) do
    if SameText(Trim(AText), GateNames[Gate]) then
      Exit(Gate);
  Result := TAtlasBuildGate.Off;
end;

class function TAtlasReleaseGuard.ConfigurationList(const AText: string): TArray<string>;
var
  Part, Name, Known: string;
  Seen: Boolean;
begin
  Result := nil;
  for Part in AText.Split([',', ';']) do
  begin
    Name := Trim(Part);
    // JSON-artige Eingabe ["Release", "Ship"] verträgt die Liste auch.
    Name := Trim(StringReplace(StringReplace(StringReplace(Name, '"', '', [rfReplaceAll]), '[', '',
      [rfReplaceAll]), ']', '', [rfReplaceAll]));
    if Name = '' then
      Continue;
    Seen := False;
    for Known in Result do
      if SameText(Known, Name) then
        Seen := True;
    if not Seen then
      Result := Result + [Name];
  end;
end;

class function TAtlasReleaseGuard.NormalizedConfigurations(const AText: string): string;
begin
  Result := string.Join(', ', ConfigurationList(AText));
end;

class function TAtlasReleaseGuard.Applies(const ASettings: TAtlasReleaseSettings;
  const AProject: TAtlasCompileProject): Boolean;
begin
  Result := ASettings.Enabled and not AProject.Background and (AProject.FileName <> '') and
    ((AProject.Kind = TAtlasCompileKind.Make) or (AProject.Kind = TAtlasCompileKind.Build)) and
    ASettings.IsRelease(AProject.Configuration);
end;

class function TAtlasReleaseGuard.IsOn(const AValue: string; ADefault: Boolean): Boolean;
var
  Value: string;
begin
  Value := LowerCase(Trim(AValue));
  if (Value = 'true') or (Value = '1') or (Value = '2') then
    Result := True
  else if (Value = 'false') or (Value = '0') then
    Result := False
  else
    Result := ADefault;
end;

function VersionPart(const AValue, ADefault: string): string;
begin
  Result := Trim(AValue);
  if Result = '' then
    Result := ADefault;
end;

class function TAtlasReleaseGuard.VersionOf(const AOptions: TAtlasReleaseOptions): string;
var
  Part: string;
begin
  Result := '';
  if not IsOn(AOptions.IncludeVersionInfo, False) then
    Exit;
  for Part in AOptions.VersionKeys.Split([';']) do
    if SameText(Trim(Copy(Part, 1, Pos('=', Part) - 1)), 'FileVersion') then
    begin
      Result := Trim(Copy(Part, Pos('=', Part) + 1, MaxInt));
      // $(…) setzt erst MSBuild ein; dann gelten die Einzelwerte.
      if Pos('$(', Result) > 0 then
        Result := '';
      Break;
    end;
  if Result = '' then
    Result := VersionPart(AOptions.MajorVersion, '1') + '.' + VersionPart(AOptions.MinorVersion, '0') + '.' +
      VersionPart(AOptions.ReleaseVersion, '0') + '.' + VersionPart(AOptions.BuildVersion, '0');
end;

class function TAtlasReleaseGuard.ResolveFolder(const AFolder, AConfiguration, APlatform: string): string;
begin
  Result := Trim(AFolder);
  Result := StringReplace(Result, '$(Platform)', APlatform, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(Config)', AConfiguration, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
  while Result.StartsWith('.\') do
    Result := Copy(Result, 3, MaxInt);
  while (Length(Result) > 1) and Result.EndsWith('\') do
    Result := Copy(Result, 1, Length(Result) - 1);
  if (Result = '') or (Result = '.') then
    Result := '.';
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
    Result := TGuardKind.IfNotDebug
  else if Pos('DEFINED(DEBUG)', Text) > 0 then
    Result := TGuardKind.IfDebug
  else
    Result := TGuardKind.Neutral;
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

class function TAtlasReleaseGuard.LeakReportLine(const ASource: string): Integer;
var
  Index, Length_, Line, Start, Found, FoundLine: Integer;
  Frames: TArray<TGuardFrame>;
  Frame: TGuardFrame;
  Directive, Name, Argument, Word: string;

  function Guarded: Boolean;
  var
    Item: TGuardFrame;
  begin
    Result := False;
    for Item in Frames do
      if FrameGuarded(Item) then
        Exit(True);
  end;

  procedure CountLines(AFrom, ATo: Integer);
  var
    Position: Integer;
  begin
    for Position := AFrom to ATo do
      if ASource[Position] = #10 then
        Inc(Line);
  end;

  procedure HandleDirective(const AText: string);
  var
    Space: Integer;
  begin
    Space := Pos(' ', AText + ' ');
    Name := UpperCase(Copy(AText, 1, Space - 1));
    Argument := Trim(Copy(AText, Space + 1, MaxInt));
    if Name = 'IFDEF' then
    begin
      Frame.InElse := False;
      if SameText(Argument, 'DEBUG') then
        Frame.Kind := TGuardKind.IfDebug
      else
        Frame.Kind := TGuardKind.Neutral;
      Frames := Frames + [Frame];
    end
    else if Name = 'IFNDEF' then
    begin
      Frame.InElse := False;
      if SameText(Argument, 'DEBUG') then
        Frame.Kind := TGuardKind.IfNotDebug
      else
        Frame.Kind := TGuardKind.Neutral;
      Frames := Frames + [Frame];
    end
    else if (Name = 'IF') or (Name = 'IFOPT') then
    begin
      Frame.InElse := False;
      Frame.Kind := DirectiveKind(Argument);
      if Name = 'IFOPT' then
        Frame.Kind := TGuardKind.Neutral;
      Frames := Frames + [Frame];
    end
    else if (Name = 'ELSEIF') and (System.Length(Frames) > 0) then
    begin
      Frames[High(Frames)].Kind := DirectiveKind(Argument);
      Frames[High(Frames)].InElse := False;
    end
    else if (Name = 'ELSE') and (System.Length(Frames) > 0) then
      Frames[High(Frames)].InElse := True
    else if ((Name = 'ENDIF') or (Name = 'IFEND')) and (System.Length(Frames) > 0) then
      SetLength(Frames, System.Length(Frames) - 1);
  end;

  procedure SkipBlanks;
  begin
    while (Index <= Length_) and CharInSet(ASource[Index], [' ', #9, #13, #10]) do
    begin
      if ASource[Index] = #10 then
        Inc(Line);
      Inc(Index);
    end;
  end;

begin
  Result := 0;
  Frames := nil;
  Frame := Default(TGuardFrame);
  Length_ := System.Length(ASource);
  Line := 1;
  Index := 1;
  while Index <= Length_ do
  begin
    case ASource[Index] of
      #10:
        begin
          Inc(Line);
          Inc(Index);
        end;
      '/':
        if (Index < Length_) and (ASource[Index + 1] = '/') then
        begin
          while (Index <= Length_) and (ASource[Index] <> #10) do
            Inc(Index);
        end
        else
          Inc(Index);
      '{':
        begin
          Start := Index;
          Found := Pos('}', ASource, Index + 1);
          if Found = 0 then
            Found := Length_;
          if (Index < Length_) and (ASource[Index + 1] = '$') then
          begin
            Directive := Trim(Copy(ASource, Index + 2, Found - Index - 2));
            HandleDirective(Directive);
          end;
          CountLines(Start, Found);
          Index := Found + 1;
        end;
      '(':
        if (Index < Length_) and (ASource[Index + 1] = '*') then
        begin
          Start := Index;
          Found := Pos('*)', ASource, Index + 2);
          if Found = 0 then
            Found := Length_;
          if (Index + 2 <= Length_) and (ASource[Index + 2] = '$') then
          begin
            Directive := Trim(Copy(ASource, Index + 3, Found - Index - 3));
            HandleDirective(Directive);
          end;
          CountLines(Start, Found);
          Index := Found + 2;
        end
        else
          Inc(Index);
      '''':
        begin
          Inc(Index);
          while (Index <= Length_) and (ASource[Index] <> '''') and (ASource[Index] <> #10) do
            Inc(Index);
          // Das Zeilenende zählt die Hauptschleife.
          if (Index <= Length_) and (ASource[Index] = '''') then
            Inc(Index);
        end;
    else
      if IsQualifiedChar(ASource[Index]) then
      begin
        Start := Index;
        while (Index <= Length_) and IsQualifiedChar(ASource[Index]) do
          Inc(Index);
        Word := UpperCase(Copy(ASource, Start, Index - Start));
        if (Word = 'REPORTMEMORYLEAKSONSHUTDOWN') or (Word = 'SYSTEM.REPORTMEMORYLEAKSONSHUTDOWN') then
        begin
          FoundLine := Line;
          SkipBlanks;
          if (Index < Length_) and (ASource[Index] = ':') and (ASource[Index + 1] = '=') then
          begin
            Inc(Index, 2);
            SkipBlanks;
            Start := Index;
            while (Index <= Length_) and IsQualifiedChar(ASource[Index]) do
              Inc(Index);
            if SameText(Copy(ASource, Start, Index - Start), 'True') and not Guarded then
              Exit(FoundLine);
          end;
        end;
      end
      else
        Inc(Index);
    end;
  end;
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
      Findings := Findings + [Finding(AIssue, ACheck, AValue, Expected(ACheck))];
  end;

var
  Define, Version, Output: string;
  Line: Integer;
  Item: TAtlasReleaseFinding;
begin
  Findings := nil;
  if Enabled(TAtlasReleaseCheck.DebugDefine) then
    for Define in AOptions.Defines do
      if SameText(Trim(Define), 'DEBUG') then
      begin
        Findings := Findings + [Finding(TAtlasReleaseIssue.DebugDefine, TAtlasReleaseCheck.DebugDefine, 'DEBUG',
          False)];
        Break;
      end;
  Option(TAtlasReleaseIssue.DebugInfo, TAtlasReleaseCheck.DebugInfo, AOptions.DebugInformation, True);
  // „Mit Debug-Informationen linken“ zählt nur, wenn keine Debug-Informationen gewollt sind.
  if Enabled(TAtlasReleaseCheck.DebugInfo) and not Expected(TAtlasReleaseCheck.DebugInfo) and
    IsOn(AOptions.DebugInfoInExe, False) then
    Findings := Findings + [Finding(TAtlasReleaseIssue.DebugInfoInExe, TAtlasReleaseCheck.DebugInfo,
      AOptions.DebugInfoInExe, False)];
  Option(TAtlasReleaseIssue.StackFrames, TAtlasReleaseCheck.StackFrames, AOptions.StackFrames, False);
  Option(TAtlasReleaseIssue.Assertions, TAtlasReleaseCheck.Assertions, AOptions.Assertions, True);
  Option(TAtlasReleaseIssue.RangeChecks, TAtlasReleaseCheck.RangeChecks, AOptions.RangeChecks, False);
  Option(TAtlasReleaseIssue.OverflowChecks, TAtlasReleaseCheck.OverflowChecks, AOptions.OverflowChecks, False);
  if Enabled(TAtlasReleaseCheck.MemoryLeaks) and not AOptions.IsPackage and (AOptions.Source <> '') then
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
  if Enabled(TAtlasReleaseCheck.VersionInfo) then
  begin
    Version := VersionOf(AOptions);
    if (Version = '') or (Version = '0.0.0.0') then
      Findings := Findings + [Finding(TAtlasReleaseIssue.VersionMissing, TAtlasReleaseCheck.VersionInfo, Version,
        False)]
    else if (AOptions.LastVersion <> '') and SameText(Version, AOptions.LastVersion) and
      not IsOn(AOptions.AutoIncrementVersion, False) then
      Findings := Findings + [Finding(TAtlasReleaseIssue.VersionUnchanged, TAtlasReleaseCheck.VersionInfo, Version,
        False)];
  end;
  if Enabled(TAtlasReleaseCheck.OutputFolder) and not AOptions.IsPackage and AOptions.HasDebugConfiguration and
    not SameText(AOptions.Configuration, DebugConfiguration) then
  begin
    Output := ResolveFolder(AOptions.OutputFolder, AOptions.Configuration, AOptions.Platform);
    if SameText(Output, ResolveFolder(AOptions.DebugOutputFolder, DebugConfiguration, AOptions.Platform)) then
      Findings := Findings + [Finding(TAtlasReleaseIssue.OutputFolder, TAtlasReleaseCheck.OutputFolder, Output,
        False)];
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
    Result := Result + '|' + OptionNames[Item.Issue] + '=' + Item.Value;
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
    Result := FClock()
  else
    Result := TStopwatch.GetTimeStamp div (TStopwatch.Frequency div 1000);
end;

function TAtlasReleaseGuardParticipant.PendingIndex(const AFileName: string): Integer;
begin
  for Result := 0 to FPending.Count - 1 do
    if SameText(FPending[Result].Options.Project, AFileName) then
      Exit;
  Result := -1;
end;

function TAtlasReleaseGuardParticipant.CancelCompile(const AProject: TAtlasCompileProject;
  out AReason: string): Boolean;
var
  Settings: TAtlasReleaseSettings;
  Options: TAtlasReleaseOptions;
  Findings: TAtlasReleaseFindings;
  Outcome: TAtlasReleaseOutcome;
  Key, Reason: string;
  Index: Integer;
  Pending: TPending;
begin
  AReason := '';
  Result := False;
  Settings := FSettings();
  if not TAtlasReleaseGuard.Applies(Settings, AProject) or not FRead(AProject, Options) then
    Exit;
  if Options.Project = '' then
    Options.Project := AProject.FileName;
  Findings := TAtlasReleaseGuard.Evaluate(Settings, Options);
  if Length(Findings) = 0 then
    Outcome := TAtlasReleaseOutcome.Passed
  else if Settings.Gate <> TAtlasBuildGate.Block then
    Outcome := TAtlasReleaseOutcome.Reported
  else
  begin
    Key := TAtlasReleaseGuard.FindingsKey(Options, Findings);
    if (Key = FBlockedKey) and (Now_ - FBlockedAt <= TAtlasReleaseGuard.OverrideMs) then
    begin
      Outcome := TAtlasReleaseOutcome.Overridden;
      FBlockedKey := '';
    end
    else
    begin
      Outcome := TAtlasReleaseOutcome.Blocked;
      FBlockedKey := Key;
      FBlockedAt := Now_;
    end;
  end;
  Reason := FReport(Options, Findings, Outcome);
  Index := PendingIndex(Options.Project);
  if Index >= 0 then
    FPending.Delete(Index);
  if Outcome = TAtlasReleaseOutcome.Blocked then
  begin
    AReason := Reason;
    Exit(True);
  end;
  Pending.Options := Options;
  Pending.Version := TAtlasReleaseGuard.VersionOf(Options);
  if Pending.Version <> '' then
    FPending.Add(Pending);
end;

procedure TAtlasReleaseGuardParticipant.ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
var
  Index: Integer;
  Pending: TPending;
begin
  Index := PendingIndex(AProject.FileName);
  if Index < 0 then
    Exit;
  Pending := FPending[Index];
  FPending.Delete(Index);
  if ASucceeded and Assigned(FRemember) then
    FRemember(Pending.Options, Pending.Version);
end;

end.
