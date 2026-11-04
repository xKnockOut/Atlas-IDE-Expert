unit Atlas.IDE.Welcome.Setup;

// Bereich „<Projekt> für Atlas einrichten“ in der IDE (#759): Quelle des
// Bereichs (IAtlasSetupSource) und Bereich atlas.setup der Willkommensseite.
// - Ziel ist das aktive Projekt; ohne offenes Projekt das oberste nicht
//   ausgeblendete der Liste „Wieder öffnen“ (kann eine Projektgruppe sein).
//   Ein noch nie gespeichertes Projekt hat keine Karte.
// - Schritt 2 „atlas.json anlegen“: Vorlage aus dem Ordner Vorlagen der
//   Installation (sonst die eingebaute Fassung), vorher gegen
//   atlas.schema.json geprüft und im Dialog gezeigt; geschrieben als UTF-8
//   ohne BOM mit CRLF neben die .dproj bzw. .groupproj. Eine vorhandene
//   atlas.json oder delphi-lsp.json wird nie überschrieben.
// - Schritt 3 „Baseline erzeugen“: derselbe Weg wie „Baseline des Projekts
//   aktualisieren“ (#97, atlas.updateBaseline, die Komposition reicht ihn
//   herein); danach stehen die neuen Treffer der Zusammenfassung auf 0.
// - Schritt 4 „Suchpfade und Defines prüfen“: Projektkontext der aktiven
//   Konfiguration (#396), Dateien des Projekts und .dproj im Hintergrund
//   (Atlas.Core.Projects.PathCheck); das Ergebnis kommt in den Abschnitt
//   "setup" der Projekt-Zusammenfassung. Ein Klick öffnet die Projektoptionen.
//   $(…) in Suchpfaden löst TAtlasIdeProjectContext.Macros auf (IDE vor
//   Prozess); bleibt ein Makro unbekannt, fällt der Pfad weg und die Funde
//   gelten als unsicher (mit dem Makro in der Karte).
//   Projektgruppe: Ist eine Gruppe mit mehreren Projekten geöffnet (oder das
//   Ziel eine .groupproj), läuft die Prüfung für jedes ihrer Projekte; die
//   Funde stehen je Projekt in dessen Zusammenfassung, die Karte fasst sie
//   zusammen (TAtlasWelcomeSetup.Combined).
// - „Für dieses Projekt nicht mehr fragen“ steht ebenfalls dort
//   ("setup.dismissed") und gilt dauerhaft; der Befehl „Projekt für Atlas
//   einrichten“ (Atlas.ProjectSetup) hebt es auf.
// - „Neu mit Atlas“: die Komposition reicht das Erzeugen-Menü mit den
//   Dateivorlagen herein (Atlas.IDE.Generate.NewFile).
// - welcomePage.projectSetup aus: kein Bereich, kein Befehl; mit
//   welcomePage.newFromTemplate aus fehlen nur die Knöpfe „Neu mit Atlas“.
// Jeder Schritt läuft nur auf Klick. Meldungen mit Pfaden nur in die
// Meldungsansicht; ins Protokoll kommt nur, was ohne Pfade auskommt.
// Pfadprüfung, Gruppen und Lesen von Dateien: Atlas.IDE.Welcome.Setup.Paths.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Generate.FileTemplates,
  Atlas.Core.Welcome.Setup,
  Atlas.UI.Welcome.Setup,
  Atlas.IDE.Welcome.Setup.Paths;

