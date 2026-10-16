unit Atlas.IDE.Welcome.Continue;

// Bereich „Weiterarbeiten“ in der IDE (#755): Quelle des Bereichs
// (IAtlasContinueSource), Anmeldung als Bereich atlas.continue der
// Willkommensseite (bzw. des Fensters „Atlas-Start“), Mitschreiben des
// Arbeitsstands und die Aktionen.
// - Mitschreiben (nur mit welcomePage.continue): EditorViewModified merkt je
//   Datei die letzte Änderungsstelle. Beim Schließen eines Projekts bzw. einer
//   Projektgruppe und beim Beenden der IDE gehen die offenen Reiter (Reihenfolge
//   aus den Beschriftungen des Editorfensters, sonst die der Puffer), der aktive
//   Reiter, die Änderungsstellen samt Methode (Gliederung), Zeitpunkt und der
//   zuletzt bekannte HEAD in den Abschnitt "continue" der
//   Projekt-Zusammenfassung (#592); Ziel ist die gespeicherte Projektgruppe,
//   sonst das Projekt. Die IDE schließt beim Schließen eines Projekts erst die
//   Dateien: Die Reiter werden deshalb beim ersten Schließen einer Datei
//   festgehalten und gelten für ein Projekt, das binnen BatchMs folgt. Ohne
//   offene Reiter bleibt der vorige Stand.
// - HEAD und verfolgter Branch (#571) kommen aus einer Abfrage im
//   Hintergrund beim Öffnen und höchstens einmal je Minute beim Arbeiten;
//   nach dem Schließen wird frisch abgefragt und nachgetragen.
// - Eingehende Commits (welcomePage.continue.incoming) für den obersten
//   Eintrag im Hintergrund beim Anzeigen, höchstens einmal je Minute; fetch nur
//   mit welcomePage.continue.fetch (5 s, ohne Rückfrage nach Zugangsdaten).
//   Klick auf einen Commit listet seine Dateien im Fenster „Atlas-Ergebnisse“
//   (#400); eine eigene Commit-Ansicht hat #571 nicht.
// - „Fortsetzen“ öffnet das Projekt, dann die Reiter in ihrer Reihenfolge mit
//   dem Cursor an der letzten Änderung und aktiviert zuletzt den zuvor aktiven
//   Reiter. Fehlende Dateien werden übersprungen und als Hinweis im Bereich und
//   in der Meldungsansicht genannt. Palettenbefehl Atlas.Continue setzt den
//   obersten Eintrag fort.
// - „Gemerkt“ (welcomePage.saved) liest nur Dateien: Notizen (#545),
//   Lesezeichen (#622) der zuletzt geöffneten Projekte (bei Projektgruppen
//   auch ihrer Projekte) und Favoriten (#458). Doppelklick öffnet das Projekt
//   und springt hin; ein Favorit springt zur Deklaration in der Unit, deren
//   Datei aus den Index-Caches auf der Platte kommt.
// - welcomePage.continue aus: kein Bereich, kein Mitschreiben, keine Abfrage.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  ToolsAPI,
  DockForm,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Results.Model,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.Saved,
  Atlas.UI.Welcome.Continue;

