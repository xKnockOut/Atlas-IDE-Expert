unit Atlas.Common.Lsp.IdeUnits.Tests;

// Tests für die Ersatz-Units aus der RTTI der IDE (atlas/ideMembers): Pascal-Text mit kurzen Typnamen und uses,
// Einlesen in den eigenen Index samt Text, Nachfrage nur nach unbekannten Units, Vorrang des gemeinsamen Index,
// Hover und Vervollständigung über TIdeIndex.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIdeUnitsTests = class
  public
    /// <summary>Erste Vervollständigung füllt Caches, nicht dem Test anrechnen.</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure ShortTypeDropsUnitsAndCollectsUses;
    [Test]
    procedure BuildWritesClassEnumInterfaceAndRecord;
    [Test]
    procedure AddIndexesUnitAndKeepsText;
    [Test]
    procedure WantedSkipsKnownAndAskedUnits;
    [Test]
    procedure SharedIndexWins;
    [Test]
    procedure HoverShowsMemberOfIdeType;
    [Test]
    procedure CompletionListsMembersAndEnumValues;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Documentation,
  Atlas.Common.Lsp.Hover,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.Completion.Lists,
  Atlas.Common.Lsp.IdeUnits.Source,
  Atlas.Common.Lsp.IdeUnits,
  Atlas.Common.Lsp.IdeIndex;

const
  cMembers = '{"units":[{"unit":"Vendor.Grid","types":[' +
    '{"name":"TVendorGrid","kind":"class","parent":"Vcl.Controls.TCustomControl",' +
    '"interfaces":["Vendor.Base.IVendor"],"members":[' +
    '{"kind":"property","name":"State","type":"Vendor.Grid.TGridState","visibility":"published"},' +
    '{"kind":"function","name":"Find","type":"System.Integer","static":true,' +
    '"params":[{"name":"AName","type":"System.string","flag":"const"}]},' +
    '{"kind":"constructor","name":"Create","params":[{"name":"AOwner","type":"System.Classes.TComponent"}]},' +
    '{"kind":"field","name":"Tag2","type":"System.Integer"}]},' +
    '{"name":"TGridState","kind":"enum","values":["gsNone","gsEdit"]},' +
    '{"name":"IVendor2","kind":"interface","parent":"System.IInterface",' +
    '"members":[{"kind":"procedure","name":"Ping"}]},' +
    '{"name":"TCell","kind":"record","members":[{"kind":"field","name":"Row","type":"System.Integer"}]},' +
    '{"name":"TGridSet","kind":"set"}]}]}';

  cMain = 'unit Haupt;'#10'interface'#10'uses'#10'  Vendor.Grid;'#10'implementation'#10 +
    'procedure Zeige(G: TVendorGrid);'#10'begin'#10'  G.State := gsEdit;'#10'  G.;'#10'end;'#10'end.';

function Units: TIdeUnits;
var
  mValue: TJSONValue;
begin
  Result := TIdeUnits.Create;
  mValue := TJSONObject.ParseJSONValue(cMembers);
  try
    Result.Add(mValue);
  finally
    mValue.Free;
  end;
end;

function PositionOf(const AText, AMarker: string; AOffset: Integer): TTextPosition;
var
  mIndex, mLine, mStart, mPos: Integer;
begin
  mIndex := Pos(AMarker, AText) + AOffset;
  mLine := 0;
  mStart := 1;
  for mPos := 1 to mIndex - 1 do
  begin
    if AText[mPos] = #10 then
    begin
      Inc(mLine);
      mStart := mPos + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mStart);
end;

procedure TIdeUnitsTests.ShortTypeDropsUnitsAndCollectsUses;
var
  mUses: TList<string>;
begin
  mUses := TList<string>.Create;
  try
    Assert.AreEqual('TColor', TIdeUnitSource.ShortType('Vcl.Graphics.TColor', 'Vendor.Grid', mUses));
    Assert.AreEqual('TList<TCell>', TIdeUnitSource.ShortType('System.Generics.Collections.TList<Vendor.Grid.TCell>',
      'Vendor.Grid', mUses));
    Assert.AreEqual('string', TIdeUnitSource.ShortType('System.string', 'Vendor.Grid', mUses));
    // Eigene Unit und System kommen nicht in uses, jede andere nur einmal.
    TIdeUnitSource.ShortType('Vcl.Graphics.TFont', 'Vendor.Grid', mUses);
    Assert.AreEqual('Vcl.Graphics,System.Generics.Collections', string.Join(',', mUses.ToArray));
  finally
    mUses.Free;
  end;
