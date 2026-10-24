unit Atlas.Core.UnitSearch.UseUnit.Tests;

// Tests des Kerns von „Unit verwenden“ und „Formulare suchen“ (#786):
// Antwort von atlas.useUnitInfo lesen, „schon in uses“ (auch kurz
// geschrieben und die aktive Unit selbst), Kreis-Erkennung je Abschnitt
// (Warnung nur im interface), einfügbare Units und Argumente für
// atlas.server.addUses.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasUseUnitTests = class
  public
    [Test]
    procedure ParsesServerAnswer;
    [Test]
    procedure RejectsEmptyOrBrokenAnswer;
    [Test]
    procedure MarksUnitsAlreadyInUses;
    [Test]
    procedure ShortNameMatchesNamespacedUnit;
    [Test]
    procedure InterfaceCycleWarnsImplementationHints;
    [Test]
    procedure CycleViaNamesLastUnitBeforeTarget;
    [Test]
    procedure MarksFindCyclesByFileOrName;
    [Test]
    procedure AddableSkipsInUsesOwnAndDuplicates;
    [Test]
    procedure BuildsArguments;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.UseUnit;

function Entry(const AName: string; AKind: TAtlasUnitKind): TAtlasUnitEntry;
begin
  Result := Default(TAtlasUnitEntry);
  Result.Name := AName;
  Result.FileName := 'C:\P\' + AName + '.pas';
  Result.Kind := AKind;
end;

function Info: TAtlasUseUnitInfo;
var
  Cycle: TAtlasUseUnitCycle;
begin
  Result := Default(TAtlasUseUnitInfo);
  Result.Found := True;
  Result.UnitName := 'Kunde.Import';
  Result.FileName := 'C:\P\Kunde.Import.pas';
  Result.InUses := TArray<string>.Create('SysUtils', 'Atlas.Common.Log.Format');
  // Kunde.Ansicht verwendet Kunde.Import im interface, Kunde.Bericht nur im implementation.
  Cycle := Default(TAtlasUseUnitCycle);
  Cycle.Name := 'Kunde.Ansicht';
  Cycle.FileName := 'C:\P\Kunde.Ansicht.pas';
  Cycle.InterfacePath := 'Kunde.Import → Kunde.Ansicht → Kunde.Import';
  Cycle.Path := Cycle.InterfacePath;
  Result.Cycles := [Cycle];
  Cycle := Default(TAtlasUseUnitCycle);
  Cycle.Name := 'Kunde.Bericht';
  Cycle.Path := 'Kunde.Import → Kunde.Bericht → Kunde.Liste → Kunde.Import';
  Result.Cycles := Result.Cycles + [Cycle];
end;

procedure TAtlasUseUnitTests.ParsesServerAnswer;
var
  Value: TAtlasUseUnitInfo;
begin
  Assert.IsTrue(TAtlasUseUnit.Parse('{"found":true,"unit":"Unten","file":"C:\\P\\Unten.pas",' +
    '"inUses":["SysUtils","Basis"],"cycles":[{"name":"Mitte","file":"C:\\P\\Mitte.pas",' +
    '"interfacePath":"Unten → Mitte → Unten","path":"Unten → Mitte → Unten"},' +
    '{"name":"Seite","path":"Unten → Seite → Unten"},{"name":"OhneWeg"}],"generation":7}', Value));
  Assert.IsTrue(Value.Found);
  Assert.AreEqual('Unten', Value.UnitName);
  Assert.AreEqual('C:\P\Unten.pas', Value.FileName);
  Assert.AreEqual('SysUtils,Basis', string.Join(',', Value.InUses));
  Assert.AreEqual(2, Integer(Length(Value.Cycles)), 'Kreis ohne Weg zählt nicht');
  Assert.AreEqual('Mitte', Value.Cycles[0].Name);
  Assert.AreEqual('C:\P\Mitte.pas', Value.Cycles[0].FileName);
  Assert.AreEqual('Unten → Mitte → Unten', Value.Cycles[0].InterfacePath);
  Assert.AreEqual('', Value.Cycles[1].InterfacePath);
  Assert.AreEqual('Unten → Seite → Unten', Value.Cycles[1].Path);
  Assert.AreEqual(Int64(7), Value.Generation);
  Assert.IsTrue(TAtlasUseUnit.Parse('{"found":false,"unit":"Neu","cycles":[]}', Value));
  Assert.IsFalse(Value.Found);
  Assert.IsNull(Value.Cycles);
