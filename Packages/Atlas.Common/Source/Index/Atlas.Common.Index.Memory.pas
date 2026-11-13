unit Atlas.Common.Index.Memory;

// Speicherbudget des Symbolindex (#185).
//
// - TStringPool legt gleiche Zeichenketten (Container, Typnamen, Vorfahren,
//   Unit-Namen) nur einmal ab; Delphi-Strings teilen sich dann den Puffer.
// - TIndexMemory schätzt den Bedarf einer Unit und liefert ihre kompakte Form:
//   nur Symbole aus dem interface. Das reicht für Namensauflösung, Hover und
//   Navigation in andere Units; die uses-Listen bleiben für den Indexaufbau.
// - Verwendungen (#492) lassen sich vorher auslagern: WithoutUsages entfernt
//   sie aus dem Speicher; sie bleiben im Cache auf der Platte.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Common.Index.Contract;

type
  /// <summary>InternUnit und Count sind threadsicher (eigene Sperre, damit der Index große Units außerhalb seiner
  /// Sperre einordnen kann); Intern allein nicht.</summary>
  TStringPool = class
  private
    FStrings: TDictionary<string, string>;
    FLock: TCriticalSection;
    procedure InternUnitNow(var AUnit: TUnitIndex);
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
    /// <summary>Bedarf der Verwendungen allein.</summary>
    class function UsageBytes(const AUnit: TUnitIndex): Int64; static;
    /// <summary>Unit ohne Verwendungen im Speicher; UsagesOffloaded, wenn es welche gab.</summary>
    class function WithoutUsages(const AUnit: TUnitIndex): TUnitIndex; static;
  end;

implementation

uses
  Atlas.Common.Documents.Contract;

function StringBytes(const AValue: string): Int64;
begin
  // Kopf (Referenzzähler, Länge, Codepage) plus UTF-16-Zeichen und Endnull.
  if AValue = '' then
  begin
    Result := 0;
  end
  else
  begin
    Result := 12 + (Length(AValue) + 1) * SizeOf(Char);
  end;
end;

function ArrayBytes(const AValues: TArray<string>): Int64;
var
  mValue: string;
begin
  Result := 0;
  if Length(AValues) > 0 then
  begin
    Result := 16 + Length(AValues) * SizeOf(Pointer);
  end;
  for mValue in AValues do
  begin
    Inc(Result, StringBytes(mValue));
  end;
end;

{ TStringPool }

constructor TStringPool.Create;
begin
  inherited Create;
  FStrings := TDictionary<string, string>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TStringPool.Destroy;
begin
  FLock.Free;
  FStrings.Free;
  inherited;
end;

function TStringPool.Intern(const AValue: string): string;
begin
  if AValue = '' then
  begin
    Exit('');
  end;
  if not FStrings.TryGetValue(AValue, Result) then
  begin
    Result := AValue;
    FStrings.Add(Result, Result);
  end;
end;

procedure TStringPool.InternUnit(var AUnit: TUnitIndex);
begin
  FLock.Enter;
  try
    InternUnitNow(AUnit);
  finally
    FLock.Leave;
  end;
end;

procedure TStringPool.InternUnitNow(var AUnit: TUnitIndex);
var
  mIndex, mInner: Integer;
