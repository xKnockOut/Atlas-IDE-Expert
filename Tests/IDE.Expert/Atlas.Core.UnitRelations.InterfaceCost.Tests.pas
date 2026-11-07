unit Atlas.Core.UnitRelations.InterfaceCost.Tests;

// Tests des Kerns der Statusleisten-Anzeige „interface-Änderung: N Units
// werden neu kompiliert“ (#554): Antwort von atlas.interfaceCost lesen,
// interface-Teil an der Einfügemarke erkennen (implementation zeigt nichts),
// Sichtbarkeit und Namensliste.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Analysis')]
  TAtlasInterfaceCostTests = class
  public
    [Test]
    procedure ParsesServerAnswer;
    [Test]
    procedure RejectsEmptyOrBrokenAnswer;
    [Test]
    procedure BuildsArguments;
    [Test]
    procedure InterfacePartEndsBeforeImplementation;
    [Test]
    procedure ProgramHasNoInterfacePart;
    [Test]
    procedure VisibleOnlyInInterfaceWithCost;
    [Test]
    procedure UnitListCountsTheRest;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.EditorToolbar.Sections,
  Atlas.Core.UnitRelations.InterfaceCost;

function Sections(const ALines: array of string): TAtlasUnitSections;
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mLines, Length(ALines));
  for mIndex := 0 to High(ALines) do
  begin
    mLines[mIndex] := ALines[mIndex];
  end;
  Result := TAtlasSectionScanner.Scan(mLines);
end;

function Cost(ACount: Integer): TAtlasInterfaceCost;
begin
  Result := Default(TAtlasInterfaceCost);
  Result.Found := True;
  Result.UnitName := 'Unten';
  Result.RecompileCount := ACount;
end;

procedure TAtlasInterfaceCostTests.ParsesServerAnswer;
var
  mValue: TAtlasInterfaceCost;
begin
  Assert.IsTrue(TAtlasInterfaceCostModel.Parse('{"found":true,"unit":"Unten","file":"C:\\P\\Unten.pas",' +
    '"recompileCount":2,"units":["Mitte","Oben"],"generation":12}', mValue));
  Assert.IsTrue(mValue.Found);
  Assert.AreEqual('Unten', mValue.UnitName);
  Assert.AreEqual('C:\P\Unten.pas', mValue.FileName);
  Assert.AreEqual(2, mValue.RecompileCount);
  Assert.AreEqual('Mitte,Oben', string.Join(',', mValue.Units));
  Assert.AreEqual(Int64(12), mValue.Generation);
  Assert.IsTrue(TAtlasInterfaceCostModel.Parse('{"found":false,"unit":"Neu","recompileCount":0}', mValue));
  Assert.IsFalse(mValue.Found);
  Assert.IsNull(mValue.Units);
end;

procedure TAtlasInterfaceCostTests.RejectsEmptyOrBrokenAnswer;
var
  mValue: TAtlasInterfaceCost;
begin
  Assert.IsFalse(TAtlasInterfaceCostModel.Parse('', mValue));
  Assert.IsFalse(TAtlasInterfaceCostModel.Parse('[1]', mValue));
  Assert.IsFalse(TAtlasInterfaceCostModel.Parse('{"found":true}', mValue), 'ohne recompileCount');
  Assert.IsFalse(TAtlasInterfaceCostModel.Parse('{kaputt', mValue));
end;

procedure TAtlasInterfaceCostTests.BuildsArguments;
begin
  Assert.AreEqual('atlas.interfaceCost', TAtlasInterfaceCostModel.cCommand);
  Assert.AreEqual('["file:///C:/P/A.pas"]', TAtlasInterfaceCostModel.Arguments('file:///C:/P/A.pas'));
end;

procedure TAtlasInterfaceCostTests.InterfacePartEndsBeforeImplementation;
var
  mValue: TAtlasUnitSections;
begin
  mValue := Sections(['unit Unten;', 'interface', 'uses', '  Basis;', 'type', '  TUnten = class end;',
    'implementation', 'procedure P;', 'begin', 'end;', 'end.']);
  Assert.IsFalse(TAtlasInterfaceCostModel.InInterfacePart(mValue, 0, 5), 'Unit-Kopf');
  Assert.IsTrue(TAtlasInterfaceCostModel.InInterfacePart(mValue, 1, 0), 'auf interface');
  Assert.IsTrue(TAtlasInterfaceCostModel.InInterfacePart(mValue, 3, 4), 'interface-uses zählen mit');
  Assert.IsTrue(TAtlasInterfaceCostModel.InInterfacePart(mValue, 5, 10));
  Assert.IsFalse(TAtlasInterfaceCostModel.InInterfacePart(mValue, 6, 0), 'auf implementation');
  Assert.IsFalse(TAtlasInterfaceCostModel.InInterfacePart(mValue, 8, 2), 'Änderung im implementation: kein Hinweis');
  // Noch ohne implementation (beim Tippen): alles nach interface.
  mValue := Sections(['unit Neu;', 'interface', 'type', '  T = Integer;']);
  Assert.IsTrue(TAtlasInterfaceCostModel.InInterfacePart(mValue, 3, 2));
end;

procedure TAtlasInterfaceCostTests.ProgramHasNoInterfacePart;
begin
  Assert.IsFalse(TAtlasInterfaceCostModel.InInterfacePart(Sections(['program P;', 'uses', '  A;', 'begin',
    'end.']), 2, 2));
  Assert.IsFalse(TAtlasInterfaceCostModel.InInterfacePart(Sections(['procedure P;', 'begin', 'end;']), 1, 0),
    'Include-Datei ohne Kopf');
end;

procedure TAtlasInterfaceCostTests.VisibleOnlyInInterfaceWithCost;
var
  mUnknown: TAtlasInterfaceCost;
begin
  Assert.IsTrue(TAtlasInterfaceCostModel.Visible(True, True, Cost(2)));
  Assert.IsFalse(TAtlasInterfaceCostModel.Visible(False, True, Cost(2)), 'build.showInterfaceCost aus');
  Assert.IsFalse(TAtlasInterfaceCostModel.Visible(True, False, Cost(2)), 'im implementation-Teil');
  Assert.IsFalse(TAtlasInterfaceCostModel.Visible(True, True, Cost(0)), 'niemand verwendet die Unit');
  mUnknown := Cost(3);
  mUnknown.Found := False;
  Assert.IsFalse(TAtlasInterfaceCostModel.Visible(True, True, mUnknown), 'nicht im Index');
end;

procedure TAtlasInterfaceCostTests.UnitListCountsTheRest;
var
  mValue: TAtlasInterfaceCost;
  mMore: Integer;
begin
  mValue := Cost(12);
  mValue.Units := TArray<string>.Create('A', 'B');
  Assert.AreEqual('A, B', TAtlasInterfaceCostModel.UnitList(mValue, mMore));
  Assert.AreEqual(10, mMore);
  mValue := Cost(2);
  mValue.Units := TArray<string>.Create('Mitte', 'Oben');
  Assert.AreEqual('Mitte, Oben', TAtlasInterfaceCostModel.UnitList(mValue, mMore));
  Assert.AreEqual(0, mMore);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasInterfaceCostTests);

end.
