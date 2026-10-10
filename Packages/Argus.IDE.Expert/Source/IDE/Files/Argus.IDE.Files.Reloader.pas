unit Argus.IDE.Files.Reloader;

// Extern geänderte Dateien ohne Rückfrage neu laden (#536).
// Ein Timer (500 ms, läuft auch, wenn die IDE im Hintergrund ist) meldet die
// offenen Quelltexte an TArgusExternalChanges. Ist ein Vorgang fertig, lädt
// Argus Dateien ohne ungespeicherte Änderungen über IOTAModule.Refresh neu,
// bevor die IDE beim Zurückwechseln selbst vergleicht; Cursor und sichtbarer
// Bereich bleiben. Puffer mit eigenen Änderungen fasst Argus nie an: Für sie
// bleibt die Rückfrage der IDE („In-memory changes … will be overwritten“).
// Gelöschte Dateien meldet Argus nur. Hat sich nur der Zeitstempel geändert
// (z. B. eigenes Speichern), bleibt der Puffer unberührt.
// Ergebnis im Meldungsfenster, Gruppe „Argus“.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  ToolsAPI,
  Argus.Core.Files.ExternalChanges;

type
  TArgusFileReloader = class
  private
    FTimer: TTimer;
    FChanges: TArgusExternalChanges;
    FBusy: Boolean;
    FReport: TProc<string>;
    procedure Tick(Sender: TObject);
    function OpenFiles: TArray<TArgusObservedFile>;
    procedure Process(const ADecisions: TArray<TArgusReloadDecision>);
    function Reload(const AFileName: string): Boolean;
    class function SourceEditorOf(const AModule: IOTAModule): IOTASourceEditor; static;
    class function FindModule(const AFileName: string): IOTAModule; static;
    class function DiskStamp(const AFileName: string; out AStamp: Int64): Boolean; static;
    class function SameAsDisk(const AEditor: IOTASourceEditor; const AFileName: string): Boolean; static;
    class procedure AddMessage(const AText: string); static;
  public
    /// <summary>AReport erhält je Vorgang eine Zeile fürs Protokoll (was neu geladen bzw. behalten wurde).</summary>
    constructor Create(const AReport: TProc<string>);
    destructor Destroy; override;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  Argus.UI.Strings,
  Argus.IDE.Settings.Store,
  Argus.IDE.Editor.Buffer,
  Argus.Core.Diagnostics.Hangs;

function NowMs: Int64;
begin
  Result := GetTickCount64;
end;

{ TArgusFileReloader }

constructor TArgusFileReloader.Create(const AReport: TProc<string>);
begin
  inherited Create;
  FReport := AReport;
  FChanges := TArgusExternalChanges.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 500;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TArgusFileReloader.Destroy;
begin
  FTimer.Enabled := False;
  FTimer.Free;
  FChanges.Free;
  inherited;
end;

class function TArgusFileReloader.DiskStamp(const AFileName: string; out AStamp: Int64): Boolean;
var
  Data: TWin32FileAttributeData;
begin
  AStamp := 0;
  Result := GetFileAttributesEx(PChar(AFileName), GetFileExInfoStandard, @Data);
  if Result then
    AStamp := Int64(Data.ftLastWriteTime.dwHighDateTime) shl 32 or Data.ftLastWriteTime.dwLowDateTime;
end;

class function TArgusFileReloader.SourceEditorOf(const AModule: IOTAModule): IOTASourceEditor;
var
  Index: Integer;
  Editor: IOTAEditor;
begin
  Result := nil;
  for Index := 0 to AModule.ModuleFileCount - 1 do
  begin
    Editor := AModule.ModuleFileEditors[Index];
    if Supports(Editor, IOTASourceEditor, Result) and SameText(Editor.FileName, AModule.FileName) then
      Exit;
    Result := nil;
  end;
end;

class function TArgusFileReloader.FindModule(const AFileName: string): IOTAModule;
var
  Services: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Result := Services.FindModule(AFileName);
end;

function TArgusFileReloader.OpenFiles: TArray<TArgusObservedFile>;
var
  Services: IOTAModuleServices;
  Index: Integer;
  Module: IOTAModule;
  Editor: IOTASourceEditor;
  Stamp: Int64;
  Exists: Boolean;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  for Index := 0 to Services.ModuleCount - 1 do
  begin
    Module := Services.Modules[Index];
    // Nur Quelltexte im Editor; Projekte und Gruppen verwaltet die IDE selbst.
    Editor := SourceEditorOf(Module);
    if Editor = nil then
      Continue;
    Exists := DiskStamp(Module.FileName, Stamp);
    Result := Result + [TArgusObservedFile.Create(Module.FileName, Exists, Stamp, Editor.Modified)];
  end;