type
  TAtlasIdeContinue = class(TInterfacedObject, IAtlasContinueSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts.</summary>
    Order = 15;
    /// <summary>So lange nach dem ersten Schließen einer Datei gelten die festgehaltenen Reiter.</summary>
    BatchMs = 5000;
  private type
    TIdeNotifier = class(TNotifierObject, IOTAIDENotifier)
    private
      FOwner: TAtlasIdeContinue;
    public
      procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
      procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
      procedure AfterCompile(Succeeded: Boolean); overload;
    end;

    TEditNotifier = class(TNotifierObject, INTAEditServicesNotifier)
    private
      FOwner: TAtlasIdeContinue;
    public
      procedure WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
      procedure WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
      procedure WindowActivated(const EditWindow: INTAEditWindow);
      procedure WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer; var Handled: Boolean);
      procedure EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
      procedure EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
      procedure DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
      procedure DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
      procedure DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    end;

    /// <summary>Offene Reiter in ihrer Reihenfolge mit der Cursorstelle und aktive Datei.</summary>
    TSnapshot = record
      Tabs: TArray<TAtlasWorkTab>;
      Active: string;
    end;
  private
    FMessage: TProc<string>;
    FNotifier: TIdeNotifier;
    FNotifierIndex: Integer;
    FEditNotifier: TEditNotifier;
    FEditNotifierIndex: Integer;
    FStopped: Boolean;
    // Großgeschriebener Pfad → letzte Änderungsstelle dieser Sitzung.
    FChanges: TDictionary<string, TAtlasWorkTab>;
    // Festgehaltene Reiter beim ersten Schließen einer Datei (GetTickCount64 des letzten Schließens).
    FBatch: TSnapshot;
    FBatchAt: UInt64;
    FLastWrite: UInt64;
    // Normiertes Ziel → HEAD-Stand (VcsKind, Head, Upstream, UpstreamRevision) bzw. Zeitpunkt der Abfrage.
    FHeads: TDictionary<string, TAtlasWorkState>;
    FHeadFresh: TDictionary<string, UInt64>;
    FHeadQuerying: TDictionary<string, UInt64>;
    // Eingehende Commits zum obersten Eintrag.
    FIncoming: TAtlasContinueIncoming;
    FIncomingKey: string;
    FIncomingFresh: UInt64;
    FIncomingStarted: UInt64;
    FNotice: string;
    procedure Changed;
    procedure Report(const AText: string);
    function Enabled: Boolean;
    function Recording: Boolean;
    procedure Modified(const AView: IOTAEditView);
    procedure Activated;
    procedure SourceClosing;
    procedure ProjectOpened(const AFileName: string);
    procedure ProjectClosing(const AFileName: string);
    function TakeSnapshot: TSnapshot;
    procedure WriteState(const ATarget: string; const ASnapshot: TSnapshot; AProbe: Boolean);
    procedure QueryHead(const ATarget: string; AStamp: TDateTime);
    procedure RefreshIncoming(AForce: Boolean);
    function IncomingRunning: Boolean;
    procedure EnsureProject(const AProject: string);
    procedure OpenFavorite(const AItem: TAtlasSavedItem);
    function Top: TAtlasContinueEntry;
    class function NowUtc: TDateTime; static;
    class function Key(const APath: string): string; static;
    class function ProjectOpen(const AFileName: string): Boolean; static;
    class function TargetOf(const AFileName: string): string; static;
    class function CurrentTarget: string; static;
    class function TabCaptions: TArray<string>; static;
    class function IsPascal(const AFileName: string): Boolean; static;
    class function FileText(const AFileName: string): string; static;
    /// <summary>Datei öffnen, Cursor an Zeile und Spalte des Reiters (ab 1).</summary>
    class procedure OpenTab(const ATab: TAtlasWorkTab); static;
    /// <summary>Einträge für „Atlas-Ergebnisse“: die Dateien des Commits, die eigenen zuerst.</summary>
    class function CommitEntries(const ACommit: TAtlasContinueCommit;
      const AFiles: TArray<string>): TArray<TAtlasResultEntry>; static;
    class procedure ShowCommitEntries(const ACommit: TAtlasContinueCommit;
      const AEntries: TArray<TAtlasResultEntry>); static;
  public
    /// <summary>AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Bereich, Fabrik und Beobachter der IDE anmelden.</summary>
    procedure Start;
    /// <summary>Stand des offenen Projekts schreiben (Beenden der IDE), alles abmelden; danach wirkungslos.</summary>
    procedure Stop;
    function Section: TAtlasWelcomeSection;
    /// <summary>Palettenbefehl Atlas.Continue: obersten Arbeitsstand fortsetzen.</summary>
    procedure ResumeLatest;
    { IAtlasContinueSource }
    function Entries: TAtlasContinueEntries;
    function Incoming: TAtlasContinueIncoming;
    function IncomingQuerying: Boolean;
    function SavedEnabled: Boolean;
    function Saved: TAtlasSavedItems;
    function Notice: string;
    procedure Resume(const AProject: string);
    procedure ShowCommit(const AProject: string; const ACommit: TAtlasContinueCommit);
    procedure OpenSaved(const AItem: TAtlasSavedItem);
    procedure Shown;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.DateUtils,
  System.TypInfo,
  Vcl.Forms,
  Vcl.Controls,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Notes.Store,
  Atlas.Core.Bookmarks.Store,
  Atlas.Core.Completion.Favorites,
  Atlas.Core.Welcome.Search,
  Atlas.Core.Welcome.IndexFiles,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Vcs.Service,
  Atlas.IDE.Bookmarks.Service,
  Atlas.IDE.Completion.Favorites,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.Projects;

{ TAtlasIdeContinue.TIdeNotifier }

procedure TAtlasIdeContinue.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
var
  Owner: TAtlasIdeContinue;
  Name: string;
  Code: TOTAFileNotification;
begin
  Owner := FOwner;
  if (Owner = nil) or not ((NotifyCode = ofnFileOpened) or (NotifyCode = ofnFileClosing)) then
    Exit;
  Name := FileName;
  Code := NotifyCode;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if not TAtlasWelcomeSearch.IsProjectFile(Name) then
      begin
        if Code = ofnFileClosing then
          Owner.SourceClosing;
      end
      else if Code = ofnFileOpened then
        Owner.ProjectOpened(Name)
      else
        Owner.ProjectClosing(Name);
    end);
end;

procedure TAtlasIdeContinue.TIdeNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TAtlasIdeContinue.TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ TAtlasIdeContinue.TEditNotifier }

procedure TAtlasIdeContinue.TEditNotifier.WindowShow(const EditWindow: INTAEditWindow; Show,
  LoadedFromDesktop: Boolean);
begin
end;

procedure TAtlasIdeContinue.TEditNotifier.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
end;

procedure TAtlasIdeContinue.TEditNotifier.WindowActivated(const EditWindow: INTAEditWindow);
begin
end;

procedure TAtlasIdeContinue.TEditNotifier.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);
begin
end;

procedure TAtlasIdeContinue.TEditNotifier.EditorViewActivated(const EditWindow: INTAEditWindow;
  const EditView: IOTAEditView);
var
  Owner: TAtlasIdeContinue;
begin
  Owner := FOwner;
  if Owner = nil then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      Owner.Activated;
    end);
end;

procedure TAtlasIdeContinue.TEditNotifier.EditorViewModified(const EditWindow: INTAEditWindow;
  const EditView: IOTAEditView);
var
  Owner: TAtlasIdeContinue;
  View: IOTAEditView;
begin
  Owner := FOwner;
  if (Owner = nil) or (EditView = nil) then
    Exit;
  View := EditView;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      Owner.Modified(View);
    end);
end;

procedure TAtlasIdeContinue.TEditNotifier.DockFormVisibleChanged(const EditWindow: INTAEditWindow;
  DockForm: TDockableForm);
begin
end;

procedure TAtlasIdeContinue.TEditNotifier.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TAtlasIdeContinue.TEditNotifier.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

{ TAtlasIdeContinue }

constructor TAtlasIdeContinue.Create(const AMessage: TProc<string>);
begin
  inherited Create;
  FMessage := AMessage;
  FNotifierIndex := -1;
  FEditNotifierIndex := -1;
  FChanges := TDictionary<string, TAtlasWorkTab>.Create;
  FHeads := TDictionary<string, TAtlasWorkState>.Create;
  FHeadFresh := TDictionary<string, UInt64>.Create;
  FHeadQuerying := TDictionary<string, UInt64>.Create;
