unit Atlas.UI.Debug.DataBreak.Tests;

// Anhalten bei Datenzugriff (#870), Fensterteil: Wahl im Dialog, Leiste nach
// dem Halt und die gemeinsame Halteleiste.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDataBreakWindowTests = class
  public
    [Test]
    procedure DialogShowsAndReturnsChoice;
    [Test]
    procedure DialogNeedsKind;
    [Test]
    procedure BarActions;
    [Test]
    procedure StopBarShortensDetail;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.Core.Debug.DataBreak,
  Atlas.UI.Strings,
  Atlas.UI.Debug.StopBar,
  Atlas.UI.Debug.DataBreak;

{ TAtlasDataBreakWindowTests }

procedure TAtlasDataBreakWindowTests.DialogShowsAndReturnsChoice;
var
  mDialog: TAtlasDataBreakDialog;
  mStart, mChoice: TAtlasDataChoice;
  mAsked: Integer;
begin
  TAtlasStrings.Language := TAtlasLanguage.German;
  mStart := TAtlasDataChoice.Defaults;
  mStart.SqlPattern := '*FROM Kunden*';
  mAsked := 0;
  mDialog := TAtlasDataBreakDialog.CreateDialog(nil, mStart, 12, 3,
    function(const AChoice: TAtlasDataChoice): string
    begin
      Inc(mAsked);
      Result := IntToStr(mAsked);
    end);
  try
    mDialog.Prepare;
    Assert.IsTrue(mDialog.SqlCheck.Checked);
    Assert.IsTrue(mDialog.HttpCheck.Checked);
    Assert.AreEqual('*FROM Kunden*', mDialog.SqlPatternEdit.Text);
    Assert.IsTrue(mDialog.IgnoreCaseCheck.Checked);
    Assert.IsTrue(mDialog.StopRadio.Checked);
    Assert.IsTrue(mAsked > 0, 'Zahl zur Wahl');
    Assert.AreNotEqual('', mDialog.CountLabel.Caption);
    mDialog.HttpCheck.Checked := False;
    Assert.IsFalse(mDialog.HttpPatternEdit.Enabled, 'Muster nur mit Art');
    mDialog.SqlPatternEdit.Text := '  *Auftrag* ';
    mDialog.IgnoreCaseCheck.Checked := False;
    mDialog.LogRadio.Checked := True;
    mChoice := mDialog.Choice;
    Assert.IsTrue(mChoice.Kinds = [TAtlasDataKind.Sql]);
    Assert.AreEqual('*Auftrag*', mChoice.SqlPattern);
    Assert.IsFalse(mChoice.IgnoreCase);
    Assert.AreEqual(Ord(TAtlasDataMode.Log), Ord(mChoice.Mode));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDataBreakWindowTests.DialogNeedsKind;
var
  mDialog: TAtlasDataBreakDialog;
begin
  // Ohne HTTP-Stellen ist HTTP nicht wählbar.
  mDialog := TAtlasDataBreakDialog.CreateDialog(nil, TAtlasDataChoice.Defaults, 2, 0, nil);
  try
    mDialog.Prepare;
    Assert.IsFalse(mDialog.HttpCheck.Enabled);
    Assert.IsFalse(mDialog.HttpCheck.Checked);
    Assert.IsTrue(mDialog.OkButton.Enabled);
    mDialog.SqlCheck.Checked := False;
    Assert.IsFalse(mDialog.OkButton.Enabled);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDataBreakWindowTests.BarActions;
var
  mBar: TAtlasDataBreakBar;
  mActions: string;
begin
  mActions := '';
  mBar := TAtlasDataBreakBar.Create(nil);
  try
    mBar.Colors := TAtlasColors.Light;
    mBar.SetScaling(96, 1, 'Segoe UI', 9);
    mBar.OnAction :=
      procedure(AAction: TAtlasDataBreakAction)
      begin
        mActions := mActions + IntToStr(Ord(AAction));
      end;
    mBar.ShowFor('Kunde.pas:43 · qryKunde.ExecSQL', 'SELECT * FROM Kunden WHERE ID = 1', Point(100, 100));
    Assert.IsTrue(mBar.IsShown);
    Assert.AreEqual('SELECT * FROM Kunden WHERE ID = 1', mBar.Detail);
    Assert.IsTrue(mBar.ActionRect(TAtlasDataBreakAction.LogOnly).Left >
      mBar.ActionRect(TAtlasDataBreakAction.KeepWatching).Right, 'nebeneinander');
    Assert.IsTrue(mBar.ActionRect(TAtlasDataBreakAction.Finish).Left >
      mBar.ActionRect(TAtlasDataBreakAction.LogOnly).Right, 'nebeneinander');
    mBar.Act(TAtlasDataBreakAction.LogOnly);
    Assert.IsFalse(mBar.IsShown);
    mBar.ShowFor('x', '', Point(100, 100));
    mBar.Act(TAtlasDataBreakAction.Finish);
    mBar.ShowFor('x', '', Point(100, 100));
    mBar.Act(TAtlasDataBreakAction.KeepWatching);
    Assert.AreEqual('120', mActions);
  finally
    mBar.Free;
  end;
end;

procedure TAtlasDataBreakWindowTests.StopBarShortensDetail;
var
  mLong: string;
begin
  Assert.AreEqual('SELECT * FROM X WHERE ID = 1', TAtlasStopBar.ShortDetail('SELECT *'#13#10'FROM X'#9'WHERE ID = 1 '));
  mLong := StringOfChar('a', TAtlasStopBar.cMaxDetail + 10);
  Assert.AreEqual(TAtlasStopBar.cMaxDetail, Integer(Length(TAtlasStopBar.ShortDetail(mLong))));
  Assert.IsTrue(TAtlasStopBar.ShortDetail(mLong).EndsWith('…'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDataBreakWindowTests);

end.