type
  /// <summary>Ende des Baseline-Laufs im Hauptthread; ATotal und AFiles nur mit ASucceeded.</summary>
  TAtlasSetupBaselineDone = reference to procedure(ASucceeded: Boolean; ATotal, AFiles: Integer;
    const AError: string);
  /// <summary>Startet atlas.updateBaseline für AProject; '' = gestartet, sonst der Grund in der Sprache der
  /// Oberfläche (ADone kommt dann nicht).</summary>
  TAtlasSetupBaselineStart = reference to function(const AProject: string;
    const ADone: TAtlasSetupBaselineDone): string;
  TAtlasSetupNewFile = reference to procedure(AKind: TAtlasNewFileKind);

  TAtlasIdeSetup = class(TInterfacedObject, IAtlasSetupSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts: vor „Projekte“.</summary>
    Order = 15;
  private type
    /// <summary>Was die Komposition hereinreicht.</summary>
    THooks = record
      Message: TProc<string>;
      StartBaseline: TAtlasSetupBaselineStart;
      NewFile: TAtlasSetupNewFile;
    end;

    /// <summary>Baseline-Lauf dieser Sitzung (gilt nur für sein Projekt).</summary>
    TBaselineRun = record
      Project: string;
      Run: TAtlasSetupRun;
      Started: UInt64;
      Total: Integer;
      Files: Integer;
      Error: string;
    end;

    /// <summary>Pfadprüfung dieser Sitzung (gilt nur für ihr Projekt).</summary>
    TPathsRun = record
      Project: string;
      Run: TAtlasSetupRun;
      Started: UInt64;
      Error: string;
    end;
  private
    FHooks: THooks;
    FStarted: Boolean;
    FTitle: string;
    FShown: Boolean;
    FListener: Integer;
    FQueued: Boolean;
    /// <summary>Wechsel des aktiven Projekts meldet die IDE nicht: einmal je Sekunde vergleichen.</summary>
    FWatch: TTimer;
    FWatched: string;
    FBaseline: TBaselineRun;
    FPaths: TPathsRun;
    FThread: TThread;
    procedure WatchTick(Sender: TObject);
    procedure ProjectsChanged(const AId: string);
    procedure BaselineFinished(const AProject: string; ASucceeded: Boolean; ATotal, AFiles: Integer;
      const AError: string);
    procedure PathsFinished(const AProject: string; const ARuns: TArray<TAtlasSetupPathRun>);
    function ShouldShow: Boolean;
  public
    /// <summary>AMessage: Zeile in die Meldungsansicht; AStartBaseline: atlas.updateBaseline (#97);
    /// ANewFile: Erzeugen-Menü mit den Dateivorlagen.</summary>
    constructor Create(const AMessage: TProc<string>; const AStartBaseline: TAtlasSetupBaselineStart;
      const ANewFile: TAtlasSetupNewFile);
    destructor Destroy; override;
    /// <summary>Bereich, Fabrik und Beobachter anmelden.</summary>
    procedure Start;
    /// <summary>Alles abmelden (beim Entladen); wartet kurz auf eine laufende Prüfung.</summary>
    procedure Stop;
    /// <summary>Nach geänderten Einstellungen, Projekten oder Schritten: Titel, Sichtbarkeit und Inhalt neu.
    /// </summary>
    procedure Refresh;
    function Section: TAtlasWelcomeSection;
    /// <summary>Befehl „Projekt für Atlas einrichten“: hebt „nicht mehr fragen“ für das Ziel auf.</summary>
    procedure Ask;
    /// <summary>welcomePage.enabled und welcomePage.projectSetup an?</summary>
    class function Active: Boolean; static;
    { IAtlasSetupSource }
    function Card: TAtlasSetupCard;
    procedure CreateConfig(ATemplate: TAtlasSetupTemplate);
    procedure StartBaseline;
    procedure CheckPaths;
    procedure OpenOptions;
    procedure OpenProject;
    procedure Dismiss;
    procedure NewFile(AKind: TAtlasNewFileKind);
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Setup,
  Atlas.Core.Projects.PathCheck,
  Atlas.Core.Projects.Baseline,
  Atlas.Core.Settings.SchemaData,
  Atlas.UI.Welcome.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.SetupPreview,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Projects.Summaries,
  Atlas.IDE.Foundation.Host;

type
  /// <summary>Summe der Funde aller Projekte einer Pfadprüfung (nur Zahlen, fürs Protokoll).</summary>
  TPathTotals = record
    Files: Integer;
    Units: Integer;
    Defines: Integer;
    Uncertain: Integer;
  end;

{ Hilfen }

function FileThere(const AFileName: string): Boolean;
begin
  Result := FileExists(AFileName);
end;

procedure Report(ASelf: TAtlasIdeSetup; const AText: string);
begin
  if Assigned(ASelf.FHooks.Message) then
  begin
    ASelf.FHooks.Message(AText);
  end;
end;

/// <summary>Projektdatei eines Eintrags aus „Wieder öffnen“; '' fehlt sie oder ist sie ausgeblendet.</summary>
function RecentTarget(const ARecent: string): string;
var
  mSummary: TAtlasProjectSummary;
begin
  Result := TAtlasIdeProjectSummaries.ProjectFileOf(ARecent);
  // „Aus Liste entfernen“ (#592) gilt auch hier.
  if not FileExists(Result) or (TAtlasProjectSummaries.Load(TAtlasIdeProjectSummaries.Folder, Result, mSummary) and
    mSummary.Hidden) then
  begin
    Result := '';
  end;
end;

/// <summary>Ziel der Karte; AOpen = es ist in der IDE geöffnet. '' ohne Projekt.</summary>
function Target(out AOpen: Boolean): string;
var
  mProject: IOTAProject;
  mRecent: string;
begin
  Result := '';
  AOpen := False;
  mProject := GetActiveProject;
  if mProject <> nil then
  begin
    // Noch nie gespeichert: kein Ordner für atlas.json, keine Karte.
    Result := TAtlasIdeProjectSummaries.ProjectFileOf(mProject.FileName);
    AOpen := FileExists(Result);
    if not AOpen then
    begin
      Result := '';
    end;
    Exit;
  end;
  try
    for mRecent in TAtlasIdeWelcomeSearch.ClosedProjects do
    begin
      Result := RecentTarget(mRecent);
      if Result <> '' then
      begin
        AOpen := TAtlasIdeSetupPaths.OpenProjectOf(Result) <> nil;
        Exit;
      end;
    end;
  except
    // Registry nicht lesbar: ohne Ziel statt eines Fehlers in der Willkommensseite.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  Result := '';
end;

/// <summary>Ziel der Karte; '' mit Meldung, wenn es keins gibt.</summary>
function TargetOrReport(ASelf: TAtlasIdeSetup; out AOpen: Boolean): string;
begin
  Result := Target(AOpen);
  if Result = '' then
  begin
    Report(ASelf, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupNoProject));
  end;