end;

destructor TAtlasIdeContinue.Destroy;
begin
  Stop;
  FHeadQuerying.Free;
  FHeadFresh.Free;
  FHeads.Free;
  FChanges.Free;
  inherited;
end;

class function TAtlasIdeContinue.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasIdeContinue.Key(const APath: string): string;
begin
  Result := TAtlasProjectSummaries.NormalizedPath(APath);
end;

procedure TAtlasIdeContinue.Start;
var
  Services: IOTAServices;
  Editors: IOTAEditorServices;
  Keep: IAtlasContinueSource;
begin
  FStopped := False;
  Keep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.Continue,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeContinueFrame;
    begin
      Frame := TAtlasWelcomeContinueFrame.Create(AOwner);
      Frame.Source := Keep;
      Result := Frame;
    end);
  TAtlasWelcomeSections.Default.Add(Section);
  if (FNotifier = nil) and Supports(BorlandIDEServices, IOTAServices, Services) then
  begin
    FNotifier := TIdeNotifier.Create;
    FNotifier.FOwner := Self;
    FNotifierIndex := Services.AddNotifier(FNotifier);
  end;
  if (FEditNotifier = nil) and Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
  begin
    FEditNotifier := TEditNotifier.Create;
    FEditNotifier.FOwner := Self;
    FEditNotifierIndex := Editors.AddNotifier(FEditNotifier);
  end;
  // Plugin nach dem Öffnen eines Projekts geladen: HEAD trotzdem kennen.
  if Recording then
    QueryHead(CurrentTarget, 0);
end;

procedure TAtlasIdeContinue.Stop;
var
  Services: IOTAServices;
  Editors: IOTAEditorServices;
  Target: string;
begin
  if FStopped then
    Exit;
  // Beenden der IDE: Ist das Projekt noch offen (kein Schließen gemeldet), jetzt schreiben, ohne Abfrage.
  try
    if Recording and (GetTickCount64 - FLastWrite >= BatchMs) then
    begin
      Target := CurrentTarget;
      if Target <> '' then
        WriteState(Target, TakeSnapshot, False);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  FStopped := True;
  if FNotifier <> nil then
  begin
    FNotifier.FOwner := nil;
    // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter (#493).
    if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, Services) then
      Services.RemoveNotifier(FNotifierIndex);
    FNotifier := nil;
    FNotifierIndex := -1;
  end;
  if FEditNotifier <> nil then
  begin
    FEditNotifier.FOwner := nil;
    if (FEditNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
      Editors.RemoveNotifier(FEditNotifierIndex);
    FEditNotifier := nil;
    FEditNotifierIndex := -1;
  end;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.Continue);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.Continue);
end;

function TAtlasIdeContinue.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.Continue,
    TAtlasStrings.Text(TAtlasTextId.WelcomeContinueTitle), Order, TAtlasWelcomeColumn.Left,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.WelcomePageContinue;
    end);
end;

function TAtlasIdeContinue.Enabled: Boolean;
begin
  Result := not FStopped and TAtlasIdeSettings.Current.WelcomePageContinue;
end;

function TAtlasIdeContinue.Recording: Boolean;
begin
  // Ohne Willkommensseite gibt es den Bereich nicht: dann auch nichts mitschreiben.
  Result := Enabled and TAtlasIdeSettings.Current.WelcomePage;
end;

procedure TAtlasIdeContinue.Changed;
begin
  if not FStopped then
    TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Continue);
end;

procedure TAtlasIdeContinue.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

class function TAtlasIdeContinue.ProjectOpen(const AFileName: string): Boolean;
var
  Modules: IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, Modules) and (Modules.FindModule(AFileName) <> nil);
end;

class function TAtlasIdeContinue.TargetOf(const AFileName: string): string;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Project: string;
  Index: Integer;
begin
  Result := '';
  // Projektgruppe: nur eine gespeicherte (die Vorgabegruppe eines einzelnen Projekts liegt nicht auf der Platte).
  if SameText(ExtractFileExt(AFileName), '.groupproj') then
  begin
    if FileExists(AFileName) then
      Result := AFileName;
    Exit;
  end;
  Project := TAtlasIdeProjects.ProjectFileOf(AFileName);
  Result := Project;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Group := Modules.MainProjectGroup;
  if (Group = nil) or (Group.FileName = '') or not FileExists(Group.FileName) then
    Exit;
  for Index := 0 to Group.ProjectCount - 1 do
    if (Group.Projects[Index] <> nil) and
      SameText(TAtlasIdeProjects.ProjectFileOf(Group.Projects[Index].FileName), Project) then
      Exit(Group.FileName);
end;

class function TAtlasIdeContinue.CurrentTarget: string;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Project: IOTAProject;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Group := Modules.MainProjectGroup;
  if (Group <> nil) and (Group.FileName <> '') and FileExists(Group.FileName) then
    Exit(Group.FileName);
  Project := Modules.GetActiveProject;
  if (Project <> nil) and (Project.FileName <> '') then
    Result := TAtlasIdeProjects.ProjectFileOf(Project.FileName);
end;

