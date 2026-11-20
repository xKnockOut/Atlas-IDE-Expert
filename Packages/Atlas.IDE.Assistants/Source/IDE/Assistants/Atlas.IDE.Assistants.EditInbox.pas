unit Atlas.IDE.Assistants.EditInbox;

// Eingang für schreibende MCP-Werkzeuge (#397, Protokoll in
// Atlas.Core.Assistants.EditInbox): Das Plugin übernimmt wartende Aufträge,
// sobald der Ordner sich ändert (Signal alle 100 ms abgefragt, aufgelistet nur
// nach einem Signal oder alle zwei Sekunden, #1984), ändert den Puffer der
// offenen Datei als einen Rückgängig-Schritt (nur der geänderte Bereich) und
// speichert sie, wenn sie vorher gespeichert war. So erscheint die Änderung
// sofort im Editor, und die Platte stimmt für den MCP-Server wieder. Ob
// angewendet, abgelehnt oder vom MCP-Server selbst geschrieben wird, und den
// ganzen Ablauf eines Auftrags führt Atlas.Core.Assistants.EditPlan.Run aus
// (getestet); diese Unit stellt nur Zeitgeber, Anwenden im Editor und Antwort.
// Ist die Datei ungespeichert geändert, bittet der MCP-Server um Zurückhalten und ist
// assistants.editHoldModified an (#2605), wartet die Änderung in TAtlasIdeHeldEdits
// auf den Menschen; die Antwort lautet „held“. Jeder Auftrag landet im KI-Protokoll
// (#2049): angewendet, zurückgehalten oder abgelehnt.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Files.Contract,
  Atlas.Core.Assistants.Activity,
  Atlas.Core.Assistants.InboxPace,
  Atlas.Core.Assistants.Log,
  Atlas.IDE.Assistants.FolderSignal,
  Atlas.IDE.Assistants.HeldEdits;

type
  TAtlasEditInboxProc = reference to procedure(const AMessage: string);

  TAtlasIdeEditInbox = class
  private
    FFolder: string;
    FTimer: TTimer;
    FSignal: TAtlasFolderSignal;
    FPace: TAtlasInboxPace;
    FOnMessage: TAtlasEditInboxProc;
    FFiles: IAtlasEditorFiles;
    FActivity: TAtlasAssistantsActivity;
    FLog: TAtlasAssistantsLog;
    FHeld: TAtlasIdeHeldEdits;
    procedure Tick(Sender: TObject);
    procedure Process(const ARequestFile: string);
    procedure Clean;
  public
    /// <summary>AFiles: offene Dateien der IDE; AActivity: Pause und Anzeige „KI-Assistent aktiv“ (#1906), gehört
    /// der Composition; ALog: KI-Protokoll (#2049), gehört der Composition, darf nil sein; AOnMessage: Zeile für
    /// die Meldungsansicht (geänderte Datei).</summary>
    constructor Create(const AFiles: IAtlasEditorFiles; AActivity: TAtlasAssistantsActivity; ALog: TAtlasAssistantsLog;
      const AOnMessage: TAtlasEditInboxProc);
    destructor Destroy; override;
    property Folder: string read FFolder;
    /// <summary>Zurückgehaltene Änderungen (#2605); leben mit dem Eingang.</summary>
    property Held: TAtlasIdeHeldEdits read FHeld;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.UI.Assistants.Strings,
  Atlas.Core.Assistants.EditInbox,
  Atlas.Core.Assistants.Inbox,
  Atlas.Core.Assistants.EditPlan,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Assistants.LogEntries,
  Atlas.Core.Editor.WorkspacePlan;

{ TAtlasIdeEditInbox }

constructor TAtlasIdeEditInbox.Create(const AFiles: IAtlasEditorFiles; AActivity: TAtlasAssistantsActivity;
  ALog: TAtlasAssistantsLog; const AOnMessage: TAtlasEditInboxProc);
begin
  inherited Create;
  FFiles := AFiles;
  FActivity := AActivity;
  FLog := ALog;
  FOnMessage := AOnMessage;
  FHeld := TAtlasIdeHeldEdits.Create(AFiles, ALog,
    procedure(AText: string)
    begin
      if Assigned(AOnMessage) then
      begin
        AOnMessage(AText);
      end;
    end);
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
  // Wartende Änderungen gehen mit dem Eingang (Regel 3); der MCP-Server hat schon „wartet“ bekommen.
  FHeld.Free;
  // Erst die Beobachtung schließen: Sie hält den Ordner offen.
  FSignal.Free;
  Clean;
  inherited Destroy;
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
    for mRequestFile in TAtlasFileInbox.Pending(FFolder) do
    begin
      Process(mRequestFile);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Files, E);
  end;
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
  // Pause für KI (#1906): ablehnen, ohne dass der MCP-Server selbst schreibt.
  if FActivity.Paused then
  begin
    TAtlasEditInbox.Answer(FFolder, mRequest, False, False,
      TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.RefusedPaused), False);
    TAtlasIdeLogEntries.AddPlain(FLog, TAtlasAssistantsLogKind.Refused, mRequest.FileName, mRequest.Client,
      TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.RefusedPaused));
    Exit;
  end;
  // Zurückhalten nur, wenn der MCP-Server darum bittet und der Mensch es eingeschaltet hat (#2605).
  mOutcome := TAtlasEditInboxPlan.Run(FFiles, mRequest.FileName, mRequest.Expected, mRequest.Text,
    mRequest.Hold and TAtlasIdeSettings.Current.AssistantsEditHoldModified, ApplyInEditor);
  if mOutcome.Held then
  begin
    TAtlasEditInbox.Answer(FFolder, mRequest, False, False, mOutcome.Reason, True);
    FHeld.Hold(mRequest);
    Exit;
  end;
  TAtlasEditInbox.Answer(FFolder, mRequest, mOutcome.Applied, mOutcome.ServerWrites, mOutcome.Reason, False);
  if not mOutcome.Applied then
  begin
    // Schreibt der MCP-Server selbst (Datei nicht offen), ist nichts abgelehnt.
    if not mOutcome.ServerWrites then
    begin
      TAtlasIdeLogEntries.AddPlain(FLog, TAtlasAssistantsLogKind.Refused, mRequest.FileName, mRequest.Client,
        mOutcome.Reason);
    end;
    Exit;
  end;
  TAtlasIdeLogEntries.AddEdit(FLog, TAtlasAssistantsLogKind.Edited, mRequest.FileName, mRequest.Client,
    mRequest.Expected, mRequest.Text);
  FActivity.EditApplied(mRequest.FileName, mRequest.Client, GetTickCount64);
  if Assigned(FOnMessage) then
  begin
    FOnMessage(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.McpEditApplied,
      [ExtractFileName(mRequest.FileName)]));
  end;
end;

end.
