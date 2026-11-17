unit Atlas.UI.Debug.CallStackFrame.Tests;

// Fenster „Atlas-Aufrufstapel“ (#843), Oberfläche: Zeilen mit zugeklappter Bibliotheksgruppe, Aufklappen und Sprung
// melden sich, Suche nennt Treffer in der Gruppe, Kopieren nur eigener Code, Vergleich markiert geänderte Rahmen,
// Statuszeile ohne Liste.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugCallStackFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FillsRowsWithFoldedGroup;
    [Test]
    procedure ExpandAndOpenReport;
    [Test]
    procedure SearchCountsHitsInGroup;
    [Test]
    procedure CopyOwnCodeOnlyAsMarkdown;
    [Test]
    procedure CompareMarksChangedFrame;
    [Test]
    procedure StatusClearsList;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Vcl.Forms,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.CallStackView,
  Atlas.UI.Debug.CallStackFrame;

function Frame(const AHeader, AFileName: string; ALine: Integer; AOwn: Boolean): TAtlasDebugFrame;
begin
  Result := TAtlasDebugFrame.Create(AHeader, AFileName, ALine);
  Result.Own := AOwn;
end;

function ClickStack(const AName: string): TAtlasDebugStackView;
begin
  Result := TAtlasDebugStackView.FromFrames([
    Frame('Kunden.TImport.Lies(''' + AName + ''')', 'C:\P\Kunden.pas', 42, True),
    Frame('Vcl.Controls.TControl.Click', 'Vcl.Controls.pas', 7400, False),
    Frame('Vcl.Forms.TApplication.Run', 'Vcl.Forms.pas', 11000, False),
    Frame('Projekt.Projekt', 'C:\P\Projekt.dpr', 19, True)]);
end;

function NewFrame(AHost: TForm): TAtlasDebugCallStackFrame;
begin
  Result := TAtlasDebugCallStackFrame.Create(AHost);
  Result.Parent := AHost;
  Result.HandleNeeded;
end;

{ TAtlasDebugCallStackFrameTests }

procedure TAtlasDebugCallStackFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasDebugCallStackFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasDebugCallStackFrameTests.FillsRowsWithFoldedGroup;
var
  mHost: TForm;
  mFrame: TAtlasDebugCallStackFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    mFrame.SetStack(ClickStack('Meier'), Default(TAtlasDebugStackView), False);
    Assert.AreEqual(3, mFrame.List.Items.Count);
    Assert.AreEqual('Kunden.TImport.Lies(''Meier'')', mFrame.List.Items[0].Caption);
    Assert.AreEqual('Kunden.pas:42', mFrame.List.Items[0].SubItems[0]);
    Assert.AreEqual('▸ 2 Aufrufe in VCL', mFrame.List.Items[1].Caption);
    Assert.AreEqual('Vcl.Controls.TControl.Click … Vcl.Forms.TApplication.Run', mFrame.List.Items[1].SubItems[0]);
    Assert.AreEqual('4 Rahmen, davon 2 eigene', mFrame.Bar.StatusLabel.Caption);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasDebugCallStackFrameTests.ExpandAndOpenReport;
var
  mHost: TForm;
  mFrame: TAtlasDebugCallStackFrame;
  mExpanded: Boolean;
  mOpened: Integer;
  mKey: Word;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    mExpanded := False;
    mOpened := -1;
    mFrame.OnExpand :=
      procedure
      begin
        mExpanded := True;
      end;
    mFrame.OnOpenFrame :=
      procedure(AIndex: Integer)
      begin
        mOpened := AIndex;
      end;
    mFrame.SetStack(ClickStack('Meier'), Default(TAtlasDebugStackView), False);
    mFrame.OpenRow(1);
    Assert.IsTrue(mExpanded);
    Assert.AreEqual(4, mFrame.List.Items.Count);
    mFrame.List.Items[3].Selected := True;
    mKey := VK_RETURN;
    mFrame.List.OnKeyDown(mFrame.List, mKey, []);
    Assert.AreEqual(3, mOpened);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasDebugCallStackFrameTests.SearchCountsHitsInGroup;
var
  mHost: TForm;
  mFrame: TAtlasDebugCallStackFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    mFrame.SetStack(ClickStack('Meier'), Default(TAtlasDebugStackView), False);
    mFrame.Bar.SearchEdit.Text := 'run';
    Assert.AreEqual('▸ 2 Aufrufe in VCL · 1 Treffer', mFrame.List.Items[1].Caption);
    Assert.AreEqual('4 Rahmen, davon 2 eigene · 1 Treffer', mFrame.Bar.StatusLabel.Caption);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasDebugCallStackFrameTests.CopyOwnCodeOnlyAsMarkdown;
var
  mHost: TForm;
  mFrame: TAtlasDebugCallStackFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    mFrame.SetStack(ClickStack('Meier'), Default(TAtlasDebugStackView), False);
    mFrame.Bar.OwnOnlyItem.Checked := True;
    Assert.AreEqual('- `Kunden.TImport.Lies(''Meier'')` – `Kunden.pas:42`' + sLineBreak +
      '- `Projekt.Projekt` – `Projekt.dpr:19`', mFrame.CopyText(True));
  finally
    mHost.Free;
  end;
end;

procedure TAtlasDebugCallStackFrameTests.CompareMarksChangedFrame;
var
  mHost: TForm;
  mFrame: TAtlasDebugCallStackFrame;
  mOld, mNew: TAtlasDebugStackView;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    mOld := ClickStack('Meier');
    mNew := ClickStack('Müller');
    mNew.CompareWith(mOld);
    mOld.CompareWith(mNew);
    mFrame.SetStack(mNew, mOld, True);
    Assert.IsFalse(mFrame.PreviousList.Visible);
    mFrame.Bar.CompareCheck.Checked := True;
    Assert.AreEqual('≠ Kunden.TImport.Lies(''Müller'')', mFrame.List.Items[0].Caption);
    Assert.AreEqual('Projekt.Projekt', mFrame.List.Items[2].Caption);
    Assert.AreEqual(4, mFrame.PreviousList.Items.Count);
    Assert.AreEqual('≠ Kunden.TImport.Lies(''Meier'')', mFrame.PreviousList.Items[0].Caption);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasDebugCallStackFrameTests.StatusClearsList;
var
  mHost: TForm;
  mFrame: TAtlasDebugCallStackFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mHost);
    mFrame.SetStack(ClickStack('Meier'), Default(TAtlasDebugStackView), False);
    mFrame.ShowStatus('läuft');
    Assert.AreEqual(0, mFrame.List.Items.Count);
    Assert.AreEqual('läuft', mFrame.Bar.StatusLabel.Caption);
  finally
    mHost.Free;
  end;
end;

end.
