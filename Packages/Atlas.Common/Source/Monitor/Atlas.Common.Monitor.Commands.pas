unit Atlas.Common.Monitor.Commands;

// Befehle des Prüffensters von AtlasMonitor (#1900): die zentrale Liste aller Kommandozeilenbefehle von AtlasServer,
// die das Fenster anbietet, mit Namen in Deutsch und Englisch, Art des Ergebnisses (Befunde, Text, HTML-Seite) und
// dem Aufbau des Aufrufs je Ziel. Der Aufruf schreibt immer in eine Datei (--output bzw. Berichtsdatei), damit der
// Monitor stdout nicht lesen muss. „Aufruf kopieren“ zeigt denselben Aufruf ohne die Ausgabedatei für die CI.
// Ein Test vergleicht die Schalter hier mit denen der Befehlszeile des Servers, damit neue Befehle nachgezogen
// werden (Covered + Skipped = alle).

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TMonitorCommand = (Check, Metrics, Todos, FormatCheck, FormatWrite, FixDryRun, Fix, AffectedTests, Architecture,
    ArchitectureSave, ArchitectureCompare, Hotspots, Query, Replay);
  /// <summary>Was der Monitor nach dem Lauf zeigt: Befundliste (SARIF), Text (Markdown, Diff, CSV) oder eine
  /// interaktive HTML-Seite im eingebetteten Browser.</summary>
  TMonitorOutputKind = (Findings, Text, Html);
  {$SCOPEDENUMS OFF}

  /// <summary>Optionen des Prüffensters; leere Werte lassen den Schalter weg.</summary>
  TMonitorOptions = record
    /// <summary>hint, info, warning, error; '' = alle.</summary>
    MinSeverity: string;
    /// <summary>Regeln, durch Komma getrennt; '' = alle.</summary>
    Rules: string;
    Profile: string;
    /// <summary>Units (Name oder Glob), durch Komma getrennt.</summary>
    Units: string;
    /// <summary>--changed gegen die Merge-Base mit ChangedBase ('' = main).</summary>
    Changed: Boolean;
    ChangedBase: string;
    /// <summary>--diff gegen diesen Ref; hat Vorrang vor Changed.</summary>
    DiffRef: string;
    IncludeUncommitted: Boolean;
    ChangedLines: Boolean;
    Baseline: string;
    UpdateBaseline: Boolean;
    NoIndex: Boolean;
    /// <summary>--timings mit Datei neben der Ausgabe (Prüfen).</summary>
    Timings: Boolean;
    /// <summary>Regeln für --fix bzw. --fix-dry-run; '' = all.</summary>
    FixRules: string;
    /// <summary>Basis von --affected-tests; '' = Vorgabe des Servers.</summary>
    AffectedBase: string;
    /// <summary>Abfrage oder @name.</summary>
    Query: string;
    /// <summary>Gespeicherter Architekturstand (.json) für den Vergleich bzw. Zieldatei zum Speichern.</summary>
    ArchitectureFile: string;
    /// <summary>anfrage.json eines Absturzfalls.</summary>
    ReplayFile: string;
  end;

  TMonitorCommands = record
  public
    /// <summary>Name im Fenster, z. B. „Prüfen“.</summary>
    class function Text(ACommand: TMonitorCommand): string; static;
    class function OutputKind(ACommand: TMonitorCommand): TMonitorOutputKind; static;
    /// <summary>Braucht der Befehl ein Ziel (Ordner, Projekt, Gruppe, Datei)? Nur --replay nicht.</summary>
    class function NeedsTarget(ACommand: TMonitorCommand): Boolean; static;
    /// <summary>Ändert der Befehl Dateien (Formatieren schreiben, Sammelkorrektur, Baseline schreiben)? Dann fragt
    /// der Monitor vorher.</summary>
    class function Writes(ACommand: TMonitorCommand; const AOptions: TMonitorOptions): Boolean; static;
    /// <summary>Endung der Ausgabedatei: .sarif, .md, .diff, .txt, .html, .json.</summary>
    class function OutputExtension(ACommand: TMonitorCommand): string; static;
    /// <summary>Argumente für AtlasServer: ATarget das Ziel, AOutputFile die Ergebnisdatei ('' = ohne, für „Aufruf
    /// kopieren“), ALocale de oder en ('' = ohne).</summary>
    class function Arguments(ACommand: TMonitorCommand; const ATarget: string; const AOptions: TMonitorOptions;
      const AOutputFile, ALocale: string): TArray<string>; static;
    /// <summary>Datei des Zeitprofils zu AOutputFile (--timings).</summary>
    class function TimingsFileOf(const AOutputFile: string): string; static;
    /// <summary>Befehlszeile mit Anführungszeichen nach den Regeln von Windows.</summary>
    class function CommandLine(const AServer: string; const AArguments: TArray<string>): string; static;
    /// <summary>Alle Schalter, die der Monitor anbietet.</summary>
    class function CoveredSwitches: TArray<string>; static;
    /// <summary>Schalter des Servers, die der Monitor bewusst nicht anbietet (Protokoll, LSP/MCP, Editor, CI).
    /// </summary>
    class function SkippedSwitches: TArray<string>; static;
  end;

