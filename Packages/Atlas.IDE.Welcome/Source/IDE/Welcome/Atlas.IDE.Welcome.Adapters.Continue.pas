unit Atlas.IDE.Welcome.Adapters.Continue;

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
//   (#400, Atlas.IDE.Welcome.Continue.Commit); eine eigene Commit-Ansicht hat
//   #571 nicht.
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
// - Schnellaktionen (#764): Die Quelle der Knopfleiste (QuickActions, aus der
//   Composition) bekommt jeder Frame.
// - Reiter „Issues“ (#2052): Arbeitsstand je Issue in
//   Atlas.IDE.Welcome.ContinueIssueLink (legt die Composition an); WriteState schreibt denselben Stand
//   dort unter dem aktiven Issue.
// - Der Ablauf (Mitschreiben, Schreiben, Abfragen, Fortsetzen) liegt in
//   Atlas.Core.Welcome.ContinueWork; die IDE erreicht er über
//   IAtlasContinueHost (Atlas.IDE.Welcome.Adapters.ContinueHost, legt die
//   Composition an). Hier bleiben die Beobachter der IDE, der Bereich und
//   „Gemerkt“ (Atlas.IDE.Welcome.Continue.Saved).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  ToolsAPI,
  DockForm,
  Atlas.Core.Welcome.Contract,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.ContinueWork,
  Atlas.Core.Welcome.Saved,
  Atlas.IDE.Welcome.ContinueIssueLink,
  Atlas.Core.Notifications.MessageSink,
  Atlas.UI.Welcome.Contract;

type
  /// <summary>Was die Komposition dem Bereich mitgibt.</summary>
  TAtlasIdeContinueHooks = record
    /// <summary>Quelle der Schnellaktionen (#764) für neue Frames; nil = keine Knöpfe. Vor Start setzen.</summary>
    QuickActions: IAtlasQuickActionsSource;
    /// <summary>„Anmeldung am Server nötig – prüfen …“ (#1287): Seite Versionsverwaltung für den Ordner öffnen;
    /// nil = Link ohne Wirkung.</summary>
    OnServerAccess: TProc<string>;
  end;

  TAtlasIdeContinue = class(TInterfacedObject, IAtlasContinueSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts.</summary>
    cOrder = 15;
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

    /// <summary>Angemeldete Beobachter der IDE mit ihrem Index (-1 = keiner).</summary>
    TNotifiers = record
      Ide: TIdeNotifier;
      IdeIndex: Integer;
      Edit: TEditNotifier;
      EditIndex: Integer;
    end;
  private
    FMessage: TAtlasMessageSink;
    FNotifiers: TNotifiers;
    // Ablauf in Core; die Referenz hält ihn am Leben, solange eine Abfrage läuft.
    FWork: TAtlasContinueWork;
    FWorkRef: IInterface;
    // Reiter „Issues“ (#2052); die Referenz hält es am Leben, auch solange Frames es noch kennen.
    FIssues: IInterface;
    FHooks: TAtlasIdeContinueHooks;
    procedure Changed;
    function Enabled: Boolean;
    procedure Modified(const AView: IOTAEditView);
    procedure OpenFavorite(const AItem: TAtlasSavedItem);
  public
    /// <summary>Quelle der Schnellaktionen und Seite Versionsverwaltung; setzt die Komposition.</summary>
    property QuickActions: IAtlasQuickActionsSource read FHooks.QuickActions write FHooks.QuickActions;
    property OnServerAccess: TProc<string> read FHooks.OnServerAccess write FHooks.OnServerAccess;
    /// <summary>AMessage: Zeile in die Meldungsansicht; AHost: die IDE für den Ablauf; AIssues legt den Reiter
    /// „Issues“ an (#2052).</summary>
    constructor Create(const AMessage: TProc<string>; const AHost: IAtlasContinueHost;
      const AIssues: TAtlasIdeContinueIssuesCreate);
    destructor Destroy; override;
    /// <summary>Bereich, Fabrik und Beobachter der IDE anmelden.</summary>
    procedure Start;
    /// <summary>Stand des offenen Projekts schreiben (Beenden der IDE), alles abmelden; danach wirkungslos.</summary>
    procedure Stop;
    function Section: TAtlasWelcomeSection;
    /// <summary>Palettenbefehl Atlas.Continue: obersten Arbeitsstand fortsetzen.</summary>
    procedure ResumeLatest;
    /// <summary>Arbeitsstand je Issue (#2052); bis zur Freigabe vorhanden.</summary>
    function Issues: TAtlasIdeContinueIssueLink;
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
    procedure ShowServerAccess(const AProject: string);
    procedure Shown;
  end;

implementation

uses
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Search,
  Atlas.UI.Welcome.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Welcome.Neighbors,
  Atlas.IDE.Welcome.Continue.Editor,
  Atlas.IDE.Welcome.Continue.Saved,
  Atlas.IDE.Welcome.Continue.Commit,
  Atlas.UI.Welcome.Continue;

{ TAtlasIdeContinue.TIdeNotifier }

procedure TAtlasIdeContinue.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
var
  mOwner: TAtlasIdeContinue;
  mName: string;
  mCode: TOTAFileNotification;
begin
  mOwner := FOwner;
  if (mOwner = nil) or not ((NotifyCode = ofnFileOpened) or (NotifyCode = ofnFileClosing)) then
  begin
    Exit;
  end;
  mName := FileName;
  mCode := NotifyCode;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if not TAtlasWelcomeSearch.IsProjectFile(mName) then
      begin
        if mCode = ofnFileClosing then
        begin
          mOwner.FWork.SourceClosing;
        end;
      end
      else if mCode = ofnFileOpened then
      begin
        mOwner.FWork.ProjectOpened(mName);
      end
      else
      begin
        mOwner.FWork.ProjectClosing(mName);
      end;
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
  mOwner: TAtlasIdeContinue;
begin
  mOwner := FOwner;
  if mOwner = nil then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      mOwner.FWork.Activated;
    end);
