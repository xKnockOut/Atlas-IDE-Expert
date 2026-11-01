unit Atlas.IDE.Editor.UnitRename;

// uses nachziehen nach dem Umbenennen einer Unit (#512), IDE-Teil:
// - Erkennung: An jedem Projekt der Projektgruppe hängt ein Projekt-Notifier
//   (IOTAProjectNotifier.ModuleRenamed mit altem und neuem Dateinamen). Neu
//   geöffnete Projekte bekommen ihn über den IDE-Notifier, beim Start die
//   schon geladenen; geschlossene und zerstörte Projekte geben ihn frei.
// - Liegt die Unit in mehreren Projekten, kommt dasselbe Umbenennen mehrfach;
//   die Warteschlange (TAtlasUnitRenameQueue) fragt einmal. Ein Zeitgeber
//   wartet RenameDelayMs, bis die IDE .dpr, .dproj und den Unit-Kopf
//   angepasst hat.
// - Danach fragt Atlas den Server (atlas.server.unitRenamed) mit den Dateien
//   der Projektgruppe, wer den alten Namen noch verwendet. Ist
//   refactoring.unitRenameFollowUp "off", antwortet der Server
//   {"enabled": false} und Atlas tut nichts.
// - Sonst ein nicht modaler Hinweis „7 Units verwenden noch Kunden.
//   Anpassen?“ mit „Im Projekt anpassen …“ und „In der Projektgruppe
//   anpassen …“ (nur, wenn die Gruppe mehr betroffene Units hat). Er steht in
//   der Benachrichtigungszentrale (Quelle unitRename) und, im Verhalten Show,
//   zusätzlich als eigene Einblendung unten rechts und als Zeile in der
//   Meldungsansicht. Wer nichts wählt, ändert nichts.
// - Eine Aktion holt das WorkspaceEdit für den gewählten Bereich neu, zeigt
//   die Vorschau wie beim Umbenennen und übernimmt erst nach Bestätigung über
//   TAtlasIdeWorkspaceEdit (#397): offene Puffer rückgängig machbar, nicht
//   offene Dateien je nach editor.openForEdits, mit Kodierung und
//   Zeilenenden (#121).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Projects.UnitRename,
  Atlas.UI.Notifications.Notice;

type
  TAtlasIdeUnitRename = class
  public const
    /// <summary>Wartezeit nach dem Umbenennen, bis die IDE ihre eigenen Anpassungen fertig hat.</summary>
    RenameDelayMs = 500;
    /// <summary>Alle verwendenden Units lesen dauert; wie beim Umbenennen.</summary>
    TimeoutMs = 60000;
  private type
    TProjectNotifier = class(TInterfacedObject, IOTANotifier, IOTAModuleNotifier, IOTAProjectNotifier)
    private
      FOwner: TAtlasIdeUnitRename;
      FProject: IOTAProject;
      FIndex: Integer;
    public
      procedure AfterSave;
      procedure BeforeSave;
      procedure Destroyed;
      procedure Modified;
      function CheckOverwrite: Boolean;
      procedure ModuleRenamed(const NewName: string); overload;
      procedure ModuleAdded(const AFileName: string);
      procedure ModuleRemoved(const AFileName: string);
      procedure ModuleRenamed(const AOldFileName, ANewFileName: string); overload;
      /// <summary>Beim Projekt abmelden; mehrfach aufrufbar.</summary>
      procedure Detach;
    end;

    TIdeNotifier = class(TNotifierObject, IOTAIDENotifier)
    private
      FOwner: TAtlasIdeUnitRename;
    public
      procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
      procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
      procedure AfterCompile(Succeeded: Boolean); overload;
    end;
  private class var
    FInstance: TAtlasIdeUnitRename;
  private
    FSessionOf: TFunc<TLspSession>;
    FReport: TProc<string>;
    FQueue: TAtlasUnitRenameQueue;
    FProjects: TList<TProjectNotifier>;
    FNotifier: TIdeNotifier;
    FNotifierRef: IOTAIDENotifier;
    FNotifierIndex: Integer;
    FTimer: TTimer;
    FNotice: TAtlasNoticeWindow;
    procedure Tick(Sender: TObject);
    /// <summary>Jedes Projekt der Gruppe bekommt einen Notifier (schon versorgte bleiben).</summary>
    procedure Sweep;
    procedure Attach(const AProject: IOTAProject);
    procedure Closing(const AFileName: string);
    procedure Renamed(const AProject: IOTAProject; const AOldFileName, ANewFileName: string);
    procedure Forget(ANotifier: TProjectNotifier);
    procedure Offer(const AEvent: TAtlasUnitRenameEvent);
    procedure Run(const AEvent: TAtlasUnitRenameEvent; AScope: TAtlasUnitRenameScope);
    procedure Say(const AText: string);
    /// <summary>Aktion für die Zentrale; läuft nur, solange es den Dienst noch gibt.</summary>
    class function RunAction(const AEvent: TAtlasUnitRenameEvent; AScope: TAtlasUnitRenameScope): TProc; static;
    /// <summary>Quelltexte eines Projekts: .dpr/.dpk und alle Module.</summary>
    class function FilesOf(const AProject: IOTAProject): TArray<string>; static;
    /// <summary>Dateien des Bereichs zum Projekt AProjectFile.</summary>
    class function ScopeFiles(const AProjectFile: string; AScope: TAtlasUnitRenameScope): TArray<string>; static;
  public
    constructor Create(const ASessionOf: TFunc<TLspSession>; const AReport: TProc<string>);
    destructor Destroy; override;
  end;