implementation

uses
  Atlas.Text.UpdateRun,
  Atlas.Common.Localization.Texts;

const
  cTexts: array[TMonitorCommand] of TAtlasText = (
    (De: 'Prüfen'; En: 'Check'),
    (De: 'Metriken'; En: 'Metrics'),
    (De: 'TODOs'; En: 'TODOs'),
    (De: 'Formatierung prüfen'; En: 'Check formatting'),
    (De: 'Formatierung schreiben'; En: 'Write formatting'),
    (De: 'Sammelkorrektur (Vorschau)'; En: 'Bulk fix (preview)'),
    (De: 'Sammelkorrektur anwenden'; En: 'Apply bulk fix'),
    (De: 'Betroffene Tests'; En: 'Affected tests'),
    (De: 'Architektur'; En: 'Architecture'),
    (De: 'Architektur: Stand speichern'; En: 'Architecture: save state'),
    (De: 'Architektur: mit Stand vergleichen'; En: 'Architecture: compare with state'),
    (De: 'Hotspots'; En: 'Hotspots'),
    (De: 'Code-Abfrage'; En: 'Code query'),
    (De: 'Absturzfall nachstellen'; En: 'Replay crash case'));

  cExtensions: array[TMonitorCommand] of string = ('.sarif', '.md', '.md', '.diff', '.txt', '.diff', '.txt', '.txt',
    '.html', '.json', '.html', '.html', '.txt', '.txt');

  cKinds: array[TMonitorCommand] of TMonitorOutputKind = (TMonitorOutputKind.Findings, TMonitorOutputKind.Text,
    TMonitorOutputKind.Text, TMonitorOutputKind.Text, TMonitorOutputKind.Text, TMonitorOutputKind.Text,
    TMonitorOutputKind.Text, TMonitorOutputKind.Text, TMonitorOutputKind.Html, TMonitorOutputKind.Text,
    TMonitorOutputKind.Html, TMonitorOutputKind.Html, TMonitorOutputKind.Text, TMonitorOutputKind.Text);

  cAll = 'all';

class function TMonitorCommands.Text(ACommand: TMonitorCommand): string;
begin
  Result := cTexts[ACommand].Text;
end;

class function TMonitorCommands.OutputKind(ACommand: TMonitorCommand): TMonitorOutputKind;
begin
  Result := cKinds[ACommand];
end;

class function TMonitorCommands.NeedsTarget(ACommand: TMonitorCommand): Boolean;
begin
  Result := ACommand <> TMonitorCommand.Replay;
end;

class function TMonitorCommands.Writes(ACommand: TMonitorCommand; const AOptions: TMonitorOptions): Boolean;
begin
  Result := (ACommand = TMonitorCommand.FormatWrite) or (ACommand = TMonitorCommand.Fix) or
    ((ACommand = TMonitorCommand.Check) and AOptions.UpdateBaseline);
end;

class function TMonitorCommands.OutputExtension(ACommand: TMonitorCommand): string;
begin
  Result := cExtensions[ACommand];
end;

class function TMonitorCommands.TimingsFileOf(const AOutputFile: string): string;
begin
  Result := ChangeFileExt(AOutputFile, '.timings.md');
end;

type
  /// <summary>Sammelt Argumente; leere Werte lassen den Schalter weg.</summary>
  TArgs = record
    Items: TArray<string>;
    procedure Add(const AArgument: string);
    procedure Value(const ASwitch, AValue: string);
    procedure Flag(const ASwitch: string; AOn: Boolean);
  end;

