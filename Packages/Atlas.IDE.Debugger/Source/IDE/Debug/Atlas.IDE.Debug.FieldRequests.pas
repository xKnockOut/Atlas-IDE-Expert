unit Atlas.IDE.Debug.FieldRequests;

// Felder eines Ausdrucks aus dem Atlas-Index für die Fenster „Auswerten“
// (#784) und „Variablen“ (#853): atlas/expressionCompletion auf „Ausdruck.“
// im Hintergrund, die Antwort im Hauptthread über TAtlasMainThread (nach dem
// Abmelden des Moduls kommt nichts mehr an). Ohne Server, bei Zeitüberschreitung
// oder ohne Felder kommt nil. Den Text der Datei gleicht der Aufrufer vorher im
// Hauptthread ab: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
// Laufende Anfragen halten die Sitzung als rohen Zeiger: Wer die Anfragen
// freigibt, wartet sie ab (Destroy).

interface

uses
  System.Classes,
  System.Generics.Collections,
  Atlas.Core.Lsp.Session;

type
  /// <summary>Felder im Hauptthread; nil ohne Server oder ohne Felder.</summary>
  TAtlasDebugFieldsArrived = reference to procedure(const AFields: TArray<string>);

  TAtlasIdeDebugFieldRequests = class
  public const
    cTimeoutMs = 3000;
  private
    FThreads: TList<TThread>;
  public
    constructor Create;
    /// <summary>Wartet laufende Anfragen ab.</summary>
    destructor Destroy; override;
    /// <summary>Beendete Anfragen freigeben; mit AWait auch laufende (abwarten).</summary>
    procedure Reap(AWait: Boolean);
    /// <summary>Felder von AExpression („Ausdruck.“) an AFileName, ALine (0-basiert) über ASession holen; mit
    /// AWithProperties auch Eigenschaften.</summary>
    procedure Start(ASession: TLspSession; const AFileName: string; ALine: Integer; const AExpression: string;
      AWithProperties: Boolean; const AArrived: TAtlasDebugFieldsArrived);
    /// <summary>Die Anfrage selbst (im Hintergrund); nil, wenn der Server langsam oder weg ist.</summary>
    class function Query(ASession: TLspSession; const AFileName: string; ALine: Integer; const AExpression: string;
      AWithProperties: Boolean): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Debug.Evaluate;

/// <summary>AFields im Hauptthread an AArrived.</summary>
procedure Deliver(const AArrived: TAtlasDebugFieldsArrived; const AFields: TArray<string>);
begin
  TAtlasMainThread.Queue(TAtlasFeature.Debugger,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger,
        procedure
        begin
          AArrived(AFields);
        end);
    end);
end;

{ TAtlasIdeDebugFieldRequests }

constructor TAtlasIdeDebugFieldRequests.Create;
begin
  inherited Create;
  FThreads := TList<TThread>.Create;
end;

destructor TAtlasIdeDebugFieldRequests.Destroy;
begin
  if FThreads <> nil then
  begin
    Reap(True);
  end;
  FreeAndNil(FThreads);
  inherited Destroy;
end;

procedure TAtlasIdeDebugFieldRequests.Reap(AWait: Boolean);
var
  mIndex: Integer;
begin
  for mIndex := FThreads.Count - 1 downto 0 do
  begin
    if AWait or FThreads[mIndex].Finished then
    begin
      FThreads[mIndex].WaitFor;
      FThreads[mIndex].Free;
      FThreads.Delete(mIndex);
    end;
  end;
end;

class function TAtlasIdeDebugFieldRequests.Query(ASession: TLspSession; const AFileName: string; ALine: Integer;
  const AExpression: string; AWithProperties: Boolean): TArray<string>;
var
  mResponse: TJSONValue;
begin
  Result := nil;
  try
    mResponse := ASession.ExpressionCompletion(AFileName, ALine, AExpression, Length(AExpression), cTimeoutMs);
    try
      Result := TAtlasEvalText.FieldsOf(mResponse, AWithProperties);
    finally
      mResponse.Free;
    end;
  except
    // Server langsam oder weg: Der Aufrufer zerlegt den Ergebnis-String.
    Result := nil;
  end;
end;

procedure TAtlasIdeDebugFieldRequests.Start(ASession: TLspSession; const AFileName: string; ALine: Integer;
  const AExpression: string; AWithProperties: Boolean; const AArrived: TAtlasDebugFieldsArrived);
var
  mFileName, mExpression: string;
  mArrived: TAtlasDebugFieldsArrived;
  mWorker: TThread;
begin
  Reap(False);
  mFileName := AFileName;
  mExpression := AExpression;
  mArrived := AArrived;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    begin
      Deliver(mArrived, Query(ASession, mFileName, ALine, mExpression, AWithProperties));
    end);
  mWorker.FreeOnTerminate := False;
  FThreads.Add(mWorker);
  mWorker.Start;
end;

end.
