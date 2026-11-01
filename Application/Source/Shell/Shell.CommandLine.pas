unit Shell.CommandLine;

// Host-Rolle Shell: Kommandozeilenparameter des Servers.
//
//   --log <Datei>         Logdatei (wird fortgeschrieben)
//   --log-level <Stufe>   debug, info, warning, error (Standard: info)
//   --trace <Datei>       Mitschnitt aller JSON-Nachrichten
//
// Linter-Modus ohne Editor (#95):
//   --check <Ziel>        .dproj, Ordner oder einzelne Datei prüfen
//   --format <Art>        text (Standard), json, sarif
//   --output <Datei>      Ergebnis in Datei statt auf stdout
//   --rules <a,b>         nur diese Regeln
//   --units <a,b>         nur diese Units (Name oder Glob-Muster für Pfade)
//   --min-severity <S>    hint, info, warning, error
//   --fail-on <S>         error (Standard), warning, never: ab welchem Treffer Exit-Code 1;
//                         mit --compare die Abweichungen (#1121, siehe unten)
//   --source-root <Ordner> Wurzel der SARIF-Pfade (Standard: Git-Wurzel, sonst Ordner des Ziels)
//   --profile <Name>      Regelprofil (#146), vor "profile" aus atlas.json
//   --changed [<Basis>]   nur Dateien, die sich gegenüber der Merge-Base mit <Basis>
//                         (Standard main) geändert haben (Git, #157)
//   --diff <Ref>          nur Dateien, die sich gegenüber <Ref> geändert haben
//   --include-uncommitted mit --changed/--diff auch Index und Arbeitsverzeichnis
//   --changed-lines       nur Treffer in geänderten Zeilen
//   --metrics             statt der Treffer die Code-Metriken (#66): Markdown-Bericht
//                         (--format text) oder Metrikdaten (--format json)
//   --todos               statt der Treffer die offenen TODO-Einträge (#68): Markdown-Übersicht
//                         (--format text) oder TODO-Daten (--format json)
//   --no-index            ohne Symbolindex prüfen (#1112); Regeln, die Typen anderer Units
//                         oder der RTL brauchen, schweigen dann
//   --index-cache <Ordner> Ordner der Index-Caches (Standard wie der Server, %LOCALAPPDATA%\Atlas)
//   --fix <a,b|all>       Sammelkorrektur (#1352): sichere Korrekturen dieser Regeln anwenden (fix.minConfidence)
//   --fix-dry-run         mit --fix nur den vereinigten Diff ausgeben (stdout bzw. --output), nichts schreiben
//   --timings [<Datei>]   nach dem Lauf das Zeitprofil (#1356): langsamste Units und Regeln,
//                         Indexzeit, Speicher; als Markdown, mit Endung .json als JSON; ohne
//                         Datei auf stderr. Die Treffer bleiben unverändert auf stdout bzw. --output.
//                         (Nicht --profile: Das wählt seit #146 das Regelprofil.)
//
// Formatieren ohne IDE (#1358), Ziel wie bei --check:
//   --format-check        prüft, ob die Dateien den Formatregeln (format.*, .editorconfig) entsprechen;
//                         mit --format json alle Abweichungen, mit --format diff der vereinigte Diff;
//                         Exit-Code 1 bei einer Abweichung
//   --format-write        schreibt die formatierten Dateien (atomar, Kodierung bleibt)
//                         Beide mit --changed/--diff, --changed-lines (nur geänderte Zeilen) und --units.
//
// Betroffene Tests (#1353):
//   --affected-tests [<Basis>] statt der Prüfung die DUnitX-Tests, die eine Änderung gegenüber
//                         der Basis betrifft (Git: Merge-Base mit <Basis>, Standard main;
//                         SVN: Revision, Standard BASE); Ziel aus --check ist das Testprojekt
//                         oder die Projektgruppe. --format text, json oder dunitx (fertiges
//                         --run:… für die Test-exe), --output, --include-uncommitted.
//                         Exit-Code 0; 2, wenn alle Tests nötig sind; 3 bei Fehlern oder mit
//                         tests.affected = false
//
// Architekturbericht (#1118):
//   --architecture <Datei> Architekturübersicht des Ziels aus --check (Standard: aktueller Ordner)
//                         als Markdown (.md) oder interaktive HTML-Seite (.html) schreiben,
//                         als .json den Stand für einen späteren Vergleich (#1121)
//   --compare <alt.json>  mit einem gespeicherten Stand vergleichen (#1121): Text des Vergleichs
//                         auf stdout (bzw. --output), Exit-Code 1 bei einer Abweichung aus
//                         --fail-on newCycle,newCrossLink,subsystemChange,centralGrowth
//                         (Standard architecture.failOn, sonst newCycle)
//
// Absturzfall nachstellen (#1355):
//   --replay <anfrage.json> Fall aus %LOCALAPPDATA%\Atlas\crash nachspielen: Exit-Code 1 =
//                         reproduziert, 0 = nicht reproduziert, 2 = Fall nicht lesbar
// Code-Abfragen (#1351):
//   --query "<Abfrage>"   statt der Treffer das Ergebnis einer Abfrage über das Ziel aus --check,
//                         z. B. "classes where methods > 40"; "@name" führt eine gespeicherte Abfrage
//                         aus atlas.json (queries) aus. --format text (Standard), json oder csv;
//                         Exit-Code 0, Fehler in der Abfrage 3, query.enabled aus 3
//   --fail-on-match       mit --query Exit-Code 1, sobald die Abfrage etwas findet
// Hotspots (#1354):
//   --hotspots <Datei>    Hotspots des Ziels aus --check (Standard: aktueller Ordner) aus
//                         Änderungshäufigkeit und Komplexität samt Methoden und
//                         Änderungskopplung als Markdown (.md), HTML-Seite mit Blasendiagramm
//                         (.html) oder Daten (.json) schreiben; Exit-Code 3 ohne
//                         Versionsverwaltung oder mit hotspots.enabled = false
//
// MCP-Modus (#48):
//   --mcp                 Symbolindex über das Model Context Protocol anbieten
//   --root <Ordner>       Projektordner (Standard: aktuelles Verzeichnis)
//
// Werte können auch mit "=" angegeben werden (--log=server.log). --stdio, das
// Editoren anhängen, wird ignoriert; --clientProcessId=<PID> nennt den Editor-
// Prozess, dessen Ende auch den Server beendet (#283).

