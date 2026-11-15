unit Atlas.Core.Debug.LeakFlow.Tests;

// Tests für die Entscheidungen des Fensters „Atlas-Lecks“ außerhalb von Bericht und Zeilen (#1875, #1967):
// Doppelklick, Datei des Projekts, Vergleich, bekannte Namen, Statuszeile, Ablage; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasLeakFlowTests = class
  public
    [Test]
    procedure OpenFollowsRowKind;
    [Test]
    procedure FileNamedIgnoresFolderAndCase;
    [Test]
    procedure CompareKeepsKnown;
    [Test]
    procedure KnownFromHistory;
    [Test]
    procedure StatusAndHistoryPath;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.LeakReport,
  Atlas.Core.Debug.LeakCapture,
  Atlas.Core.Debug.LeakView,
  Atlas.Core.Debug.LeakFlow;

function GroupRow(ASite: Integer): TAtlasLeakRow;
var
  mFrame: TLeakFrame;
begin
  Result := Default(TAtlasLeakRow);
  Result.Kind := TAtlasLeakRowKind.Group;
  mFrame := Default(TLeakFrame);
  mFrame.FileName := 'Kunden.pas';
  mFrame.Line := 42;
  Result.Group.Frames := [Default(TLeakFrame), mFrame];
  Result.Group.Site := ASite;
end;

function History: TAtlasLeakHistory;
begin
  Result := Default(TAtlasLeakHistory);
  Result.Names := ['TKunde'];
  Result.Counts := [3];
  Result.Known := ['TLager'];
end;

{ TAtlasLeakFlowTests }

procedure TAtlasLeakFlowTests.OpenFollowsRowKind;
var
  mRow: TAtlasLeakRow;
begin
  mRow := Default(TAtlasLeakRow);
  mRow.Kind := TAtlasLeakRowKind.Place;
  Assert.AreEqual<TAtlasLeakOpen>(TAtlasLeakOpen.Place, TAtlasLeakFlow.OpenOf(mRow));
  mRow.Kind := TAtlasLeakRowKind.Name;
  Assert.AreEqual<TAtlasLeakOpen>(TAtlasLeakOpen.None, TAtlasLeakFlow.OpenOf(mRow));
  Assert.AreEqual<TAtlasLeakOpen>(TAtlasLeakOpen.None, TAtlasLeakFlow.OpenOf(GroupRow(-1)));
  Assert.AreEqual<TAtlasLeakOpen>(TAtlasLeakOpen.Site, TAtlasLeakFlow.OpenOf(GroupRow(1)));
  Assert.AreEqual(42, TAtlasLeakFlow.SiteOf(GroupRow(1)).Line);
end;

procedure TAtlasLeakFlowTests.FileNamedIgnoresFolderAndCase;
var
  mSeparator: string;
begin
  mSeparator := PathDelim;
  Assert.AreEqual('Src' + mSeparator + 'Kunden.pas', TAtlasLeakFlow.FileNamed(['Main.pas',
    'Src' + mSeparator + 'Kunden.pas'], 'Alt' + mSeparator + 'KUNDEN.PAS'));
  Assert.AreEqual('', TAtlasLeakFlow.FileNamed(['Main.pas'], 'Kunden.pas'));
end;

procedure TAtlasLeakFlowTests.CompareKeepsKnown;
var
  mHistory: TAtlasLeakHistory;
begin
  mHistory := TAtlasLeakFlow.Compared(History, False);
  Assert.AreEqual(0, Integer(Length(mHistory.Names)));
  Assert.AreEqual(0, Integer(Length(mHistory.Counts)));
  Assert.IsTrue(mHistory.IsKnown('TLager'));
  Assert.AreEqual(3, TAtlasLeakFlow.Compared(History, True).CountOf('TKunde'));
end;

procedure TAtlasLeakFlowTests.KnownFromHistory;
var
  mEntries: TArray<TAtlasLeakEntry>;
begin
  SetLength(mEntries, 2);
  mEntries[0] := Default(TAtlasLeakEntry);
  mEntries[0].Name := 'TLager';
  mEntries[1] := Default(TAtlasLeakEntry);
  mEntries[1].Name := 'TKunde';
  mEntries[1].Known := True;
  TAtlasLeakFlow.ApplyKnown(mEntries, History);
  Assert.IsTrue(mEntries[0].Known);
  Assert.IsFalse(mEntries[1].Known);
end;

procedure TAtlasLeakFlowTests.StatusAndHistoryPath;
begin
  Assert.AreEqual('3 Lecks  ·  Suche …', TAtlasLeakFlow.StatusWith('3 Lecks', 'Suche …'));
  Assert.AreEqual('', TAtlasLeakFlow.HistoryPath('', '.atlas-local', 'leaks.json'));
  Assert.AreEqual(IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter('P') + '.atlas-local') + 'leaks.json',
    TAtlasLeakFlow.HistoryPath(IncludeTrailingPathDelimiter('P') + 'Kunden.dproj', '.atlas-local', 'leaks.json'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLeakFlowTests);

end.
