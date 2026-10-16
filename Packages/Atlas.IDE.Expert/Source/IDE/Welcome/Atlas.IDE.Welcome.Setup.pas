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

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Setup,
  Atlas.Core.Projects.PathCheck,
  Atlas.Core.Generate.FileTemplates,
  Atlas.Core.Welcome.Setup,
  Atlas.UI.Welcome.Setup;

type
  /// <summary>Ende des Baseline-Laufs im Hauptthread; ATotal und AFiles nur mit ASucceeded.</summary>
  TAtlasSetupBaselineDone = reference to procedure(ASucceeded: Boolean; ATotal, AFiles: Integer;
    const AError: string);
  /// <summary>Startet atlas.updateBaseline für AProject; '' = gestartet, sonst der Grund in der Sprache der
  /// Oberfläche (ADone kommt dann nicht).</summary>
  TAtlasSetupBaselineStart = reference to function(const AProject: string;
    const ADone: TAtlasSetupBaselineDone): string;
  TAtlasSetupNewFile = reference to procedure(AKind: TAtlasNewFileKind);

  /// <summary>Ergebnis der Pfadprüfung eines Projekts (bei einer Gruppe eins je Projekt).</summary>
  TAtlasSetupPathRun = record
    Project: string;
    Check: TAtlasPathCheckResult;
    /// <summary>Grund, wenn die Prüfung dieses Projekts abbrach; '' sonst.</summary>
    Error: string;
  end;

  TAtlasIdeSetup = class(TInterfacedObject, IAtlasSetupSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts: vor „Projekte“.</summary>
    Order = 15;
  private
    FMessage: TProc<string>;
    FStartBaseline: TAtlasSetupBaselineStart;
    FNewFile: TAtlasSetupNewFile;
    FStarted: Boolean;
    FTitle: string;
    FShown: Boolean;
    FListener: Integer;
    FQueued: Boolean;
    /// <summary>Wechsel des aktiven Projekts meldet die IDE nicht: einmal je Sekunde vergleichen.</summary>
    FWatch: TTimer;
    FWatched: string;
    FBaselineProject: string;
    FBaseline: TAtlasSetupRun;
    FBaselineStarted: UInt64;
    FBaselineTotal: Integer;
    FBaselineFiles: Integer;
    FBaselineError: string;
    FPathsProject: string;
    FPaths: TAtlasSetupRun;
    FPathsStarted: UInt64;
    FPathsError: string;
    FThread: TThread;
    procedure WatchTick(Sender: TObject);
    procedure Report(const AText: string);
    procedure ProjectsChanged(const AId: string);
    procedure BaselineFinished(const AProject: string; ASucceeded: Boolean; ATotal, AFiles: Integer;
      const AError: string);
    procedure PathsFinished(const AProject: string; const ARuns: TArray<TAtlasSetupPathRun>);
    function ShouldShow: Boolean;
    class function ReadText(const AFileName: string; out AText: string): Boolean; static;
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
    /// <summary>Ziel der Karte; AOpen = es ist in der IDE geöffnet. '' ohne Projekt.</summary>
    class function Target(out AOpen: Boolean): string; static;
    /// <summary>Dateien neben AProject und Abschnitte der Zusammenfassung.</summary>
    class function FactsOf(const AProject: string; out ASummary: TAtlasProjectSummary): TAtlasSetupFacts; static;
    /// <summary>Projekte, deren Prüfung zu AProject gehört: bei einer .groupproj ihre Projekte, bei einem Projekt
    /// der geöffneten Gruppe mit mehreren Projekten alle Projekte der Gruppe; sonst leer.</summary>
    class function GroupOf(const AProject: string): TArray<string>; static;
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
  System.IOUtils,
  System.RegularExpressions,
  ToolsAPI,
  Atlas.Text.Defines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Projects.Baseline,
  Atlas.Core.Projects.Contract,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Welcome.Saved,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.SetupPreview,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Projects.Context,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.Projects;

function FileThere(const AFileName: string): Boolean;
begin
  Result := FileExists(AFileName);
end;

/// <summary>Offenes Projekt zur Projektdatei AFileName (.dproj); nil, wenn es nicht geöffnet ist.</summary>
function OpenProjectOf(const AFileName: string): IOTAProject;
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
begin
  Result := nil;
  if (AFileName = '') or not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Module := Modules.FindModule(AFileName);
  if Module <> nil then
    Supports(Module, IOTAProject, Result);
end;

{ TAtlasIdeSetup }

constructor TAtlasIdeSetup.Create(const AMessage: TProc<string>; const AStartBaseline: TAtlasSetupBaselineStart;
  const ANewFile: TAtlasSetupNewFile);
begin
  inherited Create;
  FMessage := AMessage;
  FStartBaseline := AStartBaseline;
  FNewFile := ANewFile;
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

class function TAtlasIdeSetup.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  // Abbruch beim Entladen: Die Prüfung liest dann nichts mehr.
  if TAtlasShutdown.Signalled or not FileExists(AFileName) then
    Exit(False);
  try
    AText := TFile.ReadAllText(AFileName);
    Result := True;
  except
    on Exception do
      Result := False;
  end;
end;

procedure TAtlasIdeSetup.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
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
    FListener := TAtlasWelcomeSections.Default.AddListener(
      procedure(AId: string)
      begin
        ProjectsChanged(AId);
      end);
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
        Exit;
      FWatched := Project;
      Refresh;
    end);
