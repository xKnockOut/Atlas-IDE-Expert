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
  Lines: TArray<string>;
  Index: Integer;
begin
  SetLength(Lines, Length(ALines));
  for Index := 0 to High(ALines) do
    Lines[Index] := ALines[Index];
  Result := TAtlasSectionScanner.Scan(Lines);
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
  Value: TAtlasInterfaceCost;
begin
  Assert.IsTrue(TAtlasInterfaceCostModel.Parse('{"found":true,"unit":"Unten","file":"C:\\P\\Unten.pas",' +
    '"recompileCount":2,"units":["Mitte","Oben"],"generation":12}', Value));
  Assert.IsTrue(Value.Found);
  Assert.AreEqual('Unten', Value.UnitName);
  Assert.AreEqual('C:\P\Unten.pas', Value.FileName);
  Assert.AreEqual(2, Value.RecompileCount);
  Assert.AreEqual('Mitte,Oben', string.Join(',', Value.Units));
  Assert.AreEqual(Int64(12), Value.Generation);
  Assert.IsTrue(TAtlasInterfaceCostModel.Parse('{"found":false,"unit":"Neu","recompileCount":0}', Value));
  Assert.IsFalse(Value.Found);
  Assert.IsNull(Value.Units);
end;

procedure TAtlasInterfaceCostTests.RejectsEmptyOrBrokenAnswer;
var
  Value: TAtlasInterfaceCost;
begin
  Assert.IsFalse(TAtlasInterfaceCostModel.Parse('', Value));
  Assert.IsFalse(TAtlasInterfaceCostModel.Parse('[1]', Value));
  Assert.IsFalse(TAtlasInterfaceCostModel.Parse('{"found":true}', Value), 'ohne recompileCount');
  Assert.IsFalse(TAtlasInterfaceCostModel.Parse('{kaputt', Value));
end;

procedure TAtlasInterfaceCostTests.BuildsArguments;
begin
  Assert.AreEqual('atlas.interfaceCost', TAtlasInterfaceCostModel.Command);
  Assert.AreEqual('["file:///C:/P/A.pas"]', TAtlasInterfaceCostModel.Arguments('file:///C:/P/A.pas'));
end;

procedure TAtlasInterfaceCostTests.InterfacePartEndsBeforeImplementation;
var
  Value: TAtlasUnitSections;
begin
  Value := Sections(['unit Unten;', 'interface', 'uses', '  Basis;', 'type', '  TUnten = class end;',
    'implementation', 'procedure P;', 'begin', 'end;', 'end.']);
  Assert.IsFalse(TAtlasInterfaceCostModel.InInterfacePart(Value, 0, 5), 'Unit-Kopf');
  Assert.IsTrue(TAtlasInterfaceCostModel.InInterfacePart(Value, 1, 0), 'auf interface');
  Assert.IsTrue(TAtlasInterfaceCostModel.InInterfacePart(Value, 3, 4), 'interface-uses zählen mit');
  Assert.IsTrue(TAtlasInterfaceCostModel.InInterfacePart(Value, 5, 10));
  Assert.IsFalse(TAtlasInterfaceCostModel.InInterfacePart(Value, 6, 0), 'auf implementation');
  Assert.IsFalse(TAtlasInterfaceCostModel.InInterfacePart(Value, 8, 2), 'Änderung im implementation: kein Hinweis');
  // Noch ohne implementation (beim Tippen): alles nach interface.
  Value := Sections(['unit Neu;', 'interface', 'type', '  T = Integer;']);
  Assert.IsTrue(TAtlasInterfaceCostModel.InInterfacePart(Value, 3, 2));
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
  Unknown: TAtlasInterfaceCost;
begin
  Assert.IsTrue(TAtlasInterfaceCostModel.Visible(True, True, Cost(2)));
  Assert.IsFalse(TAtlasInterfaceCostModel.Visible(False, True, Cost(2)), 'build.showInterfaceCost aus');
  Assert.IsFalse(TAtlasInterfaceCostModel.Visible(True, False, Cost(2)), 'im implementation-Teil');
  Assert.IsFalse(TAtlasInterfaceCostModel.Visible(True, True, Cost(0)), 'niemand verwendet die Unit');
  Unknown := Cost(3);
  Unknown.Found := False;
  Assert.IsFalse(TAtlasInterfaceCostModel.Visible(True, True, Unknown), 'nicht im Index');
end;

procedure TAtlasInterfaceCostTests.UnitListCountsTheRest;
var
  Value: TAtlasInterfaceCost;
  More: Integer;
begin
  Value := Cost(12);
  Value.Units := TArray<string>.Create('A', 'B');
  Assert.AreEqual('A, B', TAtlasInterfaceCostModel.UnitList(Value, More));
  Assert.AreEqual(10, More);
  Value := Cost(2);
  Value.Units := TArray<string>.Create('Mitte', 'Oben');
  Assert.AreEqual('Mitte, Oben', TAtlasInterfaceCostModel.UnitList(Value, More));
  Assert.AreEqual(0, More);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasInterfaceCostTests);

end.