end;

procedure TAtlasIdeContinue.TEditNotifier.EditorViewModified(const EditWindow: INTAEditWindow;
  const EditView: IOTAEditView);
var
  mOwner: TAtlasIdeContinue;
  mView: IOTAEditView;
begin
  mOwner := FOwner;
  if (mOwner = nil) or (EditView = nil) then
  begin
    Exit;
  end;
  mView := EditView;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      mOwner.Modified(mView);
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

constructor TAtlasIdeContinue.Create(const AMessage: TProc<string>; const AHost: IAtlasContinueHost;
  const AIssues: TAtlasIdeContinueIssuesCreate);
begin
  inherited Create;
  FMessage := TAtlasMessageSink.Create(AMessage);
  FNotifiers.IdeIndex := -1;
  FNotifiers.EditIndex := -1;
  FWork := TAtlasContinueWork.Create(AHost);
  FWorkRef := FWork;
  FIssues := AIssues(AMessage, FWork.Changes, Changed);
  FWork.OnWritten :=
    procedure(ATarget: string; ASnapshot: TAtlasContinueSnapshot)
    begin
      Issues.ProjectWritten(ATarget, ASnapshot);
    end;
end;

destructor TAtlasIdeContinue.Destroy;
begin
  Stop;
  FIssues := nil;
  FWork := nil;
  FWorkRef := nil;
  inherited;
end;

procedure TAtlasIdeContinue.Changed;
begin
  if not FWork.Stopped then
  begin
    TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.cContinue);
  end;
end;

function TAtlasIdeContinue.Enabled: Boolean;
begin
  Result := FWork.Enabled;
end;

procedure TAtlasIdeContinue.Modified(const AView: IOTAEditView);
begin
  if (AView.Buffer = nil) or (AView.Buffer.FileName = '') then
  begin
    Exit;
  end;
  FWork.Modified(AView.Buffer.FileName, AView.CursorPos.Line, AView.CursorPos.Col);
end;

procedure TAtlasIdeContinue.OpenFavorite(const AItem: TAtlasSavedItem);
var
  mFileName: string;
  mLine: Integer;
begin
  if not TAtlasIdeContinueSaved.FindFavorite(AItem, mFileName, mLine) then
  begin
    FMessage.Say(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSavedUnitMissing, [AItem.Text, AItem.UnitName]));
    Exit;
  end;
  TAtlasIdeResults.Open(mFileName, mLine, 0);
end;

procedure TAtlasIdeContinue.Start;
var
  mServices: IOTAServices;
  mEditors: IOTAEditorServices;
  mKeep: IAtlasContinueSource;
begin
  mKeep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.cContinue,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeContinueFrame;
    begin
      Frame := TAtlasWelcomeContinueFrame.Create(AOwner);
      Frame.Source := mKeep;
      // Schnellaktionen (#764): dieselbe Quelle für jeden Frame.
      Frame.QuickActions := FHooks.QuickActions;
      // Reiter „Issues“ (#2052).
      Frame.IssuesSource := Issues.Source;
      Result := Frame;
    end);
  TAtlasWelcomeSections.Default.Add(Section);
  if (FNotifiers.Ide = nil) and Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    FNotifiers.Ide := TIdeNotifier.Create;
    FNotifiers.Ide.FOwner := Self;
    FNotifiers.IdeIndex := mServices.AddNotifier(FNotifiers.Ide);
  end;
  if (FNotifiers.Edit = nil) and Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    FNotifiers.Edit := TEditNotifier.Create;
    FNotifiers.Edit.FOwner := Self;
    FNotifiers.EditIndex := mEditors.AddNotifier(FNotifiers.Edit);
  end;
  // Plugin nach dem Öffnen eines Projekts geladen: HEAD trotzdem kennen.
  FWork.Started;
end;