end;

procedure TIdeUnitsTests.BuildWritesClassEnumInterfaceAndRecord;
var
  mValue: TJSONValue;
  mText: string;
begin
  mValue := TJSONObject.ParseJSONValue(cMembers);
  try
    mText := TIdeUnitSource.Build('Vendor.Grid',
      TJSONObject(mValue).GetValue<TJSONArray>('units').Items[0].GetValue<TJSONArray>('types'));
  finally
    mValue.Free;
  end;
  Assert.IsTrue(mText.StartsWith('unit Vendor.Grid;'));
  Assert.IsTrue(mText.Contains('uses' + sLineBreak + '  Vcl.Controls, Vendor.Base, System.Classes;'), mText);
  Assert.IsTrue(mText.Contains('  TVendorGrid = class(TCustomControl, IVendor)' + sLineBreak + '  public' +
    sLineBreak + '    Tag2: Integer;' + sLineBreak + '    class function Find(const AName: string): Integer;' +
    sLineBreak + '    constructor Create(AOwner: TComponent);' + sLineBreak + '  published' + sLineBreak +
    '    property State: TGridState;' + sLineBreak + '  end;'), mText);
  Assert.IsTrue(mText.Contains('  TGridState = (gsNone, gsEdit);'), mText);
  Assert.IsTrue(mText.Contains('  IVendor2 = interface(IInterface)' + sLineBreak + '    procedure Ping;' +
    sLineBreak + '  end;'), mText);
  Assert.IsTrue(mText.Contains('  TCell = record' + sLineBreak + '  public' + sLineBreak + '    Row: Integer;'),
    mText);
  // Mengen und andere Arten entfallen.
  Assert.IsFalse(mText.Contains('TGridSet'), mText);
end;

procedure TIdeUnitsTests.AddIndexesUnitAndKeepsText;
var
  mUnits: TIdeUnits;
  mUnit: TUnitIndex;
  mText: string;
begin
  mUnits := Units;
  try
    Assert.IsTrue(mUnits.Index.FindUnit('vendor.grid', mUnit));
    Assert.AreEqual(TIdeUnits.PathOf('Vendor.Grid'), mUnit.FileName);
    Assert.IsTrue(mUnit.Library_);
    Assert.IsTrue(TIdeUnits.IsIdePath(mUnit.FileName));
    Assert.IsTrue(mUnits.ReadText(mUnit.FileName, mText));
    Assert.IsTrue(mText.Contains('property State: TGridState;'));
    Assert.IsFalse(mUnits.ReadText('C:\Vendor\Vendor.Grid.pas', mText));
    Assert.AreEqual(1, Integer(Length(mUnits.Index.FindSymbols('State'))));
  finally
    mUnits.Free;
  end;
end;

procedure TIdeUnitsTests.WantedSkipsKnownAndAskedUnits;
var
  mUnits: TIdeUnits;
  mShared: ISymbolIndex;
begin
  mShared := TSymbolIndex.Create;
  mShared.AddUnit(TIndexExtractor.ExtractText('unit Vendor.Src;'#10'interface'#10'implementation'#10'end.',
    'C:\Vendor\Vendor.Src.pas', nil));
  mUnits := Units;
  try
    // Vendor.Src hat Quelltext, Vendor.Grid schon eine Ersatz-Unit.
    Assert.AreEqual('Vendor.Neu', string.Join(',', mUnits.Wanted(TArray<string>.Create('Vendor.Src', 'Vendor.Grid',
      'Vendor.Neu'), mShared)));
    // Einmal gefragt genügt.
    Assert.AreEqual(0, Integer(Length(mUnits.Wanted(TArray<string>.Create('Vendor.Neu'), mShared))));
  finally
    mUnits.Free;
  end;
end;

procedure TIdeUnitsTests.SharedIndexWins;
var
  mUnits: TIdeUnits;
  mShared, mIndex: ISymbolIndex;
  mUnit: TUnitIndex;
