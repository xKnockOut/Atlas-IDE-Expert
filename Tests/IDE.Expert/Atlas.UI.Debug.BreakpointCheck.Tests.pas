unit Atlas.UI.Debug.BreakpointCheck.Tests;

// Dialog „Haltepunkte, die nicht greifen werden“ (#577): Texte der Einträge
// mit Zeilen ab 1, Knöpfe je Modus, Verschieben nur bei verschiebbaren Funden,
// Liste erst mit Fenster, Doppelklick springt zum Eintrag, Wahl je Knopf.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasBreakpointCheckDialogTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ProblemTextsCountFromOne;
    [Test]
    procedure LaunchHasStartAndCancel;
    [Test]
    procedure CommandOnlyMovesAndCloses;
    [Test]
    procedure FillAndJump;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Atlas.Core.Debug.BreakpointCheck,
  Atlas.UI.Debug.BreakpointCheck;

function Problem(const AFileName: string; ALine: Integer; AReason: TAtlasBreakpointReason;
  const ADetail: string; ANextLine: Integer): TAtlasBreakpointProblem;
begin
  Result := Default(TAtlasBreakpointProblem);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Reason := AReason;
  Result.Detail := ADetail;
  Result.NextLine := ANextLine;
end;

function Problems: TAtlasBreakpointProblems;
begin
  SetLength(Result, 3);
  Result[0] := Problem('C:\P\Kunden.pas', 41, TAtlasBreakpointReason.NoCode, '', 43);
  Result[1] := Problem('C:\P\Kunden.pas', 87, TAtlasBreakpointReason.Inactive, 'RELEASE', -1);
  Result[2] := Problem('C:\Q\Werkzeug.pas', 6, TAtlasBreakpointReason.NotInProject, '', -1);
end;

{ TAtlasBreakpointCheckDialogTests }

procedure TAtlasBreakpointCheckDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasBreakpointCheckDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasBreakpointCheckDialogTests.ProblemTextsCountFromOne;
var
  mProblems: TAtlasBreakpointProblems;
begin
  mProblems := Problems;
  Assert.AreEqual('Kunden.pas:42  Zeile ohne Code, nächste Codezeile 44',
    TAtlasBreakpointCheckDialog.ProblemText(mProblems[0]));
  Assert.AreEqual('Inaktiver Zweig der bedingten Kompilierung (RELEASE)',
    TAtlasBreakpointCheckDialog.ReasonText(mProblems[1]));
  Assert.AreEqual('Werkzeug.pas:7  Unit gehört nicht zum gestarteten Projekt',
    TAtlasBreakpointCheckDialog.ProblemText(mProblems[2]));
  mProblems[0].NextLine := -1;
  Assert.AreEqual('Zeile ohne Code', TAtlasBreakpointCheckDialog.ReasonText(mProblems[0]));
  mProblems[0].Reason := TAtlasBreakpointReason.Unreadable;
  Assert.AreEqual('Datei nicht lesbar', TAtlasBreakpointCheckDialog.ReasonText(mProblems[0]));
end;

procedure TAtlasBreakpointCheckDialogTests.LaunchHasStartAndCancel;
var
  mDialog: TAtlasBreakpointCheckDialog;
begin
  mDialog := TAtlasBreakpointCheckDialog.CreateDialog(nil, Problems, TAtlasBreakpointCheckMode.Launch, nil);
  try
    Assert.AreEqual(Ord(TAtlasBreakpointCheckChoice.Cancel), Ord(mDialog.Choice), 'Schließen = Start abbrechen');
    Assert.AreEqual('Auf nächste Codezeile verschieben (1)', mDialog.MoveButton.Caption);
    Assert.IsTrue(mDialog.MoveButton.Enabled);
    Assert.AreEqual('Trotzdem starten', mDialog.StartButton.Caption);
    Assert.IsNotNull(mDialog.CancelButton);
    mDialog.MoveButton.Click;
    Assert.AreEqual(Ord(TAtlasBreakpointCheckChoice.Move), Ord(mDialog.Choice));
    Assert.AreEqual(Integer(mrRetry), Integer(mDialog.ModalResult));
    mDialog.CancelButton.Click;
    Assert.AreEqual(Ord(TAtlasBreakpointCheckChoice.Cancel), Ord(mDialog.Choice));
    mDialog.StartButton.Click;
    Assert.AreEqual(Ord(TAtlasBreakpointCheckChoice.Start), Ord(mDialog.Choice));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasBreakpointCheckDialogTests.CommandOnlyMovesAndCloses;
var
  mProblems: TAtlasBreakpointProblems;
  mDialog: TAtlasBreakpointCheckDialog;
begin
  mProblems := Problems;
  mProblems[0].NextLine := -1;
  mDialog := TAtlasBreakpointCheckDialog.CreateDialog(nil, mProblems, TAtlasBreakpointCheckMode.Command, nil);
  try
    Assert.AreEqual(Ord(TAtlasBreakpointCheckChoice.Start), Ord(mDialog.Choice), 'Schließen = nichts tun');
    Assert.IsFalse(mDialog.MoveButton.Enabled, 'nichts verschiebbar');
    Assert.AreEqual('Schließen', mDialog.StartButton.Caption);
    Assert.IsNull(mDialog.CancelButton);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasBreakpointCheckDialogTests.FillAndJump;
var
  mDialog: TAtlasBreakpointCheckDialog;
  mJumped: Integer;
begin
  mJumped := -1;
  mDialog := TAtlasBreakpointCheckDialog.CreateDialog(nil, Problems, TAtlasBreakpointCheckMode.Launch,
    procedure(const AProblem: TAtlasBreakpointProblem)
    begin
      mJumped := AProblem.Line;
    end);
  try
    mDialog.HandleNeeded;
    mDialog.Fill;
    mDialog.Fill;
    Assert.AreEqual(3, mDialog.ProblemList.Items.Count, 'einmal gefüllt');
    Assert.AreEqual(0, mDialog.ProblemList.ItemIndex);
    Assert.AreEqual('Kunden.pas:88  Inaktiver Zweig der bedingten Kompilierung (RELEASE)',
      mDialog.ProblemList.Items[1]);
    mDialog.JumpTo(2);
    Assert.AreEqual(6, mJumped);
    mJumped := -1;
    mDialog.JumpTo(3);
    Assert.AreEqual(-1, mJumped, 'außerhalb der Liste');
  finally
    mDialog.Free;
  end;
end;

end.
