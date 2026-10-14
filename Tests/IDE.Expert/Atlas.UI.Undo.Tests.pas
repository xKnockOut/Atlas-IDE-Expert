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
  Report: TAtlasUndoReport;
  Lines: TArray<string>;
begin
  Report := Default(TAtlasUndoReport);
  Report.SetId := 3;
  Report.Action := 'Umbenennen: Alt → Neu';
  Report.Done := ['C:\P\A.pas', 'C:\P\B.pas'];
  Lines := TAtlasUndoMessages.Report(Report);
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UndoDone, [Report.Action, 2]), Lines[0]);
  Report.Redo := True;
  Lines := TAtlasUndoMessages.Report(Report);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.RedoDone, [Report.Action, 2]), Lines[0]);
end;

procedure TAtlasUndoMessagesTests.ReportsPartialWithOneLinePerFile;
var
  Report: TAtlasUndoReport;
  Lines: TArray<string>;
begin
  Report := Default(TAtlasUndoReport);
  Report.Action := 'Code-Aktion';
  Report.Done := ['C:\P\A.pas'];
  Report.Conflicts := [Problem('C:\P\B.pas', TAtlasUndoProblemKind.ChangedSince, ''),
    Problem('C:\P\C.pas', TAtlasUndoProblemKind.Exists, ''),
    Problem('C:\P\D.pas', TAtlasUndoProblemKind.Missing, '')];
  Report.Errors := [Problem('C:\P\E.pas', TAtlasUndoProblemKind.Failed, 'schreibgeschützt')];
  Lines := TAtlasUndoMessages.Report(Report);
  Assert.AreEqual(5, Integer(Length(Lines)));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UndoPartial, ['Code-Aktion', 1, 4]), Lines[0]);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UndoConflictChanged, ['C:\P\B.pas']), Lines[1]);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UndoConflictExists, ['C:\P\C.pas']), Lines[2]);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UndoConflictMissing, ['C:\P\D.pas']), Lines[3]);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UndoFailed, ['C:\P\E.pas', 'schreibgeschützt']), Lines[4]);
  Report.Redo := True;
  Lines := TAtlasUndoMessages.Report(Report);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.RedoPartial, ['Code-Aktion', 1, 4]), Lines[0]);
end;

procedure TAtlasUndoMessagesTests.ReportsAbortedDisabledAndNothing;
var
  Report: TAtlasUndoReport;
  Lines: TArray<string>;
begin
  Report := Default(TAtlasUndoReport);
  Report.Action := 'Umbenennen';
  Report.Aborted := True;
  Report.Conflicts := [Problem('C:\P\B.pas', TAtlasUndoProblemKind.ChangedSince, '')];
  Lines := TAtlasUndoMessages.Report(Report);
  Assert.AreEqual(2, Integer(Length(Lines)));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UndoAborted, ['Umbenennen', 1]), Lines[0]);
  Report.Redo := True;
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.RedoAborted, ['Umbenennen', 1]),
    TAtlasUndoMessages.Report(Report)[0]);

  Report := Default(TAtlasUndoReport);
  Report.Disabled := True;
  Lines := TAtlasUndoMessages.Report(Report);
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.UndoDisabled), Lines[0]);

  Report := Default(TAtlasUndoReport);
  Report.NotFound := True;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.UndoNothing), TAtlasUndoMessages.Report(Report)[0]);
  Report.Redo := True;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.RedoNothing), TAtlasUndoMessages.Report(Report)[0]);
end;

procedure TAtlasUndoMessagesTests.CaptionsShowActionCountTimeAndState;
var
  ChangeSet: TAtlasChangeSet;
  Caption: string;
begin
  ChangeSet := SampleSet(False);
  Caption := TAtlasUndoMessages.SetCaption(ChangeSet, EncodeDateTime(2026, 10, 14, 18, 0, 0, 0));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.UndoSetCaption, [ChangeSet.Action, 2, '14:03',
    TAtlasStrings.Text(TAtlasTextId.UndoStateApplied)]), Caption);
  // Von einem anderen Tag: mit Datum.
  Caption := TAtlasUndoMessages.SetCaption(SampleSet(True), EncodeDateTime(2026, 10, 15, 9, 0, 0, 0));
  Assert.Contains(Caption, '14.10. 14:03');
  Assert.Contains(Caption, TAtlasStrings.Text(TAtlasTextId.UndoStateUndone));
  ChangeSet.Files[0].Undone := True;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.UndoStatePartly), TAtlasUndoMessages.StateText(ChangeSet.State));

  Assert.AreEqual('A.pas (C:\P)', TAtlasUndoMessages.FileCaption(SampleSet(False).Files[0]));
  Assert.AreEqual('B.pas (C:\P) · ' + TAtlasStrings.Text(TAtlasTextId.UndoKindCreated),
    TAtlasUndoMessages.FileCaption(SampleSet(False).Files[1]));
  Assert.AreEqual('A.pas (C:\P) · ' + TAtlasStrings.Text(TAtlasTextId.UndoStateUndone),
    TAtlasUndoMessages.FileCaption(SampleSet(True).Files[0]));
