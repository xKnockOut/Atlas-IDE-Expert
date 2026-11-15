unit Atlas.Core.Completion.EditorPlan.Tests;

// Entscheidungen der Vervollständigung im Editor (Atlas.Core.Completion.EditorPlan): Navigationstasten, Kürzel,
// Commit-Zeichen, Präfix, Details und Überladungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompletionEditorPlanTests = class
  public
    [Test]
    procedure NavigationKeysMapToList;
    [Test]
    procedure CommandsNeedVisibleListAndState;
    [Test]
    procedure RevealInaccessibleWithoutList;
    [Test]
    procedure ChipKeysAltOneToSix;
    [Test]
    procedure KeyStepToggleOnlyInSetMode;
    [Test]
    procedure KeyStepEnterClosesPassiveList;
    [Test]
    procedure KeyStepEscapeOnEmptyList;
    [Test]
    procedure CommitCharactersBeforeCursor;
    [Test]
    procedure PrefixFromWordStart;
    [Test]
    procedure DetailsKeyNameAndData;
    [Test]
    procedure OverloadsWrapAround;
    [Test]
    procedure OverloadItemTakesData;
    [Test]
    procedure AvailabilityHintWithCondition;
  end;

implementation

uses
  System.Classes,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Completion.EditorPlan;

function FullState: TAtlasCompletionCommandState;
begin
  Result.Visible := True;
  Result.HasFavorites := True;
  Result.HasDocText := True;
  Result.HasOverloads := True;
  Result.ChipsEnabled := True;
  Result.CanRevealInaccessible := True;
end;

{ TCompletionEditorPlanTests }

procedure TCompletionEditorPlanTests.NavigationKeysMapToList;
var
  mKey: TAtlasNavigationKey;
begin
  Assert.IsTrue(TAtlasCompletionEditorPlan.NavigationKey(TAtlasCompletionEditorPlan.cVkDown, mKey));
  Assert.AreEqual<TAtlasNavigationKey>(TAtlasNavigationKey.Down, mKey);
  Assert.IsTrue(TAtlasCompletionEditorPlan.NavigationKey(TAtlasCompletionEditorPlan.cVkTab, mKey));
  Assert.AreEqual<TAtlasNavigationKey>(TAtlasNavigationKey.Accept, mKey);
  Assert.IsTrue(TAtlasCompletionEditorPlan.NavigationKey(TAtlasCompletionEditorPlan.cVkReturn, mKey));
  Assert.AreEqual<TAtlasNavigationKey>(TAtlasNavigationKey.Accept, mKey);
  Assert.IsTrue(TAtlasCompletionEditorPlan.NavigationKey(TAtlasCompletionEditorPlan.cVkEnd, mKey));
  Assert.AreEqual<TAtlasNavigationKey>(TAtlasNavigationKey.Last, mKey);
  Assert.IsTrue(TAtlasCompletionEditorPlan.NavigationKey(TAtlasCompletionEditorPlan.cVkSpace, mKey));
  Assert.AreEqual<TAtlasNavigationKey>(TAtlasNavigationKey.Toggle, mKey);
  Assert.IsFalse(TAtlasCompletionEditorPlan.NavigationKey(Ord('A'), mKey));
end;

procedure TCompletionEditorPlanTests.CommandsNeedVisibleListAndState;
var
  mState: TAtlasCompletionCommandState;
begin
  mState := FullState;
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.TogglePanel,
    TAtlasCompletionEditorPlan.Command(Ord('Q'), [ssCtrl], mState));
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.ToggleFavorite,
    TAtlasCompletionEditorPlan.Command(Ord('D'), [ssCtrl], mState));
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.CopyDoc,
    TAtlasCompletionEditorPlan.Command(Ord('C'), [ssCtrl], mState));
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.PreviousOverload,
    TAtlasCompletionEditorPlan.Command(TAtlasCompletionEditorPlan.cVkUp, [ssAlt], mState));
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.NextOverload,
    TAtlasCompletionEditorPlan.Command(TAtlasCompletionEditorPlan.cVkDown, [ssAlt], mState));
  // Andere Umschalttasten oder fehlender Zustand: nicht nehmen.
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.None,
    TAtlasCompletionEditorPlan.Command(Ord('Q'), [ssCtrl, ssShift], mState));
  mState.HasFavorites := False;
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.None,
    TAtlasCompletionEditorPlan.Command(Ord('D'), [ssCtrl], mState));
  mState.HasDocText := False;
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.None,
    TAtlasCompletionEditorPlan.Command(Ord('C'), [ssCtrl], mState));
  mState.HasOverloads := False;
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.None,
    TAtlasCompletionEditorPlan.Command(TAtlasCompletionEditorPlan.cVkUp, [ssAlt], mState));
  mState := FullState;
  mState.Visible := False;
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.None,
    TAtlasCompletionEditorPlan.Command(Ord('Q'), [ssCtrl], mState));
