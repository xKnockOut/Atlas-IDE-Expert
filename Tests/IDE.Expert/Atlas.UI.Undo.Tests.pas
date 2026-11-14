unit Atlas.UI.Undo.Tests;

// Dateiübergreifendes Zurücknehmen (#721), Oberfläche: Texte für die
// Meldungsansicht, Beschriftungen der Liste „Atlas-Änderungen“, Unterschied,
// Unterschiedsfenster und die Liste im Ergebnisfenster mit Kontextmenü.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasUndoMessagesTests = class
  public
    [Test]
    procedure ReportsDoneUndoAndRedo;
    [Test]
    procedure ReportsPartialWithOneLinePerFile;
    [Test]
    procedure ReportsAbortedDisabledAndNothing;
    [Test]
    procedure CaptionsShowActionCountTimeAndState;
    [Test]
    procedure DiffLinesForOneOrAllFiles;
  end;

  [TestFixture]
  TAtlasUndoViewTests = class
  public
    /// <summary>Erste Benutzung (VCL, Codepages, RTTI) ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure DiffViewShowsLines;
    [Test]
    procedure ChangeListShowsSetsAndRaisesEvents;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Vcl.Forms,
  Vcl.ComCtrls,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Undo.Contract,
  Atlas.UI.Strings,
  Atlas.UI.Undo.Strings,
  Atlas.UI.Undo.Messages,
  Atlas.UI.Undo.DiffView,
  Atlas.UI.Results.Frame;

function Content(const AText: string): TAtlasTextFileContent;
begin
  Result := Default(TAtlasTextFileContent);
  Result.Text := AText;
  Result.Encoding := TAtlasTextEncoding.Utf8;
end;

function Problem(const AFileName: string; AKind: TAtlasUndoProblemKind; const AMessage: string): TAtlasUndoProblem;
begin
  Result := Default(TAtlasUndoProblem);
  Result.FileName := AFileName;
  Result.Kind := AKind;
  Result.Message := AMessage;
end;

function SampleSet(AUndone: Boolean): TAtlasChangeSet;
begin
  Result := Default(TAtlasChangeSet);
  Result.Id := 3;
  Result.Action := 'Umbenennen: Alt → Neu';
  Result.Time := EncodeDateTime(2026, 10, 14, 14, 3, 0, 0);
  Result.Files := [
    TAtlasFileChange.Modified('C:\P\A.pas', Content('Alt;'#13#10), Content('Neu;'#13#10)),
    TAtlasFileChange.Created('C:\P\B.pas', 'C:\P\P.dproj', Content('unit B;'#13#10))];
  Result.Files[0].Undone := AUndone;
  Result.Files[1].Undone := AUndone;
end;

{ TAtlasUndoMessagesTests }

procedure TAtlasUndoMessagesTests.ReportsDoneUndoAndRedo;
var
  mReport: TAtlasUndoReport;
  mLines: TArray<string>;
begin
  mReport := Default(TAtlasUndoReport);
  mReport.SetId := 3;
  mReport.Action := 'Umbenennen: Alt → Neu';
  mReport.Done := ['C:\P\A.pas', 'C:\P\B.pas'];
  mLines := TAtlasUndoMessages.Report(mReport);
  Assert.AreEqual(1, Integer(Length(mLines)));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UndoDone, [mReport.Action, 2]), mLines[0]);
  mReport.Redo := True;
  mLines := TAtlasUndoMessages.Report(mReport);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.RedoDone, [mReport.Action, 2]), mLines[0]);
end;

procedure TAtlasUndoMessagesTests.ReportsPartialWithOneLinePerFile;
var
  mReport: TAtlasUndoReport;
  mLines: TArray<string>;
begin
  mReport := Default(TAtlasUndoReport);
  mReport.Action := 'Code-Aktion';
  mReport.Done := ['C:\P\A.pas'];
  mReport.Conflicts := [Problem('C:\P\B.pas', TAtlasUndoProblemKind.ChangedSince, ''),
    Problem('C:\P\C.pas', TAtlasUndoProblemKind.Exists, ''),
    Problem('C:\P\D.pas', TAtlasUndoProblemKind.Missing, '')];
  mReport.Errors := [Problem('C:\P\E.pas', TAtlasUndoProblemKind.Failed, 'schreibgeschützt')];
  mLines := TAtlasUndoMessages.Report(mReport);
  Assert.AreEqual(5, Integer(Length(mLines)));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UndoPartial, ['Code-Aktion', 1, 4]), mLines[0]);
  Assert.AreEqual(TAtlasUndoStrings.Fmt(TAtlasUndoTextId.UndoConflictChanged, ['C:\P\B.pas']), mLines[1]);
  Assert.AreEqual(TAtlasUndoStrings.Fmt(TAtlasUndoTextId.UndoConflictExists, ['C:\P\C.pas']), mLines[2]);
  Assert.AreEqual(TAtlasUndoStrings.Fmt(TAtlasUndoTextId.UndoConflictMissing, ['C:\P\D.pas']), mLines[3]);
  Assert.AreEqual(TAtlasUndoStrings.Fmt(TAtlasUndoTextId.UndoFailed, ['C:\P\E.pas', 'schreibgeschützt']), mLines[4]);
  mReport.Redo := True;
  mLines := TAtlasUndoMessages.Report(mReport);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.RedoPartial, ['Code-Aktion', 1, 4]), mLines[0]);
