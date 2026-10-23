unit Atlas.Common.Index.TypeMembers.Tests;

// Tests von TTypeMembers (#854): eigene Mitglieder zuerst, Vorfahren aus Unit
// und Index, TObject ohne Index, unbekannter Vorfahr, Records.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypeMembersTests = class
  public
    [Test]
    procedure OwnMembersThenAncestors;
    [Test]
    procedure UnknownAncestorIsReported;
    [Test]
    procedure RecordHasNoAncestors;
    [Test]
    procedure ShortName;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.TypeMembers;

const
  Kunden =
    'unit Kunden;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TKunde = class(TPerson)'#10 +
    '  private'#10 +
    '    FNr: Integer;'#10 +
    '  public'#10 +
    '    function Saldo: Double;'#10 +
    '    property Nr: Integer read FNr;'#10 +
    '  end;'#10 +
    '  TFremd = class(TUnbekannt)'#10 +
    '    X: Integer;'#10 +
    '  end;'#10 +
    '  TPunkt = record'#10 +
    '    X, Y: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TKunde.Saldo: Double;'#10 +
    'begin'#10 +
    '  Result := 0;'#10 +
    'end;'#10 +
    'end.';

function TypeOf(const AUnit: TUnitIndex; const AName: string): TIndexSymbol;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
    if Symbol.Name = AName then
      Exit(Symbol);
  Result := Default(TIndexSymbol);
end;

function Names(const AMembers: TArray<TTypeMember>): string;
var
  Member: TTypeMember;
begin
  Result := '';
  for Member in AMembers do
    Result := Result + Member.Name + ':' + IntToStr(Member.Depth) + ' ';
end;

procedure TTypeMembersTests.OwnMembersThenAncestors;
var
  Index: ISymbolIndex;
  Local: TUnitIndex;
  Members: TArray<TTypeMember>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Basis;'#10'interface'#10'type'#10'  TPerson = class'#10 +
    '    Name: string;'#10'    Nr: Integer;'#10'  end;'#10'implementation'#10'end.', 'Basis.pas', nil));
  Local := TIndexExtractor.ExtractText(Kunden, 'Kunden.pas', nil);
  Assert.IsTrue(TTypeMembers.Collect(Local, Index, TypeOf(Local, 'TKunde'), Members));
  Assert.IsTrue(Names(Members).StartsWith('FNr:0 Saldo:0 Nr:0 Name:1 '), Names(Members));
  // Nr nur einmal: die eigene Eigenschaft verdeckt das Feld des Vorfahren.
  Assert.AreEqual(1, Integer(Length((' ' + Names(Members)).Split([' Nr:'])) - 1));
  Assert.IsTrue(TTypeMembers.Contains(Members, 'classname'));
  Assert.IsTrue(TTypeMembers.Contains(Members, 'NAME'));
  Assert.IsFalse(TTypeMembers.Contains(Members, 'Ort'));
end;

procedure TTypeMembersTests.UnknownAncestorIsReported;
var
  Local: TUnitIndex;
  Members: TArray<TTypeMember>;
begin
  Local := TIndexExtractor.ExtractText(Kunden, 'Kunden.pas', nil);
  Assert.IsFalse(TTypeMembers.Collect(Local, nil, TypeOf(Local, 'TFremd'), Members));
  Assert.AreEqual('X:0 ', Names(Members));
  Assert.IsFalse(TTypeMembers.Collect(Local, nil, TypeOf(Local, 'TKunde'), Members), 'TPerson ohne Index');
end;

procedure TTypeMembersTests.RecordHasNoAncestors;
var
  Local: TUnitIndex;
  Members: TArray<TTypeMember>;
begin
  Local := TIndexExtractor.ExtractText(Kunden, 'Kunden.pas', nil);
  Assert.IsTrue(TTypeMembers.Collect(Local, nil, TypeOf(Local, 'TPunkt'), Members));
  Assert.AreEqual('X:0 Y:0 ', Names(Members));
end;

procedure TTypeMembersTests.ShortName;
begin
  Assert.AreEqual('TList', TTypeMembers.ShortName('System.Generics.Collections.TList<T>'));
  Assert.AreEqual('TKunde', TTypeMembers.ShortName('TKunde'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeMembersTests);

end.