end;

procedure TArgusFileReloader.Tick(Sender: TObject);
begin
  if FBusy or not TArgusIdeSettings.Current.ReloadExternal then
    Exit;
  FBusy := True;
  try
    try
      FChanges.Observe(OpenFiles, NowMs);
      if FChanges.Due(NowMs) then
        Process(FChanges.TakeBatch);
    except
      // Keine Exception an die IDE (#493); im nächsten Takt neu versuchen.
    end;
  finally
    FBusy := False;
  end;
end;

class function TArgusFileReloader.SameAsDisk(const AEditor: IOTASourceEditor; const AFileName: string): Boolean;
var
  Buffer: IOTAEditBuffer;
  Current, Disk: string;
begin
  Result := False;
  if not Supports(AEditor, IOTAEditBuffer, Buffer) then
    Exit;
  Current := TArgusEditorBuffer.Text(Buffer).Replace(#13, '');
  try
    Disk := TFile.ReadAllText(AFileName).Replace(#13, '');
  except
    Exit;
  end;
  Result := Current = Disk;
end;

function TArgusFileReloader.Reload(const AFileName: string): Boolean;
type
  TViewState = record
    Cursor: TOTAEditPos;
    TopRow: Integer;
    LeftColumn: Integer;
  end;
var
  Module: IOTAModule;
  Editor: IOTASourceEditor;
  States: TArray<TViewState>;
  View: IOTAEditView;
  Index: Integer;
begin
  Result := False;
  Module := FindModule(AFileName);
  if Module = nil then
    Exit;
  Editor := SourceEditorOf(Module);
  if (Editor = nil) or Editor.Modified then
    Exit;
  // Nur der Zeitstempel (z. B. Touch, eigenes Speichern): nichts neu laden, Rückgängig bleibt.
  if SameAsDisk(Editor, AFileName) then
    Exit;
  SetLength(States, Editor.EditViewCount);
  for Index := 0 to High(States) do
  begin
    View := Editor.EditViews[Index];
    States[Index].Cursor := View.CursorPos;
    States[Index].TopRow := View.TopRow;
    States[Index].LeftColumn := View.LeftColumn;
  end;
  Module.Refresh(True);
  Editor := SourceEditorOf(Module);
  if Editor <> nil then
    for Index := 0 to Editor.EditViewCount - 1 do
      if Index <= High(States) then
      begin
        View := Editor.EditViews[Index];
        View.SetTopLeft(States[Index].TopRow, States[Index].LeftColumn);
        View.CursorPos := States[Index].Cursor;
        View.Paint;
      end;
  Result := True;
end;

class procedure TArgusFileReloader.AddMessage(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Group := Messages.GetGroup('Argus');
  if Group = nil then
    Group := Messages.AddMessageGroup('Argus');
  Messages.AddTitleMessage(AText, Group);
end;

procedure TArgusFileReloader.Process(const ADecisions: TArray<TArgusReloadDecision>);
var
  Decision: TArgusReloadDecision;
  Reloaded: TArray<string>;
  Name: string;
  Activity: IInterface;
begin
  Activity := TArgusActivity.Scope('Dateien neu laden');
  Reloaded := nil;
  if Assigned(FReport) then
    for Decision in ADecisions do
      FReport(Format('Extern geändert: %s (%s)', [Decision.FileName,
        TArgusExternalChanges.ActionText(Decision.Action)]));
  for Decision in ADecisions do
    case Decision.Action of
      TArgusReloadAction.Reload:
        if Reload(Decision.FileName) then
          Reloaded := Reloaded + [Decision.FileName];
      TArgusReloadAction.KeepModified:
        AddMessage(TArgusStrings.Fmt(TArgusTextId.ReloadKeptModified, [ExtractFileName(Decision.FileName)]));
      TArgusReloadAction.Deleted:
        AddMessage(TArgusStrings.Fmt(TArgusTextId.ReloadDeleted, [ExtractFileName(Decision.FileName)]));
    end;
  if Length(Reloaded) = 0 then
    Exit;
  AddMessage(TArgusStrings.Fmt(TArgusTextId.ReloadDone, [Length(Reloaded)]));
  for Name in Reloaded do
    AddMessage('    ' + Name);
end;

end.