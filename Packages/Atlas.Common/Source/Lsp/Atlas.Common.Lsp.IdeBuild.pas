unit Atlas.Common.Lsp.IdeBuild;

// Build-Ergebnisse aus der IDE (#527, #528). Das IDE-Plugin meldet
// atlas/compileStarted, atlas/compileFinished (Ereignisse) und
// atlas/compilerMessages (Meldungen aus dem Meldungsfenster der IDE). Die
// Meldungen ersetzen die Compilermeldungen (source "dcc") für alle Dateien,
// wie ein eigener Compilerlauf (#40); der letzte Build bleibt für Abfragen
// (z. B. MCP, #556) stehen. Zeilen und Spalten kommen 1-basiert aus der IDE.
// Hintergrundprüfungen nach dem Speichern (#548, "background") ersetzen die
// Meldungen, zählen aber nicht als letzter Build des Benutzers.
// Laufende Compiles (#1247): Beginn und Ende je Projekt bzw. Gruppenlauf
// ("group") ergeben Compiling; OnCompiling meldet den Wechsel, damit die
// Projektprüfung solange pausiert. Das Ende eines Gruppenlaufs beendet alle.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
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
    /// <summary>Wer den Build angestoßen hat: '' = Benutzer, "mcp" = Claude Code über build_project (#261).</summary>
    RequestedBy: string;
  end;

  TIdeBuildMessagesEvent = reference to procedure(const AMessages: TArray<TCompilerMessage>);
  TIdeBuildChangedEvent = reference to procedure(const ABuild: TIdeBuild);
  TIdeBuildCompilingEvent = reference to procedure(ARunning: Boolean);

  TLspIdeBuild = class
  public const
    cStartedMethod = 'atlas/compileStarted';
    cFinishedMethod = 'atlas/compileFinished';
    cMessagesMethod = 'atlas/compilerMessages';
  private
    FLock: TObject;
    FLast: TIdeBuild;
    FOnMessages: TIdeBuildMessagesEvent;
    FOnChanged: TIdeBuildChangedEvent;
    FOnCompiling: TIdeBuildCompilingEvent;
    // Laufende Compiles: "group" bzw. Projektdatei in Kleinschreibung. Unter FLock.
    FRunning: TDictionary<string, Boolean>;
    procedure Changed;
    /// <summary>Compile AParams beginnt (ARunning) bzw. endet; meldet den Wechsel von Compiling.</summary>
    procedure Track(const AParams: TJSONValue; ARunning: Boolean);
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
    /// <summary>Der letzte Build hat sich geändert (nicht bei Hintergrundprüfungen, #548), z. B. zum Speichern
    /// (#556).</summary>
    property OnChanged: TIdeBuildChangedEvent read FOnChanged write FOnChanged;
    /// <summary>Läuft gerade ein Compile in der IDE (auch im Hintergrund)?</summary>
    function Compiling: Boolean;
    /// <summary>Compiling hat gewechselt (#1247).</summary>
    property OnCompiling: TIdeBuildCompilingEvent read FOnCompiling write FOnCompiling;
  end;

implementation

{ TLspIdeBuild }

constructor TLspIdeBuild.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FRunning := TDictionary<string, Boolean>.Create;
end;

destructor TLspIdeBuild.Destroy;
begin
  FRunning.Free;
  FLock.Free;
  inherited;
end;

procedure TLspIdeBuild.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  // Der Beginn zählt nur für Compiling (#1247); das Ende und die Meldungen tragen alles Nötige.
  ADispatcher.RegisterNotification(cStartedMethod,
    procedure(const AParams: TJSONValue)
    begin
      Track(AParams, True);
    end);
  ADispatcher.RegisterNotification(cFinishedMethod, HandleFinished);
  ADispatcher.RegisterNotification(cMessagesMethod, HandleMessages);
end;

function SeverityOf(const AText: string): TCompilerSeverity;
begin
  if SameText(AText, 'fatal') then
  begin
    Result := TCompilerSeverity.Fatal;
  end
  else if SameText(AText, 'error') then
  begin
    Result := TCompilerSeverity.Error;
  end
  else if SameText(AText, 'warning') then
  begin
    Result := TCompilerSeverity.Warning;
  end
  else
  begin
    Result := TCompilerSeverity.Hint;
  end;
end;

class function TLspIdeBuild.ParseMessages(const AParams: TJSONValue): TArray<TCompilerMessage>;
var
  mItems: TJSONArray;
  mValue: TJSONValue;
  mItem: TJSONObject;
  mMessage: TCompilerMessage;
