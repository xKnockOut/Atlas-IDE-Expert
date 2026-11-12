unit Atlas.UI.Tracker.ReviewDialog.Tests;

// Tests des Dialogs „ATL-2052 prüfen“ (#2126): Zeilen der Schritte mit
// Zeichen, {build}/{tests}-Texte, Einträge „Ergebnis“ mit und ohne
// Zustandsmaschine, Kommentar folgt der Vorlage, bis der Benutzer ihn ändert,
// Rückweg nur nach dem Wechsel, Schließen meldet genau einmal.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerReviewDialogTests = class
  private
    FSaved: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure StepTexts;
    [Test]
    procedure BuildAndTestsTexts;
    [Test]
    procedure ResultChoicesWithAndWithoutRules;
    [Test]
    procedure CommentFollowsResultsUntilEdited;
    [Test]
    procedure BackOnlyAfterSwitch;
    [Test]
    procedure ChangeUnderStateMachine;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Review,
  Atlas.Core.Tracker.Workflow,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.ReviewDialog;

function Options: TAtlasTrackerSyncOptions;
begin
  Result := TAtlasTrackerSyncOptions.Create(True, 'Status', '').WithReview('Zur Prüfung');
end;

function Rules: TAtlasTrackerStateRules;
begin
  Result := Default(TAtlasTrackerStateRules);
  Result.StateMachine := True;
  Result.FieldId := '82-11';
  Result.Current := 'Zur Prüfung';
  Result.Transitions := [TAtlasTrackerTransition.Create('verifiziert', 'Verifizieren'),
    TAtlasTrackerTransition.Create('offen', 'Zurückgeben')];
end;

function Built(AErrors: Integer): TAtlasReviewState;
var
  mBuild: TAtlasReviewBuild;
begin
  Result := TAtlasReviewState.Create('ATL-2052', True);
  Result.OwnBranch := 'issue/ATL-2060';
  Result.Branch := 'issue/ATL-2052';
  Result.Marks[TAtlasReviewStep.Saved] := TAtlasReviewMark.Done;
  Result.Marks[TAtlasReviewStep.Switched] := TAtlasReviewMark.Done;
  mBuild := Default(TAtlasReviewBuild);
  mBuild.Platform := 'Win64';
  mBuild.Configuration := 'Debug';
  mBuild.Errors := AErrors;
  mBuild.Succeeded := AErrors = 0;
  Result.Built(mBuild);
end;

{ TAtlasTrackerReviewDialogTests }

procedure TAtlasTrackerReviewDialogTests.Setup;
begin
  FSaved := Ord(TAtlasStrings.Language);
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasTrackerReviewDialogTests.TearDown;
begin
  TAtlasStrings.Language := TAtlasLanguage(FSaved);
end;

procedure TAtlasTrackerReviewDialogTests.StepTexts;
var
  mState: TAtlasReviewState;
begin
  mState := Built(0);
  Assert.AreEqual('✓ Eigener Stand gemerkt (issue/ATL-2060)',
    TAtlasTrackerReviewDialog.StepText(mState, TAtlasReviewStep.Saved));
  Assert.AreEqual('✓ Branch gewechselt (issue/ATL-2052)',
    TAtlasTrackerReviewDialog.StepText(mState, TAtlasReviewStep.Switched));
  Assert.AreEqual('✓ Build Win64 Debug 0/0/0', TAtlasTrackerReviewDialog.StepText(mState, TAtlasReviewStep.Build));
  Assert.AreEqual('○ Tests warten', TAtlasTrackerReviewDialog.StepText(mState, TAtlasReviewStep.Tests));
  mState.Marks[TAtlasReviewStep.Switched] := TAtlasReviewMark.Failed;
  mState.SwitchError := 'Failed';
  Assert.AreEqual('✗ Wechsel auf issue/ATL-2052 gescheitert (Failed)',
    TAtlasTrackerReviewDialog.StepText(mState, TAtlasReviewStep.Switched));
  mState.OwnBranch := '';
  Assert.AreEqual('✓ Eigener Stand: kein Branch erkannt, kein Rückweg',
    TAtlasTrackerReviewDialog.StepText(mState, TAtlasReviewStep.Saved));
end;

procedure TAtlasTrackerReviewDialogTests.BuildAndTestsTexts;
var
  mState: TAtlasReviewState;
begin
  mState := Built(2);
  Assert.AreEqual('Build Win64 Debug mit 2 Fehlern', TAtlasTrackerReviewDialog.BuildText(mState));
  Assert.AreEqual('Tests ausgelassen', TAtlasTrackerReviewDialog.TestsText(mState));
  mState := Built(0);
  mState.Tested(12, 2);
  Assert.AreEqual('2 von 14 Tests fehlgeschlagen', TAtlasTrackerReviewDialog.TestsText(mState));
  mState.Tested(14, 0);
  Assert.AreEqual('14 Tests bestanden', TAtlasTrackerReviewDialog.TestsText(mState));
  mState := TAtlasReviewState.Create('ATL-2052', True);
  mState.Built(Default(TAtlasReviewBuild));
  Assert.AreEqual('Build nicht gestartet', TAtlasTrackerReviewDialog.BuildText(mState), 'ohne Fehler kein Ergebnis');
  mState := TAtlasReviewState.Create('ATL-2052', False);
  Assert.AreEqual('Build ausgelassen', TAtlasTrackerReviewDialog.BuildText(mState));
