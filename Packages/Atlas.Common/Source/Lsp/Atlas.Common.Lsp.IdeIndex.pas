unit Atlas.Common.Lsp.IdeIndex;

// Index für Hover, Vervollständigung und Parameterhilfe: der gemeinsame Index, ergänzt um die Ersatz-Units der
// IDE (Atlas.Common.Lsp.IdeUnits). Gefragt wird immer zuerst der gemeinsame Index; eine Ersatz-Unit zählt nur,
// wenn er die Unit nicht kennt. Ändern (AddUnit, RemoveFile, Budget) geht nur an den gemeinsamen Index.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Index.Contract;

type
  TIdeIndex = class(TInterfacedObject, ISymbolIndex)
  private
    FInner: ISymbolIndex;
    FIde: ISymbolIndex;
  public
    /// <summary>AInner ist der gemeinsame Index, AIde der Index der Ersatz-Units.</summary>
    constructor Create(const AInner, AIde: ISymbolIndex);
    procedure AddUnit(const AUnit: TUnitIndex);
    procedure RemoveFile(const AFileName: string);
    function FindUnit(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
    procedure AddUnitAliases(const AAliases: TArray<TPair<string, string>>);
    function FindFile(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    function FindSymbols(const AName: string): TArray<TSymbolLocation>;
    function HasSymbol(const AName: string; const AMatch: TSymbolMatch): Boolean;
    function Descendants(const ATypeName: string): TArray<TSymbolLocation>;
    function Units: TArray<TUnitIndex>;
    function UnavailableUnits: TArray<TUnitIndex>;
    function UnitCount: Integer;
    function SymbolCount: Integer;
    function MemoryBytes: Int64;
    function MemoryParts: TIndexMemoryParts;
    function CompactCount: Integer;
    function OffloadedCount: Integer;
    procedure SetBudget(ABytes: Int64);
    function Budget: Int64;
    function Generation: Int64;
  end;

implementation

/// <summary>AFirst, dann ASecond; ohne ASecond AFirst selbst (keine Kopie).</summary>
function Joined(const AFirst, ASecond: TArray<TSymbolLocation>): TArray<TSymbolLocation>;
var
  mIndex: Integer;
begin
  // Kopie: Result darf den Schnappschuss von AFirst nicht verändern.
  Result := Copy(AFirst);
  if Length(ASecond) = 0 then
  begin
    Exit;
  end;
  SetLength(Result, Length(AFirst) + Length(ASecond));
  for mIndex := 0 to High(ASecond) do
  begin
    Result[Length(AFirst) + mIndex] := ASecond[mIndex];
  end;
end;

constructor TIdeIndex.Create(const AInner, AIde: ISymbolIndex);
begin
  inherited Create;
  FInner := AInner;
  FIde := AIde;
end;

procedure TIdeIndex.AddUnit(const AUnit: TUnitIndex);
begin
  FInner.AddUnit(AUnit);
end;

procedure TIdeIndex.RemoveFile(const AFileName: string);
begin
  FInner.RemoveFile(AFileName);
end;

function TIdeIndex.FindUnit(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
begin
  Result := FInner.FindUnit(AUnitName, AUnit) or FIde.FindUnit(AUnitName, AUnit);
end;

procedure TIdeIndex.AddUnitAliases(const AAliases: TArray<TPair<string, string>>);
begin
  FInner.AddUnitAliases(AAliases);
end;

function TIdeIndex.FindFile(const AFileName: string; out AUnit: TUnitIndex): Boolean;
begin
  Result := FInner.FindFile(AFileName, AUnit) or FIde.FindFile(AFileName, AUnit);
end;

function TIdeIndex.FindSymbols(const AName: string): TArray<TSymbolLocation>;
begin
  Result := Joined(FInner.FindSymbols(AName), FIde.FindSymbols(AName));
end;

function TIdeIndex.HasSymbol(const AName: string; const AMatch: TSymbolMatch): Boolean;
begin
  Result := FInner.HasSymbol(AName, AMatch) or FIde.HasSymbol(AName, AMatch);
end;

function TIdeIndex.Descendants(const ATypeName: string): TArray<TSymbolLocation>;
begin
  Result := Joined(FInner.Descendants(ATypeName), FIde.Descendants(ATypeName));
end;

function TIdeIndex.Units: TArray<TUnitIndex>;
var
  mIde: TArray<TUnitIndex>;
  mInner, mIndex: Integer;
begin
  Result := FInner.Units;
  // Ohne Ersatz-Units den Schnappschuss des gemeinsamen Index unverändert weitergeben (keine Kopie).
  mIde := FIde.Units;
  if Length(mIde) = 0 then
  begin
    Exit;
  end;
  mInner := Length(Result);
  Result := Copy(Result);
  SetLength(Result, mInner + Length(mIde));
  for mIndex := 0 to High(mIde) do
  begin
    Result[mInner + mIndex] := mIde[mIndex];
  end;
end;

function TIdeIndex.UnavailableUnits: TArray<TUnitIndex>;
begin
  Result := FInner.UnavailableUnits;
end;

function TIdeIndex.UnitCount: Integer;
begin
  Result := FInner.UnitCount + FIde.UnitCount;
end;

function TIdeIndex.SymbolCount: Integer;
begin
  Result := FInner.SymbolCount + FIde.SymbolCount;
end;

function TIdeIndex.MemoryBytes: Int64;
begin
  Result := FInner.MemoryBytes;
end;

function TIdeIndex.MemoryParts: TIndexMemoryParts;
begin
  Result := FInner.MemoryParts;
end;

function TIdeIndex.CompactCount: Integer;
begin
  Result := FInner.CompactCount;
end;

function TIdeIndex.OffloadedCount: Integer;
begin
  Result := FInner.OffloadedCount;
end;

procedure TIdeIndex.SetBudget(ABytes: Int64);
begin
  FInner.SetBudget(ABytes);
end;

function TIdeIndex.Budget: Int64;
begin
  Result := FInner.Budget;
end;

function TIdeIndex.Generation: Int64;
begin
  // Beide zählen nur hoch: Die Summe ändert sich bei jeder Änderung an einem der beiden.
  Result := FInner.Generation + FIde.Generation;
end;

end.
