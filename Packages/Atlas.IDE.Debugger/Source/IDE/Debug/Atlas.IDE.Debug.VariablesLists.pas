unit Atlas.IDE.Debug.VariablesLists;

// Zeilen des Fensters „Variablen“ (#853) und ihre Auswertung:
//   - Je Reiter (Autos, Lokal, Überwachung) eine TAtlasEvalList; seit dem
//     letzten Halt geänderte Werte markiert die Liste (BeginStop/SetResult).
//   - Slice wertet offene Knoten aus, zuerst im gezeigten Reiter, höchstens
//     cSliceMs lang, über TAtlasIdeDebugValueRequest ohne Nebenwirkungen
//     (eseNone: keine Funktionsaufrufe, keine Getter). Ein verzögerter Wert
//     (LLDB) kommt über den Rückruf; nach cDeferredTimeoutMs gilt er als
//     nicht auswertbar.
//   - Die Suche (TAtlasVariableSearch) gilt für den gezeigten Reiter.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.Variables,
  Atlas.IDE.Debug.ValueRequest;

type
  {$SCOPEDENUMS ON}
  /// <summary>Ergebnis einer Zeitscheibe: alles ausgewertet, Zeit um, auf einen verzögerten Wert warten, kein
  /// angehaltener Prozess mehr.</summary>
  TAtlasVariablesStep = (Done, More, Wait, Stopped);
  {$SCOPEDENUMS OFF}

  TAtlasIdeVariablesLists = class
  public const
    cSliceMs = 30;
    cDeferredTimeoutMs = 2000;
  private
    FLists: array[TAtlasVariablesTab] of TAtlasEvalList;
    FSearch: TAtlasVariableSearch;
    FValues: TAtlasIdeDebugValueRequest;
    FOnArrived: TProc;
    /// <summary>Innerhalb von Evaluate: Der Rückruf kommt sofort, nicht verzögert.</summary>
    FEvaluating: Boolean;
    function GetList(ATab: TAtlasVariablesTab): TAtlasEvalList;
    procedure Put(ATab: TAtlasVariablesTab; const AKey, AText: string; AOk: Boolean);
    function EvaluateOne(ATab: TAtlasVariablesTab; ANode: TAtlasEvalNode; const AFileName: string;
      ALine: Integer): TAtlasVariablesStep;
  public
    /// <summary>AOnArrived: ein verzögerter Wert ist angekommen (neu zeichnen).</summary>
    constructor Create(const AOnArrived: TProc);
    destructor Destroy; override;
    /// <summary>Neuer Halt: alle Listen offen, Werte dieses Halts werden die vorigen.</summary>
    procedure BeginStop;
    /// <summary>Kein angehaltener Prozess: alles grau, die Werte bleiben für den Vergleich.</summary>
    procedure Unavailable;
    /// <summary>Laufende Auswertung verwerfen.</summary>
    procedure Cancel;
    /// <summary>Wartet noch ein verzögerter Wert (höchstens cDeferredTimeoutMs)?</summary>
    function Busy: Boolean;
    /// <summary>Offene Knoten an AFileName, ALine (0-basiert) auswerten, zuerst in AFirst; AChanged: mindestens
    /// ein Wert neu.</summary>
    function Slice(AFirst: TAtlasVariablesTab; const AFileName: string; ALine: Integer;
      out AChanged: Boolean): TAtlasVariablesStep;
    /// <summary>Hat ein Reiter noch offene Knoten?</summary>
    function HasPending: Boolean;
    property Lists[ATab: TAtlasVariablesTab]: TAtlasEvalList read GetList; default;
    property Search: TAtlasVariableSearch read FSearch;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Deadline,
  Atlas.UI.Debug.Strings;

/// <summary>Reiter in der Reihenfolge der Auswertung: AFirst, dann die übrigen.</summary>
function TabOrder(AFirst: TAtlasVariablesTab): TArray<TAtlasVariablesTab>;
var
  mTab: TAtlasVariablesTab;
  mCount: Integer;
begin
  // Ohne Array-Literal: [AFirst] läse Delphi als Menge.
  SetLength(Result, Ord(High(TAtlasVariablesTab)) + 1);
  Result[0] := AFirst;
  mCount := 1;
  for mTab := Low(TAtlasVariablesTab) to High(TAtlasVariablesTab) do
  begin
    if mTab <> AFirst then
    begin
      Result[mCount] := mTab;
      Inc(mCount);
    end;
  end;
end;

{ TAtlasIdeVariablesLists }

constructor TAtlasIdeVariablesLists.Create(const AOnArrived: TProc);
var
  mTab: TAtlasVariablesTab;
begin
  inherited Create;
  FOnArrived := AOnArrived;
  for mTab := Low(TAtlasVariablesTab) to High(TAtlasVariablesTab) do
  begin
    FLists[mTab] := TAtlasEvalList.Create;
  end;
  FSearch := TAtlasVariableSearch.Create;
  FValues := TAtlasIdeDebugValueRequest.Create(cDeferredTimeoutMs);
