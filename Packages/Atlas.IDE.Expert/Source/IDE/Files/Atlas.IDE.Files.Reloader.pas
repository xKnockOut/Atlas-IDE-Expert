unit Atlas.IDE.Files.Reloader;

// Extern geänderte Dateien ohne Rückfrage neu laden (#536).
// Ein Timer (500 ms, läuft auch, wenn die IDE im Hintergrund ist) meldet die
// offenen Quelltexte an TAtlasExternalChanges. Ist ein Vorgang fertig, lädt
// Atlas Dateien ohne ungespeicherte Änderungen über IOTAModule.Refresh neu,
// bevor die IDE beim Zurückwechseln selbst vergleicht; Cursor und sichtbarer
// Bereich bleiben. Puffer mit eigenen Änderungen fasst Atlas nie an: Für sie
// bleibt die Rückfrage der IDE (mit „Alle Ja/Alle Nein“; sie lässt sich nicht
// unterdrücken); den Unterschied Editor/Platte schreibt Atlas vorher ins
// Meldungsfenster. Gelöschte Dateien meldet Atlas nur. Hat sich nur der Zeitstempel geändert
// (z. B. eigenes Speichern), bleibt der Puffer unberührt.
// Ergebnis im Meldungsfenster, Gruppe „Atlas“.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Files.ExternalChanges;

type
  TAtlasFileReloader = class
  private
    FTimer: TTimer;
    FChanges: TAtlasExternalChanges;
    FBusy: Boolean;
    FReport: TProc<string>;
    FOnSaved: TProc<string>;
    procedure Tick(Sender: TObject);
    function OpenFiles: TArray<TAtlasObservedFile>;
    procedure Process(const ADecisions: TArray<TAtlasReloadDecision>);
    function Reload(const AFileName: string): Boolean;
    procedure AskModified(const ADecisions: TArray<TAtlasReloadDecision>);
    class function SourceEditorOf(const AModule: IOTAModule): IOTASourceEditor; static;
    class function FindModule(const AFileName: string): IOTAModule; static;
    class function DiskStamp(const AFileName: string; out AStamp: Int64): Boolean; static;
    class function SameAsDisk(const AEditor: IOTASourceEditor; const AFileName: string): Boolean; static;
    class procedure AddMessage(const AText: string); static;
  public
    /// <summary>AReport erhält je Vorgang eine Zeile fürs Protokoll (was neu geladen bzw. behalten wurde).</summary>
    constructor Create(const AReport: TProc<string>);
    destructor Destroy; override;
    /// <summary>Datei wurde gespeichert (neuer Zeitstempel, Inhalt wie im Puffer), z. B. für #548.</summary>
    property OnSaved: TProc<string> read FOnSaved write FOnSaved;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Winapi.Windows,
  System.IOUtils,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Files.TextDiff;

function NowMs: Int64;
begin
  Result := GetTickCount64;
end;

{ TAtlasFileReloader }

constructor TAtlasFileReloader.Create(const AReport: TProc<string>);
begin
  inherited Create;
  FReport := AReport;
  FChanges := TAtlasExternalChanges.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 500;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasFileReloader.Destroy;
begin
  FTimer.Enabled := False;
  FTimer.Free;
  FChanges.Free;
  inherited;
end;

class function TAtlasFileReloader.DiskStamp(const AFileName: string; out AStamp: Int64): Boolean;
var
  Data: TWin32FileAttributeData;
begin
  AStamp := 0;
  Result := GetFileAttributesEx(PChar(AFileName), GetFileExInfoStandard, @Data);
  if Result then
    AStamp := Int64(Data.ftLastWriteTime.dwHighDateTime) shl 32 or Data.ftLastWriteTime.dwLowDateTime;
end;

class function TAtlasFileReloader.SourceEditorOf(const AModule: IOTAModule): IOTASourceEditor;
var
  Index: Integer;
  Editor: IOTAEditor;
  First: IOTASourceEditor;
begin
  Result := nil;
  First := nil;
  for Index := 0 to AModule.ModuleFileCount - 1 do
  begin
    Editor := AModule.ModuleFileEditors[Index];
    if Supports(Editor, IOTASourceEditor, Result) then
    begin
      if SameText(Editor.FileName, AModule.FileName) then
        Exit;
      if First = nil then
        First := Result;
    end;
    Result := nil;
  end;
  // Projekte (.dproj): ihr Quelltext ist die .dpr bzw. .dpk.
  if Supports(AModule, IOTAProject) then
    Result := First;
end;

class function TAtlasFileReloader.FindModule(const AFileName: string): IOTAModule;
var
  Services: IOTAModuleServices;
  Index: Integer;
  Editor: IOTASourceEditor;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  // Über den Quelltexteditor: Die .dpr gehört zum Projektmodul (.dproj).
  for Index := 0 to Services.ModuleCount - 1 do
  begin
    Editor := SourceEditorOf(Services.Modules[Index]);
    if (Editor <> nil) and SameText(Editor.FileName, AFileName) then
      Exit(Services.Modules[Index]);
  end;
end;

function TAtlasFileReloader.OpenFiles: TArray<TAtlasObservedFile>;
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
    Exists := DiskStamp(Editor.FileName, Stamp);
    Result := Result + [TAtlasObservedFile.Create(Editor.FileName, Exists, Stamp, Editor.Modified)];
  end;
