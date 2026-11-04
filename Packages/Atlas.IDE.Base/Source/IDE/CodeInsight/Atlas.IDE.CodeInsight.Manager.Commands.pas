unit Atlas.IDE.CodeInsight.Manager.Commands;

// Befehle des Code Insight-Managers an den Server, dritte Stufe der Klassenkette: QueryStatusAsync fragt
// atlas.server.status im Hintergrund (#591); StopSession wartet auf eine laufende Abfrage, bevor es die Sitzung
// freigibt. RunCommandAsync (#66) schickt einen Befehl mit Argumenten im Hintergrund, etwa die Metriken des
// Projekts nach einem Build; RunCommandsAsync (#68) mehrere nacheinander in einem Hintergrundlauf. Bedienbefehle
// (#874) laufen im Hintergrund und antworten im Hauptthread.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.CodeInsight.Manager.Session;

type
  /// <summary>Befehle und Benachrichtigungen an den Server, im Hintergrund oder sofort.</summary>
  TAtlasCodeInsightCommands = class(TAtlasCodeInsightSession)
  protected
    FQueryRunning: Boolean;
    /// <summary>Befehl im Hintergrund (RunCommandAsync, #66).</summary>
    FCommandRunning: Boolean;
    /// <summary>Anzahl laufender Bedienbefehle im Hintergrund (ExecuteServerCommandAsync, #874).</summary>
    FServerCommands: Integer;
    /// <summary>Führt AWork mit ASession in einem eigenen Thread aus und ruft ADone im Hauptthread (#874).
    /// ASession nil: ADone(nil) sofort.</summary>
    procedure RunInBackground(ASession: TLspSession; const AWork: TFunc<TLspSession, TJSONValue>;
      const ADone: TProc<TJSONValue>);
  public
    /// <summary>Benachrichtigung an den Server, falls eine Sitzung läuft (#527); übernimmt AParams.
    /// Startet den Server dafür nicht.</summary>
    procedure NotifyServer(const AMethod: string; AParams: TJSONObject);
    /// <summary>Gespeichert: didSave an den Server, falls eine Sitzung läuft (Prüfung mit dcc).</summary>
    procedure NotifySaved(const AFileName: string);
    /// <summary>Befehl an den Server, ohne den Hauptthread warten zu lassen (#874; eine synchrone Fassung gibt es
    /// nicht mehr). Startet den Server bei Bedarf (im Hauptthread), fragt im Hintergrund und ruft ADone im
    /// Hauptthread auf, mit nil bei Fehler, Zeitlimit oder ohne Server. Den Wert gibt der Manager nach
    /// ADone frei. Mehrere Befehle dürfen gleichzeitig laufen; StopSession wartet auf sie.</summary>
    procedure ExecuteServerCommandAsync(const ACommand: string; ATimeoutMs: Cardinal; const ADone: TProc<TJSONValue>);
    /// <summary>Befehl mit Argumenten (JSON-Array) an den laufenden Server (#108); startet keinen Server.
    /// nil ohne Sitzung, bei Fehler oder Zeitlimit; das Ergebnis gehört dem Aufrufer.</summary>
    function RunServerCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>Wie RunServerCommand, aber im Hintergrund (#874): ADone im Hauptthread mit der Antwort oder nil;
    /// den Wert gibt der Manager nach ADone frei. Startet keinen Server.</summary>
    procedure RunServerCommandAsync(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
      const ADone: TProc<TJSONValue>);
    /// <summary>Anfrage AMethod (Parameter als JSON-Objekt) im Hintergrund an den laufenden Server (#1351), abbrechbar
    /// über ACancelled (aus dem Hintergrund-Thread gefragt); ADone bekommt die Antwort im Hauptthread (nil bei
    /// Fehler, Abbruch oder Zeitlimit). Startet keinen Server.</summary>
    procedure RunServerRequestAsync(const AMethod, AParamsJson: string; ATimeoutMs: Cardinal;
      const ACancelled: TFunc<Boolean>; const ADone: TProc<TJSONValue>);
    /// <summary>atlas.server.status im Hintergrund, nur bei laufender Sitzung und ohne laufende
    /// Abfrage; ADone bekommt das JSON ('' bei Fehler) im Hintergrund-Thread. False = nicht gestartet.</summary>
    function QueryStatusAsync(const ADone: TProc<string>): Boolean;
    /// <summary>Befehl mit Argumenten (JSON-Array) im Hintergrund an den laufenden Server (#66), nur ohne
    /// laufenden Hintergrundbefehl; startet keinen Server. ADone bekommt das Ergebnis als JSON ('' bei Fehler
    /// oder Zeitlimit) im Hintergrund-Thread. False = nicht gestartet.</summary>
    function RunCommandAsync(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
      const ADone: TProc<string>): Boolean;
    /// <summary>Mehrere Befehle nacheinander in einem Hintergrundlauf (#68), sonst wie RunCommandAsync; ATimeoutMs
    /// gilt je Befehl. ADone bekommt die Ergebnisse in derselben Reihenfolge ('' bei Fehler oder Zeitlimit).
    /// False = nicht gestartet oder ungleich viele Befehle und Argumente.</summary>
    function RunCommandsAsync(const ACommands, AArgumentsJson: TArray<string>; ATimeoutMs: Cardinal;
      const ADone: TProc<TArray<string>>): Boolean;
  end;

implementation

uses
  System.SyncObjs,
  Atlas.Core.Status.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread;

/// <summary>Antwort als JSON-Text; '' ohne Antwort. Gibt AAnswer frei.</summary>
function TakeJson(AAnswer: TJSONValue): string;
begin
  Result := '';
  try
    if AAnswer <> nil then
    begin
      Result := AAnswer.ToJSON;
    end;
  finally
    AAnswer.Free;
  end;
end;

/// <summary>Ein Befehl im Hintergrund; Fehler, Zeitlimit oder geschlossene Verbindung: ''.</summary>
function CommandJson(ASession: TLspSession; const ACommand, AArguments: string; ATimeoutMs: Cardinal): string;
var
  mAnswer: TJSONValue;
begin
  try
    mAnswer := ASession.RunCommand(ACommand, AArguments, ATimeoutMs);
  except
    on Exception do
    begin
      mAnswer := nil;
    end;
  end;
  Result := TakeJson(mAnswer);
end;

/// <summary>Befehle nacheinander; je Befehl die Antwort als JSON oder ''.</summary>
function CommandsJson(ASession: TLspSession; const ACommands, AArguments: TArray<string>;
  ATimeoutMs: Cardinal): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ACommands));
  for mIndex := 0 to High(ACommands) do
  begin
    Result[mIndex] := CommandJson(ASession, ACommands[mIndex], AArguments[mIndex], ATimeoutMs);
  end;
