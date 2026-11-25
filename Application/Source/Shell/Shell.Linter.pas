unit Shell.Linter;

// Host-Rolle Shell: Linter-Modus ohne Editor (#95). Fassade über die Befehle in Shell.Linter.*.
//
//   AtlasServer.exe --check Projekt.dproj --format sarif --output ergebnis.sarif
//
// Ziel ist eine .dproj (Hauptdatei und Units des Projekts), ein Ordner (alle
// .pas, .dpr, .dpk darunter) oder eine einzelne Datei. atlas.json im
// Ordner des Ziels gilt wie im Editor. Das Ergebnis geht auf stdout oder in
// die Datei aus --output, Meldungen zum Ablauf auf stderr.
// Mit --suppression-stats erscheint statt der Treffer die Auswertung der
// Unterdrückungskommentare je Regel; Exit-Code dann 0.
// Mit --metrics erscheinen statt der Treffer die Code-Metriken (#66): mit
// --format text der Markdown-Bericht, mit json die Metrikdaten; Grenzwerte
// aus atlas.json (Regeln metric-*, Option "max"); Exit-Code dann 0.
// Mit --todos erscheinen statt der Treffer die offenen TODO-Einträge (#68):
// mit --format text die Markdown-Übersicht, mit json die Daten; Marken aus
// atlas.json (Regel todo-comment, Option "keywords"); Exit-Code dann 0.
// Bekannte Treffer aus der Baseline (--baseline, sonst atlas-baseline.json
// neben atlas.json) werden ausgeblendet; --update-baseline schreibt sie aus
// den aktuellen Treffern neu (#97), Exit-Code dann 0. Dabei nennt es auf
// stderr hinzugekommene, entfernte und unveränderte Treffer und, bevor sie
// herausfallen, die Einträge ohne Datei (umbenannt, verschoben, gelöscht).
// Mit --format sarif trägt jedes Ergebnis partialFingerprints und mit
// Baseline baselineState; unveränderte und nicht mehr gefundene Treffer der
// Baseline stehen dort mit, zählen aber nicht für den Exit-Code.
// Mit --changed bzw. --diff werden nur die geänderten Dateien laut Git (#157)
// bzw. SVN (#276) geprüft, mit --changed-lines nur Treffer in geänderten Zeilen ausgegeben;
// zusammen mit der Baseline zählt ein Treffer nur, wenn er in einer geänderten
// Zeile liegt und nicht in der Baseline steht. Die Regeln prüfen jede Datei für
// sich, deshalb ergibt die Teilmenge dieselben Treffer wie ein voller Lauf.
// SARIF-Pfade sind relativ zur Quellwurzel (--source-root, sonst die
// Git-Wurzel über dem Ziel, sonst der Ordner des Ziels).
// Bei einer .dproj gelten deren Symbole für Plattform und Konfiguration aus
// atlas.json, und {$I}-Dateien werden über ihre Suchpfade gelesen (#860);
// sonst die Vordefinitionen von Delphi 13 für Win32 und $I aus dem Ordner der Datei.
// Symbolindex (#1112): Wie im Server und im MCP-Modus baut --check den Index des
// Projekts (Ordner, .dproj oder Ordner der Datei, mit index.projectGroup die
// ganze Gruppe) und liest dabei den gemeinsamen Index-Cache (--index-cache,
// sonst der Ordner des Servers), damit Regeln Typen aus anderen Units und der
// RTL kennen. --no-index prüft wie früher jede Datei für sich.
// --affected-tests (#1353, TLinterShell.AffectedTests): statt der Prüfung die
// DUnitX-Tests, die eine Änderung gegenüber der Basis betrifft; Ziel ist das
// Testprojekt (.dproj), die Projektgruppe (.groupproj) oder ein Ordner. Exit-Code
// 0, 2 wenn alle Tests nötig sind (die Ausgabe sagt warum), 3 bei Fehlern und
// mit tests.affected = false.
// Sammelkorrektur (#1352): --fix <Regeln|all> wendet je Datei die sicheren
// Korrekturen dieser Regeln an (TBulkFix: Konfidenz ab fix.minConfidence,
// Katalogfeld safeFix, bis zu drei Durchgänge, keine neuen Syntaxfehler) und
// schreibt alle geänderten Dateien oder keine, in ihrer Kodierung und mit ihren
// Zeilenenden; --fix-dry-run gibt stattdessen den vereinigten Diff aus. Es gelten
// --units, --changed, --diff, --changed-lines (nur Treffer in geänderten Zeilen),
// --baseline (deren Treffer bleiben) und --profile. Die Zusammenfassung (Regeln,
// Dateien, Korrekturen je Regel, übersprungene Treffer) steht auf stderr.
//
// Mit --timings (#1356) misst der Lauf die Prüfung je Unit und, über die
// Messung der Regel-Engine, je Regel (TCheckProfiler) und schreibt danach
// das Zeitprofil mit Indexzeit und Speicher als Markdown bzw. JSON in die
// Datei oder ohne Datei auf stderr. stdout und --output bleiben unverändert.
// Exit-Code: 1, wenn ein Treffer --fail-on erreicht (Standard error: mindestens
// ein Fehler; Baseline-Treffer zählen nie), sonst 0; 3 Aufruf- oder Lesefehler.
// Mit --fix zählen die Treffer, die nach der Korrektur bleiben.
// Formatieren ohne IDE (#1358): --format-check bzw. --format-write statt der
// Regeln. Dieselben Dateien wie --check (Ziel, --units, --changed/--diff,
// Ausschlüsse aus atlas.json), mit --changed-lines nur die geänderten Zeilen.
// Formatregeln wie „Dokument formatieren“: format.* aus atlas.json über
// .editorconfig über den Vorgaben (ohne die Einrückung der IDE-Optionen).
// Geschrieben wird atomar über eine Nachbardatei; Kodierung und Zeilenenden
// bleiben, außer format.endOfLine verlangt andere. Exit-Codes in
// Atlas.Common.Editing.FormatOutput.
// Wortgleiche Rümpfe (Kopien-Prüfung): --check-duplicates statt der Regeln, siehe Core.Linter.Duplicates.

