unit Atlas.Core.Debug.CallStackView.Tests;

// Tests zum Inhalt des Fensters „Aufrufstapel“ (#843): Gruppen der Bibliotheksrahmen, Suche auch in zugeklappten
// Gruppen, Kopieren als Text und Markdown, Vergleich mit dem letzten Halt und die Grenze der gemerkten Stellen,
// ohne IDE.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.CallStackView;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugStackViewTests = class
  private
    function ClickStack(const AName: string): TAtlasDebugStackView;
  public
    [Test]
    procedure LibraryFramesFoldIntoOneGroup;
    [Test]
    procedure ExpandedGroupShowsFrames;
    [Test]
    procedure SearchFindsFramesInFoldedGroup;
    [Test]
    procedure SearchMatchesParameterValues;
    [Test]
    procedure CopyMarkdownOwnCodeOnly;
    [Test]
    procedure CopyTextAllFrames;
    [Test]
    procedure CompareMarksChangedParameter;
    [Test]
    procedure CompareMarksNewFrames;
    [Test]
    procedure UnnamedOnlyVisibleOwnFrames;
    [Test]
    procedure HistoryKeepsTwentyPlaces;
    [Test]
    procedure UnitNameAndArea;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.OwnCode,
  Atlas.Core.Debug.CallStack;

function Frame(const AHeader, AFileName: string; ALine: Integer; AOwn: Boolean): TAtlasDebugFrame;
begin
  Result := TAtlasDebugFrame.Create(AHeader, AFileName, ALine);
  Result.Own := AOwn;
end;

{ TAtlasDebugStackViewTests }

