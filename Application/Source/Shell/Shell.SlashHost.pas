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
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.SlashCommands,
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

  TShellSlashHost = class(TInterfacedObject, ISlashHost)
  private
    FWorkspaceOf: TWorkspaceOfFunc;
    FReadText: TReadTextFunc;
    FHeaderTemplate: THeaderTemplateFunc;
    FTransport: IJsonRpcTransport;
    FLogger: ILogger;
    FRequestId: Integer;
    FDispatcher: TJsonRpcDispatcher;
    FClientAppliesEdits: TFunc<Boolean>;
    FRunInLoop: TJsonRpcScheduler;
    FSettingOf: TSlashSettingFunc;
    FTestUnitOf: TSlashTestUnitFunc;
    FRuleIdsOf: TSlashRuleIdsFunc;
    FUsesContextOf: TSlashUsesContextFunc;
    FFindingsOf: TSlashFindingsFunc;
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
    constructor Create(const AWorkspaceOf: TWorkspaceOfFunc; const AReadText: TReadTextFunc;
      const AHeaderTemplate: THeaderTemplateFunc; const ATransport: IJsonRpcTransport; const ALogger: ILogger;
      ADispatcher: TJsonRpcDispatcher = nil; const AClientAppliesEdits: TFunc<Boolean> = nil);
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
    property SettingOf: TSlashSettingFunc read FSettingOf write FSettingOf;
    /// <summary>Testunit zur Unit (/test, #295); ohne Zuweisung keine.</summary>
    property TestUnitOf: TSlashTestUnitFunc read FTestUnitOf write FTestUnitOf;
    /// <summary>Treffer der Prüfregeln in einer Zeile (/ignore, #297); ohne Zuweisung gilt jede Regel.</summary>
    property RuleIdsOf: TSlashRuleIdsFunc read FRuleIdsOf write FRuleIdsOf;
    /// <summary>Index und usesKeep (/sortuses, #297); ohne Zuweisung wird nur sortiert.</summary>
    property UsesContextOf: TSlashUsesContextFunc read FUsesContextOf write FUsesContextOf;
    /// <summary>Regeltreffer einer Zeile mit Erklärung und sicherer Korrektur (/fix, /explain, #300); ohne
    /// Zuweisung keine Prüfregeln.</summary>
    property FindingsOf: TSlashFindingsFunc read FFindingsOf write FFindingsOf;
    /// <summary>Stellt Arbeit in die Nachrichtenschleife (TJsonRpcConnection.Queue). Reload und SelectBuild
    /// laufen nur dort (Code-Review A-03); ohne Zuweisung (Tests) sofort.</summary>
    property RunInLoop: TJsonRpcScheduler read FRunInLoop write FRunInLoop;
  end;

implementation

uses
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.ApplyEdit;

constructor TShellSlashHost.Create(const AWorkspaceOf: TWorkspaceOfFunc; const AReadText: TReadTextFunc;
  const AHeaderTemplate: THeaderTemplateFunc; const ATransport: IJsonRpcTransport; const ALogger: ILogger;
  ADispatcher: TJsonRpcDispatcher; const AClientAppliesEdits: TFunc<Boolean>);
begin
  inherited Create;
  FWorkspaceOf := AWorkspaceOf;
  FReadText := AReadText;
  FHeaderTemplate := AHeaderTemplate;
  FTransport := ATransport;
  FLogger := ALogger;
  FDispatcher := ADispatcher;
  FClientAppliesEdits := AClientAppliesEdits;
end;

function TShellSlashHost.Project(const AUri: string; out AProject: TProjectInfo): Boolean;
var
  Workspace: TShellWorkspace;
begin
  Workspace := FWorkspaceOf(AUri);
  Result := (Workspace <> nil) and Workspace.Project(AProject);
end;

function TShellSlashHost.ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := FReadText(AFileName, AText);
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

procedure TShellSlashHost.SendEdit(const AUri, ADescription: string; AEdit: TJSONObject; const AAfter: TProc;
  AReload: Boolean);
var
  Reload: Boolean;
  Id, Uri, Description: string;
  Request: TJSONObject;
  Logger: ILogger;
  Transport: IJsonRpcTransport;
  WorkspaceOf: TWorkspaceOfFunc;
  After: TProc;