end;

procedure TAtlasIdeSetup.Stop;
begin
  if not FStarted then
    Exit;
  FStarted := False;
  FreeAndNil(FWatch);
  if FListener >= 0 then
    TAtlasWelcomeSections.Default.RemoveListener(FListener);
  FListener := -1;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.Setup);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.Setup);
  if FThread <> nil then
  begin
    // ReadText liest nach dem Abbruchsignal nichts mehr; die Prüfung endet gleich.
    TAtlasShutdown.WaitForThreads([FThread]);
    if FThread.Finished then
      FreeAndNil(FThread)
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
    Exit;
  FQueued := True;
  // Keep hält die Quelle, bis der Eintrag gelaufen ist.
  Keep := Self;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if Keep = nil then
        Exit;
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
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.Setup, TAtlasWelcomeSetupFrame.TitleText(Card), Order,
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
    Exit;
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

class function TAtlasIdeSetup.Target(out AOpen: Boolean): string;
var
  Project: IOTAProject;
  Recent: string;
  Summary: TAtlasProjectSummary;
begin
  Result := '';
  AOpen := False;
  Project := GetActiveProject;
  if Project <> nil then
  begin
    // Noch nie gespeichert: kein Ordner für atlas.json, keine Karte.
    Result := TAtlasIdeProjects.ProjectFileOf(Project.FileName);
    AOpen := FileExists(Result);
    if not AOpen then
      Result := '';
    Exit;
  end;
  try
    for Recent in TAtlasIdeWelcomeSearch.ClosedProjects do
    begin
      Result := TAtlasIdeProjects.ProjectFileOf(Recent);
      if not FileExists(Result) then
        Continue;
      // „Aus Liste entfernen“ (#592) gilt auch hier.
      if TAtlasProjectSummaries.Load(TAtlasIdeProjects.Folder, Result, Summary) and Summary.Hidden then
        Continue;
      AOpen := OpenProjectOf(Result) <> nil;
      Exit;
    end;
  except
    // Registry nicht lesbar: ohne Ziel statt eines Fehlers in der Willkommensseite.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  Result := '';
end;

