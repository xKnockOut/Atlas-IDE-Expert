unit Atlas.Core.Debug.ExceptionCapture;

// Aufnahme eines Halts wegen einer Exception (#517) ohne IDE, prüfbar (#1967): Ablauf von Stapel und Dialog
// (beide müssen fertig sein), Nachfragen beim verzögerten Stapel, Ersatzklasse, Ort aus dem Stapel und wie still
// fortgesetzt wird. Atlas.IDE.Debug.Exceptions fragt Debugger und Dialog und ruft diese Entscheidungen.

interface

uses
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.ExceptionBanner;

{$SCOPEDENUMS ON}

type
  /// <summary>Wie Atlas still fortsetzt: gar nicht, über „Fortsetzen“ im erkannten Dialog, ohne Dialog direkt am
  /// Prozess.</summary>
  TAtlasDebugCaptureResume = (None, ByDialog, ByProcess);

  /// <summary>Stand der Aufnahme des aktuellen Halts.</summary>
  TAtlasDebugCaptureState = record
    HasPending: Boolean;
    DialogDone: Boolean;
    StackDone: Boolean;
    Retries: Integer;
    /// <summary>Halt, den der Dialog schon vor der Meldung der Session ausgelöst hat; 0 = keiner.</summary>
    EarlyStop: Integer;
    /// <summary>Neue Sitzung bzw. Freigabe: nichts offen, kein vorweggenommener Halt.</summary>
    procedure Reset;
    /// <summary>Neue Aufnahme: Stapel und Dialog stehen aus.</summary>
    procedure Open;
    /// <summary>Stapel und Dialog nicht mehr abwarten (Weiterlaufen, neuer Halt).</summary>
    procedure Force;
    /// <summary>Offen und beides fertig: Aufnahme abschließen (danach nichts mehr offen).</summary>
    function Take: Boolean;
    /// <summary>Stapel kommt verzögert: noch einmal fragen, solange höchstens AMax Versuche.</summary>
    function RetryStack(AMax: Integer): Boolean;
  end;

  TAtlasDebugCapture = class
  public
    /// <summary>Klasse aus dem Zustandstext bzw. Ersatz: Fehler des Betriebssystems (AFault) oder unbekannt.
    /// </summary>
    class function ClassOrFallback(const AClass: string; AFault: Boolean; const AFaultText,
      AUnknownText: string): string; static;
    /// <summary>Stapel übernehmen: Ort ist der erste Rahmen mit Quelltext (mit AJustMyCode der erste eigene),
    /// sonst nur die Routine des obersten Rahmens.</summary>
    class procedure ApplyFrames(var AException: TAtlasDebugException; const AFrames: TAtlasDebugFrames;
      AJustMyCode: Boolean); static;
    /// <summary>Still fortsetzen, wenn AAuto es verlangt: über den Dialog, wenn einer erkannt ist.</summary>
    class function Resume(AAuto: TAtlasDebugAutoContinue; AHasDialog: Boolean): TAtlasDebugCaptureResume; static;
    /// <summary>Ort lässt sich merken: Projekt, Datei und Zeile bekannt.</summary>
    class function CanIgnoreLocation(const AProject, AFileName: string; ALine: Integer): Boolean; static;
  end;

implementation

uses
  Atlas.Core.Debug.OwnCode;

{ TAtlasDebugCaptureState }

procedure TAtlasDebugCaptureState.Reset;
begin
  HasPending := False;
  EarlyStop := 0;
end;

procedure TAtlasDebugCaptureState.Open;
begin
  HasPending := True;
  DialogDone := False;
  StackDone := False;
  Retries := 0;
end;

procedure TAtlasDebugCaptureState.Force;
begin
  DialogDone := True;
  StackDone := True;
end;

function TAtlasDebugCaptureState.Take: Boolean;
begin
  Result := HasPending and DialogDone and StackDone;
  if Result then
  begin
    HasPending := False;
  end;
end;

function TAtlasDebugCaptureState.RetryStack(AMax: Integer): Boolean;
begin
  Inc(Retries);
  Result := Retries <= AMax;
end;

{ TAtlasDebugCapture }

class function TAtlasDebugCapture.ClassOrFallback(const AClass: string; AFault: Boolean; const AFaultText,
  AUnknownText: string): string;
begin
  if AClass <> '' then
  begin
    Result := AClass;
  end
  else if AFault then
  begin
    Result := AFaultText;
  end
  else
  begin
    Result := AUnknownText;
  end;
end;

class procedure TAtlasDebugCapture.ApplyFrames(var AException: TAtlasDebugException;
  const AFrames: TAtlasDebugFrames; AJustMyCode: Boolean);
var
  mIndex: Integer;
begin
  AException.Frames := AFrames;
  mIndex := TAtlasDebugOwnCode.LocationIndex(AFrames, AJustMyCode);
  if mIndex >= 0 then
  begin
    AException.FileName := AFrames[mIndex].FileName;
    AException.Line := AFrames[mIndex].Line;
    AException.Routine := AFrames[mIndex].Routine;
  end
  else if AFrames <> nil then
  begin
    AException.Routine := AFrames[0].Routine;
  end;
end;

class function TAtlasDebugCapture.Resume(AAuto: TAtlasDebugAutoContinue;
  AHasDialog: Boolean): TAtlasDebugCaptureResume;
begin
  if AAuto = TAtlasDebugAutoContinue.None then
  begin
    Result := TAtlasDebugCaptureResume.None;
  end
  else if AHasDialog then
  begin
    Result := TAtlasDebugCaptureResume.ByDialog;
  end
  else
  begin
    Result := TAtlasDebugCaptureResume.ByProcess;
  end;
end;

class function TAtlasDebugCapture.CanIgnoreLocation(const AProject, AFileName: string; ALine: Integer): Boolean;
begin
  Result := (AProject <> '') and (AFileName <> '') and (ALine > 0);
end;

end.