implementation

uses
  System.JSON,
  System.Types,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Results.Model,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Window,
  Atlas.UI.Results.Frame,
  Atlas.UI.Results.RenamePreview,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit;

function IsProjectFile(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.dproj') or (Extension = '.dpr') or (Extension = '.dpk') or (Extension = '.groupproj');
end;

{ TAtlasIdeUnitRename.TProjectNotifier }

procedure TAtlasIdeUnitRename.TProjectNotifier.AfterSave;
begin
end;

procedure TAtlasIdeUnitRename.TProjectNotifier.BeforeSave;
begin
end;

procedure TAtlasIdeUnitRename.TProjectNotifier.Modified;
begin
end;

function TAtlasIdeUnitRename.TProjectNotifier.CheckOverwrite: Boolean;
begin
  Result := True;
end;

procedure TAtlasIdeUnitRename.TProjectNotifier.ModuleRenamed(const NewName: string);
begin
  // Das Projekt selbst wurde umbenannt; für #512 ohne Bedeutung.
end;

procedure TAtlasIdeUnitRename.TProjectNotifier.ModuleAdded(const AFileName: string);
begin
end;

procedure TAtlasIdeUnitRename.TProjectNotifier.ModuleRemoved(const AFileName: string);
begin
end;

procedure TAtlasIdeUnitRename.TProjectNotifier.ModuleRenamed(const AOldFileName, ANewFileName: string);
var
  Owner: TAtlasIdeUnitRename;
  Project: IOTAProject;
  OldName, NewName: string;
begin
  Owner := FOwner;
  Project := FProject;
  if (Owner = nil) or (Project = nil) then
    Exit;
  OldName := AOldFileName;
  NewName := ANewFileName;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.Files,
    procedure
    begin
      Owner.Renamed(Project, OldName, NewName);
    end);
end;

procedure TAtlasIdeUnitRename.TProjectNotifier.Destroyed;
var
  Owner: TAtlasIdeUnitRename;
begin
  Owner := FOwner;
  if Owner <> nil then
    Owner.Forget(Self);
  // Zuletzt: Mit dem Abmelden kann die IDE die letzte Referenz freigeben.
  Detach;
end;

procedure TAtlasIdeUnitRename.TProjectNotifier.Detach;
var
  Project: IOTAProject;
  Index: Integer;
begin
  Project := FProject;
  Index := FIndex;
  FProject := nil;
  FOwner := nil;
  FIndex := -1;
  // Danach keine Felder mehr: RemoveNotifier kann dieses Objekt freigeben.
  if (Project <> nil) and (Index >= 0) then
    Project.RemoveNotifier(Index);
end;

{ TAtlasIdeUnitRename.TIdeNotifier }

procedure TAtlasIdeUnitRename.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
var
  Owner: TAtlasIdeUnitRename;
  Name: string;
begin
  Owner := FOwner;
  if (Owner = nil) or not ((NotifyCode = ofnFileOpened) or (NotifyCode = ofnFileClosing)) or
    not IsProjectFile(FileName) then
    Exit;
  Name := FileName;
  if NotifyCode = ofnFileOpened then
    TAtlasGuard.Run(TAtlasFeature.Files,
      procedure
      begin
        Owner.Sweep;
      end)
  else
    TAtlasGuard.Run(TAtlasFeature.Files,
      procedure
      begin
        Owner.Closing(Name);
      end);
end;

