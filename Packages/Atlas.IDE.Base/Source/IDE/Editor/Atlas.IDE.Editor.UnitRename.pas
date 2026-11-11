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
    cRenameDelayMs = 500;
    /// <summary>Alle verwendenden Units lesen dauert; wie beim Umbenennen.</summary>
    cTimeoutMs = 60000;
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
    /// <summary>Antwort des Servers für die Dateien AFiles; False (mit Meldung), wenn er scheitert.</summary>
    function FetchAnswer(ASession: TLspSession; const AEvent: TAtlasUnitRenameEvent; const AFiles: TArray<string>;
      out AAnswer: TAtlasUnitRenameAnswer): Boolean;
    /// <summary>Eigene Einblendung unten rechts mit einem Knopf je Bereich aus AScopes.</summary>
    procedure ShowNotice(const AEvent: TAtlasUnitRenameEvent; const ATitle, AText: string;
      const AScopes: TArray<TAtlasUnitRenameScope>);
    procedure Run(const AEvent: TAtlasUnitRenameEvent; AScope: TAtlasUnitRenameScope);
    procedure Say(const AText: string);
    /// <summary>Say als Methodenreferenz (eigene Routine, damit kein Rahmen sich selbst festhält).</summary>
    function Reporter: TProc<string>;
    /// <summary>Laufende Sitzung oder nil.</summary>
    function CurrentSession: TLspSession;
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
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.UI.Strings,
  Atlas.UI.Editor.Strings,
  Atlas.UI.Popup.Window,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.ServerEdit;

function IsProjectFile(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.dproj') or (mExtension = '.dpr') or (mExtension = '.dpk') or (mExtension = '.groupproj');
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
  mOwner: TAtlasIdeUnitRename;
  mProject: IOTAProject;
  mOldName, mNewName: string;
begin
  mOwner := FOwner;
  mProject := FProject;
  if (mOwner = nil) or (mProject = nil) then
  begin
    Exit;
  end;
  mOldName := AOldFileName;
  mNewName := ANewFileName;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.Files,
    procedure
    begin
      mOwner.Renamed(mProject, mOldName, mNewName);
    end);
end;

procedure TAtlasIdeUnitRename.TProjectNotifier.Destroyed;
var
  mOwner: TAtlasIdeUnitRename;
begin
  mOwner := FOwner;
  if mOwner <> nil then
  begin
    mOwner.Forget(Self);
  end;
  // Zuletzt: Mit dem Abmelden kann die IDE die letzte Referenz freigeben.
  Detach;
end;

procedure TAtlasIdeUnitRename.TProjectNotifier.Detach;
var
  mProject: IOTAProject;
  mIndex: Integer;
begin
  mProject := FProject;
  mIndex := FIndex;
  FProject := nil;
  FOwner := nil;
  FIndex := -1;
  // Danach keine Felder mehr: RemoveNotifier kann dieses Objekt freigeben.
  if (mProject <> nil) and (mIndex >= 0) then
  begin
    mProject.RemoveNotifier(mIndex);
  end;
end;

{ TAtlasIdeUnitRename.TIdeNotifier }

procedure TAtlasIdeUnitRename.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
var
  mOwner: TAtlasIdeUnitRename;
  mName: string;
begin
  mOwner := FOwner;
  if (mOwner = nil) or not ((NotifyCode = ofnFileOpened) or (NotifyCode = ofnFileClosing)) or
    not IsProjectFile(FileName) then
  begin
    Exit;
  end;
  mName := FileName;
  if NotifyCode = ofnFileOpened then
  begin
    TAtlasGuard.Run(TAtlasFeature.Files,
      procedure
      begin
        mOwner.Sweep;
      end);
  end
  else
  begin
    TAtlasGuard.Run(TAtlasFeature.Files,
      procedure
      begin
        mOwner.Closing(mName);
      end);
  end;
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
  mServices: IOTAServices;
begin
  inherited Create;
  FSessionOf := ASessionOf;
  FReport := AReport;
  FQueue := TAtlasUnitRenameQueue.Create;
  FProjects := TList<TProjectNotifier>.Create;
  FNotifierIndex := -1;
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    FNotifier := TIdeNotifier.Create;
    FNotifier.FOwner := Self;
    FNotifierRef := FNotifier;
    FNotifierIndex := mServices.AddNotifier(FNotifierRef);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cRenameDelayMs;
  FTimer.OnTimer := Tick;
  FInstance := Self;
  // Schon geladene Projekte (die IDE lädt das letzte Projekt oft vor dem Plugin).
  Sweep;
end;

destructor TAtlasIdeUnitRename.Destroy;
var
  mServices: IOTAServices;
  mNotifier: TProjectNotifier;
