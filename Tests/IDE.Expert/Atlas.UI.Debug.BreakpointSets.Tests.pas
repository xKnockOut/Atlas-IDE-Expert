unit Atlas.UI.Debug.BreakpointSets.Tests;

// Dialoge der Haltepunkt-Sätze (#586): Text je Satz, Speichern mit und ohne
// Branch, Auswahl des zuletzt aktiven Satzes, Knopf je Modus.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasBreakpointSetDialogTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ItemTexts;
    [Test]
    procedure SaveOffersBranch;
    [Test]
    procedure SaveWithoutBranch;
    [Test]
    procedure PickSelectsActiveSet;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.BreakpointSets,
  Atlas.UI.Debug.BreakpointSets;

function Sets: TAtlasBreakpointSetList;
begin
  SetLength(Result, 2);
  Result[0] := Default(TAtlasBreakpointSet);
  Result[0].Name := 'Import';
  Result[0].Branch := 'feature/import';
  SetLength(Result[0].Entries, 2);
  Result[1] := Default(TAtlasBreakpointSet);
  Result[1].Name := 'Speichern';
  SetLength(Result[1].Entries, 1);
end;

{ TAtlasBreakpointSetDialogTests }

procedure TAtlasBreakpointSetDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasBreakpointSetDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasBreakpointSetDialogTests.ItemTexts;
var
  mSets: TAtlasBreakpointSetList;
begin
  mSets := Sets;
  Assert.AreEqual('Import (2 Haltepunkte, Branch feature/import)', TAtlasBreakpointSetDialog.ItemText(mSets[0]));
  Assert.AreEqual('Speichern (1 Haltepunkte)', TAtlasBreakpointSetDialog.ItemText(mSets[1]));
end;

procedure TAtlasBreakpointSetDialogTests.SaveOffersBranch;
var
  mDialog: TAtlasBreakpointSetDialog;
begin
  mDialog := TAtlasBreakpointSetDialog.CreateDialog(nil, TAtlasBreakpointSetMode.Save, Sets, 'feature/import',
    'Import');
  try
    Assert.IsNull(mDialog.SetList);
    Assert.IsNotNull(mDialog.CoupleCheck);
    Assert.AreEqual('An Branch feature/import koppeln', mDialog.CoupleCheck.Caption);
    Assert.AreEqual('Speichern', mDialog.OkButton.Caption);
    mDialog.HandleNeeded;
    mDialog.Fill;
    Assert.AreEqual(2, mDialog.NameBox.Items.Count);
    Assert.AreEqual('Import', mDialog.ChosenName);
    Assert.IsTrue(mDialog.CoupleCheck.Checked, 'Satz ist schon an diesen Branch gekoppelt');
    Assert.AreEqual('feature/import', mDialog.ChosenBranch);
    mDialog.CoupleCheck.Checked := False;
    Assert.AreEqual('', mDialog.ChosenBranch);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasBreakpointSetDialogTests.SaveWithoutBranch;
var
  mDialog: TAtlasBreakpointSetDialog;
begin
  mDialog := TAtlasBreakpointSetDialog.CreateDialog(nil, TAtlasBreakpointSetMode.Save, nil, '', '');
  try
    Assert.IsNull(mDialog.CoupleCheck);
    Assert.AreEqual('', mDialog.ChosenBranch);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasBreakpointSetDialogTests.PickSelectsActiveSet;
var
  mDialog: TAtlasBreakpointSetDialog;
begin
  mDialog := TAtlasBreakpointSetDialog.CreateDialog(nil, TAtlasBreakpointSetMode.Delete, Sets, '', 'Speichern');
  try
    Assert.IsNull(mDialog.NameBox);
    Assert.AreEqual('Löschen', mDialog.OkButton.Caption);
    Assert.AreEqual('Haltepunkt-Satz löschen', mDialog.Caption);
    mDialog.HandleNeeded;
    mDialog.Fill;
    Assert.AreEqual(2, mDialog.SetList.Items.Count);
    Assert.AreEqual(1, mDialog.SetList.ItemIndex);
    Assert.AreEqual('Speichern', mDialog.ChosenName);
  finally
    mDialog.Free;
  end;
end;

end.