procedure TAtlasIdeUnitRename.TIdeNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TAtlasIdeUnitRename.TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ TAtlasIdeUnitRename }

constructor TAtlasIdeUnitRename.Create(const ASessionOf: TFunc<TLspSession>; const AReport: TProc<string>);
var
  Services: IOTAServices;
begin
  inherited Create;
  FSessionOf := ASessionOf;
  FReport := AReport;
  FQueue := TAtlasUnitRenameQueue.Create;
  FProjects := TList<TProjectNotifier>.Create;
  FNotifierIndex := -1;
  if Supports(BorlandIDEServices, IOTAServices, Services) then
  begin
    FNotifier := TIdeNotifier.Create;
    FNotifier.FOwner := Self;
    FNotifierRef := FNotifier;
    FNotifierIndex := Services.AddNotifier(FNotifierRef);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := RenameDelayMs;
  FTimer.OnTimer := Tick;
  FInstance := Self;
  // Schon geladene Projekte (die IDE lädt das letzte Projekt oft vor dem Plugin).
  Sweep;
end;

destructor TAtlasIdeUnitRename.Destroy;
var
  Services: IOTAServices;
  Notifier: TProjectNotifier;
begin
  if FInstance = Self then
    FInstance := nil;
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
    FTimer.Free;
  end;
  FNotice.Free;
  // Erst abmelden, dann freigeben (#493).
  if FNotifier <> nil then
    FNotifier.FOwner := nil;
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, Services) then
    Services.RemoveNotifier(FNotifierIndex);
  FNotifierRef := nil;
  for Notifier in FProjects.ToArray do
    Notifier.Detach;
  FProjects.Free;
  FQueue.Free;
  inherited;
end;

procedure TAtlasIdeUnitRename.Sweep;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Group := Modules.MainProjectGroup;
  if Group = nil then
    Exit;
  for Index := 0 to Group.ProjectCount - 1 do
    Attach(Group.Projects[Index]);
end;

procedure TAtlasIdeUnitRename.Attach(const AProject: IOTAProject);
var
  Notifier: TProjectNotifier;
  Reference: IOTAProjectNotifier;
begin
  if AProject = nil then
    Exit;
  for Notifier in FProjects do
    if Notifier.FProject = AProject then
      Exit;
  Notifier := TProjectNotifier.Create;
  Notifier.FOwner := Self;
  Notifier.FProject := AProject;
  Reference := Notifier;
  // Die IDE hält die Referenz; Detach gibt sie frei.
  Notifier.FIndex := AProject.AddNotifier(Reference);
  FProjects.Add(Notifier);
end;

procedure TAtlasIdeUnitRename.Closing(const AFileName: string);
var
  Notifier: TProjectNotifier;
begin
  for Notifier in FProjects.ToArray do
    if (Notifier.FProject <> nil) and (SameText(Notifier.FProject.FileName, AFileName) or
      SameText(ChangeFileExt(Notifier.FProject.FileName, ExtractFileExt(AFileName)), AFileName)) then
    begin
      FProjects.Remove(Notifier);
      Notifier.Detach;
    end;
end;

procedure TAtlasIdeUnitRename.Forget(ANotifier: TProjectNotifier);
begin
  FProjects.Remove(ANotifier);
end;

procedure TAtlasIdeUnitRename.Renamed(const AProject: IOTAProject; const AOldFileName, ANewFileName: string);
begin
  if not FQueue.Add(TAtlasUnitRenameEvent.Create(AOldFileName, ANewFileName, AProject.FileName)) then
    Exit;
  // Anonym: keine Datei- oder Unit-Namen (#647).
  TAtlasGuard.Log('Unit umbenannt (#512)');
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeUnitRename.Tick(Sender: TObject);
var
  Event: TAtlasUnitRenameEvent;
begin
  FTimer.Enabled := False;
  try
    for Event in FQueue.Take do
      Offer(Event);
  except
    // Keine Exception an die IDE (#493).
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Files, E);
  end;
end;

procedure TAtlasIdeUnitRename.Say(const AText: string);
begin
  if Assigned(FReport) then
    FReport(AText);
end;

class function TAtlasIdeUnitRename.RunAction(const AEvent: TAtlasUnitRenameEvent;
  AScope: TAtlasUnitRenameScope): TProc;
var
  Event: TAtlasUnitRenameEvent;
begin
  // Eigene Funktion: Jede Aktion fängt ihren Bereich als Wert ein, nicht die Schleifenvariable.
  Event := AEvent;
  Result :=
    procedure
    begin
      if FInstance <> nil then
        FInstance.Run(Event, AScope);
    end;