begin
  if FInstance = Self then
  begin
    FInstance := nil;
  end;
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
    FTimer.Free;
  end;
  FNotice.Free;
  // Erst abmelden, dann freigeben (#493).
  if FNotifier <> nil then
  begin
    FNotifier.FOwner := nil;
  end;
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    mServices.RemoveNotifier(FNotifierIndex);
  end;
  FNotifierRef := nil;
  for mNotifier in FProjects.ToArray do
  begin
    mNotifier.Detach;
  end;
  FProjects.Free;
  FQueue.Free;
  inherited;
end;

procedure TAtlasIdeUnitRename.Sweep;
var
  mModules: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mGroup := mModules.MainProjectGroup;
  if mGroup = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    Attach(mGroup.Projects[mIndex]);
  end;
end;

procedure TAtlasIdeUnitRename.Attach(const AProject: IOTAProject);
var
  mNotifier: TProjectNotifier;
  mReference: IOTAProjectNotifier;
begin
  if AProject = nil then
  begin
    Exit;
  end;
  for mNotifier in FProjects do
  begin
    if mNotifier.FProject = AProject then
    begin
      Exit;
    end;
  end;
  mNotifier := TProjectNotifier.Create;
  mNotifier.FOwner := Self;
  mNotifier.FProject := AProject;
  mReference := mNotifier;
  // Die IDE hält die Referenz; Detach gibt sie frei.
  mNotifier.FIndex := AProject.AddNotifier(mReference);
  FProjects.Add(mNotifier);
end;

procedure TAtlasIdeUnitRename.Closing(const AFileName: string);
var
  mNotifier: TProjectNotifier;
begin
  for mNotifier in FProjects.ToArray do
  begin
    if (mNotifier.FProject <> nil) and (SameText(mNotifier.FProject.FileName, AFileName) or
      SameText(ChangeFileExt(mNotifier.FProject.FileName, ExtractFileExt(AFileName)), AFileName)) then
    begin
      FProjects.Remove(mNotifier);
      mNotifier.Detach;
    end;
  end;
end;

procedure TAtlasIdeUnitRename.Forget(ANotifier: TProjectNotifier);
begin
  FProjects.Remove(ANotifier);
end;

procedure TAtlasIdeUnitRename.Renamed(const AProject: IOTAProject; const AOldFileName, ANewFileName: string);
begin
  if not FQueue.Add(TAtlasUnitRenameEvent.Create(AOldFileName, ANewFileName, AProject.FileName)) then
  begin
    Exit;
  end;
  // Anonym: keine Datei- oder Unit-Namen (#647).
  TAtlasGuard.Log('Unit umbenannt (#512)');
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeUnitRename.Tick(Sender: TObject);
var
  mEvent: TAtlasUnitRenameEvent;
begin
  FTimer.Enabled := False;
  try
    for mEvent in FQueue.Take do
    begin
      Offer(mEvent);
    end;
  except
    // Keine Exception an die IDE (#493).
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Files, E);
  end;
end;

procedure TAtlasIdeUnitRename.Say(const AText: string);
begin
  if Assigned(FReport) then
  begin
    FReport(AText);
  end;
end;

class function TAtlasIdeUnitRename.RunAction(const AEvent: TAtlasUnitRenameEvent;
  AScope: TAtlasUnitRenameScope): TProc;
var
  mEvent: TAtlasUnitRenameEvent;
begin
  // Eigene Funktion: Jede Aktion fängt ihren Bereich als Wert ein, nicht die Schleifenvariable.
  mEvent := AEvent;
  Result :=
    procedure
    begin
      if FInstance <> nil then
      begin
        FInstance.Run(mEvent, AScope);
      end;
    end;
end;

class function TAtlasIdeUnitRename.FilesOf(const AProject: IOTAProject): TArray<string>;
var
  mMains: array[0..1] of string;
  mMain: string;
  mIndex: Integer;
  mInfo: IOTAModuleInfo;
begin
  Result := nil;
  if AProject = nil then
  begin
    Exit;
  end;
  mMains[0] := ChangeFileExt(AProject.FileName, '.dpr');
  mMains[1] := ChangeFileExt(AProject.FileName, '.dpk');
  for mMain in mMains do
  begin
    if FileExists(mMain) then
    begin
      Result := Result + [mMain];
    end;
  end;
  for mIndex := 0 to AProject.GetModuleCount - 1 do
  begin
    mInfo := AProject.GetModule(mIndex);
    if (mInfo <> nil) and (mInfo.FileName <> '') then
    begin
      Result := Result + [mInfo.FileName];
    end;
  end;
  Result := TAtlasUnitRename.SourceFiles(Result);
end;

class function TAtlasIdeUnitRename.ScopeFiles(const AProjectFile: string;
  AScope: TAtlasUnitRenameScope): TArray<string>;