class function TAtlasIdeSetup.FactsOf(const AProject: string; out ASummary: TAtlasProjectSummary): TAtlasSetupFacts;
begin
  Result := Default(TAtlasSetupFacts);
  Result.Setup := TAtlasProjectSetup.Empty;
  ASummary := TAtlasProjectSummary.Create(AProject);
  if AProject = '' then
    Exit;
  Result.Project := AProject;
  Result.ConfigExists := TAtlasProjectSetups.ExistingConfig(AProject, FileThere) <> '';
  Result.BaselineExists := TAtlasProjectBaselines.FileIn(ExtractFileDir(AProject),
    function(const AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end) <> '';
  if TAtlasProjectSummaries.Load(TAtlasIdeProjects.Folder, AProject, ASummary) then
    Result.Setup := ASummary.Setup;
end;

class function TAtlasIdeSetup.GroupOf(const AProject: string): TArray<string>;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Text, Member, FileName: string;
  Index: Integer;
  Inside: Boolean;
begin
  Result := nil;
  if AProject = '' then
    Exit;
  if TAtlasWelcomeSetup.IsGroup(AProject) then
  begin
    // Geschlossene Gruppe: Projekte aus der .groupproj.
    if ReadText(AProject, Text) then
      for Member in TAtlasWelcomeSaved.GroupProjects(AProject, Text) do
        if SameText(ExtractFileExt(Member), '.dproj') and FileExists(Member) then
          Result := Result + [Member];
    Exit;
  end;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Group := Modules.MainProjectGroup;
  if (Group = nil) or (Group.ProjectCount < 2) then
    Exit;
  Inside := False;
  for Index := 0 to Group.ProjectCount - 1 do
  begin
    FileName := Group.Projects[Index].FileName;
    // Nur gespeicherte .dproj (wie TAtlasIdeProjectContext.Read).
    if not SameText(ExtractFileExt(FileName), '.dproj') or not FileExists(FileName) then
      Continue;
    Result := Result + [FileName];
    if SameText(FileName, AProject) then
      Inside := True;
  end;
  if not Inside or (Length(Result) < 2) then
    Result := nil;
end;

function TAtlasIdeSetup.Card: TAtlasSetupCard;
var
  Open: Boolean;
  Summary, Other: TAtlasProjectSummary;
  Members: TArray<string>;
  Member: string;
  Item: TAtlasSetupMember;
  Combined: TArray<TAtlasSetupMember>;
begin
  Result := TAtlasSetupCard.Empty;
  if not FStarted or not Active then
    Exit;
  Result.ShowNew := TAtlasWelcomeSetup.ShowNew(True, TAtlasIdeSettings.Current.WelcomePageNewFromTemplate,
    GetActiveProject <> nil);
  Result.Project := Target(Open);
  if Result.Project = '' then
    Exit;
  Result.ProjectOpen := Open;
  Result.ProjectName := TAtlasWelcomeSetup.NameOf(Result.Project);
  Result.Facts := FactsOf(Result.Project, Summary);
  // Projektgruppe: Prüfung je Projekt, die Karte fasst sie zusammen.
  Members := GroupOf(Result.Project);
  if Length(Members) > 0 then
  begin
    Combined := nil;
    for Member in Members do
    begin
      Item.Project := Member;
      Item.Setup := TAtlasProjectSetup.Empty;
      if SameText(Member, Result.Project) then
        Item.Setup := Result.Facts.Setup
      else if TAtlasProjectSummaries.Load(TAtlasIdeProjects.Folder, Member, Other) then
        Item.Setup := Other.Setup;
      Combined := Combined + [Item];
    end;
    Result.GroupProjects := Length(Members);
    Result.Facts.Setup := TAtlasWelcomeSetup.Combined(Result.Project, Result.Facts.Setup, Combined,
      Result.GroupChecked);
  end;
  Result.ConfigName := ExtractFileName(TAtlasProjectSetups.ExistingConfig(Result.Project, FileThere));
  Result.ShowCard := TAtlasWelcomeSetup.ShowCard(True, Result.Facts);
  if Summary.Rules.Known then
    Result.BaselineNewHits := Summary.Rules.NewHits;
  // Läufe dieser Sitzung gelten nur für ihr Projekt.
  if SameText(FBaselineProject, Result.Project) then
  begin
    Result.Baseline := FBaseline;
    Result.BaselineStarted := FBaselineStarted;
    Result.BaselineTotal := FBaselineTotal;
    Result.BaselineFiles := FBaselineFiles;
    Result.BaselineError := FBaselineError;
  end;
  if SameText(FPathsProject, Result.Project) then
  begin
    Result.Paths := FPaths;
    Result.PathsStarted := FPathsStarted;
    Result.PathsError := FPathsError;
  end;
end;

procedure TAtlasIdeSetup.CreateConfig(ATemplate: TAtlasSetupTemplate);
var
  Template: TAtlasSetupTemplate;
begin
  Template := ATemplate;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Project, Existing, Folder, Text, ConfigFile: string;
      Issues: TArray<string>;
      Open: Boolean;
    begin
      if not Active then
        Exit;
      Project := Target(Open);
      if Project = '' then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.WelcomeSetupNoProject));
        Exit;
      end;
      Existing := TAtlasProjectSetups.ExistingConfig(Project, FileThere);
      if Existing <> '' then
      begin
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupConfigExists, [Existing]));
        Refresh;
        Exit;
      end;
      Folder := TAtlasProjectSetups.TemplateFolder(ExtractFilePath(GetModuleName(HInstance)), FileThere);
      Text := TAtlasProjectSetups.TemplateText(Template, Folder, ReadText);
      if not TAtlasProjectSetups.ValidTemplate(Text, AtlasSchemaJson, Issues) then
      begin
        // Beschädigte oder veraltete Datei der Installation: die eingebaute Fassung.
        TAtlasGuard.Log('Einrichtung: Vorlage ' + TAtlasProjectSetups.TemplateId(Template) +
          ' passt nicht zum Schema, eingebaute Fassung');
        Text := TAtlasProjectSetups.BuiltIn(Template);
        if not TAtlasProjectSetups.ValidTemplate(Text, AtlasSchemaJson, Issues) then
        begin
          Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupConfigInvalid,
            [TAtlasWelcomeSetupFrame.TemplateCaption(Template), string.Join('; ', Issues)]));
          Exit;
        end;
      end;
      // CRLF wie die übrigen Dateien eines Delphi-Projekts.
      Text := StringReplace(StringReplace(Text, #13#10, #10, [rfReplaceAll]), #10, #13#10, [rfReplaceAll]);
      ConfigFile := TAtlasProjectSetups.ConfigTarget(Project);
      if not TAtlasSetupPreviewDialog.Confirm(ExtractFileName(ConfigFile), ExtractFileName(Project),
        TAtlasWelcomeSetupFrame.TemplateCaption(Template), Text, nil) then
        Exit;
      // Während der Vorschau angelegt (etwa im Editor): nicht überschreiben.
      if TAtlasProjectSetups.ExistingConfig(Project, FileThere) <> '' then
      begin
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupConfigExists, [ConfigFile]));
        Refresh;
        Exit;
      end;
      try
        // UTF-8 ohne BOM, wie atlas.json im Repository.
        TFile.WriteAllBytes(ConfigFile, TEncoding.UTF8.GetBytes(Text));
      except
        on E: Exception do
        begin
          TAtlasGuard.Log('Einrichtung: atlas.json nicht geschrieben (' + E.ClassName + ')');
          Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupConfigFailed, [ConfigFile, E.Message]));
          Exit;
        end;
      end;
      TAtlasGuard.Log('Einrichtung: atlas.json angelegt (Vorlage ' + TAtlasProjectSetups.TemplateId(Template) + ')');
      Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupConfigWritten, [ConfigFile]));
      // Abnahme: Schritt 2 ist danach abgehakt.
      Refresh;
    end);
