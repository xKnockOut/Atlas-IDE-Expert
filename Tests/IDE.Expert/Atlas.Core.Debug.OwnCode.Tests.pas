unit Atlas.Core.Debug.OwnCode.Tests;

// Tests für „Nur eigener Code beim Debuggen“ (#578): Ordnerliste
// (Trenner, doppelte, abschließender Trenner), eigener Code nur unter ganzen
// Ordnern, Ort im Verlauf, Sprungziel, „Bis zur Rückkehr“ nach F7 und die
// zusammengefasste Stapelanzeige.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugOwnCodeTests = class
  public
    [Test]
    procedure ParseFoldersCleansList;
    [Test]
    procedure OwnFileOnlyBelowWholeFolder;
    [Test]
    procedure LocationIsFirstOwnFrame;
    [Test]
    procedure JumpOnlyWhenTopIsLibrary;
    [Test]
    procedure ReturnOnlyAfterStepWithoutSource;
    [Test]
    procedure RowsGroupLibraryFrames;
    [Test]
    procedure RowsWithoutJustMyCode;
  end;

implementation

uses
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.OwnCode;

function Frame(const AHeader, AFile: string; ALine: Integer; AOwn: Boolean): TAtlasDebugFrame;
begin
  Result := TAtlasDebugFrame.Create(AHeader, AFile, ALine);
  Result.Own := AOwn;
end;

/// <summary>Exception in StrToInt: zwei Rahmen ohne Quelltext, einer der RTL mit Quelltext, dann eigener Code.
/// </summary>
function SampleFrames: TAtlasDebugFrames;
begin
  Result := TArray<TAtlasDebugFrame>.Create(
    Frame(':7714C3E2 KERNELBASE.RaiseException + 0x62', '', 0, False),
    Frame(':0040A1B2 System._RaiseExcept', '', 0, False),
    Frame('System.SysUtils.StrToInt(''x'')', 'C:\BDS\source\rtl\sys\System.SysUtils.pas', 9012, False),
    Frame('Unit1.TForm1.Button1Click(Self=$02A3F2C0)', 'C:\Projekte\Demo\Unit1.pas', 42, True),
    Frame('Vcl.Controls.TControl.Click', '', 0, False),
    Frame('Project1.Project1', 'C:\Projekte\Demo\Project1.dpr', 18, True));
end;

{ TAtlasDebugOwnCodeTests }

procedure TAtlasDebugOwnCodeTests.ParseFoldersCleansList;
var
  mFolders: TArray<string>;