procedure TAtlasIdeContinue.Stop;
var
  mServices: IOTAServices;
  mEditors: IOTAEditorServices;
begin
  if (FWork = nil) or FWork.Stopped then
  begin
    Exit;
  end;
  // Beenden der IDE: Ist das Projekt noch offen (kein Schließen gemeldet), schreibt der Ablauf jetzt.
  try
    FWork.Stop;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  FWork.OnWritten := nil;
  Issues.Stop;
  FHooks.OnServerAccess := nil;
  if FNotifiers.Ide <> nil then
  begin
    FNotifiers.Ide.FOwner := nil;
    // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter (#493).
    if (FNotifiers.IdeIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
    begin
      mServices.RemoveNotifier(FNotifiers.IdeIndex);
    end;
    FNotifiers.Ide := nil;
    FNotifiers.IdeIndex := -1;
  end;
  if FNotifiers.Edit <> nil then
  begin
    FNotifiers.Edit.FOwner := nil;
    if (FNotifiers.EditIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
    begin
      mEditors.RemoveNotifier(FNotifiers.EditIndex);
    end;
    FNotifiers.Edit := nil;
    FNotifiers.EditIndex := -1;
  end;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.cContinue);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.cContinue);
  FHooks.QuickActions := nil;
end;

function TAtlasIdeContinue.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.cContinue,
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueTitle), cOrder, TAtlasWelcomeColumn.Left,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.WelcomePageContinue;
    end);
end;

procedure TAtlasIdeContinue.ResumeLatest;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      FWork.ResumeLatest;
    end);
end;

function TAtlasIdeContinue.Issues: TAtlasIdeContinueIssueLink;
begin
  Result := FIssues as TAtlasIdeContinueIssueLink;
end;

function TAtlasIdeContinue.Entries: TAtlasContinueEntries;
begin
  Result := FWork.Entries;
end;

function TAtlasIdeContinue.Incoming: TAtlasContinueIncoming;
begin
  Result := FWork.Incoming;
end;

function TAtlasIdeContinue.IncomingQuerying: Boolean;
begin
  Result := FWork.IncomingQuerying;
end;

function TAtlasIdeContinue.SavedEnabled: Boolean;
begin
  Result := Enabled and TAtlasIdeSettings.Current.WelcomePageSaved;
end;

function TAtlasIdeContinue.Saved: TAtlasSavedItems;
begin
  Result := nil;
  if SavedEnabled then
  begin
    Result := TAtlasIdeContinueSaved.Items;
  end;
end;

function TAtlasIdeContinue.Notice: string;
begin
  Result := FWork.Notice;
end;

procedure TAtlasIdeContinue.Resume(const AProject: string);
var
  mProject: string;
begin
  mProject := AProject;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      FWork.Resume(mProject);
    end);
end;

procedure TAtlasIdeContinue.ShowCommit(const AProject: string; const ACommit: TAtlasContinueCommit);
var
  mKeep: IAtlasContinueSource;
begin
  mKeep := Self;
  TAtlasIdeContinueCommit.Show(AProject, ACommit,
    function: Boolean
    begin
      Result := (mKeep <> nil) and not FWork.Stopped;
    end, FMessage);
end;

procedure TAtlasIdeContinue.OpenSaved(const AItem: TAtlasSavedItem);
var
  mItem: TAtlasSavedItem;
begin
  mItem := AItem;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Line: Integer;
    begin
      if not SavedEnabled then
      begin
        Exit;
      end;
      if mItem.Kind = TAtlasSavedKind.Favorite then
      begin
        OpenFavorite(mItem);
        Exit;
      end;
      TAtlasIdeContinueEditor.EnsureProject(mItem.Project);
      if not FileExists(mItem.FileName) then
      begin
        FMessage.Say(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSavedFileMissing, [mItem.FileName]));
        Exit;
      end;
      // Lesezeichen mit eingeschalteter Funktion: über #622 (findet die Stelle vor dem Sprung wieder).
      if (mItem.Kind = TAtlasSavedKind.Bookmark) and TAtlasWelcomeNeighbors.OpenBookmark(mItem.Project, mItem.Id) then
      begin
        Exit;
      end;
      Line := mItem.Line;
      if Line < 0 then
      begin
        Line := 0;
      end;
      TAtlasIdeResults.Open(mItem.FileName, Line, 0);
    end);
end;

procedure TAtlasIdeContinue.ShowServerAccess(const AProject: string);
var
  mFolder: string;
begin
  mFolder := ExtractFileDir(AProject);
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if FWork.Stopped or not Assigned(FHooks.OnServerAccess) or (mFolder = '') then
      begin
        Exit;
      end;
      FHooks.OnServerAccess(mFolder);
      // Nach dem Dialog (vielleicht angemeldet): eingehende Commits neu abfragen.
      FWork.RefreshIncoming(True);
    end);
end;

procedure TAtlasIdeContinue.Shown;
begin
  FWork.RefreshIncoming(False);
end;

end.
