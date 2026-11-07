unit Atlas.IDE.Files.EditInbox;

// Eingang für schreibende MCP-Werkzeuge (#397, Protokoll in
// Atlas.Core.Files.EditInbox): Alle 100 ms übernimmt das Plugin wartende
// Aufträge, ändert den Puffer der offenen Datei als einen Rückgängig-Schritt
// (nur der geänderte Bereich, TLspTextChanges) und speichert sie, wenn sie
// vorher ungespeichert unverändert war. So erscheint die Änderung sofort im
// Editor, und die Platte stimmt für den MCP-Server wieder. Abgelehnt wird,
// wenn der Puffer inzwischen ungespeichert geändert ist; ist die Datei nicht
// mehr offen oder weicht der Puffer sonst von der Platte ab, schreibt der
// MCP-Server selbst.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls;

type
  TAtlasEditInboxProc = reference to procedure(const AMessage: string);

  TAtlasIdeEditInbox = class
  private
    FFolder: string;
    FTimer: TTimer;
    FOnMessage: TAtlasEditInboxProc;
    procedure Tick(Sender: TObject);
    procedure Process(const ARequestFile: string);
    procedure Clean;
  public
    /// <summary>AOnMessage: Zeile für die Meldungsansicht (geänderte Datei, Ablehnung).</summary>
    constructor Create(const AOnMessage: TAtlasEditInboxProc);
    destructor Destroy; override;
    property Folder: string read FFolder;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.Core.Files.EditInbox,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Files,
  Atlas.Core.Editor.WorkspacePlan;

constructor TAtlasIdeEditInbox.Create(const AOnMessage: TAtlasEditInboxProc);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FFolder := TAtlasEditInbox.Folder(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    GetCurrentProcessId);
  Clean;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 100;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeEditInbox.Destroy;
begin
  FTimer.Free;
  Clean;
  inherited Destroy;
end;

procedure TAtlasIdeEditInbox.Clean;
begin
  // Reste eines früheren Prozesses mit derselben Nummer oder dieses Laufs.
  try
    if TDirectory.Exists(FFolder) then
    begin
      TDirectory.Delete(FFolder, True);
    end;
  except
    on Exception do
      ;
  end;
end;

procedure TAtlasIdeEditInbox.Tick(Sender: TObject);
var
  mRequestFile: string;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Files) then
  begin
    Exit;
  end;
  try
    for mRequestFile in TAtlasEditInbox.Pending(FFolder) do
    begin
      Process(mRequestFile);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Files, E);
  end;
end;

function ModuleOf(const AFileName: string): IOTAModule;
var
  mModules: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Result := mModules.FindModule(AFileName);
  end;
end;

/// <summary>Änderung der Anfrage als kleinste Textänderung an einer Datei.</summary>
function EditOf(const ARequest: TAtlasEditRequest): TLspWorkspaceEdit;
var
  mChange: TLspTextChange;
  mTextEdit: TLspTextEdit;
begin
  mChange := TLspTextChanges.Between(ARequest.Expected, ARequest.Text);
  mTextEdit.StartPos := mChange.StartPos;
  mTextEdit.EndPos := mChange.EndPos;
  mTextEdit.NewText := mChange.Text;
  Result := Default(TLspWorkspaceEdit);
  Result.Files := [Default(TLspFileEdits)];
  Result.Files[0].FileName := ARequest.FileName;
  Result.Files[0].Edits := [mTextEdit];
end;

procedure SaveModule(const AFileName: string);
var
  mModule: IOTAModule;
begin
  mModule := ModuleOf(AFileName);
  if mModule <> nil then
  begin
    mModule.Save(False, True);
  end;
end;

procedure TAtlasIdeEditInbox.Process(const ARequestFile: string);
var
  mRequest: TAtlasEditRequest;
  mBuffer: IOTAEditBuffer;
  mOutcome: TAtlasWorkspaceEditResult;
  mWasModified: Boolean;
begin
  if not TAtlasEditInbox.Take(ARequestFile, mRequest) then
  begin
    Exit;
  end;
  mBuffer := TAtlasIdeFiles.BufferOf(mRequest.FileName);
  if mBuffer = nil then
  begin
    TAtlasEditInbox.Answer(FFolder, mRequest, False, True, 'nicht offen');
    Exit;
  end;
  // Puffer weicht vom gelesenen Stand ab: Ungespeichert geändert lehnt der MCP-Server vorher ab; sonst
  // (z. B. andere Zeilenenden) schreibt er selbst, und das Neuladen der IDE (#536) holt die Datei.
  if TAtlasEditorBuffer.Text(mBuffer) <> mRequest.Expected then
  begin
    if mBuffer.IsModified then
    begin
      TAtlasEditInbox.Answer(FFolder, mRequest, False, False, 'im Editor ungespeichert geändert');
    end
    else
    begin
      TAtlasEditInbox.Answer(FFolder, mRequest, False, True, 'Puffer weicht von der Platte ab');
    end;
    Exit;
  end;
  mWasModified := mBuffer.IsModified;
  mOutcome := TAtlasIdeWorkspaceEdit.Apply(EditOf(mRequest), TAtlasUnopenedPolicy.WriteToDisk,
    TAtlasStrings.Text(TAtlasTextId.UndoActionMcp));
  if mOutcome.Error <> '' then
  begin
    TAtlasEditInbox.Answer(FFolder, mRequest, False, False, mOutcome.Error);
    Exit;
  end;
  // War die Datei gespeichert, bleibt sie es: Der MCP-Server liest und vergleicht über die Platte.
  if not mWasModified then
  begin
    SaveModule(mRequest.FileName);
  end;
  TAtlasEditInbox.Answer(FFolder, mRequest, True, False, '');
  if Assigned(FOnMessage) then
  begin
    FOnMessage(TAtlasStrings.Fmt(TAtlasTextId.McpEditApplied, [ExtractFileName(mRequest.FileName)]));
  end;
end;

end.