end;

procedure TAtlasTrackerReviewDialogTests.ResultChoicesWithAndWithoutRules;
var
  mChoices: TArray<string>;
begin
  mChoices := TAtlasTrackerReviewDialog.ResultChoices(Rules, TArray<string>.Create('Verifiziert', 'Offen'),
    'Zur Prüfung');
  Assert.AreEqual(3, Integer(Length(mChoices)), string.Join('|', mChoices));
  Assert.AreEqual('Zustand nicht ändern', mChoices[0]);
  Assert.AreEqual('Verifizieren → Verifiziert', mChoices[1]);
  Assert.AreEqual('Zurückgeben → Offen', mChoices[2]);
  // Ohne Zustandsmaschine: die Zustände vom Tracker außer dem aktuellen.
  mChoices := TAtlasTrackerReviewDialog.ResultChoices(Default(TAtlasTrackerStateRules),
    TArray<string>.Create('Offen', 'Zur Prüfung', 'Verifiziert'), ' zur prüfung ');
  Assert.AreEqual('Zustand nicht ändern|Offen|Verifiziert', string.Join('|', mChoices));
end;

procedure TAtlasTrackerReviewDialogTests.CommentFollowsResultsUntilEdited;
var
  mDialog: TAtlasTrackerReviewDialog;
  mState: TAtlasReviewState;
begin
  mState := Built(0);
  mDialog := TAtlasTrackerReviewDialog.CreateDialog(nil, mState, Options, TAtlasTrackerReview.cDefaultComment);
  try
    Assert.AreEqual('ATL-2052 prüfen', mDialog.Caption);
    Assert.AreEqual('Geprüft: Build Win64 Debug 0/0/0, Tests warten.', mDialog.Parts.Editor.Text);
    mState.Tested(14, 0);
    mDialog.ShowState(mState);
    Assert.AreEqual('Geprüft: Build Win64 Debug 0/0/0, 14 Tests bestanden.', mDialog.Parts.Editor.Text);
    // Vom Benutzer geändert: bleibt.
    mDialog.Parts.Editor.SetText('Sieht gut aus.');
    mState.Tested(12, 2);
    mDialog.ShowState(mState);
    Assert.AreEqual('Sieht gut aus.', mDialog.Parts.Editor.Text);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerReviewDialogTests.BackOnlyAfterSwitch;
var
  mDialog: TAtlasTrackerReviewDialog;
  mState: TAtlasReviewState;
  mCalls: Integer;
  mReturn: Boolean;
  mEvents: TAtlasReviewDialogEvents;
begin
  mState := TAtlasReviewState.Create('ATL-2052', False);
  mState.OwnBranch := 'issue/ATL-2060';
  mDialog := TAtlasTrackerReviewDialog.CreateDialog(nil, mState, Options, '');
  try
    Assert.AreEqual('Danach zurück zu issue/ATL-2060 (mein Stand)', mDialog.Parts.Back.Caption);
    Assert.IsFalse(mDialog.Parts.Back.Enabled, 'noch nicht gewechselt');
    Assert.AreEqual('Senden', mDialog.Parts.Send.Caption);
    mState.Branch := 'issue/ATL-2052';
    mState.Marks[TAtlasReviewStep.Switched] := TAtlasReviewMark.Done;
    mDialog.ShowState(mState);
    Assert.IsTrue(mDialog.Parts.Back.Enabled);
    Assert.AreEqual('Senden und zurück', mDialog.Parts.Send.Caption);
    mCalls := 0;
    mReturn := False;
    mEvents := Default(TAtlasReviewDialogEvents);
    mEvents.Closed :=
      procedure(AReturn: Boolean)
      begin
        Inc(mCalls);
        mReturn := AReturn;
      end;
    mDialog.Events := mEvents;
    mDialog.Parts.Later.Click;
    Assert.AreEqual(1, mCalls);
    Assert.IsTrue(mReturn);
  finally
    mDialog.Free;
  end;
  Assert.AreEqual(1, mCalls, 'Freigeben meldet nicht noch einmal');
end;

procedure TAtlasTrackerReviewDialogTests.ChangeUnderStateMachine;
var
  mDialog: TAtlasTrackerReviewDialog;
  mChange: TAtlasTrackerWrite;
begin
  mDialog := TAtlasTrackerReviewDialog.CreateDialog(nil, Built(0), Options, 'ok');
  try
    mDialog.SetStates(TArray<string>.Create('Verifiziert', 'Offen'), Rules);
    Assert.AreEqual(3, mDialog.Parts.Choice.Items.Count);
    Assert.AreEqual(0, mDialog.Parts.Choice.ItemIndex, 'Vorgabe: Zustand nicht ändern');
    mDialog.Parts.Choice.ItemIndex := 1;
    mChange := mDialog.Change;
    Assert.AreEqual('verifiziert', mChange.Transition.Id);
    Assert.AreEqual('82-11', mChange.FieldId);
    Assert.AreEqual('ok', mChange.Comment);
    mDialog.Parts.Choice.ItemIndex := 0;
    Assert.AreEqual('', mDialog.Change.Transition.Id);
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerReviewDialogTests);

end.
