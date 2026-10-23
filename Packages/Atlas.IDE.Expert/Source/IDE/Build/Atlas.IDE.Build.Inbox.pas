unit Atlas.IDE.Build.Inbox;

// Eingang für Builds von Claude Code (#261, Protokoll in
// Atlas.Core.Build.Inbox): Alle 250 ms übernimmt das Plugin einen wartenden
// Auftrag des MCP-Werkzeugs build_project, baut über den Build-Läufer
// (Atlas.IDE.Build.Runner) und antwortet mit Ergebnis und Compilermeldungen.
// Immer nur ein Auftrag zugleich; die übrigen warten, bis der Läufer frei ist
// (der MCP-Server zieht sie nach seiner Frist zurück). Abschaltbar über die
// Einstellung „Builds für Claude Code“ (McpBuild); dann läuft der Eingang
// nicht, und der MCP-Server meldet „nicht angenommen“.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.IDE.Build.Runner;

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
  Atlas.Core.Build.Inbox,
  Atlas.UI.Strings;

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
      TDirectory.Delete(FFolder, True);
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
    Exit;
  try
    Pending := TAtlasBuildInbox.Pending(FFolder);
    if Length(Pending) > 0 then
      Process(Pending[0]);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Build, E);
  end;
end;

function ErrorCount(const AMessages: TArray<TAtlasCompilerMessage>): Integer;
var
  Message: TAtlasCompilerMessage;
begin
  Result := 0;
  for Message in AMessages do
    if Message.Severity in [TAtlasCompilerSeverity.Error, TAtlasCompilerSeverity.Fatal] then
      Inc(Result);
end;

procedure TAtlasIdeBuildInbox.Process(const ARequestFile: string);
var
  Request: TAtlasBuildRequest;
  Reason, mFolder: string;
  OnMessage: TAtlasBuildInboxProc;
begin
  if not TAtlasBuildInbox.Take(ARequestFile, Request, Reason) then
    Exit;
  mFolder := FFolder;
  OnMessage := FOnMessage;
  if Assigned(OnMessage) then
    OnMessage(TAtlasStrings.Fmt(TAtlasTextId.McpBuildStarted, [ExtractFileName(Request.Project)]));
  // Die Antwort kommt nach dem Build (Meldungen des Lesers, #528); der Rückruf hält nur Werte, nicht Self.
  if not FRunner.Start(Request, TAtlasBuildInbox.RequestedBy,
    procedure(const AReport: TAtlasBuildReport; const AError: string)
    begin
      try
        if AError <> '' then
          TAtlasBuildInbox.Answer(mFolder, Request.Id, TAtlasBuildInbox.RefusalText(AError))
        else
          TAtlasBuildInbox.Answer(mFolder, Request.Id, TAtlasBuildInbox.SuccessText(AReport));
        if Assigned(OnMessage) and (AError = '') then
          OnMessage(TAtlasStrings.Fmt(TAtlasTextId.McpBuildFinished, [ExtractFileName(Request.Project),
            ErrorCount(AReport.Messages)]));
      except
        on E: Exception do
          TAtlasGuard.Report(TAtlasFeature.Build, E);
      end;
    end, Reason) then
  begin
    TAtlasBuildInbox.Answer(FFolder, Request.Id, TAtlasBuildInbox.RefusalText(Reason));
    if Assigned(OnMessage) then
      OnMessage(TAtlasStrings.Fmt(TAtlasTextId.McpBuildRefused, [ExtractFileName(Request.Project), Reason]));
  end;
end;

end.
