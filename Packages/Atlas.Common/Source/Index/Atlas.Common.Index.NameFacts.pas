unit Atlas.Common.Index.NameFacts;

// Antworten, die nur vom Index und einem Namen abhängen ("gibt es eine Property
// Count ohne write?", "ist TKurz ein Alias auf string[8]?"), über alle Units
// eines Arbeitsbereichs hinweg merken. Die Regeln fragten sie sonst je Unit
// neu, bei häufigen Namen gegen Tausende Treffer. Gilt für genau eine Fassung
// des Index: ISymbolIndex.Generation ist je Instanz eindeutig und zählt jede
// Änderung hoch, ein anderer Stand leert den Vorrat. Der Arbeitsbereich besitzt
// den Vorrat und reicht ihn über TRuleContext.NameFacts weiter; ohne ihn (Tests,
// einzelne Prüfung) rechnen die Regeln jedes Mal. Threadsicher.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract;

type
  TIndexNameFacts = class(TInterfacedObject, IIndexNameFacts)
  private
    FLock: TObject;
    FGeneration: Int64;
    FValues: TDictionary<string, Integer>;
  public
    constructor Create;
    destructor Destroy; override;
    function Lookup(const AIndex: ISymbolIndex; const AKey: string; const ACompute: TFunc<Integer>): Integer;
    /// <summary>Wie Lookup über AFacts; ohne Vorrat oder ohne Index rechnet ACompute jedes Mal.</summary>
    class function Get(const AFacts: IIndexNameFacts; const AIndex: ISymbolIndex; const AKey: string;
      const ACompute: TFunc<Integer>): Integer; static;
  end;

implementation

constructor TIndexNameFacts.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FValues := TDictionary<string, Integer>.Create;
end;

destructor TIndexNameFacts.Destroy;
begin
  FValues.Free;
  FLock.Free;
  inherited;
end;

function TIndexNameFacts.Lookup(const AIndex: ISymbolIndex; const AKey: string;
  const ACompute: TFunc<Integer>): Integer;
var
  mGeneration: Int64;
begin
  if AIndex = nil then
  begin
    Exit(ACompute());
  end;
  mGeneration := AIndex.Generation;
  TMonitor.Enter(FLock);
  try
    if mGeneration <> FGeneration then
    begin
      FValues.Clear;
      FGeneration := mGeneration;
    end
    else if FValues.TryGetValue(AKey, Result) then
    begin
      Exit;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  // Außerhalb der Sperre rechnen: ACompute fragt den Index, der seine eigene Sperre hat.
  Result := ACompute();
  TMonitor.Enter(FLock);
  try
    // Hat sich der Index inzwischen geändert, gehört die Antwort zum alten Stand.
    if AIndex.Generation = FGeneration then
    begin
      FValues.AddOrSetValue(AKey, Result);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TIndexNameFacts.Get(const AFacts: IIndexNameFacts; const AIndex: ISymbolIndex; const AKey: string;
  const ACompute: TFunc<Integer>): Integer;
begin
  if AFacts = nil then
  begin
    Result := ACompute();
  end
  else
  begin
    Result := AFacts.Lookup(AIndex, AKey, ACompute);
  end;
end;

end.