end;

procedure TCompletionEditorPlanTests.RevealInaccessibleWithoutList;
var
  mState: TAtlasCompletionCommandState;
begin
  mState := FullState;
  mState.Visible := False;
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.RevealInaccessible,
    TAtlasCompletionEditorPlan.Command(TAtlasCompletionEditorPlan.cVkSpace, [ssCtrl], mState));
  mState.CanRevealInaccessible := False;
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.None,
    TAtlasCompletionEditorPlan.Command(TAtlasCompletionEditorPlan.cVkSpace, [ssCtrl], mState));
end;

procedure TCompletionEditorPlanTests.ChipKeysAltOneToSix;
var
  mState: TAtlasCompletionCommandState;
begin
  mState := FullState;
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.SelectChip,
    TAtlasCompletionEditorPlan.Command(Ord('1'), [ssAlt], mState));
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.SelectChip,
    TAtlasCompletionEditorPlan.Command(Ord('6'), [ssAlt], mState));
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.None,
    TAtlasCompletionEditorPlan.Command(Ord('7'), [ssAlt], mState));
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.None,
    TAtlasCompletionEditorPlan.Command(Ord('1'), [ssCtrl], mState));
  Assert.AreEqual(0, TAtlasCompletionEditorPlan.ChipIndex(Ord('1')));
  Assert.AreEqual(5, TAtlasCompletionEditorPlan.ChipIndex(Ord('6')));
  mState.ChipsEnabled := False;
  Assert.AreEqual<TAtlasCompletionCommand>(TAtlasCompletionCommand.None,
    TAtlasCompletionEditorPlan.Command(Ord('1'), [ssAlt], mState));
end;

procedure TCompletionEditorPlanTests.KeyStepToggleOnlyInSetMode;
begin
  Assert.AreEqual<TAtlasCompletionKeyStep>(TAtlasCompletionKeyStep.Take,
    TAtlasCompletionEditorPlan.KeyStep(TAtlasNavigationKey.Toggle, True, True, False, False));
  Assert.AreEqual<TAtlasCompletionKeyStep>(TAtlasCompletionKeyStep.Pass,
    TAtlasCompletionEditorPlan.KeyStep(TAtlasNavigationKey.Toggle, True, False, False, False));
  Assert.AreEqual<TAtlasCompletionKeyStep>(TAtlasCompletionKeyStep.Pass,
    TAtlasCompletionEditorPlan.KeyStep(TAtlasNavigationKey.Toggle, False, True, False, False));
end;

procedure TCompletionEditorPlanTests.KeyStepEnterClosesPassiveList;
begin
  Assert.AreEqual<TAtlasCompletionKeyStep>(TAtlasCompletionKeyStep.CloseAndPass,
    TAtlasCompletionEditorPlan.KeyStep(TAtlasNavigationKey.Accept, True, False, True, False));
  Assert.AreEqual<TAtlasCompletionKeyStep>(TAtlasCompletionKeyStep.Take,
    TAtlasCompletionEditorPlan.KeyStep(TAtlasNavigationKey.Accept, True, False, False, False));
  Assert.AreEqual<TAtlasCompletionKeyStep>(TAtlasCompletionKeyStep.Pass,
    TAtlasCompletionEditorPlan.KeyStep(TAtlasNavigationKey.Down, False, False, False, False));
end;

procedure TCompletionEditorPlanTests.KeyStepEscapeOnEmptyList;
begin
  Assert.AreEqual<TAtlasCompletionKeyStep>(TAtlasCompletionKeyStep.Take,
    TAtlasCompletionEditorPlan.KeyStep(TAtlasNavigationKey.Cancel, False, False, False, True));
  Assert.AreEqual<TAtlasCompletionKeyStep>(TAtlasCompletionKeyStep.Pass,
    TAtlasCompletionEditorPlan.KeyStep(TAtlasNavigationKey.Down, False, False, False, True));
  Assert.AreEqual<TAtlasCompletionKeyStep>(TAtlasCompletionKeyStep.Pass,
    TAtlasCompletionEditorPlan.KeyStep(TAtlasNavigationKey.Cancel, False, False, False, False));
end;

