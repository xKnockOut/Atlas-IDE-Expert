unit Atlas.IDE.Assistants.BuildInbox;

// Eingang für Builds von KI-Assistenten (#261, Protokoll in
// Atlas.Core.Assistants.BuildInbox): Alle 250 ms übernimmt das Plugin einen wartenden
// Auftrag des MCP-Werkzeugs build_project, baut über den Vertrag IAtlasBuildRequests
// des Moduls Build-Pipeline (#1888) und antwortet mit Ergebnis und Compilermeldungen.
// Fehlt das Modul, lehnt der Eingang mit Grund ab.
// Immer nur ein Auftrag zugleich; die übrigen warten, bis der Läufer frei ist
// (der MCP-Server zieht sie nach seiner Frist zurück). Abschaltbar über die
// Einstellung „Builds für KI-Assistenten“ (McpBuild); dann läuft der Eingang
// nicht, und der MCP-Server meldet „nicht angenommen“.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Build.Requests,
  Atlas.IDE.Contracts.BuildRequests;

type
  TAtlasBuildInboxProc = reference to procedure(const AMessage: string);

  TAtlasIdeBuildInbox = class
  private
    FFolder: string;
    FTimer: TTimer;
    FRequests: TFunc<IAtlasBuildRequests>;
    FOnMessage: TAtlasBuildInboxProc;
    procedure Tick(Sender: TObject);
    procedure Process(const ARequestFile: string);
    procedure Clean;
  public
    /// <summary>ARequests liefert die Builds des Moduls Build-Pipeline (nil ohne Modul). AOnMessage: Zeile für die
    /// Meldungsansicht.</summary>
    constructor Create(const ARequests: TFunc<IAtlasBuildRequests>; const AOnMessage: TAtlasBuildInboxProc);
    destructor Destroy; override;
    property Folder: string read FFolder;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Build.Messages,
  Atlas.Core.Assistants.BuildInbox,
  Atlas.UI.Assistants.Strings;

constructor TAtlasIdeBuildInbox.Create(const ARequests: TFunc<IAtlasBuildRequests>;
  const AOnMessage: TAtlasBuildInboxProc);
begin
  inherited Create;
  FRequests := ARequests;
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
  mPending: TArray<string>;
  mRequests: IAtlasBuildRequests;
begin
  mRequests := FRequests();
  if TAtlasGuard.Disabled(TAtlasFeature.Build) or ((mRequests <> nil) and mRequests.Busy) then
  begin
    Exit;
  end;
  try
    mPending := TAtlasBuildInbox.Pending(FFolder);
    if Length(mPending) > 0 then
    begin
      Process(mPending[0]);
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
  Result.Unreadable := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.RequestUnreadable);
  Result.NoProject := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.RequestNoProject);
  Result.UnknownMode := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.RequestUnknownMode);
end;

function ErrorCount(const AMessages: TArray<TAtlasCompilerMessage>): Integer;
var
  mMessage: TAtlasCompilerMessage;
begin
  Result := 0;
  for mMessage in AMessages do
  begin
    if mMessage.Severity in [TAtlasCompilerSeverity.Error, TAtlasCompilerSeverity.Fatal] then
    begin
      Inc(Result);
    end;
  end;
end;

procedure TAtlasIdeBuildInbox.Process(const ARequestFile: string);
var
  mRequest: TAtlasBuildRequest;
  mReason, mFolder: string;
  mOnMessage: TAtlasBuildInboxProc;
  mRequests: IAtlasBuildRequests;
  mStarted: Boolean;
begin
  if not TAtlasBuildInbox.Take(ARequestFile, InboxTexts, mRequest, mReason) then
  begin
    Exit;
  end;
  mRequests := FRequests();
  mFolder := FFolder;
  mOnMessage := FOnMessage;
  if Assigned(mOnMessage) then
  begin
    mOnMessage(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.BuildStarted,
      [ExtractFileName(mRequest.Project)]));
  end;
  // Die Antwort kommt nach dem Build (Meldungen des Lesers, #528); der Rückruf hält nur Werte, nicht Self.
  mStarted := False;
  mReason := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.NoBuildPipeline);
  if mRequests <> nil then
  begin
    mStarted := mRequests.Start(mRequest, TAtlasBuildInbox.cRequestedBy,
    procedure(const AReport: TAtlasBuildReport; const AError: string)
    begin
      try
        if AError <> '' then
        begin
          TAtlasBuildInbox.Answer(mFolder, mRequest.Id, TAtlasBuildInbox.RefusalText(AError));
        end
        else
        begin
          TAtlasBuildInbox.Answer(mFolder, mRequest.Id, TAtlasBuildInbox.SuccessText(AReport));
        end;
        if Assigned(mOnMessage) and (AError = '') then
        begin
          mOnMessage(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.BuildFinished,
            [ExtractFileName(mRequest.Project),
            ErrorCount(AReport.Messages)]));
        end;
      except
        on E: Exception do
          TAtlasGuard.Report(TAtlasFeature.Build, E);
      end;
    end, mReason);
  end;
  if not mStarted then
  begin
    TAtlasBuildInbox.Answer(FFolder, mRequest.Id, TAtlasBuildInbox.RefusalText(mReason));
    if Assigned(mOnMessage) then
    begin
      mOnMessage(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.BuildRefused,
        [ExtractFileName(mRequest.Project), mReason]));
    end;
  end;
end;

end.