class function TAtlasIdeContinue.IsPascal(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.pas') or (Extension = '.dpr') or (Extension = '.dpk') or (Extension = '.inc');
end;

/// <summary>Beschriftungen eines Reiter-Steuerelements (veröffentlichte Eigenschaft „Tabs“ als TStrings).</summary>
function TabsOf(AComponent: TComponent): TArray<string>;
var
  Value: TObject;
begin
  Result := nil;
  if (AComponent = nil) or not IsPublishedProp(AComponent, 'Tabs') or
    (PropType(AComponent, 'Tabs') <> tkClass) then
    Exit;
  Value := GetObjectProp(AComponent, 'Tabs');
  if Value is TStrings then
    Result := TStrings(Value).ToStringArray;
end;

class function TAtlasIdeContinue.TabCaptions: TArray<string>;
var
  Services: INTAEditorServices;
  Window: INTAEditWindow;
  Form: TCustomForm;
  Index: Integer;
begin
  // Das Editorfenster der IDE führt seine Reiter in einem Steuerelement „TabControl“ (TTabSet-Abkömmling); ohne
  // es gilt die Reihenfolge der Puffer.
  Result := nil;
  if not Supports(BorlandIDEServices, INTAEditorServices, Services) then
    Exit;
  Window := Services.TopEditWindow;
  if Window = nil then
    Exit;
  Form := Window.Form;
  if Form = nil then
    Exit;
  Result := TabsOf(Form.FindComponent('TabControl'));
  if Length(Result) > 0 then
    Exit;
  for Index := 0 to Form.ComponentCount - 1 do
  begin
    Result := TabsOf(Form.Components[Index]);
    if Length(Result) > 0 then
      Exit;
  end;
end;

function TAtlasIdeContinue.TakeSnapshot: TSnapshot;
var
  Modules: IOTAModuleServices;
  Editors: IOTAEditorServices;
  Module: IOTAModule;
  Editor: IOTAEditor;
  Source: IOTASourceEditor;
  Buffer: IOTAEditBuffer;
  View: IOTAEditView;
  Buffers: TDictionary<string, IOTAEditBuffer>;
  Files, Ordered: TArray<string>;
  Tabs: TArray<TAtlasWorkTab>;
  Tab, Change: TAtlasWorkTab;
  Index, FileIndex, Position: Integer;
  Name, Text: string;
begin
  Result := Default(TSnapshot);
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Buffers := TDictionary<string, IOTAEditBuffer>.Create;
  try
    Files := nil;
    Tabs := nil;
    // Offene Reiter: Quelltext-Editoren mit Ansicht.
    for Index := 0 to Modules.ModuleCount - 1 do
    begin
      Module := Modules.Modules[Index];
      if Module = nil then
        Continue;
      for FileIndex := 0 to Module.ModuleFileCount - 1 do
      begin
        Editor := Module.ModuleFileEditors[FileIndex];
        if (Editor = nil) or (Editor.FileName = '') or not Supports(Editor, IOTASourceEditor, Source) or
          (Source.EditViewCount = 0) or not Supports(Editor, IOTAEditBuffer, Buffer) then
          Continue;
        Name := Editor.FileName;
        if Buffers.ContainsKey(AnsiUpperCase(Name)) then
          Continue;
        Buffers.Add(AnsiUpperCase(Name), Buffer);
        View := Buffer.TopView;
        if View = nil then
          View := Source.EditViews[0];
        Tab := TAtlasWorkTab.Create(Name, 0, 0);
        if View <> nil then
          Tab := TAtlasWorkTab.Create(Name, View.CursorPos.Line, View.CursorPos.Col);
        Files := Files + [Name];
        Tabs := Tabs + [Tab];
      end;
    end;
    // Reihenfolge der Reiter im Editorfenster.
    Ordered := TAtlasWelcomeContinue.OrderByTabs(Files, TabCaptions);
    for Name in Ordered do
      for Tab in Tabs do
        if SameText(Tab.FileName, Name) then
        begin
          Result.Tabs := Result.Tabs + [Tab];
          Break;
        end;
    if Supports(BorlandIDEServices, IOTAEditorServices, Editors) and (Editors.TopBuffer <> nil) then
      Result.Active := Editors.TopBuffer.FileName;
    // Methode an der letzten Änderung bzw. (aktiver Reiter) am Cursor, aus dem Text des Puffers.
    for Position := 0 to High(Result.Tabs) do
    begin
      Tab := Result.Tabs[Position];
      if not IsPascal(Tab.FileName) or not Buffers.TryGetValue(AnsiUpperCase(Tab.FileName), Buffer) then
        Continue;
      Text := '';
      if FChanges.TryGetValue(AnsiUpperCase(Tab.FileName), Change) then
      begin
        Text := TAtlasEditorBuffer.Text(Buffer);
        Change.Method := TAtlasWelcomeContinue.MethodAt(Text, Change.Line);
        FChanges.AddOrSetValue(AnsiUpperCase(Tab.FileName), Change);
      end;
      if SameText(Tab.FileName, Result.Active) then
      begin
        if Text = '' then
          Text := TAtlasEditorBuffer.Text(Buffer);
        Result.Tabs[Position].Method := TAtlasWelcomeContinue.MethodAt(Text, Tab.Line);
      end;
    end;
  finally
    Buffers.Free;
  end;
end;

procedure TAtlasIdeContinue.Modified(const AView: IOTAEditView);
var
  Tab: TAtlasWorkTab;
begin
  if not Recording or (AView.Buffer = nil) or (AView.Buffer.FileName = '') then
    Exit;
  // Nur die Stelle merken (bei jedem Tastendruck): Methode erst beim Festhalten der Reiter.
  Tab := TAtlasWorkTab.Create(AView.Buffer.FileName, AView.CursorPos.Line, AView.CursorPos.Col);
  Tab.Changed := True;
  Tab.ChangedAt := NowUtc;
  FChanges.AddOrSetValue(AnsiUpperCase(Tab.FileName), Tab);
end;

procedure TAtlasIdeContinue.Activated;
var
  Target: string;
  Last: UInt64;
begin
  // HEAD beim Arbeiten aktuell halten (höchstens einmal je Minute), damit er beim Beenden bekannt ist.
  if not Recording or not TAtlasIdeSettings.Current.WelcomePageContinueIncoming then
    Exit;
  Target := CurrentTarget;
  if (Target = '') or (FHeadFresh.TryGetValue(Key(Target), Last) and
    (GetTickCount64 - Last < TAtlasWelcomeContinue.RefreshMs)) then
    Exit;
  QueryHead(Target, 0);
end;

procedure TAtlasIdeContinue.SourceClosing;
begin
  if not Recording then
    Exit;
  // Erste Datei einer Folge: Reiter festhalten, solange sie noch alle offen sind.
  if (FBatchAt = 0) or (GetTickCount64 - FBatchAt >= BatchMs) then
    FBatch := TakeSnapshot;
  FBatchAt := GetTickCount64;
end;

procedure TAtlasIdeContinue.ProjectOpened(const AFileName: string);
var
  Target: string;
begin
  if not Recording then
    Exit;
  Target := TargetOf(AFileName);
  if Target <> '' then
    QueryHead(Target, 0);
end;

procedure TAtlasIdeContinue.ProjectClosing(const AFileName: string);
var
  Target: string;
  Snapshot: TSnapshot;
begin
  if not Recording then
    Exit;
  // Gruppe und ihre Projekte melden sich einzeln: einmal je Schließen schreiben.
  if (FLastWrite > 0) and (GetTickCount64 - FLastWrite < BatchMs) then
    Exit;
  Target := TargetOf(AFileName);
  if Target = '' then
    Exit;
  if (FBatchAt > 0) and (GetTickCount64 - FBatchAt < BatchMs) then
    Snapshot := FBatch
  else
    Snapshot := TakeSnapshot;
  WriteState(Target, Snapshot, True);
end;

procedure TAtlasIdeContinue.WriteState(const ATarget: string; const ASnapshot: TSnapshot; AProbe: Boolean);
var
  Old, State, Head: TAtlasWorkState;
  Summary: TAtlasProjectSummary;
  Stamp: TDateTime;
  Root, TargetKey: string;
begin
  // Ohne offene Reiter bleibt der vorige Stand (z. B. alles schon geschlossen).
  if Length(ASnapshot.Tabs) = 0 then
    Exit;
  Root := TAtlasIdeProjects.Folder;
  TargetKey := Key(ATarget);
  Stamp := NowUtc;
  Old := TAtlasWorkState.Empty;
  if TAtlasProjectSummaries.Load(Root, ATarget, Summary) then
    TAtlasWelcomeContinue.Read(Summary, Old);
  State := TAtlasWelcomeContinue.Build(ASnapshot.Tabs, ASnapshot.Active, FChanges.Values.ToArray, Old, Stamp);
  if FHeads.TryGetValue(TargetKey, Head) then
  begin
    State.VcsKind := Head.VcsKind;
    State.Head := Head.Head;
    State.Upstream := Head.Upstream;
    State.UpstreamRevision := Head.UpstreamRevision;
  end;
  TAtlasProjectSummaries.Update(Root, ATarget,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      TAtlasWelcomeContinue.Write(ASummary, State);
    end);
  FLastWrite := GetTickCount64;
  FBatchAt := 0;
  FBatch := Default(TSnapshot);
  // Neue Sitzung: Änderungen gehören zum geschriebenen Stand.
  FChanges.Clear;
  if FIncomingKey = TargetKey then
    FIncomingFresh := 0;
  // HEAD frisch abfragen und nachtragen; beim Beenden der IDE weder Abfrage noch neues Zeichnen.
  if not AProbe then
    Exit;
  QueryHead(ATarget, Stamp);
  Changed;
end;

procedure TAtlasIdeContinue.QueryHead(const ATarget: string; AStamp: TDateTime);
var
  Keep: IAtlasContinueSource;
  TargetKey, Dir, Root, Target: string;
  Started, Current: UInt64;
  Ok: Boolean;
  Head: TAtlasWorkState;
begin
  if FStopped or (ATarget = '') then
    Exit;
  TargetKey := Key(ATarget);
  if FHeadQuerying.TryGetValue(TargetKey, Started) and
    (GetTickCount64 - Started < TAtlasWelcomeContinue.QueryLimitMs) then
    Exit;
  Started := GetTickCount64;
  FHeadQuerying.AddOrSetValue(TargetKey, Started);
  Keep := Self;
  Target := ATarget;
  Dir := ExtractFileDir(ATarget);
  Root := TAtlasIdeProjects.Folder;
  Ok := False;
  Head := TAtlasWorkState.Empty;
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      Ok := TAtlasWelcomeContinue.ProbeHead(TAtlasIdeVcs.ForFolder(Dir, TAtlasWelcomeContinue.CallTimeoutMs), Head);
    end,
    procedure
    begin
      if (Keep = nil) or FStopped then
        Exit;
      if FHeadQuerying.TryGetValue(TargetKey, Current) and (Current = Started) then
        FHeadQuerying.Remove(TargetKey);
      FHeadFresh.AddOrSetValue(TargetKey, GetTickCount64);
      if not Ok then
        Exit;
      FHeads.AddOrSetValue(TargetKey, Head);
      // Nach dem Schließen: in den eben geschriebenen Stand nachtragen (nur, wenn es noch derselbe ist).
      if AStamp <= 0 then
        Exit;
      TAtlasProjectSummaries.Update(Root, Target,
        procedure(var ASummary: TAtlasProjectSummary)
        var
          Stored: TAtlasWorkState;
        begin
          if not TAtlasWelcomeContinue.Read(ASummary, Stored) or (Abs(Stored.At - AStamp) > OneSecond) then
            Exit;
          Stored.VcsKind := Head.VcsKind;
          Stored.Head := Head.Head;
          Stored.Upstream := Head.Upstream;
          Stored.UpstreamRevision := Head.UpstreamRevision;
          TAtlasWelcomeContinue.Write(ASummary, Stored);
        end);
      Changed;
    end) then
  begin
    FHeadQuerying.Remove(TargetKey);
    FHeadFresh.AddOrSetValue(TargetKey, GetTickCount64);
  end;