end;

/// <summary>Dateien neben AProject und Abschnitte der Zusammenfassung.</summary>
function FactsOf(const AProject: string; out ASummary: TAtlasProjectSummary): TAtlasSetupFacts;
begin
  Result := Default(TAtlasSetupFacts);
  Result.Setup := TAtlasProjectSetup.Empty;
  ASummary := TAtlasProjectSummary.Create(AProject);
  if AProject = '' then
  begin
    Exit;
  end;
  Result.Project := AProject;
  Result.ConfigExists := TAtlasProjectSetups.ExistingConfig(AProject, FileThere) <> '';
  Result.BaselineExists := TAtlasProjectBaselines.FileIn(ExtractFileDir(AProject),
    function(const AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end) <> '';
  if TAtlasProjectSummaries.Load(TAtlasIdeProjectSummaries.Folder, AProject, ASummary) then
  begin
    Result.Setup := ASummary.Setup;
  end;
end;

/// <summary>Projektgruppe: Prüfung je Projekt, die Karte fasst sie zusammen.</summary>
procedure CombineGroup(var ACard: TAtlasSetupCard; const AMembers: TArray<string>);
var
  mOther: TAtlasProjectSummary;
  mMember: string;
  mItem: TAtlasSetupMember;
  mCombined: TArray<TAtlasSetupMember>;
begin
  mCombined := nil;
  for mMember in AMembers do
  begin
    mItem.Project := mMember;
    mItem.Setup := TAtlasProjectSetup.Empty;
    if SameText(mMember, ACard.Project) then
    begin
      mItem.Setup := ACard.Facts.Setup;
    end
    else if TAtlasProjectSummaries.Load(TAtlasIdeProjectSummaries.Folder, mMember, mOther) then
    begin
      mItem.Setup := mOther.Setup;
    end;
    mCombined := mCombined + [mItem];
  end;
  ACard.GroupProjects := Length(AMembers);
  ACard.Facts.Setup := TAtlasWelcomeSetup.Combined(ACard.Project, ACard.Facts.Setup, mCombined, ACard.GroupChecked);
end;

/// <summary>Läufe dieser Sitzung gelten nur für ihr Projekt.</summary>
procedure AddRuns(ASelf: TAtlasIdeSetup; var ACard: TAtlasSetupCard);
begin
  if SameText(ASelf.FBaseline.Project, ACard.Project) then
  begin
    ACard.Baseline := ASelf.FBaseline.Run;
    ACard.BaselineStarted := ASelf.FBaseline.Started;
    ACard.BaselineTotal := ASelf.FBaseline.Total;
    ACard.BaselineFiles := ASelf.FBaseline.Files;
    ACard.BaselineError := ASelf.FBaseline.Error;
  end;
  if SameText(ASelf.FPaths.Project, ACard.Project) then
  begin
    ACard.Paths := ASelf.FPaths.Run;
    ACard.PathsStarted := ASelf.FPaths.Started;
    ACard.PathsError := ASelf.FPaths.Error;
  end;
end;

/// <summary>Text der Vorlage ATemplate (Ordner der Installation, sonst die eingebaute Fassung), gegen das Schema
/// geprüft und mit CRLF; False mit Meldung, wenn auch die eingebaute nicht passt.</summary>
function ConfigText(ASelf: TAtlasIdeSetup; ATemplate: TAtlasSetupTemplate; out AText: string): Boolean;
var
  mFolder: string;
  mIssues: TArray<string>;
begin
  mFolder := TAtlasProjectSetups.TemplateFolder(TAtlasIdeHost.InstallFolder, FileThere);
  AText := TAtlasProjectSetups.TemplateText(ATemplate, mFolder,
    function(const AFileName: string; out AContent: string): Boolean
    begin
      Result := TAtlasIdeSetupPaths.ReadText(AFileName, AContent);
    end);
  Result := TAtlasProjectSetups.ValidTemplate(AText, AtlasSchemaJson, mIssues);
  if not Result then
  begin
    // Beschädigte oder veraltete Datei der Installation: die eingebaute Fassung.
    TAtlasGuard.Log('Einrichtung: Vorlage ' + TAtlasProjectSetups.TemplateId(ATemplate) +
      ' passt nicht zum Schema, eingebaute Fassung');
    AText := TAtlasProjectSetups.BuiltIn(ATemplate);
    Result := TAtlasProjectSetups.ValidTemplate(AText, AtlasSchemaJson, mIssues);
  end;
  if not Result then
  begin
    Report(ASelf, TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupConfigInvalid,
      [TAtlasSetupTexts.TemplateCaption(ATemplate), string.Join('; ', mIssues)]));
    Exit;
  end;
  // CRLF wie die übrigen Dateien eines Delphi-Projekts.
  AText := StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #10, #13#10, [rfReplaceAll]);