begin
  Id := Format('atlas/applyEdit/%d', [AtomicIncrement(FRequestId)]);
  // Nur lokale Werte einfangen: Die Antwort kommt in der Nachrichtenschleife (ExpectResponse).
  Logger := FLogger;
  Transport := FTransport;
  WorkspaceOf := FWorkspaceOf;
  Uri := AUri;
  Description := ADescription;
  After := AAfter;
  Reload := AReload;
  FDispatcher.ExpectResponse(Id,
    procedure(const AResponse: TJSONObject)
    var
      Reason: string;
      Target: TShellWorkspace;
      Message: TJSONObject;
    begin
      if TLspApplyEdit.ReadResult(AResponse, Reason) then
      begin
        Logger.Info(Format('%s geändert (Schnellbefehl, über den Editor)', [Description]));
        Target := nil;
        if Reload then
          Target := WorkspaceOf(Uri);
        if Target <> nil then
          Target.Reload;
        if Assigned(After) then
          After();
        Exit;
      end;
      Logger.Warning(Format('%s nicht geändert: %s', [Description, Reason]));
      Message := TJSONObject.Create;
      try
        Message.AddPair('jsonrpc', '2.0');
        Message.AddPair('method', 'window/showMessage');
        Message.AddPair('params', TJSONObject.Create.AddPair('type', TJSONNumber.Create(2))
          .AddPair('message', Format('Atlas: %s wurde nicht geändert (%s).', [Description, Reason])));
        Transport.WriteMessage(Message);
      finally
        Message.Free;
      end;
    end);
  Request := TLspApplyEdit.Request(Id, 'Atlas: Schnellbefehl', AEdit);
  try
    try
      FTransport.WriteMessage(Request);
    except
      FDispatcher.ForgetResponse(Id);
      raise;
    end;
  finally
    Request.Free;
  end;
end;

function TShellSlashHost.WriteThroughClient(const AUri, AFileName, AText: string): Boolean;
var
  OldText: string;
  FileFormat: TFileFormat;
begin
  Result := ClientWrites;
  if not Result then
    Exit;
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
    FRunInLoop(AWork)
  else
    AWork();
end;

procedure TShellSlashHost.WriteProject(const AUri, AText: string);
var
  Workspace: TShellWorkspace;
  Info: TProjectInfo;
  FileFormat: TFileFormat;
  WorkspaceOf: TWorkspaceOfFunc;
  Uri: string;
begin
  Workspace := FWorkspaceOf(AUri);
  if (Workspace = nil) or not Workspace.Project(Info) then
    Exit;
  try
    // In der IDE über das Plugin, nicht auf die Platte (#397).
    if WriteThroughClient(AUri, Info.FileName, AText) then
      Exit;
    // Kodierung und Zeilenumbrüche der vorhandenen Datei beibehalten.
    TFileEncoding.LoadFromFile(Info.FileName, FileFormat);
    TFileEncoding.SaveToFile(Info.FileName, AText, FileFormat);
    FLogger.Info(Format('%s geändert (Schnellbefehl)', [Info.FileName]));
  except
    on E: Exception do
    begin
      FLogger.Error(Format('%s ließ sich nicht schreiben: %s', [Info.FileName, E.Message]));
      Exit;
    end;
  end;
  // const-Parameter lassen sich nicht einfangen.
  WorkspaceOf := FWorkspaceOf;
  Uri := AUri;
  InLoop(
    procedure
    var
      Target: TShellWorkspace;
    begin
      // In der Schleife neu suchen: Bis dahin kann der Ordner geschlossen worden sein.
      Target := WorkspaceOf(Uri);
      if Target <> nil then
        Target.Reload;
    end);
end;

procedure TShellSlashHost.SelectBuild(const AUri, AConfig, APlatform: string);
var
  WorkspaceOf: TWorkspaceOfFunc;
  Logger: ILogger;
  Uri, Config, PlatformName: string;
begin
  // const-Parameter lassen sich nicht einfangen; Self auch nicht (der Host kann vorher frei werden).
  WorkspaceOf := FWorkspaceOf;
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
        Logger.Warning(Error);
    end);
end;

procedure TShellSlashHost.ShowDocument(const AFileName: string; const ASelection: TTextRange);
begin
  SendShowDocument(FTransport, AFileName, ASelection);
end;

function TShellSlashHost.HeaderTemplate(const AUri: string): string;
begin
  Result := FHeaderTemplate(AUri);
end;

function TShellSlashHost.Setting(const AUri, AName: string): string;
begin
  Result := '';
  if Assigned(FSettingOf) then
    Result := FSettingOf(AUri, AName);