end;

function TAtlasIdeContinue.Entries: TAtlasContinueEntries;
var
  Recent: TArray<string>;
  Root: string;
begin
  Result := nil;
  if not Enabled then
    Exit;
  Recent := nil;
  try
    Recent := TAtlasIdeWelcomeSearch.ClosedProjects;
  except
    // Registry nicht lesbar: leere Liste statt eines Fehlers in der Willkommensseite.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  Root := TAtlasIdeProjects.Folder;
  Result := TAtlasWelcomeContinue.Entries(Recent,
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    begin
      Result := TAtlasProjectSummaries.Load(Root, AProject, ASummary);
    end,
    TAtlasIdeSettings.Current.WelcomePageContinueCount);
end;

function TAtlasIdeContinue.Top: TAtlasContinueEntry;
var
  List: TAtlasContinueEntries;
begin
  Result := Default(TAtlasContinueEntry);
  List := Entries;
  if Length(List) > 0 then
    Result := List[0];
end;

function TAtlasIdeContinue.Incoming: TAtlasContinueIncoming;
var
  Entry: TAtlasContinueEntry;
begin
  Result := Default(TAtlasContinueIncoming);
  if not Enabled or not TAtlasIdeSettings.Current.WelcomePageContinueIncoming then
    Exit;
  Entry := Top;
  if (Entry.Project <> '') and (Key(Entry.Project) = FIncomingKey) and (Key(FIncoming.Project) = FIncomingKey) then
    Result := FIncoming;
