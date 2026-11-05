unit Shell.SlashHost;

// Host-Rolle Shell: Projekt- und Editorzugriff für Schnellbefehle wie
// /define, /config und /dfm (#301). Schreibt die .dproj in ihrer Kodierung
// zurück, lädt den Ordner neu und schickt window/showDocument an den Editor.
// Kann der Client workspace/applyEdit (das Plugin, #397), geht die Änderung
// an ihn statt auf die Platte, damit die IDE sie nicht beim Speichern des
// Projekts überschreibt; neu geladen wird nach seiner Antwort. Lehnt er ab,
// bleibt die Datei unverändert und der Editor zeigt den Grund.
//
// Schnellbefehle laufen in einem Worker-Thread (onTypeFormatting). Neu geladen
// wird nur im Thread der Nachrichtenschleife (Code-Review A-03): WriteProject
// und SelectBuild stellen das über RunInLoop dorthin.
//
// WriteFiles (/unit, #297) legt mehrere Dateien in einem WorkspaceEdit an
// bzw. ersetzt sie und öffnet danach die neue Unit; ohne Editor auf der Platte
// (neue Dateien in der Kodierung der Datei des Befehls, sonst UTF-8 mit BOM,
// Zeilenende wie im Text, #299/#121; vorhandene in ihrer Kodierung).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Editing.Contract,
  Shell.Workspace;