begin
  mShared := TSymbolIndex.Create;
  mUnits := Units;
  try
    mIndex := TIdeIndex.Create(mShared, mUnits.Index);
    Assert.IsTrue(mIndex.FindUnit('Vendor.Grid', mUnit));
    Assert.IsTrue(TIdeUnits.IsIdePath(mUnit.FileName));
    Assert.AreEqual(1, mIndex.UnitCount);
    mShared.AddUnit(TIndexExtractor.ExtractText('unit Vendor.Grid;'#10'interface'#10'implementation'#10'end.',
      'C:\Vendor\Vendor.Grid.pas', nil));
    Assert.IsTrue(mIndex.FindUnit('Vendor.Grid', mUnit));
    Assert.AreEqual('C:\Vendor\Vendor.Grid.pas', mUnit.FileName);
    mIndex := nil;
  finally
    mUnits.Free;
  end;
end;

/// <summary>Liest die Ersatz-Units aus AUnits.</summary>
function ReaderOf(AUnits: TIdeUnits): TDocReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := AUnits.ReadText(AFileName, AText);
    end;
end;

procedure TIdeUnitsTests.HoverShowsMemberOfIdeType;
var
  mUnits: TIdeUnits;
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mInfo: THoverInfo;
  mJson: TJSONObject;
begin
  mUnits := Units;
  mTree := TPascalParser.Parse(cMain);
  try
    mIndex := TIdeIndex.Create(TSymbolIndex.Create, mUnits.Index);
    mResolver := TNameResolver.Create(mIndex);
    try
      mInfo := TLspHover.InfoAt(THoverSource.Create(mResolver, mIndex, ReaderOf(mUnits)), mTree, cMain,
        'C:\P\Haupt.pas', PositionOf(cMain, 'State', 1));
    finally
      mResolver.Free;
    end;
    Assert.IsTrue(mInfo.Found);
    Assert.AreEqual('property State: TGridState;', mInfo.Declaration);
    Assert.AreEqual('Vendor.Grid', mInfo.UnitName);
    // Die Ersatz-Unit gibt es nicht als Datei: kein Sprungziel für Strg+Klick.
    mJson := mInfo.ToAtlasJson;
    try
      Assert.IsNull(mJson.GetValue('file'));
    finally
      mJson.Free;
    end;
    mInfo := Default(THoverInfo);
    mIndex := nil;
  finally
    mTree.Free;
    mUnits.Free;
  end;
end;

/// <summary>Namen der Vervollständigung an AMarker (+ AOffset), durch Leerzeichen getrennt.</summary>
function CompletionNames(AUnits: TIdeUnits; const AText, AMarker: string; AOffset: Integer): string;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mItem: TCompletionItem;
begin
  Result := '';
  mIndex := TIdeIndex.Create(TSymbolIndex.Create, AUnits.Index);
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(AText);
  try
    for mItem in TCompletionLists.Collect(mResolver, mIndex, mTree, 'C:\P\Haupt.pas',
      PositionOf(AText, AMarker, AOffset), TCompletionMatching.Prefix).Items do
    begin
      Result := Result + mItem.Name + ' ';
    end;
  finally
    mTree.Free;
    mResolver.Free;
  end;
end;

procedure TIdeUnitsTests.WarmUp;
var
  mUnits: TIdeUnits;
begin
  mUnits := Units;
  try
    CompletionNames(mUnits, cMain, 'G.;', 2);
    CompletionNames(mUnits, StringReplace(cMain, 'gsEdit;', 'gs;', []), ':= gs;', 5);
  finally
    mUnits.Free;
  end;
end;

procedure TIdeUnitsTests.CompletionListsMembersAndEnumValues;
var
  mUnits: TIdeUnits;
  mNames: string;
begin
  mUnits := Units;
  try
    mNames := CompletionNames(mUnits, cMain, 'G.;', 2);
    Assert.IsTrue(mNames.Contains('State '), mNames);
    Assert.IsTrue(mNames.Contains('Find '), mNames);
    mNames := CompletionNames(mUnits, StringReplace(cMain, 'gsEdit;', 'gs;', []), ':= gs;', 5);
    Assert.IsTrue(mNames.Contains('gsNone '), mNames);
    Assert.IsTrue(mNames.Contains('gsEdit '), mNames);
  finally
    mUnits.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIdeUnitsTests);

end.
