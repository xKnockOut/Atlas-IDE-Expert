unit Atlas.Core.Debug.WatchScopes.Tests;

// Tests für überwachte Ausdrücke je Klasse oder Unit (#2550): Bindung lesen und schreiben, Ort des Halts aus der
// Antwort des Servers und aus dem Rahmen, Abgleich (Klasse, Unit, Nachfahre, Routine ohne Klasse, Rahmen ohne
// Quelltext) und Reihenfolge im Reiter Überwachung; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasWatchScopesTests = class
  public
    [Test]
    procedure ScopeRoundTrip;
    [Test]
    procedure UnknownScopeIsEverywhere;
    [Test]
    procedure PlaceFromServerAnswer;
    [Test]
    procedure PlaceFromFrame;
    [Test]
    procedure FrameOfGenericClassBindsUnitOnly;
    [Test]
    procedure ClassMatchesOwnClassAndDescendants;
    [Test]
    procedure UnitMatchesUnitOnly;
    [Test]
    procedure FreeRoutineMatchesNoClass;
    [Test]
    procedure WithoutSourceOnlyEverywhere;
    [Test]
    procedure ArrangePutsMatchingFirstAndCountsHidden;
    [Test]
    procedure ArrangeShowsHiddenOnRequest;
    [Test]
    procedure ArrangeDisabledKeepsAll;
    [Test]
    procedure ScopeOfPlace;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Debug.WatchScopes;

const
  cEverywhere: Integer = Ord(TAtlasWatchScopeKind.Everywhere);

/// <summary>Art der Bindung als Zahl für Assert.AreEqual.</summary>
function KindOf(const AScope: TAtlasWatchScope): Integer;
begin
  Result := Ord(AScope.Kind);
end;

function Place(const AUnit, AClass: string; const AAncestors: TArray<string>): TAtlasWatchPlace;
begin
  Result := Default(TAtlasWatchPlace);
  Result.UnitName := AUnit;
  Result.TypeName := AClass;
  Result.Ancestors := AAncestors;
end;

function Watches: TAtlasScopedWatches;
begin
  Result := nil;
  SetLength(Result, 5);
  Result[0] := TAtlasScopedWatch.Create('Now', TAtlasWatchScope.Everywhere);
  Result[1] := TAtlasScopedWatch.Create('FFilter', TAtlasWatchScope.ForClass('TAuftragsLauf'));
  Result[2] := TAtlasScopedWatch.Create('FKunde', TAtlasWatchScope.ForClass('TKundenFenster'));
  Result[3] := TAtlasScopedWatch.Create('GZaehler', TAtlasWatchScope.ForUnit('Auftrag.Lauf'));
  Result[4] := TAtlasScopedWatch.Create('FOffen.Count', TAtlasWatchScope.ForClass('TBasisLauf'));
end;

{ TAtlasWatchScopesTests }

procedure TAtlasWatchScopesTests.ScopeRoundTrip;
begin
  Assert.AreEqual('class:TAuftragsLauf', TAtlasWatchScope.Parse('class:TAuftragsLauf').ToText);
  Assert.AreEqual('unit:Auftrag.Lauf', TAtlasWatchScope.Parse(' unit:Auftrag.Lauf ').ToText);
  Assert.AreEqual('', TAtlasWatchScope.Everywhere.ToText);
  Assert.IsTrue(TAtlasWatchScope.Parse('CLASS:TA').Same(TAtlasWatchScope.ForClass('ta')), 'ohne Groß/klein');
end;

procedure TAtlasWatchScopesTests.UnknownScopeIsEverywhere;
begin
  Assert.AreEqual(cEverywhere, KindOf(TAtlasWatchScope.Parse('')));
  Assert.AreEqual(cEverywhere, KindOf(TAtlasWatchScope.Parse('thread:12')));
  Assert.AreEqual(cEverywhere, KindOf(TAtlasWatchScope.Parse('class:')), 'ohne Namen');
end;

procedure TAtlasWatchScopesTests.PlaceFromServerAnswer;
var
  mJson: TJSONValue;
  mPlace: TAtlasWatchPlace;
begin
  mJson := TJSONObject.ParseJSONValue(
    '{"autos":[],"locals":[],"unit":"Auftrag.Lauf","class":"TAuftragsLauf","ancestors":["TBasisLauf"]}');
  try
    mPlace := TAtlasWatchPlace.Read(mJson as TJSONObject);
  finally
    mJson.Free;
  end;
  Assert.AreEqual('Auftrag.Lauf', mPlace.UnitName);
  Assert.AreEqual('TAuftragsLauf', mPlace.TypeName);
  Assert.AreEqual('TBasisLauf', string.Join(',', mPlace.Ancestors));
  Assert.IsFalse(TAtlasWatchPlace.Read(nil).Known, 'alte Antwort ohne Felder');
end;

procedure TAtlasWatchScopesTests.PlaceFromFrame;
var
  mPlace: TAtlasWatchPlace;
begin
  mPlace := TAtlasWatchPlace.FromFrame('Auftrag.Lauf.TAuftragsLauf.LeseBericht', 'C:\P\Auftrag.Lauf.pas');
  Assert.AreEqual('Auftrag.Lauf', mPlace.UnitName);
  Assert.AreEqual('TAuftragsLauf', mPlace.TypeName);
  mPlace := TAtlasWatchPlace.FromFrame('Haupt.TAussen.TInnen.Lauf', '/p/Haupt.pas');
  Assert.AreEqual('TAussen.TInnen', mPlace.TypeName, 'verschachtelter Typ');
  mPlace := TAtlasWatchPlace.FromFrame('Haupt.Starte', 'C:\P\Haupt.pas');
  Assert.AreEqual('', mPlace.TypeName, 'freie Routine');
  Assert.IsTrue(mPlace.Known);
