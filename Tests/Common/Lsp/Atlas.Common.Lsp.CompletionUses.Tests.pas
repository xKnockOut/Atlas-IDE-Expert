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
  Atlas.Common.Lsp.Completion.Lists,
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
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
  cHauptFile = 'C:\P\Haupt.pas';
  cBds = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\source\rtl\';

  cUnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses System.SysUtils, Gener'#10 +
    'implementation'#10 +
    'uses System.Generics.Defaults;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  mIndex, mLine, mLineStart, mScan: Integer;
begin
  // Cursor hinter AMarker.
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  Inc(mIndex, Length(AMarker));
  mLine := 0;
  mLineStart := 1;
  for mScan := 1 to mIndex - 1 do
  begin
    if AText[mScan] = #10 then
    begin
      Inc(mLine);
      mLineStart := mScan + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

{ TCompletionUsesTests }

procedure TCompletionUsesTests.AddUnit(const AText, AFileName: string; ALibrary: Boolean);
var
  mUnitInfo: TUnitIndex;
begin
  mUnitInfo := TIndexExtractor.ExtractText(AText, AFileName, nil);
  mUnitInfo.Library_ := ALibrary;
  FIndex.AddUnit(mUnitInfo);
end;

procedure TCompletionUsesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  AddUnit('unit uGeneratorBeleg;'#10'interface'#10'uses Haupt;'#10'implementation'#10'end.',
    'C:\P\uGeneratorBeleg.pas', False);
  AddUnit('unit uMitte;'#10'interface'#10'uses uZwei;'#10'implementation'#10'end.', 'C:\P\uMitte.pas', False);
  AddUnit('unit uZwei;'#10'interface'#10'uses Haupt;'#10'implementation'#10'end.', 'C:\P\uZwei.pas', False);
  AddUnit('unit System.SysUtils;'#10'interface'#10'type'#10'  Exception = class end;'#10'implementation'#10'end.',
    cBds + 'sys\System.SysUtils.pas', True);
  AddUnit('unit System.Classes;'#10'interface'#10'type'#10'  TStrings = class end;'#10'implementation'#10'end.',
    cBds + 'common\System.Classes.pas', True);
  AddUnit('unit System.Generics.Collections;'#10'interface'#10'type'#10 +
    '  TList<T> = class end;'#10'  TObjectList<T: class> = class end;'#10'  TDictionary<K, V> = class end;'#10 +
    '  TQueue<T> = class end;'#10'  TStack<T> = class end;'#10'  TPair<K, V> = record end;'#10 +
    '  TObjectStack<T> = class end;'#10'const'#10'  Groesse = 4;'#10'implementation'#10'end.',
    cBds + 'common\System.Generics.Collections.pas', True);
  AddUnit('unit System.Generics.Defaults;'#10'interface'#10'type'#10'  IComparer<T> = interface end;'#10 +
    'implementation'#10'end.', cBds + 'common\System.Generics.Defaults.pas', True);
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
  mTree: TSyntaxTree;
  mRequest: TCompletionRequest;
  mSettings: TCompletionSettings;
begin
  mTree := TPascalParser.Parse(AText);
  mRequest := TCompletionRequest.Create(AText, cHauptFile, PositionOf(AText, AMarker));
  try
    mRequest.Tree := mTree;
    mRequest.Resolver := FResolver;
    mRequest.Index := FIndex;
    mSettings := TCompletionSettings.Default;
    mSettings.UsesDetails := AUsesDetails;
    mRequest.Settings := mSettings;
    Result := TCompletionLists.Collect(mRequest, TPostfixOptions.Default, nil);
  finally
    mRequest.Free;
    mTree.Free;
  end;
end;

function TCompletionUsesTests.Names(const AItems: TCompletionItems): string;
var
  mItem: TCompletionItem;
begin
  Result := '';
  for mItem in AItems.Items do
  begin
    Result := Result + mItem.Name + ' ';
  end;
  Result := Result.Trim;
end;

function TCompletionUsesTests.Find(const AItems: TCompletionItems; const AName: string;
  out AItem: TCompletionItem): Boolean;
var
  mItem: TCompletionItem;
begin
  for mItem in AItems.Items do
  begin
    if mItem.Name = AName then
    begin
      AItem := mItem;
      Exit(True);
    end;
  end;
  AItem := Default(TCompletionItem);
  Result := False;
end;

procedure TCompletionUsesTests.GenerShowsGenericsUnitsGroupedAndSkipsUsedUnit;
var
  mItems: TCompletionItems;
begin
  // Abnahme: Projekt vor RTL vor Drittanbietern; System.SysUtils steht schon in der Liste.
  mItems := ItemsAt(cUnitHaupt, 'Gener');
  Assert.AreEqual('uGeneratorBeleg System.Generics.Defaults System.Generics.Collections Spring.Collections.Generic',
    Names(mItems));
  Assert.AreEqual('project', mItems.Items[0].UsesGroup);
  Assert.AreEqual('rtl', mItems.Items[1].UsesGroup);
  Assert.AreEqual('library', mItems.Items[3].UsesGroup);
  Assert.AreEqual(9, mItems.Items[1].Kind);
end;

procedure TCompletionUsesTests.FooterNamesUsedUnits;
var
  mItems: TCompletionItems;
begin
  // Nichts Eingebundenes passt zu "Gener": dann alle der Liste.
  mItems := ItemsAt(cUnitHaupt, 'Gener');
  Assert.AreEqual(1, Integer(Length(mItems.Items[0].UsesHidden)));
  Assert.AreEqual('System.SysUtils', mItems.Items[0].UsesHidden[0]);
  // Passt eines, nur dieses.
  mItems := ItemsAt(StringReplace(cUnitHaupt, 'Gener', 'Sys', []), ', Sys');
  Assert.AreEqual(1, Integer(Length(mItems.Items[0].UsesHidden)));
  Assert.AreEqual('System.SysUtils', mItems.Items[0].UsesHidden[0]);
  Assert.IsFalse((' ' + Names(mItems) + ' ').Contains(' System.SysUtils '));
end;

procedure TCompletionUsesTests.ShortFormBecomesFullName;
var
  mText: string;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mText := StringReplace(cUnitHaupt, 'Gener', 'Classes', []);
  mItems := ItemsAt(mText, 'Classes');
  Assert.IsTrue(Find(mItems, 'System.Classes', mItem));
  Assert.IsTrue(mItem.HasTextEdit);
  Assert.AreEqual('System.Classes', mItem.TextEdit.NewText);
  Assert.AreEqual(2, mItem.TextEdit.Range.StartPos.Line);
  Assert.AreEqual(Length('uses System.SysUtils, '), mItem.TextEdit.Range.StartPos.Character);
  Assert.AreEqual(Length('uses System.SysUtils, Classes'), mItem.TextEdit.Range.EndPos.Character);
  Assert.AreEqual('Classes', mItem.UsesFilter);
  // Mit Namespace getippt: ersetzt wird ab "System.".
  mText := StringReplace(cUnitHaupt, 'Gener', 'System.Cla', []);
  mItems := ItemsAt(mText, 'System.Cla');
  Assert.IsTrue(Find(mItems, 'System.Classes', mItem));
  Assert.AreEqual(Length('uses System.SysUtils, '), mItem.TextEdit.Range.StartPos.Character);
  Assert.AreEqual('Classes', mItem.UsesFilter);
end;

procedure TCompletionUsesTests.UnitOfOtherSectionCarriesHint;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt(cUnitHaupt, 'Gener');
  Assert.IsTrue(Find(mItems, 'System.Generics.Defaults', mItem));
  Assert.AreEqual('implementation', mItem.UsesElsewhere);
  Assert.IsTrue(Find(mItems, 'System.Generics.Collections', mItem));
  Assert.AreEqual('', mItem.UsesElsewhere);
end;

procedure TCompletionUsesTests.CircularReferenceInInterfaceOnly;
var
  mText: string;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mText := StringReplace(cUnitHaupt, 'Gener', 'u', []);
  mItems := ItemsAt(mText, ', u');
  Assert.IsTrue(Find(mItems, 'uGeneratorBeleg', mItem));
  Assert.AreEqual('uGeneratorBeleg → Haupt', mItem.UsesCycle);
  Assert.IsTrue(Find(mItems, 'uMitte', mItem));
  Assert.AreEqual('uMitte → uZwei → Haupt', mItem.UsesCycle);
  // Im implementation-Teil ist ein Zirkelbezug erlaubt.
  mText := StringReplace(cUnitHaupt, 'uses System.Generics.Defaults;', 'uses System.Generics.Defaults, uG', []);
  mItems := ItemsAt(mText, ', uG');
  Assert.IsTrue(Find(mItems, 'uGeneratorBeleg', mItem));
  Assert.AreEqual('', mItem.UsesCycle);
  Assert.AreEqual('', mItem.UsesElsewhere);
end;

procedure TCompletionUsesTests.DetailsCarryPathAndTypes;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt(cUnitHaupt, 'Gener');
  Assert.IsTrue(Find(mItems, 'System.Generics.Collections', mItem));
  Assert.AreEqual('$(BDS)\source\rtl\common\System.Generics.Collections.pas', mItem.Detail);
  Assert.AreEqual('TList<T> TObjectList<T> TDictionary<K,V> TQueue<T> TStack<T> TPair<K,V>',
    string.Join(' ', mItem.UsesTypes));
  Assert.AreEqual(7, mItem.UsesTypeCount);
  Assert.IsTrue(Find(mItems, 'Spring.Collections.Generic', mItem));
  Assert.AreEqual('C:\Libs\Spring\Source\Spring.Collections.Generic.pas', mItem.Detail);
end;

procedure TCompletionUsesTests.SwitchOffListsAllUnits;
var
  mItems: TCompletionItems;
begin
  // Aus: schlichte Liste wie vor #469, auch mit der schon eingebundenen Unit und ohne Gruppen.
  mItems := ItemsAt(StringReplace(cUnitHaupt, 'Gener', 'System.Sys', []), 'System.Sys', False);
  Assert.AreEqual('System.SysUtils', Names(mItems));
  Assert.AreEqual('', mItems.Items[0].UsesGroup);
end;

procedure TCompletionUsesTests.WritesUsesDataToJson;
var
  mItems: TCompletionItems;
  mJson: TJSONArray;
  mData: TJSONObject;
begin
  mItems := ItemsAt(cUnitHaupt, 'Gener');
  mJson := CompletionItemsToJson(Copy(mItems.Items, 1, 1), 0);
  try
    mData := (mJson.Items[0] as TJSONObject).GetValue('data') as TJSONObject;
    Assert.AreEqual('rtl', mData.GetValue<string>('usesGroup'));
    Assert.AreEqual('Generics.Defaults', mData.GetValue<string>('usesFilter'));
    Assert.AreEqual('implementation', mData.GetValue<string>('usesElsewhere'));
    Assert.AreEqual('["IComparer<T>"]', mData.GetValue('usesTypes').ToJSON);
    Assert.AreEqual('["System.SysUtils"]', mData.GetValue('usesHidden').ToJSON);
    Assert.IsNotNull((mJson.Items[0] as TJSONObject).GetValue('textEdit'));
  finally
    mJson.Free;
  end;
end;

procedure TCompletionUsesTests.MatchesFromLaterNamePart;
var
  mFound, mFull: TUsesMatch;
begin
  Assert.IsTrue(TCompletionUses.Match('System.Generics.Collections', 'Gener', ['System'],
    TCompletionMatching.Prefix, mFound));
  Assert.AreEqual('Generics.Collections', mFound.Filter);
  Assert.IsTrue(TCompletionUses.Match('System.Generics.Collections', 'System.Gen', ['System'],
    TCompletionMatching.Prefix, mFull));
  Assert.AreEqual('Generics.Collections', mFull.Filter);
  // Voller Name vor Namespace-Kurzform vor sonstigem Namensteil.
  Assert.IsTrue(mFull.Score > mFound.Score);
  Assert.IsTrue(TCompletionUses.Match('Spring.Collections.Generic', 'Gener', ['System'],
    TCompletionMatching.Prefix, mFull));
  Assert.IsTrue(mFound.Score > mFull.Score);
  Assert.IsFalse(TCompletionUses.Match('System.Classes', 'Gener', ['System'], TCompletionMatching.Prefix, mFound));
end;

procedure TCompletionUsesTests.GroupsAndShortPaths;
var
  mUnitInfo: TUnitIndex;
begin
  mUnitInfo := Default(TUnitIndex);
  mUnitInfo.UnitName := 'Vcl.Forms';
  mUnitInfo.FileName := 'D:\Quellen\Vcl.Forms.pas';
  Assert.AreEqual<TUsesGroup>(TUsesGroup.Project, TCompletionUses.GroupOf(mUnitInfo));
  mUnitInfo.Library_ := True;
  Assert.AreEqual<TUsesGroup>(TUsesGroup.Rtl, TCompletionUses.GroupOf(mUnitInfo));
  mUnitInfo.UnitName := 'IdHTTP';
  mUnitInfo.FileName := 'C:\Program Files\Embarcadero\Studio\23.0\source\Indy10\Protocols\IdHTTP.pas';
  Assert.AreEqual<TUsesGroup>(TUsesGroup.Rtl, TCompletionUses.GroupOf(mUnitInfo));
  mUnitInfo.FileName := 'C:\Komponenten\Indy\IdHTTP.pas';
  Assert.AreEqual<TUsesGroup>(TUsesGroup.Library_, TCompletionUses.GroupOf(mUnitInfo));
  Assert.AreEqual('$(BDS)\source\Indy10\Protocols\IdHTTP.pas',
    TCompletionUses.ShortPath('C:\Program Files\Embarcadero\Studio\23.0\source\Indy10\Protocols\IdHTTP.pas'));
  Assert.AreEqual('C:\Komponenten\Indy\IdHTTP.pas', TCompletionUses.ShortPath('C:\Komponenten\Indy\IdHTTP.pas'));
end;

procedure TCompletionUsesTests.SiteReadsIncompleteListAndOtherSection;
var
  mTree: TSyntaxTree;
  mSite: TUsesSite;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    mSite := TCompletionUses.SiteAt(mTree.Tokens, PositionOf(cUnitHaupt, 'Gener'));
    Assert.AreEqual<TUsesSection>(TUsesSection.Interface_, mSite.Section);
    Assert.AreEqual('System.SysUtils', string.Join(',', mSite.Here));
    Assert.AreEqual('System.Generics.Defaults', string.Join(',', mSite.Other));
    mSite := TCompletionUses.SiteAt(mTree.Tokens, PositionOf(cUnitHaupt, 'uses System.Gen'));
    Assert.AreEqual<TUsesSection>(TUsesSection.Implementation_, mSite.Section);
    Assert.AreEqual('', string.Join(',', mSite.Here));
    Assert.AreEqual('System.SysUtils,Gener', string.Join(',', mSite.Other));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionUsesTests);

end.