procedure TCompletionEditorPlanTests.CommitCharactersBeforeCursor;
begin
  Assert.IsTrue(TAtlasCompletionEditorPlan.CommitsOnCharacter(True, 'Foo(', 4, 4, True));
  Assert.IsTrue(TAtlasCompletionEditorPlan.CommitsOnCharacter(True, 'Foo;', 4, 4, True));
  Assert.IsTrue(TAtlasCompletionEditorPlan.CommitsOnCharacter(True, 'Foo.', 4, 4, True));
  Assert.IsFalse(TAtlasCompletionEditorPlan.CommitsOnCharacter(True, 'Foo,', 4, 4, True));
  // Nicht direkt vor dem Cursor, abgeschaltet, nichts zu übernehmen oder außerhalb der Zeile.
  Assert.IsFalse(TAtlasCompletionEditorPlan.CommitsOnCharacter(True, 'Foo(x', 4, 5, True));
  Assert.IsFalse(TAtlasCompletionEditorPlan.CommitsOnCharacter(False, 'Foo(', 4, 4, True));
  Assert.IsFalse(TAtlasCompletionEditorPlan.CommitsOnCharacter(True, 'Foo(', 4, 4, False));
  Assert.IsFalse(TAtlasCompletionEditorPlan.CommitsOnCharacter(True, 'Foo', 4, 4, True));
  Assert.IsFalse(TAtlasCompletionEditorPlan.CommitsOnCharacter(True, '', 0, 0, True));
end;

procedure TCompletionEditorPlanTests.PrefixFromWordStart;
begin
  Assert.AreEqual('Wri', TAtlasCompletionEditorPlan.Prefix('  Wri', 2, 5));
  Assert.AreEqual('', TAtlasCompletionEditorPlan.Prefix('  Wri', 2, 2));
  Assert.AreEqual('Wr', TAtlasCompletionEditorPlan.Prefix('  Write', 2, 4));
end;

procedure TCompletionEditorPlanTests.DetailsKeyNameAndData;
var
  mItem, mOther: TAtlasCompletionItem;
begin
  mItem := Default(TAtlasCompletionItem);
  mItem.Name := 'Add';
  mItem.ResolveData := '1';
  mOther := mItem;
  mOther.ResolveData := '2';
  Assert.AreNotEqual(TAtlasCompletionEditorPlan.DetailsKey(mItem), TAtlasCompletionEditorPlan.DetailsKey(mOther));
  mOther.ResolveData := '1';
  Assert.AreEqual(TAtlasCompletionEditorPlan.DetailsKey(mItem), TAtlasCompletionEditorPlan.DetailsKey(mOther));
  // Name und Daten bleiben getrennt.
  mItem.Name := 'Ad';
  mItem.ResolveData := 'd1';
  Assert.AreNotEqual(TAtlasCompletionEditorPlan.DetailsKey(mItem), TAtlasCompletionEditorPlan.DetailsKey(mOther));
end;

procedure TCompletionEditorPlanTests.OverloadsWrapAround;
begin
  Assert.AreEqual(1, TAtlasCompletionEditorPlan.NextOverload(0, 1, 3));
  Assert.AreEqual(0, TAtlasCompletionEditorPlan.NextOverload(2, 1, 3));
  Assert.AreEqual(2, TAtlasCompletionEditorPlan.NextOverload(0, -1, 3));
  Assert.AreEqual(0, TAtlasCompletionEditorPlan.NextOverload(0, 1, 0));
end;

procedure TCompletionEditorPlanTests.OverloadItemTakesData;
var
  mItem: TAtlasCompletionItem;
begin
  mItem := Default(TAtlasCompletionItem);
  mItem.Name := 'Add';
  mItem.ResolveData := 'erste';
  mItem.OverloadData := TArray<string>.Create('zweite', 'dritte');
  Assert.AreEqual('erste', TAtlasCompletionEditorPlan.OverloadItem(mItem, 0).ResolveData);
  Assert.AreEqual('zweite', TAtlasCompletionEditorPlan.OverloadItem(mItem, 1).ResolveData);
  Assert.AreEqual('dritte', TAtlasCompletionEditorPlan.OverloadItem(mItem, 2).ResolveData);
  Assert.AreEqual('erste', TAtlasCompletionEditorPlan.OverloadItem(mItem, 3).ResolveData);
  Assert.AreEqual('Add', TAtlasCompletionEditorPlan.OverloadItem(mItem, 1).Name);
end;

procedure TCompletionEditorPlanTests.AvailabilityHintWithCondition;
var
  mItem: TAtlasCompletionItem;
begin
  mItem := Default(TAtlasCompletionItem);
  mItem.Unavailable := True;
  mItem.Condition := 'DEBUG';
  Assert.IsTrue(TAtlasCompletionEditorPlan.ShowsAvailability(mItem));
  mItem.Condition := 'Platform';
  Assert.IsFalse(TAtlasCompletionEditorPlan.ShowsAvailability(mItem));
  mItem.Condition := '';
  Assert.IsFalse(TAtlasCompletionEditorPlan.ShowsAvailability(mItem));
  mItem.Condition := 'DEBUG';
  mItem.Unavailable := False;
  Assert.IsFalse(TAtlasCompletionEditorPlan.ShowsAvailability(mItem));
end;

end.
