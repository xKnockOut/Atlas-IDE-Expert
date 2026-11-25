unit Atlas.Common.Index.Extractor.Routines;

// Implementierung einer Routine im Rumpf der Unit und ihre Symbole im Index:
// die Deklaration (gleicher Name und Typ, bei Überladungen dieselben
// Parametertypen) und das Symbol der Implementierung selbst. Gemeinsam für
// Angaben, die der Extraktor aus Rümpfen an beide Symbole hängt: inline-Verweise
// (Atlas.Common.Index.Extractor.InlineRefs) und die Besitz-Zusammenfassung je
// Parameter (Atlas.Common.Index.Extractor.ParamOwnership).

interface

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract;

type
  /// <summary>Ändert ein Symbol an Ort und Stelle.</summary>
  TIndexSymbolChange = reference to procedure(var ASymbol: TIndexSymbol);

  TIndexRoutineSymbols = class
  private
    FSymbols: TList<TIndexSymbol>;
    /// <summary>Positionen der Methoden und Routinen in FSymbols je "typ.name" (klein), bis FIndexed
    /// eingetragen. Vorher suchte jede Implementierung alle Symbole ab: quadratisch in der Länge der Unit.
    /// </summary>
    FRoutines: TObjectDictionary<string, TList<Integer>>;
    FIndexed: Integer;
  public
    constructor Create(ASymbols: TList<TIndexSymbol>);
    destructor Destroy; override;
    /// <summary>Positionen der Routinen namens AName in AContainer; nil ohne.</summary>
    function RoutinesNamed(const AName, AContainer: string): TList<Integer>;
    /// <summary>Deklaration der Implementierung ANode: gleicher Name und Typ, bei Überladungen dieselben
    /// Parametertypen. -1 ohne, -2 bei mehrdeutigen Überladungen ohne Parameterliste in der Implementierung.
    /// </summary>
    function FindDeclaration(ANode: TSyntaxNode; const AName, AContainer: string): Integer;
    /// <summary>AChange auf die Deklaration AFound (ab 0) und das Symbol der Implementierung ANode anwenden.
    /// </summary>
    procedure Change(ANode: TSyntaxNode; const AName, AContainer: string; AFound: Integer;
      const AChange: TIndexSymbolChange);
    /// <summary>Teilt "TFoo.Bar" in Typ und Namen; ohne Punkt ist AContainer ''.</summary>
    class procedure SplitName(const AFullName: string; out AContainer, AName: string); static;
    property Symbols: TList<TIndexSymbol> read FSymbols;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Extractor.TypeText;

const
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_];

function RoutineKey(const AName, AContainer: string): string;
begin
  Result := LowerCase(AContainer) + '.' + LowerCase(AName);
end;

function SameParamTypes(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  mIndex := 0;
  while Result and (mIndex <= High(A)) do
  begin
    Result := SameText(A[mIndex], B[mIndex]);
    Inc(mIndex);
  end;
end;

/// <summary>Methode oder Routine AName im Typ AContainer?</summary>
function IsSameRoutine(const ASymbol: TIndexSymbol; const AName, AContainer: string): Boolean;
begin
  Result := (ASymbol.Kind in cRoutineKinds) and
    SameText(ASymbol.Name, AName) and SameText(ASymbol.Container, AContainer);
end;

{ TIndexRoutineSymbols }

constructor TIndexRoutineSymbols.Create(ASymbols: TList<TIndexSymbol>);
begin
  inherited Create;
  FSymbols := ASymbols;
  FRoutines := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
end;

destructor TIndexRoutineSymbols.Destroy;
begin
  FRoutines.Free;
  inherited Destroy;
end;

class procedure TIndexRoutineSymbols.SplitName(const AFullName: string; out AContainer, AName: string);
var
  mDot: Integer;
begin
  AName := AFullName;
  AContainer := '';
  mDot := AFullName.LastIndexOf('.');
  if mDot >= 0 then
  begin
    AContainer := AFullName.Substring(0, mDot);
    AName := AFullName.Substring(mDot + 1);
  end;
end;

function TIndexRoutineSymbols.RoutinesNamed(const AName, AContainer: string): TList<Integer>;
var
  mSymbol: TIndexSymbol;
  mKey: string;
  mList: TList<Integer>;
begin
  // Neu hinzugekommene Symbole nachtragen; die Positionen bleiben gleich (nur angehängt).
  while FIndexed < FSymbols.Count do
  begin
    mSymbol := FSymbols[FIndexed];
    if mSymbol.Kind in cRoutineKinds then
    begin
      mKey := RoutineKey(mSymbol.Name, mSymbol.Container);
      if not FRoutines.TryGetValue(mKey, mList) then
      begin
        mList := TList<Integer>.Create;
        FRoutines.Add(mKey, mList);
      end;
      mList.Add(FIndexed);
    end;
    Inc(FIndexed);
  end;
  if not FRoutines.TryGetValue(RoutineKey(AName, AContainer), Result) then
  begin
    Result := nil;
  end;
end;

function TIndexRoutineSymbols.FindDeclaration(ANode: TSyntaxNode; const AName, AContainer: string): Integer;
var
  mPosition, mMin, mMax: Integer;
  mTypes: TArray<string>;
  mSymbol: TIndexSymbol;
  mCandidates: TList<Integer>;
begin
  Result := -1;
  mCandidates := RoutinesNamed(AName, AContainer);
  if mCandidates = nil then
  begin
    Exit;
  end;
  TIndexTypeText.ParamInfo(ANode.FindChild(TSyntaxKind.RoutineHeader), mMin, mMax, mTypes);
  for mPosition in mCandidates do
  begin
    mSymbol := FSymbols[mPosition];
    if IsSameRoutine(mSymbol, AName, AContainer) and not (mSymbol.Range.StartPos = ANode.StartPos) and
      ((Length(mTypes) = 0) or SameParamTypes(mSymbol.ParamTypes, mTypes)) then
    begin
      if Result >= 0 then
      begin
        // Mehrdeutig (Überladungen ohne Parameterliste in der Implementierung).
        Exit(-2);
      end;
      Result := mPosition;
    end;
  end;
end;

procedure TIndexRoutineSymbols.Change(ANode: TSyntaxNode; const AName, AContainer: string; AFound: Integer;
  const AChange: TIndexSymbolChange);
var
  mPosition: Integer;
  mSymbol: TIndexSymbol;
  mCandidates: TList<Integer>;
begin
  if AFound >= 0 then
  begin
    mSymbol := FSymbols[AFound];
    AChange(mSymbol);
    FSymbols[AFound] := mSymbol;
  end;
  // Das Symbol der Implementierung steht unter demselben Namen und Typ, an der Stelle von ANode.
  mCandidates := RoutinesNamed(AName, AContainer);
  if mCandidates = nil then
  begin
    Exit;
  end;
  for mPosition in mCandidates do
  begin
    if (mPosition <> AFound) and (FSymbols[mPosition].Range.StartPos = ANode.StartPos) then
    begin
      mSymbol := FSymbols[mPosition];
      AChange(mSymbol);
      FSymbols[mPosition] := mSymbol;
    end;
  end;
end;

end.