end;

class function TAtlasIdeUnitRename.FilesOf(const AProject: IOTAProject): TArray<string>;
var
  Mains: array[0..1] of string;
  Main: string;
  Index: Integer;
  Info: IOTAModuleInfo;
begin
  Result := nil;
  if AProject = nil then
    Exit;
  Mains[0] := ChangeFileExt(AProject.FileName, '.dpr');
  Mains[1] := ChangeFileExt(AProject.FileName, '.dpk');
  for Main in Mains do
    if FileExists(Main) then
      Result := Result + [Main];
  for Index := 0 to AProject.GetModuleCount - 1 do
  begin
    Info := AProject.GetModule(Index);
    if (Info <> nil) and (Info.FileName <> '') then
      Result := Result + [Info.FileName];
  end;
  Result := TAtlasUnitRename.SourceFiles(Result);
end;

class function TAtlasIdeUnitRename.ScopeFiles(const AProjectFile: string;
  AScope: TAtlasUnitRenameScope): TArray<string>;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Project: IOTAProject;
  Index: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  if AScope = TAtlasUnitRenameScope.Group then
  begin
    Group := Modules.MainProjectGroup;
    if Group <> nil then
      for Index := 0 to Group.ProjectCount - 1 do
        Result := Result + FilesOf(Group.Projects[Index]);
    Result := TAtlasUnitRename.SourceFiles(Result);
  end;
  // Ohne Gruppe (oder Projekt außerhalb) zählt das Projekt.
  if (AScope = TAtlasUnitRenameScope.Project) or (Result = nil) then
    if Supports(Modules.FindModule(AProjectFile), IOTAProject, Project) then
      Result := TAtlasUnitRename.SourceFiles(Result + FilesOf(Project));
end;

procedure TAtlasIdeUnitRename.Offer(const AEvent: TAtlasUnitRenameEvent);
var
  Session: TLspSession;
  Group, Project: TArray<string>;
  Reply: TJSONValue;
  Answer: TAtlasUnitRenameAnswer;
  InProject, InGroup, Shown: Integer;
  Title, Text: string;
  Captions: TArray<string>;
  Scopes: TArray<TAtlasUnitRenameScope>;
  Actions: TArray<TAtlasNotificationAction>;
  Action: TAtlasNotificationAction;
  Scope: TAtlasUnitRenameScope;
  Event: TAtlasUnitRenameEvent;
  Mode: TAtlasNotificationMode;
  Area: TRect;
begin
  Session := nil;
  if Assigned(FSessionOf) then
    Session := FSessionOf();
  if Session = nil then
    Exit;
  Group := ScopeFiles(AEvent.ProjectFile, TAtlasUnitRenameScope.Group);
  Project := ScopeFiles(AEvent.ProjectFile, TAtlasUnitRenameScope.Project);
  TAtlasIdeRename.SyncOpenBuffers(Session);
  try
    Reply := Session.RunCommand(TAtlasUnitRename.Command,
      TAtlasUnitRename.Arguments(AEvent.OldFile, AEvent.NewFile, Group), TimeoutMs);
    try
      Answer := TAtlasUnitRename.ReadAnswer(Reply);
    finally
      Reply.Free;
    end;
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.UnitRenameFailed, [E.Message]));
      Exit;
    end;
  end;
  // refactoring.unitRenameFollowUp = off: wie ohne die Funktion.
  if not Answer.Enabled or (Length(Answer.Files) = 0) then
    Exit;
  InProject := TAtlasUnitRename.CountIn(Answer, Project);
  InGroup := TAtlasUnitRename.CountIn(Answer, Group);
  Shown := InProject;
  if Shown = 0 then
    Shown := InGroup;
  if Shown = 1 then
    Title := TAtlasStrings.Fmt(TAtlasTextId.UnitRenameNoticeOne, [Answer.OldName])
  else
    Title := TAtlasStrings.Fmt(TAtlasTextId.UnitRenameNotice, [Shown, Answer.OldName]);
  Text := '';
  if InGroup > InProject then
    Text := TAtlasStrings.Fmt(TAtlasTextId.UnitRenameGroupCount, [InGroup]);
  Captions := nil;
  Scopes := nil;
  if InProject > 0 then
  begin
    Captions := Captions + [TAtlasStrings.Text(TAtlasTextId.UnitRenameProject)];
    Scopes := Scopes + [TAtlasUnitRenameScope.Project];
  end;
  if InGroup > InProject then
  begin
    Captions := Captions + [TAtlasStrings.Text(TAtlasTextId.UnitRenameGroup)];
    Scopes := Scopes + [TAtlasUnitRenameScope.Group];
  end;
  Event := AEvent;
  Actions := nil;
  for Scope in Scopes do
  begin
    Action.Caption := TAtlasStrings.Text(TAtlasTextId.UnitRenameProject);
    if Scope = TAtlasUnitRenameScope.Group then
      Action.Caption := TAtlasStrings.Text(TAtlasTextId.UnitRenameGroup);
    Action.Run := RunAction(Event, Scope);
    Actions := Actions + [Action];
  end;
  Mode := TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.UnitRename,
    TAtlasNotificationSeverity.Info, Title, Text, Actions);
  if Mode <> TAtlasNotificationMode.Show then
    Exit;
  Say(TAtlasStrings.Fmt(TAtlasTextId.UnitRenameReport, [Answer.OldName, Answer.NewName, InProject, InGroup]));
  if FNotice = nil then
    FNotice := TAtlasNoticeWindow.Create(nil);
  FNotice.OnAction :=
    procedure(AIndex: Integer)
    begin
      if (AIndex >= 0) and (AIndex <= High(Scopes)) then
        Run(Event, Scopes[AIndex]);
    end;
  Area := Screen.WorkAreaRect;
  if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect;
  FNotice.Colors := TAtlasIdeStyle.Colors;
  FNotice.SetScaling(TAtlasPopupWindow.MonitorPPI(Area.BottomRight), 1, '', 10);
  FNotice.ShowNotice(Title, Text, Captions, Area);