end;

function TAtlasIdeContinue.IncomingRunning: Boolean;
begin
  Result := (FIncomingStarted > 0) and (GetTickCount64 - FIncomingStarted < TAtlasWelcomeContinue.QueryLimitMs);
  if not Result then
    FIncomingStarted := 0;
end;

function TAtlasIdeContinue.IncomingQuerying: Boolean;
var
  Entry: TAtlasContinueEntry;
begin
  Result := False;
  if not Enabled or not TAtlasIdeSettings.Current.WelcomePageContinueIncoming or not IncomingRunning then
    Exit;
  Entry := Top;
  Result := (Entry.Project <> '') and (Key(Entry.Project) = FIncomingKey);
end;

procedure TAtlasIdeContinue.Shown;
begin
  RefreshIncoming(False);
end;

procedure TAtlasIdeContinue.RefreshIncoming(AForce: Boolean);
var
  Keep: IAtlasContinueSource;
  Entry: TAtlasContinueEntry;
  EntryKey, Dir, Project: string;
  State: TAtlasWorkState;
  Fetch, Ok: Boolean;
  Stamp: TDateTime;
  Started: UInt64;
  Found: TAtlasContinueIncoming;
begin
  if not Enabled or not TAtlasIdeSettings.Current.WelcomePageContinueIncoming or IncomingRunning then
    Exit;
  Entry := Top;
  if Entry.Project = '' then
    Exit;
  EntryKey := Key(Entry.Project);
  if not AForce and (EntryKey = FIncomingKey) and (FIncomingFresh > 0) and
    (GetTickCount64 - FIncomingFresh < TAtlasWelcomeContinue.RefreshMs) then
    Exit;
  Keep := Self;
  Project := Entry.Project;
  State := Entry.State;
  Dir := ExtractFileDir(Entry.Project);
  Fetch := TAtlasIdeSettings.Current.WelcomePageContinueFetch;
  Stamp := NowUtc;
  Ok := False;
  Found := Default(TAtlasContinueIncoming);
  Started := GetTickCount64;
  FIncomingStarted := Started;
  // Ein anderer oberster Eintrag: alte Commits nicht mehr zeigen.
  if EntryKey <> FIncomingKey then
    FIncoming := Default(TAtlasContinueIncoming);
  FIncomingKey := EntryKey;
  if not TAtlasIdeVcs.Run(
    procedure
    var
      FetchVcs: IAtlasVersionControl;
    begin
      FetchVcs := nil;
      // fetch mit eigenem Zeitlimit; Zugangsdaten fragt der Anbieter nie ab.
      if Fetch then
        FetchVcs := TAtlasIdeVcs.ForFolder(Dir, TAtlasWelcomeContinue.FetchTimeoutMs);
      Ok := TAtlasWelcomeContinue.ProbeIncoming(TAtlasIdeVcs.ForFolder(Dir, TAtlasWelcomeContinue.CallTimeoutMs),
        FetchVcs, Project, State, Stamp, Found);
    end,
    procedure
    begin
      if (Keep = nil) or FStopped then
        Exit;
      if FIncomingStarted = Started then
        FIncomingStarted := 0;
      if FIncomingKey <> EntryKey then
        Exit;
      FIncomingFresh := GetTickCount64;
      if Ok then
        FIncoming := Found
      else
      begin
        // Fehler oder Zeitüberschreitung: kein Abschnitt.
        FIncoming := Default(TAtlasContinueIncoming);
        FIncoming.Project := Project;
      end;
      Changed;
    end) then
  begin
    FIncomingStarted := 0;
    FIncomingFresh := GetTickCount64;
  end;
end;

function TAtlasIdeContinue.Notice: string;
begin
  Result := '';
  if Enabled then
    Result := FNotice;
end;

procedure TAtlasIdeContinue.EnsureProject(const AProject: string);
var
  Actions: IOTAActionServices;
begin
  if (AProject = '') or not FileExists(AProject) or ProjectOpen(AProject) then
    Exit;
  if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
    Actions.OpenProject(AProject, True);
end;