var
  mModules: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mProject: IOTAProject;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  if AScope = TAtlasUnitRenameScope.Group then
  begin
    mGroup := mModules.MainProjectGroup;
    if mGroup <> nil then
    begin
      for mIndex := 0 to mGroup.ProjectCount - 1 do
      begin
        Result := Result + FilesOf(mGroup.Projects[mIndex]);
      end;
    end;
    Result := TAtlasUnitRename.SourceFiles(Result);
  end;
  // Ohne Gruppe (oder Projekt außerhalb) zählt das Projekt.
  if (AScope = TAtlasUnitRenameScope.Project) or (Result = nil) then
  begin
    if Supports(mModules.FindModule(AProjectFile), IOTAProject, mProject) then
    begin
      Result := TAtlasUnitRename.SourceFiles(Result + FilesOf(mProject));
    end;
  end;
end;

/// <summary>Beschriftung des Knopfs für AScope.</summary>
function ScopeCaption(AScope: TAtlasUnitRenameScope): string;
begin
  if AScope = TAtlasUnitRenameScope.Group then
  begin
    Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.UnitRenameGroup);
  end
  else
  begin
    Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.UnitRenameProject);
  end;
end;

/// <summary>Angebotene Bereiche: Projekt, wenn dort Units betroffen sind; Gruppe, wenn sie mehr betrifft.</summary>
function OfferScopes(AInProject, AInGroup: Integer): TArray<TAtlasUnitRenameScope>;
begin
  Result := nil;
  if AInProject > 0 then
  begin
    Result := Result + [TAtlasUnitRenameScope.Project];
  end;
  if AInGroup > AInProject then
  begin
    Result := Result + [TAtlasUnitRenameScope.Group];
  end;
end;

/// <summary>Überschrift des Hinweises: Zahl im Projekt, ohne Treffer dort die der Gruppe.</summary>
function OfferTitle(const AAnswer: TAtlasUnitRenameAnswer; AInProject, AInGroup: Integer): string;
var
  mShown: Integer;
begin
  mShown := AInProject;
  if mShown = 0 then
  begin
    mShown := AInGroup;
  end;
  if mShown = 1 then
  begin
    Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.UnitRenameNoticeOne, [AAnswer.OldName]);
  end
  else
  begin
    Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.UnitRenameNotice, [mShown, AAnswer.OldName]);
  end;
end;

function TAtlasIdeUnitRename.CurrentSession: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
  begin
    Result := FSessionOf();
  end;
end;

function TAtlasIdeUnitRename.Reporter: TProc<string>;
begin
  Result :=
    procedure(AText: string)
    begin
      Say(AText);
    end;
end;

function TAtlasIdeUnitRename.FetchAnswer(ASession: TLspSession; const AEvent: TAtlasUnitRenameEvent;
  const AFiles: TArray<string>; out AAnswer: TAtlasUnitRenameAnswer): Boolean;
var
  mReply: TJSONValue;
begin
  Result := False;
  AAnswer := Default(TAtlasUnitRenameAnswer);
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  try
    mReply := ASession.RunCommand(TAtlasUnitRename.cCommand,
      TAtlasUnitRename.Arguments(AEvent.OldFile, AEvent.NewFile, AFiles), cTimeoutMs);
    try
      AAnswer := TAtlasUnitRename.ReadAnswer(mReply);
    finally
      mReply.Free;
    end;
    Result := True;
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.UnitRenameFailed, [E.Message]));
    end;
  end;
end;

procedure TAtlasIdeUnitRename.Offer(const AEvent: TAtlasUnitRenameEvent);
var
  mSession: TLspSession;
  mGroup, mProject: TArray<string>;
  mAnswer: TAtlasUnitRenameAnswer;
  mInProject, mInGroup: Integer;
  mTitle, mText: string;
  mScopes: TArray<TAtlasUnitRenameScope>;
  mScope: TAtlasUnitRenameScope;
  mActions: TArray<TAtlasNotificationAction>;
  mAction: TAtlasNotificationAction;
