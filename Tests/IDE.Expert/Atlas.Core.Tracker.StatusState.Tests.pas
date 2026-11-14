unit Atlas.Core.Tracker.StatusState.Tests;

// Tests des Zustands im Statusfeld (#2124) ohne IDE: Feldtext mit gekürztem
// Zustand, Einträge des Menüs unter einer Zustandsmaschine und ohne, Einträge
// der Befehlspalette mit Filter und Kennung, Änderung je Eintrag und der
// danach bekannte Zustand.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasIssueStatusTests = class
  public
    [Test]
    procedure FieldTextLeavesOutEmptyParts;
    [Test]
    procedure LongStateIsShortened;
    [Test]
    procedure MenuShowsAllowedTransitions;
    [Test]
    procedure MenuWithoutStateMachineShowsOtherValues;
    [Test]
    procedure PaletteRowsMatchEveryWord;
    [Test]
    procedure RowIdLeadsBackToEntry;
    [Test]
    procedure ChangeForTransitionAndValue;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.StatusState;

function Rules: TAtlasTrackerStateRules;
begin
  Result := Default(TAtlasTrackerStateRules);
  Result.StateMachine := True;
  Result.FieldId := '82-11';
  Result.Current := 'In Bearbeitung';
  Result.Transitions := [TAtlasTrackerTransition.Create('zur-pruefung', 'Zur Prüfung'),
    TAtlasTrackerTransition.Create('pause', 'Pausieren')];
end;

function States: TArray<string>;
begin
  Result := TArray<string>.Create('Offen', 'In Bearbeitung', 'Zur Prüfung', 'Erledigt');
end;

procedure TAtlasIssueStatusTests.FieldTextLeavesOutEmptyParts;
begin
  Assert.AreEqual('ATL-2052 · In Bearbeitung · 1:25', TAtlasIssueStatus.Text('ATL-2052', 'In Bearbeitung', '1:25'));
  Assert.AreEqual('ATL-2052 · In Bearbeitung', TAtlasIssueStatus.Text('ATL-2052', 'In Bearbeitung', ''),
    'ohne Zeiterfassung');
  Assert.AreEqual('ATL-2052 · 1:25', TAtlasIssueStatus.Text('ATL-2052', '', '1:25'), 'Zustand unbekannt');
  Assert.AreEqual('', TAtlasIssueStatus.Text('', '', ''));
end;

procedure TAtlasIssueStatusTests.LongStateIsShortened;
var
  mShort: string;
begin
  mShort := TAtlasIssueStatus.Short('Wartet auf Rückmeldung des Kunden');
  Assert.AreEqual('Wartet auf Rückmeldung…', mShort, 'ohne Leerzeichen vor „…“');
  Assert.AreEqual(TAtlasIssueStatus.cMaxState, Integer(Length(TAtlasIssueStatus.Short(StringOfChar('x', 40)))));
  Assert.AreEqual('Offen', TAtlasIssueStatus.Short(' Offen '));
end;

procedure TAtlasIssueStatusTests.MenuShowsAllowedTransitions;
var
  mEntries: TArray<TAtlasIssueStateEntry>;
begin
  mEntries := TAtlasIssueStatus.Entries(Rules, States, 'In Bearbeitung');
  Assert.AreEqual(2, Integer(Length(mEntries)));
  Assert.AreEqual('Zur Prüfung', mEntries[0].Caption, 'Ziel gleich dem Namen: kein Pfeil');
  Assert.AreEqual('zur-pruefung', mEntries[0].Transition.Id);
  Assert.AreEqual('Pausieren', mEntries[1].Caption);
  Assert.AreEqual(0, Integer(Length(TAtlasIssueStatus.Entries(Default(TAtlasTrackerStateRules), nil, ''))));
end;

procedure TAtlasIssueStatusTests.MenuWithoutStateMachineShowsOtherValues;
var
  mEntries: TArray<TAtlasIssueStateEntry>;