procedure TArgs.Add(const AArgument: string);
begin
  SetLength(Items, Length(Items) + 1);
  Items[High(Items)] := AArgument;
end;

procedure TArgs.Value(const ASwitch, AValue: string);
begin
  if AValue <> '' then
  begin
    Add(ASwitch);
    Add(AValue);
  end;
end;

procedure TArgs.Flag(const ASwitch: string; AOn: Boolean);
begin
  if AOn then
  begin
    Add(ASwitch);
  end;
end;

/// <summary>Auswahl der Dateien (--units, --changed/--diff, --include-uncommitted, --changed-lines), die alle
/// Befehle über ein Ziel kennen.</summary>
procedure AddSelection(var AArgs: TArgs; const AOptions: TMonitorOptions);
begin
  AArgs.Value('--units', AOptions.Units);
  if AOptions.DiffRef <> '' then
  begin
    AArgs.Value('--diff', AOptions.DiffRef);
  end
  else if AOptions.Changed then
  begin
    // Mit "=", damit der Server den Wert nicht für das nächste Argument hält.
    if AOptions.ChangedBase <> '' then
    begin
      AArgs.Add('--changed=' + AOptions.ChangedBase);
    end
    else
    begin
      AArgs.Add('--changed');
    end;
  end;
  AArgs.Flag('--include-uncommitted', AOptions.IncludeUncommitted);
  AArgs.Flag('--changed-lines', AOptions.ChangedLines);
end;

/// <summary>Regeln und Profil der Prüfung.</summary>
procedure AddRules(var AArgs: TArgs; const AOptions: TMonitorOptions);
begin
  AArgs.Value('--min-severity', AOptions.MinSeverity);
  AArgs.Value('--rules', AOptions.Rules);
  AArgs.Value('--profile', AOptions.Profile);
  AArgs.Value('--baseline', AOptions.Baseline);
  AArgs.Flag('--no-index', AOptions.NoIndex);
end;

function FixRulesOf(const AOptions: TMonitorOptions): string;
begin
  Result := AOptions.FixRules;
  if Result = '' then
  begin
    Result := cAll;
  end;
end;

procedure AddCheck(var AArgs: TArgs; const AOptions: TMonitorOptions; const AOutputFile: string);
begin
  AArgs.Value('--format', 'sarif');
  // Ohne Ausgabedatei (Aufruf für die CI) bleibt --fail-on beim Server; im Monitor zählt jeder Lauf als fertig.
  if AOutputFile <> '' then
  begin
    AArgs.Value('--fail-on', 'never');
  end;
  AddRules(AArgs, AOptions);
  AddSelection(AArgs, AOptions);
  AArgs.Flag('--update-baseline', AOptions.UpdateBaseline);
  if AOptions.Timings and (AOutputFile <> '') then
  begin
    AArgs.Value('--timings', TMonitorCommands.TimingsFileOf(AOutputFile));
  end
  else
  begin
    AArgs.Flag('--timings', AOptions.Timings);
  end;
  AArgs.Value('--output', AOutputFile);
end;

/// <summary>Befehle mit eigener Berichtsdatei statt --output; ohne Datei der Name aus AFallback.</summary>
procedure AddReport(var AArgs: TArgs; const ASwitch, AOutputFile, AFallback: string);
begin
  if AOutputFile <> '' then
  begin
    AArgs.Value(ASwitch, AOutputFile);
  end
  else
  begin
    AArgs.Value(ASwitch, AFallback);
  end;
end;

procedure AddCommand(var AArgs: TArgs; ACommand: TMonitorCommand; const AOptions: TMonitorOptions;
  const AOutputFile: string);
