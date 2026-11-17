unit Atlas.IDE.Debug.VariablesLists;

// Zeilen des Fensters „Variablen“ (#853) und ihre Auswertung:
//   - Je Reiter (Autos, Lokal, Überwachung) eine TAtlasEvalList; seit dem
//     letzten Halt geänderte Werte markiert die Liste (BeginStop/SetResult).
//   - Slice wertet offene Knoten aus, zuerst im gezeigten Reiter, höchstens
//     cSliceMs lang, über TAtlasEvalSlices ohne Nebenwirkungen (eseNone:
//     keine Funktionsaufrufe, keine Getter). Ein verzögerter Wert (LLDB)
//     kommt über den Rückruf; nach cDeferredTimeoutMs gilt er als nicht
//     auswertbar.
//   - Die Suche (TAtlasVariableSearch) gilt für den gezeigten Reiter.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.Variables,
  Atlas.Core.Debug.EvalSlices;

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
    FSlices: TAtlasEvalSlices;
    FOnArrived: TProc;
    function GetList(ATab: TAtlasVariablesTab): TAtlasEvalList;
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
  Atlas.IDE.Debug.ThreadEvaluator,
  Atlas.UI.Debug.Evaluate.Strings;

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
  FSlices := TAtlasEvalSlices.Create(TAtlasIdeDebugThreadEvaluator.Create, cSliceMs, cDeferredTimeoutMs);
  FSlices.TimeoutText := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId.DebugEvaluateTimeout);
  FSlices.EmptyErrorText := FSlices.TimeoutText;
  FSlices.OnArrived := AOnArrived;
end;

destructor TAtlasIdeVariablesLists.Destroy;
var
  mTab: TAtlasVariablesTab;
begin
  // Zuerst die Auswertung: Ihr Rückruf kommt danach nicht mehr.
  FreeAndNil(FSlices);
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
  FSlices.Cancel;
end;

function TAtlasIdeVariablesLists.Busy: Boolean;
begin
  Result := FSlices.Waiting and not FSlices.Overdue;
  if FSlices.Waiting and not Result then
  begin
    // Nach dem Zeitlimit: nicht auswertbar, neu zeichnen.
    FSlices.Expire;
    if Assigned(FOnArrived) then
    begin
      FOnArrived();
    end;
  end;
end;

function TAtlasIdeVariablesLists.Slice(AFirst: TAtlasVariablesTab; const AFileName: string; ALine: Integer;
  out AChanged: Boolean): TAtlasVariablesStep;
var
  mLists: TArray<TAtlasEvalList>;
  mTab: TAtlasVariablesTab;
begin
  mLists := nil;
  for mTab in TabOrder(AFirst) do
  begin
    mLists := mLists + [FLists[mTab]];
  end;
  case FSlices.Slice(mLists, TAtlasEvalPlace.Create(AFileName, ALine, False), AChanged) of
    TAtlasEvalSliceStep.More:
      Result := TAtlasVariablesStep.More;
    TAtlasEvalSliceStep.Wait:
      Result := TAtlasVariablesStep.Wait;
    TAtlasEvalSliceStep.Stopped:
      Result := TAtlasVariablesStep.Stopped;
  else
    Result := TAtlasVariablesStep.Done;
  end;
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

end.