begin
  mEntries := TAtlasIssueStatus.Entries(Default(TAtlasTrackerStateRules), States, 'in bearbeitung');
  Assert.AreEqual(3, Integer(Length(mEntries)), 'der aktuelle Wert fehlt');
  Assert.AreEqual('Offen', mEntries[0].State);
  Assert.AreEqual('', mEntries[0].Transition.Id);
  Assert.AreEqual('Erledigt', mEntries[2].Caption);
end;

procedure TAtlasIssueStatusTests.PaletteRowsMatchEveryWord;
var
  mEntries: TArray<TAtlasIssueStateEntry>;
  mRows: TArray<Integer>;
begin
  mEntries := TAtlasIssueStatus.Entries(Rules, States, 'In Bearbeitung');
  mRows := TAtlasIssueStatus.Matching('ATL-2052', mEntries, 'prüf');
  Assert.AreEqual(1, Integer(Length(mRows)));
  Assert.AreEqual('ATL-2052: Zur Prüfung', TAtlasIssueStatus.RowCaption('ATL-2052', mEntries[mRows[0]]));
  Assert.AreEqual(2, Integer(Length(TAtlasIssueStatus.Matching('ATL-2052', mEntries, '2052'))),
    'Kennung passt auf alle');
  Assert.AreEqual(1, Integer(Length(TAtlasIssueStatus.Matching('ATL-2052', mEntries, 'ATL PAUS'))));
  Assert.AreEqual(0, Integer(Length(TAtlasIssueStatus.Matching('ATL-2052', mEntries, 'prüf erledigt'))));
  Assert.AreEqual(0, Integer(Length(TAtlasIssueStatus.Matching('ATL-2052', mEntries, '  '))), 'leere Eingabe');
  Assert.AreEqual(0, Integer(Length(TAtlasIssueStatus.Matching('', mEntries, 'prüf'))), 'ohne Issue');
end;

procedure TAtlasIssueStatusTests.RowIdLeadsBackToEntry;
var
  mRows: TArray<Integer>;
begin
  mRows := TAtlasIssueStatus.Matching('ATL-2052', TAtlasIssueStatus.Entries(Rules, States, ''), 'paus');
  Assert.AreEqual(1, Integer(Length(mRows)));
  Assert.AreEqual(1, TAtlasIssueStatus.IndexOf(TAtlasIssueStatus.RowId(mRows[0])), 'Nummer in der Liste');
  Assert.AreEqual(-1, TAtlasIssueStatus.IndexOf('ATL-2052'), 'Issue der Suche');
  Assert.AreEqual(-1, TAtlasIssueStatus.IndexOf(TAtlasIssueStatus.cRowPrefix + 'x'));
end;

procedure TAtlasIssueStatusTests.ChangeForTransitionAndValue;
var
  mEntries: TArray<TAtlasIssueStateEntry>;
  mChange: TAtlasTrackerWrite;
begin
  mEntries := TAtlasIssueStatus.Entries(Rules, States, '');
  mChange := TAtlasIssueStatus.Change(mEntries[0], 'State', '82-11', ' Bitte prüfen ');
  Assert.AreEqual('zur-pruefung', mChange.Transition.Id);
  Assert.AreEqual('82-11', mChange.FieldId);
  Assert.AreEqual('', mChange.State);
  Assert.AreEqual('Bitte prüfen', mChange.Comment);
  Assert.AreEqual<TAtlasTrackerAssign>(TAtlasTrackerAssign.Keep, mChange.Assign);
  Assert.AreEqual('Zur Prüfung', TAtlasIssueStatus.After(mEntries[0], States));
  Assert.AreEqual('', TAtlasIssueStatus.After(mEntries[1], States), 'Ziel von „Pausieren“ unbekannt');

  mChange := TAtlasIssueStatus.Change(TAtlasIssueStateEntry.ForState('Erledigt'), 'Status', '', '');
  Assert.AreEqual('Erledigt', mChange.State);
  Assert.AreEqual('Status', mChange.StateField);
  Assert.AreEqual('', mChange.Transition.Id);
  Assert.AreEqual('', mChange.Comment);
  Assert.AreEqual('Erledigt', TAtlasIssueStatus.After(TAtlasIssueStateEntry.ForState('Erledigt'), nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssueStatusTests);

end.