end;

procedure TAtlasIdeSetup.StartBaseline;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Project, Reason: string;
      Open: Boolean;
      Keep: IAtlasSetupSource;
    begin
      if not Active or not Assigned(FStartBaseline) then
        Exit;
      Project := Target(Open);
      if Project = '' then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.WelcomeSetupNoProject));
        Exit;
      end;
      if not Open then
      begin
        OpenProject;
        Exit;
      end;
      if (FBaseline = TAtlasSetupRun.Running) and SameText(FBaselineProject, Project) then
        Exit;
      FBaselineProject := Project;
      FBaselineTotal := 0;
      FBaselineFiles := 0;
      FBaselineError := '';
      // Keep hält die Quelle bis zur Antwort des Servers.
      Keep := Self;
      Reason := FStartBaseline(Project,
        procedure(ASucceeded: Boolean; ATotal, AFiles: Integer; const AError: string)
        begin
          if Keep <> nil then
            BaselineFinished(Project, ASucceeded, ATotal, AFiles, AError);
        end);
      if Reason <> '' then
      begin
        FBaseline := TAtlasSetupRun.Failed;
        FBaselineError := Reason;
      end
      else
      begin
        FBaseline := TAtlasSetupRun.Running;
        FBaselineStarted := TThread.GetTickCount64;
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
    Exit;
  if ASucceeded then
  begin
    Stamp := TAtlasIdeProjects.StampUtc;
    // Abnahme: Nach der Baseline sind die neuen Treffer 0 (alle stehen in der Baseline).
    TAtlasProjectSummaries.Update(TAtlasIdeProjects.Folder, AProject,
      procedure(var ASummary: TAtlasProjectSummary)
      begin
        TAtlasWelcomeSetup.BaselineWritten(ASummary.Rules, Stamp);
      end);
  end;
  if not SameText(FBaselineProject, AProject) then
    Exit;
  FBaselineTotal := ATotal;
  FBaselineFiles := AFiles;
  FBaselineError := AError;
  if ASucceeded then
    FBaseline := TAtlasSetupRun.Done
  else
    FBaseline := TAtlasSetupRun.Failed;
  Refresh;
