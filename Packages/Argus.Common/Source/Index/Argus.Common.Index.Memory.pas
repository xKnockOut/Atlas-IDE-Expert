unit Argus.Common.Index.Memory;

// Speicherbudget des Symbolindex (#185).
//
// - TStringPool legt gleiche Zeichenketten (Container, Typnamen, Vorfahren,
//   Unit-Namen) nur einmal ab; Delphi-Strings teilen sich dann den Puffer.
// - TIndexMemory schätzt den Bedarf einer Unit und liefert ihre kompakte Form:
//   nur Symbole aus dem interface. Das reicht für Namensauflösung, Hover und
//   Navigation in andere Units; die uses-Listen bleiben für den Indexaufbau.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Argus.Common.Index.Contract;

type
  /// <summary>Nicht threadsicher; der Index ruft ihn unter seiner Sperre.</summary>
  TStringPool = class
  private
    FStrings: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function Intern(const AValue: string): string;
    procedure InternUnit(var AUnit: TUnitIndex);
    function Count: Integer;
  end;

  TIndexMemory = class
  public
    /// <summary>Geschätzter Bedarf in Byte; geteilte Strings zählen bei jeder Verwendung.</summary>
    class function UnitBytes(const AUnit: TUnitIndex): Int64; static;
    class function Compacted(const AUnit: TUnitIndex): TUnitIndex; static;
  end;

implementation

function StringBytes(const AValue: string): Int64;
begin
  // Kopf (Referenzzähler, Länge, Codepage) plus UTF-16-Zeichen und Endnull.
  if AValue = '' then
    Result := 0
  else
    Result := 12 + (Length(AValue) + 1) * SizeOf(Char);
end;

function ArrayBytes(const AValues: TArray<string>): Int64;
var
  Value: string;
begin
  Result := 0;
  if Length(AValues) > 0 then
    Result := 16 + Length(AValues) * SizeOf(Pointer);
  for Value in AValues do
    Inc(Result, StringBytes(Value));
end;

{ TStringPool }

constructor TStringPool.Create;
begin
  inherited Create;
  FStrings := TDictionary<string, string>.Create;
end;

destructor TStringPool.Destroy;
begin
  FStrings.Free;
  inherited;
end;

function TStringPool.Intern(const AValue: string): string;
begin
  if AValue = '' then
    Exit('');
  if not FStrings.TryGetValue(AValue, Result) then
  begin
    Result := AValue;
    FStrings.Add(Result, Result);
  end;
end;

procedure TStringPool.InternUnit(var AUnit: TUnitIndex);
var
  Index, Inner: Integer;
begin
  AUnit.UnitName := Intern(AUnit.UnitName);
  for Index := 0 to High(AUnit.InterfaceUses) do
    AUnit.InterfaceUses[Index] := Intern(AUnit.InterfaceUses[Index]);
  for Index := 0 to High(AUnit.ImplementationUses) do
    AUnit.ImplementationUses[Index] := Intern(AUnit.ImplementationUses[Index]);
  for Index := 0 to High(AUnit.Symbols) do
  begin
    // Die Vorfahren-Arrays teilt sich der Eintrag noch mit dem Aufrufer.
    AUnit.Symbols[Index].Ancestors := Copy(AUnit.Symbols[Index].Ancestors);
    AUnit.Symbols[Index].Name := Intern(AUnit.Symbols[Index].Name);
    AUnit.Symbols[Index].Container := Intern(AUnit.Symbols[Index].Container);
    AUnit.Symbols[Index].TypeName := Intern(AUnit.Symbols[Index].TypeName);
    for Inner := 0 to High(AUnit.Symbols[Index].Ancestors) do
      AUnit.Symbols[Index].Ancestors[Inner] := Intern(AUnit.Symbols[Index].Ancestors[Inner]);
  end;
end;

function TStringPool.Count: Integer;
begin
  Result := FStrings.Count;
end;

{ TIndexMemory }

class function TIndexMemory.UnitBytes(const AUnit: TUnitIndex): Int64;
var
  Symbol: TIndexSymbol;
begin
  Result := SizeOf(TUnitIndex) + StringBytes(AUnit.UnitName) + StringBytes(AUnit.FileName) +
    StringBytes(AUnit.Hash) + ArrayBytes(AUnit.InterfaceUses) + ArrayBytes(AUnit.ImplementationUses);
  if Length(AUnit.Symbols) > 0 then
    Inc(Result, 16);
  for Symbol in AUnit.Symbols do
    Inc(Result, SizeOf(TIndexSymbol) + StringBytes(Symbol.Name) + StringBytes(Symbol.Container) +
      StringBytes(Symbol.TypeName) + ArrayBytes(Symbol.Ancestors));
end;

class function TIndexMemory.Compacted(const AUnit: TUnitIndex): TUnitIndex;
var
  Kept: TArray<TIndexSymbol>;
  Count: Integer;
  Symbol: TIndexSymbol;
begin
  Result := AUnit;
  Result.Compact := True;
  SetLength(Kept, Length(AUnit.Symbols));
  Count := 0;
  for Symbol in AUnit.Symbols do
    if Symbol.InInterface then
    begin
      Kept[Count] := Symbol;
      Inc(Count);
    end;
  SetLength(Kept, Count);
  Result.Symbols := Kept;
end;

end.