class procedure TAtlasIdeContinue.OpenTab(const ATab: TAtlasWorkTab);
var
  Line, Column: Integer;
begin
  // Die Zusammenfassung zählt ab 1, der Editor ab 0.
  Line := ATab.Line - 1;
  if Line < 0 then
    Line := 0;
  Column := ATab.Column - 1;
  if Column < 0 then
    Column := 0;
  TAtlasIdeResults.Open(ATab.FileName, Line, Column);
end;

procedure TAtlasIdeContinue.Resume(const AProject: string);
var
  Project: string;
begin
  Project := AProject;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Summary: TAtlasProjectSummary;
      State: TAtlasWorkState;
      Plan: TAtlasContinuePlan;
      Names: TArray<string>;
      Tab: TAtlasWorkTab;
      Name: string;
    begin
      if not Enabled then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.WelcomeContinueDisabled));
        Exit;
      end;
      if not TAtlasProjectSummaries.Load(TAtlasIdeProjects.Folder, Project, Summary) or
        not TAtlasWelcomeContinue.Read(Summary, State) or (State.TabCount = 0) then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.WelcomeContinueNothing));
        Exit;
      end;
      if not FileExists(Project) then
      begin
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsMissing, [Project]));
        Exit;
      end;
      Plan := TAtlasWelcomeContinue.Plan(Project, State,
        function(const AFileName: string): Boolean
        begin
          Result := FileExists(AFileName);
        end);
      FNotice := '';
      if Length(Plan.Missing) > 0 then
      begin
        Names := nil;
        for Name in Plan.Missing do
          Names := Names + [ExtractFileName(Name)];
        FNotice := TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueMissing, [string.Join(', ', Names)]);
        Report(FNotice);
      end;
      EnsureProject(Project);
      // Reiter in ihrer Reihenfolge; danach den zuvor aktiven noch einmal, damit er vorn liegt.
      for Tab in Plan.Open do
        OpenTab(Tab);
      if (Plan.Active >= 0) and (Plan.Active <= High(Plan.Open)) then
        OpenTab(Plan.Open[Plan.Active]);
      Changed;
    end);
end;

procedure TAtlasIdeContinue.ResumeLatest;
var
  Entry: TAtlasContinueEntry;
begin
  if not Enabled then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.WelcomeContinueDisabled));
    Exit;
  end;
  Entry := Top;
  if Entry.Project = '' then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.WelcomeContinueNothing));
    Exit;
  end;
  Resume(Entry.Project);
end;

class function TAtlasIdeContinue.CommitEntries(const ACommit: TAtlasContinueCommit;
  const AFiles: TArray<string>): TArray<TAtlasResultEntry>;
var
  FileName, Own: string;
  Mine: Boolean;
  Entry: TAtlasResultEntry;
  First, Rest: TArray<TAtlasResultEntry>;
begin
  // Die eigenen Dateien zuerst.
  First := nil;
  Rest := nil;
  for FileName in AFiles do
  begin
    Entry := TAtlasResultEntry.Create(FileName, 0, 0);
    Entry.Text := TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueCommitFile, [ACommit.Commit.ShortHash]);
    Mine := False;
    for Own in ACommit.Files do
      if TAtlasWelcomeContinue.SameFile(Own, FileName) then
        Mine := True;
    if Mine then
      First := First + [Entry]
    else
      Rest := Rest + [Entry];
  end;
  Result := First + Rest;
end;

class procedure TAtlasIdeContinue.ShowCommitEntries(const ACommit: TAtlasContinueCommit;
  const AEntries: TArray<TAtlasResultEntry>);
begin
  TAtlasIdeResultsWindow.ShowEntries(TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueCommitTitle,
    [ACommit.Commit.ShortHash, ACommit.Commit.Summary, ACommit.Commit.Author, Length(AEntries)]), AEntries);
end;

procedure TAtlasIdeContinue.ShowCommit(const AProject: string; const ACommit: TAtlasContinueCommit);
var
  Keep: IAtlasContinueSource;
  Commit: TAtlasContinueCommit;
  Dir: string;
  Entries: TArray<TAtlasResultEntry>;
  Outcome: TAtlasVcsOutcome;
begin
  Commit := ACommit;
  if Length(Commit.Commit.Files) > 0 then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        ShowCommitEntries(Commit, CommitEntries(Commit, Commit.Commit.Files));
      end);
    Exit;
  end;
  // Ohne Dateiliste (z. B. Merge): beim Anbieter nachfragen.
  Keep := Self;
  Dir := ExtractFileDir(AProject);
  Entries := nil;
  Outcome := TAtlasVcsOutcome.Failed;
  TAtlasIdeVcs.Run(
    procedure
    var
      Local: IAtlasVcsLocalWork;
      Changes: TArray<TAtlasVcsChange>;
      Change: TAtlasVcsChange;
      Files: TArray<string>;
    begin
      if not Supports(TAtlasIdeVcs.ForFolder(Dir, TAtlasWelcomeContinue.FetchTimeoutMs), IAtlasVcsLocalWork,
        Local) then
        Exit;
      Outcome := Local.ChangesIn(Commit.Commit.Hash, Changes);
      Files := nil;
      for Change in Changes do
        Files := Files + [Change.Path];
      Entries := CommitEntries(Commit, Files);
    end,
    procedure
    begin
      if (Keep = nil) or FStopped then
        Exit;
      if Outcome <> TAtlasVcsOutcome.Ok then
      begin
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueCommitFailed, [Commit.Commit.ShortHash,
          AtlasVcsOutcomeName(Outcome)]));
        Exit;
      end;
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        begin
          ShowCommitEntries(Commit, Entries);
        end);
    end);
end;

function TAtlasIdeContinue.SavedEnabled: Boolean;
begin
  Result := Enabled and TAtlasIdeSettings.Current.WelcomePageSaved;
