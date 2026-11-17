unit Atlas.Core.Debug.EvalSlices;

// Auswertung der Zeilen von „Auswerten“ (#784) und „Variablen“ (#853) in
// Zeitscheiben, ohne Open Tools API. Den angehaltenen Thread vertritt der
// schmale Vertrag IAtlasDebugEvaluator (Auswerten, Verwerfen, Ändern); in
// der IDE steht IOTAThread dahinter (TAtlasIdeDebugThreadEvaluator), in den
// Tests eine Fälschung.
//   - Slice wertet die offenen Knoten der Listen der Reihe nach aus,
//     höchstens SliceMs lang, Ausdrücke mit ",r" (Records mit Feldnamen).
//   - Ein verzögerter Wert (LLDB) hält die Auswertung an: Waiting, bis er
//     über den Rückruf kommt; nach TimeoutMs gilt er als überfällig (Overdue)
//     und Expire schreibt die Zeitüberschreitung an die Zeile.
//   - Der Wert kommt über den Schlüssel an seinen Knoten: Ist die Zeile
//     inzwischen weg, fällt er weg. Drop verwirft eine laufende Auswertung,
//     wenn ihre Zeile entfernt wird; ein später Rückruf kommt nicht mehr an.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.EvaluateRows;

type
  /// <summary>Verzögert kommender Wert einer Auswertung.</summary>
  TAtlasDebugValueDone = reference to procedure(const AValue: TAtlasDebugValue);

  /// <summary>Auswertung im angehaltenen Thread.</summary>
  IAtlasDebugEvaluator = interface
    ['{3A27E153-140A-4972-9BE0-FC10ACB9CE65}']
    /// <summary>AExpression an AFileName, ALine (1-basiert) auswerten; ASideEffects erlaubt Aufrufe und Getter.
    /// Ergebnis Value oder Failed; Pending: Der Wert kommt einmal über ADone, außer nach Cancel; None: kein
    /// angehaltener Prozess.</summary>
    function Evaluate(const AExpression, AFileName: string; ALine: Integer; ASideEffects: Boolean;
      const ADone: TAtlasDebugValueDone): TAtlasDebugValue;
    /// <summary>Laufende verzögerte Auswertung verwerfen; ihr Rückruf kommt nicht mehr.</summary>
    procedure Cancel;
    /// <summary>AExpression an AFileName, ALine (1-basiert) auf ANewValue setzen. AResult: neuer Wert bzw.
    /// Fehlertext; leer, wenn der Debugger verzögert antwortet.</summary>
    function Modify(const AExpression, AFileName: string; ALine: Integer; const ANewValue: string;
      out AResult: string): Boolean;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Ergebnis einer Zeitscheibe: alles ausgewertet, Zeit um, auf einen verzögerten Wert warten, kein
  /// angehaltener Prozess mehr.</summary>
  TAtlasEvalSliceStep = (Done, More, Wait, Stopped);
  {$SCOPEDENUMS OFF}

  /// <summary>Ort der Auswertung: Datei und Zeile (0-basiert); ASideEffects erlaubt Aufrufe.</summary>
  TAtlasEvalPlace = record
    FileName: string;
    Line: Integer;
    SideEffects: Boolean;
    class function Create(const AFileName: string; ALine: Integer; ASideEffects: Boolean): TAtlasEvalPlace; static;
  end;

  TAtlasEvalSlices = class
  private
    FEvaluator: IAtlasDebugEvaluator;
    FSliceMs: Cardinal;
    FTimeoutMs: Cardinal;
    FUnavailable: TAtlasEvalUnavailable;
    FTimeoutText: string;
    FEmptyErrorText: string;
    FOnArrived: TProc;
    /// <summary>Liste und Schlüssel des Knotens, dessen verzögerter Wert aussteht ('' ohne).</summary>
    FWaitList: TAtlasEvalList;
    FWaitKey: string;
    FWaitAt: UInt64;
    /// <summary>Nummer der Auswertung; ein Rückruf mit älterer Nummer kommt zu spät.</summary>
    FRequest: Integer;
    procedure Put(AList: TAtlasEvalList; ANode: TAtlasEvalNode; const AValue: TAtlasDebugValue);
    procedure Arrived(ARequest: Integer; const AValue: TAtlasDebugValue);
    function EvaluateOne(AList: TAtlasEvalList; ANode: TAtlasEvalNode;
      const APlace: TAtlasEvalPlace): TAtlasEvalSliceStep;
  public
    constructor Create(const AEvaluator: IAtlasDebugEvaluator; ASliceMs, ATimeoutMs: Cardinal);
    destructor Destroy; override;
    /// <summary>Offene Knoten von ALists in dieser Reihenfolge auswerten; AChanged: mindestens ein Wert neu.
    /// </summary>
    function Slice(const ALists: TArray<TAtlasEvalList>; const APlace: TAtlasEvalPlace;
      out AChanged: Boolean): TAtlasEvalSliceStep;
    /// <summary>Wartet ein verzögerter Wert?</summary>
    function Waiting: Boolean;
    /// <summary>Wartet er länger als TimeoutMs?</summary>
    function Overdue: Boolean;
    /// <summary>Den verzögerten Wert aufgeben: Zeitüberschreitung an seiner Zeile.</summary>
    procedure Expire;
    /// <summary>Läuft die Auswertung der Zeile ARowKey von AList oder eines ihrer Felder: verwerfen.</summary>
    procedure Drop(AList: TAtlasEvalList; const ARowKey: string);
    /// <summary>Laufende Auswertung verwerfen.</summary>
    procedure Cancel;
    /// <summary>Kennzeichnung „kein Zugriff“ (#840) vor passenden Fehlertexten; leer ohne.</summary>
    property Unavailable: TAtlasEvalUnavailable read FUnavailable write FUnavailable;
    /// <summary>Text der Zeile nach Expire.</summary>
    property TimeoutText: string read FTimeoutText write FTimeoutText;
    /// <summary>Text eines Fehlers ohne Meldung des Debuggers; leer: bleibt leer.</summary>
    property EmptyErrorText: string read FEmptyErrorText write FEmptyErrorText;
    /// <summary>Ein verzögerter Wert ist angekommen (neu zeichnen).</summary>
    property OnArrived: TProc read FOnArrived write FOnArrived;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Deadline;