end;

procedure TAtlasWatchScopesTests.FrameOfGenericClassBindsUnitOnly;
var
  mPlace: TAtlasWatchPlace;
begin
  mPlace := TAtlasWatchPlace.FromFrame('Listen.TListe<System.Integer>.Add', 'C:\P\Listen.pas');
  Assert.AreEqual('Listen', mPlace.UnitName);
  Assert.AreEqual('', mPlace.TypeName);
end;

procedure TAtlasWatchScopesTests.ClassMatchesOwnClassAndDescendants;
var
  mPlace: TAtlasWatchPlace;
begin
  mPlace := Place('Auftrag.Lauf', 'TAuftragsLauf', ['TBasisLauf', 'TObject']);
  Assert.IsTrue(mPlace.Matches(TAtlasWatchScope.ForClass('tauftragslauf')));
  Assert.IsTrue(mPlace.Matches(TAtlasWatchScope.ForClass('TBasisLauf')), 'Vorfahr bekannt');
  Assert.IsFalse(mPlace.Matches(TAtlasWatchScope.ForClass('TKundenFenster')));
  mPlace.Ancestors := nil;
  Assert.IsFalse(mPlace.Matches(TAtlasWatchScope.ForClass('TBasisLauf')), 'Vorfahren unbekannt');
end;

procedure TAtlasWatchScopesTests.UnitMatchesUnitOnly;
var
  mPlace: TAtlasWatchPlace;
begin
  mPlace := Place('Auftrag.Lauf', 'TAuftragsLauf', nil);
  Assert.IsTrue(mPlace.Matches(TAtlasWatchScope.ForUnit('auftrag.lauf')));
  Assert.IsFalse(mPlace.Matches(TAtlasWatchScope.ForUnit('Auftrag')));
  Assert.IsTrue(mPlace.Matches(TAtlasWatchScope.Everywhere));
end;

procedure TAtlasWatchScopesTests.FreeRoutineMatchesNoClass;
var
  mPlace: TAtlasWatchPlace;
begin
  mPlace := Place('Auftrag.Lauf', '', nil);
  Assert.IsFalse(mPlace.Matches(TAtlasWatchScope.ForClass('TAuftragsLauf')));
  Assert.IsTrue(mPlace.Matches(TAtlasWatchScope.ForUnit('Auftrag.Lauf')));
end;

procedure TAtlasWatchScopesTests.WithoutSourceOnlyEverywhere;
var
  mPlace: TAtlasWatchPlace;
  mArrangement: TAtlasWatchArrangement;
begin
  // Rahmen ohne Quelltext: kein Ort, keine Bindung passt.
  mPlace := TAtlasWatchPlace.FromFrame(':7714C3E2 KERNELBASE.RaiseException', '');
  Assert.IsFalse(mPlace.Known);
  mArrangement := TAtlasWatchArrange.Arrange(Watches, mPlace, True, False);
  Assert.AreEqual('Now', string.Join(',', mArrangement.Expressions));
  Assert.AreEqual(4, mArrangement.Hidden);
end;

procedure TAtlasWatchScopesTests.ArrangePutsMatchingFirstAndCountsHidden;
var
  mArrangement: TAtlasWatchArrangement;
begin
  mArrangement := TAtlasWatchArrange.Arrange(Watches, Place('Auftrag.Lauf', 'TAuftragsLauf', ['TBasisLauf']), True,
    False);
  Assert.AreEqual('FFilter,GZaehler,FOffen.Count,Now', string.Join(',', mArrangement.Expressions));
  Assert.AreEqual(1, mArrangement.Hidden, 'FKunde gehört zu einer anderen Klasse');
end;

procedure TAtlasWatchScopesTests.ArrangeShowsHiddenOnRequest;
var
  mArrangement: TAtlasWatchArrangement;
begin
  mArrangement := TAtlasWatchArrange.Arrange(Watches, Place('Kunden', 'TKundenFenster', nil), True, True);
  Assert.AreEqual('FKunde,Now,FFilter,GZaehler,FOffen.Count', string.Join(',', mArrangement.Expressions));
  Assert.AreEqual(3, mArrangement.Hidden);
end;

procedure TAtlasWatchScopesTests.ArrangeDisabledKeepsAll;
var
  mArrangement: TAtlasWatchArrangement;
begin
  mArrangement := TAtlasWatchArrange.Arrange(Watches, Place('Kunden', 'TKundenFenster', nil), False, False);
  Assert.AreEqual('Now,FFilter,FKunde,GZaehler,FOffen.Count', string.Join(',', mArrangement.Expressions));
  Assert.AreEqual(0, mArrangement.Hidden);
end;

procedure TAtlasWatchScopesTests.ScopeOfPlace;
var
  mPlace: TAtlasWatchPlace;
begin
  mPlace := Place('Auftrag.Lauf', 'TAuftragsLauf', nil);
  Assert.AreEqual('class:TAuftragsLauf', mPlace.ScopeOf(TAtlasWatchScopeKind.ClassType).ToText);
  Assert.AreEqual('unit:Auftrag.Lauf', mPlace.ScopeOf(TAtlasWatchScopeKind.UnitName).ToText);
  mPlace.TypeName := '';
  Assert.AreEqual(cEverywhere, KindOf(mPlace.ScopeOf(TAtlasWatchScopeKind.ClassType)),
    'ohne Klasse keine Bindung an eine');
end;

end.
