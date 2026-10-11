unit Atlas.Common.Editing.DocumentLinks.Tests;

// Tests für anklickbare Verweise (#25).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDocumentLinksTests = class
  public
    [Test]
    procedure IncludeDirective;
    [Test]
    procedure IncludeWithQuotesAndLongForm;
    [Test]
    procedure IncludeFromSearchPath;
    [Test]
    procedure ResourceWithStarUsesUnitName;
    [Test]
    procedure SwitchesAreNoLinks;
    [Test]
    procedure MissingFileIsNoLink;
    [Test]
    procedure UrlInComment;
    [Test]
    procedure UrlInMultilineComment;
    [Test]
    procedure UrlAndFileInString;
    [Test]
    procedure SentenceInStringIsNoLink;
    [Test]
    procedure LspLinkUsesFileUriOrUrl;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  System.JSON,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Editing.DocumentLinks,
  Atlas.Common.Lsp.DocumentLinks;

const
  Dir = 'C:\Proj\';
  UnitFile = Dir + 'Main.pas';

function Exists(const AFiles: array of string): TFileExistsFunc;
var
  List: TArray<string>;
  I: Integer;
begin
  SetLength(List, Length(AFiles));
  for I := 0 to High(AFiles) do
    List[I] := AFiles[I];
  Result :=
    function(const AFileName: string): Boolean
    var
      Name: string;
    begin
      for Name in List do
        if SameText(Name, AFileName) then
          Exit(True);
      Result := False;
    end;
end;

function Links(const AText: string; const AFiles: array of string;
  const ASearchPaths: TArray<string> = nil): TArray<TDocumentLink>;
begin
  Result := TDocumentLinks.Find(AText, UnitFile, ASearchPaths, Exists(AFiles));
end;

procedure AssertRange(const ALink: TDocumentLink; ALine, AStart, AEnd: Integer);
begin
  Assert.AreEqual(ALine, ALink.Range.StartPos.Line, 'Zeile');
  Assert.AreEqual(AStart, ALink.Range.StartPos.Character, 'Anfang');
  Assert.AreEqual(AEnd, ALink.Range.EndPos.Character, 'Ende');
end;

{ TDocumentLinksTests }

procedure TDocumentLinksTests.IncludeDirective;
var
  Found: TArray<TDocumentLink>;
begin
  Found := Links('unit Main;' + sLineBreak + '{$I Defs.inc}', [Dir + 'Defs.inc']);
  Assert.AreEqual<NativeInt>(1, Length(Found));
  Assert.AreEqual(Dir + 'Defs.inc', Found[0].Target);
  Assert.IsFalse(Found[0].IsUrl);
  AssertRange(Found[0], 1, 4, 12);
end;

procedure TDocumentLinksTests.IncludeWithQuotesAndLongForm;
var
  Found: TArray<TDocumentLink>;
begin
  Found := Links('{$INCLUDE ''Sub Dir\A.inc''} (*$I B.inc*)', [Dir + 'Sub Dir\A.inc', Dir + 'B.inc']);
  Assert.AreEqual<NativeInt>(2, Length(Found));
  Assert.AreEqual(Dir + 'Sub Dir\A.inc', Found[0].Target);
  AssertRange(Found[0], 0, 11, 24);
  Assert.AreEqual(Dir + 'B.inc', Found[1].Target);
  AssertRange(Found[1], 0, 32, 37);
end;

procedure TDocumentLinksTests.IncludeFromSearchPath;
var
  Found: TArray<TDocumentLink>;
begin
  Found := Links('{$I Shared.inc}', ['D:\Lib\Shared.inc'], ['D:\Lib']);
  Assert.AreEqual<NativeInt>(1, Length(Found));
  Assert.AreEqual('D:\Lib\Shared.inc', Found[0].Target);
end;

procedure TDocumentLinksTests.ResourceWithStarUsesUnitName;
var
  Found: TArray<TDocumentLink>;
begin
  Found := Links('{$R *.dfm}', [Dir + 'Main.dfm']);
  Assert.AreEqual<NativeInt>(1, Length(Found));
  Assert.AreEqual(Dir + 'Main.dfm', Found[0].Target);
  AssertRange(Found[0], 0, 4, 9);
end;

procedure TDocumentLinksTests.SwitchesAreNoLinks;
begin
  Assert.AreEqual<NativeInt>(0, Length(Links('{$I+} {$R-} {$IFDEF X}{$ENDIF}', [])));
end;

procedure TDocumentLinksTests.MissingFileIsNoLink;
begin
  Assert.AreEqual<NativeInt>(0, Length(Links('{$I Fehlt.inc}', [])));
end;

procedure TDocumentLinksTests.UrlInComment;
var
  Found: TArray<TDocumentLink>;
begin
  Found := Links('// siehe https://example.com/a?b=1.', []);
  Assert.AreEqual<NativeInt>(1, Length(Found));
  Assert.IsTrue(Found[0].IsUrl);
  Assert.AreEqual('https://example.com/a?b=1', Found[0].Target);
  AssertRange(Found[0], 0, 9, 34);
end;

procedure TDocumentLinksTests.UrlInMultilineComment;
var
  Found: TArray<TDocumentLink>;
begin
  Found := Links('{ Doku:' + #10 + '  http://x.de/y }', []);
  Assert.AreEqual<NativeInt>(1, Length(Found));
  AssertRange(Found[0], 1, 2, 15);
end;

procedure TDocumentLinksTests.UrlAndFileInString;
var
  Found: TArray<TDocumentLink>;
begin
  Found := Links('S := ''https://x.de''; T := ''Daten\Liste.txt'';', [Dir + 'Daten\Liste.txt']);
  Assert.AreEqual<NativeInt>(2, Length(Found));
  Assert.AreEqual('https://x.de', Found[0].Target);
  Assert.AreEqual(Dir + 'Daten\Liste.txt', Found[1].Target);
  AssertRange(Found[1], 0, 27, 42);
end;

procedure TDocumentLinksTests.SentenceInStringIsNoLink;
begin
  Assert.AreEqual<NativeInt>(0, Length(Links('S := ''Fehler in Datei.txt''; T := ''%s.txt'';',
    [Dir + 'Fehler in Datei.txt', Dir + '%s.txt'])));
end;

procedure TDocumentLinksTests.LspLinkUsesFileUriOrUrl;
var
  Link: TDocumentLink;
  Item: TJSONObject;
begin
  Link := Links('{$I Defs.inc} // http://x.de', [Dir + 'Defs.inc'])[0];
  Item := TLspDocumentLinks.LinkToJson(Link);
  try
    Assert.AreEqual(TDocumentUris.FromPath(Dir + 'Defs.inc'), Item.GetValue<string>('target'));
    Assert.AreEqual(4, Item.GetValue<Integer>('range.start.character'));
  finally
    Item.Free;
  end;
  Link := Links('{$I Defs.inc} // http://x.de', [Dir + 'Defs.inc'])[1];
  Item := TLspDocumentLinks.LinkToJson(Link);
  try
    Assert.AreEqual('http://x.de', Item.GetValue<string>('target'));
  finally
    Item.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDocumentLinksTests);

end.
