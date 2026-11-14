unit Atlas.IDE.Foundation.OpenWatch;

// Beobachter „Quelltext-Editor offen“ und „Projekt offen“ für Takte, die nur
// mit Arbeit laufen sollen. Vorher liefen Brotkrumen (150 ms),
// Übersichtsleiste (200 ms), Unit-Beziehungen (250 ms), Statusfeld der Tests
// (500 ms) und andere auch auf der Willkommensseite ohne Projekt und Editor.
// Vorbild: Atlas.IDE.Designer.OpenWatch (offene Formular-Designer).
// - Register meldet einen Zuhörer an; er hört, sobald sich EditorOpen oder
//   ProjectOpen ändert, und liest dann beide neu. Der erste Zuhörer meldet die
//   Notifier an (INTAEditServicesNotifier, IOTAIDENotifier), der letzte ab.
// - Ereignisse (Fenster, Ansicht aktiviert, Datei geöffnet oder geschlossen)
//   zählen sofort neu und noch einmal nach cSettleMs: Beim Schließen meldet die
//   IDE vor dem Abbau, die Ansicht besteht im Ereignis noch.
// - Unregister: Danach erreicht den Zuhörer nichts mehr (auch nicht aus einer
//   laufenden Meldung an andere Zuhörer).
// Über Package-Grenzen gehen nur Methodenreferenzen und Boolean (Regel 6).
// Nur im Hauptthread.

interface

uses
  System.SysUtils;

type
  TAtlasIdeOpenWatch = class
  public const
    /// <summary>Nach einem Ereignis noch einmal zählen (die IDE baut Ansichten erst nach der Meldung ab).</summary>
    cSettleMs = 300;
  public
    /// <summary>AChanged: EditorOpen oder ProjectOpen hat sich geändert. Ergebnis für Unregister.</summary>
    class function Register(const AChanged: TProc): Integer; static;
    class procedure Unregister(AHandle: Integer); static;
    /// <summary>Ist mindestens eine Quelltext-Ansicht offen (nicht Willkommensseite, nicht nur Designer)?</summary>
    class function EditorOpen: Boolean; static;
    /// <summary>Ist mindestens ein Projekt geladen?</summary>
    class function ProjectOpen: Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  ToolsAPI,
  DockForm,
  Atlas.Core.Diagnostics.Guard;

type
  TEditWatch = class(TNotifierObject, INTAEditServicesNotifier)
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

  TFileWatch = class(TNotifierObject, IOTAIDENotifier)
  public
    procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
    procedure AfterCompile(Succeeded: Boolean); overload;
  end;

  TSettleTicker = class
  public
    procedure Tick(Sender: TObject);
  end;

var
  Listeners: TDictionary<Integer, TProc>;
  NextHandle: Integer;
  EditIndex: Integer = -1;
  FileIndex: Integer = -1;
  Settle: TTimer;
  SettleTicker: TSettleTicker;
  EditorState: Boolean;
  ProjectState: Boolean;

function CountEditorOpen: Boolean;
var
  mServices: IOTAModuleServices;
  mModule: IOTAModule;
  mSource: IOTASourceEditor;
  mModuleIndex, mFileIndex: Integer;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  for mModuleIndex := 0 to mServices.ModuleCount - 1 do
  begin
    mModule := mServices.Modules[mModuleIndex];
    for mFileIndex := 0 to mModule.ModuleFileCount - 1 do
    begin
      if Supports(mModule.ModuleFileEditors[mFileIndex], IOTASourceEditor, mSource) and
        (mSource.EditViewCount > 0) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

function CountProjectOpen: Boolean;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  Result := (mGroup <> nil) and (mGroup.ProjectCount > 0);
end;

/// <summary>Neu zählen und bei einer Änderung jeden Zuhörer rufen, der dann noch angemeldet ist.</summary>
procedure Recount;
var
  mEditor, mProject: Boolean;
  mHandles: TArray<Integer>;
  mHandle: Integer;
  mChanged: TProc;