end;

/// <summary>False mit Meldung, wenn es neben AProject schon eine atlas.json gibt.</summary>
function ConfigMissing(ASelf: TAtlasIdeSetup; const AProject: string): Boolean;
var
  mExisting: string;
begin
  mExisting := TAtlasProjectSetups.ExistingConfig(AProject, FileThere);
  Result := mExisting = '';
  if not Result then
  begin
    Report(ASelf, TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupConfigExists, [mExisting]));
    ASelf.Refresh;
  end;
end;

/// <summary>atlas.json schreiben: UTF-8 ohne BOM, wie atlas.json im Repository; atomar (Bericht N3).</summary>
function WriteConfig(ASelf: TAtlasIdeSetup; const AConfigFile, AText: string): Boolean;
begin
  Result := True;
  try
    TAtlasDataFile.Write(AConfigFile, AText);
  except
    on E: Exception do
    begin
      TAtlasGuard.Log('Einrichtung: atlas.json nicht geschrieben (' + E.ClassName + ')');
      Report(ASelf, TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupConfigFailed, [AConfigFile,
        E.Message]));
      Result := False;
    end;
  end;
end;

/// <summary>Ziel für einen Schritt, der das geöffnete Projekt braucht; ist es zu, wird es geöffnet und das
/// Ergebnis ist ''.</summary>
function OpenTarget(ASelf: TAtlasIdeSetup): string;
var
  mOpen: Boolean;
begin
  Result := '';
  mOpen := False;
  if Active then
  begin
    Result := TargetOrReport(ASelf, mOpen);
  end;
  if (Result <> '') and (not mOpen or (TAtlasIdeSetupPaths.OpenProjectOf(Result) = nil)) then
  begin
    ASelf.OpenProject;
    Result := '';
  end;
end;

/// <summary>Im Hauptthread: Optionen der aktiven Konfiguration, Dateien und Makros; bei einer Gruppe je Projekt.
/// </summary>
function JobsFor(const AProject: string): TArray<TAtlasSetupPathJob>;
var
  mMember: string;
  mIde: IOTAProject;
