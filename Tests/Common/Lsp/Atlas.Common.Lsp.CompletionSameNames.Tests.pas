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
  Atlas.Common.Lsp.Completion.Lists,
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
  Atlas.Common.Lsp.CompletionSameNames,
  Atlas.Common.Lsp.Completion;

const
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitWindows =
    'unit Winapi.Windows;'#10'interface'#10'type'#10'  tagBITMAP = record'#10'    bmType: Integer;'#10'  end;'#10 +
    '  TBitmap = tagBITMAP;'#10'implementation'#10'end.';
  cUnitGraphics =
    'unit Vcl.Graphics;'#10'interface'#10'type'#10'  TBitmap = class'#10'  end;'#10 +
    '  TBitmapImage = class'#10'  end;'#10'implementation'#10'end.';
  cUnitFmx =
    'unit FMX.Graphics;'#10'interface'#10'type'#10'  TBitmap = class'#10'  end;'#10'implementation'#10'end.';

  cUnitHaupt =
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
  mResolver: TNameResolver;
  mRequest: TCompletionRequest;
  mTree: TSyntaxTree;
  mLines: TArray<string>;
  mLine: Integer;
  mPosition: TTextPosition;
  mPostfix: TPostfixOptions;
begin
  mLines := AText.Split([#10]);
  mPosition := TTextPosition.Create(0, 0);
  for mLine := 0 to High(mLines) do
  begin
    if Pos(AMarker, mLines[mLine]) > 0 then
    begin
      mPosition := TTextPosition.Create(mLine, Pos(AMarker, mLines[mLine]) - 1 + Length(AMarker));
    end;
  end;
  mTree := TPascalParser.Parse(AText);
  mResolver := TNameResolver.Create(AIndex);
  mRequest := TCompletionRequest.Create(AText, cHauptFile, mPosition);
  try
    mRequest.Tree := mTree;
    mRequest.Resolver := mResolver;
    mRequest.Index := AIndex;
    mRequest.Matching := TCompletionMatching.Prefix;
    mRequest.Settings := ASettings;
    mPostfix := Default(TPostfixOptions);
    Result := TCompletionLists.Collect(mRequest, mPostfix, nil);
  finally
    mRequest.Free;
    mResolver.Free;
    mTree.Free;
  end;
end;

function Find(const AItems: TCompletionItems; const AName, AUnit: string; out AItem: TCompletionItem): Boolean;
var
  mItem: TCompletionItem;
begin
  for mItem in AItems.Items do
  begin
    if SameText(mItem.Name, AName) and SameText(mItem.UnitName, AUnit) then
    begin
      AItem := mItem;
      Exit(True);
    end;
  end;
  AItem := Default(TCompletionItem);
  Result := False;
end;

function Order(const AItems: TCompletionItems): string;
var
  mItem: TCompletionItem;
begin
  Result := '';
  for mItem in AItems.Items do
  begin
    Result := Result + mItem.Name + '@' + mItem.UnitName + ' ';
  end;
  Result := Result.Trim;
end;

{ TCompletionSameNamesTests }

procedure TCompletionSameNamesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitWindows, 'C:\RTL\Winapi.Windows.pas', nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitGraphics, 'C:\RTL\Vcl.Graphics.pas', nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitFmx, 'C:\RTL\FMX.Graphics.pas', nil));
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
  cText = 'unit Haupt;'#10'interface'#10'uses Winapi.Windows, Vcl.Graphics, System.Classes;'#10 +
    'implementation'#10'uses Vcl.Forms;'#10'end.';
