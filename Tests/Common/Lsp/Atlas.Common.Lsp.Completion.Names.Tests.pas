unit Atlas.Common.Lsp.Completion.Names.Tests;

// Tests für die Namensvorschläge an der Namensposition einer Deklaration (#452).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Completion.Names;

type
  [TestFixture]
  TCompletionNamesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function NamesAt(ALine, ACharacter: Integer; const ANamingFor: TCompletionNamingFunc;
      ASwitchedOn: Boolean): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Vorgabe über die Namensfunktion: Feldnamen mit F.</summary>
    [Test]
    procedure FieldNamesWithForcedPrefix;
    /// <summary>Ohne Vorgabe und ohne Index kein Präfix.</summary>
    [Test]
    procedure FieldNamesWithoutPrefix;
    /// <summary>completion.nameSuggestions aus: keine Vorschläge.</summary>
    [Test]
    procedure SwitchedOffOffersNothing;
    /// <summary>Außerhalb einer Namensposition keine Vorschläge.</summary>
    [Test]
    procedure NothingOutsideNameSite;
    /// <summary>Ohne Index zählt NamingPrefix nichts.</summary>
    [Test]
    procedure NamingPrefixWithoutIndex;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Lsp.CompletionRequest;

const
  cFieldSite =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TForm = class'#10 +
    '  private'#10 +
    '    : TCustomerList;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

/// <summary>Namen der Vorschläge an Zeile ALine, Spalte ACharacter, durch Leerzeichen getrennt; '-' ohne.
/// </summary>
function TCompletionNamesTests.NamesAt(ALine, ACharacter: Integer; const ANamingFor: TCompletionNamingFunc;
  ASwitchedOn: Boolean): string;
var
  mTree: TSyntaxTree;
  mRequest: TCompletionRequest;
  mSettings: TCompletionSettings;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  Result := '-';
  mTree := TPascalParser.Parse(cFieldSite);
  mRequest := TCompletionRequest.Create(cFieldSite, 'C:\P\Haupt.pas', TTextPosition.Create(ALine, ACharacter));
  try
    mRequest.Tree := mTree;
    mRequest.Index := FIndex;
    mRequest.Resolver := FResolver;
    mSettings := mRequest.Settings;
    mSettings.NameSuggestions := ASwitchedOn;
    mRequest.Settings := mSettings;
    if TCompletionNames.NameItems(mRequest, ANamingFor, mItems) then
    begin
      Result := '';
      for mItem in mItems.Items do
      begin
        Result := Trim(Result + ' ' + mItem.Name);
      end;
    end;
  finally
    mRequest.Free;
    mTree.Free;
  end;
end;

function FieldPrefix: TCompletionNamingFunc;
begin
  Result :=
    function(const AUri: string; AKind: TNamingKind): string
    begin
      Result := '';
      if AKind = TNamingKind.Field then
      begin
        Result := 'F';
      end;
    end;
end;

procedure TCompletionNamesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TCompletionNamesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

procedure TCompletionNamesTests.FieldNamesWithForcedPrefix;
begin
  Assert.AreEqual('FCustomers FCustomerList FList', NamesAt(5, 4, FieldPrefix(), True));
end;

procedure TCompletionNamesTests.FieldNamesWithoutPrefix;
begin
  Assert.AreEqual('Customers CustomerList List', NamesAt(5, 4, nil, True));
end;

procedure TCompletionNamesTests.SwitchedOffOffersNothing;
begin
  Assert.AreEqual('-', NamesAt(5, 4, FieldPrefix(), False));
end;

procedure TCompletionNamesTests.NothingOutsideNameSite;
begin
  Assert.AreEqual('-', NamesAt(3, 4, nil, True));
end;

procedure TCompletionNamesTests.NamingPrefixWithoutIndex;
begin
  Assert.AreEqual('', TCompletionNames.NamingPrefix(nil, TNamingKind.Field));
  Assert.AreEqual('', TCompletionNames.NamingPrefix(FIndex, TNamingKind.Field), 'leerer Index');
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionNamesTests);

end.