begin
  Result := nil;
  for mMember in TAtlasIdeSetupPaths.GroupOf(AProject) do
  begin
    mIde := TAtlasIdeSetupPaths.OpenProjectOf(mMember);
    if mIde <> nil then
    begin
      Result := Result + [TAtlasIdeSetupPaths.JobOf(mIde)];
    end;
  end;
  if Length(Result) = 0 then
  begin
    Result := [TAtlasIdeSetupPaths.JobOf(TAtlasIdeSetupPaths.OpenProjectOf(AProject))];
  end;
end;

/// <summary>Im Hintergrund: Pfade auflösen, .dproj und alle Dateien lesen, ein Projekt nach dem anderen; nil beim
/// Entladen.</summary>
function RunJobs(const AJobs: TArray<TAtlasSetupPathJob>; out ARuns: TArray<TAtlasSetupPathRun>): Boolean;
var
  mJob: TAtlasSetupPathJob;
begin
  ARuns := nil;
  for mJob in AJobs do
  begin
    if TAtlasShutdown.Signalled then
    begin
      Exit(False);
    end;
    ARuns := ARuns + [TAtlasIdeSetupPaths.Run(mJob)];
  end;
  Result := not TAtlasShutdown.Signalled;
end;

/// <summary>Funde des Projekts in dessen Zusammenfassung; die Karte einer Gruppe fasst sie zusammen.</summary>
procedure StoreRun(const ARun: TAtlasSetupPathRun; AStamp: TDateTime; var ATotals: TPathTotals);
var
  mCheck: TAtlasPathCheckResult;
  mMember: string;
begin
  // Kopien: Der Parameter darf nicht in die anonyme Methode.
  mCheck := ARun.Check;
  mMember := ARun.Project;
  TAtlasProjectSummaries.Update(TAtlasIdeProjectSummaries.Folder, mMember,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.Setup := TAtlasWelcomeSetup.Checked(ASummary.Setup, mMember, mCheck, AStamp);
    end);
  Inc(ATotals.Files, mCheck.Files);
  Inc(ATotals.Units, Length(mCheck.MissingUnits));
  Inc(ATotals.Defines, Length(mCheck.UndefinedDefines));
  Inc(ATotals.Uncertain, TAtlasPathCheckResult.UncertainIn(mCheck.MissingUnits) +
    TAtlasPathCheckResult.UncertainIn(mCheck.UndefinedDefines));
end;

{ TAtlasIdeSetup }

constructor TAtlasIdeSetup.Create(const AMessage: TProc<string>; const AStartBaseline: TAtlasSetupBaselineStart;
  const ANewFile: TAtlasSetupNewFile);
begin
  inherited Create;
  FHooks.Message := AMessage;
  FHooks.StartBaseline := AStartBaseline;
  FHooks.NewFile := ANewFile;
  FListener := -1;
end;

destructor TAtlasIdeSetup.Destroy;
begin
  Stop;
  inherited;
end;

class function TAtlasIdeSetup.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.WelcomePage and TAtlasIdeSettings.Current.WelcomePageProjectSetup;
end;

procedure TAtlasIdeSetup.Start;
var
  Keep: IAtlasSetupSource;
begin
  FStarted := True;
  Keep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.Setup,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeSetupFrame;
    begin
      Frame := TAtlasWelcomeSetupFrame.Create(AOwner);
      Frame.Source := Keep;
      Result := Frame;
    end);
  // Projekte geöffnet, geschlossen oder gebaut: Ziel und Schritte neu.
  if FListener < 0 then
  begin
    FListener := TAtlasWelcomeSections.Default.AddListener(
      procedure(AId: string)
      begin
        ProjectsChanged(AId);
      end);
  end;
  FTitle := '';
  if FWatch = nil then
  begin
    FWatch := TTimer.Create(nil);
    FWatch.Interval := 1000;
    FWatch.OnTimer := WatchTick;
  end;
  FWatch.Enabled := True;
  Refresh;
end;

procedure TAtlasIdeSetup.WatchTick(Sender: TObject);
var
  Open: Boolean;
  Project: string;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      // Anderes aktives Projekt in der Projektverwaltung: Karte für dieses Projekt.
      Project := Target(Open);
      if SameText(Project, FWatched) then
      begin
        Exit;
      end;
      FWatched := Project;
      Refresh;
    end);
end;

