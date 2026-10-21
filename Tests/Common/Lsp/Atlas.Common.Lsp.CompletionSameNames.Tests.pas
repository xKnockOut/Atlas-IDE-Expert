unit Atlas.Common.Lsp.CompletionSameNames.Tests;

// Gleiche Namen aus verschiedenen Units (#475): Übernahmeart, Verschieben in den uses, Varianten in der
// Vervollständigung, FMX ausgeblendet, Schalter.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TCompletionSameNamesTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure InsertModeFollowsSettingAndUses;
    [Test]
    procedure MoveToEndInSameList;
    [Test]
    procedure VariantsFollowTheActiveOne;
    [Test]
    procedure UsesModeMovesTheUnit;
    [Test]
    procedure FmxAppearsOnlyWhenSwitchedOn;
    [Test]
    procedure SwitchedOffShowsOnlyTheActive;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.CompletionSameNames,
  Atlas.Common.Lsp.Completion;

const
  HauptFile = 'C:\P\Haupt.pas';

  UnitWindows =
    'unit Winapi.Windows;'#10'interface'#10'type'#10'  tagBITMAP = record'#10'    bmType: Integer;'#10'  end;'#10 +
    '  TBitmap = tagBITMAP;'#10'implementation'#10'end.';
  UnitGraphics =
    'unit Vcl.Graphics;'#10'interface'#10'type'#10'  TBitmap = class'#10'  end;'#10 +
    '  TBitmapImage = class'#10'  end;'#10'implementation'#10'end.';
  UnitFmx =
    'unit FMX.Graphics;'#10'interface'#10'type'#10'  TBitmap = class'#10'  end;'#10'implementation'#10'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Winapi.Windows, Vcl.Graphics;'#10 +
    'implementation'#10 +
    'procedure Zeige;'#10 +
    'var'#10 +
    '  Bild: TObject;'#10 +
    'begin'#10 +
    '  Bild := TBitm'#10 +
    'end;'#10 +
    'end.';

function ItemsAt(const AIndex: ISymbolIndex; const AText, AMarker: string;
  const ASettings: TCompletionSettings): TCompletionItems;
var
  Resolver: TNameResolver;
  Request: TCompletionRequest;
  Tree: TSyntaxTree;
  Lines: TArray<string>;
  Line: Integer;
  Position: TTextPosition;
  Postfix: TPostfixOptions;
begin
  Lines := AText.Split([#10]);
  Position := TTextPosition.Create(0, 0);
  for Line := 0 to High(Lines) do
    if Pos(AMarker, Lines[Line]) > 0 then
      Position := TTextPosition.Create(Line, Pos(AMarker, Lines[Line]) - 1 + Length(AMarker));
  Tree := TPascalParser.Parse(AText);
  Resolver := TNameResolver.Create(AIndex);
  Request := TCompletionRequest.Create(AText, HauptFile, Position);
  try
    Request.Tree := Tree;
    Request.Resolver := Resolver;
    Request.Index := AIndex;
    Request.Matching := TCompletionMatching.Prefix;
    Request.Settings := ASettings;
    Postfix := Default(TPostfixOptions);
    Result := TLspCompletion.Collect(Request, Postfix, nil);
  finally
    Request.Free;
    Resolver.Free;
    Tree.Free;
  end;
end;

function Find(const AItems: TCompletionItems; const AName, AUnit: string; out AItem: TCompletionItem): Boolean;
var
  Item: TCompletionItem;
begin
  for Item in AItems.Items do
    if SameText(Item.Name, AName) and SameText(Item.UnitName, AUnit) then
    begin
      AItem := Item;
      Exit(True);
    end;
  AItem := Default(TCompletionItem);
  Result := False;
end;

function Order(const AItems: TCompletionItems): string;
var
  Item: TCompletionItem;
begin
  Result := '';
  for Item in AItems.Items do
    Result := Result + Item.Name + '@' + Item.UnitName + ' ';
  Result := Result.Trim;
end;

{ TCompletionSameNamesTests }

procedure TCompletionSameNamesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWindows, 'C:\RTL\Winapi.Windows.pas', nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitGraphics, 'C:\RTL\Vcl.Graphics.pas', nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitFmx, 'C:\RTL\FMX.Graphics.pas', nil));
end;

procedure TCompletionSameNamesTests.TearDown;
begin
  FIndex := nil;
end;

procedure TCompletionSameNamesTests.InsertModeFollowsSettingAndUses;
begin
  Assert.AreEqual('prefix', TCompletionSameNames.InsertMode(TCompletionSameNameInsert.Prefix, True, True));
  Assert.AreEqual('prefixAdd', TCompletionSameNames.InsertMode(TCompletionSameNameInsert.Prefix, False, False));
  Assert.AreEqual('move', TCompletionSameNames.InsertMode(TCompletionSameNameInsert.Uses_, True, True));
  // Nicht verschiebbar (andere Liste): Präfix.
  Assert.AreEqual('prefix', TCompletionSameNames.InsertMode(TCompletionSameNameInsert.Uses_, True, False));
  Assert.AreEqual('add', TCompletionSameNames.InsertMode(TCompletionSameNameInsert.Uses_, False, False));
  Assert.IsTrue(TCompletionSameNames.IsFmx('FMX.Graphics'));
  Assert.IsFalse(TCompletionSameNames.IsFmx('FMXTools'));
end;

procedure TCompletionSameNamesTests.MoveToEndInSameList;
const
  Text = 'unit Haupt;'#10'interface'#10'uses Winapi.Windows, Vcl.Graphics, System.Classes;'#10 +
    'implementation'#10'uses Vcl.Forms;'#10'end.';