interface

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Output;

type
  TCommandLineOptions = record
  public const
    DefaultLogLevel = TLogLevel.Info;
    DefaultChangedBase = 'main';
  public
    LogFile: string;
    LogLevel: TLogLevel;
    /// <summary>--log-names: Server-Log mit Pfaden und Namen statt anonymisiert (#647).</summary>
    LogNames: Boolean;
    TraceFile: string;
    /// <summary>Ziel des Linter-Modus; '' = Server-Modus.</summary>
    CheckTarget: string;
    CheckFormat: TFindingsFormat;
    /// <summary>Wert von --format wie angegeben ('' = nicht angegeben); --affected-tests kennt auch dunitx.
    /// </summary>
    FormatText: string;
    OutputFile: string;
    RuleFilter: TArray<string>;
    UnitFilter: TArray<string>;
    MinSeverity: TRuleSeverity;
    /// <summary>Ab welchem Schweregrad Exit-Code 1 (#95); Standard Error.</summary>
    FailOn: TFailOn;
    /// <summary>Wert von --fail-on wie angegeben; mit --compare die Abweichungsarten (#1121). '' = nicht angegeben.
    /// </summary>
    FailOnText: string;
    /// <summary>Quellwurzel für SARIF-Pfade (#95); '' = Git-Wurzel, sonst Ordner des Ziels.</summary>
    SourceRoot: string;
    /// <summary>Regelprofil für --check (#146); '' = aus atlas.json.</summary>
    Profile: string;
    /// <summary>Statt der Treffer die Unterdrückungen je Regel ausgeben (#147).</summary>
    SuppressionStats: Boolean;
    /// <summary>Statt der Treffer die Code-Metriken ausgeben (#66).</summary>
    Metrics: Boolean;
    /// <summary>Statt der Treffer die offenen TODO-Einträge ausgeben (#68).</summary>
    Todos: Boolean;
    /// <summary>--check ohne Symbolindex (#1112).</summary>
    NoIndex: Boolean;
    /// <summary>Ordner der Index-Caches für --check (#1112); '' = wie der Server.</summary>
    IndexCacheFolder: string;
    /// <summary>--timings (#1356): Zeitprofil nach dem Lauf; TimingsFile '' = auf stderr.</summary>
    Timings: Boolean;
    TimingsFile: string;
    /// <summary>--architecture: Zieldatei des Architekturberichts (#1118, .md oder .html); '' = keiner.</summary>
    ArchitectureFile: string;
    /// <summary>--hotspots: Zieldatei des Hotspot-Berichts (#1354, .md, .html oder .json); '' = keiner.</summary>
    HotspotsFile: string;
    /// <summary>--compare: gespeicherter Architekturstand für den Vergleich (#1121); '' = keiner.</summary>
    CompareFile: string;
    /// <summary>--replay: anfrage.json eines Absturzfalls (#1355); '' = kein Nachstellen.</summary>
    ReplayFile: string;
    /// <summary>--query: Code-Abfrage oder @name einer gespeicherten (#1351); '' = keine.</summary>
    QueryText: string;
    /// <summary>--fail-on-match: Exit-Code 1, wenn --query etwas findet (#1351).</summary>
    FailOnMatch: Boolean;
    /// <summary>Baseline-Datei (#97); '' = atlas-baseline.json neben atlas.json, falls vorhanden.</summary>
    BaselineFile: string;
    /// <summary>Baseline aus den aktuellen Treffern neu schreiben statt zu prüfen.</summary>
    UpdateBaseline: Boolean;
    /// <summary>Git-Ref, gegen den --changed/--diff vergleicht (#157); '' = alle Dateien.</summary>
    ChangedRef: string;
    /// <summary>True bei --changed: Vergleich mit der Merge-Base von ChangedRef und HEAD.</summary>
    ChangedMergeBase: Boolean;
    /// <summary>Index und Arbeitsverzeichnis einbeziehen.</summary>
    IncludeUncommitted: Boolean;
    /// <summary>Nur Treffer in geänderten Zeilen ausgeben.</summary>
    ChangedLines: Boolean;
    /// <summary>--affected-tests (#1353): betroffene Tests statt der Prüfung.</summary>
    AffectedTests: Boolean;
    /// <summary>Basis von --affected-tests; '' = main (Git) bzw. BASE (SVN).</summary>
    AffectedBase: string;
    /// <summary>--format-check (#1358): Formatierung prüfen statt Regeln.</summary>
    FormatCheck: Boolean;
    /// <summary>--format-write (#1358): formatierte Dateien schreiben.</summary>
    FormatWrite: Boolean;
    /// <summary>--format diff (#1358): vereinigter Diff; nur mit --format-check/--format-write.</summary>
    FormatDiff: Boolean;
    /// <summary>Index-Caches löschen und beenden (#184).</summary>
    ClearCache: Boolean;
    /// <summary>Nicht vertrauenswürdiger Arbeitsbereich (#186): nichts ausführen, was Code aus dem Projekt startet.</summary>
    Restricted: Boolean;
    /// <summary>MCP-Modus statt LSP (#48).</summary>
    Mcp: Boolean;
    /// <summary>Projektordner im MCP-Modus; '' = aktuelles Verzeichnis.</summary>
    McpRoot: string;
    /// <summary>Prozess-ID des Editors aus --clientProcessId; 0 = unbekannt.</summary>
    ClientProcessId: Cardinal;
    /// <summary>--fix (#1352): Regeln der Sammelkorrektur, "all" = alle; nil = keine Sammelkorrektur.</summary>
    FixRules: TArray<string>;
    /// <summary>--fix-dry-run: nur den Diff ausgeben.</summary>
    FixDryRun: Boolean;
    /// <summary>Hinweise zu ungültigen oder unbekannten Parametern, für das Log.</summary>
    Warnings: TArray<string>;
    class function Parse(const AArgs: TArray<string>): TCommandLineOptions; static;
    /// <summary>Parameter des laufenden Prozesses.</summary>
    class function FromProcess: TCommandLineOptions; static;
    class function TryParseLogLevel(const AText: string; out ALevel: TLogLevel): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Filter,
  Atlas.Common.Architecture.Comparison;