procedure TAtlasIdeSetup.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FStarted := False;
  FreeAndNil(FWatch);
  if FListener >= 0 then
  begin
    TAtlasWelcomeSections.Default.RemoveListener(FListener);
  end;
  FListener := -1;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.Setup);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.Setup);
  if FThread <> nil then
  begin
    // ReadText liest nach dem Abbruchsignal nichts mehr; die Prüfung endet gleich.
    TAtlasShutdown.WaitForThreads([FThread]);
    if FThread.Finished then
    begin
      FreeAndNil(FThread);
    end
    else
    begin
      FThread.FreeOnTerminate := True;
      FThread := nil;
    end;
  end;
end;

procedure TAtlasIdeSetup.ProjectsChanged(const AId: string);
var
  Keep: IAtlasSetupSource;
begin
  // Nur auf „Projekte“: Ein eigenes Changed löst hier nichts aus (keine Schleife).
  if not FStarted or (AId <> TAtlasWelcomeIds.Projects) or FQueued then
  begin
    Exit;
  end;
  FQueued := True;
  // Keep hält die Quelle, bis der Eintrag gelaufen ist.
  Keep := Self;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if Keep = nil then
      begin
        Exit;
      end;
      FQueued := False;
      Refresh;
    end);
end;

function TAtlasIdeSetup.ShouldShow: Boolean;
begin
  Result := Active and Card.Visible;
end;

function TAtlasIdeSetup.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.Setup, TAtlasSetupTexts.TitleText(Card), Order,
    TAtlasWelcomeColumn.Left,
    function: Boolean
    begin
      // Abnahme: Bei vollständiger Einrichtung (und ohne „Neu mit Atlas“) erscheint keine Karte.
      Result := FStarted and ShouldShow;
      FShown := Result;
    end);
end;

procedure TAtlasIdeSetup.Refresh;
var
  Next: TAtlasWelcomeSection;
  Shown: Boolean;
begin
  if not FStarted then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      Next := Section;
      // Titel mit dem Projektnamen (oder nach einem Sprachwechsel): neu anmelden; Add meldet allen Beobachtern.
      if Next.Title <> FTitle then
      begin
        FTitle := Next.Title;
        FShown := ShouldShow;
        TAtlasWelcomeSections.Default.Add(Next);
        Exit;
      end;
      Shown := ShouldShow;
      if Shown <> FShown then
      begin
        // Karte erscheint oder verschwindet: Die Willkommensseite ordnet neu.
        FShown := Shown;
        TAtlasWelcomeSections.Default.Changed;
        Exit;
      end;
      TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Setup);
    end);
end;

function TAtlasIdeSetup.Card: TAtlasSetupCard;
var
  mOpen: Boolean;
  mSummary: TAtlasProjectSummary;
  mMembers: TArray<string>;
begin
  Result := TAtlasSetupCard.Empty;
  if not FStarted or not Active then
  begin
    Exit;
  end;
  Result.ShowNew := TAtlasWelcomeSetup.ShowNew(True, TAtlasIdeSettings.Current.WelcomePageNewFromTemplate,
    GetActiveProject <> nil);
  Result.Project := Target(mOpen);
  if Result.Project = '' then
  begin
    Exit;
  end;
  Result.ProjectOpen := mOpen;
  Result.ProjectName := TAtlasWelcomeSetup.NameOf(Result.Project);
  Result.Facts := FactsOf(Result.Project, mSummary);
  mMembers := TAtlasIdeSetupPaths.GroupOf(Result.Project);
  if Length(mMembers) > 0 then
  begin
    CombineGroup(Result, mMembers);
  end;
  Result.ConfigName := ExtractFileName(TAtlasProjectSetups.ExistingConfig(Result.Project, FileThere));
  Result.ShowCard := TAtlasWelcomeSetup.ShowCard(True, Result.Facts);
  if mSummary.Rules.Known then
  begin
    Result.BaselineNewHits := mSummary.Rules.NewHits;
  end;
  AddRuns(Self, Result);
end;

procedure TAtlasIdeSetup.CreateConfig(ATemplate: TAtlasSetupTemplate);
var
  mTemplate: TAtlasSetupTemplate;
