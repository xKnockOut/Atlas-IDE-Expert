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
  cKunden =
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
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if mSymbol.Name = AName then
    begin
      Exit(mSymbol);
    end;
  end;
  Result := Default(TIndexSymbol);
end;

function Names(const AMembers: TArray<TTypeMember>): string;
var
  mMember: TTypeMember;
begin
  Result := '';
  for mMember in AMembers do
  begin
    Result := Result + mMember.Name + ':' + IntToStr(mMember.Depth) + ' ';
  end;
end;

procedure TTypeMembersTests.OwnMembersThenAncestors;
var
  mIndex: ISymbolIndex;
  mLocal: TUnitIndex;
  mMembers: TArray<TTypeMember>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Basis;'#10'interface'#10'type'#10'  TPerson = class'#10 +
    '    Name: string;'#10'    Nr: Integer;'#10'  end;'#10'implementation'#10'end.', 'Basis.pas', nil));
  mLocal := TIndexExtractor.ExtractText(cKunden, 'Kunden.pas', nil);
  Assert.IsTrue(TTypeMembers.Collect(mLocal, mIndex, TypeOf(mLocal, 'TKunde'), mMembers));
  Assert.IsTrue(Names(mMembers).StartsWith('FNr:0 Saldo:0 Nr:0 Name:1 '), Names(mMembers));
  // Nr nur einmal: die eigene Eigenschaft verdeckt das Feld des Vorfahren.
  Assert.AreEqual(1, Integer(Length((' ' + Names(mMembers)).Split([' Nr:'])) - 1));
  Assert.IsTrue(TTypeMembers.Contains(mMembers, 'classname'));
  Assert.IsTrue(TTypeMembers.Contains(mMembers, 'NAME'));
  Assert.IsFalse(TTypeMembers.Contains(mMembers, 'Ort'));
end;

procedure TTypeMembersTests.UnknownAncestorIsReported;
var
  mLocal: TUnitIndex;
  mMembers: TArray<TTypeMember>;
begin
  mLocal := TIndexExtractor.ExtractText(cKunden, 'Kunden.pas', nil);
  Assert.IsFalse(TTypeMembers.Collect(mLocal, nil, TypeOf(mLocal, 'TFremd'), mMembers));
  Assert.AreEqual('X:0 ', Names(mMembers));
  Assert.IsFalse(TTypeMembers.Collect(mLocal, nil, TypeOf(mLocal, 'TKunde'), mMembers), 'TPerson ohne Index');
end;

procedure TTypeMembersTests.RecordHasNoAncestors;
var
  mLocal: TUnitIndex;
  mMembers: TArray<TTypeMember>;
begin
  mLocal := TIndexExtractor.ExtractText(cKunden, 'Kunden.pas', nil);
  Assert.IsTrue(TTypeMembers.Collect(mLocal, nil, TypeOf(mLocal, 'TPunkt'), mMembers));
  Assert.AreEqual('X:0 Y:0 ', Names(mMembers));
end;

procedure TTypeMembersTests.ShortName;
begin
  Assert.AreEqual('TList', TTypeMembers.ShortName('System.Generics.Collections.TList<T>'));
  Assert.AreEqual('TKunde', TTypeMembers.ShortName('TKunde'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeMembersTests);

end.
