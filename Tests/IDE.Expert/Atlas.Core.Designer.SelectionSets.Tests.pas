unit Atlas.Core.Designer.SelectionSets.Tests;

// Tests der Auswahlsätze (#739): Namensvorschlag, Tasten, Umbenennen und
// Löschen von Komponenten, Sätze pflegen und sortieren, JSON hin und zurück.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Designer.SelectionSets;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasSelectionSetsTests = class
  private
    FSets: TAtlasSelectionSets;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SuggestsCommonWord;
    [Test]
    procedure ShortcutsFollowOrder;
    [Test]
    procedure AddSameNameReplaces;
    [Test]
    procedure RenamedComponentStays;
    [Test]
    procedure DeletedComponentLeavesEmptySet;
    [Test]
    procedure MaintainSets;
    [Test]
    procedure FormsAreSeparate;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure BrokenJsonIsEmpty;
    [Test]
    procedure MissingMembers;
  end;

implementation

const
  cForm = 'C:\Projekt\uKunden.dfm';

procedure TAtlasSelectionSetsTests.Setup;
begin
  FSets := TAtlasSelectionSets.Create;
end;

procedure TAtlasSelectionSetsTests.TearDown;
begin
  FSets.Free;
  FSets := nil;
end;

procedure TAtlasSelectionSetsTests.SuggestsCommonWord;
begin
  Assert.AreEqual('Adresse', TAtlasSelectionSets.SuggestName(['edtAdresseStrasse', 'edtAdressePlz',
    'lblAdresseOrt']));
  Assert.AreEqual('Kunde', TAtlasSelectionSets.SuggestName(['Kunde_Name', 'edtKunde2']));
  Assert.AreEqual('', TAtlasSelectionSets.SuggestName(['btnOk', 'btnAbbrechen']), 'nur das Präfix gemeinsam');
  Assert.AreEqual('', TAtlasSelectionSets.SuggestName(['edtName']), 'ein Name allein');
end;

procedure TAtlasSelectionSetsTests.ShortcutsFollowOrder;
begin
  Assert.AreEqual(1, TAtlasSelectionSets.ShortcutOf(0));
  Assert.AreEqual(9, TAtlasSelectionSets.ShortcutOf(8));
  Assert.AreEqual(0, TAtlasSelectionSets.ShortcutOf(9));
  Assert.AreEqual(0, TAtlasSelectionSets.ShortcutOf(-1));
end;

procedure TAtlasSelectionSetsTests.AddSameNameReplaces;
begin
  Assert.AreEqual(0, FSets.Add(cForm, 'Adressfelder', ['edtStrasse', 'edtPlz', 'edtPlz']));
  Assert.AreEqual(1, FSets.Add(cForm, 'Knöpfe', ['btnOk']));
  Assert.AreEqual(0, FSets.Add(cForm, ' adressfelder ', ['edtOrt']));
  Assert.AreEqual(2, Integer(Length(FSets.SetsOf(cForm))));
  Assert.AreEqual(1, Integer(Length(FSets.SetsOf(cForm)[0].Members)));
  Assert.AreEqual('edtOrt', FSets.SetsOf(cForm)[0].Members[0]);
  Assert.AreEqual(1, Integer(Length(FSets.SetsOf(cForm)[1].Members)), 'Knöpfe unverändert');
  Assert.IsTrue(FSets.Changed);
end;

procedure TAtlasSelectionSetsTests.RenamedComponentStays;
begin
  FSets.Add(cForm, 'Adressfelder', ['edtStrasse', 'edtPlz', 'edtOrt', 'edtLand']);
  FSets.ComponentRenamed(cForm, 'EDTORT', 'edtWohnort');
  Assert.AreEqual('edtWohnort', FSets.SetsOf(cForm)[0].Members[2]);
  Assert.AreEqual(4, Integer(Length(FSets.SetsOf(cForm)[0].Members)));
end;

procedure TAtlasSelectionSetsTests.DeletedComponentLeavesEmptySet;
begin
  FSets.Add(cForm, 'Adressfelder', ['edtStrasse', 'edtPlz', 'edtOrt', 'edtLand']);
  FSets.ComponentDeleted(cForm, 'edtPlz');
  Assert.AreEqual(3, Integer(Length(FSets.SetsOf(cForm)[0].Members)));
  FSets.Add(cForm, 'Einer', ['btnOk']);
  FSets.ComponentDeleted(cForm, 'btnOk');
  Assert.AreEqual(2, Integer(Length(FSets.SetsOf(cForm))), 'leerer Satz bleibt');
  Assert.AreEqual(0, Integer(Length(FSets.SetsOf(cForm)[1].Members)));