begin
  mTemplate := ATemplate;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mProject, mText, mConfigFile: string;
      mOpen: Boolean;
    begin
      if not Active then
      begin
        Exit;
      end;
      mProject := TargetOrReport(Self, mOpen);
      if (mProject = '') or not ConfigMissing(Self, mProject) or not ConfigText(Self, mTemplate, mText) then
      begin
        Exit;
      end;
      mConfigFile := TAtlasProjectSetups.ConfigTarget(mProject);
      // Während der Vorschau angelegt (etwa im Editor): nicht überschreiben.
      if not TAtlasSetupPreviewDialog.Confirm(ExtractFileName(mConfigFile), ExtractFileName(mProject),
        TAtlasSetupTexts.TemplateCaption(mTemplate), mText, nil) or not ConfigMissing(Self, mProject) or
        not WriteConfig(Self, mConfigFile, mText) then
      begin
        Exit;
      end;
      TAtlasGuard.Log('Einrichtung: atlas.json angelegt (Vorlage ' + TAtlasProjectSetups.TemplateId(mTemplate) + ')');
      Report(Self, TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupConfigWritten, [mConfigFile]));
      // Abnahme: Schritt 2 ist danach abgehakt.
      Refresh;
    end);
end;

procedure TAtlasIdeSetup.StartBaseline;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mProject, mReason: string;
      mKeep: IAtlasSetupSource;
    begin
      if not Assigned(FHooks.StartBaseline) then
      begin
        Exit;
      end;
      mProject := OpenTarget(Self);
      if (mProject = '') or ((FBaseline.Run = TAtlasSetupRun.Running) and SameText(FBaseline.Project, mProject)) then
      begin
        Exit;
      end;
      FBaseline := Default(TBaselineRun);
      FBaseline.Project := mProject;
      // Keep hält die Quelle bis zur Antwort des Servers.
      mKeep := Self;
      mReason := FHooks.StartBaseline(mProject,
        procedure(ASucceeded: Boolean; ATotal, AFiles: Integer; const AError: string)
        begin
          if mKeep <> nil then
          begin
            BaselineFinished(mProject, ASucceeded, ATotal, AFiles, AError);
          end;
        end);
      if mReason <> '' then
      begin
        FBaseline.Run := TAtlasSetupRun.Failed;
        FBaseline.Error := mReason;
      end
      else
      begin
        FBaseline.Run := TAtlasSetupRun.Running;
        FBaseline.Started := TThread.GetTickCount64;
      end;
      Refresh;
    end);
end;

procedure TAtlasIdeSetup.BaselineFinished(const AProject: string; ASucceeded: Boolean; ATotal, AFiles: Integer;
  const AError: string);
var
  Stamp: TDateTime;
begin
  if not FStarted then
  begin
    Exit;
  end;
  if ASucceeded then
  begin
    Stamp := TAtlasIdeProjectSummaries.StampUtc;
    // Abnahme: Nach der Baseline sind die neuen Treffer 0 (alle stehen in der Baseline).
    TAtlasProjectSummaries.Update(TAtlasIdeProjectSummaries.Folder, AProject,
      procedure(var ASummary: TAtlasProjectSummary)
      begin
        TAtlasWelcomeSetup.BaselineWritten(ASummary.Rules, Stamp);
      end);
  end;
  if not SameText(FBaseline.Project, AProject) then
  begin
    Exit;
  end;
  FBaseline.Total := ATotal;
  FBaseline.Files := AFiles;
  FBaseline.Error := AError;
  if ASucceeded then
  begin
    FBaseline.Run := TAtlasSetupRun.Done;
  end
  else
  begin
    FBaseline.Run := TAtlasSetupRun.Failed;
  end;
  Refresh;
end;

procedure TAtlasIdeSetup.CheckPaths;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mProject: string;
      mJobs: TArray<TAtlasSetupPathJob>;
      mKeep: IAtlasSetupSource;
    begin
      mProject := OpenTarget(Self);
      if (mProject = '') or ((FThread <> nil) and not FThread.Finished) then
      begin
        Exit;
      end;
      FreeAndNil(FThread);
      mJobs := JobsFor(mProject);
      FPaths := Default(TPathsRun);
      FPaths.Project := mProject;
      FPaths.Run := TAtlasSetupRun.Running;
      FPaths.Started := TThread.GetTickCount64;
      Refresh;
      // Keep hält die Quelle, bis das Ergebnis im Hauptthread angekommen ist.
      mKeep := Self;
      FThread := TThread.CreateAnonymousThread(
        procedure
        var
          mRuns: TArray<TAtlasSetupPathRun>;
        begin
          if not RunJobs(mJobs, mRuns) then
          begin
            Exit;
          end;
          TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
            procedure
            begin
              if mKeep <> nil then
              begin
                PathsFinished(mProject, mRuns);
              end;
            end);
        end);
      FThread.FreeOnTerminate := False;
      FThread.Start;
    end);
