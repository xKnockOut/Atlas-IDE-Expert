unit Atlas.Core.Designer.ButtonStates.Tests;

// Tests für den gemerkten Zustand der Umschaltknöpfe der Designer-Leiste:
// Vorgabe ohne Eintrag, Lesen ohne Groß-/Kleinschreibung, ungültige und
// doppelte Einträge, Setzen, Überschreiben, Sortierung und Bereinigen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Designer.ButtonStates;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerButtonStatesTests = class
  public
    [Test]
    procedure EmptyGivesDefault;
    [Test]
    procedure ReadsStoredState;
    [Test]
    procedure IdIgnoresCase;
    [Test]
    procedure InvalidEntriesGiveDefault;
    [Test]
    procedure LastDuplicateWins;
    [Test]
    procedure SetsNewEntry;
    [Test]
    procedure OverwritesEntry;
    [Test]
    procedure SortsById;
    [Test]
    procedure DropsInvalidEntries;
    [Test]
    procedure EmptyIdOnlyCleans;
    [Test]
    procedure RoundTrip;
  end;

implementation

{ TAtlasDesignerButtonStatesTests }

procedure TAtlasDesignerButtonStatesTests.EmptyGivesDefault;
begin
  Assert.IsTrue(TAtlasDesignerButtonStates.Pressed('', 'measure', True));
  Assert.IsFalse(TAtlasDesignerButtonStates.Pressed('', 'dataBindings', False));
end;

procedure TAtlasDesignerButtonStatesTests.ReadsStoredState;
const
  cText = 'dataBindings=1, measure=0';
begin
  Assert.IsTrue(TAtlasDesignerButtonStates.Pressed(cText, 'dataBindings', False));
  Assert.IsFalse(TAtlasDesignerButtonStates.Pressed(cText, 'measure', True));
  Assert.IsTrue(TAtlasDesignerButtonStates.Pressed(cText, 'gapHandles', True));
end;

procedure TAtlasDesignerButtonStatesTests.IdIgnoresCase;
begin
  Assert.IsTrue(TAtlasDesignerButtonStates.Pressed('DATABINDINGS=1', 'dataBindings', False));
end;

procedure TAtlasDesignerButtonStatesTests.InvalidEntriesGiveDefault;
begin
  Assert.IsTrue(TAtlasDesignerButtonStates.Pressed('measure', 'measure', True));
  Assert.IsTrue(TAtlasDesignerButtonStates.Pressed('measure=ja', 'measure', True));
  Assert.IsTrue(TAtlasDesignerButtonStates.Pressed('=0', 'measure', True));
  Assert.IsFalse(TAtlasDesignerButtonStates.Pressed('measure=2, tabOrder=1', 'measure', False));
end;

procedure TAtlasDesignerButtonStatesTests.LastDuplicateWins;
begin
  Assert.IsFalse(TAtlasDesignerButtonStates.Pressed('measure=1, Measure=0', 'measure', True));
end;

procedure TAtlasDesignerButtonStatesTests.SetsNewEntry;
begin
  Assert.AreEqual('dataBindings=1', TAtlasDesignerButtonStates.WithPressed('', 'dataBindings', True));
  Assert.AreEqual('measure=0', TAtlasDesignerButtonStates.WithPressed('', 'measure', False));
end;

procedure TAtlasDesignerButtonStatesTests.OverwritesEntry;
begin
  // Die Schreibweise der Kennung im Code gilt, auch wenn der gemerkte Eintrag anders geschrieben war.
  Assert.AreEqual('dataBindings=0, measure=0',
    TAtlasDesignerButtonStates.WithPressed('measure=0, DATABINDINGS=1', 'dataBindings', False));
end;

procedure TAtlasDesignerButtonStatesTests.SortsById;
begin
  Assert.AreEqual('dataBindings=1, measure=1, tabOrder=0',
    TAtlasDesignerButtonStates.WithPressed('tabOrder=0, measure=1', 'dataBindings', True));
end;

procedure TAtlasDesignerButtonStatesTests.DropsInvalidEntries;
begin
  Assert.AreEqual('measure=1, tabOrder=1',
    TAtlasDesignerButtonStates.WithPressed('kaputt, =1, x=ja, tabOrder=1', 'measure', True));
end;

procedure TAtlasDesignerButtonStatesTests.EmptyIdOnlyCleans;
begin
  Assert.AreEqual('tabOrder=1', TAtlasDesignerButtonStates.WithPressed('kaputt,tabOrder=1', '', True));
end;

procedure TAtlasDesignerButtonStatesTests.RoundTrip;
var
  mText: string;
begin
  mText := TAtlasDesignerButtonStates.WithPressed('', 'selectionBar', False);
  mText := TAtlasDesignerButtonStates.WithPressed(mText, 'gapHandles', True);
  Assert.IsFalse(TAtlasDesignerButtonStates.Pressed(mText, 'selectionBar', True));
  Assert.IsTrue(TAtlasDesignerButtonStates.Pressed(mText, 'gapHandles', False));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDesignerButtonStatesTests);

end.