function TAtlasDebugStackViewTests.ClickStack(const AName: string): TAtlasDebugStackView;
begin
  Result := TAtlasDebugStackView.FromFrames([
    Frame('Kunden.TImport.Lies(''' + AName + ''',5)', 'C:\P\Kunden.pas', 42, True),
    Frame('Main.TForm1.ImportClick($2A3F2C0)', 'C:\P\Main.pas', 17, True),
    Frame('Vcl.Controls.TControl.Click', 'Vcl.Controls.pas', 7400, False),
    Frame('Vcl.StdCtrls.TButton.Click', 'Vcl.StdCtrls.pas', 5300, False),
    Frame('Vcl.Controls.TWinControl.WndProc($19F3A0)', 'Vcl.Controls.pas', 10200, False),
    Frame('Vcl.Forms.TApplication.Run', 'Vcl.Forms.pas', 11000, False),
    Frame('Projekt.Projekt', 'C:\P\Projekt.dpr', 19, True)]);
end;

procedure TAtlasDebugStackViewTests.LibraryFramesFoldIntoOneGroup;
var
  mStack: TAtlasDebugStackView;
  mRows: TAtlasDebugStackRows;
begin
  mStack := ClickStack('Meier');
  mRows := mStack.Rows(nil);
  Assert.AreEqual(4, Integer(Length(mRows)));
  Assert.AreEqual(Ord(TAtlasDebugStackRowKind.LibraryGroup), Ord(mRows[2].Kind));
  Assert.AreEqual(4, mRows[2].Count);
  Assert.AreEqual('VCL', mStack.Area(mRows[2]));
  Assert.AreEqual('Vcl.Controls.TControl.Click … Vcl.Forms.TApplication.Run', mStack.Hint(mRows[2]));
end;

procedure TAtlasDebugStackViewTests.ExpandedGroupShowsFrames;
var
  mRows: TAtlasDebugStackRows;
begin
  mRows := ClickStack('Meier').Rows([2]);
  Assert.AreEqual(7, Integer(Length(mRows)));
  Assert.AreEqual(Ord(TAtlasDebugStackRowKind.Frame), Ord(mRows[3].Kind));
  Assert.IsTrue(mRows[3].Faded);
end;

procedure TAtlasDebugStackViewTests.SearchFindsFramesInFoldedGroup;
var
  mStack: TAtlasDebugStackView;
  mRows: TAtlasDebugStackRows;
begin
  mStack := ClickStack('Meier');
  mRows := mStack.Rows(nil);
  Assert.AreEqual(1, mStack.Hits(mRows[0], 'import'));
  Assert.AreEqual(1, mStack.Hits(mRows[1], 'Import'));
  Assert.AreEqual(2, mStack.Hits(mRows[2], 'click'));
  Assert.AreEqual(1, mStack.Hits(mRows[2], 'forms.pas'));
  Assert.AreEqual(0, mStack.Hits(mRows[2], ''));
end;

procedure TAtlasDebugStackViewTests.SearchMatchesParameterValues;
var
  mStack: TAtlasDebugStackView;
begin
  mStack := ClickStack('Meier');
  Assert.IsTrue(mStack.Matches(0, 'meier'));
  Assert.IsFalse(mStack.Matches(1, 'meier'));
  mStack.Entries[0].Params[0].Name := 'AName';
  Assert.IsTrue(mStack.Matches(0, 'aname'));
end;

procedure TAtlasDebugStackViewTests.CopyMarkdownOwnCodeOnly;
var
  mStack: TAtlasDebugStackView;
begin
  mStack := ClickStack('Meier');
  mStack.Entries[0].Params[0].Name := 'AName';
  Assert.AreEqual(
    '- `Kunden.TImport.Lies(AName = ''Meier'', 5)` – `Kunden.pas:42`' + sLineBreak +
    '- `Main.TForm1.ImportClick($2A3F2C0)` – `Main.pas:17`' + sLineBreak +
    '- `Projekt.Projekt` – `Projekt.dpr:19`', mStack.CopyText(True, True));
end;

procedure TAtlasDebugStackViewTests.CopyTextAllFrames;
var
  mLines: TArray<string>;
begin
  mLines := ClickStack('Meier').CopyText(False, False).Split([sLineBreak]);
  Assert.AreEqual(7, Integer(Length(mLines)));
  Assert.AreEqual('Kunden.TImport.Lies(''Meier'', 5)  Kunden.pas:42', mLines[0]);
  Assert.AreEqual('Vcl.Controls.TControl.Click  Vcl.Controls.pas:7400', mLines[2]);
end;

procedure TAtlasDebugStackViewTests.CompareMarksChangedParameter;
var
  mOld, mNew: TAtlasDebugStackView;
begin
  mOld := ClickStack('Meier');
  mNew := ClickStack('Müller');
  mNew.CompareWith(mOld);
  Assert.IsFalse(mNew.Entries[0].Changed);
  Assert.IsTrue(mNew.Entries[0].Params[0].Changed);
  Assert.IsFalse(mNew.Entries[0].Params[1].Changed);
  Assert.IsTrue(mNew.Entries[0].ParamsChanged);
  Assert.IsFalse(mNew.Entries[1].ParamsChanged);
  // Ausgewertete Werte zählen, wenn beide welche haben.
  mOld.Entries[1].Params[0].Value := 'TForm1 ''Form1''';
  mNew.Entries[1].Params[0].Value := 'TForm1 ''Form2''';
  mNew.CompareWith(mOld);
  Assert.IsTrue(mNew.Entries[1].Params[0].Changed);
end;

procedure TAtlasDebugStackViewTests.CompareMarksNewFrames;
var
  mOld, mNew: TAtlasDebugStackView;
begin
  mOld := ClickStack('Meier');
  mNew := TAtlasDebugStackView.FromFrames(TAtlasDebugFrames.Create(Frame('Kunden.TImport.Pruefe(1)',
    'C:\P\Kunden.pas', 80, True)) + ClickStack('Meier').Frames);
  mNew.CompareWith(mOld);
  Assert.IsTrue(mNew.Entries[0].Changed);
  Assert.IsFalse(mNew.Entries[1].Changed);
  Assert.IsFalse(mNew.Entries[7].Changed);
  Assert.AreEqual('c:\p\kunden.pas:80', mNew.Key);
end;

procedure TAtlasDebugStackViewTests.UnnamedOnlyVisibleOwnFrames;
var
  mStack: TAtlasDebugStackView;
  mUnnamed: TArray<Integer>;
begin
  mStack := ClickStack('Meier');
  mUnnamed := mStack.Unnamed(mStack.Rows(nil));
  // Projekt.Projekt hat keine Werte, die Bibliotheksrahmen stehen zugeklappt.
  Assert.AreEqual(2, Integer(Length(mUnnamed)));
  Assert.AreEqual(0, mUnnamed[0]);
  Assert.AreEqual(1, mUnnamed[1]);
  mUnnamed := mStack.Unnamed(mStack.Rows([2]));
  Assert.AreEqual(3, Integer(Length(mUnnamed)));
  Assert.AreEqual(4, mUnnamed[2]);
end;

procedure TAtlasDebugStackViewTests.HistoryKeepsTwentyPlaces;
var
  mHistory: TAtlasDebugStackHistory;
  mIndex: Integer;
  mStack: TAtlasDebugStackView;
begin
  mHistory := TAtlasDebugStackHistory.Create;
  try
    for mIndex := 1 to TAtlasDebugStackHistory.cMaxKeys + 1 do
    begin
      mHistory.Remember(TAtlasDebugStackView.FromFrames([Frame('Unit1.Run', 'C:\P\Unit1.pas', mIndex, True)]));
    end;
    Assert.AreEqual(TAtlasDebugStackHistory.cMaxKeys, mHistory.Count);
    Assert.IsFalse(mHistory.Previous('c:\p\unit1.pas:1', mStack));
    Assert.IsTrue(mHistory.Previous('c:\p\unit1.pas:2', mStack));
    Assert.AreEqual(2, mStack.Entries[0].Frame.Line);
    // Ohne Quelltext keine Stelle.
    mHistory.Remember(TAtlasDebugStackView.FromFrames([Frame(':7714C3E2 KERNELBASE.RaiseException', '', 0, False)]));
    Assert.AreEqual(TAtlasDebugStackHistory.cMaxKeys, mHistory.Count);
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasDebugStackViewTests.UnitNameAndArea;
var
  mStack: TAtlasDebugStackView;
begin
  mStack := TAtlasDebugStackView.FromFrames([Frame('System.Classes.TThread.Execute', '', 0, False),
    Frame('Unit1.TForm1.Click', '/home/p/Unit1.pas', 3, True)]);
  Assert.AreEqual('System.Classes', mStack.Entries[0].UnitName);
  Assert.AreEqual('', mStack.Entries[0].Location);
  Assert.AreEqual('Unit1.pas', mStack.Entries[1].UnitName);
  Assert.AreEqual('Unit1.pas:3', mStack.Entries[1].Location);
  Assert.AreEqual('RTL', TAtlasDebugStackView.AreaOf('System.SysUtils'));
  Assert.AreEqual('Windows', TAtlasDebugStackView.AreaOf('Winapi.Messages'));
  Assert.AreEqual('JclDebug', TAtlasDebugStackView.AreaOf('JclDebug'));
end;

end.