end;

type
  /// <summary>Was die Prüfung eines Projekts im Hintergrund braucht; im Hauptthread gesammelt.</summary>
  TAtlasSetupPathJob = record
    Project: string;
    Input: TAtlasPathCheckInput;
    /// <summary>Such- und Bibliothekspfade wie in den Optionen, mit $(…).</summary>
    SearchPaths: TArray<string>;
    LibraryPaths: TArray<string>;
    Macros: TAtlasPathMacros;
  end;

/// <summary>Optionen, Dateien und Makros eines geöffneten Projekts (nur im Hauptthread).</summary>
function PathJobOf(const AIde: IOTAProject): TAtlasSetupPathJob;
var
  Context: TAtlasProjectContext;
  Index: Integer;
  Main, Name, GroupDir: string;
  Version: Double;
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
begin
  Result := Default(TAtlasSetupPathJob);
  Result.Project := TAtlasIdeProjects.ProjectFileOf(AIde.FileName);
  Context := TAtlasIdeProjectContext.Read(AIde);
  Result.Input.Project := Result.Project;
  // Hauptdatei: .dpr bei Programmen und Bibliotheken, .dpk bei Packages.
  Main := ChangeFileExt(Result.Project, '.dpr');
  if not FileExists(Main) then
    Main := ChangeFileExt(Result.Project, '.dpk');
  if not FileExists(Main) then
    Main := '';
  if Main <> '' then
    Result.Input.Sources := [Main];
  for Index := 0 to AIde.GetModuleCount - 1 do
  begin
    Name := AIde.GetModule(Index).FileName;
    if SameText(ExtractFileExt(Name), '.pas') then
      Result.Input.Sources := Result.Input.Sources + [Name];
  end;
  Result.Input.Namespaces := Context.Namespaces;
  // Projekte der Gruppe: ihre Packages erfüllen requires (#759).
  GroupDir := ExtractFileDir(Result.Project);
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
  begin
    Group := Modules.MainProjectGroup;
    if Group <> nil then
    begin
      if Group.FileName <> '' then
        GroupDir := ExtractFileDir(Group.FileName);
      for Index := 0 to Group.ProjectCount - 1 do
        if Group.Projects[Index] <> nil then
          Result.Input.GroupProjects := Result.Input.GroupProjects +
            [TAtlasIdeProjects.ProjectFileOf(Group.Projects[Index].FileName)];
    end;
  end;
  // Build-Skripte (-dX) neben dem Projekt, neben der Gruppe und in üblichen Unterordnern der Gruppe.
  Result.Input.ScriptFolders := [ExtractFileDir(Result.Project), GroupDir, TPath.Combine(GroupDir, 'tools'),
    TPath.Combine(GroupDir, 'scripts'), TPath.Combine(GroupDir, 'build')];
  Version := TTextDefines.CompilerVersionOfBds(StrToFloatDef(Context.BdsVersion, 0, TFormatSettings.Invariant));
  Result.Input.ActiveDefines := Context.Defines + TTextDefines.Predefined(Context.Platform, Version);
  Result.SearchPaths := Context.SearchPaths;
  Result.LibraryPaths := Context.LibraryPaths;
  // Makros der IDE (Umgebungsvariablen der Optionen, BDS-Ordner, Projekt), danach der Prozess.
  if Context.Project = '' then
    Context.Project := Result.Project;
  Result.Macros := TAtlasIdeProjectContext.Macros(Context);
end;

/// <summary>Prüft ein Projekt; im Hintergrundthread.</summary>
function RunPathJob(const AJob: TAtlasSetupPathJob): TAtlasSetupPathRun;
var
  Input: TAtlasPathCheckInput;
  Folder, Dproj, Member, Other, Output, Each: string;
  Match: TMatch;
  Variable: TAtlasPathVariable;
  Skipped: TArray<string>;
