unit Atlas.IDE.Assistants.ContextExport;

// Zustand der IDE für KI-Assistenten (#2050, MCP-Werkzeug get_ide_context): Alle cTickMs sammelt das Modul, wo
// der Entwickler gerade ist (Datei, Cursor, Methode aus dem vorhandenen Gliederungsstand, Auswahl, aktives
// Projekt, letzter Build, Reiter), und schreibt es nach %LOCALAPPDATA%\Atlas\ide-context-<pid>.json, sobald ein
// neuer Stand cQuietMs ruht (TAtlasContextPace). Tippen in derselben Methode schreibt nicht. Den letzten Build
// meldet das Modul über BuildRemembered (IAtlasBuildVerdictListener). Beim Beenden löscht es die Datei; Reste
// abgestürzter Prozesse räumt Base beim Start weg (Atlas.IDE.Files.DirtyExport). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Text.IdeContext,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Verdict,
  Atlas.Core.Assistants.ContextState;

type
  TAtlasIdeContextExport = class
  public const
    cTickMs = 250;
  private
    FTimer: TTimer;
    FFileName: string;
    FPace: TAtlasContextPace;
    FBuild: TIdeContextBuild;
    FSelectionRange: string;
    FSelectionText: string;
    FWritten: Boolean;
    procedure Tick(Sender: TObject);
    function Collect: TIdeContext;
    function SelectionText(const ARange: string; const AReadText: TFunc<string>): string;
    procedure WriteState(var AContext: TIdeContext);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Letzter Build der IDE (nicht die Hintergrundprüfung von Atlas).</summary>
    procedure BuildRemembered(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.DateUtils,
  ToolsAPI,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Editor.Metrics,
  Atlas.Core.StatusBar.Content,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorTabs,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Files.DirtyExport,
  Atlas.IDE.Outline.Cache,
  Atlas.UI.Assistants.Strings;

function NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

/// <summary>Qualifizierter Name der Methode an ALine (0-basiert) aus dem Gliederungsstand; '' ohne.</summary>
function MethodAt(const AView: IOTAEditView; const AFileName: string; ALine: Integer): string;
var
  mSnapshot: TAtlasOutlineSnapshot;
  mMethod: TAtlasStatusMethod;
begin
  Result := '';
  if not TAtlasIdeOutlineCache.IsPascal(AFileName) then
  begin
    Exit;
  end;
  mSnapshot := TAtlasIdeOutlineCache.Refresh(AView);
  if (mSnapshot.Status = TAtlasOutlineStatus.Ready) and SameText(mSnapshot.FileName, AFileName) then
  begin
    mMethod := TAtlasStatusBarContent.MethodAt(mSnapshot.Nodes, ALine, Default(TAtlasFileMetrics), False);
    if mMethod.Found then
    begin
      Result := mMethod.Name;
    end;
  end;
end;

function EditorOf(const AView: IOTAEditView): TIdeContextEditor;
begin
  Result := Default(TIdeContextEditor);
  if (AView = nil) or (AView.Buffer = nil) or (AView.Buffer.FileName = '') then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.FileName := AView.Buffer.FileName;
  Result.Line := AView.CursorPos.Line;
  Result.Column := AView.CursorPos.Col;
  Result.Modified := AView.Buffer.IsModified;
  Result.Method := MethodAt(AView, Result.FileName, Result.Line - 1);
end;

function ProjectOf: TIdeContextProject;
var
  mModules: IOTAModuleServices;
  mProject: IOTAProject;
  mGroup: IOTAProjectGroup;
begin
  Result := Default(TIdeContextProject);
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mProject := mModules.GetActiveProject;
  if mProject <> nil then
  begin
    Result.FileName := mProject.FileName;
    Result.Configuration := mProject.CurrentConfiguration;
    Result.Platform := mProject.CurrentPlatform;
  end;
  mGroup := mModules.MainProjectGroup;
  if mGroup <> nil then
  begin
    Result.Group := mGroup.FileName;
  end;
end;

{ TAtlasIdeContextExport }

constructor TAtlasIdeContextExport.Create;
begin
  inherited Create;
  FFileName := TIdeContexts.FileName(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    GetCurrentProcessId);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeContextExport.Destroy;
begin
  FTimer.Free;
  // Nur wenn dieser Lauf geschrieben hat; die Datei eines abgestürzten Vorgängers mit derselben Nummer räumt Base
  // beim Start weg. Liegengeblieben übergeht der Server sie (Prozess beendet).
  if FWritten then
  begin
    TAtlasDataFile.RemoveQuietly(FFileName);
  end;
  inherited Destroy;
end;

procedure TAtlasIdeContextExport.BuildRemembered(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict);
begin
  if not AProject.Background then
  begin
    FBuild := TAtlasAssistantContext.Build(AMessages, AProject, AVerdict, NowUtc);
  end;
end;

function TAtlasIdeContextExport.SelectionText(const ARange: string; const AReadText: TFunc<string>): string;
begin
  // Text nur bei geändertem Bereich neu holen: Große Auswahlen kosten sonst bei jedem Takt.
  if ARange <> FSelectionRange then
  begin
    FSelectionRange := ARange;
    FSelectionText := AReadText();
  end;
  Result := FSelectionText;
end;

function TAtlasIdeContextExport.Collect: TIdeContext;
var
  mView: IOTAEditView;
  mBlock: IOTAEditBlock;
  mText: string;
begin
  Result := Default(TIdeContext);
  Result.Pid := GetCurrentProcessId;
  mView := TAtlasEditorBuffer.ActiveView;
  Result.Editor := EditorOf(mView);
  mBlock := nil;
  if mView <> nil then
  begin
    mBlock := mView.Block;
  end;
  if (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0) then
  begin
    mText := SelectionText(Format('%s|%d:%d-%d:%d|%d', [Result.Editor.FileName, mBlock.StartingRow,
      mBlock.StartingColumn, mBlock.EndingRow, mBlock.EndingColumn, mBlock.Size]),
      function: string
      begin
        Result := mBlock.Text;
      end);
    Result.Selection := TAtlasAssistantContext.Selection(
      TAtlasAssistantContext.Range(mBlock.StartingRow, mBlock.StartingColumn, mBlock.EndingRow, mBlock.EndingColumn),
      mText, TAtlasIdeSettings.Current.AssistantsContextSelection,
      TAtlasIdeSettings.Current.AssistantsContextSelectionMax);
  end;
  Result.Project := ProjectOf;
  Result.Build := FBuild;
  Result.Tabs := TAtlasEditorTabs.Ordered(TAtlasDirtyExport.OpenFiles);
end;

procedure TAtlasIdeContextExport.WriteState(var AContext: TIdeContext);
begin
  AContext.AtUtc := NowUtc;
  try
    // Atomar: Der Server liest jederzeit und sähe sonst womöglich einen halben Stand.
    TAtlasDataFile.Write(FFileName, TIdeContexts.ToJson(AContext));
    FWritten := True;
  except
    // Beim nächsten Wechsel erneut versuchen; der Grund steht einmal im Protokoll.
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.ContextKind), E);
  end;
end;

procedure TAtlasIdeContextExport.Tick(Sender: TObject);
var
  mContext: TIdeContext;
begin
  mContext := Collect;
  if FPace.Due(TIdeContexts.ChangeKey(mContext), GetTickCount64) then
  begin
    WriteState(mContext);
  end;
end;

end.