begin
  if Listeners = nil then
  begin
    Exit;
  end;
  try
    mEditor := CountEditorOpen;
    mProject := CountProjectOpen;
  except
    on E: Exception do
    begin
      TAtlasGuard.Log('Offen-Beobachter: Zählen fehlgeschlagen: ' + E.ClassName); // german-ok: Protokollzeile
      Exit;
    end;
  end;
  if (mEditor = EditorState) and (mProject = ProjectState) then
  begin
    Exit;
  end;
  EditorState := mEditor;
  ProjectState := mProject;
  mHandles := Listeners.Keys.ToArray;
  for mHandle in mHandles do
  begin
    // Ein Zuhörer kann andere (oder sich) abmelden; danach erreicht ihn nichts mehr.
    if (Listeners <> nil) and Listeners.TryGetValue(mHandle, mChanged) then
      try
        mChanged();
      except
        on E: Exception do
          TAtlasGuard.Log('Offen-Beobachter: Zuhörer fehlgeschlagen: ' + E.ClassName); // german-ok: Protokollzeile
      end;
  end;
end;

/// <summary>Sofort zählen und nach cSettleMs noch einmal.</summary>
procedure Changed;
begin
  if Listeners = nil then
  begin
    Exit;
  end;
  Recount;
  if Settle <> nil then
  begin
    Settle.Enabled := False;
    Settle.Enabled := True;
  end;
end;

{ TSettleTicker }

procedure TSettleTicker.Tick(Sender: TObject);
begin
  if Settle <> nil then
  begin
    Settle.Enabled := False;
  end;
  Recount;
end;

{ TEditWatch }

procedure TEditWatch.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
begin
  Changed;
end;

procedure TEditWatch.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
  Changed;
end;

procedure TEditWatch.WindowActivated(const EditWindow: INTAEditWindow);
begin
end;

procedure TEditWatch.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer; var Handled: Boolean);
begin
end;

procedure TEditWatch.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  Changed;
end;

procedure TEditWatch.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
end;

procedure TEditWatch.DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TEditWatch.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TEditWatch.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

{ TFileWatch }

procedure TFileWatch.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
begin
  // Datei, Projekt oder Gruppe geöffnet bzw. geschlossen; Schließen meldet die IDE vorher, daher auch cSettleMs.
  if NotifyCode in [ofnFileOpened, ofnFileClosing, ofnProjectDesktopLoad, ofnActiveProjectChanged] then
  begin
    Changed;
  end;
end;

procedure TFileWatch.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TFileWatch.AfterCompile(Succeeded: Boolean);
begin
end;

{ TAtlasIdeOpenWatch }

class function TAtlasIdeOpenWatch.Register(const AChanged: TProc): Integer;
var
  mEditors: IOTAEditorServices;
  mServices: IOTAServices;
begin
  if Listeners = nil then
  begin
    Listeners := TDictionary<Integer, TProc>.Create;
    SettleTicker := TSettleTicker.Create;
    Settle := TTimer.Create(nil);
    Settle.Enabled := False;
    Settle.Interval := cSettleMs;
    Settle.OnTimer := SettleTicker.Tick;
    EditorState := CountEditorOpen;
    ProjectState := CountProjectOpen;
  end;
  if (EditIndex < 0) and Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    EditIndex := mEditors.AddNotifier(TEditWatch.Create);
  end;
  if (FileIndex < 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    FileIndex := mServices.AddNotifier(TFileWatch.Create);
  end;
  Inc(NextHandle);
  Result := NextHandle;
  Listeners.Add(Result, AChanged);
end;

class procedure TAtlasIdeOpenWatch.Unregister(AHandle: Integer);
var
  mEditors: IOTAEditorServices;
  mServices: IOTAServices;
begin
  if Listeners = nil then
  begin
    Exit;
  end;
  Listeners.Remove(AHandle);
  if Listeners.Count > 0 then
  begin
    Exit;
  end;
  // Letzter Zuhörer: erst die Notifier abmelden, dann freigeben.
  if (EditIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mEditors.RemoveNotifier(EditIndex);
  end;
  EditIndex := -1;
  if (FileIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    mServices.RemoveNotifier(FileIndex);
  end;
  FileIndex := -1;
  FreeAndNil(Settle);
  FreeAndNil(SettleTicker);
  FreeAndNil(Listeners);
end;

class function TAtlasIdeOpenWatch.EditorOpen: Boolean;
begin
  if Listeners = nil then
  begin
    Exit(CountEditorOpen);
  end;
  Result := EditorState;
end;

class function TAtlasIdeOpenWatch.ProjectOpen: Boolean;
begin
  if Listeners = nil then
  begin
    Exit(CountProjectOpen);
  end;
  Result := ProjectState;
end;

end.
