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
    begin
      if FrameGuarded(Item) then
      begin
        Exit(True);
      end;
    end;
  end;

  procedure CountLines(AFrom, ATo: Integer);
  var
    Position: Integer;
  begin
    for Position := AFrom to ATo do
    begin
      if ASource[Position] = #10 then
      begin
        Inc(Line);
      end;
    end;
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
      begin
        Frame.Kind := TGuardKind.IfDebug;
      end
      else
      begin
        Frame.Kind := TGuardKind.Neutral;
      end;
      Frames := Frames + [Frame];
    end
    else if Name = 'IFNDEF' then
    begin
      Frame.InElse := False;
      if SameText(Argument, 'DEBUG') then
      begin
        Frame.Kind := TGuardKind.IfNotDebug;
      end
      else
      begin
        Frame.Kind := TGuardKind.Neutral;
      end;
      Frames := Frames + [Frame];
    end
    else if (Name = 'IF') or (Name = 'IFOPT') then
    begin
      Frame.InElse := False;
      Frame.Kind := DirectiveKind(Argument);
      if Name = 'IFOPT' then
      begin
        Frame.Kind := TGuardKind.Neutral;
      end;
      Frames := Frames + [Frame];
    end
    else if (Name = 'ELSEIF') and (System.Length(Frames) > 0) then
    begin
      Frames[High(Frames)].Kind := DirectiveKind(Argument);
      Frames[High(Frames)].InElse := False;
    end
    else if (Name = 'ELSE') and (System.Length(Frames) > 0) then
    begin
      Frames[High(Frames)].InElse := True;
    end
    else if ((Name = 'ENDIF') or (Name = 'IFEND')) and (System.Length(Frames) > 0) then
    begin
      SetLength(Frames, System.Length(Frames) - 1);
    end;
  end;

  procedure SkipBlanks;
  begin
    while (Index <= Length_) and CharInSet(ASource[Index], [' ', #9, #13, #10]) do
    begin
      if ASource[Index] = #10 then
      begin
        Inc(Line);
      end;
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
          begin
            Inc(Index);
          end;
        end
        else
        begin
          Inc(Index);
        end;
      '{':
        begin
          Start := Index;
          Found := Pos('}', ASource, Index + 1);
          if Found = 0 then
          begin
            Found := Length_;
          end;
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
          begin
            Found := Length_;
          end;
          if (Index + 2 <= Length_) and (ASource[Index + 2] = '$') then
          begin
            Directive := Trim(Copy(ASource, Index + 3, Found - Index - 3));
            HandleDirective(Directive);
          end;
          CountLines(Start, Found);
          Index := Found + 2;
        end
        else
        begin
          Inc(Index);
        end;
      '''':
        begin
          Inc(Index);
          while (Index <= Length_) and (ASource[Index] <> '''') and (ASource[Index] <> #10) do
          begin
            Inc(Index);
          end;
          // Das Zeilenende zählt die Hauptschleife.
          if (Index <= Length_) and (ASource[Index] = '''') then
          begin
            Inc(Index);
          end;
        end;
    else
      if IsQualifiedChar(ASource[Index]) then
      begin
        Start := Index;
        while (Index <= Length_) and IsQualifiedChar(ASource[Index]) do
        begin
          Inc(Index);
        end;
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
            begin
              Inc(Index);
            end;
            if SameText(Copy(ASource, Start, Index - Start), 'True') and not Guarded then
            begin
              Exit(FoundLine);
            end;
          end;
        end;
      end
      else
      begin
        Inc(Index);
      end;
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
    begin
      Findings := Findings + [Finding(AIssue, ACheck, AValue, Expected(ACheck))];
    end;
  end;

var
  Define, Version, Output: string;
  Line: Integer;
  Item: TAtlasReleaseFinding;
begin
  Findings := nil;
  if Enabled(TAtlasReleaseCheck.DebugDefine) then
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
  if Enabled(TAtlasReleaseCheck.OutputFolder) and not AOptions.IsPackage and AOptions.HasDebugConfiguration and
    not SameText(AOptions.Configuration, DebugConfiguration) then
  begin
    Output := ResolveFolder(AOptions.OutputFolder, AOptions.Configuration, AOptions.Platform);
    if SameText(Output, ResolveFolder(AOptions.DebugOutputFolder, DebugConfiguration, AOptions.Platform)) then
    begin
      Findings := Findings + [Finding(TAtlasReleaseIssue.OutputFolder, TAtlasReleaseCheck.OutputFolder, Output,
        False)];
    end;
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
  begin
    Exit;
  end;
  if Options.Project = '' then
  begin
    Options.Project := AProject.FileName;
  end;
  Findings := TAtlasReleaseGuard.Evaluate(Settings, Options);
  if Length(Findings) = 0 then
  begin
    Outcome := TAtlasReleaseOutcome.Passed;
  end
  else if Settings.Gate <> TAtlasBuildGate.Block then
  begin
    Outcome := TAtlasReleaseOutcome.Reported;
  end
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
  begin
    FPending.Delete(Index);
  end;
  if Outcome = TAtlasReleaseOutcome.Blocked then
  begin
    AReason := Reason;
    Exit(True);
  end;
  Pending.Options := Options;
  Pending.Version := TAtlasReleaseGuard.VersionOf(Options);
  if Pending.Version <> '' then
  begin
    FPending.Add(Pending);
  end;
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
