unit Atlas.Core.Designer.Groups.Tests;

// Tests für Gruppen ohne Container (#744): Gruppenbildung, Parent-Prüfung,
// Erweitern der Auswahl, Umbenennen, Löschen bis zur Auflösung, Kopieren und
// Ablage als JSON.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerGroupsTests = class
  public
    [Test]
    procedure GroupAndExpand;
    [Test]
    procedure MemberChangesGroup;
    [Test]
    procedure Parents;
    [Test]
    procedure RenameAndDelete;
    [Test]
    procedure CopyBecomesGroup;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure Names;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Designer.SelectionSets,
  Atlas.Core.Designer.Groups;

const
  cForm = 'C:\Projekt\Main.dfm';

procedure TAtlasDesignerGroupsTests.GroupAndExpand;
var
  mGroups: TAtlasDesignerGroups;
  mSelection: TArray<string>;
begin
  mGroups := TAtlasDesignerGroups.Create;
  try
    Assert.AreEqual(-1, mGroups.Add(cForm, 'Allein', ['edtA']), 'eins reicht nicht');
    Assert.AreEqual(0, mGroups.Add(cForm, 'Lieferant', ['lblLieferant', 'edtLieferant', 'btnLieferant']));
    mSelection := mGroups.Expand(cForm, ['edtLieferant']);
    Assert.AreEqual(3, Integer(Length(mSelection)));
    Assert.AreEqual('edtLieferant', mSelection[0], 'Geklicktes zuerst');
    Assert.AreEqual(1, Integer(Length(mGroups.Expand(cForm, ['edtOther']))));
    Assert.IsTrue(mGroups.Ungroup(cForm, 'btnLieferant'));
    Assert.AreEqual(1, Integer(Length(mGroups.Expand(cForm, ['edtLieferant']))), 'aufgelöst');
    Assert.IsFalse(mGroups.Ungroup(cForm, 'btnLieferant'));
  finally
    mGroups.Free;
  end;
end;

procedure TAtlasDesignerGroupsTests.MemberChangesGroup;
var
  mGroups: TAtlasDesignerGroups;
begin
  mGroups := TAtlasDesignerGroups.Create;
  try
    mGroups.Add(cForm, 'A', ['a1', 'a2']);
    mGroups.Add(cForm, 'B', ['b1', 'b2', 'b3']);
    mGroups.Add(cForm, 'C', ['a1', 'b1']);
    // A behält nur a2 und löst sich auf, B behält zwei.
    Assert.AreEqual(2, Integer(Length(mGroups.GroupsOf(cForm))));
    Assert.AreEqual(-1, mGroups.IndexOf(cForm, 'a2'));
    Assert.AreEqual(2, Integer(Length(mGroups.GroupsOf(cForm)[mGroups.IndexOf(cForm, 'b2')].Members)));
    Assert.AreEqual('C', mGroups.GroupsOf(cForm)[mGroups.IndexOf(cForm, 'a1')].Name);
  finally
    mGroups.Free;
  end;
end;

procedure TAtlasDesignerGroupsTests.Parents;
begin
  Assert.IsTrue(TAtlasDesignerGroups.SameParent(['pnlA', 'PNLA', 'pnlA']));
  Assert.IsFalse(TAtlasDesignerGroups.SameParent(['pnlA', 'pnlB']));
  Assert.IsFalse(TAtlasDesignerGroups.SameParent([]));
end;

procedure TAtlasDesignerGroupsTests.RenameAndDelete;
var
  mGroups: TAtlasDesignerGroups;
begin
  mGroups := TAtlasDesignerGroups.Create;
  try
    mGroups.Add(cForm, 'Zeile', ['lblA', 'edtA', 'btnA']);
    mGroups.ComponentRenamed(cForm, 'edtA', 'edtName');
    Assert.AreEqual(0, mGroups.IndexOf(cForm, 'edtName'));
    mGroups.ComponentDeleted(cForm, 'btnA');
    Assert.AreEqual(0, mGroups.IndexOf(cForm, 'lblA'), 'zwei bleiben');
    mGroups.ComponentDeleted(cForm, 'lblA');
    Assert.AreEqual(0, Integer(Length(mGroups.GroupsOf(cForm))), 'eine allein löst sich auf');
  finally
    mGroups.Free;
  end;
end;

procedure TAtlasDesignerGroupsTests.CopyBecomesGroup;
var
  mGroups: TAtlasDesignerGroups;
  mGroup, mCopy, mOther: TArray<TAtlasGroupShape>;
begin
  mGroups := TAtlasDesignerGroups.Create;
  try
    mGroups.Add(cForm, 'Lieferant', ['lblA', 'edtA']);
    mGroup := [TAtlasGroupShape.Create('lblA', 'TLabel', Bounds(10, 13, 50, 15)),
      TAtlasGroupShape.Create('edtA', 'TEdit', Bounds(70, 10, 120, 23))];
    mCopy := [TAtlasGroupShape.Create('edtA2', 'TEdit', Bounds(80, 50, 120, 23)),
      TAtlasGroupShape.Create('lblA2', 'TLabel', Bounds(20, 53, 50, 15))];
    mOther := [TAtlasGroupShape.Create('edtB', 'TEdit', Bounds(80, 90, 120, 23)),
      TAtlasGroupShape.Create('lblB', 'TLabel', Bounds(10, 93, 50, 15))];
    Assert.IsTrue(TAtlasDesignerGroups.IsCopy(mGroup, mCopy));
    Assert.IsFalse(TAtlasDesignerGroups.IsCopy(mGroup, mOther), 'andere Lage zueinander');
    Assert.AreEqual(-1, mGroups.AddCopy(cForm, [mGroup], mOther));
    Assert.AreEqual(1, mGroups.AddCopy(cForm, [mGroup], mCopy));
    Assert.AreEqual('Lieferant 2', mGroups.GroupsOf(cForm)[1].Name);
  finally
    mGroups.Free;
  end;
end;

procedure TAtlasDesignerGroupsTests.JsonRoundTrip;
var
  mGroups, mLoaded: TAtlasDesignerGroups;
begin
  mGroups := TAtlasDesignerGroups.Create;
  mLoaded := TAtlasDesignerGroups.Create;
  try
    mGroups.Add(cForm, 'Zeile', ['lblA', 'edtA']);
    Assert.IsTrue(mGroups.Changed);
    Assert.IsTrue(mLoaded.LoadJson(mGroups.ToJson));
    Assert.AreEqual(0, mLoaded.IndexOf(cForm, 'edtA'));
    mLoaded.Restore(cForm, nil);
    Assert.AreEqual(-1, mLoaded.IndexOf(cForm, 'edtA'), 'Rückgängig leert');
    Assert.IsFalse(mLoaded.LoadJson('kaputt'));
  finally
    mLoaded.Free;
    mGroups.Free;
  end;
end;

procedure TAtlasDesignerGroupsTests.Names;
begin
  Assert.AreEqual('Lieferant', TAtlasDesignerGroups.SuggestName(['lblX', 'edtY'], '&Lieferant:'));
  Assert.AreEqual(TAtlasSelectionSets.SuggestName(['edtAdresseStrasse', 'edtAdressePlz']),
    TAtlasDesignerGroups.SuggestName(['edtAdresseStrasse', 'edtAdressePlz'], ''));
end;

end.
