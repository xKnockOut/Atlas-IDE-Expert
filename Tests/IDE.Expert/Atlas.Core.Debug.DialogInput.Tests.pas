unit Atlas.Core.Debug.DialogInput.Tests;

// Tests für die Entscheidungen der Vervollständigung in den Debugger-Dialogen (#538, #1967): Beschriftung über
// die Lage der Labels, ganz markierter Text, Mitgliederliste nach „.“, offene Liste nach einer Eingabe, übernommene
// Tasten und der ersetzte Bereich beim Übernehmen; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDialogInputTests = class
  public
    [Test]
    procedure LabelLeftOrAboveCounts;
    [Test]
    procedure NearestLabelWins;
    [Test]
    procedure AllSelectedNeedsWholeText;
    [Test]
    procedure MemberTriggerAfterDot;
    [Test]
    procedure FollowClosesQueriesOrUpdates;
    [Test]
    procedure WantsCtrlSpaceAndListKeys;
    [Test]
    procedure WantsDownOnlyInEmptyForeignField;
    [Test]
    procedure CommitReplacesWholeWord;
    [Test]
    procedure CommitInHistoryReplacesField;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Debug.DialogInput;

function Field: TRect;
begin
  Result := TRect.Create(100, 50, 300, 70);
end;

function Keys: TAtlasDialogKeyInput;
begin
  Result := Default(TAtlasDialogKeyInput);
  Result.Tracked := True;
  Result.Plain := True;
end;

{ TAtlasDialogInputTests }

procedure TAtlasDialogInputTests.LabelLeftOrAboveCounts;
var
  mDistance: Integer;
begin
  Assert.IsTrue(TAtlasDialogInput.LabelDistance(TRect.Create(20, 52, 90, 68), Field, mDistance));
  Assert.AreEqual(10, mDistance);
  Assert.IsTrue(TAtlasDialogInput.LabelDistance(TRect.Create(100, 30, 160, 46), Field, mDistance));
  Assert.AreEqual(4, mDistance);
  // Rechts daneben bzw. in anderer Höhe: keine Beschriftung.
  Assert.IsFalse(TAtlasDialogInput.LabelDistance(TRect.Create(310, 52, 360, 68), Field, mDistance));
  Assert.IsFalse(TAtlasDialogInput.LabelDistance(TRect.Create(20, 100, 90, 116), Field, mDistance));
end;

procedure TAtlasDialogInputTests.NearestLabelWins;
begin
  Assert.AreEqual('&Ausdruck:', TAtlasDialogInput.NearestLabel([
    TAtlasDialogLabel.Create('Weit', TRect.Create(0, 52, 40, 68)),
    TAtlasDialogLabel.Create('&Ausdruck:', TRect.Create(50, 52, 95, 68)),
    TAtlasDialogLabel.Create('Daneben', TRect.Create(310, 52, 360, 68))], Field));
  Assert.AreEqual('', TAtlasDialogInput.NearestLabel(nil, Field));
end;

procedure TAtlasDialogInputTests.AllSelectedNeedsWholeText;
begin
  Assert.IsTrue(TAtlasDialogInput.AllSelected('abc', 0, 3));
  Assert.IsFalse(TAtlasDialogInput.AllSelected('abc', 0, 2));
  Assert.IsFalse(TAtlasDialogInput.AllSelected('abc', 1, 3));
  Assert.IsFalse(TAtlasDialogInput.AllSelected('', 0, 0));
end;

procedure TAtlasDialogInputTests.MemberTriggerAfterDot;
begin
  Assert.IsTrue(TAtlasDialogInput.MemberTrigger('Self.FLi', 8, 'FLi'));
  Assert.IsTrue(TAtlasDialogInput.MemberTrigger('Self.', 5, ''));
  Assert.IsFalse(TAtlasDialogInput.MemberTrigger('Self', 4, 'Self'));
  Assert.IsFalse(TAtlasDialogInput.MemberTrigger('a + b', 5, 'b'));
end;

procedure TAtlasDialogInputTests.FollowClosesQueriesOrUpdates;
begin
  Assert.AreEqual<TAtlasDialogFollow>(TAtlasDialogFollow.Close, TAtlasDialogInput.Follow(True, True, False));
  Assert.AreEqual<TAtlasDialogFollow>(TAtlasDialogFollow.Close, TAtlasDialogInput.Follow(False, False, True));
  Assert.AreEqual<TAtlasDialogFollow>(TAtlasDialogFollow.Query, TAtlasDialogInput.Follow(False, True, True));
  Assert.AreEqual<TAtlasDialogFollow>(TAtlasDialogFollow.UpdatePrefix, TAtlasDialogInput.Follow(False, True, False));
end;

procedure TAtlasDialogInputTests.WantsCtrlSpaceAndListKeys;
var
  mInput: TAtlasDialogKeyInput;
begin
  mInput := Keys;
  mInput.Plain := False;
  mInput.CtrlSpace := True;
  Assert.IsTrue(TAtlasDialogInput.WantsKey(mInput));
  mInput.Tracked := False;
  Assert.IsFalse(TAtlasDialogInput.WantsKey(mInput));
  mInput := Keys;
  mInput.Navigation := True;
  Assert.IsFalse(TAtlasDialogInput.WantsKey(mInput));
  mInput.ListVisible := True;
  Assert.IsTrue(TAtlasDialogInput.WantsKey(mInput));
  // Mit Umschalttaste gehört die Taste dem Dialog.
  mInput.Plain := False;
  Assert.IsFalse(TAtlasDialogInput.WantsKey(mInput));
end;

procedure TAtlasDialogInputTests.WantsDownOnlyInEmptyForeignField;
var
  mInput: TAtlasDialogKeyInput;
begin
  mInput := Keys;
  mInput.Down := True;
  mInput.FieldEmpty := True;
  Assert.IsTrue(TAtlasDialogInput.WantsKey(mInput));
  mInput.OwnField := True;
  Assert.IsFalse(TAtlasDialogInput.WantsKey(mInput));
  mInput.OwnField := False;
  mInput.ListActive := True;
  Assert.IsFalse(TAtlasDialogInput.WantsKey(mInput));
  mInput.ListActive := False;
  mInput.FieldEmpty := False;
  Assert.IsFalse(TAtlasDialogInput.WantsKey(mInput));
end;

procedure TAtlasDialogInputTests.CommitReplacesWholeWord;
var
  mCommit: TAtlasDialogCommit;
begin
  // „Self.FLi|st + 1“: das ganze Wort FList ersetzen.
  mCommit := TAtlasDialogInput.Commit('Self.FList + 1', 8, 5, 'FLines', False);
  Assert.AreEqual(5, mCommit.SelStart);
  Assert.AreEqual(10, mCommit.SelStop);
  Assert.AreEqual(11, mCommit.Caret);
  // Ohne Wortanfang ab der Schreibmarke.
  mCommit := TAtlasDialogInput.Commit('', 0, -1, 'X', False);
  Assert.AreEqual(0, mCommit.SelStart);
  Assert.AreEqual(0, mCommit.SelStop);
  Assert.AreEqual(1, mCommit.Caret);
end;

procedure TAtlasDialogInputTests.CommitInHistoryReplacesField;
var
  mCommit: TAtlasDialogCommit;
begin
  mCommit := TAtlasDialogInput.Commit('alt', 3, 0, 'Kunde.Name', True);
  Assert.AreEqual(0, mCommit.SelStart);
  Assert.AreEqual(-1, mCommit.SelStop);
  Assert.AreEqual(10, mCommit.Caret);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDialogInputTests);

end.