end;

procedure TAtlasUndoMessagesTests.ReportsAbortedDisabledAndNothing;
var
  mReport: TAtlasUndoReport;
  mLines: TArray<string>;
begin
  mReport := Default(TAtlasUndoReport);
  mReport.Action := 'Umbenennen';
  mReport.Aborted := True;
  mReport.Conflicts := [Problem('C:\P\B.pas', TAtlasUndoProblemKind.ChangedSince, '')];
  mLines := TAtlasUndoMessages.Report(mReport);
  Assert.AreEqual(2, Integer(Length(mLines)));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UndoAborted, ['Umbenennen', 1]), mLines[0]);
  mReport.Redo := True;
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.RedoAborted, ['Umbenennen', 1]),
    TAtlasUndoMessages.Report(mReport)[0]);

  mReport := Default(TAtlasUndoReport);
  mReport.Disabled := True;
  mLines := TAtlasUndoMessages.Report(mReport);
  Assert.AreEqual(1, Integer(Length(mLines)));
  Assert.AreEqual(TAtlasUndoStrings.Text(TAtlasUndoTextId.UndoDisabled), mLines[0]);

  mReport := Default(TAtlasUndoReport);
  mReport.NotFound := True;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.UndoNothing), TAtlasUndoMessages.Report(mReport)[0]);
  mReport.Redo := True;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.RedoNothing), TAtlasUndoMessages.Report(mReport)[0]);
end;

procedure TAtlasUndoMessagesTests.CaptionsShowActionCountTimeAndState;
var
  mChangeSet: TAtlasChangeSet;
  mCaption: string;
begin
  mChangeSet := SampleSet(False);
  mCaption := TAtlasUndoMessages.SetCaption(mChangeSet, EncodeDateTime(2026, 10, 14, 18, 0, 0, 0));
  Assert.AreEqual(TAtlasUndoStrings.Fmt(TAtlasUndoTextId.UndoSetCaption, [mChangeSet.Action, 2, '14:03',
    TAtlasUndoStrings.Text(TAtlasUndoTextId.UndoStateApplied)]), mCaption);
  // Von einem anderen Tag: mit Datum.
  mCaption := TAtlasUndoMessages.SetCaption(SampleSet(True), EncodeDateTime(2026, 10, 15, 9, 0, 0, 0));
  Assert.Contains(mCaption, '14.10. 14:03');
  Assert.Contains(mCaption, TAtlasUndoStrings.Text(TAtlasUndoTextId.UndoStateUndone));
  mChangeSet.Files[0].Undone := True;
  Assert.AreEqual(TAtlasUndoStrings.Text(TAtlasUndoTextId.UndoStatePartly),
    TAtlasUndoMessages.StateText(mChangeSet.State));

  Assert.AreEqual('A.pas (C:\P)', TAtlasUndoMessages.FileCaption(SampleSet(False).Files[0]));
  Assert.AreEqual('B.pas (C:\P) · ' + TAtlasUndoStrings.Text(TAtlasUndoTextId.UndoKindCreated),
    TAtlasUndoMessages.FileCaption(SampleSet(False).Files[1]));
  Assert.AreEqual('A.pas (C:\P) · ' + TAtlasUndoStrings.Text(TAtlasUndoTextId.UndoStateUndone),
    TAtlasUndoMessages.FileCaption(SampleSet(True).Files[0]));
end;

procedure TAtlasUndoMessagesTests.DiffLinesForOneOrAllFiles;
var
  mLines: TArray<string>;
  mJoined: string;
