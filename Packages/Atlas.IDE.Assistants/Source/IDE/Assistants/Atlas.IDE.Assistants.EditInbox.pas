unit Atlas.IDE.Assistants.EditInbox;

// Eingang für schreibende MCP-Werkzeuge (#397, Protokoll in
// Atlas.Core.Assistants.EditInbox): Alle 100 ms übernimmt das Plugin wartende
// Aufträge, ändert den Puffer der offenen Datei als einen Rückgängig-Schritt
// (nur der geänderte Bereich) und speichert sie, wenn sie vorher gespeichert
// war. So erscheint die Änderung sofort im Editor, und die Platte stimmt für
// den MCP-Server wieder. Ob angewendet, abgelehnt oder vom MCP-Server selbst
// geschrieben wird, und den ganzen Ablauf eines Auftrags führt
// Atlas.Core.Assistants.EditPlan.Run aus (getestet); diese Unit stellt nur den
// Zeitgeber, das Anwenden im Editor und die Antwort.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Files.Contract;

type
  TAtlasEditInboxProc = reference to procedure(const AMessage: string);

  TAtlasIdeEditInbox = class
  private
    FFolder: string;
    FTimer: TTimer;
    FOnMessage: TAtlasEditInboxProc;
    FFiles: IAtlasEditorFiles;
    procedure Tick(Sender: TObject);
    procedure Process(const ARequestFile: string);
    procedure Clean;
  public
    /// <summary>AFiles: offene Dateien der IDE; AOnMessage: Zeile für die Meldungsansicht (geänderte
    /// Datei).</summary>
    constructor Create(const AFiles: IAtlasEditorFiles; const AOnMessage: TAtlasEditInboxProc);
    destructor Destroy; override;
    property Folder: string read FFolder;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.UI.Assistants.Strings,
  Atlas.Core.Assistants.EditInbox,
  Atlas.Core.Assistants.EditPlan,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.Core.Editor.WorkspacePlan;

constructor TAtlasIdeEditInbox.Create(const AFiles: IAtlasEditorFiles; const AOnMessage: TAtlasEditInboxProc);
begin
  inherited Create;
  FFiles := AFiles;
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

function ApplyInEditor(const AEdit: TLspWorkspaceEdit): string;
begin
  Result := TAtlasIdeWorkspaceEdit.Apply(AEdit, TAtlasUnopenedPolicy.WriteToDisk,
    TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.UndoActionMcp)).Error;
end;

procedure TAtlasIdeEditInbox.Process(const ARequestFile: string);
var
  mRequest: TAtlasEditRequest;
  mOutcome: TAtlasEditInboxOutcome;
begin
  if not TAtlasEditInbox.Take(ARequestFile, mRequest) then
  begin
    Exit;
  end;
  mOutcome := TAtlasEditInboxPlan.Run(FFiles, mRequest.FileName, mRequest.Expected, mRequest.Text,
    ApplyInEditor);
  TAtlasEditInbox.Answer(FFolder, mRequest, mOutcome.Applied, mOutcome.ServerWrites, mOutcome.Reason);
  if mOutcome.Applied and Assigned(FOnMessage) then
  begin
    FOnMessage(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.McpEditApplied, [ExtractFileName(mRequest.FileName)]));
  end;
end;

end.
