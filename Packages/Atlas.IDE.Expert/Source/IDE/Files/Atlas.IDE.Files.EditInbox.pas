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
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Editor.WorkspaceEdit;

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
      TDirectory.Delete(FFolder, True);
  except
    on Exception do
      ;
  end;
end;

procedure TAtlasIdeEditInbox.Tick(Sender: TObject);
var
  RequestFile: string;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Files) then
    Exit;
  try
    for RequestFile in TAtlasEditInbox.Pending(FFolder) do
      Process(RequestFile);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Files, E);
  end;
end;

function ModuleOf(const AFileName: string): IOTAModule;
var
  Modules: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Result := Modules.FindModule(AFileName);
end;

procedure TAtlasIdeEditInbox.Process(const ARequestFile: string);
var
  Request: TAtlasEditRequest;
  Buffer: IOTAEditBuffer;
  Change: TLspTextChange;
  Edit: TLspWorkspaceEdit;
  TextEdit: TLspTextEdit;
  Outcome: TAtlasWorkspaceEditResult;
  WasModified: Boolean;
  Module: IOTAModule;
begin
  if not TAtlasEditInbox.Take(ARequestFile, Request) then
    Exit;
  Buffer := TAtlasIdeWorkspaceEdit.BufferOf(Request.FileName);
  if Buffer = nil then
  begin
    TAtlasEditInbox.Answer(FFolder, Request, False, True, 'nicht offen');
    Exit;
  end;
  // Puffer weicht vom gelesenen Stand ab: Ungespeichert geändert lehnt der MCP-Server vorher ab; sonst
  // (z. B. andere Zeilenenden) schreibt er selbst, und das Neuladen der IDE (#536) holt die Datei.
  if TAtlasEditorBuffer.Text(Buffer) <> Request.Expected then
  begin
    if Buffer.IsModified then
      TAtlasEditInbox.Answer(FFolder, Request, False, False, 'im Editor ungespeichert geändert')
    else
      TAtlasEditInbox.Answer(FFolder, Request, False, True, 'Puffer weicht von der Platte ab');
    Exit;
  end;
  WasModified := Buffer.IsModified;
  Change := TLspTextChanges.Between(Request.Expected, Request.Text);
  TextEdit.StartPos := Change.StartPos;
  TextEdit.EndPos := Change.EndPos;
  TextEdit.NewText := Change.Text;
  Edit := Default(TLspWorkspaceEdit);
  Edit.Files := [Default(TLspFileEdits)];
  Edit.Files[0].FileName := Request.FileName;
  Edit.Files[0].Edits := [TextEdit];
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, False, TAtlasStrings.Text(TAtlasTextId.UndoActionMcp));
  if Outcome.Error <> '' then
  begin
    TAtlasEditInbox.Answer(FFolder, Request, False, False, Outcome.Error);
    Exit;
  end;
  // War die Datei gespeichert, bleibt sie es: Der MCP-Server liest und vergleicht über die Platte.
  if not WasModified then
  begin
    Module := ModuleOf(Request.FileName);
    if Module <> nil then
      Module.Save(False, True);
  end;
  TAtlasEditInbox.Answer(FFolder, Request, True, False, '');
  if Assigned(FOnMessage) then
    FOnMessage(TAtlasStrings.Fmt(TAtlasTextId.McpEditApplied, [ExtractFileName(Request.FileName)]));
end;

end.
