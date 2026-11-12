unit Atlas.UI.Tracker.EndDialog.Tests;

// Tests des Dialogs „ATL-123 beenden“ (#1266) und der Klappliste mit Eingabe
// von Hand: Vorschläge und Vorgabe des Zielzustands, Änderung aus den
// Feldern, „Senden“ ohne etwas zu schreiben, Fehler im Dialog mit dem Text
// des Trackers (400/401/403/404, Zeitlimit) und die Zeile der Meldungsansicht;
// unter einer Zustandsmaschine (#2122) nur die erlaubten Übergänge; größer
// ziehen (#2131).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerEndDialogTests = class
  private
    FSaved: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ValueBoxKeepsTextWithoutWindow;
    [Test]
    procedure StateChoicesAndDefault;
    [Test]
    procedure ChangeFromFields;
    [Test]
    procedure SendWithoutWorkWritesNothing;
    /// <summary>Fehler bleiben im Dialog, nichts wird wiederholt; Erfolg schließt mit der Änderung.</summary>
    [Test]
    procedure SendShowsErrorThenSucceeds;
    [Test]
    procedure ErrorTexts;
    [Test]
    procedure SummaryText;
    [Test]
    procedure TransitionsUnderStateMachine;
    [Test]
    procedure SummaryTextWithTransition;
    [Test]
    procedure GrowsWithWindow;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Forms,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Workflow,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.ValueBox,
  Atlas.UI.Tracker.EndDialog;

function Options(const AEndStates: string): TAtlasTrackerSyncOptions;
begin
  Result := TAtlasTrackerSyncOptions.Create(True, 'Status', '').WithStart('In Arbeit', False, '').WithEnd(AEndStates, '');
end;

{ TAtlasTrackerEndDialogTests }

procedure TAtlasTrackerEndDialogTests.Setup;
begin
  FSaved := Ord(TAtlasStrings.Language);
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasTrackerEndDialogTests.TearDown;
begin
  TAtlasStrings.Language := TAtlasLanguage(FSaved);
end;

procedure TAtlasTrackerEndDialogTests.ValueBoxKeepsTextWithoutWindow;
var
  mBox: TAtlasValueBox;
begin
  mBox := TAtlasValueBox.Create(nil);
  try
    mBox.Value := ' In Arbeit ';
    mBox.SetValues(TArray<string>.Create('Offen', 'In Arbeit'));
    Assert.AreEqual('In Arbeit', mBox.Value, 'ohne Fenster, ohne Leerraum außen');
    Assert.AreEqual(2, Integer(Length(mBox.Values)));
    Assert.IsTrue(mBox.Style = csDropDown, 'Eingabe von Hand');
  finally
    mBox.Free;
  end;
end;

procedure TAtlasTrackerEndDialogTests.StateChoicesAndDefault;
var
  mChoices: TArray<string>;
  mDialog: TAtlasTrackerEndDialog;
begin
  mChoices := TAtlasTrackerEndDialog.StateChoices(Options('Zur Prüfung, Erledigt'));
  Assert.AreEqual(3, Integer(Length(mChoices)));
  Assert.AreEqual('Zustand nicht ändern', mChoices[0]);
  Assert.AreEqual('Zur Prüfung', mChoices[1]);
  mDialog := TAtlasTrackerEndDialog.CreateDialog(nil, 'ATL-123', Options('Zur Prüfung, Erledigt'), 'Text');
  try
    Assert.AreEqual('ATL-123 beenden', mDialog.Caption);
    Assert.AreEqual('Zur Prüfung', mDialog.Parts.State.Value, 'Vorgabe: der erste Zielzustand');
    // Werte vom Tracker kommen hinter die eingestellten, ohne doppelte.
    mDialog.SetStates(TArray<string>.Create('erledigt', 'Offen'));
    Assert.AreEqual(4, Integer(Length(mDialog.Parts.State.Values)));
    Assert.AreEqual('Offen', mDialog.Parts.State.Values[3]);
    mDialog.SetUsers(TArray<string>.Create('anna', 'bert'));
    Assert.AreEqual(2, Integer(Length(mDialog.Parts.Assignee.Values)));
  finally
    mDialog.Free;
  end;
  mDialog := TAtlasTrackerEndDialog.CreateDialog(nil, 'ATL-1', Options(''), '');
  try
    Assert.AreEqual('Zustand nicht ändern', mDialog.Parts.State.Value, 'ohne Zielzustände');
    Assert.IsFalse(mDialog.Parts.HandOver.Checked);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerEndDialogTests.ChangeFromFields;