begin
  case ACommand of
    TMonitorCommand.Check:
      AddCheck(AArgs, AOptions, AOutputFile);
    TMonitorCommand.Metrics, TMonitorCommand.Todos:
      begin
        AArgs.Flag('--metrics', ACommand = TMonitorCommand.Metrics);
        AArgs.Flag('--todos', ACommand = TMonitorCommand.Todos);
        AddSelection(AArgs, AOptions);
        AArgs.Value('--output', AOutputFile);
      end;
    TMonitorCommand.FormatCheck, TMonitorCommand.FormatWrite:
      begin
        AArgs.Flag('--format-check', ACommand = TMonitorCommand.FormatCheck);
        AArgs.Flag('--format-write', ACommand = TMonitorCommand.FormatWrite);
        AArgs.Value('--format', 'diff');
        AddSelection(AArgs, AOptions);
        AArgs.Value('--output', AOutputFile);
      end;
    TMonitorCommand.FixDryRun, TMonitorCommand.Fix:
      begin
        AArgs.Value('--fix', FixRulesOf(AOptions));
        AArgs.Flag('--fix-dry-run', ACommand = TMonitorCommand.FixDryRun);
        AddSelection(AArgs, AOptions);
        AArgs.Value('--output', AOutputFile);
      end;
    TMonitorCommand.AffectedTests:
      begin
        if AOptions.AffectedBase <> '' then
        begin
          AArgs.Add('--affected-tests=' + AOptions.AffectedBase);
        end
        else
        begin
          AArgs.Add('--affected-tests');
        end;
        AArgs.Flag('--include-uncommitted', AOptions.IncludeUncommitted);
        AArgs.Value('--output', AOutputFile);
      end;
    TMonitorCommand.Architecture:
      AddReport(AArgs, '--architecture', AOutputFile, 'architecture.html');
    TMonitorCommand.ArchitectureSave:
      AddReport(AArgs, '--architecture', AOptions.ArchitectureFile, 'architecture.json');
    TMonitorCommand.ArchitectureCompare:
      begin
        AddReport(AArgs, '--architecture', AOutputFile, 'architecture.html');
        AArgs.Value('--compare', AOptions.ArchitectureFile);
      end;
    TMonitorCommand.Hotspots:
      AddReport(AArgs, '--hotspots', AOutputFile, 'hotspots.html');
    TMonitorCommand.Query:
      begin
        AArgs.Value('--query', AOptions.Query);
        AArgs.Value('--output', AOutputFile);
      end;
    TMonitorCommand.Replay:
      AArgs.Value('--replay', AOptions.ReplayFile);
  end;
end;

class function TMonitorCommands.Arguments(ACommand: TMonitorCommand; const ATarget: string;
  const AOptions: TMonitorOptions; const AOutputFile, ALocale: string): TArray<string>;
var
  mArgs: TArgs;
begin
  mArgs := Default(TArgs);
  if NeedsTarget(ACommand) then
  begin
    mArgs.Value('--check', ATarget);
  end;
  AddCommand(mArgs, ACommand, AOptions, AOutputFile);
  mArgs.Value('--locale', ALocale);
  Result := mArgs.Items;
end;

class function TMonitorCommands.CommandLine(const AServer: string; const AArguments: TArray<string>): string;
var
  mBuilder: TStringBuilder;
  mArgument: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append(TUpdateNames.QuoteArgument(AServer));
    for mArgument in AArguments do
    begin
      mBuilder.Append(' ').Append(TUpdateNames.QuoteArgument(mArgument));
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TMonitorCommands.CoveredSwitches: TArray<string>;
begin
  Result := TArray<string>.Create('--check', '--format', '--output', '--fail-on', '--min-severity', '--rules',
    '--profile', '--units', '--changed', '--diff', '--include-uncommitted', '--changed-lines', '--baseline',
    '--update-baseline', '--no-index', '--timings', '--metrics', '--todos', '--format-check', '--format-write',
    '--fix', '--fix-dry-run', '--affected-tests', '--architecture', '--compare', '--hotspots', '--query', '--replay',
    '--locale');
end;

class function TMonitorCommands.SkippedSwitches: TArray<string>;
begin
  // Protokoll und Mitschnitt des Servers, LSP- und MCP-Betrieb, Editor-Prozess, Cache-Ordner (der Monitor leert
  // den Cache selbst), Auswertungen nur für die CI (Pfadwurzel von SARIF, Unterdrückungszahlen, Exit-Code einer
  // Abfrage, Mutanten für KI-Assistenten und CI).
  Result := TArray<string>.Create('--log', '--log-level', '--log-names', '--trace', '--mcp', '--root', '--restricted',
    '--clientprocessid', '--stdio', '--clear-cache', '--index-cache', '--source-root', '--suppression-stats',
    '--fail-on-match', '--mutate', '--routine', '--operators');
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Monitor.Commands', cTexts);

end.
