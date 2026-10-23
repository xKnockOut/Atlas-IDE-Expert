unit Atlas.Core.Debug.OwnCode.Tests;

// Tests für „Nur eigener Code beim Debuggen“ (#578): Ordnerliste
// (Trenner, doppelte, abschließender Trenner), eigener Code nur unter ganzen
// Ordnern, Ort im Verlauf, Sprungziel, „Bis zur Rückkehr“ nach F7 und die
// zusammengefasste Stapelanzeige.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.CallStack;

type
  [TestFixture]
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
  Folders: TArray<string>;
begin
  Folders := TAtlasDebugOwnCode.ParseFolders('C:\Komponenten\; ;c:\komponenten' + #13#10 + 'D:/Lib/ ;');
  Assert.AreEqual(2, Integer(Length(Folders)));
  Assert.AreEqual('C:\Komponenten', Folders[0]);
  Assert.AreEqual('D:\Lib', Folders[1], 'Schrägstrich vereinheitlicht');
  Assert.AreEqual('C:\Komponenten;D:\Lib', TAtlasDebugOwnCode.FoldersText(Folders));
  Assert.AreEqual(0, Integer(Length(TAtlasDebugOwnCode.ParseFolders(''))));
end;

procedure TAtlasDebugOwnCodeTests.OwnFileOnlyBelowWholeFolder;
var
  Own: TAtlasDebugOwnCode;
begin
  Own := TAtlasDebugOwnCode.Create(TArray<string>.Create('C:\Projekte\Demo\'));
  Own.AddFolder('c:\projekte\demo');
  Own.AddFolder('D:\Komponenten');
  Assert.AreEqual(2, Integer(Length(Own.Folders)), 'doppelte entfallen');
  Assert.IsTrue(Own.IsOwnFile('C:\Projekte\Demo\Unit1.pas'));
  Assert.IsTrue(Own.IsOwnFile('c:\projekte\demo\Sub\Unit2.pas'), 'Unterordner und Groß/klein');
  Assert.IsTrue(Own.IsOwnFile('D:/Komponenten/Grid.pas'));
  Assert.IsFalse(Own.IsOwnFile('C:\Projekte\Demo2\Unit1.pas'), 'nur ganze Ordner');
  Assert.IsFalse(Own.IsOwnFile('C:\BDS\source\rtl\sys\System.SysUtils.pas'));
  Assert.IsFalse(Own.IsOwnFile(''));
end;

procedure TAtlasDebugOwnCodeTests.LocationIsFirstOwnFrame;
var
  Frames: TAtlasDebugFrames;
begin
  Frames := SampleFrames;
  Assert.AreEqual(3, TAtlasDebugOwnCode.LocationIndex(Frames, True), 'erste eigene Zeile');
  Assert.AreEqual(2, TAtlasDebugOwnCode.LocationIndex(Frames, False), 'aus: erster Rahmen mit Quelltext');
  Assert.AreEqual(3, TAtlasDebugOwnCode.FirstOwn(Frames));
  Frames := TArray<TAtlasDebugFrame>.Create(Frame('System.SysUtils.StrToInt', 'System.SysUtils.pas', 10, False));
  Assert.AreEqual(0, TAtlasDebugOwnCode.LocationIndex(Frames, True), 'ohne eigenen Rahmen der mit Quelltext');
  Assert.AreEqual(-1, TAtlasDebugOwnCode.LocationIndex(nil, True));
end;

procedure TAtlasDebugOwnCodeTests.JumpOnlyWhenTopIsLibrary;
var
  Frames: TAtlasDebugFrames;
begin
  Frames := SampleFrames;
  Assert.AreEqual(3, TAtlasDebugOwnCode.JumpIndex(Frames, True));
  Assert.AreEqual(-1, TAtlasDebugOwnCode.JumpIndex(Frames, False), 'aus: kein Sprung');
  Delete(Frames, 0, 3);
  Assert.AreEqual(-1, TAtlasDebugOwnCode.JumpIndex(Frames, True), 'IDE steht schon im eigenen Code');
  Frames := TArray<TAtlasDebugFrame>.Create(Frame(':0040A1B2 System._RaiseExcept', '', 0, False));
  Assert.AreEqual(-1, TAtlasDebugOwnCode.JumpIndex(Frames, True), 'ohne eigenen Rahmen kein Sprung');
end;

procedure TAtlasDebugOwnCodeTests.ReturnOnlyAfterStepWithoutSource;
var
  Frames, Own: TAtlasDebugFrames;
begin
  Frames := SampleFrames;
  Own := Copy(Frames, 3, 3);
  Assert.IsTrue(TAtlasDebugOwnCode.ShouldReturn(True, True, Frames, 0), 'F7 in Code ohne Quelltext');
  Assert.IsFalse(TAtlasDebugOwnCode.ShouldReturn(True, False, Frames, 0), 'Halt ohne Schritt (Pause)');
  Assert.IsFalse(TAtlasDebugOwnCode.ShouldReturn(False, True, Frames, 0), 'aus');
  Assert.IsFalse(TAtlasDebugOwnCode.ShouldReturn(True, True, Own, 0), 'wieder im Quelltext');
  Assert.IsFalse(TAtlasDebugOwnCode.ShouldReturn(True, True, Frames, TAtlasDebugOwnCode.MaxReturns),
    'höchstens MaxReturns-mal');
  Assert.IsFalse(TAtlasDebugOwnCode.ShouldReturn(True, True, nil, 0), 'Stapel unbekannt');
end;

procedure TAtlasDebugOwnCodeTests.RowsGroupLibraryFrames;
var
  Rows: TAtlasDebugStackRows;
begin
  Rows := TAtlasDebugOwnCode.Rows(SampleFrames, True, nil);
  Assert.AreEqual(4, Integer(Length(Rows)));
  Assert.AreEqual(Ord(TAtlasDebugStackRowKind.LibraryGroup), Ord(Rows[0].Kind));
  Assert.AreEqual(0, Rows[0].First);
  Assert.AreEqual(3, Rows[0].Count);
  Assert.IsTrue(Rows[0].Faded);
  Assert.AreEqual(Ord(TAtlasDebugStackRowKind.Frame), Ord(Rows[1].Kind));
  Assert.AreEqual(3, Rows[1].First);
  Assert.IsFalse(Rows[1].Faded);
  Assert.AreEqual(Ord(TAtlasDebugStackRowKind.Frame), Ord(Rows[2].Kind), 'einzelner Bibliotheksrahmen bleibt');
  Assert.IsTrue(Rows[2].Faded);
  Assert.AreEqual(5, Rows[3].First);
  // Aufgeklappt: drei einzelne, abgeschwächte Rahmen.
  Rows := TAtlasDebugOwnCode.Rows(SampleFrames, True, TArray<Integer>.Create(0));
  Assert.AreEqual(6, Integer(Length(Rows)));
  Assert.AreEqual(Ord(TAtlasDebugStackRowKind.Frame), Ord(Rows[0].Kind));
  Assert.IsTrue(Rows[2].Faded);
end;

procedure TAtlasDebugOwnCodeTests.RowsWithoutJustMyCode;
var
  Rows: TAtlasDebugStackRows;
  Row: TAtlasDebugStackRow;
begin
  Rows := TAtlasDebugOwnCode.Rows(SampleFrames, False, nil);
  Assert.AreEqual(6, Integer(Length(Rows)));
  for Row in Rows do
  begin
    Assert.AreEqual(Ord(TAtlasDebugStackRowKind.Frame), Ord(Row.Kind));
    Assert.IsFalse(Row.Faded);
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasDebugOwnCode.Rows(nil, True, nil))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugOwnCodeTests);

end.