end;

function TAtlasIdeContinue.Saved: TAtlasSavedItems;
var
  Books: TArray<TAtlasNoteBook>;
  Lists: TArray<TAtlasBookmarkList>;
  List: TAtlasBookmarkList;
  Favorites: TAtlasFavorites;
  Items: TArray<TAtlasFavorite>;
  Recent, Projects: TArray<string>;
  Seen: TDictionary<string, Boolean>;
  Project, Member: string;
  Shared: Boolean;
begin
  Result := nil;
  if not SavedEnabled then
    Exit;
  Books := nil;
  Lists := nil;
  Items := nil;
  // Notizen (#545): alle Notizbücher im Ordner der Notizen.
  try
    Books := TAtlasNotes.LoadAll(TAtlasNotes.DefaultFolder);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  // Lesezeichen (#622): neben den zuletzt geöffneten Projekten; bei Projektgruppen auch neben deren Projekten.
  Recent := nil;
  try
    Recent := TAtlasIdeWelcomeSearch.RecentProjects;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  Projects := nil;
  for Project in Recent do
  begin
    Projects := Projects + [Project];
    if SameText(ExtractFileExt(Project), '.groupproj') and FileExists(Project) then
      try
        for Member in TAtlasWelcomeSaved.GroupProjects(Project, TFile.ReadAllText(Project)) do
          Projects := Projects + [Member];
      except
        // Gruppe nicht lesbar: nur ihr eigener Ordner.
        on E: Exception do
          TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
      end;
  end;
  Shared := TAtlasIdeSettings.Current.BookmarksShared;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Project in Projects do
    begin
      if SameText(ExtractFileExt(Project), '.groupproj') or Seen.ContainsKey(Key(Project)) then
        Continue;
      Seen.Add(Key(Project), True);
      try
        if FileExists(Project) and TAtlasBookmarks.Load(Project, Shared, List) and (List.Count > 0) then
          Lists := Lists + [List];
      except
        on E: Exception do
          TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
      end;
    end;
  finally
    Seen.Free;
  end;
  // Favoriten (#458): eigene Instanz, damit die der Vervollständigung unberührt bleibt.
  Favorites := TAtlasFavorites.Create;
  try
    try
      if FileExists(TAtlasIdeFavorites.FileName) then
        Favorites.LoadFromFile(TAtlasIdeFavorites.FileName);
      Items := Favorites.Items;
    except
      on E: Exception do
        TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
    end;
  finally
    Favorites.Free;
  end;
  Result := TAtlasWelcomeSaved.Collect(Books, Lists, Items);
end;

class function TAtlasIdeContinue.FileText(const AFileName: string): string;
var
  Buffer: IOTAEditBuffer;
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Index: Integer;
begin
  // Offene Datei: der Text des Puffers; sonst die Platte.
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
  begin
    Module := Modules.FindModule(AFileName);
    if Module <> nil then
      for Index := 0 to Module.ModuleFileCount - 1 do
        if SameText(Module.ModuleFileEditors[Index].FileName, AFileName) and
          Supports(Module.ModuleFileEditors[Index], IOTAEditBuffer, Buffer) then
          Exit(TAtlasEditorBuffer.Text(Buffer));
  end;
  Result := TFile.ReadAllText(AFileName);
end;

procedure TAtlasIdeContinue.OpenFavorite(const AItem: TAtlasSavedItem);
var
  Root, Cache, FileName: string;
  Caches: TArray<string>;
  Line: Integer;
  Cursor: TCursor;
begin
  // Datei der Unit aus den Index-Caches auf der Platte: erst die Projekte, dann die Bibliothek.
  FileName := '';
  Root := TAtlasIdeWelcomeSearch.CacheRoot;
  Caches := TAtlasWelcomeIndexFiles.CacheFiles(Root) + TAtlasWelcomeIndexFiles.LibraryCacheFiles(Root);
  Cursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    for Cache in Caches do
    begin
      FileName := TAtlasWelcomeSaved.FindUnit(TAtlasWelcomeIndexFiles.LoadUnits(Cache), AItem.UnitName);
      if (FileName <> '') and FileExists(FileName) then
        Break;
      FileName := '';
    end;
  finally
    Screen.Cursor := Cursor;
  end;
  if FileName = '' then
  begin
    Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeSavedUnitMissing, [AItem.Text, AItem.UnitName]));
    Exit;
  end;
  Line := TAtlasWelcomeSaved.DeclarationLine(FileText(FileName), AItem.TypeName, AItem.Member);
  if Line < 0 then
    Line := 0;
  TAtlasIdeResults.Open(FileName, Line, 0);
end;

procedure TAtlasIdeContinue.OpenSaved(const AItem: TAtlasSavedItem);
var
  Item: TAtlasSavedItem;
begin
  Item := AItem;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Line: Integer;
    begin
      if not SavedEnabled then
        Exit;
      if Item.Kind = TAtlasSavedKind.Favorite then
      begin
        OpenFavorite(Item);
        Exit;
      end;
      EnsureProject(Item.Project);
      if not FileExists(Item.FileName) then
      begin
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeSavedFileMissing, [Item.FileName]));
        Exit;
      end;
      // Lesezeichen mit eingeschalteter Funktion: über #622 (findet die Stelle vor dem Sprung wieder).
      if (Item.Kind = TAtlasSavedKind.Bookmark) and TAtlasIdeSettings.Current.BookmarksNamed then
      begin
        TAtlasIdeBookmarks.OpenBookmark(Item.Project, Item.Id);
        Exit;
      end;
      Line := Item.Line;
      if Line < 0 then
        Line := 0;
      TAtlasIdeResults.Open(Item.FileName, Line, 0);
    end);
end;

end.