{ TCommandLineOptions }

class function TCommandLineOptions.TryParseLogLevel(const AText: string; out ALevel: TLogLevel): Boolean;
var
  mText: string;
begin
  mText := AText.Trim.ToLower;
  Result := True;
  if mText = 'debug' then
  begin
    ALevel := TLogLevel.Debug;
  end
  else if mText = 'info' then
  begin
    ALevel := TLogLevel.Info;
  end
  else if (mText = 'warning') or (mText = 'warn') then
  begin
    ALevel := TLogLevel.Warning;
  end
  else if mText = 'error' then
  begin
    ALevel := TLogLevel.Error;
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>"-log" und "–log" (Gedankenstrich, z. B. aus Word oder Chat kopiert) gelten als "--log" (#647).</summary>
function NormalizeDashes(const AArg: string): string;
begin
  Result := AArg;
  if (Result <> '') and ((Result[1] = #$2013) or (Result[1] = #$2014)) then
  begin
    Result := '--' + Result.Substring(1);
  end
  else if (Length(Result) > 1) and (Result[1] = '-') and CharInSet(Result[2], ['A'..'Z', 'a'..'z']) then
  begin
    Result := '-' + Result;
  end;
end;

procedure AddWarning(var AOptions: TCommandLineOptions; const AText: string);
begin
  AOptions.Warnings := AOptions.Warnings + [AText];
end;

type
  /// <summary>Zeiger auf ein string-Feld; eigener Typ, weil PString nicht überall auf string zeigt.</summary>
  PStringField = ^string;

  /// <summary>Parameter mit Textwert, der unverändert in ein Feld geht (S-02: Tabelle statt if-Kette).</summary>
  TStringOption = record
    Name: string;
    Target: PStringField;
  end;

  /// <summary>Schalter ohne Wert, der ein Feld auf True setzt.</summary>
  TFlagOption = record
    Name: string;
    Target: PBoolean;
  end;

  /// <summary>Wertet den Wert eines Parameters aus und setzt die Felder dazu.</summary>
  TValueHandler = procedure(var AOptions: TCommandLineOptions; const AValue: string);

  /// <summary>Parameter mit Wert, den ein eigener Handler prüft.</summary>
  TValueOption = record
    Name: string;
    Apply: TValueHandler;
  end;

  /// <summary>Die Tabellen der Parameter eines Aufrufs von Parse.</summary>
  TOptionTables = record
    Strings: TArray<TStringOption>;
    Flags: TArray<TFlagOption>;
    Values: TArray<TValueOption>;
  end;

  /// <summary>Liest die Parameter der Reihe nach; Name und Value gehören zum aktuellen.</summary>
  TArgReader = record
    Args: TArray<string>;
    Index: Integer;
    Arg: string;
    Name: string;
    Value: string;
    HasValue: Boolean;
    /// <summary>Geht zum nächsten Parameter und zerlegt "--name=wert"; False am Ende.</summary>
    function Next: Boolean;
    /// <summary>Wert aus "=" oder dem folgenden Argument; ohne beides eine Warnung in AOptions.</summary>
    function TakeValue(var AOptions: TCommandLineOptions): Boolean;
    /// <summary>Optionaler Wert: aus "=" oder dem folgenden Argument, wenn es nicht mit "-" beginnt.</summary>
    function OptionalValue(out AValue: string): Boolean;
  end;

function TArgReader.Next: Boolean;
var
  mSeparator: Integer;
begin
  Inc(Index);
  Result := Index <= High(Args);
  if not Result then
  begin
    Exit;
  end;
  Arg := NormalizeDashes(Args[Index]);
  mSeparator := Arg.IndexOf('=');
  HasValue := mSeparator > 0;
  Name := Arg.ToLower;
  Value := '';
  if HasValue then
  begin
    Name := Arg.Substring(0, mSeparator).ToLower;
    Value := Arg.Substring(mSeparator + 1);
  end;
end;

function TArgReader.TakeValue(var AOptions: TCommandLineOptions): Boolean;
begin
  Result := True;
  if HasValue then
  begin
    Exit;
  end;
  if Index < High(Args) then
  begin
    Inc(Index);
    Value := Args[Index];
    Exit;
  end;
  AddWarning(AOptions, Format('Parameter %s erwartet einen Wert', [Name]));
  Result := False;
end;

function TArgReader.OptionalValue(out AValue: string): Boolean;
begin
  AValue := Value;
  Result := HasValue;
  if not Result and (Index < High(Args)) and not Args[Index + 1].StartsWith('-') then
  begin
    Inc(Index);
    AValue := Args[Index];
    Result := True;
  end;
end;

function StringOption(const AName: string; ATarget: PStringField): TStringOption;
begin
  Result.Name := AName;
  Result.Target := ATarget;
end;

function FlagOption(const AName: string; ATarget: PBoolean): TFlagOption;
begin
  Result.Name := AName;
  Result.Target := ATarget;
end;

function ValueOption(const AName: string; AApply: TValueHandler): TValueOption;
begin
  Result.Name := AName;
  Result.Apply := AApply;
end;

procedure ApplyLogLevel(var AOptions: TCommandLineOptions; const AValue: string);
var
  mLevel: TLogLevel;
begin
  if TCommandLineOptions.TryParseLogLevel(AValue, mLevel) then
  begin
    AOptions.LogLevel := mLevel;
  end
  else
  begin
    AddWarning(AOptions, Format('Unbekannte Log-Stufe "%s", verwendet wird info', [AValue]));
  end;
end;

procedure ApplyFormat(var AOptions: TCommandLineOptions; const AValue: string);
var
  mFormat: TFindingsFormat;
begin
  AOptions.FormatText := AValue;
  // diff gibt es nur beim Formatieren (#1358); die Prüfung dort lehnt es ohne --format-check ab.
  if SameText(AValue.Trim, 'diff') then
  begin
    AOptions.FormatDiff := True;
  end
  else if TFindingsOutput.TryParseFormat(AValue, mFormat) then
  begin
    AOptions.CheckFormat := mFormat;
    AOptions.FormatDiff := False;
  end
  // dunitx gibt es nur für --affected-tests (#1353), csv nur für --query (#1351); dort wird der Wert geprüft.
  else if not SameText(AValue, 'dunitx') and not SameText(AValue, 'csv') then
  begin
    AddWarning(AOptions, Format('Unbekanntes Format "%s", verwendet wird text', [AValue]));
  end;
end;

procedure ApplyRules(var AOptions: TCommandLineOptions; const AValue: string);
begin
  AOptions.RuleFilter := TFindingFilter.SplitList(AValue);
end;

procedure ApplyUnits(var AOptions: TCommandLineOptions; const AValue: string);
begin
  AOptions.UnitFilter := TFindingFilter.SplitList(AValue);
end;

procedure ApplyFix(var AOptions: TCommandLineOptions; const AValue: string);
begin
  AOptions.FixRules := TFindingFilter.SplitList(AValue);
  if AOptions.FixRules = nil then
  begin
    AddWarning(AOptions, '--fix erwartet Regeln, z. B. --fix redundant-cast oder --fix all');
  end;
end;

procedure ApplyMinSeverity(var AOptions: TCommandLineOptions; const AValue: string);
var
  mSeverity: TRuleSeverity;
begin
  if TConfigurationParser.TryParseSeverity(AValue, mSeverity) and (mSeverity <> TRuleSeverity.Off) then
  begin
    AOptions.MinSeverity := mSeverity;
  end
  else
  begin
    AddWarning(AOptions, Format('Unbekannter Schweregrad "%s", gemeldet wird alles', [AValue]));
  end;
end;

procedure ApplyFailOn(var AOptions: TCommandLineOptions; const AValue: string);
var
  mFailOn: TFailOn;
  mKinds: TArchitectureFailKinds;
  mKindError: string;
begin
  AOptions.FailOnText := AValue;
  if TFindingsOutput.TryParseFailOn(AValue, mFailOn) then
  begin
    AOptions.FailOn := mFailOn;
  end
  // Abweichungsarten für --compare (#1121) prüft der Architekturbericht.
  else if not TArchitectureComparer.ParseKindList(AValue, mKinds, mKindError) then
  begin
    AddWarning(AOptions, Format('Unbekannter Wert "%s" für --fail-on, verwendet wird error', [AValue]));
  end;
end;

procedure ApplyDiff(var AOptions: TCommandLineOptions; const AValue: string);
begin
  AOptions.ChangedRef := AValue;
  AOptions.ChangedMergeBase := False;
end;

procedure ApplyClientProcessId(var AOptions: TCommandLineOptions; const AValue: string);
var
  mProcessId: Cardinal;
begin
  if TryStrToUInt(AValue, mProcessId) then
  begin
    AOptions.ClientProcessId := mProcessId;
  end
  else
  begin
    AddWarning(AOptions, Format('Ungültige Prozess-ID "%s" wird ignoriert', [AValue]));
  end;
end;

/// <summary>Tabellen mit Zeigern in AOptions; AOptions muss so lange leben wie die Tabellen.</summary>
function OptionTables(var AOptions: TCommandLineOptions): TOptionTables;
begin
  Result.Strings := [StringOption('--log', @AOptions.LogFile), StringOption('--trace', @AOptions.TraceFile),
    StringOption('--check', @AOptions.CheckTarget), StringOption('--output', @AOptions.OutputFile),
    StringOption('--source-root', @AOptions.SourceRoot), StringOption('--profile', @AOptions.Profile),
    StringOption('--baseline', @AOptions.BaselineFile), StringOption('--root', @AOptions.McpRoot),
    StringOption('--index-cache', @AOptions.IndexCacheFolder),
    StringOption('--architecture', @AOptions.ArchitectureFile), StringOption('--compare', @AOptions.CompareFile),
    StringOption('--replay', @AOptions.ReplayFile), StringOption('--hotspots', @AOptions.HotspotsFile),
    StringOption('--query', @AOptions.QueryText)];
  Result.Flags := [FlagOption('--log-names', @AOptions.LogNames), FlagOption('--mcp', @AOptions.Mcp),
    FlagOption('--restricted', @AOptions.Restricted), FlagOption('--clear-cache', @AOptions.ClearCache),
    FlagOption('--include-uncommitted', @AOptions.IncludeUncommitted),
    FlagOption('--changed-lines', @AOptions.ChangedLines), FlagOption('--update-baseline', @AOptions.UpdateBaseline),
    FlagOption('--suppression-stats', @AOptions.SuppressionStats), FlagOption('--metrics', @AOptions.Metrics),
    FlagOption('--todos', @AOptions.Todos), FlagOption('--no-index', @AOptions.NoIndex),
    FlagOption('--fix-dry-run', @AOptions.FixDryRun), FlagOption('--fail-on-match', @AOptions.FailOnMatch),
    FlagOption('--format-check', @AOptions.FormatCheck), FlagOption('--format-write', @AOptions.FormatWrite)];
  Result.Values := [ValueOption('--log-level', ApplyLogLevel), ValueOption('--format', ApplyFormat),
    ValueOption('--rules', ApplyRules), ValueOption('--units', ApplyUnits), ValueOption('--fix', ApplyFix),
    ValueOption('--min-severity', ApplyMinSeverity), ValueOption('--fail-on', ApplyFailOn),
    ValueOption('--diff', ApplyDiff), ValueOption('--clientprocessid', ApplyClientProcessId)];
end;

/// <summary>Parameter aus den Tabellen; False, wenn AReader.Name in keiner steht.</summary>
function ApplyTabled(var AOptions: TCommandLineOptions; var AReader: TArgReader;
  const ATables: TOptionTables): Boolean;
var
  mString: TStringOption;
  mFlag: TFlagOption;
  mValue: TValueOption;
begin
  Result := True;
  for mString in ATables.Strings do
  begin
    if mString.Name = AReader.Name then
    begin
      if AReader.TakeValue(AOptions) then
      begin
        mString.Target^ := AReader.Value;
      end;
      Exit;
    end;
  end;
  for mFlag in ATables.Flags do
  begin
    if mFlag.Name = AReader.Name then
    begin
      mFlag.Target^ := True;
      Exit;
    end;
  end;
  for mValue in ATables.Values do
  begin
    if mValue.Name = AReader.Name then
    begin
      if AReader.TakeValue(AOptions) then
      begin
        mValue.Apply(AOptions, AReader.Value);
      end;
      Exit;
    end;
  end;
  Result := False;
end;

/// <summary>Parameter mit optionalem Wert (--changed, --affected-tests, --timings); False bei anderen.</summary>
function ApplyOptional(var AOptions: TCommandLineOptions; var AReader: TArgReader): Boolean;
var
  mValue: string;
begin
  Result := True;
  if AReader.Name = '--changed' then
  begin
    // Basis optional: --changed, --changed=dev oder --changed dev
    AOptions.ChangedMergeBase := True;
    AOptions.ChangedRef := TCommandLineOptions.DefaultChangedBase;
    if AReader.OptionalValue(mValue) then
    begin
      AOptions.ChangedRef := mValue;
    end;
  end
  else if AReader.Name = '--affected-tests' then
  begin
    // Basis optional wie bei --changed: --affected-tests, --affected-tests=dev oder --affected-tests dev
    AOptions.AffectedTests := True;
    if AReader.OptionalValue(mValue) then
    begin
      AOptions.AffectedBase := mValue;
    end;
  end
  else if AReader.Name = '--timings' then
  begin
    // Datei optional: --timings, --timings=profil.md oder --timings profil.md
    AOptions.Timings := True;
    if AReader.OptionalValue(mValue) then
    begin
      AOptions.TimingsFile := mValue;
    end;
  end
  else
  begin
    Result := False;
  end;
end;

class function TCommandLineOptions.Parse(const AArgs: TArray<string>): TCommandLineOptions;
var
  mReader: TArgReader;
  mTables: TOptionTables;
begin
  Result := Default(TCommandLineOptions);
  Result.LogLevel := DefaultLogLevel;
  Result.FailOn := TFailOn.Error;
  mTables := OptionTables(Result);
  mReader := Default(TArgReader);
  mReader.Args := AArgs;
  mReader.Index := Low(AArgs) - 1;
  while mReader.Next do
  begin
    // --stdio hängen Editoren an; ohne Bedeutung für den Server.
    if not ApplyTabled(Result, mReader, mTables) and not ApplyOptional(Result, mReader)
      and (mReader.Name <> '--stdio') then
    begin
      AddWarning(Result, Format('Unbekannter Parameter "%s" wird ignoriert', [mReader.Arg]));
    end;
  end;
  // Mit --affected-tests gilt --include-uncommitted für dessen Basis, nicht als --changed.
  if (Result.IncludeUncommitted or Result.ChangedLines) and (Result.ChangedRef = '') and not Result.AffectedTests then
  begin
    // Ohne Ref gilt --changed mit der Standardbasis.
    Result.ChangedRef := DefaultChangedBase;
    Result.ChangedMergeBase := True;
  end;
end;

class function TCommandLineOptions.FromProcess: TCommandLineOptions;
var
  Args: TArray<string>;
  I: Integer;
begin
  SetLength(Args, ParamCount);
  for I := 1 to ParamCount do
  begin
    Args[I - 1] := ParamStr(I);
  end;
  Result := Parse(Args);
end;

end.