end;

procedure TAtlasUndoMessagesTests.DiffLinesForOneOrAllFiles;
var
  Lines: TArray<string>;
  Joined: string;
begin
  Lines := TAtlasUndoMessages.DiffLines(SampleSet(False), 'c:\p\a.pas');
  Joined := string.Join(#10, Lines);
  Assert.Contains(Joined, '- Alt;');
  Assert.Contains(Joined, '+ Neu;');
  Assert.DoesNotContain(Joined, '===');
  // Alle Dateien: je Datei eine Überschrift, dazwischen eine Leerzeile.
  Lines := TAtlasUndoMessages.DiffLines(SampleSet(False), '');
  Joined := string.Join(#10, Lines);
  Assert.Contains(Joined, '=== A.pas (C:\P) ===');
  Assert.Contains(Joined, '=== B.pas (C:\P) · ' + TAtlasStrings.Text(TAtlasTextId.UndoKindCreated) + ' ===');
  Assert.Contains(Joined, '+ unit B;');
  Assert.Contains(Joined, #10#10'===');
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
  View: TAtlasUndoDiffView;
begin
  View := TAtlasUndoDiffView.CreateView(nil, 'Unterschied', ['=== A.pas ===', '- Alt;', '+ Neu;']);
  try
    Assert.AreEqual('Unterschied', View.Caption);
    Assert.AreEqual(3, View.Lines.Lines.Count);
    Assert.AreEqual('+ Neu;', View.Lines.Lines[2]);
    Assert.IsTrue(View.Lines.ReadOnly);
    Assert.IsTrue(View.CloseButton.Cancel, 'Esc schließt');
  finally
    View.Free;
  end;
end;

procedure TAtlasUndoViewTests.ChangeListShowsSetsAndRaisesEvents;
var
  Host: TForm;
  Frame: TAtlasResultsFrame;
  Older: TAtlasChangeSet;
  UndoId, RedoId, DiffId: Integer;
  DiffFile: string;
begin
  Older := SampleSet(True);
  Older.Id := 2;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    UndoId := 0;
    RedoId := 0;
    DiffId := 0;
    Frame.OnChangeUndo :=
      procedure(ASetId: Integer)
      begin
        UndoId := ASetId;
      end;
    Frame.OnChangeRedo :=
      procedure(ASetId: Integer)
      begin
        RedoId := ASetId;
      end;
    Frame.OnChangeDiff :=
      procedure(ASetId: Integer; const AFileName: string)
      begin
        DiffId := ASetId;
        DiffFile := AFileName;
      end;
    Frame.ShowChanges('Atlas-Änderungen', [SampleSet(False), Older], EncodeDateTime(2026, 10, 14, 18, 0, 0, 0),
      False);
    Assert.IsTrue(Frame.ShowsChanges);
    // Zwei Sätze mit je zwei Dateien.
    Assert.AreEqual(6, Frame.Tree.Items.Count);
    Assert.AreEqual(2, Frame.Tree.Items[0].Count);
    Assert.IsTrue(Frame.Tree.Selected = Frame.Tree.Items[0], 'neuester Satz ausgewählt');
    // Menü: angewendeter Satz lässt sich zurücknehmen, aber nicht wiederherstellen.
    Frame.Menu.OnPopup(Frame.Menu);
    Assert.IsTrue(Frame.Menu.Items[0].Visible);
    Assert.IsTrue(Frame.Menu.Items[0].Enabled);
    Assert.IsFalse(Frame.Menu.Items[1].Enabled);
    Frame.UndoSelected;
    Assert.AreEqual(3, UndoId);
    Frame.ShowSelectedDiff;
    Assert.AreEqual(3, DiffId);
    Assert.AreEqual('', DiffFile, 'Satz: alle Dateien');
    // Datei des älteren, zurückgenommenen Satzes.
    Frame.Tree.Selected := Frame.Tree.Items[4];
    Frame.Menu.OnPopup(Frame.Menu);
    Assert.IsFalse(Frame.Menu.Items[0].Enabled);
    Assert.IsTrue(Frame.Menu.Items[1].Enabled);
    Frame.RedoSelected;
    Assert.AreEqual(2, RedoId);
    Frame.ShowSelectedDiff;
    Assert.AreEqual(2, DiffId);
    Assert.AreEqual('C:\P\A.pas', DiffFile);
    // Neu aufbauen behält die Auswahl.
    Frame.Tree.Selected := Frame.Tree.Items[3];
    Frame.ShowChanges('Atlas-Änderungen', [SampleSet(False), Older], Now, True);
    Assert.IsTrue(Frame.Tree.Selected = Frame.Tree.Items[3]);
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUndoMessagesTests);
  TDUnitX.RegisterTestFixture(TAtlasUndoViewTests);

end.