interface

uses
  Core.CommandLine,
  Core.Linter.Host;

type
  TLinterShell = class
  public
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>--fix (#1352): Sammelkorrektur statt Prüfung; Run ruft sie, sobald --fix angegeben ist.</summary>
    class function Fix(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>--architecture (#1118): Architekturbericht des Ziels aus --check (sonst des aktuellen Ordners)
    /// als Markdown oder HTML nach der Endung der Datei, als .json der Stand für den Vergleich (#1121). Berichte
    /// vergleichen mit --compare, sonst mit architecture.baseline. Mit --compare steht der Text des Vergleichs auf
    /// stdout (bzw. in --output); Exit-Code 1, wenn eine Abweichung aus --fail-on (sonst architecture.failOn)
    /// vorkommt, sonst 0; bei Fehlern 3.</summary>
    class function Architecture(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>--query (#1351): Code-Abfrage über das Ziel aus --check (sonst den aktuellen Ordner) mit Symbolindex
    /// wie --check; Ergebnis als Text, JSON oder CSV (--format) auf stdout bzw. in --output. "@name" führt eine
    /// gespeicherte Abfrage aus. Exit-Code 0; 1 mit --fail-on-match (oder failIfAny der gespeicherten Abfrage),
    /// wenn sie etwas findet; 3 bei einem Fehler in der Abfrage, bei Aufruffehlern und bei query.enabled aus.
    /// </summary>
    class function Query(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>--hotspots (#1354): Hotspots des Ziels aus --check (sonst des aktuellen Ordners) samt Methoden und
    /// Änderungskopplung als Markdown, HTML oder JSON nach der Endung der Datei. Exit-Code 0; 3 ohne
    /// Versionsverwaltung, mit hotspots.enabled = false und bei Fehlern.</summary>
    class function Hotspots(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>--mutate (#1460): Mutanten einer Unit als Markdown, JSON oder Patch (--format text, json, diff),
    /// ohne zu bauen; Auswahl mit --routine und --operators, Symbole aus dem Projekt in --check. Exit-Code 0; 3 bei
    /// Aufruffehlern.</summary>
    class function Mutate(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>--format-check bzw. --format-write (#1358), siehe Kopf der Unit.</summary>
    class function Formatting(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>--clear-cache: löscht alle Index-Caches, die keine laufende Instanz nutzt (#184).</summary>
    class function ClearCache: Integer; static;
    /// <summary>--affected-tests (#1353): betroffene Tests als text, json oder dunitx (--format) auf stdout bzw. in
    /// --output. Exit-Code 0; 2, wenn alle Tests nötig sind; 3 bei Fehlern oder mit tests.affected = false.
    /// </summary>
    class function AffectedTests(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>--write-instructions bzw. --check-instructions (#2615): Anweisungsdateien für KI-Assistenten, siehe
    /// Core.Linter.Instructions.</summary>
    class function Instructions(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>Was die Befehle in Core.Linter.* von der Shell brauchen: Delphi-Versionen, git und svn,
    /// Arbeitsbereiche, Anweisungsdateien, Prüfregeln.</summary>
    class function Host: TCoreLinterHost; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Findings.Output,
  Atlas.Common.Index.CacheDirectory,
  Core.Linter.Output,
  Core.Linter.Check,
  Core.Linter.Fix,
  Core.Linter.Architecture,
  Core.Linter.Query,
  Core.Linter.Hotspots,
  Core.Linter.Mutation,
  Core.Linter.Formatting,
  Core.Linter.Duplicates,
  Core.Linter.AffectedTests,
  Core.Linter.Instructions,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Logging.Providers.StreamSink,
  Atlas.Common.Rules.InstructionFiles,
  Atlas.Common.Rules.Instructions,
  Shell.Composition.LinterRules,
  Platform.Server,
  Core.Bootstrap,
  Core.VersionControlChanges,
  Core.WorkspaceGroup,
  Shell.Composition.Platform,
  Shell.Composition.Instructions,
  Shell.Composition.CheckRefactorings;

type
{$SCOPEDENUMS ON}
  TLinterShellText = (Cleared);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TLinterShellText] of TAtlasText = (
    (De: '%d Index-Caches gelöscht in %s'; En: '%d index caches deleted in %s'));

/// <summary>Logger nur für Warnungen und Fehler auf stderr; stdout gehört dem Ergebnis.</summary>
function ErrorLogger: ILogger;
var
  mLogger: TLogger;
begin
  mLogger := TLogger.Create;
  Result := mLogger;
  mLogger.AddSink(TStreamLogSink.Create(TStdStreams.CreateError, True), TLogLevel.Warning);
end;

/// <summary>Gruppe über AConfigRoot mit AIndex. Als anonyme Methode statt TCoreBootstrap.ReadSourceText: Free
/// Pascal (Linux-Bau) bricht an der Umwandlung einer Klassenmethode in eine Methodenreferenz intern ab.</summary>
function NewGroup(const AConfigRoot: string; const AIndex: ISymbolIndex): TCoreWorkspaceGroup;
var
  mStore: IDocumentStore;
begin
  mStore := TDocumentStore.Create(
    function(const APath: string): string
    begin
      Result := TServerPlatform.CanonicalizePath(APath);
    end);
  Result := TCoreWorkspaceGroup.Create(ExcludeTrailingPathDelimiter(AConfigRoot), mStore, ErrorLogger, AIndex,
    'atlas-check-index', TShellPlatformAdapters.WorkspaceFactories,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TCoreBootstrap.ReadSourceText(AFileName, AText);
    end);
  Result.Refactorings := TShellCheckRefactorings.Create;
end;

function InstalledVersions: TArray<string>;
begin
  Result := TDelphiInstallation.Versions;
end;

function VcsAccess: TCoreVcsAccess;
begin
  Result := TShellPlatformAdapters.VcsAccess;
end;

function WriteInstructions(const ARoot: string; const ASettings: TServerSettings; AWrite: Boolean):
  TArray<TCoreInstructionsFile>;
const
  cStates: array[TInstructionsState] of TCoreInstructionsState = (TCoreInstructionsState.Current,
    TCoreInstructionsState.Stale, TCoreInstructionsState.Missing);
var
  mFiles: TArray<TInstructionsFile>;
  mIndex: Integer;
begin
  mFiles := TShellInstructions.Run(ARoot, ASettings, AWrite);
  Result := nil;
  SetLength(Result, Length(mFiles));
  for mIndex := 0 to High(mFiles) do
  begin
    Result[mIndex].FileName := mFiles[mIndex].FileName;
    Result[mIndex].State := cStates[mFiles[mIndex].State];
    Result[mIndex].Written := mFiles[mIndex].Written;
    Result[mIndex].Error := mFiles[mIndex].Error;
  end;
end;

{ TLinterShell }

class function TLinterShell.Host: TCoreLinterHost;
begin
  Result := Default(TCoreLinterHost);
  Result.InstalledVersions := InstalledVersions;
  Result.Vcs := VcsAccess;
  Result.NewGroup := NewGroup;
  Result.Instructions := WriteInstructions;
  Result.Rules := TShellLinterRules.Create;
end;

class function TLinterShell.Run(const AOptions: TCommandLineOptions): Integer;
begin
  if AOptions.FixRules <> nil then
  begin
    Result := Fix(AOptions);
  end
  else if AOptions.FormatCheck or AOptions.FormatWrite then
  begin
    Result := Formatting(AOptions);
  end
  else if AOptions.CheckDuplicates then
  begin
    Result := TLinterDuplicates.Run(AOptions, Host);
  end
  else
  begin
    Result := TLinterCheck.Run(AOptions, Host);
  end;
end;

class function TLinterShell.Fix(const AOptions: TCommandLineOptions): Integer;
begin
  Result := TLinterFix.Run(AOptions, Host);
end;

class function TLinterShell.Architecture(const AOptions: TCommandLineOptions): Integer;
begin
  Result := TLinterArchitecture.Run(AOptions, Host);
end;

class function TLinterShell.Query(const AOptions: TCommandLineOptions): Integer;
begin
  Result := TLinterQuery.Run(AOptions, Host);
end;

class function TLinterShell.Hotspots(const AOptions: TCommandLineOptions): Integer;
begin
  Result := TLinterHotspots.Run(AOptions, Host);
end;

class function TLinterShell.Mutate(const AOptions: TCommandLineOptions): Integer;
begin
  Result := TLinterMutation.Run(AOptions, Host);
end;

class function TLinterShell.Formatting(const AOptions: TCommandLineOptions): Integer;
begin
  Result := TLinterFormatting.Run(AOptions, Host);
end;

class function TLinterShell.Instructions(const AOptions: TCommandLineOptions): Integer;
begin
  Result := TLinterInstructions.Run(AOptions, Host);
end;

class function TLinterShell.ClearCache: Integer;
begin
  try
    TLinterOutput.Error(cTexts[TLinterShellText.Cleared].Fmt([TIndexCacheDirectory.Clear(
      TIndexCacheDirectory.DefaultRoot), TIndexCacheDirectory.DefaultRoot]));
    Result := TFindingsOutput.cExitClean;
  except
    on E: Exception do
    begin
      TLinterOutput.Error(Format('%s: %s', [E.ClassName, E.Message]));
      Result := TFindingsOutput.cExitFailure;
    end;
  end;
end;

class function TLinterShell.AffectedTests(const AOptions: TCommandLineOptions): Integer;
begin
  Result := TLinterAffectedTests.Run(AOptions, Host);
end;

initialization
  TAtlasTextTables.Add('Shell.Linter', cTexts);

end.