end;

procedure TAtlasUseUnitTests.RejectsEmptyOrBrokenAnswer;
var
  Value: TAtlasUseUnitInfo;
begin
  Assert.IsFalse(TAtlasUseUnit.Parse('', Value));
  Assert.IsFalse(TAtlasUseUnit.Parse('[1]', Value));
  Assert.IsFalse(TAtlasUseUnit.Parse('{"unit":"A"}', Value), 'ohne found');
  Assert.IsFalse(TAtlasUseUnit.Parse('{kaputt', Value));
end;

procedure TAtlasUseUnitTests.MarksUnitsAlreadyInUses;
var
  Marks: TArray<TAtlasUseUnitMark>;
begin
  // Akzeptanz: Alt+F11 in Kunde.Import.pas zeigt Atlas.Common.Log.Format als „schon in uses“.
  Assert.IsTrue(TAtlasUseUnit.InUses(Info, 'Atlas.Common.Log.Format'));
  Assert.IsTrue(TAtlasUseUnit.InUses(Info, 'atlas.common.log.format'), 'ohne Groß-/Kleinschreibung');
  Assert.IsTrue(TAtlasUseUnit.InUses(Info, 'Kunde.Import'), 'die aktive Unit selbst');
  Assert.IsFalse(TAtlasUseUnit.InUses(Info, 'Atlas.Common.Log'));
  Assert.IsFalse(TAtlasUseUnit.InUses(Info, 'Format'), 'Teil eines Namens zählt nicht');
  Marks := TAtlasUseUnit.Marks(Info, TArray<TAtlasUnitEntry>.Create(Entry('Atlas.Common.Log.Format',
    TAtlasUnitKind.Unit_), Entry('Kunde.Daten', TAtlasUnitKind.Unit_)));
  Assert.AreEqual(2, Integer(Length(Marks)));
  Assert.IsTrue(Marks[0].InUses);
  Assert.IsFalse(Marks[1].InUses);
  Assert.AreEqual(-1, Marks[1].Cycle);
end;

procedure TAtlasUseUnitTests.ShortNameMatchesNamespacedUnit;
begin
  // uses SysUtils meint über die Namensräume des Projekts System.SysUtils.
  Assert.IsTrue(TAtlasUseUnit.InUses(Info, 'System.SysUtils'));
  Assert.IsFalse(TAtlasUseUnit.InUses(Info, 'System.SysUtilsExtra'));
  Assert.IsFalse(TAtlasUseUnit.InUses(Info, 'MySysUtils'));
end;

procedure TAtlasUseUnitTests.InterfaceCycleWarnsImplementationHints;
var
  Value: TAtlasUseUnitInfo;
begin
  // Akzeptanz: Kunde.Ansicht verwendet Kunde.Import im interface; die Aufnahme ins interface warnt.
  Value := Info;
  Assert.AreEqual(Ord(TAtlasUseUnitCycleState.Warning), Ord(TAtlasUseUnit.CycleState(Value.Cycles[0],
    TAtlasUseUnitSection.Interface_)));
  Assert.AreEqual(Ord(TAtlasUseUnitCycleState.Hint), Ord(TAtlasUseUnit.CycleState(Value.Cycles[0],
    TAtlasUseUnitSection.Implementation_)), 'im implementation nur ein Hinweis');
  // Rückweg über implementation-uses: in beiden Abschnitten erlaubt.
  Assert.AreEqual(Ord(TAtlasUseUnitCycleState.Hint), Ord(TAtlasUseUnit.CycleState(Value.Cycles[1],
    TAtlasUseUnitSection.Interface_)));
  Assert.AreEqual(Ord(TAtlasUseUnitCycleState.None), Ord(TAtlasUseUnit.CycleState(Default(TAtlasUseUnitCycle),
    TAtlasUseUnitSection.Interface_)));
  Assert.AreEqual('Kunde.Import → Kunde.Ansicht → Kunde.Import', TAtlasUseUnit.CyclePath(Value.Cycles[0],
    TAtlasUseUnitSection.Interface_));
  Assert.AreEqual('Kunde.Import → Kunde.Bericht → Kunde.Liste → Kunde.Import',
    TAtlasUseUnit.CyclePath(Value.Cycles[1], TAtlasUseUnitSection.Interface_));
