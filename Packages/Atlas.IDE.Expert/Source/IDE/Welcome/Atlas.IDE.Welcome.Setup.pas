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
    procedure Report(const AText: string);
    procedure ProjectsChanged(const AId: string);
    procedure BaselineFinished(const AProject: string; ASucceeded: Boolean; ATotal, AFiles: Integer;
      const AError: string);
    procedure PathsFinished(const AProject: string; const AResult: TAtlasPathCheckResult; const AError: string);
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
  ToolsAPI,
  Atlas.Text.Defines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Projects.Baseline,
  Atlas.Core.Projects.Contract,
  Atlas.Core.Settings.SchemaData,
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
  Refresh;
end;

procedure TAtlasIdeSetup.Stop;
begin
  if not FStarted then
    Exit;
  FStarted := False;
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

function TAtlasIdeSetup.Card: TAtlasSetupCard;
var
  Open: Boolean;
  Summary: TAtlasProjectSummary;
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

procedure TAtlasIdeSetup.CheckPaths;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Project: string;
      Open: Boolean;
      Ide: IOTAProject;
      Context: TAtlasProjectContext;
      Input: TAtlasPathCheckInput;
      Index: Integer;
      Main, Name: string;
      Configuration, PlatformName: string;
      Version: Double;
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
      // Im Hauptthread: Optionen der aktiven Konfiguration und die Dateien des Projekts.
      Context := TAtlasIdeProjectContext.Read(Ide);
      Input := Default(TAtlasPathCheckInput);
      Input.Project := Project;
      // Hauptdatei: .dpr bei Programmen und Bibliotheken, .dpk bei Packages.
      Main := ChangeFileExt(Project, '.dpr');
      if not FileExists(Main) then
        Main := ChangeFileExt(Project, '.dpk');
      if not FileExists(Main) then
        Main := '';
      if Main <> '' then
        Input.Sources := [Main];
      for Index := 0 to Ide.GetModuleCount - 1 do
      begin
        Name := Ide.GetModule(Index).FileName;
        if SameText(ExtractFileExt(Name), '.pas') then
          Input.Sources := Input.Sources + [Name];
      end;
      Input.Namespaces := Context.Namespaces;
      Configuration := Context.Configuration;
      PlatformName := Context.Platform;
      Version := TTextDefines.CompilerVersionOfBds(StrToFloatDef(Context.BdsVersion, 0,
        TFormatSettings.Invariant));
      Input.ActiveDefines := Context.Defines + TTextDefines.Predefined(PlatformName, Version);
      FPathsProject := Project;
      FPaths := TAtlasSetupRun.Running;
      FPathsStarted := TThread.GetTickCount64;
      FPathsError := '';
      Refresh;
      // Keep hält die Quelle, bis das Ergebnis im Hauptthread angekommen ist.
      Keep := Self;
      // Im Hintergrund: Pfade auflösen, .dproj und alle Dateien lesen.
      FThread := TThread.CreateAnonymousThread(
        procedure
        var
          Check: TAtlasPathCheckResult;
          Error, Dproj, Folder, Raw, Path: string;
          Variable: TAtlasPathVariable;
        begin
          Check := Default(TAtlasPathCheckResult);
          Error := '';
          try
            Folder := ExtractFileDir(Project);
            Variable :=
              function(const AName: string): string
              begin
                if SameText(AName, 'Platform') then
                  Result := PlatformName
                else if SameText(AName, 'Config') then
                  Result := Configuration
                else
                  Result := GetEnvironmentVariable(AName);
              end;
            for Raw in Context.SearchPaths do
            begin
              // Unbekannte $(…) ergeben '': Der Pfad fällt weg.
              Path := TAtlasPathCheck.ExpandPath(Raw, Folder, Variable);
              if Path <> '' then
                Input.SearchPaths := Input.SearchPaths + [Path];
            end;
            for Raw in Context.LibraryPaths do
            begin
              Path := TAtlasPathCheck.ExpandPath(Raw, Folder, Variable);
              if Path <> '' then
                Input.LibraryPaths := Input.LibraryPaths + [Path];
            end;
            if ReadText(Project, Dproj) then
              Input.ProjectDefines := TAtlasPathCheck.DprojDefines(Dproj);
            Check := TAtlasPathCheck.Run(Input, ReadText,
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
              Error := E.Message;
            end;
          end;
          if TAtlasShutdown.Signalled then
            Exit;
          TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
            procedure
            begin
              if Keep <> nil then
                PathsFinished(Project, Check, Error);
            end);
        end);
      FThread.FreeOnTerminate := False;
      FThread.Start;
    end);
end;

procedure TAtlasIdeSetup.PathsFinished(const AProject: string; const AResult: TAtlasPathCheckResult;
  const AError: string);
var
  Check: TAtlasPathCheckResult;
  Stamp: TDateTime;
begin
  if not FStarted then
    Exit;
  if AError = '' then
  begin
    Check := AResult;
    Stamp := TAtlasIdeProjects.StampUtc;
    TAtlasProjectSummaries.Update(TAtlasIdeProjects.Folder, AProject,
      procedure(var ASummary: TAtlasProjectSummary)
      begin
        ASummary.Setup := TAtlasWelcomeSetup.Checked(ASummary.Setup, AProject, Check, Stamp);
      end);
    // Anonym: nur Zahlen.
    TAtlasGuard.Log(Format('Einrichtung: %d Dateien geprüft, %d Units fehlen, %d Defines ohne Quelle',
      [AResult.Files, Length(AResult.MissingUnits), Length(AResult.UndefinedDefines)]));
  end;
  if SameText(FPathsProject, AProject) then
  begin
    if AError = '' then
      FPaths := TAtlasSetupRun.Done
    else
    begin
      FPaths := TAtlasSetupRun.Failed;
      FPathsError := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupPathsFailed, [AError]);
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
