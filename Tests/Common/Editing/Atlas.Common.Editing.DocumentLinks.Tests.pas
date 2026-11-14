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
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Editing.DocumentLinks,
  Atlas.Common.Lsp.DocumentLinks;

const
  cDir = 'C:\Proj\';
  cUnitFile = cDir + 'Main.pas';

function Exists(const AFiles: array of string): TFileExistsFunc;
var
  mList: TArray<string>;
  I: Integer;
begin
  SetLength(mList, Length(AFiles));
  for I := 0 to High(AFiles) do
  begin
    mList[I] := AFiles[I];
  end;
  Result :=
    function(const AFileName: string): Boolean
    var
      Name: string;
    begin
      for Name in mList do
      begin
        if SameText(Name, AFileName) then
        begin
          Exit(True);
        end;
      end;
      Result := False;
    end;
end;

function Links(const AText: string; const AFiles: array of string;
  const ASearchPaths: TArray<string>): TArray<TDocumentLink>; overload;
begin
  Result := TDocumentLinks.Find(AText, cUnitFile, ASearchPaths, Exists(AFiles));
end;

function Links(const AText: string; const AFiles: array of string): TArray<TDocumentLink>; overload;
begin
  Result := Links(AText, AFiles, nil);
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
  mFound: TArray<TDocumentLink>;
begin
  mFound := Links('unit Main;' + sLineBreak + '{$I Defs.inc}', [cDir + 'Defs.inc']);
  Assert.AreEqual<NativeInt>(1, Length(mFound));
  Assert.AreEqual(cDir + 'Defs.inc', mFound[0].Target);
  Assert.IsFalse(mFound[0].IsUrl);
  AssertRange(mFound[0], 1, 4, 12);
end;

procedure TDocumentLinksTests.IncludeWithQuotesAndLongForm;
var
  mFound: TArray<TDocumentLink>;
begin
  mFound := Links('{$INCLUDE ''Sub Dir\A.inc''} (*$I B.inc*)', [cDir + 'Sub Dir\A.inc', cDir + 'B.inc']);
  Assert.AreEqual<NativeInt>(2, Length(mFound));
  Assert.AreEqual(cDir + 'Sub Dir\A.inc', mFound[0].Target);
  AssertRange(mFound[0], 0, 11, 24);
  Assert.AreEqual(cDir + 'B.inc', mFound[1].Target);
  AssertRange(mFound[1], 0, 32, 37);
end;

procedure TDocumentLinksTests.IncludeFromSearchPath;
var
  mFound: TArray<TDocumentLink>;
begin
  mFound := Links('{$I Shared.inc}', ['D:\Lib\Shared.inc'], ['D:\Lib']);
  Assert.AreEqual<NativeInt>(1, Length(mFound));
  Assert.AreEqual('D:\Lib\Shared.inc', mFound[0].Target);
end;

procedure TDocumentLinksTests.ResourceWithStarUsesUnitName;
var
  mFound: TArray<TDocumentLink>;
begin
  mFound := Links('{$R *.dfm}', [cDir + 'Main.dfm']);
  Assert.AreEqual<NativeInt>(1, Length(mFound));
  Assert.AreEqual(cDir + 'Main.dfm', mFound[0].Target);
  AssertRange(mFound[0], 0, 4, 9);
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
  mFound: TArray<TDocumentLink>;
begin
  mFound := Links('// siehe https://example.com/a?b=1.', []);
  Assert.AreEqual<NativeInt>(1, Length(mFound));
  Assert.IsTrue(mFound[0].IsUrl);
  Assert.AreEqual('https://example.com/a?b=1', mFound[0].Target);
  AssertRange(mFound[0], 0, 9, 34);
end;

procedure TDocumentLinksTests.UrlInMultilineComment;
var
  mFound: TArray<TDocumentLink>;
begin
  mFound := Links('{ Doku:' + #10 + '  http://x.de/y }', []);
  Assert.AreEqual<NativeInt>(1, Length(mFound));
  AssertRange(mFound[0], 1, 2, 15);
end;

procedure TDocumentLinksTests.UrlAndFileInString;
var
  mFound: TArray<TDocumentLink>;
begin
  mFound := Links('S := ''https://x.de''; T := ''Daten\Liste.txt'';', [cDir + 'Daten\Liste.txt']);
  Assert.AreEqual<NativeInt>(2, Length(mFound));
  Assert.AreEqual('https://x.de', mFound[0].Target);
  Assert.AreEqual(cDir + 'Daten\Liste.txt', mFound[1].Target);
  AssertRange(mFound[1], 0, 27, 42);
end;

procedure TDocumentLinksTests.SentenceInStringIsNoLink;
begin
  Assert.AreEqual<NativeInt>(0, Length(Links('S := ''Fehler in Datei.txt''; T := ''%s.txt'';',
    [cDir + 'Fehler in Datei.txt', cDir + '%s.txt'])));
end;

procedure TDocumentLinksTests.LspLinkUsesFileUriOrUrl;
var
  mLink: TDocumentLink;
  mItem: TJSONObject;
begin
  mLink := Links('{$I Defs.inc} // http://x.de', [cDir + 'Defs.inc'])[0];
  mItem := TLspDocumentLinks.LinkToJson(mLink);
  try
    Assert.AreEqual(TDocumentUris.FromPath(cDir + 'Defs.inc'), mItem.GetValue<string>('target'));
    Assert.AreEqual(4, mItem.GetValue<Integer>('range.start.character'));
  finally
    mItem.Free;
  end;
  mLink := Links('{$I Defs.inc} // http://x.de', [cDir + 'Defs.inc'])[1];
  mItem := TLspDocumentLinks.LinkToJson(mLink);
  try
    Assert.AreEqual('http://x.de', mItem.GetValue<string>('target'));
  finally
    mItem.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDocumentLinksTests);

end.