end;

function TShellSlashHost.RuleIdsAt(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean;
begin
  AIds := nil;
  Result := Assigned(FRuleIdsOf) and FRuleIdsOf(AUri, AText, ALine, AIds);
end;

function TShellSlashHost.UsesContext(const AUri: string; out AContext: TUsesContext): Boolean;
begin
  AContext := Default(TUsesContext);
  Result := Assigned(FUsesContextOf) and FUsesContextOf(AUri, AContext);
end;

function TShellSlashHost.FindingsAt(const AUri, AText: string; ALine: Integer;
  out AFindings: TArray<TSlashFinding>): Boolean;
begin
  AFindings := nil;
  Result := Assigned(FFindingsOf) and FFindingsOf(AUri, AText, ALine, AFindings);
end;

function TShellSlashHost.TestUnit(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;
begin
  ATarget := Default(TSlashTestUnit);
  if not Assigned(FTestUnitOf) then
  begin
    ATarget.Reason := 'Testunits sind hier nicht verfügbar';
    Exit(False);
  end;
  Result := FTestUnitOf(AUri, AText, ATarget);
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
    Sibling := TDocumentUris.ToPath(AUri);
  if (Sibling <> '') and FileExists(Sibling) then
    try
      TFileEncoding.LoadFromFile(Sibling, Result);
    except
      on EFileEncodingError do
        Result := TFileFormat.Create(TFileEncodingKind.Utf8Bom, TLineBreakStyle.CRLF);
    end;
  Result.MixedLineBreaks := False;
  if Pos(#13#10, AText) > 0 then
    Result.LineBreak := TLineBreakStyle.CRLF
  else if Pos(#10, AText) > 0 then
    Result.LineBreak := TLineBreakStyle.LF;
end;

procedure TShellSlashHost.WriteFiles(const AUri: string; const AFiles: TArray<TSlashFile>; const AShow: string);
var
  Changes: TArray<TLspFileChange>;
  Item: TSlashFile;
  FileFormat: TFileFormat;
  OldText, Show, Uri, Description: string;
  Transport: IJsonRpcTransport;
  WorkspaceOf: TWorkspaceOfFunc;
  Names: TArray<string>;
  AfterEdit: TProc;
begin
  // const-Parameter lassen sich nicht einfangen.
  Transport := FTransport;
  Show := AShow;
  Names := nil;
  for Item in AFiles do
    Names := Names + [ExtractFileName(Item.FileName)];
  Description := string.Join(', ', Names);
  try
    // In der IDE über das Plugin, damit neue und geänderte Dateien in ihren Puffern landen (#397).
    if ClientWrites then
    begin
      Changes := nil;
      for Item in AFiles do
      begin
        OldText := '';
        if not Item.New then
          OldText := TFileEncoding.LoadFromFile(Item.FileName, FileFormat);
        Changes := Changes + [TLspFileChange.Create(Item.FileName, OldText, Item.Text, Item.New)];
      end;
      AfterEdit :=
        procedure
        begin
          if Show <> '' then
            SendShowDocument(Transport, Show, TTextRange.Create(0, 0, 0, 0));
        end;
      SendEdit(AUri, Description, TLspApplyEdit.Files(Changes), AfterEdit);
      Exit;
    end;
    for Item in AFiles do
    begin
      if Item.New then
      begin
        ForceDirectories(ExtractFileDir(Item.FileName));
        FileFormat := NewFileFormat(AUri, Item.Text);
      end
      else
        TFileEncoding.LoadFromFile(Item.FileName, FileFormat);
      TFileEncoding.SaveToFile(Item.FileName, Item.Text, FileFormat);
    end;
    FLogger.Info(Format('%s geschrieben (Schnellbefehl)', [Description]));
  except
    on E: Exception do
    begin
      FLogger.Error(Format('%s ließ sich nicht schreiben: %s', [Description, E.Message]));
      Exit;
    end;
  end;
  WorkspaceOf := FWorkspaceOf;
  Uri := AUri;
  InLoop(
    procedure
    var
      Target: TShellWorkspace;
    begin
      // In der Schleife neu suchen: Bis dahin kann der Ordner geschlossen worden sein.
      Target := WorkspaceOf(Uri);
      if Target <> nil then
        Target.Reload;
      if Show <> '' then
        SendShowDocument(Transport, Show, TTextRange.Create(0, 0, 0, 0));
    end);
end;

end.