begin
  Result := Default(TAtlasSetupPathRun);
  Result.Project := AJob.Project;
  try
    Input := AJob.Input;
    Folder := ExtractFileDir(AJob.Project);
    // Mit (): Variable liefert eine Funktion; ohne Klammern wäre es die Methode selbst.
    Variable := AJob.Macros.Variable();
    // Pfade mit unbekanntem Makro fallen weg; ihre Makros machen die Funde unsicher.
    Skipped := nil;
    Input.SearchPaths := TAtlasPathCheck.ExpandPaths(AJob.SearchPaths, Folder, Variable, Skipped);
    Input.LibraryPaths := TAtlasPathCheck.ExpandPaths(AJob.LibraryPaths, Folder, Variable, Skipped);
    Input.SkippedMacros := Skipped;
    if TAtlasIdeSetup.ReadText(AJob.Project, Dproj) then
      Input.ProjectDefines := TAtlasPathCheck.DprojDefines(Dproj);
    // Projekte der Gruppe, die in einen Ordner des Suchpfads übersetzen (DCC_DcuOutput).
    for Member in Input.GroupProjects do
      if not SameText(Member, AJob.Project) and TAtlasIdeSetup.ReadText(Member, Other) then
      begin
        Match := TRegEx.Match(Other, '<DCC_DcuOutput>([^<]*)</DCC_DcuOutput>', [roIgnoreCase]);
        if Match.Success then
        begin
          Output := TAtlasPathCheck.ExpandPath(Match.Groups[1].Value, ExtractFileDir(Member), Variable);
          for Each in Input.SearchPaths do
            if (Output <> '') and SameText(ExcludeTrailingPathDelimiter(Each), ExcludeTrailingPathDelimiter(Output)) then
            begin
              Input.ProducedBy := Input.ProducedBy + [Member];
              Break;
            end;
        end;
      end;
    Result.Check := TAtlasPathCheck.Run(Input,
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := TAtlasIdeSetup.ReadText(AFileName, AText);
      end,
      function(const AFolder: string): TArray<string>
      var
        Item: string;
      begin
        Result := nil;
        if TAtlasShutdown.Signalled or not TDirectory.Exists(AFolder) then
          Exit;
        try
          for Item in TDirectory.GetFiles(AFolder) do
            Result := Result + [ExtractFileName(Item)];
        except
          on Exception do
            Result := nil;
        end;
      end);
  except
    on E: Exception do
    begin
      // Ins Protokoll nur die Klasse: Die Meldung kann Pfade enthalten.
      TAtlasGuard.Log('Einrichtung: Prüfung der Suchpfade abgebrochen (' + E.ClassName + ')');
      Result.Error := E.Message;
    end;
  end;
end;

procedure TAtlasIdeSetup.CheckPaths;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Project, Member: string;
      Open: Boolean;
      Ide: IOTAProject;
      Jobs: TArray<TAtlasSetupPathJob>;
      Keep: IAtlasSetupSource;
    begin
      if not Active then
        Exit;
      Project := Target(Open);
      if Project = '' then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.WelcomeSetupNoProject));
        Exit;
      end;
      Ide := OpenProjectOf(Project);
      if not Open or (Ide = nil) then
      begin
        OpenProject;
        Exit;
      end;
      if FThread <> nil then
      begin
        if not FThread.Finished then
          Exit;
        FreeAndNil(FThread);
      end;
      // Im Hauptthread: Optionen der aktiven Konfiguration, Dateien und Makros; bei einer Gruppe je Projekt.
      Jobs := nil;
      for Member in GroupOf(Project) do
        if OpenProjectOf(Member) <> nil then
          Jobs := Jobs + [PathJobOf(OpenProjectOf(Member))];
      if Length(Jobs) = 0 then
        Jobs := [PathJobOf(Ide)];
      FPathsProject := Project;
      FPaths := TAtlasSetupRun.Running;
      FPathsStarted := TThread.GetTickCount64;
      FPathsError := '';
      Refresh;
      // Keep hält die Quelle, bis das Ergebnis im Hauptthread angekommen ist.
      Keep := Self;
      // Im Hintergrund: Pfade auflösen, .dproj und alle Dateien lesen, ein Projekt nach dem anderen.
      FThread := TThread.CreateAnonymousThread(
        procedure
        var
          Runs: TArray<TAtlasSetupPathRun>;
          Job: TAtlasSetupPathJob;
        begin
          Runs := nil;
          for Job in Jobs do
          begin
            if TAtlasShutdown.Signalled then
              Exit;
            Runs := Runs + [RunPathJob(Job)];
          end;
          if TAtlasShutdown.Signalled then
            Exit;
          TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
            procedure
            begin
              if Keep <> nil then
                PathsFinished(Project, Runs);
            end);
        end);
      FThread.FreeOnTerminate := False;
      FThread.Start;
    end);
