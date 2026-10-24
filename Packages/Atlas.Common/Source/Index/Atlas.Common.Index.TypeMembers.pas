unit Atlas.Common.Index.TypeMembers;

// Mitglieder eines Typs samt Vorfahren aus dem Index (#854), für die Prüfregel
// debug-display-placeholder und die Vervollständigung in Wertdarstellungen:
// Felder, Eigenschaften, Methoden, Konstanten und Klassenvariablen des Typs,
// dann die des Vorfahren usw. (der nähere zuerst, ohne doppelte Namen).
// Vorfahren sucht die Klasse erst in der eigenen Unit, dann im Index. Ist ein
// Vorfahr unbekannt, liefert Collect False (Aufrufer schweigen dann); TObject
// steht oft nicht im Index, seine bekannten Methoden ergänzt die Klasse.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract;

type
  TTypeMember = record
    Name: string;
    Kind: TIndexSymbolKind;
    /// <summary>Deklarierter Typ ('' bei Methoden ohne Ergebnis).</summary>
    TypeName: string;
    /// <summary>Typ, der das Mitglied deklariert.</summary>
    Container: string;
    /// <summary>0 = eigener Typ, 1 = Vorfahr …</summary>
    Depth: Integer;
  end;

  TTypeMembers = class
  public const
    MaxDepth = 32;
    RuleKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType];
    ClassKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType];
    MemberKinds = [TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Method,
      TIndexSymbolKind.Constructor_, TIndexSymbolKind.Constant, TIndexSymbolKind.Variable];
    /// <summary>Mitglieder von TObject, falls System nicht im Index steht.</summary>
    ObjectMembers: array[0..10] of string = ('ClassName', 'ClassType', 'ClassParent', 'ClassInfo', 'InstanceSize',
      'UnitName', 'UnitScope', 'QualifiedClassName', 'ToString', 'GetHashCode', 'Equals');
  public
    /// <summary>Mitglieder von AType (aus ALocal) und seinen Vorfahren; False, wenn ein Vorfahr unbekannt ist
    /// (AMembers enthält dann, was bis dahin bekannt war).</summary>
    class function Collect(const ALocal: TUnitIndex; const AIndex: ISymbolIndex; const AType: TIndexSymbol;
      out AMembers: TArray<TTypeMember>): Boolean; static;
    /// <summary>Gibt es AName (ohne Groß-/Kleinschreibung) unter AMembers?</summary>
    class function Contains(const AMembers: TArray<TTypeMember>; const AName: string): Boolean; static;
    /// <summary>Letzter Namensteil ohne Typargumente.</summary>
    class function ShortName(const ATypeName: string): string; static;
  end;

implementation

uses
  System.Generics.Collections;

class function TTypeMembers.ShortName(const ATypeName: string): string;
var
  Angle, Dot: Integer;
begin
  Result := Trim(ATypeName);
  Angle := Pos('<', Result);
  if Angle > 0 then
    Result := Copy(Result, 1, Angle - 1);
  Dot := LastDelimiter('.', Result);
  if Dot > 0 then
    Result := Copy(Result, Dot + 1, MaxInt);
end;

class function TTypeMembers.Contains(const AMembers: TArray<TTypeMember>; const AName: string): Boolean;
var
  Member: TTypeMember;
begin
  for Member in AMembers do
    if SameText(Member.Name, AName) then
      Exit(True);
  Result := False;
end;

/// <summary>Sucht die Klasse AName erst in ALocal, dann im Index.</summary>
function FindClass(const ALocal: TUnitIndex; const AIndex: ISymbolIndex; const AName: string;
  out AUnit: TUnitIndex; out ASymbol: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  for Symbol in ALocal.Symbols do
    if (Symbol.Kind in TTypeMembers.ClassKinds) and SameText(Symbol.Name, AName) then
    begin
      AUnit := ALocal;
      ASymbol := Symbol;
      Exit(True);
    end;
  Result := False;
  if AIndex = nil then
    Exit;
  for Location in AIndex.FindSymbols(AName) do
    if (Location.Symbol.Kind in TTypeMembers.ClassKinds) and AIndex.FindUnit(Location.UnitName, AUnit) then
    begin
      ASymbol := Location.Symbol;
      Exit(True);
    end;
end;

class function TTypeMembers.Collect(const ALocal: TUnitIndex; const AIndex: ISymbolIndex; const AType: TIndexSymbol;
  out AMembers: TArray<TTypeMember>): Boolean;
var
  Seen: TDictionary<string, Boolean>;
  Current: TIndexSymbol;
  Owner: TUnitIndex;
  Ancestor, Name: string;
  Depth: Integer;

  procedure AddMember(const AName, AContainer: string; AKind: TIndexSymbolKind; const ATypeName: string;
    ADepth: Integer);
  var
    Member: TTypeMember;
  begin
    if Seen.ContainsKey(LowerCase(AName)) then
      Exit;
    Seen.Add(LowerCase(AName), True);
    Member.Name := AName;
    Member.Kind := AKind;
    Member.TypeName := ATypeName;
    Member.Container := AContainer;
    Member.Depth := ADepth;
    AMembers := AMembers + [Member];
  end;

  procedure AddOf(const AUnit: TUnitIndex; const AQualified: string; ADepth: Integer);
  var
    Symbol: TIndexSymbol;
  begin
    for Symbol in AUnit.Symbols do
      if (Symbol.Kind in MemberKinds) and SameText(Symbol.Container, AQualified) then
        AddMember(Symbol.Name, AQualified, Symbol.Kind, Symbol.TypeName, ADepth);
  end;

begin
  AMembers := nil;
  Seen := TDictionary<string, Boolean>.Create;
  try
    AddOf(ALocal, AType.QualifiedName, 0);
    if not (AType.Kind in ClassKinds) then
      Exit(True);
    Current := AType;
    for Depth := 1 to MaxDepth do
    begin
      Ancestor := '';
      if Length(Current.Ancestors) > 0 then
        Ancestor := ShortName(Current.Ancestors[0]);
      if (Ancestor = '') or SameText(Ancestor, 'TObject') then
      begin
        for Name in ObjectMembers do
          AddMember(Name, 'TObject', TIndexSymbolKind.Method, '', Depth);
        Exit(True);
      end;
      if not FindClass(ALocal, AIndex, Ancestor, Owner, Current) then
        Exit(False);
      AddOf(Owner, Current.QualifiedName, Depth);
    end;
    Result := False;
  finally
    Seen.Free;
  end;
end;

end.
