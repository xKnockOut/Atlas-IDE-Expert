unit Atlas.Common.Editing.NameSuggestions.Tests;

// Tests für die Namensvorschläge aus dem Typ (#452) und die Zählung der
// Präfixe im Index.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TNameSuggestionsTests = class
  public
    [Test]
    procedure DerivesNamesFromListType;
    [Test]
    procedure DerivesNamesFromGenericsAndArrays;
    [Test]
    procedure DerivesNamesFromPlainTypes;
    [Test]
    procedure SplitsLastWordAndPlural;
    [Test]
    procedure PrefixNeedsSixtyPercent;
    [Test]
    procedure TakenNamesGetDigits;
    [Test]
    procedure FindsFieldSite;
    [Test]
    procedure FindsLocalParameterAndInlineSites;
    [Test]
    procedure FindsGlobalSiteAndRejectsOthers;
    [Test]
    procedure CountsPrefixesInTree;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.NameSuggestions;

function Join(const ALines: array of string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(ALines) do
    Result := Result + ALines[Index] + #10;
end;

/// <summary>Namensposition am "|" in AMarked als "Art Typ" ("field TCustomerList", "global …"); '-' ohne.</summary>
function SiteOf(const AMarked: string): string;
var
  Text: string;
  Line, Character, Index: Integer;
  Tree: TSyntaxTree;
  Site: TNameSite;
const
  Kinds: array[TNamingKind] of string = ('field', 'parameter', 'local');
begin
  Line := 0;
  Character := 0;
  for Index := 1 to Pos('|', AMarked) - 1 do
    if AMarked[Index] = #10 then
    begin
      Inc(Line);
      Character := 0;
    end
    else
      Inc(Character);
  Text := StringReplace(AMarked, '|', '', []);
  Tree := TPascalParser.Parse(Text);
  try
    if not TNameSuggestions.Site(Tree, TTextPosition.Create(Line, Character), Site) then
      Exit('-');
    if Site.Global then
      Result := 'global ' + Site.TypeText
    else
      Result := Kinds[Site.Kind] + ' ' + Site.TypeText;
    if Site.Typed <> '' then
      Result := Result + ' (' + Site.Typed + ')';
  finally
    Tree.Free;
  end;
end;

function Count(ATotal, APrefixed: Integer): TNamingCount;
begin
  Result.Total := ATotal;
  Result.Prefixed := APrefixed;
end;

procedure TNameSuggestionsTests.DerivesNamesFromListType;
begin
  // Akzeptanz #452: TCustomerList mit F-Konvention ergibt FCustomers, FCustomerList, FList.
  Assert.AreEqual('FCustomers FCustomerList FList', string.Join(' ',
    TNameSuggestions.Suggest('TCustomerList', 'F', nil)));
  Assert.AreEqual('Customers CustomerList List', string.Join(' ', TNameSuggestions.Suggest('TCustomerList', '', nil)));
  Assert.IsTrue(TNameSuggestions.IsListType('TCustomerList'));
  Assert.IsTrue(TNameSuggestions.IsListType('Data.TOrderCollection'));
  Assert.IsFalse(TNameSuggestions.IsListType('TList'));
  Assert.IsFalse(TNameSuggestions.IsListType('TCustomer'));
end;

procedure TNameSuggestionsTests.DerivesNamesFromGenericsAndArrays;
begin
  Assert.AreEqual('Customers CustomerList List', string.Join(' ', TNameSuggestions.Bases('TList<TCustomer>')));
  Assert.AreEqual('Orders OrderList List', string.Join(' ', TNameSuggestions.Bases('TObjectList<Shop.TOrder>')));
  // "Array" ist reserviert und entfällt.
  Assert.AreEqual('Customers CustomerArray', string.Join(' ', TNameSuggestions.Bases('TArray<TCustomer>')));
  Assert.AreEqual('Customers CustomerArray', string.Join(' ', TNameSuggestions.Bases('array of TCustomer')));
  Assert.AreEqual('Texts TextArray', string.Join(' ', TNameSuggestions.Bases('array[0..9] of string')));
  // Zwei Typargumente: keine Liste.
  Assert.AreEqual('Dictionary', string.Join(' ', TNameSuggestions.Bases('TDictionary<string, TCustomer>')));
  Assert.IsTrue(TNameSuggestions.IsListType('TArray<Integer>'));
  Assert.IsFalse(TNameSuggestions.IsListType('TDictionary<string, TCustomer>'));
end;

procedure TNameSuggestionsTests.DerivesNamesFromPlainTypes;
begin
  Assert.AreEqual('Customer', string.Join(' ', TNameSuggestions.Bases('TCustomer')));
  Assert.AreEqual('HttpClient Client', string.Join(' ', TNameSuggestions.Bases('System.Net.THttpClient')));
  Assert.AreEqual('Exporter', string.Join(' ', TNameSuggestions.Bases('IExporter')));
  Assert.AreEqual('Text', string.Join(' ', TNameSuggestions.Bases('string')));
  Assert.AreEqual('Value', string.Join(' ', TNameSuggestions.Bases('Integer')));
  Assert.AreEqual('Strings StringList List', string.Join(' ', TNameSuggestions.Bases('TStringList')));
end;

procedure TNameSuggestionsTests.SplitsLastWordAndPlural;
begin
  Assert.AreEqual('List', TNameSuggestions.LastWord('CustomerList'));
  Assert.AreEqual('Client', TNameSuggestions.LastWord('HTTPClient'));
  Assert.AreEqual('IO', TNameSuggestions.LastWord('FileIO'));
  Assert.AreEqual('Customer', TNameSuggestions.LastWord('Customer'));
  Assert.AreEqual('Vector3', TNameSuggestions.LastWord('Vector3'));
  Assert.AreEqual('Categories', TNameSuggestions.Plural('Category'));
  Assert.AreEqual('Keys', TNameSuggestions.Plural('Key'));
  Assert.AreEqual('Boxes', TNameSuggestions.Plural('Box'));
  Assert.AreEqual('Matches', TNameSuggestions.Plural('Match'));
  Assert.AreEqual('Customers', TNameSuggestions.Plural('Customer'));
end;

procedure TNameSuggestionsTests.PrefixNeedsSixtyPercent;
begin
  Assert.IsTrue(TNameSuggestions.UsesPrefix(Count(10, 6)));
  Assert.IsFalse(TNameSuggestions.UsesPrefix(Count(10, 5)));
  Assert.IsFalse(TNameSuggestions.UsesPrefix(Count(0, 0)));
  Assert.IsTrue(TNameSuggestions.UsesPrefix(Count(3, 2)));
  Assert.AreEqual('FCustomer', TNameSuggestions.Prefixed('Customer', 'F'));
  Assert.AreEqual('FCustomer', TNameSuggestions.Prefixed('FCustomer', 'F'));
  Assert.AreEqual('m_Value', TNameSuggestions.Prefixed('Value', 'm_'));
  Assert.AreEqual('Value', TNameSuggestions.Prefixed('Value', ''));
end;

procedure TNameSuggestionsTests.TakenNamesGetDigits;
begin
  Assert.AreEqual('Customers2', TNameSuggestions.Unique('Customers', ['customers']));
  Assert.AreEqual('List3', TNameSuggestions.Unique('List', ['List', 'List2']));
  Assert.AreEqual('LCustomers2 LCustomerList LList', string.Join(' ',
    TNameSuggestions.Suggest('TCustomerList', 'L', ['LCustomers', 'Customers'])));
end;

procedure TNameSuggestionsTests.FindsFieldSite;
begin
  Assert.AreEqual('field TCustomerList', SiteOf(Join([
    'unit U;',
    'interface',
    'type',
    '  TForm = class',
    '  private',
    '    |: TCustomerList;',
    '  end;',
    'implementation',
    'end.'])));
  Assert.AreEqual('field TList<TCustomer> (FCu)', SiteOf(Join([
    'unit U;',
    'interface',
    'type',
    '  TForm = class',
    '    FName: string;',
    '    FCu|: TList<TCustomer>;',
    '  end;',
    'implementation',
    'end.'])));
  Assert.AreEqual('field TPoint', SiteOf(Join([
    'unit U;',
    'interface',
    'type',
    '  TLine = record',
    '    |: TPoint;',
    '  end;',
    'implementation',
    'end.'])));
end;

procedure TNameSuggestionsTests.FindsLocalParameterAndInlineSites;
begin
  Assert.AreEqual('local TCustomerList', SiteOf(Join([
    'unit U;',
    'interface',
    'implementation',
    'procedure Laden;',
    'var',
    '  Count: Integer;',
    '  |: TCustomerList;',
    'begin',
    'end;',
    'end.'])));
  Assert.AreEqual('parameter TCustomer', SiteOf(Join([
    'unit U;',
    'interface',
    'implementation',
    'procedure Laden(const |: TCustomer; Count: Integer);',
    'begin',
    'end;',
    'end.'])));
  Assert.AreEqual('parameter string', SiteOf(Join([
    'unit U;',
    'interface',
    'implementation',
    'procedure TForm.Laden(Count: Integer; |: string);',
    'begin',
    'end;',
    'end.'])));
  Assert.AreEqual('local TCustomerList', SiteOf(Join([
    'unit U;',
    'interface',
    'implementation',
    'procedure Laden;',
    'begin',
    '  var |: TCustomerList := nil;',
    'end;',
    'end.'])));
end;

procedure TNameSuggestionsTests.FindsGlobalSiteAndRejectsOthers;
begin
  Assert.AreEqual('global TCustomerList', SiteOf(Join([
    'unit U;',
    'interface',
    'var',
    '  |: TCustomerList;',
    'implementation',
    'end.'])));
  // Ohne Typ rechts vom Caret, in Konstanten und in Anweisungen nichts.
  Assert.AreEqual('-', SiteOf(Join([
    'unit U;',
    'interface',
    'var',
    '  |',
    'implementation',
    'end.'])));
  Assert.AreEqual('-', SiteOf(Join([
    'unit U;',
    'interface',
    'const',
    '  |: Integer = 5;',
    'implementation',
    'end.'])));
  Assert.AreEqual('-', SiteOf(Join([
    'unit U;',
    'interface',
    'implementation',
    'procedure Laden;',
    'begin',
    '  try',
    '  except',
    '    on |: Exception do;',
    '  end;',
    'end;',
    'end.'])));
end;

procedure TNameSuggestionsTests.CountsPrefixesInTree;
var
  Tree: TSyntaxTree;
  Counts: TNamingCounts;
begin
  Tree := TPascalParser.Parse(Join([
    'unit U;',
    'interface',
    'type',
    '  TForm = class',
    '    FName, FCity: string;',
    '    Count: Integer;',
    '  public',
    '    procedure Laden(AValue: Integer; Fast: Boolean);',
    '  end;',
    'var',
    '  Global: Integer;',
    'implementation',
    'procedure TForm.Laden(AValue: Integer; Fast: Boolean);',
    'var',
    '  LIndex: Integer;',
    'begin',
    '  var LText := '''';',
    'end;',
    'end.']));
  try
    Counts := TIndexExtractor.NamingOf(Tree.Root);
  finally
    Tree.Free;
  end;
  Assert.AreEqual(3, Counts[TNamingKind.Field].Total);
  Assert.AreEqual(2, Counts[TNamingKind.Field].Prefixed);
  Assert.AreEqual(4, Counts[TNamingKind.Parameter].Total);
  Assert.AreEqual(2, Counts[TNamingKind.Parameter].Prefixed);
  // Die globale Variable zählt nicht.
  Assert.AreEqual(2, Counts[TNamingKind.Local].Total);
  Assert.AreEqual(2, Counts[TNamingKind.Local].Prefixed);
  Assert.IsTrue(TIndexExtractor.HasNamePrefix('FName', 'F'));
  Assert.IsFalse(TIndexExtractor.HasNamePrefix('Fast', 'F'));
  Assert.IsFalse(TIndexExtractor.HasNamePrefix('F', 'F'));
end;

initialization
  TDUnitX.RegisterTestFixture(TNameSuggestionsTests);

end.