begin
  mSession := CurrentSession;
  if mSession = nil then
  begin
    Exit;
  end;
  mGroup := ScopeFiles(AEvent.ProjectFile, TAtlasUnitRenameScope.Group);
  mProject := ScopeFiles(AEvent.ProjectFile, TAtlasUnitRenameScope.Project);
  // refactoring.unitRenameFollowUp = off: wie ohne die Funktion.
  if not FetchAnswer(mSession, AEvent, mGroup, mAnswer) or not mAnswer.Enabled or (Length(mAnswer.Files) = 0) then
  begin
    Exit;
  end;
  mInProject := TAtlasUnitRename.CountIn(mAnswer, mProject);
  mInGroup := TAtlasUnitRename.CountIn(mAnswer, mGroup);
  mTitle := OfferTitle(mAnswer, mInProject, mInGroup);
  mText := '';
  if mInGroup > mInProject then
  begin
    mText := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.UnitRenameGroupCount, [mInGroup]);
  end;
  mScopes := OfferScopes(mInProject, mInGroup);
  mActions := nil;
  for mScope in mScopes do
  begin
    mAction.Caption := ScopeCaption(mScope);
    mAction.Run := RunAction(AEvent, mScope);
    mActions := mActions + [mAction];
  end;
  if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cUnitRename, TAtlasNotificationSeverity.Info,
    mTitle, mText, mActions) = TAtlasNotificationMode.Show then
  begin
    Say(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.UnitRenameReport, [mAnswer.OldName, mAnswer.NewName, mInProject,
      mInGroup]));
    ShowNotice(AEvent, mTitle, mText, mScopes);
  end;
end;

procedure TAtlasIdeUnitRename.ShowNotice(const AEvent: TAtlasUnitRenameEvent; const ATitle, AText: string;
  const AScopes: TArray<TAtlasUnitRenameScope>);
var
  mEvent: TAtlasUnitRenameEvent;
  mScopes: TArray<TAtlasUnitRenameScope>;
  mCaptions: TArray<string>;
  mScope: TAtlasUnitRenameScope;
  mArea: TRect;
begin
  mEvent := AEvent;
  mScopes := AScopes;
  mCaptions := nil;
  for mScope in AScopes do
  begin
    mCaptions := mCaptions + [ScopeCaption(mScope)];
  end;
  if FNotice = nil then
  begin
    FNotice := TAtlasNoticeWindow.Create(nil);
  end;
  FNotice.OnAction :=
    procedure(AIndex: Integer)
    begin
      if (AIndex >= 0) and (AIndex <= High(mScopes)) then
      begin
        Run(mEvent, mScopes[AIndex]);
      end;
    end;
  mArea := Screen.WorkAreaRect;
  if Application.MainForm <> nil then
  begin
    mArea := Application.MainForm.BoundsRect;
  end;
  FNotice.Colors := TAtlasIdeStyle.Colors;
  FNotice.SetScaling(TAtlasPopupWindow.MonitorPPI(mArea.BottomRight), 1, '', 10);
  FNotice.ShowNotice(ATitle, AText, mCaptions, mArea);
end;

procedure TAtlasIdeUnitRename.Run(const AEvent: TAtlasUnitRenameEvent; AScope: TAtlasUnitRenameScope);
var
  mSession: TLspSession;
  mAnswer: TAtlasUnitRenameAnswer;
  mReply: TAtlasServerEditReply;
  mHint: string;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  if FNotice <> nil then
  begin
    FNotice.Dismiss;
  end;
  mSession := CurrentSession;
  if mSession = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  // Neu holen: Seit dem Hinweis kann sich der Text geändert haben.
  mAnswer := Default(TAtlasUnitRenameAnswer);
  if not TAtlasIdeServerEdit.Fetch(mSession, TAtlasServerEditCommand.Create(TAtlasUnitRename.cCommand,
    TAtlasUnitRename.Arguments(AEvent.OldFile, AEvent.NewFile, ScopeFiles(AEvent.ProjectFile, AScope)), cTimeoutMs,
    TAtlasTextId.UnitRenameFailed),
    procedure(const AReply: TJSONObject)
    begin
      mAnswer := TAtlasUnitRename.ReadAnswer(AReply);
    end, Reporter(), mReply) or not mAnswer.Enabled then
  begin
    Exit;
  end;
  if mReply.Edit.IsEmpty then
  begin
    Say(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.UnitRenameNothing, [mAnswer.OldName]));
    Exit;
  end;
  mHint := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.UnitRenamePreviewHint, [mAnswer.OldName, mAnswer.NewName,
    mReply.Edit.EditCount, Length(mReply.Edit.Files)]);
  // Ablehnen ändert nichts.
  if TAtlasIdeServerEdit.Confirm(TAtlasStrings.Text(TAtlasTextId.UnitRenameTitle), mHint,
    TAtlasEditorStrings.Text(TAtlasEditorTextId.UnitRenameApply),
    mReply.Edit) and TAtlasIdeServerEdit.Apply(mReply.Edit,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
    TAtlasStrings.Text(TAtlasTextId.UnitRenameTitle), Reporter(), mOutcome) then
  begin
    Say(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.UnitRenameDone, [mAnswer.OldName, mAnswer.NewName, mOutcome.Edits,
      mOutcome.Files]));
    if mOutcome.Written > 0 then
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [mOutcome.Written]));
    end;
  end;
end;

end.