var
  Edits: TArray<TTextEdit>;
  Tokens: TArray<TPascalToken>;
begin
  Tokens := TPascalLexer.Tokenize(Text);
  Assert.IsTrue(TCompletionSameNames.MoveToEnd(Tokens, 'Winapi.Windows', 'Vcl.Graphics', nil, Edits));
  Assert.AreEqual(2, Integer(Length(Edits)));
  // Erster Eintrag: samt Komma bis vor den nächsten Namen.
  Assert.AreEqual(2, Edits[0].Range.StartPos.Line);
  Assert.AreEqual(5, Edits[0].Range.StartPos.Character);
  Assert.AreEqual(21, Edits[0].Range.EndPos.Character);
  Assert.AreEqual('', Edits[0].NewText);
  Assert.AreEqual(', Winapi.Windows', Edits[1].NewText);
  // Steht schon hinter der aktiven bzw. in einer anderen Liste: nichts.
  Assert.IsFalse(TCompletionSameNames.MoveToEnd(Tokens, 'Vcl.Graphics', 'Winapi.Windows', nil, Edits));
  Assert.IsFalse(TCompletionSameNames.MoveToEnd(Tokens, 'Vcl.Forms', 'Vcl.Graphics', nil, Edits));
  // Kurzform über die Namespaces.
  Tokens := TPascalLexer.Tokenize('unit Haupt;'#10'interface'#10'uses Windows, Graphics;'#10'implementation'#10'end.');
  Assert.IsTrue(TCompletionSameNames.MoveToEnd(Tokens, 'Winapi.Windows', 'Vcl.Graphics', ['Winapi', 'Vcl'], Edits));
  Assert.AreEqual(', Windows', Edits[1].NewText);
end;

procedure TCompletionSameNamesTests.VariantsFollowTheActiveOne;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt(FIndex, UnitHaupt, 'TBitm', TCompletionSettings.Default);
  Assert.AreEqual('TBitmap@Vcl.Graphics TBitmap@Winapi.Windows TBitmapImage@Vcl.Graphics', Order(Items));
  Assert.IsTrue(Find(Items, 'TBitmap', 'Vcl.Graphics', Item));
  Assert.IsTrue(Item.SameNameActive);
  Assert.AreEqual('Vcl.Graphics,Winapi.Windows', string.Join(',', Item.SameNameUnits));
  Assert.AreEqual('FMX.Graphics.TBitmap', string.Join(',', Item.SameNameHidden));
  Assert.IsTrue(Find(Items, 'TBitmap', 'Winapi.Windows', Item));
  Assert.IsFalse(Item.SameNameActive);
  Assert.AreEqual('Vcl.Graphics', Item.SameNameOf);
  Assert.AreEqual('prefix', Item.SameNameInsert);
  Assert.IsTrue(Item.HasTextEdit);
  Assert.AreEqual('Winapi.Windows.TBitmap', Item.TextEdit.NewText);
  Assert.AreEqual(10, Item.TextEdit.Range.StartPos.Character);
  Assert.AreEqual(0, Integer(Length(Item.AdditionalEdits)));
end;

procedure TCompletionSameNamesTests.UsesModeMovesTheUnit;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
  Settings: TCompletionSettings;
begin
  Settings := TCompletionSettings.Default;
  Settings.SameNameInsert := TCompletionSameNameInsert.Uses_;
  Items := ItemsAt(FIndex, UnitHaupt, 'TBitm', Settings);
  Assert.IsTrue(Find(Items, 'TBitmap', 'Winapi.Windows', Item));
  Assert.AreEqual('move', Item.SameNameInsert);
  Assert.IsFalse(Item.HasTextEdit);
  Assert.AreEqual(2, Integer(Length(Item.AdditionalEdits)));
  Assert.AreEqual(', Winapi.Windows', Item.AdditionalEdits[1].NewText);
end;

procedure TCompletionSameNamesTests.FmxAppearsOnlyWhenSwitchedOn;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
  Settings: TCompletionSettings;
begin
  Assert.IsFalse(Find(ItemsAt(FIndex, UnitHaupt, 'TBitm', TCompletionSettings.Default), 'TBitmap', 'FMX.Graphics',
    Item));
  Settings := TCompletionSettings.Default;
  Settings.ShowFmxUnits := True;
  Items := ItemsAt(FIndex, UnitHaupt, 'TBitm', Settings);
  Assert.IsTrue(Find(Items, 'TBitmap', 'FMX.Graphics', Item));
  // Nicht eingebunden: Präfix und uses-Eintrag.
  Assert.AreEqual('prefixAdd', Item.SameNameInsert);
  Assert.AreEqual('FMX.Graphics.TBitmap', Item.TextEdit.NewText);
  Assert.AreEqual(1, Integer(Length(Item.AdditionalEdits)));
  Assert.IsTrue(Item.AdditionalEdits[0].NewText.Contains('FMX.Graphics'), Item.AdditionalEdits[0].NewText);
end;

procedure TCompletionSameNamesTests.SwitchedOffShowsOnlyTheActive;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
  Settings: TCompletionSettings;
begin
  Settings := TCompletionSettings.Default;
  Settings.SameNameVariants := False;
  Items := ItemsAt(FIndex, UnitHaupt, 'TBitm', Settings);
  Assert.AreEqual('TBitmap@Vcl.Graphics TBitmapImage@Vcl.Graphics', Order(Items));
  Assert.IsTrue(Find(Items, 'TBitmap', 'Vcl.Graphics', Item));
  Assert.IsFalse(Item.SameNameActive);
  Assert.AreEqual(0, Integer(Length(Item.SameNameUnits)));
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionSameNamesTests);

end.
