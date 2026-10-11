unit Atlas.Common.Lsp.IdeBuild;

// Build-Ergebnisse aus der IDE (#527, #528). Das IDE-Plugin meldet
// atlas/compileStarted, atlas/compileFinished (Ereignisse) und
// atlas/compilerMessages (Meldungen aus dem Meldungsfenster der IDE). Die
// Meldungen ersetzen die Compilermeldungen (source "dcc") für alle Dateien,
// wie ein eigener Compilerlauf (#40); der letzte Build bleibt für Abfragen
// (z. B. MCP, #556) stehen. Zeilen und Spalten kommen 1-basiert aus der IDE.
// Hintergrundprüfungen nach dem Speichern (#548, "background") ersetzen die
// Meldungen, zählen aber nicht als letzter Build des Benutzers.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Compiler.Contract;

type
  TIdeBuild = record
    Known: Boolean;
    Project: string;
    Kind: string;
    Configuration: string;
    Platform: string;
    Success: Boolean;
    DurationMs: Int64;
    FinishedAt: TDateTime;
    Messages: TArray<TCompilerMessage>;
  end;

  TIdeBuildMessagesEvent = reference to procedure(const AMessages: TArray<TCompilerMessage>);
  TIdeBuildChangedEvent = reference to procedure(const ABuild: TIdeBuild);

  TLspIdeBuild = class
  public const
    StartedMethod = 'atlas/compileStarted';
    FinishedMethod = 'atlas/compileFinished';
    MessagesMethod = 'atlas/compilerMessages';
  private
    FLock: TObject;
    FLast: TIdeBuild;
    FOnMessages: TIdeBuildMessagesEvent;
    FOnChanged: TIdeBuildChangedEvent;
    procedure Changed;
    procedure HandleFinished(const AParams: TJSONValue);
    procedure HandleMessages(const AParams: TJSONValue);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Meldungen aus den Parametern von atlas/compilerMessages, 0-basiert.</summary>
    class function ParseMessages(const AParams: TJSONValue): TArray<TCompilerMessage>; static;
    /// <summary>Letzter Build aus der IDE; Known = False ohne.</summary>
    function LastBuild: TIdeBuild;
    property OnMessages: TIdeBuildMessagesEvent read FOnMessages write FOnMessages;
    /// <summary>Der letzte Build hat sich geändert (nicht bei Hintergrundprüfungen, #548), z. B. zum Speichern (#556).</summary>
    property OnChanged: TIdeBuildChangedEvent read FOnChanged write FOnChanged;
  end;

implementation

{ TLspIdeBuild }

constructor TLspIdeBuild.Create;
begin
  inherited Create;
  FLock := TObject.Create;
end;

destructor TLspIdeBuild.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TLspIdeBuild.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  // Beginn nur zur Kenntnis; das Ende und die Meldungen tragen alles Nötige.
  ADispatcher.RegisterNotification(StartedMethod,
    procedure(const AParams: TJSONValue)
    begin
    end);
  ADispatcher.RegisterNotification(FinishedMethod, HandleFinished);
  ADispatcher.RegisterNotification(MessagesMethod, HandleMessages);
end;

function SeverityOf(const AText: string): TCompilerSeverity;
begin
  if SameText(AText, 'fatal') then
    Result := TCompilerSeverity.Fatal
  else if SameText(AText, 'error') then
    Result := TCompilerSeverity.Error
  else if SameText(AText, 'warning') then
    Result := TCompilerSeverity.Warning
  else
    Result := TCompilerSeverity.Hint;
end;

class function TLspIdeBuild.ParseMessages(const AParams: TJSONValue): TArray<TCompilerMessage>;
var
  Items: TJSONArray;
  Value: TJSONValue;
  Item: TJSONObject;
  Message: TCompilerMessage;
begin
  Result := nil;
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<TJSONArray>('messages', Items)) then
    Exit;
  for Value in Items do
  begin
    if not (Value is TJSONObject) then
      Continue;
    Item := TJSONObject(Value);
    Message := Default(TCompilerMessage);
    Message.FileName := Item.GetValue<string>('file', '');
    Message.Line := Item.GetValue<Integer>('line', 0) - 1;
    Message.Column := Item.GetValue<Integer>('column', 0) - 1;
    if Message.Line < 0 then
      Message.Column := -1;
    Message.Severity := SeverityOf(Item.GetValue<string>('severity', ''));
    Message.Code := Item.GetValue<string>('code', '');
    Message.Text := Item.GetValue<string>('text', '');
    Result := Result + [Message];
  end;
end;

procedure TLspIdeBuild.HandleFinished(const AParams: TJSONValue);
var
  Params: TJSONObject;
begin
  if not (AParams is TJSONObject) then
    Exit;
  Params := TJSONObject(AParams);
  if Params.GetValue<Boolean>('background', False) then
    Exit;
  // Der Gruppenlauf hat kein Projekt; dann bleibt das Projekt des letzten Laufs.
  TMonitor.Enter(FLock);
  try
    FLast.Known := True;
    if Params.GetValue<string>('project', '') <> '' then
    begin
      FLast.Project := Params.GetValue<string>('project', '');
      FLast.Configuration := Params.GetValue<string>('configuration', '');
      FLast.Platform := Params.GetValue<string>('platform', '');
    end;
    FLast.Kind := Params.GetValue<string>('kind', FLast.Kind);
    FLast.Success := Params.GetValue<Boolean>('success', False);
    FLast.DurationMs := Params.GetValue<Int64>('durationMs', 0);
    FLast.FinishedAt := Now;
  finally
    TMonitor.Exit(FLock);
  end;
  Changed;
end;

procedure TLspIdeBuild.Changed;
begin
  if Assigned(FOnChanged) then
    FOnChanged(LastBuild);
end;

procedure TLspIdeBuild.HandleMessages(const AParams: TJSONValue);
var
  Messages: TArray<TCompilerMessage>;
begin
  Messages := ParseMessages(AParams);
  if (AParams is TJSONObject) and TJSONObject(AParams).GetValue<Boolean>('background', False) then
  begin
    if Assigned(FOnMessages) then
      FOnMessages(Messages);
    Exit;
  end;
  TMonitor.Enter(FLock);
  try
    FLast.Known := True;
    FLast.Messages := Messages;
    if AParams is TJSONObject then
    begin
      if TJSONObject(AParams).GetValue<string>('project', '') <> '' then
        FLast.Project := TJSONObject(AParams).GetValue<string>('project', '');
      FLast.Platform := TJSONObject(AParams).GetValue<string>('platform', FLast.Platform);
      FLast.Success := TJSONObject(AParams).GetValue<Boolean>('success', FLast.Success);
    end;
    if FLast.FinishedAt = 0 then
      FLast.FinishedAt := Now;
  finally
    TMonitor.Exit(FLock);
  end;
  if Assigned(FOnMessages) then
    FOnMessages(Messages);
  Changed;
end;

function TLspIdeBuild.LastBuild: TIdeBuild;
begin
  TMonitor.Enter(FLock);
  try
    Result := FLast;
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.