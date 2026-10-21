unit Atlas.Common.Lsp.CompletionUses.Tests;

// Vervollständigung im uses-Abschnitt (#469): Gruppen, ausgeblendete eingebundene Units, Kurzformen,
// Hinweis auf den anderen Abschnitt, Zirkelbezüge, Details und der Schalter completion.usesDetails.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest;

type
  [TestFixture]
  TCompletionUsesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemsAt(const AText, AMarker: string): TCompletionItems; overload;
    function ItemsAt(const AText, AMarker: string; AUsesDetails: Boolean): TCompletionItems; overload;
    function Names(const AItems: TCompletionItems): string;
    function Find(const AItems: TCompletionItems; const AName: string; out AItem: TCompletionItem): Boolean;
    procedure AddUnit(const AText, AFileName: string; ALibrary: Boolean);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure GenerShowsGenericsUnitsGroupedAndSkipsUsedUnit;
    [Test]
    procedure FooterNamesUsedUnits;
    [Test]
    procedure ShortFormBecomesFullName;
    [Test]
    procedure UnitOfOtherSectionCarriesHint;
    [Test]
    procedure CircularReferenceInInterfaceOnly;
    [Test]
    procedure DetailsCarryPathAndTypes;
    [Test]
    procedure SwitchOffListsAllUnits;
    [Test]
    procedure WritesUsesDataToJson;
    [Test]
    procedure MatchesFromLaterNamePart;
    [Test]
    procedure GroupsAndShortPaths;
    [Test]
    procedure SiteReadsIncompleteListAndOtherSection;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.CompletionJson,
  Atlas.Common.Lsp.CompletionUses;

const
  HauptFile = 'C:\P\Haupt.pas';
  Bds = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\source\rtl\';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses System.SysUtils, Gener'#10 +
    'implementation'#10 +
    'uses System.Generics.Defaults;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  Index, Line, LineStart, Scan: Integer;
begin
  // Cursor hinter AMarker.
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Inc(Index, Length(AMarker));
  Line := 0;
  LineStart := 1;
  for Scan := 1 to Index - 1 do
    if AText[Scan] = #10 then
    begin
      Inc(Line);
      LineStart := Scan + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

{ TCompletionUsesTests }

procedure TCompletionUsesTests.AddUnit(const AText, AFileName: string; ALibrary: Boolean);
var
  UnitInfo: TUnitIndex;
begin
  UnitInfo := TIndexExtractor.ExtractText(AText, AFileName, nil);
  UnitInfo.Library_ := ALibrary;
  FIndex.AddUnit(UnitInfo);
end;