end;

procedure TAtlasSelectionSetsTests.MaintainSets;
var
  mSets: TArray<TAtlasSelectionSet>;
begin
  FSets.Add(cForm, 'A', ['a1']);
  FSets.Add(cForm, 'B', ['b1']);
  FSets.Add(cForm, 'C', ['c1']);
  FSets.Move(cForm, 2, -1);
  FSets.Move(cForm, 0, -1);
  mSets := FSets.SetsOf(cForm);
  Assert.AreEqual('A', mSets[0].Name, 'am Rand bleibt er stehen');
  Assert.AreEqual('C', mSets[1].Name);
  Assert.AreEqual('B', mSets[2].Name);
  FSets.Rename(cForm, 1, 'Knöpfe');
  FSets.Rename(cForm, 1, '  ');
  FSets.Replace(cForm, 0, ['x', 'y']);
  FSets.Extend(cForm, 0, ['y', 'z']);
  FSets.Delete(cForm, 2);
  FSets.Delete(cForm, 7);
  mSets := FSets.SetsOf(cForm);
  Assert.AreEqual(2, Integer(Length(mSets)));
  Assert.AreEqual('Knöpfe', mSets[1].Name, 'leerer Name ändert nichts');
  Assert.AreEqual(3, Integer(Length(mSets[0].Members)));
  Assert.AreEqual('z', mSets[0].Members[2]);
end;

procedure TAtlasSelectionSetsTests.FormsAreSeparate;
begin
  FSets.Add(cForm, 'A', ['a1']);
  FSets.Add('C:\Projekt\uLager.dfm', 'B', ['a1']);
  FSets.ComponentDeleted(cForm, 'a1');
  Assert.AreEqual(1, Integer(Length(FSets.SetsOf('c:\projekt\ulager.dfm')[0].Members)));
  Assert.AreEqual(0, Integer(Length(FSets.SetsOf(cForm)[0].Members)));
end;

procedure TAtlasSelectionSetsTests.JsonRoundTrip;
var
  mText: string;
  mLoaded: TAtlasSelectionSets;
  mSets: TArray<TAtlasSelectionSet>;
begin
  FSets.Add(cForm, 'Adressfelder', ['edtStrasse', 'edtPlz']);
  FSets.Add(cForm, 'Leer', []);
  mText := FSets.ToJson;
  mLoaded := TAtlasSelectionSets.Create;
  try
    Assert.IsTrue(mLoaded.LoadJson(mText));
    Assert.IsFalse(mLoaded.Changed);
    mSets := mLoaded.SetsOf(cForm);
    Assert.AreEqual(2, Integer(Length(mSets)));
    Assert.AreEqual('Adressfelder', mSets[0].Name);
    Assert.AreEqual('edtPlz', mSets[0].Members[1]);
    Assert.AreEqual(0, Integer(Length(mSets[1].Members)));
  finally
    mLoaded.Free;
  end;
end;

procedure TAtlasSelectionSetsTests.BrokenJsonIsEmpty;
begin
  FSets.Add(cForm, 'A', ['a1']);
  Assert.IsFalse(FSets.LoadJson('{kaputt'));
  Assert.AreEqual(0, Integer(Length(FSets.SetsOf(cForm))));
  Assert.IsTrue(FSets.LoadJson('{"forms":{"X":[{"name":""},{"name":"B","members":[1,"b"]},7]}}'));
  Assert.AreEqual(1, Integer(Length(FSets.SetsOf('x'))));
  Assert.AreEqual('b', FSets.SetsOf('x')[0].Members[0]);
end;

procedure TAtlasSelectionSetsTests.MissingMembers;
var
  mMissing: TArray<string>;
begin
  mMissing := TAtlasSelectionSets.Missing(TAtlasSelectionSet.Create('A', ['edtPlz', 'edtOrt']), ['EDTPLZ']);
  Assert.AreEqual(1, Integer(Length(mMissing)));
  Assert.AreEqual('edtOrt', mMissing[0]);
end;

end.