end;

procedure TAtlasIdeSetup.PathsFinished(const AProject: string; const ARuns: TArray<TAtlasSetupPathRun>);
var
  Run: TAtlasSetupPathRun;
  Check: TAtlasPathCheckResult;
  Stamp: TDateTime;
  Error, Member: string;
  Units, Defines, Uncertain, Files: Integer;
begin
  if not FStarted then
    Exit;
  Error := '';
  Units := 0;
  Defines := 0;
  Uncertain := 0;
  Files := 0;
  Stamp := TAtlasIdeProjects.StampUtc;
  for Run in ARuns do
  begin
    if Run.Error <> '' then
    begin
      if Error = '' then
        Error := Run.Error;
      Continue;
    end;
    // Kopien: Die Laufvariable darf nicht in die anonyme Methode.
    Check := Run.Check;
    Member := Run.Project;
    // Funde je Projekt in dessen Zusammenfassung; die Karte einer Gruppe fasst sie zusammen.
    TAtlasProjectSummaries.Update(TAtlasIdeProjects.Folder, Member,
      procedure(var ASummary: TAtlasProjectSummary)
      begin
        ASummary.Setup := TAtlasWelcomeSetup.Checked(ASummary.Setup, Member, Check, Stamp);
      end);
    Inc(Files, Check.Files);
    Inc(Units, Length(Check.MissingUnits));
    Inc(Defines, Length(Check.UndefinedDefines));
    Inc(Uncertain, TAtlasPathCheckResult.UncertainIn(Check.MissingUnits) +
      TAtlasPathCheckResult.UncertainIn(Check.UndefinedDefines));
  end;
  // Anonym: nur Zahlen, keine Pfade und keine Makronamen.
  TAtlasGuard.Log(Format('Einrichtung: %d Projekte, %d Dateien geprüft, %d Units fehlen, %d Defines ohne Quelle, ' +
    '%d davon unsicher', [Length(ARuns), Files, Units, Defines, Uncertain]));
  if SameText(FPathsProject, AProject) then
  begin
    if Error = '' then
      FPaths := TAtlasSetupRun.Done
    else
    begin
      FPaths := TAtlasSetupRun.Failed;
      FPathsError := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupPathsFailed, [Error]);
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
      Ide := OpenProjectOf(Project);
      if Ide = nil then
      begin
        OpenProject;
        Exit;
      end;
      // Dialog „Projektoptionen“ der IDE (Suchpfade unter Delphi-Compiler, Defines unter Bedingungen).
      if Ide.ProjectOptions <> nil then
        Ide.ProjectOptions.EditOptions;
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
      Project := Target(Open);
      if Project = '' then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.WelcomeSetupNoProject));
        Exit;
      end;
      if not Open and Supports(BorlandIDEServices, IOTAActionServices, Actions) then
        Actions.OpenProject(Project, True);
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
        Exit;
      Stamp := TAtlasIdeProjects.StampUtc;
      // Abnahme: „Nicht mehr fragen“ wirkt dauerhaft (Projekt-Zusammenfassung, nicht die Sitzung).
      TAtlasProjectSummaries.Update(TAtlasIdeProjects.Folder, Project,
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
      Project := Target(Open);
      if Project = '' then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.WelcomeSetupNoProject));
        Exit;
      end;
      TAtlasProjectSummaries.Update(TAtlasIdeProjects.Folder, Project,
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
      if not Active or not TAtlasIdeSettings.Current.WelcomePageNewFromTemplate or not Assigned(FNewFile) then
        Exit;
      FNewFile(Kind);
    end);
end;

end.