begin
  mFolders := TAtlasDebugOwnCode.ParseFolders('C:\Komponenten\; ;c:\komponenten' + #13#10 + 'D:/Lib/ ;');
  Assert.AreEqual(2, Integer(Length(mFolders)));
  Assert.AreEqual('C:\Komponenten', mFolders[0]);
  Assert.AreEqual('D:\Lib', mFolders[1], 'Schrägstrich vereinheitlicht');
  Assert.AreEqual('C:\Komponenten;D:\Lib', TAtlasDebugOwnCode.FoldersText(mFolders));
  Assert.AreEqual(0, Integer(Length(TAtlasDebugOwnCode.ParseFolders(''))));
end;

procedure TAtlasDebugOwnCodeTests.OwnFileOnlyBelowWholeFolder;
var
  mOwn: TAtlasDebugOwnCode;
begin
  mOwn := TAtlasDebugOwnCode.Create(TArray<string>.Create('C:\Projekte\Demo\'));
  mOwn.AddFolder('c:\projekte\demo');
  mOwn.AddFolder('D:\Komponenten');
  Assert.AreEqual(2, Integer(Length(mOwn.Folders)), 'doppelte entfallen');
  Assert.IsTrue(mOwn.IsOwnFile('C:\Projekte\Demo\Unit1.pas'));
  Assert.IsTrue(mOwn.IsOwnFile('c:\projekte\demo\Sub\Unit2.pas'), 'Unterordner und Groß/klein');
  Assert.IsTrue(mOwn.IsOwnFile('D:/Komponenten/Grid.pas'));
  Assert.IsFalse(mOwn.IsOwnFile('C:\Projekte\Demo2\Unit1.pas'), 'nur ganze Ordner');
  Assert.IsFalse(mOwn.IsOwnFile('C:\BDS\source\rtl\sys\System.SysUtils.pas'));
  Assert.IsFalse(mOwn.IsOwnFile(''));
end;

procedure TAtlasDebugOwnCodeTests.LocationIsFirstOwnFrame;
var
  mFrames: TAtlasDebugFrames;
begin
  mFrames := SampleFrames;
  Assert.AreEqual(3, TAtlasDebugOwnCode.LocationIndex(mFrames, True), 'erste eigene Zeile');
  Assert.AreEqual(2, TAtlasDebugOwnCode.LocationIndex(mFrames, False), 'aus: erster Rahmen mit Quelltext');
  Assert.AreEqual(3, TAtlasDebugOwnCode.FirstOwn(mFrames));
  mFrames := TArray<TAtlasDebugFrame>.Create(Frame('System.SysUtils.StrToInt', 'System.SysUtils.pas', 10, False));
  Assert.AreEqual(0, TAtlasDebugOwnCode.LocationIndex(mFrames, True), 'ohne eigenen Rahmen der mit Quelltext');
  Assert.AreEqual(-1, TAtlasDebugOwnCode.LocationIndex(nil, True));
end;

procedure TAtlasDebugOwnCodeTests.JumpOnlyWhenTopIsLibrary;
var
  mFrames: TAtlasDebugFrames;
begin
  mFrames := SampleFrames;
  Assert.AreEqual(3, TAtlasDebugOwnCode.JumpIndex(mFrames, True));
  Assert.AreEqual(-1, TAtlasDebugOwnCode.JumpIndex(mFrames, False), 'aus: kein Sprung');
  Delete(mFrames, 0, 3);
  Assert.AreEqual(-1, TAtlasDebugOwnCode.JumpIndex(mFrames, True), 'IDE steht schon im eigenen Code');
  mFrames := TArray<TAtlasDebugFrame>.Create(Frame(':0040A1B2 System._RaiseExcept', '', 0, False));
  Assert.AreEqual(-1, TAtlasDebugOwnCode.JumpIndex(mFrames, True), 'ohne eigenen Rahmen kein Sprung');
end;

procedure TAtlasDebugOwnCodeTests.ReturnOnlyAfterStepWithoutSource;
var
  mFrames, mOwn: TAtlasDebugFrames;
begin
  mFrames := SampleFrames;
  mOwn := Copy(mFrames, 3, 3);
  Assert.IsTrue(TAtlasDebugOwnCode.ShouldReturn(True, True, mFrames, 0), 'F7 in Code ohne Quelltext');
  Assert.IsFalse(TAtlasDebugOwnCode.ShouldReturn(True, False, mFrames, 0), 'Halt ohne Schritt (Pause)');
  Assert.IsFalse(TAtlasDebugOwnCode.ShouldReturn(False, True, mFrames, 0), 'aus');
  Assert.IsFalse(TAtlasDebugOwnCode.ShouldReturn(True, True, mOwn, 0), 'wieder im Quelltext');
  Assert.IsFalse(TAtlasDebugOwnCode.ShouldReturn(True, True, mFrames, TAtlasDebugOwnCode.cMaxReturns),
    'höchstens MaxReturns-mal');
  Assert.IsFalse(TAtlasDebugOwnCode.ShouldReturn(True, True, nil, 0), 'Stapel unbekannt');
end;

procedure TAtlasDebugOwnCodeTests.RowsGroupLibraryFrames;
var
  mRows: TAtlasDebugStackRows;
begin
  mRows := TAtlasDebugOwnCode.Rows(SampleFrames, True, nil);
  Assert.AreEqual(4, Integer(Length(mRows)));
  Assert.AreEqual(Ord(TAtlasDebugStackRowKind.LibraryGroup), Ord(mRows[0].Kind));
  Assert.AreEqual(0, mRows[0].First);
  Assert.AreEqual(3, mRows[0].Count);
  Assert.IsTrue(mRows[0].Faded);
  Assert.AreEqual(Ord(TAtlasDebugStackRowKind.Frame), Ord(mRows[1].Kind));
  Assert.AreEqual(3, mRows[1].First);
  Assert.IsFalse(mRows[1].Faded);
  Assert.AreEqual(Ord(TAtlasDebugStackRowKind.Frame), Ord(mRows[2].Kind), 'einzelner Bibliotheksrahmen bleibt');
  Assert.IsTrue(mRows[2].Faded);
  Assert.AreEqual(5, mRows[3].First);
  // Aufgeklappt: drei einzelne, abgeschwächte Rahmen.
  mRows := TAtlasDebugOwnCode.Rows(SampleFrames, True, TArray<Integer>.Create(0));
  Assert.AreEqual(6, Integer(Length(mRows)));
  Assert.AreEqual(Ord(TAtlasDebugStackRowKind.Frame), Ord(mRows[0].Kind));
  Assert.IsTrue(mRows[2].Faded);
end;

procedure TAtlasDebugOwnCodeTests.RowsWithoutJustMyCode;
var
  mRows: TAtlasDebugStackRows;
  mRow: TAtlasDebugStackRow;
begin
  mRows := TAtlasDebugOwnCode.Rows(SampleFrames, False, nil);
  Assert.AreEqual(6, Integer(Length(mRows)));
  for mRow in mRows do
  begin
    Assert.AreEqual(Ord(TAtlasDebugStackRowKind.Frame), Ord(mRow.Kind));
    Assert.IsFalse(mRow.Faded);
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasDebugOwnCode.Rows(nil, True, nil))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugOwnCodeTests);

end.