var
  mDialog: TAtlasTrackerEndDialog;
  mChange: TAtlasTrackerWrite;
begin
  mDialog := TAtlasTrackerEndDialog.CreateDialog(nil, 'ATL-123', Options('Erledigt'), 'Erledigt in x.'#10'abc1234 y');
  try
    Assert.AreEqual('Erledigt in x.'#13#10'abc1234 y', mDialog.Parts.Comment.Text, 'Zeilen für das Memo');
    mDialog.Parts.Assignee.Value := 'anna';
    mDialog.Parts.HandOver.Checked := True;
    mChange := mDialog.Change;
    Assert.AreEqual('Erledigt', mChange.State);
    Assert.AreEqual('Status', mChange.StateField);
    Assert.AreEqual('In Arbeit', mChange.PreviousState);
    Assert.AreEqual('Erledigt in x.'#10'abc1234 y', mChange.Comment, 'Zeilen mit #10 an den Tracker');
    Assert.AreEqual(Ord(TAtlasTrackerAssign.User), Ord(mChange.Assign));
    Assert.AreEqual('anna', mChange.Assignee);
    // „Zustand nicht ändern“ und ohne Häkchen: nur der Kommentar.
    mDialog.Parts.State.Value := 'Zustand nicht ändern';
    mDialog.Parts.HandOver.Checked := False;
    mChange := mDialog.Change;
    Assert.AreEqual('', mChange.State);
    Assert.AreEqual(Ord(TAtlasTrackerAssign.Keep), Ord(mChange.Assign));
    // Zustand von Hand eingetragen.
    mDialog.Parts.State.Value := 'Wartet auf Kunde';
    Assert.AreEqual('Wartet auf Kunde', mDialog.Change.State);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerEndDialogTests.SendWithoutWorkWritesNothing;
var
  mDialog: TAtlasTrackerEndDialog;
  mCalls: Integer;
begin
  mCalls := 0;
  mDialog := TAtlasTrackerEndDialog.CreateDialog(nil, 'ATL-1', Options(''), '');
  try
    mDialog.OnSend :=
      procedure(const AChange: TAtlasTrackerWrite; const ADone: TAtlasTrackerSendDone)
      begin
        Inc(mCalls);
      end;
    mDialog.Parts.Send.Click;
    Assert.AreEqual(0, mCalls, 'nichts zu schreiben');
    Assert.IsTrue(mDialog.Sent);
    Assert.AreEqual(Integer(mrOk), Integer(mDialog.ModalResult));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerEndDialogTests.SendShowsErrorThenSucceeds;
var
  mDialog: TAtlasTrackerEndDialog;
  mCalls: Integer;
  mPending: TAtlasTrackerSendDone;
begin
  mCalls := 0;
  mPending := nil;
  mDialog := TAtlasTrackerEndDialog.CreateDialog(nil, 'ATL-123', Options('Erledigt'), 'Fertig');
  try
    mDialog.OnSend :=
      procedure(const AChange: TAtlasTrackerWrite; const ADone: TAtlasTrackerSendDone)
      begin
        Inc(mCalls);
        mPending := ADone;
      end;
    mDialog.Parts.Send.Click;
    Assert.AreEqual(1, mCalls);
    Assert.IsTrue(mDialog.Sending);
    Assert.IsFalse(mDialog.Parts.Cancel.Enabled, 'während des Sendens kein Abbrechen');
    Assert.IsFalse(mDialog.Parts.Send.Enabled);
    mDialog.Parts.Send.Click;
    Assert.AreEqual(1, mCalls, 'kein zweites Senden');
    mPending(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Unauthorized, 403, ''));
    Assert.IsFalse(mDialog.Sending);
    Assert.IsFalse(mDialog.Sent);
    Assert.AreEqual('Keine Schreibrechte für ATL-123 (403).', mDialog.Parts.Note.Caption);
    Assert.AreEqual(Integer(mrNone), Integer(mDialog.ModalResult), 'Dialog bleibt offen');
    Assert.AreEqual(1, mCalls, 'nichts wird wiederholt');
    mDialog.Parts.Send.Click;
    Assert.AreEqual(2, mCalls, 'erneut erst nach Klick');
    mPending(TAtlasTrackerWriteResult.Ok);
    Assert.IsTrue(mDialog.Sent);
    Assert.AreEqual('Erledigt', mDialog.SentChange.State);
    Assert.AreEqual(Integer(mrOk), Integer(mDialog.ModalResult));
  finally
    mDialog.Free;
  end;
  mPending := nil;
end;

procedure TAtlasTrackerEndDialogTests.ErrorTexts;
begin
  Assert.AreEqual('', TAtlasTrackerEndDialog.ErrorText('ATL-1', TAtlasTrackerWriteResult.Ok));
  Assert.AreEqual('Keine Schreibrechte für ATL-123 (403).', TAtlasTrackerEndDialog.ErrorText('ATL-123',
    TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Unauthorized, 403, '')));
  Assert.AreEqual('Zugang für ATL-123 abgelehnt (401): Token prüfen.', TAtlasTrackerEndDialog.ErrorText('ATL-123',
    TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Unauthorized, 401, '')));
  Assert.AreEqual('ATL-123 nicht gefunden (404).', TAtlasTrackerEndDialog.ErrorText('ATL-123',
    TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotFound, 404, '')));
  Assert.AreEqual('Der Tracker lehnt die Änderung an ATL-123 ab (400). Antwort des Trackers: Unknown state',
    TAtlasTrackerEndDialog.ErrorText('ATL-123', TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 400,
    'Unknown state')), 'mit dem Text des Trackers');
  Assert.AreEqual('Der Tracker antwortet nicht (Zeitlimit).', TAtlasTrackerEndDialog.ErrorText('ATL-1',
    TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Timeout, 0, '')));
  Assert.AreEqual('Tracker nicht erreichbar.', TAtlasTrackerEndDialog.ErrorText('ATL-1',
    TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '')));
  Assert.AreEqual('Kein Tracker oder kein Token für dieses Projekt.', TAtlasTrackerEndDialog.ErrorText('ATL-1',
    TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, '')));