{ TAtlasEvalPlace }

class function TAtlasEvalPlace.Create(const AFileName: string; ALine: Integer;
  ASideEffects: Boolean): TAtlasEvalPlace;
begin
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.SideEffects := ASideEffects;
end;

{ TAtlasEvalSlices }

constructor TAtlasEvalSlices.Create(const AEvaluator: IAtlasDebugEvaluator; ASliceMs, ATimeoutMs: Cardinal);
begin
  inherited Create;
  FEvaluator := AEvaluator;
  FSliceMs := ASliceMs;
  FTimeoutMs := ATimeoutMs;
end;

destructor TAtlasEvalSlices.Destroy;
begin
  Cancel;
  FEvaluator := nil;
  FOnArrived := nil;
  inherited Destroy;
end;

procedure TAtlasEvalSlices.Put(AList: TAtlasEvalList; ANode: TAtlasEvalNode; const AValue: TAtlasDebugValue);
var
  mValue: TAtlasDebugValue;
begin
  mValue := AValue;
  if (mValue.State = TAtlasDebugValueState.Failed) and (mValue.Text = '') then
  begin
    mValue.Text := FEmptyErrorText;
  end;
  TAtlasEvalRows.PutValue(AList, ANode, mValue, FUnavailable);
end;

/// <summary>Rückruf einer Auswertung an ASlices, eigene Routine: fängt nur, was sie braucht.</summary>
function ValueDone(ASlices: TAtlasEvalSlices; ARequest: Integer): TAtlasDebugValueDone;
begin
  Result :=
    procedure(const AValue: TAtlasDebugValue)
    begin
      ASlices.Arrived(ARequest, AValue);
    end;
end;