begin
  AUnit.UnitName := Intern(AUnit.UnitName);
  for mIndex := 0 to High(AUnit.InterfaceUses) do
  begin
    AUnit.InterfaceUses[mIndex] := Intern(AUnit.InterfaceUses[mIndex]);
  end;
  for mIndex := 0 to High(AUnit.ImplementationUses) do
  begin
    AUnit.ImplementationUses[mIndex] := Intern(AUnit.ImplementationUses[mIndex]);
  end;
  for mIndex := 0 to High(AUnit.Symbols) do
  begin
    // Die Vorfahren-Arrays teilt sich der Eintrag noch mit dem Aufrufer.
    AUnit.Symbols[mIndex].Ancestors := Copy(AUnit.Symbols[mIndex].Ancestors);
    AUnit.Symbols[mIndex].Name := Intern(AUnit.Symbols[mIndex].Name);
    AUnit.Symbols[mIndex].Container := Intern(AUnit.Symbols[mIndex].Container);
    AUnit.Symbols[mIndex].TypeName := Intern(AUnit.Symbols[mIndex].TypeName);
    AUnit.Symbols[mIndex].TypeArgs := Intern(AUnit.Symbols[mIndex].TypeArgs);
    AUnit.Symbols[mIndex].AncestorArgs := Copy(AUnit.Symbols[mIndex].AncestorArgs);
    for mInner := 0 to High(AUnit.Symbols[mIndex].AncestorArgs) do
    begin
      AUnit.Symbols[mIndex].AncestorArgs[mInner] := Intern(AUnit.Symbols[mIndex].AncestorArgs[mInner]);
    end;
    AUnit.Symbols[mIndex].TypeParams := Intern(AUnit.Symbols[mIndex].TypeParams);
    AUnit.Symbols[mIndex].FileName := Intern(AUnit.Symbols[mIndex].FileName);
    AUnit.Symbols[mIndex].Directives := Copy(AUnit.Symbols[mIndex].Directives);
    for mInner := 0 to High(AUnit.Symbols[mIndex].Directives) do
    begin
      AUnit.Symbols[mIndex].Directives[mInner] := Intern(AUnit.Symbols[mIndex].Directives[mInner]);
    end;
    AUnit.Symbols[mIndex].ParamTypes := Copy(AUnit.Symbols[mIndex].ParamTypes);
    for mInner := 0 to High(AUnit.Symbols[mIndex].ParamTypes) do
    begin
      AUnit.Symbols[mIndex].ParamTypes[mInner] := Intern(AUnit.Symbols[mIndex].ParamTypes[mInner]);
    end;
    for mInner := 0 to High(AUnit.Symbols[mIndex].Ancestors) do
    begin
      AUnit.Symbols[mIndex].Ancestors[mInner] := Intern(AUnit.Symbols[mIndex].Ancestors[mInner]);
    end;
  end;
end;

function TStringPool.Count: Integer;
begin
  FLock.Enter;
  try
    Result := FStrings.Count;
  finally
    FLock.Leave;
  end;
end;

{ TIndexMemory }

class function TIndexMemory.UnitBytes(const AUnit: TUnitIndex): Int64;
var
  mSymbol: TIndexSymbol;
begin
  Result := SizeOf(TUnitIndex) + StringBytes(AUnit.UnitName) + StringBytes(AUnit.FileName) +
    StringBytes(AUnit.Hash) + ArrayBytes(AUnit.InterfaceUses) + ArrayBytes(AUnit.ImplementationUses) +
    ArrayBytes(AUnit.Directives) + StringBytes(AUnit.DeprecatedText) + ArrayBytes(AUnit.Rationale);
  if Length(AUnit.Symbols) > 0 then
  begin
    Inc(Result, 16);
  end;
  for mSymbol in AUnit.Symbols do
  begin
    Inc(Result, SizeOf(TIndexSymbol) + StringBytes(mSymbol.Name) + StringBytes(mSymbol.Container) +
      StringBytes(mSymbol.TypeName) + ArrayBytes(mSymbol.Ancestors) + StringBytes(mSymbol.Signature) +
      StringBytes(mSymbol.Summary) + ArrayBytes(mSymbol.Directives) + StringBytes(mSymbol.DeprecatedText) +
      ArrayBytes(mSymbol.InlineRefs) + ArrayBytes(mSymbol.Resolutions) + ArrayBytes(mSymbol.Rationale));
  end;
  Inc(Result, UsageBytes(AUnit));
end;

class function TIndexMemory.UsageBytes(const AUnit: TUnitIndex): Int64;
var
  mUsage: TIndexUsage;
begin
  Result := 0;
  if Length(AUnit.Usages) > 0 then
  begin
    Result := 16;
  end;
  for mUsage in AUnit.Usages do
  begin
    Inc(Result, SizeOf(TIndexUsage) + StringBytes(mUsage.Name) + 16 + Length(mUsage.Positions) * SizeOf(TTextPosition));
  end;
end;

class function TIndexMemory.WithoutUsages(const AUnit: TUnitIndex): TUnitIndex;
begin
  Result := AUnit;
  if Length(AUnit.Usages) = 0 then
  begin
    Exit;
  end;
  Result.Usages := nil;
  Result.UsagesOffloaded := True;
end;

class function TIndexMemory.Compacted(const AUnit: TUnitIndex): TUnitIndex;
var
  mKept: TArray<TIndexSymbol>;
  mCount: Integer;
  mSymbol: TIndexSymbol;
begin
  Result := AUnit;
  Result.Compact := True;
  SetLength(mKept, Length(AUnit.Symbols));
  mCount := 0;
  for mSymbol in AUnit.Symbols do
  begin
    if mSymbol.InInterface then
    begin
      mKept[mCount] := mSymbol;
      Inc(mCount);
    end;
  end;
  SetLength(mKept, mCount);
  Result.Symbols := mKept;
end;

end.