procedure TCompletionUsesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  AddUnit('unit uGeneratorBeleg;'#10'interface'#10'uses Haupt;'#10'implementation'#10'end.',
    'C:\P\uGeneratorBeleg.pas', False);
  AddUnit('unit uMitte;'#10'interface'#10'uses uZwei;'#10'implementation'#10'end.', 'C:\P\uMitte.pas', False);
  AddUnit('unit uZwei;'#10'interface'#10'uses Haupt;'#10'implementation'#10'end.', 'C:\P\uZwei.pas', False);
  AddUnit('unit System.SysUtils;'#10'interface'#10'type'#10'  Exception = class end;'#10'implementation'#10'end.',
    Bds + 'sys\System.SysUtils.pas', True);
  AddUnit('unit System.Classes;'#10'interface'#10'type'#10'  TStrings = class end;'#10'implementation'#10'end.',
    Bds + 'common\System.Classes.pas', True);
  AddUnit('unit System.Generics.Collections;'#10'interface'#10'type'#10 +
    '  TList<T> = class end;'#10'  TObjectList<T: class> = class end;'#10'  TDictionary<K, V> = class end;'#10 +
    '  TQueue<T> = class end;'#10'  TStack<T> = class end;'#10'  TPair<K, V> = record end;'#10 +
    '  TObjectStack<T> = class end;'#10'const'#10'  Groesse = 4;'#10'implementation'#10'end.',
    Bds + 'common\System.Generics.Collections.pas', True);
  AddUnit('unit System.Generics.Defaults;'#10'interface'#10'type'#10'  IComparer<T> = interface end;'#10 +
    'implementation'#10'end.', Bds + 'common\System.Generics.Defaults.pas', True);
  AddUnit('unit Spring.Collections.Generic;'#10'interface'#10'implementation'#10'end.',
    'C:\Libs\Spring\Source\Spring.Collections.Generic.pas', True);
  FResolver := TNameResolver.Create(FIndex);
  FResolver.Namespaces := ['System', 'Vcl'];
end;

procedure TCompletionUsesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TCompletionUsesTests.ItemsAt(const AText, AMarker: string): TCompletionItems;
begin
  Result := ItemsAt(AText, AMarker, True);
end;

function TCompletionUsesTests.ItemsAt(const AText, AMarker: string; AUsesDetails: Boolean): TCompletionItems;
var
  Tree: TSyntaxTree;
  Request: TCompletionRequest;
  Settings: TCompletionSettings;
begin
  Tree := TPascalParser.Parse(AText);
  Request := TCompletionRequest.Create(AText, HauptFile, PositionOf(AText, AMarker));
  try
    Request.Tree := Tree;
    Request.Resolver := FResolver;
    Request.Index := FIndex;
    Settings := TCompletionSettings.Default;
    Settings.UsesDetails := AUsesDetails;
    Request.Settings := Settings;
    Result := TLspCompletion.Collect(Request, TPostfixOptions.Default, nil);
  finally
    Request.Free;
    Tree.Free;
  end;
end;

function TCompletionUsesTests.Names(const AItems: TCompletionItems): string;
var
  Item: TCompletionItem;
begin
  Result := '';
  for Item in AItems.Items do
    Result := Result + Item.Name + ' ';
  Result := Result.Trim;
end;

function TCompletionUsesTests.Find(const AItems: TCompletionItems; const AName: string;
  out AItem: TCompletionItem): Boolean;
var
  Item: TCompletionItem;
begin
  for Item in AItems.Items do
    if Item.Name = AName then
    begin
      AItem := Item;
      Exit(True);
    end;
  AItem := Default(TCompletionItem);
  Result := False;
end;

procedure TCompletionUsesTests.GenerShowsGenericsUnitsGroupedAndSkipsUsedUnit;
var
  Items: TCompletionItems;
begin
  // Abnahme: Projekt vor RTL vor Drittanbietern; System.SysUtils steht schon in der Liste.
  Items := ItemsAt(UnitHaupt, 'Gener');
  Assert.AreEqual('uGeneratorBeleg System.Generics.Defaults System.Generics.Collections Spring.Collections.Generic',
    Names(Items));
  Assert.AreEqual('project', Items.Items[0].UsesGroup);
  Assert.AreEqual('rtl', Items.Items[1].UsesGroup);
  Assert.AreEqual('library', Items.Items[3].UsesGroup);
  Assert.AreEqual(9, Items.Items[1].Kind);
end;

procedure TCompletionUsesTests.FooterNamesUsedUnits;
var
  Items: TCompletionItems;
begin
  // Nichts Eingebundenes passt zu "Gener": dann alle der Liste.
  Items := ItemsAt(UnitHaupt, 'Gener');
  Assert.AreEqual(1, Integer(Length(Items.Items[0].UsesHidden)));
  Assert.AreEqual('System.SysUtils', Items.Items[0].UsesHidden[0]);
  // Passt eines, nur dieses.
  Items := ItemsAt(StringReplace(UnitHaupt, 'Gener', 'Sys', []), ', Sys');
  Assert.AreEqual(1, Integer(Length(Items.Items[0].UsesHidden)));
  Assert.AreEqual('System.SysUtils', Items.Items[0].UsesHidden[0]);
  Assert.IsFalse((' ' + Names(Items) + ' ').Contains(' System.SysUtils '));
end;

procedure TCompletionUsesTests.ShortFormBecomesFullName;
var
  Text: string;
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Text := StringReplace(UnitHaupt, 'Gener', 'Classes', []);
  Items := ItemsAt(Text, 'Classes');
  Assert.IsTrue(Find(Items, 'System.Classes', Item));
  Assert.IsTrue(Item.HasTextEdit);
  Assert.AreEqual('System.Classes', Item.TextEdit.NewText);
  Assert.AreEqual(2, Item.TextEdit.Range.StartPos.Line);
  Assert.AreEqual(Length('uses System.SysUtils, '), Item.TextEdit.Range.StartPos.Character);
  Assert.AreEqual(Length('uses System.SysUtils, Classes'), Item.TextEdit.Range.EndPos.Character);
  Assert.AreEqual('Classes', Item.UsesFilter);
  // Mit Namespace getippt: ersetzt wird ab "System.".
  Text := StringReplace(UnitHaupt, 'Gener', 'System.Cla', []);
  Items := ItemsAt(Text, 'System.Cla');
  Assert.IsTrue(Find(Items, 'System.Classes', Item));
  Assert.AreEqual(Length('uses System.SysUtils, '), Item.TextEdit.Range.StartPos.Character);
  Assert.AreEqual('Classes', Item.UsesFilter);
end;

procedure TCompletionUsesTests.UnitOfOtherSectionCarriesHint;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt(UnitHaupt, 'Gener');
  Assert.IsTrue(Find(Items, 'System.Generics.Defaults', Item));
  Assert.AreEqual('implementation', Item.UsesElsewhere);
  Assert.IsTrue(Find(Items, 'System.Generics.Collections', Item));
  Assert.AreEqual('', Item.UsesElsewhere);
end;

procedure TCompletionUsesTests.CircularReferenceInInterfaceOnly;
var
  Text: string;
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Text := StringReplace(UnitHaupt, 'Gener', 'u', []);
  Items := ItemsAt(Text, ', u');
  Assert.IsTrue(Find(Items, 'uGeneratorBeleg', Item));
  Assert.AreEqual('uGeneratorBeleg → Haupt', Item.UsesCycle);
  Assert.IsTrue(Find(Items, 'uMitte', Item));
  Assert.AreEqual('uMitte → uZwei → Haupt', Item.UsesCycle);
  // Im implementation-Teil ist ein Zirkelbezug erlaubt.
  Text := StringReplace(UnitHaupt, 'uses System.Generics.Defaults;', 'uses System.Generics.Defaults, uG', []);
  Items := ItemsAt(Text, ', uG');
  Assert.IsTrue(Find(Items, 'uGeneratorBeleg', Item));
  Assert.AreEqual('', Item.UsesCycle);
  Assert.AreEqual('', Item.UsesElsewhere);
end;

procedure TCompletionUsesTests.DetailsCarryPathAndTypes;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt(UnitHaupt, 'Gener');
  Assert.IsTrue(Find(Items, 'System.Generics.Collections', Item));
  Assert.AreEqual('$(BDS)\source\rtl\common\System.Generics.Collections.pas', Item.Detail);
  Assert.AreEqual('TList<T> TObjectList<T> TDictionary<K,V> TQueue<T> TStack<T> TPair<K,V>',
    string.Join(' ', Item.UsesTypes));
  Assert.AreEqual(7, Item.UsesTypeCount);
  Assert.IsTrue(Find(Items, 'Spring.Collections.Generic', Item));
  Assert.AreEqual('C:\Libs\Spring\Source\Spring.Collections.Generic.pas', Item.Detail);
end;

procedure TCompletionUsesTests.SwitchOffListsAllUnits;
var
  Items: TCompletionItems;
begin
  // Aus: schlichte Liste wie vor #469, auch mit der schon eingebundenen Unit und ohne Gruppen.
  Items := ItemsAt(StringReplace(UnitHaupt, 'Gener', 'System.Sys', []), 'System.Sys', False);
  Assert.AreEqual('System.SysUtils', Names(Items));
  Assert.AreEqual('', Items.Items[0].UsesGroup);
end;

procedure TCompletionUsesTests.WritesUsesDataToJson;
var
  Items: TCompletionItems;
  Json: TJSONArray;
  Data: TJSONObject;
begin
  Items := ItemsAt(UnitHaupt, 'Gener');
  Json := CompletionItemsToJson(Copy(Items.Items, 1, 1), 0);
  try
    Data := (Json.Items[0] as TJSONObject).GetValue('data') as TJSONObject;
    Assert.AreEqual('rtl', Data.GetValue<string>('usesGroup'));
    Assert.AreEqual('Generics.Defaults', Data.GetValue<string>('usesFilter'));
    Assert.AreEqual('implementation', Data.GetValue<string>('usesElsewhere'));
    Assert.AreEqual('["IComparer<T>"]', Data.GetValue('usesTypes').ToJSON);
    Assert.AreEqual('["System.SysUtils"]', Data.GetValue('usesHidden').ToJSON);
    Assert.IsNotNull((Json.Items[0] as TJSONObject).GetValue('textEdit'));
  finally
    Json.Free;
  end;
end;

procedure TCompletionUsesTests.MatchesFromLaterNamePart;
var
  Found, Full: TUsesMatch;
begin
  Assert.IsTrue(TCompletionUses.Match('System.Generics.Collections', 'Gener', ['System'],
    TCompletionMatching.Prefix, Found));
  Assert.AreEqual('Generics.Collections', Found.Filter);
  Assert.IsTrue(TCompletionUses.Match('System.Generics.Collections', 'System.Gen', ['System'],
    TCompletionMatching.Prefix, Full));
  Assert.AreEqual('Generics.Collections', Full.Filter);
  // Voller Name vor Namespace-Kurzform vor sonstigem Namensteil.
  Assert.IsTrue(Full.Score > Found.Score);
  Assert.IsTrue(TCompletionUses.Match('Spring.Collections.Generic', 'Gener', ['System'],
    TCompletionMatching.Prefix, Full));
  Assert.IsTrue(Found.Score > Full.Score);
  Assert.IsFalse(TCompletionUses.Match('System.Classes', 'Gener', ['System'], TCompletionMatching.Prefix, Found));
end;

procedure TCompletionUsesTests.GroupsAndShortPaths;
var
  UnitInfo: TUnitIndex;
begin
  UnitInfo := Default(TUnitIndex);
  UnitInfo.UnitName := 'Vcl.Forms';
  UnitInfo.FileName := 'D:\Quellen\Vcl.Forms.pas';
  Assert.IsTrue(TCompletionUses.GroupOf(UnitInfo) = TUsesGroup.Project);
  UnitInfo.Library_ := True;
  Assert.IsTrue(TCompletionUses.GroupOf(UnitInfo) = TUsesGroup.Rtl);
  UnitInfo.UnitName := 'IdHTTP';
  UnitInfo.FileName := 'C:\Program Files\Embarcadero\Studio\23.0\source\Indy10\Protocols\IdHTTP.pas';
  Assert.IsTrue(TCompletionUses.GroupOf(UnitInfo) = TUsesGroup.Rtl);
  UnitInfo.FileName := 'C:\Komponenten\Indy\IdHTTP.pas';
  Assert.IsTrue(TCompletionUses.GroupOf(UnitInfo) = TUsesGroup.Library_);
  Assert.AreEqual('$(BDS)\source\Indy10\Protocols\IdHTTP.pas',
    TCompletionUses.ShortPath('C:\Program Files\Embarcadero\Studio\23.0\source\Indy10\Protocols\IdHTTP.pas'));
  Assert.AreEqual('C:\Komponenten\Indy\IdHTTP.pas', TCompletionUses.ShortPath('C:\Komponenten\Indy\IdHTTP.pas'));
end;

procedure TCompletionUsesTests.SiteReadsIncompleteListAndOtherSection;
var
  Tree: TSyntaxTree;
  Site: TUsesSite;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Site := TCompletionUses.SiteAt(Tree.Tokens, PositionOf(UnitHaupt, 'Gener'));
    Assert.IsTrue(Site.Section = TUsesSection.Interface_);
    Assert.AreEqual('System.SysUtils', string.Join(',', Site.Here));
    Assert.AreEqual('System.Generics.Defaults', string.Join(',', Site.Other));
    Site := TCompletionUses.SiteAt(Tree.Tokens, PositionOf(UnitHaupt, 'uses System.Gen'));
    Assert.IsTrue(Site.Section = TUsesSection.Implementation_);
    Assert.AreEqual('', string.Join(',', Site.Here));
    Assert.AreEqual('System.SysUtils,Gener', string.Join(',', Site.Other));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionUsesTests);

end.