type
  /// <summary>Ordner zur Datei AUri; nil ohne.</summary>
  TWorkspaceOfFunc = reference to function(const AUri: string): TShellWorkspace;
  TReadTextFunc = reference to function(const AFileName: string; out AText: string): Boolean;
  THeaderTemplateFunc = reference to function(const AUri: string): string;
  /// <summary>Wert der Einstellung slashCommands.AName zur Datei AUri.</summary>
  TSlashSettingFunc = reference to function(const AUri, AName: string): string;
  /// <summary>Testunit zur Unit AUri mit Text AText (/test, #295).</summary>
  TSlashTestUnitFunc = reference to function(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;

  /// <summary>Woher der Host Ordner, Dateien und Einstellungen bekommt. WorkspaceOf, ReadText und
  /// HeaderTemplate sind Pflicht; die übrigen dürfen fehlen (siehe Eigenschaften des Hosts).</summary>
  TShellSlashSources = record
    WorkspaceOf: TWorkspaceOfFunc;
    ReadText: TReadTextFunc;
    HeaderTemplate: THeaderTemplateFunc;
    SettingOf: TSlashSettingFunc;
    TestUnitOf: TSlashTestUnitFunc;
    RuleIdsOf: TSlashRuleIdsFunc;
    UsesContextOf: TSlashUsesContextFunc;
    FindingsOf: TSlashFindingsFunc;
    /// <summary>Quellen mit den drei Pflichtfunktionen, die übrigen leer.</summary>
    class function New(const AWorkspaceOf: TWorkspaceOfFunc; const AReadText: TReadTextFunc;
      const AHeaderTemplate: THeaderTemplateFunc): TShellSlashSources; static;
  end;

  TShellSlashHost = class(TInterfacedObject, ISlashHost)
  private
    FSources: TShellSlashSources;
    FTransport: IJsonRpcTransport;
    FLogger: ILogger;
    FRequestId: Integer;
    FDispatcher: TJsonRpcDispatcher;
    FClientAppliesEdits: TFunc<Boolean>;
    FRunInLoop: TJsonRpcScheduler;
    function ClientWrites: Boolean;
    /// <summary>Schickt AEdit (wird übernommen) an den Client; nach Erfolg Reload und AAfter.</summary>
    procedure SendEdit(const AUri, ADescription: string; AEdit: TJSONObject; const AAfter: TProc); overload;
    /// <summary>Wie oben; AReload: Ordner nach Erfolg neu laden (Projektdateien), sonst nur protokollieren.</summary>
    procedure SendEdit(const AUri, ADescription: string; AEdit: TJSONObject; const AAfter: TProc;
      AReload: Boolean); overload;
    function WriteThroughClient(const AUri, AFileName, AText: string): Boolean;
    /// <summary>Führt AWork im Thread der Nachrichtenschleife aus (über RunInLoop), sonst sofort.</summary>
    procedure InLoop(const AWork: TProc);
  public
    /// <summary>ADispatcher und AClientAppliesEdits dürfen nil sein; dann schreibt der Host selbst.</summary>
    constructor Create(const ASources: TShellSlashSources; const ATransport: IJsonRpcTransport;
      const ALogger: ILogger; ADispatcher: TJsonRpcDispatcher; const AClientAppliesEdits: TFunc<Boolean>); overload;
    /// <summary>Wie oben mit AClientAppliesEdits = nil.</summary>
    constructor Create(const ASources: TShellSlashSources; const ATransport: IJsonRpcTransport;
      const ALogger: ILogger; ADispatcher: TJsonRpcDispatcher); overload;
    /// <summary>Wie oben mit ADispatcher = nil und AClientAppliesEdits = nil.</summary>
    constructor Create(const ASources: TShellSlashSources; const ATransport: IJsonRpcTransport;
      const ALogger: ILogger); overload;
    function Project(const AUri: string; out AProject: TProjectInfo): Boolean;
    function ReadFile(const AFileName: string; out AText: string): Boolean;
    function DirectoryExists(const APath: string): Boolean;
    procedure WriteProject(const AUri, AText: string);
    procedure SelectBuild(const AUri, AConfig, APlatform: string);
    procedure ShowDocument(const AFileName: string; const ASelection: TTextRange);
    function HeaderTemplate(const AUri: string): string;
    procedure WriteFiles(const AUri: string; const AFiles: TArray<TSlashFile>; const AShow: string);
    function Setting(const AUri, AName: string): string;
    function TestUnit(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;
    procedure Notify(const AUri, AMessage: string);
    procedure MoveCursor(const AUri: string; const APosition: TTextPosition);
    function RuleIdsAt(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean;
    function UsesContext(const AUri: string; out AContext: TUsesContext): Boolean;
    function FindingsAt(const AUri, AText: string; ALine: Integer; out AFindings: TArray<TSlashFinding>): Boolean;
    /// <summary>Eine Änderung an einer Quelldatei (resourcestring in eine andere Unit, #473): im Editor über
    /// workspace/applyEdit in deren Puffer, ohne neu zu laden; ohne Editor ANewText auf die Platte in der
    /// Kodierung der Datei.</summary>
    procedure EditFile(const AUri, AFileName, ANewText: string; const AEdit: TTextEdit);
    /// <summary>Einstellungen slashCommands.* zur Datei (#299, #304); ohne Zuweisung ''.</summary>
    property SettingOf: TSlashSettingFunc read FSources.SettingOf write FSources.SettingOf;
    /// <summary>Testunit zur Unit (/test, #295); ohne Zuweisung keine.</summary>
    property TestUnitOf: TSlashTestUnitFunc read FSources.TestUnitOf write FSources.TestUnitOf;
    /// <summary>Treffer der Prüfregeln in einer Zeile (/ignore, #297); ohne Zuweisung gilt jede Regel.</summary>
    property RuleIdsOf: TSlashRuleIdsFunc read FSources.RuleIdsOf write FSources.RuleIdsOf;
    /// <summary>Index und usesKeep (/sortuses, #297); ohne Zuweisung wird nur sortiert.</summary>
    property UsesContextOf: TSlashUsesContextFunc read FSources.UsesContextOf write FSources.UsesContextOf;
    /// <summary>Regeltreffer einer Zeile mit Erklärung und sicherer Korrektur (/fix, /explain, #300); ohne
    /// Zuweisung keine Prüfregeln.</summary>
    property FindingsOf: TSlashFindingsFunc read FSources.FindingsOf write FSources.FindingsOf;
    /// <summary>Stellt Arbeit in die Nachrichtenschleife (TJsonRpcConnection.Queue). Reload und SelectBuild
    /// laufen nur dort (Code-Review A-03); ohne Zuweisung (Tests) sofort.</summary>
    property RunInLoop: TJsonRpcScheduler read FRunInLoop write FRunInLoop;
  end;

implementation

uses
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.ApplyEdit,
  Atlas.Text.LogMarks;

class function TShellSlashSources.New(const AWorkspaceOf: TWorkspaceOfFunc; const AReadText: TReadTextFunc;
  const AHeaderTemplate: THeaderTemplateFunc): TShellSlashSources;
begin
  Result := Default(TShellSlashSources);
  Result.WorkspaceOf := AWorkspaceOf;
  Result.ReadText := AReadText;
  Result.HeaderTemplate := AHeaderTemplate;
end;

constructor TShellSlashHost.Create(const ASources: TShellSlashSources; const ATransport: IJsonRpcTransport;
  const ALogger: ILogger; ADispatcher: TJsonRpcDispatcher);
begin
  Create(ASources, ATransport, ALogger, ADispatcher, nil);
end;

constructor TShellSlashHost.Create(const ASources: TShellSlashSources; const ATransport: IJsonRpcTransport;
  const ALogger: ILogger);
begin
  Create(ASources, ATransport, ALogger, nil, nil);
end;

constructor TShellSlashHost.Create(const ASources: TShellSlashSources; const ATransport: IJsonRpcTransport;
  const ALogger: ILogger; ADispatcher: TJsonRpcDispatcher; const AClientAppliesEdits: TFunc<Boolean>);
begin
  inherited Create;
  FSources := ASources;
  FTransport := ATransport;
  FLogger := ALogger;
  FDispatcher := ADispatcher;
  FClientAppliesEdits := AClientAppliesEdits;
end;

function TShellSlashHost.Project(const AUri: string; out AProject: TProjectInfo): Boolean;
var
  Workspace: TShellWorkspace;
begin
  Workspace := FSources.WorkspaceOf(AUri);
  Result := (Workspace <> nil) and Workspace.State.Project(AProject);
end;

function TShellSlashHost.ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := FSources.ReadText(AFileName, AText);
end;

function TShellSlashHost.DirectoryExists(const APath: string): Boolean;
begin
  Result := System.SysUtils.DirectoryExists(APath);
end;

var
  ShowRequests: Integer;

/// <summary>window/showDocument an den Editor; ohne Self, damit es auch nach der Antwort des Clients läuft.</summary>
procedure SendShowDocument(const ATransport: IJsonRpcTransport; const AFileName: string;
  const ASelection: TTextRange);
var
  Request, Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  Params.AddPair('uri', TDocumentUris.FromPath(AFileName));
  Params.AddPair('takeFocus', TJSONBool.Create(True));
  Params.AddPair('selection', TLspPositions.RangeToJson(ASelection));
  Request := TJSONObject.Create;
  try
    Request.AddPair('jsonrpc', '2.0');
    Request.AddPair('id', Format('atlas/showDocument/%d', [AtomicIncrement(ShowRequests)]));
    Request.AddPair('method', 'window/showDocument');
    Request.AddPair('params', Params);
    ATransport.WriteMessage(Request);
  finally
    Request.Free;
  end;
end;

function TShellSlashHost.ClientWrites: Boolean;
begin
  Result := (FDispatcher <> nil) and Assigned(FClientAppliesEdits) and FClientAppliesEdits();
end;

procedure TShellSlashHost.SendEdit(const AUri, ADescription: string; AEdit: TJSONObject; const AAfter: TProc);
begin
  SendEdit(AUri, ADescription, AEdit, AAfter, True);
end;

type
  /// <summary>Was die Antwort auf workspace/applyEdit eines Schnellbefehls braucht; die Antwort kommt später in der
  /// Nachrichtenschleife (ExpectResponse), deshalb als Kopie statt über Self.</summary>
  TSlashEditAnswer = record
    Logger: ILogger;
    Transport: IJsonRpcTransport;
    WorkspaceOf: TWorkspaceOfFunc;
    Uri: string;
    Description: string;
    After: TProc;
    Reload: Boolean;
    procedure Handle(const AResponse: TJSONObject);
  end;

/// <summary>Meldet dem Benutzer, dass der Editor die Änderung abgelehnt hat.</summary>
procedure ShowNotChanged(const ATransport: IJsonRpcTransport; const ADescription, AReason: string);
var
  mMessage: TJSONObject;
begin
  mMessage := TJSONObject.Create;
  try
    mMessage.AddPair('jsonrpc', '2.0');
    mMessage.AddPair('method', 'window/showMessage');
    mMessage.AddPair('params', TJSONObject.Create.AddPair('type', TJSONNumber.Create(2))
      .AddPair('message', Format('Atlas: %s wurde nicht geändert (%s).', [ADescription, AReason])));
    ATransport.WriteMessage(mMessage);
  finally
    mMessage.Free;
  end;
end;

procedure TSlashEditAnswer.Handle(const AResponse: TJSONObject);
var
  mReason: string;
  mTarget: TShellWorkspace;
begin
  if not TLspApplyEdit.ReadResult(AResponse, mReason) then
  begin
    Logger.Warning(Format('%s nicht geändert: %s', [TLogMarks.Text(Description), TLogMarks.Text(mReason)]));
    ShowNotChanged(Transport, Description, mReason);
    Exit;
  end;
  Logger.Info(Format('%s geändert (Schnellbefehl, über den Editor)', [TLogMarks.Text(Description)]));
  if Reload and Assigned(WorkspaceOf) then
  begin
    mTarget := WorkspaceOf(Uri);
    if mTarget <> nil then
    begin
      mTarget.Reload;
    end;
  end;
  if Assigned(After) then
  begin
    After();
  end;
end;

function AnswerHandler(const AAnswer: TSlashEditAnswer): TJsonRpcResponseHandler;
var
  mAnswer: TSlashEditAnswer;
begin
  mAnswer := AAnswer;
  Result :=
    procedure(const AResponse: TJSONObject)
    begin
      mAnswer.Handle(AResponse);
    end;
end;

procedure TShellSlashHost.SendEdit(const AUri, ADescription: string; AEdit: TJSONObject; const AAfter: TProc;
  AReload: Boolean);
var
  mId: string;
  mAnswer: TSlashEditAnswer;
  mRequest: TJSONObject;
begin
  mId := Format('atlas/applyEdit/%d', [AtomicIncrement(FRequestId)]);
  mAnswer.Logger := FLogger;
  mAnswer.Transport := FTransport;
  mAnswer.WorkspaceOf := FSources.WorkspaceOf;
  mAnswer.Uri := AUri;
  mAnswer.Description := ADescription;
  mAnswer.After := AAfter;
  mAnswer.Reload := AReload;
  FDispatcher.ExpectResponse(mId, AnswerHandler(mAnswer));
  mRequest := TLspApplyEdit.Request(mId, 'Atlas: Schnellbefehl', AEdit);
  try
    try
      FTransport.WriteMessage(mRequest);
    except
      FDispatcher.ForgetResponse(mId);
      raise;
    end;
  finally
    mRequest.Free;
  end;
end;

function TShellSlashHost.WriteThroughClient(const AUri, AFileName, AText: string): Boolean;
var
  OldText: string;
  FileFormat: TFileFormat;
begin
  Result := ClientWrites;
  if not Result then
  begin
    Exit;
  end;
  OldText := TFileEncoding.LoadFromFile(AFileName, FileFormat);
  SendEdit(AUri, ExtractFileName(AFileName), TLspApplyEdit.ReplaceAll(AFileName, OldText, AText), nil);
end;

procedure TShellSlashHost.EditFile(const AUri, AFileName, ANewText: string; const AEdit: TTextEdit);
var
  FileFormat: TFileFormat;
begin
  if ClientWrites then
  begin
    SendEdit(AUri, 'Die Unit für resourcestrings', TLspApplyEdit.TextEdits(AFileName, [AEdit]), nil, False);
    Exit;
  end;
  TFileEncoding.LoadFromFile(AFileName, FileFormat);
  TFileEncoding.SaveToFile(AFileName, ANewText, FileFormat);
  FLogger.Info('resourcestring eingetragen');
end;

procedure TShellSlashHost.InLoop(const AWork: TProc);
begin
  if Assigned(FRunInLoop) then
  begin
    FRunInLoop(AWork);
  end
  else
  begin
    AWork();
  end;
end;

procedure TShellSlashHost.WriteProject(const AUri, AText: string);
var
  Workspace: TShellWorkspace;
  Info: TProjectInfo;
  FileFormat: TFileFormat;
  WorkspaceOf: TWorkspaceOfFunc;
  Uri: string;
begin
  Workspace := FSources.WorkspaceOf(AUri);
  if (Workspace = nil) or not Workspace.State.Project(Info) then
  begin
    Exit;
  end;
  try
    // In der IDE über das Plugin, nicht auf die Platte (#397).
    if WriteThroughClient(AUri, Info.FileName, AText) then
    begin
      Exit;
    end;
    // Kodierung und Zeilenumbrüche der vorhandenen Datei beibehalten.
    TFileEncoding.LoadFromFile(Info.FileName, FileFormat);
    TFileEncoding.SaveToFile(Info.FileName, AText, FileFormat);
    FLogger.Info(Format('%s geändert (Schnellbefehl)', [TLogMarks.Path(Info.FileName)]));
  except
    on E: Exception do
    begin
      FLogger.Error(Format('%s ließ sich nicht schreiben: %s', [TLogMarks.Path(Info.FileName),
        TLogMarks.Text(E.Message)]));
      Exit;
    end;
  end;
  // const-Parameter lassen sich nicht einfangen.
  WorkspaceOf := FSources.WorkspaceOf;
  Uri := AUri;
  InLoop(
    procedure
    var
      Target: TShellWorkspace;
    begin
      // In der Schleife neu suchen: Bis dahin kann der Ordner geschlossen worden sein.
      Target := WorkspaceOf(Uri);
      if Target <> nil then
      begin
        Target.Reload;
      end;
    end);
end;

procedure TShellSlashHost.SelectBuild(const AUri, AConfig, APlatform: string);
var
  WorkspaceOf: TWorkspaceOfFunc;
  Logger: ILogger;
  Uri, Config, PlatformName: string;
begin
  // const-Parameter lassen sich nicht einfangen; Self auch nicht (der Host kann vorher frei werden).
  WorkspaceOf := FSources.WorkspaceOf;
  Logger := FLogger;
  Uri := AUri;
  Config := AConfig;
  PlatformName := APlatform;
  InLoop(
    procedure
    var
      Workspace: TShellWorkspace;
      Error: string;
    begin
      // Wählt Konfiguration und Plattform und lädt neu: nur in der Schleife (A-03).
      Workspace := WorkspaceOf(Uri);
      if (Workspace <> nil) and not Workspace.SelectBuild(Config, PlatformName, Error) then
      begin
        Logger.Warning(Error);
      end;
    end);
end;

procedure TShellSlashHost.ShowDocument(const AFileName: string; const ASelection: TTextRange);
begin
  SendShowDocument(FTransport, AFileName, ASelection);
end;

function TShellSlashHost.HeaderTemplate(const AUri: string): string;
begin
  Result := FSources.HeaderTemplate(AUri);
end;

function TShellSlashHost.Setting(const AUri, AName: string): string;
begin
  Result := '';
  if Assigned(FSources.SettingOf) then
  begin
    Result := FSources.SettingOf(AUri, AName);
  end;
end;

function TShellSlashHost.RuleIdsAt(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean;
begin
  AIds := nil;
  Result := Assigned(FSources.RuleIdsOf) and FSources.RuleIdsOf(AUri, AText, ALine, AIds);
end;

function TShellSlashHost.UsesContext(const AUri: string; out AContext: TUsesContext): Boolean;
begin
  AContext := Default(TUsesContext);
  Result := Assigned(FSources.UsesContextOf) and FSources.UsesContextOf(AUri, AContext);
end;

function TShellSlashHost.FindingsAt(const AUri, AText: string; ALine: Integer;
  out AFindings: TArray<TSlashFinding>): Boolean;
begin
  AFindings := nil;
  Result := Assigned(FSources.FindingsOf) and FSources.FindingsOf(AUri, AText, ALine, AFindings);
end;

function TShellSlashHost.TestUnit(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;
begin
  ATarget := Default(TSlashTestUnit);
  if not Assigned(FSources.TestUnitOf) then
  begin
    ATarget.Reason := 'Testunits sind hier nicht verfügbar';
    Exit(False);
  end;
  Result := FSources.TestUnitOf(AUri, AText, ATarget);
end;

procedure TShellSlashHost.Notify(const AUri, AMessage: string);
var
  Transport: IJsonRpcTransport;
  Text: string;
begin
  // Erst nach der Antwort mit den Änderungen (Nachrichtenschleife), damit der Hinweis zu ihnen passt.
  Transport := FTransport;
  Text := 'Atlas: ' + AMessage;
  InLoop(
    procedure
    var
      Message: TJSONObject;
    begin
      Message := TJSONObject.Create;
      try
        Message.AddPair('jsonrpc', '2.0');
        Message.AddPair('method', 'window/showMessage');
        Message.AddPair('params', TJSONObject.Create.AddPair('type', TJSONNumber.Create(3)).AddPair('message', Text));
        Transport.WriteMessage(Message);
      finally
        Message.Free;
      end;
    end);
end;

procedure TShellSlashHost.MoveCursor(const AUri: string; const APosition: TTextPosition);
var
  Transport: IJsonRpcTransport;
  FileName: string;
  Target: TTextRange;
begin
  // Wie Notify erst nach der Antwort: Die Position gilt im Text mit den Änderungen.
  Transport := FTransport;
  FileName := TDocumentUris.ToPath(AUri);
  Target := TTextRange.Create(APosition, APosition);
  InLoop(
    procedure
    begin
      SendShowDocument(Transport, FileName, Target);
    end);
end;

/// <summary>Format einer neuen Datei (#299, #121): Kodierung der Datei AUri, sonst UTF-8 mit BOM; Zeilenende
/// wie in AText.</summary>
function NewFileFormat(const AUri, AText: string): TFileFormat;
var
  Sibling: string;
begin
  Result := TFileFormat.Create(TFileEncodingKind.Utf8Bom, TLineBreakStyle.CRLF);
  Sibling := '';
  if AUri <> '' then
  begin
    Sibling := TDocumentUris.ToPath(AUri);
  end;
  if (Sibling <> '') and FileExists(Sibling) then
    try
      TFileEncoding.LoadFromFile(Sibling, Result);
    except
      on EFileEncodingError do
        Result := TFileFormat.Create(TFileEncodingKind.Utf8Bom, TLineBreakStyle.CRLF);
    end;
  Result.MixedLineBreaks := False;
  if Pos(#13#10, AText) > 0 then
  begin
    Result.LineBreak := TLineBreakStyle.CRLF;
  end
  else if Pos(#10, AText) > 0 then
  begin
    Result.LineBreak := TLineBreakStyle.LF;
  end;
end;

// Dateinamen ohne Pfad, durch Komma getrennt.
function FileNames(const AFiles: TArray<TSlashFile>): string;
var
  mItem: TSlashFile;
  mNames: TArray<string>;
begin
  mNames := nil;
  for mItem in AFiles do
  begin
    mNames := mNames + [ExtractFileName(mItem.FileName)];
  end;
  Result := string.Join(', ', mNames);
end;

// Änderungen für workspace/applyEdit: neue Dateien und Ersetzen des bisherigen Inhalts.
function FileChanges(const AFiles: TArray<TSlashFile>): TArray<TLspFileChange>;
var
  mItem: TSlashFile;
  mFormat: TFileFormat;
  mOldText: string;
begin
  Result := nil;
  for mItem in AFiles do
  begin
    mOldText := '';
    if not mItem.New then
    begin
      mOldText := TFileEncoding.LoadFromFile(mItem.FileName, mFormat);
    end;
    Result := Result + [TLspFileChange.Create(mItem.FileName, mOldText, mItem.Text, mItem.New)];
  end;
end;

// Schreibt AFiles auf die Platte: neue Dateien im Format der Umgebung, bestehende in ihrem bisherigen.
procedure WriteToDisk(const AUri: string; const AFiles: TArray<TSlashFile>);
var
  mItem: TSlashFile;
  mFormat: TFileFormat;
begin
  for mItem in AFiles do
  begin
    if mItem.New then
    begin
      ForceDirectories(ExtractFileDir(mItem.FileName));
      mFormat := NewFileFormat(AUri, mItem.Text);
    end
    else
    begin
      TFileEncoding.LoadFromFile(mItem.FileName, mFormat);
    end;
    TFileEncoding.SaveToFile(mItem.FileName, mItem.Text, mFormat);
  end;
end;

// Zeigt AShow im Editor ('' = nichts).
function ShowAfter(const ATransport: IJsonRpcTransport; const AShow: string): TProc;
var
  mTransport: IJsonRpcTransport;
  mShow: string;
begin
  mTransport := ATransport;
  mShow := AShow;
  Result :=
    procedure
    begin
      if mShow <> '' then
      begin
        SendShowDocument(mTransport, mShow, TTextRange.Create(0, 0, 0, 0));
      end;
    end;
end;

// Lädt den Ordner zu AUri neu und zeigt danach AShow.
function ReloadAndShow(const AWorkspaceOf: TWorkspaceOfFunc; const AUri: string; const AShowAfter: TProc): TProc;
var
  mWorkspaceOf: TWorkspaceOfFunc;
  mUri: string;
  mShowAfter: TProc;
begin
  mWorkspaceOf := AWorkspaceOf;
  mUri := AUri;
  mShowAfter := AShowAfter;
  Result :=
    procedure
    var
      mTarget: TShellWorkspace;
    begin
      // In der Schleife neu suchen: Bis dahin kann der Ordner geschlossen worden sein.
      mTarget := mWorkspaceOf(mUri);
      if mTarget <> nil then
      begin
        mTarget.Reload;
      end;
      mShowAfter();
    end;
end;

procedure TShellSlashHost.WriteFiles(const AUri: string; const AFiles: TArray<TSlashFile>; const AShow: string);
var
  mDescription: string;
begin
  mDescription := FileNames(AFiles);
  try
    // In der IDE über das Plugin, damit neue und geänderte Dateien in ihren Puffern landen (#397).
    if ClientWrites then
    begin
      SendEdit(AUri, mDescription, TLspApplyEdit.Files(FileChanges(AFiles)), ShowAfter(FTransport, AShow));
      Exit;
    end;
    WriteToDisk(AUri, AFiles);
    FLogger.Info(Format('%s geschrieben (Schnellbefehl)', [TLogMarks.Text(mDescription)]));
  except
    on E: Exception do
    begin
      FLogger.Error(Format('%s ließ sich nicht schreiben: %s', [TLogMarks.Text(mDescription),
        TLogMarks.Text(E.Message)]));
      Exit;
    end;
  end;
  InLoop(ReloadAndShow(FSources.WorkspaceOf, AUri, ShowAfter(FTransport, AShow)));
end;

end.