end;

/// <summary>Arbeit im Hintergrund; Fehler, Zeitlimit oder geschlossene Verbindung: Antwort „keine“ ('').</summary>
function WorkJson(ASession: TLspSession; const AWork: TFunc<TLspSession, TJSONValue>): string;
var
  mAnswer: TJSONValue;
begin
  try
    mAnswer := AWork(ASession);
  except
    on Exception do
    begin
      mAnswer := nil;
    end;
  end;
  Result := TakeJson(mAnswer);
end;

/// <summary>Antwort als Text in den Hauptthread: Verwirft TAtlasMainThread den Eintrag (Entladen), bleibt nichts
/// liegen. ADone bekommt den Wert und der Wert wird danach freigegeben.</summary>
procedure DeliverJson(const AJson: string; const ADone: TProc<TJSONValue>);
var
  mJson: string;
  mDone: TProc<TJSONValue>;
begin
  mJson := AJson;
  mDone := ADone;
  TAtlasMainThread.Queue(TAtlasFeature.Server,
    procedure
    var
      mValue: TJSONValue;
    begin
      mValue := nil;
      if mJson <> '' then
      begin
        mValue := TJSONObject.ParseJSONValue(mJson);
      end;
      try
        if Assigned(mDone) then
        begin
          mDone(mValue);
        end;
      finally
        mValue.Free;
      end;
    end);