end;

procedure TAtlasFileReloader.Tick(Sender: TObject);
begin
  // Beobachtet wird immer (Speichern erkennen, #548); neu geladen nur mit der Einstellung.
  if FBusy then
    Exit;
  FBusy := True;
  try
    try
      FChanges.Observe(OpenFiles, NowMs);
      if FChanges.Due(NowMs) then
        Process(FChanges.TakeBatch);
    except
      // Keine Exception an die IDE (#493); im nächsten Takt neu versuchen.
      on E: Exception do
        TAtlasGuard.Report(TAtlasFeature.Reloader, E);
    end;
  finally
    FBusy := False;
  end;
end;

class function TAtlasFileReloader.SameAsDisk(const AEditor: IOTASourceEditor; const AFileName: string): Boolean;
var
  Buffer: IOTAEditBuffer;
  Current, Disk: string;
begin
  Result := False;
  if not Supports(AEditor, IOTAEditBuffer, Buffer) then
    Exit;
  Current := TAtlasEditorBuffer.Text(Buffer).Replace(#13, '');
  try
    Disk := TFile.ReadAllText(AFileName).Replace(#13, '');
  except
    Exit;
  end;
  Result := Current = Disk;
end;

function TAtlasFileReloader.Reload(const AFileName: string): Boolean;
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
  // Nur der Zeitstempel (eigenes Speichern, Touch): nichts neu laden, Rückgängig bleibt.
  if SameAsDisk(Editor, AFileName) then
  begin
    if Assigned(FOnSaved) then
      FOnSaved(AFileName);
    Exit;
  end;
  if not TAtlasIdeSettings.Current.ReloadExternal then
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
  // Neu geladen ohne Editorereignis: gemeinsamen Pufferstand verwerfen (P-04).
  TAtlasEditorSnapshots.Invalidate(AFileName);
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

procedure TAtlasFileReloader.AskModified(const ADecisions: TArray<TAtlasReloadDecision>);
const
  MaxDiffLines = 40;
var
  Decision: TAtlasReloadDecision;
  Module: IOTAModule;
  Editor: IOTASourceEditor;
  Buffer: IOTAEditBuffer;
  Disk: string;
  Lines: TArray<string>;
  Index: Integer;
begin
  // Die Rückfrage der IDE lässt sich nicht unterdrücken (sie hat „Alle Ja/Alle Nein“); der
  // Unterschied steht vorher im Meldungsfenster, damit man nachsehen kann.
  for Decision in ADecisions do
  begin
    if Decision.Action <> TAtlasReloadAction.KeepModified then
      Continue;
    Module := FindModule(Decision.FileName);
    Editor := nil;
    if Module <> nil then
      Editor := SourceEditorOf(Module);
    if not Supports(Editor, IOTAEditBuffer, Buffer) then
      Continue;
    try
      Disk := TFile.ReadAllText(Decision.FileName);
    except
      on Exception do
        Continue;
    end;
    Lines := TAtlasTextDiff.Lines(TAtlasEditorBuffer.Text(Buffer), Disk);
    if Length(Lines) = 0 then
      Continue;
    AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ReloadDiffTitle, [ExtractFileName(Decision.FileName)]));
    for Index := 0 to High(Lines) do
      if Index < MaxDiffLines then
        AddMessage('    ' + Lines[Index]);
    if Length(Lines) > MaxDiffLines then
      AddMessage('    …');
  end;
end;

class procedure TAtlasFileReloader.AddMessage(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Group := Messages.GetGroup('Atlas');
  if Group = nil then
    Group := Messages.AddMessageGroup('Atlas');
  Messages.AddTitleMessage(AText, Group);
end;

procedure TAtlasFileReloader.Process(const ADecisions: TArray<TAtlasReloadDecision>);
var
  Decision: TAtlasReloadDecision;
  Reloaded: TArray<string>;
  Name: string;
  Activity: IInterface;
begin
  Activity := TAtlasActivity.Scope('Dateien neu laden');
  Reloaded := nil;
  if Assigned(FReport) and TAtlasIdeSettings.Current.ReloadExternal then
    for Decision in ADecisions do
      FReport(Format('Extern geändert: %s (%s)', [Decision.FileName,
        TAtlasExternalChanges.ActionText(Decision.Action)]));
  for Decision in ADecisions do
    case Decision.Action of
      TAtlasReloadAction.Reload:
        if Reload(Decision.FileName) then
          Reloaded := Reloaded + [Decision.FileName];
      TAtlasReloadAction.KeepModified:
        if TAtlasIdeSettings.Current.ReloadExternal then
          AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ReloadKeptModified, [ExtractFileName(Decision.FileName)]));
      TAtlasReloadAction.Deleted:
        if TAtlasIdeSettings.Current.ReloadExternal then
          AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ReloadDeleted, [ExtractFileName(Decision.FileName)]));
    end;
  if Length(Reloaded) > 0 then
  begin
    AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ReloadDone, [Length(Reloaded)]));
    for Name in Reloaded do
      AddMessage('    ' + Name);
  end;
  // Unterschied bei Dateien mit eigenen Änderungen (#536).
  if TAtlasIdeSettings.Current.ReloadExternal then
    AskModified(ADecisions);
end;

end.