end;

procedure TAtlasUseUnitTests.CycleViaNamesLastUnitBeforeTarget;
var
  Value: TAtlasUseUnitInfo;
begin
  Value := Info;
  Assert.AreEqual('Kunde.Ansicht', TAtlasUseUnit.CycleVia(Value.Cycles[0], TAtlasUseUnitSection.Interface_),
    'direkt: die Unit selbst');
  Assert.AreEqual('Kunde.Liste', TAtlasUseUnit.CycleVia(Value.Cycles[1], TAtlasUseUnitSection.Implementation_),
    'über Umwege: die Unit, die die aktive verwendet');
end;

procedure TAtlasUseUnitTests.MarksFindCyclesByFileOrName;
var
  Marks: TArray<TAtlasUseUnitMark>;
  Moved: TAtlasUnitEntry;
begin
  Moved := Entry('Kunde.Bericht', TAtlasUnitKind.Unit_);
  Moved.FileName := 'D:\Anders\Kunde.Bericht.pas';
  Marks := TAtlasUseUnit.Marks(Info, TArray<TAtlasUnitEntry>.Create(Entry('kunde.ansicht', TAtlasUnitKind.Form),
    Moved, Entry('Kunde.Liste', TAtlasUnitKind.Unit_)));
  Assert.AreEqual(0, Marks[0].Cycle, 'über die Datei');
  Assert.AreEqual(1, Marks[1].Cycle, 'ohne Datei über den Namen');
  Assert.AreEqual(-1, Marks[2].Cycle, 'nur im Weg, kein eigener Kreis');
end;

procedure TAtlasUseUnitTests.AddableSkipsInUsesOwnAndDuplicates;
var
  Added: TArray<TAtlasUnitEntry>;
begin
  // Akzeptanz: zwei markierte Units ohne Duplikat.
  Added := TAtlasUseUnit.Addable(Info, TArray<TAtlasUnitEntry>.Create(Entry('Kunde.Daten', TAtlasUnitKind.Unit_),
    Entry('Atlas.Common.Log.Format', TAtlasUnitKind.Unit_), Entry('Kunde.Import', TAtlasUnitKind.Unit_),
    Entry('Kunde.Ansicht', TAtlasUnitKind.Form), Entry('Kunde.Daten', TAtlasUnitKind.Unit_),
    Entry('Kopf', TAtlasUnitKind.Include)));
  Assert.AreEqual(2, Integer(Length(Added)));
  Assert.AreEqual('Kunde.Daten', Added[0].Name);
  Assert.AreEqual('Kunde.Ansicht', Added[1].Name);
end;

procedure TAtlasUseUnitTests.BuildsArguments;
begin
  Assert.AreEqual('atlas.useUnitInfo', TAtlasUseUnit.Command);
  Assert.AreEqual('["file:///C:/P/A.pas"]', TAtlasUseUnit.Arguments('file:///C:/P/A.pas'));
  Assert.AreEqual('["file:///C:/P/A.pas",["B","C"],{"section":"implementation"}]',
    TAtlasUseUnit.AddUsesArguments('file:///C:/P/A.pas', TArray<string>.Create('B', 'C'),
    TAtlasUseUnitSection.Implementation_));
  Assert.AreEqual('interface', TAtlasUseUnit.SectionText(TAtlasUseUnitSection.Interface_));
  Assert.IsTrue(TAtlasUnitKind.DataModule in TAtlasUseUnit.FormKinds);
  Assert.IsFalse(TAtlasUnitKind.Unit_ in TAtlasUseUnit.FormKinds);
  Assert.AreEqual('t:form|frame|dm', TAtlasUseUnit.FormsFilter);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUseUnitTests);

end.