begin
  mLines := TAtlasUndoMessages.DiffLines(SampleSet(False), 'c:\p\a.pas');
  mJoined := string.Join(#10, mLines);
  Assert.Contains(mJoined, '- Alt;');
  Assert.Contains(mJoined, '+ Neu;');
  Assert.DoesNotContain(mJoined, '===');
  // Alle Dateien: je Datei eine Überschrift, dazwischen eine Leerzeile.
  mLines := TAtlasUndoMessages.DiffLines(SampleSet(False), '');
  mJoined := string.Join(#10, mLines);
  Assert.Contains(mJoined, '=== A.pas (C:\P) ===');
  Assert.Contains(mJoined, '=== B.pas (C:\P) · ' + TAtlasUndoStrings.Text(TAtlasUndoTextId.UndoKindCreated) + ' ===');
  Assert.Contains(mJoined, '+ unit B;');
  Assert.Contains(mJoined, #10#10'===');
  Assert.AreEqual(0, Integer(Length(TAtlasUndoMessages.DiffLines(SampleSet(False), 'C:\P\X.pas'))));
end;

{ TAtlasUndoViewTests }

procedure TAtlasUndoViewTests.WarmUpFirstUse;
begin
  ChangeListShowsSetsAndRaisesEvents;
  DiffViewShowsLines;
end;

procedure TAtlasUndoViewTests.DiffViewShowsLines;
var
  mView: TAtlasUndoDiffView;
begin
  mView := TAtlasUndoDiffView.CreateView(nil, 'Unterschied', ['=== A.pas ===', '- Alt;', '+ Neu;']);
  try
    Assert.AreEqual('Unterschied', mView.Caption);
    Assert.AreEqual(3, Integer(mView.Lines.Lines.Count));
    Assert.AreEqual('+ Neu;', mView.Lines.Lines[2]);
    Assert.IsTrue(mView.Lines.ReadOnly);
    Assert.IsTrue(mView.CloseButton.Cancel, 'Esc schließt');
  finally
    mView.Free;
  end;
end;

type
  /// <summary>Hält fest, welche Ereignisse die Änderungsliste auslöst.</summary>
  TChangeEventProbe = class
  public
    FUndoId: Integer;
    FRedoId: Integer;
    FDiffId: Integer;
    FDiffFile: string;
  end;

/// <summary>Hängt Zurücknehmen, Wiederherstellen und Unterschied der Liste an die Probe.</summary>
procedure WireChangeEvents(const AFrame: TAtlasResultsFrame; const AProbe: TChangeEventProbe);
begin
  AFrame.Changes.OnUndo :=
    procedure(ASetId: Integer)
    begin
      AProbe.FUndoId := ASetId;
    end;
  AFrame.Changes.OnRedo :=
    procedure(ASetId: Integer)
    begin
      AProbe.FRedoId := ASetId;
    end;
  AFrame.Changes.OnDiff :=
    procedure(ASetId: Integer; const AFileName: string)
    begin
      AProbe.FDiffId := ASetId;
      AProbe.FDiffFile := AFileName;
    end;
end;

procedure TAtlasUndoViewTests.ChangeListShowsSetsAndRaisesEvents;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
  mOlder: TAtlasChangeSet;
  mProbe: TChangeEventProbe;
begin
  mProbe := TChangeEventProbe.Create;
  mOlder := SampleSet(True);
  mOlder.Id := 2;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    WireChangeEvents(mFrame, mProbe);
    mFrame.Changes.Show('Atlas-Änderungen', [SampleSet(False), mOlder], EncodeDateTime(2026, 10, 14, 18, 0, 0, 0),
      False);
    Assert.IsTrue(mFrame.Changes.Shows);
    // Zwei Sätze mit je zwei Dateien.
    Assert.AreEqual(6, Integer(mFrame.Tree.Items.Count));
    Assert.AreEqual(2, Integer(mFrame.Tree.Items[0].Count));
    Assert.AreSame(mFrame.Tree.Items[0], mFrame.Tree.Selected, 'neuester Satz ausgewählt');
    // Menü: angewendeter Satz lässt sich zurücknehmen, aber nicht wiederherstellen.
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.IsTrue(mFrame.Menu.Items[0].Visible);
    Assert.IsTrue(mFrame.Menu.Items[0].Enabled);
    Assert.IsFalse(mFrame.Menu.Items[1].Enabled);
    mFrame.Changes.UndoSelected;
    Assert.AreEqual(3, mProbe.FUndoId);
    mFrame.Changes.ShowSelectedDiff;
    Assert.AreEqual(3, mProbe.FDiffId);
    Assert.AreEqual('', mProbe.FDiffFile, 'Satz: alle Dateien');
    // Datei des älteren, zurückgenommenen Satzes.
    mFrame.Tree.Selected := mFrame.Tree.Items[4];
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.IsFalse(mFrame.Menu.Items[0].Enabled);
    Assert.IsTrue(mFrame.Menu.Items[1].Enabled);
    mFrame.Changes.RedoSelected;
    Assert.AreEqual(2, mProbe.FRedoId);
    mFrame.Changes.ShowSelectedDiff;
    Assert.AreEqual(2, mProbe.FDiffId);
    Assert.AreEqual('C:\P\A.pas', mProbe.FDiffFile);
    // Neu aufbauen behält die Auswahl.
    mFrame.Tree.Selected := mFrame.Tree.Items[3];
    mFrame.Changes.Show('Atlas-Änderungen', [SampleSet(False), mOlder], Now, True);
    Assert.AreSame(mFrame.Tree.Items[3], mFrame.Tree.Selected);
  finally
    mHost.Free;
    mProbe.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUndoMessagesTests);
  TDUnitX.RegisterTestFixture(TAtlasUndoViewTests);

end.
