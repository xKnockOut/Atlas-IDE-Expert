unit Atlas.IDE.Assistants.EditInbox;

// Eingang für schreibende MCP-Werkzeuge (#397, Protokoll in
// Atlas.Core.Assistants.EditInbox): Das Plugin übernimmt wartende Aufträge,
// sobald der Ordner sich ändert (Signal alle 100 ms abgefragt, aufgelistet nur
// nach einem Signal oder alle zwei Sekunden, #1984), ändert den Puffer der
// offenen Datei als einen Rückgängig-Schritt (nur der geänderte Bereich) und
// speichert sie, wenn sie vorher gespeichert war. So erscheint die Änderung
// sofort im Editor, und die Platte stimmt für den MCP-Server wieder. Ob
// angewendet, abgelehnt oder vom MCP-Server selbst geschrieben wird,
// entscheidet Atlas.Core.Assistants.EditPlan (getestet); diese Unit liest nur
// den Puffer und führt die Entscheidung aus.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Assistants.InboxPace,
  Atlas.IDE.Assistants.FolderSignal;

type
  TAtlasEditInboxProc = reference to procedure(const AMessage: string);

  TAtlasIdeEditInbox = class
  private
    FFolder: string;
    FTimer: TTimer;
    FSignal: TAtlasFolderSignal;
    FPace: TAtlasInboxPace;
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
  Atlas.UI.Assistants.Strings,
  Atlas.Core.Assistants.EditInbox,
  Atlas.Core.Assistants.EditPlan,
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
  FSignal := TAtlasFolderSignal.Create(FFolder);
  FPace := Default(TAtlasInboxPace);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 100;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeEditInbox.Destroy;
begin
  FTimer.Free;
  // Erst die Beobachtung schließen: Sie hält den Ordner offen.
  FSignal.Free;
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
  if TAtlasGuard.Disabled(TAtlasFeature.Files) or not FPace.Due(FSignal.Changed, GetTickCount64) then
  begin
    Exit;
  end;
  FSignal.Reopen;
  FPace.Listed(GetTickCount64, False);
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
  mState: TAtlasEditInboxBuffer;
  mDecision: TAtlasEditInboxDecision;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  if not TAtlasEditInbox.Take(ARequestFile, mRequest) then
  begin
    Exit;
  end;
  mBuffer := TAtlasIdeFiles.BufferOf(mRequest.FileName);
  if mBuffer = nil then
  begin
    mState := TAtlasEditInboxBuffer.Closed;
  end
  else
  begin
    mState := TAtlasEditInboxBuffer.Opened(TAtlasEditorBuffer.Text(mBuffer), mBuffer.IsModified);
  end;
  mDecision := TAtlasEditInboxPlan.Decide(mState, mRequest.Expected);
  if not mDecision.Applies then
  begin
    TAtlasEditInbox.Answer(FFolder, mRequest, False, mDecision.ServerWrites, mDecision.Reason);
    Exit;
  end;
  mOutcome := TAtlasIdeWorkspaceEdit.Apply(
    TAtlasEditInboxPlan.EditOf(mRequest.FileName, mRequest.Expected, mRequest.Text),
    TAtlasUnopenedPolicy.WriteToDisk, TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.UndoActionMcp));
  if mOutcome.Error <> '' then
  begin
    TAtlasEditInbox.Answer(FFolder, mRequest, False, False, mOutcome.Error);
    Exit;
  end;
  if mDecision.SaveAfter then
  begin
    SaveModule(mRequest.FileName);
  end;
  TAtlasEditInbox.Answer(FFolder, mRequest, True, False, '');
  if Assigned(FOnMessage) then
  begin
    FOnMessage(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.McpEditApplied, [ExtractFileName(mRequest.FileName)]));
  end;
end;

end.