procedure TAtlasEvalSlices.Arrived(ARequest: Integer; const AValue: TAtlasDebugValue);
var
  mNode: TAtlasEvalNode;
  mList: TAtlasEvalList;
begin
  // Sofortige Werte kommen über das Ergebnis von Evaluate, verworfene gar nicht.
  if not Waiting or (ARequest <> FRequest) then
  begin
    Exit;
  end;
  mList := FWaitList;
  // Über den Schlüssel: Der Knoten kann seit dem Start der Auswertung weg sein.
  mNode := mList.Find(FWaitKey);
  FWaitList := nil;
  FWaitKey := '';
  if mNode <> nil then
  begin
    Put(mList, mNode, AValue);
  end;
  if Assigned(FOnArrived) then
  begin
    FOnArrived();
  end;
end;

function TAtlasEvalSlices.EvaluateOne(AList: TAtlasEvalList; ANode: TAtlasEvalNode;
  const APlace: TAtlasEvalPlace): TAtlasEvalSliceStep;
var
  mValue: TAtlasDebugValue;
begin
  Inc(FRequest);
  // ",r": Records mit Feldnamen, sonst zeigt der Baum nur [0], [1], … (Werte ohne Namen).
  mValue := FEvaluator.Evaluate(TAtlasEvalText.WithFieldNames(ANode.Expression), APlace.FileName, APlace.Line + 1,
    APlace.SideEffects, ValueDone(Self, FRequest));
  case mValue.State of
    TAtlasDebugValueState.Pending:
      begin
        FWaitList := AList;
        FWaitKey := ANode.Key;
        FWaitAt := TAtlasTicks.Now;
        Result := TAtlasEvalSliceStep.Wait;
      end;
    TAtlasDebugValueState.None:
      Result := TAtlasEvalSliceStep.Stopped;
  else
    Put(AList, ANode, mValue);
    Result := TAtlasEvalSliceStep.Done;
  end;
end;

function TAtlasEvalSlices.Slice(const ALists: TArray<TAtlasEvalList>; const APlace: TAtlasEvalPlace;
  out AChanged: Boolean): TAtlasEvalSliceStep;
var
  mStartedAt: UInt64;
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
begin
  AChanged := False;
  if Waiting then
  begin
    Exit(TAtlasEvalSliceStep.Wait);
  end;
  mStartedAt := TAtlasTicks.Now;
  for mList in ALists do
  begin
    for mNode in mList.Pending do
    begin
      if TAtlasTicks.Since(mStartedAt) >= FSliceMs then
      begin
        Exit(TAtlasEvalSliceStep.More);
      end;
      Result := EvaluateOne(mList, mNode, APlace);
      if Result <> TAtlasEvalSliceStep.Done then
      begin
        Exit;
      end;
      AChanged := True;
    end;
  end;
  Result := TAtlasEvalSliceStep.Done;
end;

function TAtlasEvalSlices.Waiting: Boolean;
begin
  Result := FWaitKey <> '';
end;

function TAtlasEvalSlices.Overdue: Boolean;
begin
  Result := Waiting and (TAtlasTicks.Since(FWaitAt) >= FTimeoutMs);
end;

procedure TAtlasEvalSlices.Expire;
var
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
begin
  if not Waiting then
  begin
    Exit;
  end;
  mList := FWaitList;
  mNode := mList.Find(FWaitKey);
  Cancel;
  if mNode <> nil then
  begin
    mList.SetResult(mNode, False, FTimeoutText);
  end;
end;

procedure TAtlasEvalSlices.Drop(AList: TAtlasEvalList; const ARowKey: string);
begin
  if Waiting and (AList = FWaitList) and TAtlasEvalRows.Covers(ARowKey, FWaitKey) then
  begin
    Cancel;
  end;
end;

procedure TAtlasEvalSlices.Cancel;
begin
  Inc(FRequest);
  FWaitList := nil;
  FWaitKey := '';
  if FEvaluator <> nil then
  begin
    FEvaluator.Cancel;
  end;
end;

end.
