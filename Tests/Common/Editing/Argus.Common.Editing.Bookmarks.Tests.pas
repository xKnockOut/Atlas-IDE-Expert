unit Argus.Common.Editing.Bookmarks.Tests;

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
  Argus.Common.Editing.Bookmarks,
  Argus.Common.Lsp.WorkspaceSymbols;

const
  Source = 'unit U;'#10 +
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
  Found: TArray<TBookmark>;
begin
  Found := TBookmarks.Find(Source);
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Abrechnung', Found[0].Name);
  Assert.AreEqual(2, Found[0].Range.StartPos.Line);
  Assert.AreEqual('Monatsende prüfen', Found[1].Name);
  Assert.AreEqual(2, Found[1].Range.StartPos.Character);
end;

procedure TBookmarksTests.StoreReadsOnlyChangedFiles;
var
  Store: TBookmarkStore;
  Reads: Integer;
  Reader: TBookmarkReadText;
begin
  Reads := 0;
  Reader :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Inc(Reads);
      AText := Source;
      Result := True;
    end;
  Store := TBookmarkStore.Create;
  try
    Store.Update('C:\P\A.pas', 1, Reader);
    Store.Update('C:\P\A.pas', 1, Reader);
    Store.Update('C:\P\B.pas', 1, Reader);
    Assert.AreEqual(2, Reads);
    Assert.AreEqual(4, Integer(Length(Store.All)));
    Store.Update('C:\P\A.pas', 2, Reader);
    Assert.AreEqual(3, Reads);
    Store.Retain(['C:\P\B.pas']);
    Assert.AreEqual(2, Integer(Length(Store.All)));
    Assert.AreEqual('C:\P\B.pas', Store.All[0].FileName);
  finally
    Store.Free;
  end;
end;

procedure TBookmarksTests.WorkspaceSymbolFindsBookmark;
var
  Hit: TBookmarkHit;
  Found: TArray<TWorkspaceSymbol>;
begin
  Hit.FileName := 'C:\P\Kasse.pas';
  Hit.Bookmark := TBookmarks.Find(Source)[0];
  Found := TLspWorkspaceSymbols.SearchBookmarks([Hit], 'Abrechnung');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.IsTrue(Found[0].Bookmark);
  Assert.AreEqual('Kasse', Found[0].UnitName);
  Assert.AreEqual(0, Integer(Length(TLspWorkspaceSymbols.SearchBookmarks([Hit], 'Lieferung'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TBookmarksTests);

end.