end;

function TAtlasCodeInsightCommands.QueryStatusAsync(const ADone: TProc<string>): Boolean;
var
  mSession: TLspSession;
  mIdle: TEvent;
begin
  Result := False;
  if FQueryRunning or (ReadySession = nil) then
  begin
    Exit;
  end;
  FQueryRunning := True;
  FQueryIdle.ResetEvent;
  mSession := FSession;
  mIdle := FQueryIdle;
  FThreads.Start(
    procedure
    var
      mJson: string;
    begin
      try
        try
          mJson := TakeJson(mSession.ExecuteCommand(TAtlasStatusLines.StatusCommand, 5000));
          if Assigned(ADone) then
          begin
            ADone(mJson);
          end;
        except
          // Hintergrund-Thread: nie eine Ausnahme nach außen.
          on Exception do
          begin
          end;
        end;
      finally
        // Danach nichts mehr am Manager: StopSession wartet genau auf dieses Signal.
        FQueryRunning := False;
        mIdle.SetEvent;
      end;
    end);
  Result := True;
end;

function TAtlasCodeInsightCommands.RunCommandAsync(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
  const ADone: TProc<string>): Boolean;
var
  mDone: TProc<string>;
begin
  mDone := ADone;
  Result := RunCommandsAsync([ACommand], [AArgumentsJson], ATimeoutMs,
    procedure(AAnswers: TArray<string>)
    begin
      if Assigned(mDone) then
      begin
        mDone(AAnswers[0]);
      end;
    end);
end;

function TAtlasCodeInsightCommands.RunCommandsAsync(const ACommands, AArgumentsJson: TArray<string>;
  ATimeoutMs: Cardinal; const ADone: TProc<TArray<string>>): Boolean;
var
  mSession: TLspSession;
  mIdle: TEvent;
  mCommands, mArguments: TArray<string>;
  mTimeout: Cardinal;
  mDone: TProc<TArray<string>>;
begin
  Result := False;
  if (Length(ACommands) = 0) or (Length(ACommands) <> Length(AArgumentsJson)) or FCommandRunning or
    (ReadySession = nil) then
  begin
    Exit;
  end;
  FCommandRunning := True;
  FCommandIdle.ResetEvent;
  mSession := FSession;
  mIdle := FCommandIdle;
  mCommands := Copy(ACommands);
  mArguments := Copy(AArgumentsJson);
  mTimeout := ATimeoutMs;
  mDone := ADone;
  FThreads.Start(
    procedure
    var
      mAnswers: TArray<string>;
    begin
      try
        try
          mAnswers := CommandsJson(mSession, mCommands, mArguments, mTimeout);
          if Assigned(mDone) then
          begin
            mDone(mAnswers);
          end;
        except
          // Hintergrund-Thread: nie eine Ausnahme nach außen.
          on Exception do
          begin
          end;
        end;
      finally
        // Danach nichts mehr am Manager: StopSession wartet genau auf dieses Signal.
        FCommandRunning := False;
        mIdle.SetEvent;
      end;
    end);
  Result := True;
end;

procedure TAtlasCodeInsightCommands.ExecuteServerCommandAsync(const ACommand: string; ATimeoutMs: Cardinal;
  const ADone: TProc<TJSONValue>);
var
  mCommand: string;
  mTimeout: Cardinal;
begin
  mCommand := ACommand;
  mTimeout := ATimeoutMs;
  // Start gehört dem Hauptthread (A-01); ohne Server gleich die Antwort „keine“.
  RunInBackground(SessionOrNil,
    function(ASession: TLspSession): TJSONValue
    begin
      Result := ASession.ExecuteCommand(mCommand, mTimeout);
    end, ADone);
end;