var
  mEdits: TArray<TTextEdit>;
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize(cText);
  Assert.IsTrue(TCompletionSameNames.MoveToEnd(mTokens, 'Winapi.Windows', 'Vcl.Graphics', nil, mEdits));
  Assert.AreEqual(2, Integer(Length(mEdits)));
  // Erster Eintrag: samt Komma bis vor den nächsten Namen.
  Assert.AreEqual(2, mEdits[0].Range.StartPos.Line);
  Assert.AreEqual(5, mEdits[0].Range.StartPos.Character);
  Assert.AreEqual(21, mEdits[0].Range.EndPos.Character);
  Assert.AreEqual('', mEdits[0].NewText);
  Assert.AreEqual(', Winapi.Windows', mEdits[1].NewText);
  // Steht schon hinter der aktiven bzw. in einer anderen Liste: nichts.
  Assert.IsFalse(TCompletionSameNames.MoveToEnd(mTokens, 'Vcl.Graphics', 'Winapi.Windows', nil, mEdits));
  Assert.IsFalse(TCompletionSameNames.MoveToEnd(mTokens, 'Vcl.Forms', 'Vcl.Graphics', nil, mEdits));
  // Kurzform über die Namespaces.
  mTokens := TPascalLexer.Tokenize('unit Haupt;'#10'interface'#10'uses Windows, Graphics;'#10'implementation'#10'end.');
  Assert.IsTrue(TCompletionSameNames.MoveToEnd(mTokens, 'Winapi.Windows', 'Vcl.Graphics', ['Winapi', 'Vcl'], mEdits));
  Assert.AreEqual(', Windows', mEdits[1].NewText);
end;

procedure TCompletionSameNamesTests.VariantsFollowTheActiveOne;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt(FIndex, cUnitHaupt, 'TBitm', TCompletionSettings.Default);
  Assert.AreEqual('TBitmap@Vcl.Graphics TBitmap@Winapi.Windows TBitmapImage@Vcl.Graphics', Order(mItems));
  Assert.IsTrue(Find(mItems, 'TBitmap', 'Vcl.Graphics', mItem));
  Assert.IsTrue(mItem.SameNameActive);
  Assert.AreEqual('Vcl.Graphics,Winapi.Windows', string.Join(',', mItem.SameNameUnits));
  Assert.AreEqual('FMX.Graphics.TBitmap', string.Join(',', mItem.SameNameHidden));
  Assert.IsTrue(Find(mItems, 'TBitmap', 'Winapi.Windows', mItem));
  Assert.IsFalse(mItem.SameNameActive);
  Assert.AreEqual('Vcl.Graphics', mItem.SameNameOf);
  Assert.AreEqual('prefix', mItem.SameNameInsert);
  Assert.IsTrue(mItem.HasTextEdit);
  Assert.AreEqual('Winapi.Windows.TBitmap', mItem.TextEdit.NewText);
  Assert.AreEqual(10, mItem.TextEdit.Range.StartPos.Character);
  Assert.AreEqual(0, Integer(Length(mItem.AdditionalEdits)));
end;

procedure TCompletionSameNamesTests.UsesModeMovesTheUnit;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mSettings: TCompletionSettings;
begin
  mSettings := TCompletionSettings.Default;
  mSettings.SameNameInsert := TCompletionSameNameInsert.Uses_;
  mItems := ItemsAt(FIndex, cUnitHaupt, 'TBitm', mSettings);
  Assert.IsTrue(Find(mItems, 'TBitmap', 'Winapi.Windows', mItem));
  Assert.AreEqual('move', mItem.SameNameInsert);
  Assert.IsFalse(mItem.HasTextEdit);
  Assert.AreEqual(2, Integer(Length(mItem.AdditionalEdits)));
  Assert.AreEqual(', Winapi.Windows', mItem.AdditionalEdits[1].NewText);
end;

procedure TCompletionSameNamesTests.FmxAppearsOnlyWhenSwitchedOn;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mSettings: TCompletionSettings;
begin
  Assert.IsFalse(Find(ItemsAt(FIndex, cUnitHaupt, 'TBitm', TCompletionSettings.Default), 'TBitmap', 'FMX.Graphics',
    mItem));
  mSettings := TCompletionSettings.Default;
  mSettings.ShowFmxUnits := True;
  mItems := ItemsAt(FIndex, cUnitHaupt, 'TBitm', mSettings);
  Assert.IsTrue(Find(mItems, 'TBitmap', 'FMX.Graphics', mItem));
  // Nicht eingebunden: Präfix und uses-Eintrag.
  Assert.AreEqual('prefixAdd', mItem.SameNameInsert);
  Assert.AreEqual('FMX.Graphics.TBitmap', mItem.TextEdit.NewText);
  Assert.AreEqual(1, Integer(Length(mItem.AdditionalEdits)));
  Assert.IsTrue(mItem.AdditionalEdits[0].NewText.Contains('FMX.Graphics'), mItem.AdditionalEdits[0].NewText);
end;

procedure TCompletionSameNamesTests.SwitchedOffShowsOnlyTheActive;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mSettings: TCompletionSettings;
begin
  mSettings := TCompletionSettings.Default;
  mSettings.SameNameVariants := False;
  mItems := ItemsAt(FIndex, cUnitHaupt, 'TBitm', mSettings);
  Assert.AreEqual('TBitmap@Vcl.Graphics TBitmapImage@Vcl.Graphics', Order(mItems));
  Assert.IsTrue(Find(mItems, 'TBitmap', 'Vcl.Graphics', mItem));
  Assert.IsFalse(mItem.SameNameActive);
  Assert.AreEqual(0, Integer(Length(mItem.SameNameUnits)));
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionSameNamesTests);

end.