end;

destructor TAtlasIdeVariablesLists.Destroy;
var
  mTab: TAtlasVariablesTab;
begin
  // Zuerst die Auswertung: Ihr Rückruf kommt danach nicht mehr.
  FreeAndNil(FValues);
  FreeAndNil(FSearch);
  for mTab := Low(TAtlasVariablesTab) to High(TAtlasVariablesTab) do
  begin
    FreeAndNil(FLists[mTab]);
  end;
  FOnArrived := nil;
  inherited Destroy;
end;

function TAtlasIdeVariablesLists.GetList(ATab: TAtlasVariablesTab): TAtlasEvalList;
begin
  Result := FLists[ATab];
end;

procedure TAtlasIdeVariablesLists.BeginStop;
var
  mTab: TAtlasVariablesTab;
begin
  Cancel;
  for mTab := Low(TAtlasVariablesTab) to High(TAtlasVariablesTab) do
  begin
    FLists[mTab].BeginStop;
  end;
end;

procedure TAtlasIdeVariablesLists.Unavailable;
var
  mTab: TAtlasVariablesTab;
begin
  Cancel;
  for mTab := Low(TAtlasVariablesTab) to High(TAtlasVariablesTab) do
  begin
    FLists[mTab].Unavailable;
  end;
end;

procedure TAtlasIdeVariablesLists.Cancel;
begin
  FValues.Cancel;
end;

function TAtlasIdeVariablesLists.Busy: Boolean;
begin
  Result := FValues.Busy;
end;

function TAtlasIdeVariablesLists.HasPending: Boolean;
var
  mTab: TAtlasVariablesTab;
begin
  Result := False;
  for mTab := Low(TAtlasVariablesTab) to High(TAtlasVariablesTab) do
  begin
    if Length(FLists[mTab].Pending) > 0 then
    begin
      Exit(True);
    end;
  end;
end;

procedure TAtlasIdeVariablesLists.Put(ATab: TAtlasVariablesTab; const AKey, AText: string; AOk: Boolean);
var
  mNode: TAtlasEvalNode;
  mText: string;
begin
  // Über den Schlüssel: Der Knoten kann seit dem Start der Auswertung weg sein.
  mNode := FLists[ATab].Find(AKey);
  if mNode = nil then
  begin
    Exit;
  end;
  mText := AText;
  if not AOk and (mText = '') then
  begin
    mText := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateTimeout);
  end;
  FLists[ATab].SetResult(mNode, AOk, mText);
end;

/// <summary>Rückruf einer Auswertung an ALists, eigene Routine: fängt nur, was sie braucht.</summary>
function ValueDone(ALists: TAtlasIdeVariablesLists; ATab: TAtlasVariablesTab;
  const AKey: string): TAtlasDebugValueResult;
var
  mKey: string;
begin
  mKey := AKey;
  Result :=
    procedure(const AText: string; AOk: Boolean)
    begin
      ALists.Put(ATab, mKey, AText, AOk);
      if not ALists.FEvaluating and Assigned(ALists.FOnArrived) then
      begin
        ALists.FOnArrived();
      end;
    end;
end;

function TAtlasIdeVariablesLists.EvaluateOne(ATab: TAtlasVariablesTab; ANode: TAtlasEvalNode;
  const AFileName: string; ALine: Integer): TAtlasVariablesStep;
var
  mState: TAtlasDebugRequestState;
begin
  FEvaluating := True;
  try
    // ",r": Records mit Feldnamen, sonst zeigt der Baum nur [0], [1], … (Werte ohne Namen).
    mState := FValues.Evaluate(TAtlasEvalText.WithFieldNames(ANode.Expression), AFileName, ALine + 1, False,
      ValueDone(Self, ATab, ANode.Key));
  finally
    FEvaluating := False;
  end;
  case mState of
    TAtlasDebugRequestState.Waiting:
      Result := TAtlasVariablesStep.Wait;
    TAtlasDebugRequestState.NoProcess:
      Result := TAtlasVariablesStep.Stopped;
  else
    Result := TAtlasVariablesStep.Done;
  end;
end;

function TAtlasIdeVariablesLists.Slice(AFirst: TAtlasVariablesTab; const AFileName: string; ALine: Integer;
  out AChanged: Boolean): TAtlasVariablesStep;
var
  mStartedAt: UInt64;
  mTab: TAtlasVariablesTab;
  mNode: TAtlasEvalNode;
begin
  AChanged := False;
  mStartedAt := TAtlasTicks.Now;
  for mTab in TabOrder(AFirst) do
  begin
    for mNode in FLists[mTab].Pending do
    begin
      if TAtlasTicks.Since(mStartedAt) >= cSliceMs then
      begin
        Exit(TAtlasVariablesStep.More);
      end;
      Result := EvaluateOne(mTab, mNode, AFileName, ALine);
      if Result <> TAtlasVariablesStep.Done then
      begin
        Exit;
      end;
      AChanged := True;
    end;
  end;
  Result := TAtlasVariablesStep.Done;
end;

end.