end;

procedure TAtlasIdeSetup.PathsFinished(const AProject: string; const ARuns: TArray<TAtlasSetupPathRun>);
var
  mRun: TAtlasSetupPathRun;
  mStamp: TDateTime;
  mError: string;
  mTotals: TPathTotals;
begin
  if not FStarted then
  begin
    Exit;
  end;
  mError := '';
  mTotals := Default(TPathTotals);
  mStamp := TAtlasIdeProjectSummaries.StampUtc;
  for mRun in ARuns do
  begin
    if mRun.Error = '' then
    begin
      StoreRun(mRun, mStamp, mTotals);
    end
    else if mError = '' then
    begin
      mError := mRun.Error;
    end;
  end;
  // Anonym: nur Zahlen, keine Pfade und keine Makronamen.
  TAtlasGuard.Log(Format('Einrichtung: %d Projekte, %d Dateien geprüft, %d Units fehlen, %d Defines ohne Quelle, ' +
    '%d davon unsicher', [Length(ARuns), mTotals.Files, mTotals.Units, mTotals.Defines, mTotals.Uncertain]));
  if SameText(FPaths.Project, AProject) then
  begin
    FPaths.Run := TAtlasSetupRun.Done;
    if mError <> '' then
    begin
      FPaths.Run := TAtlasSetupRun.Failed;
      FPaths.Error := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupPathsFailed, [mError]);
    end;
  end;
  Refresh;
end;

procedure TAtlasIdeSetup.OpenOptions;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Project: string;
      Open: Boolean;
      Ide: IOTAProject;
    begin
      Project := Target(Open);
      Ide := TAtlasIdeSetupPaths.OpenProjectOf(Project);
      if Ide = nil then
      begin
        OpenProject;
        Exit;
      end;
      // Dialog „Projektoptionen“ der IDE (Suchpfade unter Delphi-Compiler, Defines unter Bedingungen).
      if Ide.ProjectOptions <> nil then
      begin
        Ide.ProjectOptions.EditOptions;
      end;
      Refresh;
    end);
end;

procedure TAtlasIdeSetup.OpenProject;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Project: string;
      Open: Boolean;
      Actions: IOTAActionServices;
    begin
      Project := TargetOrReport(Self, Open);
      if (Project <> '') and not Open and Supports(BorlandIDEServices, IOTAActionServices, Actions) then
      begin
        Actions.OpenProject(Project, True);
      end;
    end);
end;

procedure TAtlasIdeSetup.Dismiss;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Project: string;
      Open: Boolean;
      Stamp: TDateTime;
    begin
      Project := Target(Open);
      if Project = '' then
      begin
        Exit;
      end;
      Stamp := TAtlasIdeProjectSummaries.StampUtc;
      // Abnahme: „Nicht mehr fragen“ wirkt dauerhaft (Projekt-Zusammenfassung, nicht die Sitzung).
      TAtlasProjectSummaries.Update(TAtlasIdeProjectSummaries.Folder, Project,
        procedure(var ASummary: TAtlasProjectSummary)
        begin
          ASummary.Setup.Known := True;
          ASummary.Setup.Dismissed := True;
          ASummary.Setup.DismissedAt := Stamp;
        end);
      Refresh;
    end);
end;

procedure TAtlasIdeSetup.Ask;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Project: string;
      Open: Boolean;
    begin
      Project := TargetOrReport(Self, Open);
      if Project = '' then
      begin
        Exit;
      end;
      TAtlasProjectSummaries.Update(TAtlasIdeProjectSummaries.Folder, Project,
        procedure(var ASummary: TAtlasProjectSummary)
        begin
          ASummary.Setup.Dismissed := False;
          ASummary.Setup.DismissedAt := 0;
        end);
      Refresh;
    end);
end;

procedure TAtlasIdeSetup.NewFile(AKind: TAtlasNewFileKind);
var
  Kind: TAtlasNewFileKind;
begin
  Kind := AKind;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      // Abnahme: newFromTemplate aus schaltet nur die Knöpfe ab, projectSetup aus alles.
      if not Active or not TAtlasIdeSettings.Current.WelcomePageNewFromTemplate or not Assigned(FHooks.NewFile) then
      begin
        Exit;
      end;
      FHooks.NewFile(Kind);
    end);
end;

end.
