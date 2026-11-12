unit Atlas.IDE.Assistants.BuildInbox;

// Eingang für Builds von KI-Assistenten (#261, Protokoll in Atlas.Core.Assistants.BuildInbox): Sobald der Ordner sich
// ändert (Signal alle 250 ms abgefragt, aufgelistet nur nach einem Signal, bei liegen gebliebenen Aufträgen oder alle
// zwei Sekunden, #1984), übernimmt das Plugin einen wartenden Auftrag des MCP-Werkzeugs build_project, baut über den
// Vertrag IAtlasBuildRequests des Moduls Build-Pipeline (#1888) und antwortet mit Ergebnis und Compilermeldungen. Fehlt
// das Modul, lehnt der Eingang mit Grund ab. Ist das Projekt nicht offen, öffnet der Eingang es zuvor (mit „group“ die
// ganze Projektgruppe, sonst zur aktuellen Gruppe hinzu, #1904): So baut auch eine frisch gestartete Bau-IDE
// (Tools/Build-Ide.ps1).
// Immer nur ein Auftrag zugleich; die übrigen warten, bis der Läufer frei ist
// (der MCP-Server zieht sie nach seiner Frist zurück). Abschaltbar über die
// Einstellung „Builds für KI-Assistenten“ (McpBuild); dann läuft der Eingang
// nicht, und der MCP-Server meldet „nicht angenommen“.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Build.Requests,
  Atlas.Core.Assistants.InboxPace,
  Atlas.IDE.Contracts.BuildRequests,
  Atlas.IDE.Assistants.FolderSignal;

type
  TAtlasBuildInboxProc = reference to procedure(const AMessage: string);

  TAtlasIdeBuildInbox = class
  private
    FFolder: string;
    FTimer: TTimer;
    FSignal: TAtlasFolderSignal;
    FPace: TAtlasInboxPace;
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
  ToolsAPI,
  System.IOUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Build.Messages,
  Atlas.Core.Assistants.BuildInbox,
  Atlas.UI.Assistants.Strings;

var
  /// <summary>Ordner dieses Prozesses schon einmal aufgeräumt?</summary>
  GCleaned: Boolean;

constructor TAtlasIdeBuildInbox.Create(const ARequests: TFunc<IAtlasBuildRequests>;
  const AOnMessage: TAtlasBuildInboxProc);
begin
  inherited Create;
  FRequests := ARequests;
  FOnMessage := AOnMessage;
  FFolder := TAtlasBuildInbox.Folder(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    GetCurrentProcessId);
  // Nur beim ersten Start in diesem Prozess aufräumen (Reste eines früheren Prozesses mit derselben Nummer).
  // Startet der Eingang neu (Einstellungen neu angewendet, Projektgruppe geöffnet), bleiben wartende und
  // laufende Aufträge liegen; sonst stellte der Auftraggeber sie neu und dasselbe Projekt würde wieder gebaut.
  if not GCleaned then
  begin
    Clean;
    GCleaned := True;
  end;
  FSignal := TAtlasFolderSignal.Create(FFolder);
  FPace := Default(TAtlasInboxPace);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeBuildInbox.Destroy;
begin
  // Ordner nicht leeren: Ein laufender Build antwortet noch hinein, ein wartender Auftrag gilt beim nächsten Start.
  FTimer.Free;
  FSignal.Free;
  inherited Destroy;
end;

procedure TAtlasIdeBuildInbox.Clean;
begin
  // Reste eines früheren Prozesses mit derselben Nummer.
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
  // Erst nach der Prüfung auf „belegt“ abfragen: Ein Signal während eines Builds bleibt so stehen.
  if not FPace.Due(FSignal.Changed, GetTickCount64) then
  begin
    Exit;
  end;
  FSignal.Reopen;
  try
    mPending := TAtlasBuildInbox.Pending(FFolder);
    // Nur einer je Takt: Liegen mehr, listet der nächste Takt wieder.
    FPace.Listed(GetTickCount64, Length(mPending) > 1);
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

/// <summary>Öffnet AProject, wenn es nicht offen ist: mit AGroup die ganze Projektgruppe (dann sind alle ihre
/// Projekte offen), sonst das Projekt zur aktuellen Gruppe hinzu.</summary>
procedure EnsureProjectOpen(const AProject, AGroup: string);
var
  mModules: IOTAModuleServices;
  mActions: IOTAActionServices;
begin
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) and (mModules.FindModule(AProject) <> nil) then
  begin
    Exit;
  end;
  if not Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    Exit;
  end;
  if (AGroup <> '') and FileExists(AGroup) then
  begin
    TAtlasGuard.RunIde(
      procedure
      begin
        mActions.OpenProject(AGroup, True);
      end);
  end
  else if FileExists(AProject) then
  begin
    TAtlasGuard.RunIde(
      procedure
      begin
        mActions.OpenProject(AProject, False);
      end);
  end;
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

/// <summary>Antwort nach dem Build in AFolder und Meldung über AOnMessage; hält nur Werte, nicht den Briefkasten.
/// </summary>
function BuildDone(const AFolder: string; const ARequest: TAtlasBuildRequest;
  const AOnMessage: TAtlasBuildInboxProc): TAtlasBuildDoneProc;
begin
  Result :=
    procedure(const AReport: TAtlasBuildReport; const AError: string)
    begin
      try
        if AError <> '' then
        begin
          TAtlasBuildInbox.Answer(AFolder, ARequest.Id, TAtlasBuildInbox.RefusalText(AError));
          Exit;
        end;
        TAtlasBuildInbox.Answer(AFolder, ARequest.Id, TAtlasBuildInbox.SuccessText(AReport));
        if Assigned(AOnMessage) then
        begin
          AOnMessage(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.BuildFinished,
            [ExtractFileName(ARequest.Project), ErrorCount(AReport.Messages)]));
        end;
      except
        on E: Exception do
          TAtlasGuard.Report(TAtlasFeature.Build, E);
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
  EnsureProjectOpen(mRequest.Project, mRequest.Group);
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
    mStarted := mRequests.Start(mRequest, TAtlasBuildInbox.cRequestedBy, BuildDone(mFolder, mRequest, mOnMessage),
      mReason);
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