end;

procedure TAtlasIdeUnitRename.Run(const AEvent: TAtlasUnitRenameEvent; AScope: TAtlasUnitRenameScope);
var
  Session: TLspSession;
  Files: TArray<string>;
  Reply: TJSONValue;
  Answer: TAtlasUnitRenameAnswer;
  Edit: TLspWorkspaceEdit;
  Hint: string;
  Preview: TArray<TAtlasResultEntry>;
  Open: TAtlasResultsOpen;
  Outcome: TAtlasWorkspaceEditResult;
begin
  if FNotice <> nil then
    FNotice.Dismiss;
  Session := nil;
  if Assigned(FSessionOf) then
    Session := FSessionOf();
  if Session = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  // Neu holen: Seit dem Hinweis kann sich der Text geändert haben.
  Files := ScopeFiles(AEvent.ProjectFile, AScope);
  TAtlasIdeRename.SyncOpenBuffers(Session);
  Edit := TLspWorkspaceEdit.FromJson(nil);
  try
    Reply := Session.RunCommand(TAtlasUnitRename.Command,
      TAtlasUnitRename.Arguments(AEvent.OldFile, AEvent.NewFile, Files), TimeoutMs);
    try
      Answer := TAtlasUnitRename.ReadAnswer(Reply);
      if Answer.Enabled and (Reply is TJSONObject) then
        Edit := TLspWorkspaceEdit.FromJson(TJSONObject(Reply).GetValue('edit'));
    finally
      Reply.Free;
    end;
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.UnitRenameFailed, [E.Message]));
      Exit;
    end;
  end;
  if not Answer.Enabled then
    Exit;
  if Edit.IsEmpty then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.UnitRenameNothing, [Answer.OldName]));
    Exit;
  end;
  Hint := TAtlasStrings.Fmt(TAtlasTextId.UnitRenamePreviewHint, [Answer.OldName, Answer.NewName, Edit.EditCount,
    Length(Edit.Files)]);
  Preview := TAtlasResults.RenamePreview(Edit,
    function(const AFileName: string): string
    begin
      Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
    end);
  Open :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter);
    end;
  // Ablehnen ändert nichts.
  if not TAtlasRenamePreview.Execute(TAtlasStrings.Text(TAtlasTextId.UnitRenameTitle), Hint,
    TAtlasStrings.Text(TAtlasTextId.UnitRenameApply), TAtlasResults.Group(Preview), Open) then
    Exit;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, TAtlasUnopenedPolicies.FromSetting(
    TAtlasIdeSettings.Current.OpenForEdits), TAtlasStrings.Text(TAtlasTextId.UnitRenameTitle));
  if Outcome.Error <> '' then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  Say(TAtlasStrings.Fmt(TAtlasTextId.UnitRenameDone, [Answer.OldName, Answer.NewName, Outcome.Edits,
    Outcome.Files]));
  if Outcome.Written > 0 then
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
end;

end.