end;

procedure TAtlasTrackerEndDialogTests.SummaryText;
var
  mChange: TAtlasTrackerWrite;
begin
  mChange := TAtlasTrackerWrite.Empty;
  Assert.AreEqual('', TAtlasTrackerEndDialog.SummaryText(mChange));
  mChange.State := 'In Arbeit';
  mChange.Assign := TAtlasTrackerAssign.Me;
  mChange.Comment := 'x';
  Assert.AreEqual('Zustand „In Arbeit“, mir zugewiesen, Kommentar', TAtlasTrackerEndDialog.SummaryText(mChange));
  mChange := TAtlasTrackerWrite.Empty;
  mChange.Assign := TAtlasTrackerAssign.User;
  mChange.Assignee := 'anna';
  Assert.AreEqual('an anna übergeben', TAtlasTrackerEndDialog.SummaryText(mChange));
end;

/// <summary>Zustandsmaschine ab „In Bearbeitung“ mit benannten Ereignissen.</summary>
function NamedRules: TAtlasTrackerStateRules;
begin
  Result := Default(TAtlasTrackerStateRules);
  Result.StateMachine := True;
  Result.FieldId := '82-11';
  Result.Current := 'In Bearbeitung';
  Result.Transitions := [TAtlasTrackerTransition.Create('review', 'Zur Prüfung geben'),
    TAtlasTrackerTransition.Create('zurueckgestellt', 'Zurückstellen'),
    TAtlasTrackerTransition.Create('offen', 'Abbrechen')];
end;

procedure TAtlasTrackerEndDialogTests.TransitionsUnderStateMachine;
var
  mDialog: TAtlasTrackerEndDialog;
  mChange: TAtlasTrackerWrite;