begin
  Result := nil;
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<TJSONArray>('messages', mItems)) then
  begin
    Exit;
  end;
  for mValue in mItems do
  begin
    if not (mValue is TJSONObject) then
    begin
      Continue;
    end;
    mItem := TJSONObject(mValue);
    mMessage := Default(TCompilerMessage);
    mMessage.FileName := mItem.GetValue<string>('file', '');
    mMessage.Line := mItem.GetValue<Integer>('line', 0) - 1;
    mMessage.Column := mItem.GetValue<Integer>('column', 0) - 1;
    if mMessage.Line < 0 then
    begin
      mMessage.Column := -1;
    end;
    mMessage.Severity := SeverityOf(mItem.GetValue<string>('severity', ''));
    mMessage.Code := mItem.GetValue<string>('code', '');
    mMessage.Text := mItem.GetValue<string>('text', '');
    Result := Result + [mMessage];
  end;
end;

procedure TLspIdeBuild.HandleFinished(const AParams: TJSONValue);
var
  mParams: TJSONObject;
begin
  if not (AParams is TJSONObject) then
  begin
    Exit;
  end;
  Track(AParams, False);
  mParams := TJSONObject(AParams);
  if mParams.GetValue<Boolean>('background', False) then
  begin
    Exit;
  end;
  // Der Gruppenlauf hat kein Projekt; dann bleibt das Projekt des letzten Laufs.
  TMonitor.Enter(FLock);
  try
    FLast.Known := True;
    if mParams.GetValue<string>('project', '') <> '' then
    begin
      FLast.Project := mParams.GetValue<string>('project', '');
      FLast.Configuration := mParams.GetValue<string>('configuration', '');
      FLast.Platform := mParams.GetValue<string>('platform', '');
      FLast.RequestedBy := mParams.GetValue<string>('requestedBy', '');
    end;
    FLast.Kind := mParams.GetValue<string>('kind', FLast.Kind);
    FLast.Success := mParams.GetValue<Boolean>('success', False);
    FLast.DurationMs := mParams.GetValue<Int64>('durationMs', 0);
    FLast.FinishedAt := Now;
  finally
    TMonitor.Exit(FLock);
  end;
  Changed;
end;

procedure TLspIdeBuild.Changed;
begin
  if Assigned(FOnChanged) then
  begin
    FOnChanged(LastBuild);
  end;
end;

procedure TLspIdeBuild.HandleMessages(const AParams: TJSONValue);
var
  mMessages: TArray<TCompilerMessage>;
begin
  mMessages := ParseMessages(AParams);
  if (AParams is TJSONObject) and TJSONObject(AParams).GetValue<Boolean>('background', False) then
  begin
    if Assigned(FOnMessages) then
    begin
      FOnMessages(mMessages);
    end;
    Exit;
  end;
  TMonitor.Enter(FLock);
  try
    FLast.Known := True;
    FLast.Messages := mMessages;
    if AParams is TJSONObject then
    begin
      if TJSONObject(AParams).GetValue<string>('project', '') <> '' then
      begin
        FLast.Project := TJSONObject(AParams).GetValue<string>('project', '');
      end;
      FLast.Platform := TJSONObject(AParams).GetValue<string>('platform', FLast.Platform);
      FLast.Success := TJSONObject(AParams).GetValue<Boolean>('success', FLast.Success);
    end;
    if FLast.FinishedAt = 0 then
    begin
      FLast.FinishedAt := Now;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  if Assigned(FOnMessages) then
  begin
    FOnMessages(mMessages);
  end;
  Changed;
end;

procedure TLspIdeBuild.Track(const AParams: TJSONValue; ARunning: Boolean);
var
  mKey: string;
  mBefore, mAfter: Boolean;
begin
  if not (AParams is TJSONObject) then
  begin
    Exit;
  end;
  if TJSONObject(AParams).GetValue<Boolean>('group', False) then
  begin
    mKey := 'group';
  end
  else
  begin
    mKey := AnsiLowerCase(TJSONObject(AParams).GetValue<string>('project', ''));
  end;
  if mKey = '' then
  begin
    Exit;
  end;
  TMonitor.Enter(FLock);
  try
    mBefore := FRunning.Count > 0;
    if ARunning then
    begin
      FRunning.AddOrSetValue(mKey, True);
    end
    else if mKey = 'group' then
    begin
      // Ein Gruppenlauf endet erst nach allen Projekten; fehlt ein Projektende, endet es hier.
      FRunning.Clear;
    end
    else
    begin
      FRunning.Remove(mKey);
    end;
    mAfter := FRunning.Count > 0;
  finally
    TMonitor.Exit(FLock);
  end;
  if (mBefore <> mAfter) and Assigned(FOnCompiling) then
  begin
    FOnCompiling(mAfter);
  end;
end;

function TLspIdeBuild.Compiling: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FRunning.Count > 0;
  finally
    TMonitor.Exit(FLock);
  end;
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