procedure TAtlasCodeInsightCommands.RunServerCommandAsync(const ACommand, AArgumentsJson: string;
  ATimeoutMs: Cardinal; const ADone: TProc<TJSONValue>);
var
  mCommand, mArguments: string;
  mTimeout: Cardinal;
begin
  mCommand := ACommand;
  mArguments := AArgumentsJson;
  mTimeout := ATimeoutMs;
  RunInBackground(RunningSession,
    function(ASession: TLspSession): TJSONValue
    begin
      Result := ASession.RunCommand(mCommand, mArguments, mTimeout);
    end, ADone);
end;

procedure TAtlasCodeInsightCommands.RunServerRequestAsync(const AMethod, AParamsJson: string; ATimeoutMs: Cardinal;
  const ACancelled: TFunc<Boolean>; const ADone: TProc<TJSONValue>);
var
  mMethod, mParams: string;
  mTimeout: Cardinal;
  mCancelled: TFunc<Boolean>;
begin
  mMethod := AMethod;
  mParams := AParamsJson;
  mTimeout := ATimeoutMs;
  mCancelled := ACancelled;
  RunInBackground(RunningSession,
    function(ASession: TLspSession): TJSONValue
    begin
      Result := ASession.RunRequest(mMethod, mParams, mTimeout, mCancelled);
    end, ADone);
end;

procedure TAtlasCodeInsightCommands.RunInBackground(ASession: TLspSession;
  const AWork: TFunc<TLspSession, TJSONValue>; const ADone: TProc<TJSONValue>);
var
  mSession: TLspSession;
  mIdle: TEvent;
  mWork: TFunc<TLspSession, TJSONValue>;
  mDone: TProc<TJSONValue>;
begin
  mDone := ADone;
  mSession := ASession;
  if mSession = nil then
  begin
    if Assigned(mDone) then
    begin
      mDone(nil);
    end;
    Exit;
  end;
  mWork := AWork;
  if AtomicIncrement(FServerCommands) = 1 then
  begin
    FServerCommandsIdle.ResetEvent;
  end;
  mIdle := FServerCommandsIdle;
  FThreads.Start(
    procedure
    begin
      try
        DeliverJson(WorkJson(mSession, mWork), mDone);
      finally
        // Danach nichts mehr am Manager: StopSession wartet genau auf dieses Signal.
        if AtomicDecrement(FServerCommands) = 0 then
        begin
          mIdle.SetEvent;
        end;
      end;
    end);
end;

function TAtlasCodeInsightCommands.RunServerCommand(const ACommand, AArgumentsJson: string;
  ATimeoutMs: Cardinal): TJSONValue;
var
  mSession: TLspSession;
begin
  Result := nil;
  mSession := RunningSession;
  if mSession = nil then
  begin
    Exit;
  end;
  try
    Result := mSession.RunCommand(ACommand, AArgumentsJson, ATimeoutMs);
  except
    on E: Exception do
    begin
      Diagnose('Befehl ' + ACommand + ' fehlgeschlagen: ' + E.ClassName);
    end;
  end;
end;

procedure TAtlasCodeInsightCommands.NotifySaved(const AFileName: string);
begin
  if (FSession = nil) or not FSession.Initialized then
  begin
    Exit;
  end;
  try
    FSession.Saved(AFileName);
  except
    on E: Exception do
    begin
      Diagnose('didSave nicht gesendet: ' + E.Message);
    end;
  end;
end;

procedure TAtlasCodeInsightCommands.NotifyServer(const AMethod: string; AParams: TJSONObject);
begin
  // Nur eine laufende Sitzung; für eine Meldung startet der Server nicht.
  if (FSession = nil) or not FSession.Initialized then
  begin
    AParams.Free;
    Exit;
  end;
  try
    FSession.Notify(AMethod, AParams);
  except
    on E: Exception do
    begin
      Diagnose(Format('%s nicht gesendet: %s', [AMethod, E.Message]));
    end;
  end;
end;

end.
