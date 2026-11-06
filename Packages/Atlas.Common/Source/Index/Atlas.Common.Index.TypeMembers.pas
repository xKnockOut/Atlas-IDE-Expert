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
    cMaxDepth = 32;
    cRuleKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType];
    cClassKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType];
    cMemberKinds = [TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Method,
      TIndexSymbolKind.Constructor_, TIndexSymbolKind.Constant, TIndexSymbolKind.Variable];
    /// <summary>Mitglieder von TObject, falls System nicht im Index steht.</summary>
    cObjectMembers: array[0..10] of string = ('ClassName', 'ClassType', 'ClassParent', 'ClassInfo', 'InstanceSize',
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
  mAngle, mDot: Integer;
begin
  Result := Trim(ATypeName);
  mAngle := Pos('<', Result);
  if mAngle > 0 then
  begin
    Result := Copy(Result, 1, mAngle - 1);
  end;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
end;

class function TTypeMembers.Contains(const AMembers: TArray<TTypeMember>; const AName: string): Boolean;
var
  mMember: TTypeMember;
begin
  for mMember in AMembers do
  begin
    if SameText(mMember.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Sucht die Klasse AName erst in ALocal, dann im Index.</summary>
function FindClass(const ALocal: TUnitIndex; const AIndex: ISymbolIndex; const AName: string;
  out AUnit: TUnitIndex; out ASymbol: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
  mLocation: TSymbolLocation;
begin
  for mSymbol in ALocal.Symbols do
  begin
    if (mSymbol.Kind in TTypeMembers.cClassKinds) and SameText(mSymbol.Name, AName) then
    begin
      AUnit := ALocal;
      ASymbol := mSymbol;
      Exit(True);
    end;
  end;
  Result := False;
  if AIndex = nil then
  begin
    Exit;
  end;
  for mLocation in AIndex.FindSymbols(AName) do
  begin
    if (mLocation.Symbol.Kind in TTypeMembers.cClassKinds) and AIndex.FindUnit(mLocation.UnitName, AUnit) then
    begin
      ASymbol := mLocation.Symbol;
      Exit(True);
    end;
  end;
end;

class function TTypeMembers.Collect(const ALocal: TUnitIndex; const AIndex: ISymbolIndex; const AType: TIndexSymbol;
  out AMembers: TArray<TTypeMember>): Boolean;
var
  mSeen: TDictionary<string, Boolean>;
  mCurrent: TIndexSymbol;
  mOwner: TUnitIndex;
  mAncestor, mName: string;
  mDepth: Integer;

  procedure AddMember(const AName, AContainer: string; AKind: TIndexSymbolKind; const ATypeName: string;
    ADepth: Integer);
  var
    mMember: TTypeMember;
  begin
    if mSeen.ContainsKey(LowerCase(AName)) then
    begin
      Exit;
    end;
    mSeen.Add(LowerCase(AName), True);
    mMember.Name := AName;
    mMember.Kind := AKind;
    mMember.TypeName := ATypeName;
    mMember.Container := AContainer;
    mMember.Depth := ADepth;
    AMembers := AMembers + [mMember];
  end;

  procedure AddOf(const AUnit: TUnitIndex; const AQualified: string; ADepth: Integer);
  var
    mSymbol: TIndexSymbol;
  begin
    for mSymbol in AUnit.Symbols do
    begin
      if (mSymbol.Kind in cMemberKinds) and SameText(mSymbol.Container, AQualified) then
      begin
        AddMember(mSymbol.Name, AQualified, mSymbol.Kind, mSymbol.TypeName, ADepth);
      end;
    end;
  end;

begin
  AMembers := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    AddOf(ALocal, AType.QualifiedName, 0);
    if not (AType.Kind in cClassKinds) then
    begin
      Exit(True);
    end;
    mCurrent := AType;
    for mDepth := 1 to cMaxDepth do
    begin
      mAncestor := '';
      if Length(mCurrent.Ancestors) > 0 then
      begin
        mAncestor := ShortName(mCurrent.Ancestors[0]);
      end;
      if (mAncestor = '') or SameText(mAncestor, 'TObject') then
      begin
        for mName in cObjectMembers do
        begin
          AddMember(mName, 'TObject', TIndexSymbolKind.Method, '', mDepth);
        end;
        Exit(True);
      end;
      if not FindClass(ALocal, AIndex, mAncestor, mOwner, mCurrent) then
      begin
        Exit(False);
      end;
      AddOf(mOwner, mCurrent.QualifiedName, mDepth);
    end;
    Result := False;
  finally
    mSeen.Free;
  end;
end;

end.
