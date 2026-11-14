unit Atlas.Common.Editing.Bookmarks.Tests;

// Tests für Lesezeichen "// @bookmark Name" und ihre Suche (#306).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TBookmarksTests = class
  public
    [Test]
    procedure FindsMarkedComments;
    [Test]
    procedure StoreReadsOnlyChangedFiles;
    [Test]
    procedure WorkspaceSymbolFindsBookmark;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Editing.Bookmarks,
  Atlas.Common.Lsp.WorkspaceSymbols;

const
  cSource = 'unit U;'#10 +
    'implementation'#10 +
    '// @bookmark Abrechnung'#10 +
    'procedure Run;'#10 +
    'begin'#10 +
    '  { @bookmark Monatsende prüfen }'#10 +
    '  S := ''// @bookmark kein Lesezeichen'';'#10 +
    '  // @bookmark'#10 +
    '  // Hinweis: @bookmark mitten im Text zählt nicht'#10 +
    'end;'#10 +
    'end.';

procedure TBookmarksTests.FindsMarkedComments;
var
  mFound: TArray<TBookmark>;
begin
  mFound := TBookmarks.Find(cSource);
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Abrechnung', mFound[0].Name);
  Assert.AreEqual(2, mFound[0].Range.StartPos.Line);
  Assert.AreEqual('Monatsende prüfen', mFound[1].Name);
  Assert.AreEqual(2, mFound[1].Range.StartPos.Character);
end;

procedure TBookmarksTests.StoreReadsOnlyChangedFiles;
var
  mStore: TBookmarkStore;
  mReads: Integer;
  mReader: TBookmarkReadText;
begin
  mReads := 0;
  mReader :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Inc(mReads);
      AText := cSource;
      Result := True;
    end;
  mStore := TBookmarkStore.Create;
  try
    mStore.Update('C:\P\A.pas', 1, mReader);
    mStore.Update('C:\P\A.pas', 1, mReader);
    mStore.Update('C:\P\B.pas', 1, mReader);
    Assert.AreEqual(2, mReads);
    Assert.AreEqual(4, Integer(Length(mStore.All)));
    mStore.Update('C:\P\A.pas', 2, mReader);
    Assert.AreEqual(3, mReads);
    mStore.Retain(['C:\P\B.pas']);
    Assert.AreEqual(2, Integer(Length(mStore.All)));
    Assert.AreEqual('C:\P\B.pas', mStore.All[0].FileName);
  finally
    mStore.Free;
  end;
end;

procedure TBookmarksTests.WorkspaceSymbolFindsBookmark;
var
  mHit: TBookmarkHit;
  mFound: TArray<TWorkspaceSymbol>;
begin
  mHit.FileName := 'C:\P\Kasse.pas';
  mHit.Bookmark := TBookmarks.Find(cSource)[0];
  mFound := TLspWorkspaceSymbols.SearchBookmarks([mHit], 'Abrechnung');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.IsTrue(mFound[0].Bookmark);
  Assert.AreEqual('Kasse', mFound[0].UnitName);
  Assert.AreEqual(0, Integer(Length(TLspWorkspaceSymbols.SearchBookmarks([mHit], 'Lieferung'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TBookmarksTests);

end.
