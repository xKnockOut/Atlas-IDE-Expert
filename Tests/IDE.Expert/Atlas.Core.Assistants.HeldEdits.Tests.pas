unit Atlas.Core.Assistants.HeldEdits.Tests;

// Tests für zurückgehaltene Änderungen von KI-Assistenten (#2605): Liste, Reihenfolge je Datei und der Plan für
// „Speichern und übernehmen“ (unverändert, übertragbar, überschneidend).

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Assistants.HeldEdits;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasHeldEditsTests = class
  private
    FEdits: TAtlasHeldEdits;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure AddCountsPerFile;
    [Test]
    procedure NextForOffersTheOldestFirst;
    [Test]
    procedure RemoveDropsOnlyThatEdit;
    [Test]
    procedure PlanAppliesOnUnchangedBuffer;
    [Test]
    procedure PlanCarriesOverChangesElsewhere;
    [Test]
    procedure PlanRefusesOverlappingChanges;
    [Test]
    procedure ChangeNamesTheLines;
  end;

implementation

uses
  System.SysUtils;

const
  cExpected = 'a'#10'b'#10'c'#10'd'#10'e'#10'f'#10'g'#10;
  cText = 'a'#10'b'#10'c'#10'D'#10'e'#10'f'#10'g'#10;

{ TAtlasHeldEditsTests }

procedure TAtlasHeldEditsTests.Setup;
begin
  FEdits := TAtlasHeldEdits.Create;
end;

procedure TAtlasHeldEditsTests.TearDown;
begin
  FreeAndNil(FEdits);
end;

procedure TAtlasHeldEditsTests.AddCountsPerFile;
begin
  Assert.AreEqual(1, FEdits.Add('C:\P\A.pas', cExpected, cText, 'KI', 0));
  Assert.AreEqual(2, FEdits.Add('C:\P\B.pas', cExpected, cText, 'KI', 0));
  FEdits.Add('c:\p\a.pas', cExpected, cText, '', 0);
  Assert.AreEqual(3, FEdits.Count);
  Assert.AreEqual(2, FEdits.CountFor('C:\P\A.pas'), 'ohne Groß-/Kleinschreibung');
  Assert.AreEqual(0, FEdits.CountFor('C:\P\C.pas'));
end;

procedure TAtlasHeldEditsTests.NextForOffersTheOldestFirst;
var
  mEdit: TAtlasHeldEdit;
begin
  FEdits.Add('A.pas', cExpected, cText, 'erste', 0);
  FEdits.Add('B.pas', cExpected, cText, 'andere', 0);
  FEdits.Add('A.pas', cExpected, cText, 'zweite', 0);
  Assert.IsTrue(FEdits.TryNextFor('A.pas', mEdit));
  Assert.AreEqual('erste', mEdit.Client);
  FEdits.Remove(mEdit.Id);
  Assert.IsTrue(FEdits.TryNextFor('A.pas', mEdit));
  Assert.AreEqual('zweite', mEdit.Client, 'danach die nächste derselben Datei');
  Assert.IsTrue(FEdits.TryFirst(mEdit));
  Assert.AreEqual('andere', mEdit.Client, 'insgesamt die älteste');
  Assert.IsFalse(FEdits.TryNextFor('C.pas', mEdit));
end;

procedure TAtlasHeldEditsTests.RemoveDropsOnlyThatEdit;
var
  mFirst: Integer;
  mEdit: TAtlasHeldEdit;
begin
  mFirst := FEdits.Add('A.pas', cExpected, cText, '', 0);
  FEdits.Add('A.pas', cExpected, cText, '', 0);
  Assert.IsTrue(FEdits.Remove(mFirst));
  Assert.IsFalse(FEdits.Remove(mFirst), 'schon weg');
  Assert.IsFalse(FEdits.TryGet(mFirst, mEdit));
  Assert.AreEqual(1, FEdits.Count);
  FEdits.Clear;
  Assert.AreEqual(0, Integer(Length(FEdits.Items)));
end;

procedure TAtlasHeldEditsTests.PlanAppliesOnUnchangedBuffer;
var
  mEdit: TAtlasHeldEdit;
  mText: string;
begin
  FEdits.TryGet(FEdits.Add('A.pas', cExpected, cText, '', 0), mEdit);
  Assert.IsTrue(TAtlasHeldEdits.Plan(mEdit, cExpected, mText));
  Assert.AreEqual(cText, mText);
end;

procedure TAtlasHeldEditsTests.PlanCarriesOverChangesElsewhere;
var
  mEdit: TAtlasHeldEdit;
  mText: string;
begin
  FEdits.TryGet(FEdits.Add('A.pas', cExpected, cText, '', 0), mEdit);
  // Der Benutzer hat die erste Zeile geändert, weit weg von Zeile 4.
  Assert.IsTrue(TAtlasHeldEdits.Plan(mEdit, 'A'#10'b'#10'c'#10'd'#10'e'#10'f'#10'g'#10, mText));
  Assert.AreEqual('A'#10'b'#10'c'#10'D'#10'e'#10'f'#10'g'#10, mText);
end;

procedure TAtlasHeldEditsTests.PlanRefusesOverlappingChanges;
var
  mEdit: TAtlasHeldEdit;
  mText: string;
begin
  FEdits.TryGet(FEdits.Add('A.pas', cExpected, cText, '', 0), mEdit);
  Assert.IsFalse(TAtlasHeldEdits.Plan(mEdit, 'a'#10'b'#10'c'#10'X'#10'e'#10'f'#10'g'#10, mText),
    'derselbe Bereich: nur Vergleich');
end;

procedure TAtlasHeldEditsTests.ChangeNamesTheLines;
var
  mEdit: TAtlasHeldEdit;
begin
  FEdits.TryGet(FEdits.Add('A.pas', cExpected, cText, '', 0), mEdit);
  Assert.AreEqual(4, mEdit.Change.FirstLine);
  Assert.AreEqual(4, mEdit.Change.LastLine);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasHeldEditsTests);

end.