begin
  mDialog := TAtlasTrackerEndDialog.CreateDialog(nil, 'ATL-2052', Options('Behoben, Offen'), 'Fertig');
  try
    mDialog.SetStates(TArray<string>.Create('Neu', 'Zurückgestellt', 'Behoben'));
    mDialog.SetRules(NamedRules);
    Assert.AreEqual('Übergang (ab „In Bearbeitung“):', mDialog.Parts.StateLabel.Caption);
    Assert.AreEqual(4, Integer(Length(mDialog.Parts.State.Values)), 'nur „nicht ändern“ und die Übergänge');
    Assert.AreEqual('Zustand nicht ändern', mDialog.Parts.State.Values[0]);
    Assert.AreEqual('Zur Prüfung geben', mDialog.Parts.State.Values[1]);
    Assert.AreEqual('Zurückstellen', mDialog.Parts.State.Values[2], 'Kennung "zurueckgestellt" verrät kein Ziel');
    Assert.AreEqual('Abbrechen → Offen', mDialog.Parts.State.Values[3], 'Ziel über die Kennung');
    Assert.AreEqual('Abbrechen → Offen', mDialog.Parts.State.Value, '„Behoben“ geht nicht, „Offen“ schon');
    Assert.AreEqual('„Behoben“ ist ab „In Bearbeitung“ nicht erlaubt.', mDialog.Parts.Note.Caption);
    mChange := mDialog.Change;
    Assert.AreEqual('offen', mChange.Transition.Id);
    Assert.AreEqual('82-11', mChange.FieldId);
    Assert.AreEqual('', mChange.State, 'kein Befehl mit dem Wert');
    Assert.AreEqual('Fertig', mChange.Comment);
    mDialog.Parts.State.Value := 'Zur Prüfung geben';
    Assert.AreEqual('review', mDialog.Change.Transition.Id);
    mDialog.Parts.State.Value := 'Zustand nicht ändern';
    Assert.AreEqual('', mDialog.Change.Transition.Id);
    Assert.AreEqual('', mDialog.Change.State);
    // Von Hand: Name eines Übergangs wird zum Übergang, Unbekanntes geht als Wert hinaus.
    mDialog.Parts.State.Value := 'zurückstellen';
    Assert.AreEqual('zurueckgestellt', mDialog.Change.Transition.Id);
    mDialog.Parts.State.Value := 'Wartet';
    Assert.AreEqual('', mDialog.Change.Transition.Id);
    Assert.AreEqual('Wartet', mDialog.Change.State);
  finally
    mDialog.Free;
  end;
  // Ohne Zustandsmaschine bleibt die Liste der Zustände.
  mDialog := TAtlasTrackerEndDialog.CreateDialog(nil, 'ATL-1', Options('Erledigt'), '');
  try
    mDialog.SetRules(Default(TAtlasTrackerStateRules));
    Assert.AreEqual('Erledigt', mDialog.Parts.State.Value);
    Assert.AreEqual('Erledigt', mDialog.Change.State);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerEndDialogTests.SummaryTextWithTransition;
var
  mChange: TAtlasTrackerWrite;
begin
  mChange := TAtlasTrackerWrite.Empty;
  mChange.Transition := TAtlasTrackerTransition.Create('start', 'Beginnen');
  mChange.Assign := TAtlasTrackerAssign.Me;
  Assert.AreEqual('Übergang „Beginnen“, mir zugewiesen', TAtlasTrackerEndDialog.SummaryText(mChange));
  Assert.AreEqual('Übergang „Beginnen“ → In Bearbeitung, mir zugewiesen',
    TAtlasTrackerEndDialog.SummaryText(mChange, 'In Bearbeitung'));
end;

procedure TAtlasTrackerEndDialogTests.GrowsWithWindow;
const
  cMore = 120;
var
  mDialog: TAtlasTrackerEndDialog;
  mStateWidth, mEditorHeight, mSendTop: Integer;
begin
  mDialog := TAtlasTrackerEndDialog.CreateDialog(nil, 'ATL-1', Options('Erledigt'), '');
  try
    Assert.IsTrue(mDialog.BorderStyle = bsSizeable);
    Assert.AreEqual(mDialog.Height, Integer(mDialog.Constraints.MinHeight), 'kleiner als gebaut geht nicht');
    mStateWidth := mDialog.Parts.State.Width;
    mEditorHeight := mDialog.Parts.Editor.Height;
    mSendTop := mDialog.Parts.Send.Parent.Top;
    mDialog.Width := mDialog.Width + mDialog.ScaleValue(cMore);
    mDialog.Height := mDialog.Height + mDialog.ScaleValue(cMore);
    Assert.AreEqual(mStateWidth + mDialog.ScaleValue(cMore), mDialog.Parts.State.Width, 'Zielzustand breiter');
    Assert.AreEqual(mDialog.Parts.State.Width, mDialog.Parts.Assignee.Width, 'Zuständig gleich breit');
    Assert.AreEqual(mEditorHeight + mDialog.ScaleValue(cMore), mDialog.Parts.Editor.Height, 'Kommentar höher');
    Assert.AreEqual(mSendTop + mDialog.ScaleValue(cMore), mDialog.Parts.Send.Parent.Top, 'Knöpfe bleiben unten');
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerEndDialogTests);

end.
