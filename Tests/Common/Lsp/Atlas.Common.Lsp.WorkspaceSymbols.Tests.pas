unit Atlas.Common.Lsp.WorkspaceSymbols.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.WorkspaceSymbols;

type
  [TestFixture]
  TLspWorkspaceSymbolsTests = class
  private
    FIndex: ISymbolIndex;
    function Names(const AQuery: string): string; overload;
    function Names(const AQuery: string; AMax: Integer): string; overload;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RanksExactPrefixAndSubstring;
    [Test]
    procedure FindsAbbreviations;
    [Test]
    procedure IgnoresCase;
    [Test]
    procedure ListsRoutinesOnce;
    [Test]
    procedure LimitsResults;
    [Test]
    procedure EmptyQueryFindsNothing;
    [Test]
    procedure MapsKinds;
    [Test]
    procedure WritesSymbolInformation;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  cUnitKunden =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '    FName: string;'#10 +
    '    procedure Speichere;'#10 +
    '  end;'#10 +
    '  TKundenListe = class'#10 +
    '  end;'#10 +
    'function KundeLaden: TKunde;'#10 +
    'implementation'#10 +
    'procedure TKunde.Speichere;'#10 +
    'begin'#10 +
    'end;'#10 +
    'function KundeLaden: TKunde;'#10 +
    'begin'#10 +
    'end;'#10 +
    'var GroßKunde: TKunde;'#10 +
    'end.';

{ TLspWorkspaceSymbolsTests }

procedure TLspWorkspaceSymbolsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitKunden, 'C:\P\Kunden.pas', nil));
end;

procedure TLspWorkspaceSymbolsTests.TearDown;
begin
  FIndex := nil;
end;

function TLspWorkspaceSymbolsTests.Names(const AQuery: string): string;
begin
  Result := Names(AQuery, 100);
end;

function TLspWorkspaceSymbolsTests.Names(const AQuery: string; AMax: Integer): string;
var
  mItem: TWorkspaceSymbol;
begin
  Result := '';
  for mItem in TLspWorkspaceSymbols.Search(FIndex, AQuery, AMax) do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + mItem.Symbol.Name;
  end;
end;

procedure TLspWorkspaceSymbolsTests.RanksExactPrefixAndSubstring;
begin
  // Exakt, dann Anfang, dann Teilstring.
  Assert.AreEqual('TKunde TKundenListe', Names('TKunde'));
  Assert.AreEqual('KundeLaden TKunde TKundenListe GroßKunde', Names('Kunde'));
end;

procedure TLspWorkspaceSymbolsTests.FindsAbbreviations;
begin
  // Großbuchstaben-Kürzel und Teilfolgen (#39).
  Assert.AreEqual('TKundenListe', Names('TKL'));
  Assert.AreEqual('TKundenListe', Names('tkl'));
  Assert.AreEqual('KundeLaden TKundenListe', Names('KL'));
end;

procedure TLspWorkspaceSymbolsTests.IgnoresCase;
begin
  Assert.AreEqual('Speichere', Names('speich'));
end;

procedure TLspWorkspaceSymbolsTests.ListsRoutinesOnce;
var
  mFound: TArray<TWorkspaceSymbol>;
begin
  mFound := TLspWorkspaceSymbols.Search(FIndex, 'Speichere', 10);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('TKunde', mFound[0].Symbol.Container);
  Assert.AreEqual(5, mFound[0].Symbol.SelectionRange.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(TLspWorkspaceSymbols.Search(FIndex, 'KundeLaden', 10))));
end;

procedure TLspWorkspaceSymbolsTests.LimitsResults;
begin
  Assert.AreEqual('TKunde', Names('TKunde', 1));
end;

procedure TLspWorkspaceSymbolsTests.EmptyQueryFindsNothing;
begin
  Assert.AreEqual('', Names('  '));
  Assert.AreEqual('', Names('Gibtsnicht'));
end;

procedure TLspWorkspaceSymbolsTests.MapsKinds;
begin
  Assert.AreEqual(5, TLspWorkspaceSymbols.LspKind(TIndexSymbolKind.ClassType));
  Assert.AreEqual(23, TLspWorkspaceSymbols.LspKind(TIndexSymbolKind.RecordType));
  Assert.AreEqual(6, TLspWorkspaceSymbols.LspKind(TIndexSymbolKind.Method));
  Assert.AreEqual(12, TLspWorkspaceSymbols.LspKind(TIndexSymbolKind.Routine));
end;

procedure TLspWorkspaceSymbolsTests.WritesSymbolInformation;
var
  mJson: TJSONArray;
  mSymbol: TJSONValue;
  mName, mContainer, mUri: string;
  mKind, mLine: Integer;
begin
  mJson := TLspWorkspaceSymbols.ToJson(TLspWorkspaceSymbols.Search(FIndex, 'Speichere', 10));
  try
    Assert.AreEqual(1, Integer(mJson.Count));
    // Werte erst in typisierte Variablen lesen: Json.Items[0].GetValue<T>
    // direkt als Argument von Assert.AreEqual übersetzt dcc64 (Delphi 13) nicht.
    mSymbol := mJson.Items[0];
    mName := mSymbol.GetValue<string>('name');
    mKind := mSymbol.GetValue<Integer>('kind');
    mContainer := mSymbol.GetValue<string>('containerName');
    mUri := mSymbol.GetValue<string>('location.uri');
    mLine := mSymbol.GetValue<Integer>('location.range.start.line');
    Assert.AreEqual('Speichere', mName);
    Assert.AreEqual(6, mKind);
    Assert.AreEqual('Kunden.TKunde', mContainer);
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\Kunden.pas'), mUri);
    Assert.AreEqual(5, mLine);
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspWorkspaceSymbolsTests);

end.
