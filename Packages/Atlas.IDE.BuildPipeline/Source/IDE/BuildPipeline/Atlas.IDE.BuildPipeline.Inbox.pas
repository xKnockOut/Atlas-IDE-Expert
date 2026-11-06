unit Atlas.IDE.BuildPipeline.Inbox;

// Eingang für Builds von Claude Code (#261, Protokoll in
// Atlas.Core.BuildPipeline.Inbox): Alle 250 ms übernimmt das Plugin einen wartenden
// Auftrag des MCP-Werkzeugs build_project, baut über den Build-Läufer
// (Atlas.IDE.BuildPipeline.Runner) und antwortet mit Ergebnis und Compilermeldungen.
// Immer nur ein Auftrag zugleich; die übrigen warten, bis der Läufer frei ist
// (der MCP-Server zieht sie nach seiner Frist zurück). Abschaltbar über die
// Einstellung „Builds für Claude Code“ (McpBuild); dann läuft der Eingang
// nicht, und der MCP-Server meldet „nicht angenommen“.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.IDE.BuildPipeline.Runner;

type
  TAtlasBuildInboxProc = reference to procedure(const AMessage: string);

  TAtlasIdeBuildInbox = class
  private
    FFolder: string;
    FTimer: TTimer;
    FRunner: TAtlasIdeBuildRunner;
    FOnMessage: TAtlasBuildInboxProc;
    procedure Tick(Sender: TObject);
    procedure Process(const ARequestFile: string);
    procedure Clean;
  public
    /// <summary>ARunner gehört dem Aufrufer und muss länger leben. AOnMessage: Zeile für die Meldungsansicht.
    /// </summary>
    constructor Create(ARunner: TAtlasIdeBuildRunner; const AOnMessage: TAtlasBuildInboxProc);
    destructor Destroy; override;
    property Folder: string read FFolder;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Build.Messages,
  Atlas.Core.BuildPipeline.Inbox,
  Atlas.UI.BuildPipeline.Strings;

constructor TAtlasIdeBuildInbox.Create(ARunner: TAtlasIdeBuildRunner; const AOnMessage: TAtlasBuildInboxProc);
begin
  inherited Create;
  FRunner := ARunner;
  FOnMessage := AOnMessage;
  FFolder := TAtlasBuildInbox.Folder(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    GetCurrentProcessId);
  Clean;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeBuildInbox.Destroy;
begin
  FTimer.Free;
  Clean;
  inherited Destroy;
end;

procedure TAtlasIdeBuildInbox.Clean;
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

procedure TAtlasIdeBuildInbox.Tick(Sender: TObject);
var
  Pending: TArray<string>;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Build) or FRunner.Busy then
  begin
    Exit;
  end;
  try
    Pending := TAtlasBuildInbox.Pending(FFolder);
    if Length(Pending) > 0 then
    begin
      Process(Pending[0]);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Build, E);
  end;
end;

/// <summary>Gründe für unlesbare Aufträge in der Sprache der Oberfläche (#1458).</summary>
function InboxTexts: TAtlasBuildInboxTexts;
begin
  Result := Default(TAtlasBuildInboxTexts);
  Result.Unreadable := TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.McpRequestUnreadable);
  Result.NoProject := TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.McpRequestNoProject);
  Result.UnknownMode := TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.McpRequestUnknownMode);
end;

function ErrorCount(const AMessages: TArray<TAtlasCompilerMessage>): Integer;
var
  Message: TAtlasCompilerMessage;
begin
  Result := 0;
  for Message in AMessages do
  begin
    if Message.Severity in [TAtlasCompilerSeverity.Error, TAtlasCompilerSeverity.Fatal] then
    begin
      Inc(Result);
    end;
  end;
end;

procedure TAtlasIdeBuildInbox.Process(const ARequestFile: string);
var
  Request: TAtlasBuildRequest;
  Reason, mFolder: string;
  OnMessage: TAtlasBuildInboxProc;
begin
  if not TAtlasBuildInbox.Take(ARequestFile, InboxTexts, Request, Reason) then
  begin
    Exit;
  end;
  mFolder := FFolder;
  OnMessage := FOnMessage;
  if Assigned(OnMessage) then
  begin
    OnMessage(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.McpBuildStarted,
      [ExtractFileName(Request.Project)]));
  end;
  // Die Antwort kommt nach dem Build (Meldungen des Lesers, #528); der Rückruf hält nur Werte, nicht Self.
  if not FRunner.Start(Request, TAtlasBuildInbox.RequestedBy,
    procedure(const AReport: TAtlasBuildReport; const AError: string)
    begin
      try
        if AError <> '' then
        begin
          TAtlasBuildInbox.Answer(mFolder, Request.Id, TAtlasBuildInbox.RefusalText(AError));
        end
        else
        begin
          TAtlasBuildInbox.Answer(mFolder, Request.Id, TAtlasBuildInbox.SuccessText(AReport));
        end;
        if Assigned(OnMessage) and (AError = '') then
        begin
          OnMessage(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.McpBuildFinished,
            [ExtractFileName(Request.Project),
            ErrorCount(AReport.Messages)]));
        end;
      except
        on E: Exception do
          TAtlasGuard.Report(TAtlasFeature.Build, E);
      end;
    end, Reason) then
  begin
    TAtlasBuildInbox.Answer(FFolder, Request.Id, TAtlasBuildInbox.RefusalText(Reason));
    if Assigned(OnMessage) then
    begin
      OnMessage(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.McpBuildRefused,
        [ExtractFileName(Request.Project), Reason]));
    end;
  end;
end;

end.
