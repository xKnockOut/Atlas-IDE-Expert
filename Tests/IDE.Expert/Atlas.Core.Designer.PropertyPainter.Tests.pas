unit Atlas.Core.Designer.PropertyPainter.Tests;

// Tests für den Format-Pinsel (#726): Gruppen, Zeilen mit verschachtelten
// Eigenschaften, Vorauswahl nach Gruppen und gemerkten Pfaden, Knoten,
// Typabgleich mit Ziel, Ereignis-Handler-Typen und die Merkliste als JSON.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasPropertyPainterTests = class
  public
    [Test]
    procedure Groups;
    [Test]
    procedure ParseGroupList;
    [Test]
    procedure RowsNestUnderNode;
    [Test]
    procedure PreselectByGroups;
    [Test]
    procedure PreselectRemembered;
    [Test]
    procedure NodeCoversChildren;
    [Test]
    procedure MatchTypes;
    [Test]
    procedure EventHandlerTypes;
    [Test]
    procedure MemoryJson;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Designer.PropertyPainter;

function P(const APath, AType: string): TAtlasPaintProperty;
begin
  Result := TAtlasPaintProperty.Create(APath, AType, False);
end;

function ButtonProps: TArray<TAtlasPaintProperty>;
begin
  Result := [P('Left', 'Integer'), P('Top', 'Integer'), P('Width', 'Integer'), P('Height', 'Integer'),
    P('Caption', 'TCaption'), P('Font.Name', 'TFontName'), P('Font.Style', 'TFontStyles'),
    P('Anchors', 'TAnchors'), P('Font.Size', 'Integer'), P('BevelKind', 'TBevelKind'),
    TAtlasPaintProperty.Create('OnClick', 'TNotifyEvent', True)];
end;

function RowsText(const ARows: TArray<TAtlasPaintRow>): string;
var
  mRow: TAtlasPaintRow;
begin
  Result := '';
  for mRow in ARows do
  begin
    case mRow.Kind of
      TAtlasPaintRowKind.Header:
        Result := Result + '[' + TAtlasPropertyPainter.GroupName(mRow.Group) + ']';
      TAtlasPaintRowKind.Node:
        Result := Result + mRow.Path + '>';
    else
      Result := Result + mRow.Path + '(' + IntToStr(mRow.Parent) + ')';
    end;
    Result := Result + ' ';
  end;
  Result := Trim(Result);
end;

procedure TAtlasPropertyPainterTests.Groups;
begin
  Assert.AreEqual<TAtlasPaintGroup>(TAtlasPaintGroup.Font, TAtlasPropertyPainter.GroupOf(P('Font.Color', 'TColor')));
  Assert.AreEqual<TAtlasPaintGroup>(TAtlasPaintGroup.Colors,
    TAtlasPropertyPainter.GroupOf(P('ParentColor', 'Boolean')));
  Assert.AreEqual<TAtlasPaintGroup>(TAtlasPaintGroup.Layout,
    TAtlasPropertyPainter.GroupOf(P('Margins.Left', 'TMarginSize')));
  Assert.AreEqual<TAtlasPaintGroup>(TAtlasPaintGroup.Text, TAtlasPropertyPainter.GroupOf(P('Hint', 'string')));
  Assert.AreEqual<TAtlasPaintGroup>(TAtlasPaintGroup.Behavior,
    TAtlasPropertyPainter.GroupOf(P('PopupMenu', 'TPopupMenu')));
  Assert.AreEqual<TAtlasPaintGroup>(TAtlasPaintGroup.Position, TAtlasPropertyPainter.GroupOf(P('Top', 'Integer')));
  Assert.AreEqual<TAtlasPaintGroup>(TAtlasPaintGroup.Events,
    TAtlasPropertyPainter.GroupOf(TAtlasPaintProperty.Create('OnClick', 'TNotifyEvent', True)));
  Assert.AreEqual<TAtlasPaintGroup>(TAtlasPaintGroup.Other, TAtlasPropertyPainter.GroupOf(P('WordWrap', 'Boolean')));
end;

procedure TAtlasPropertyPainterTests.ParseGroupList;
begin
  Assert.AreEqual<TAtlasPaintGroups>([TAtlasPaintGroup.Font, TAtlasPaintGroup.Colors, TAtlasPaintGroup.Size,
    TAtlasPaintGroup.Layout],
    TAtlasPropertyPainter.ParseGroups('font, colors,size ;layout, unknown'));
  Assert.AreEqual<TAtlasPaintGroups>([], TAtlasPropertyPainter.ParseGroups(''));
end;

procedure TAtlasPropertyPainterTests.RowsNestUnderNode;
begin
  Assert.AreEqual('[font] Font> Font.Name(1) Font.Style(1) Font.Size(1) [size] Width Height [position] Left Top ' +
    '[layout] Anchors [text] Caption [events] OnClick [other] BevelKind',
    RowsText(TAtlasPropertyPainter.Rows(ButtonProps)).Replace('(-1)', ''));
end;

procedure TAtlasPropertyPainterTests.PreselectByGroups;
var
  mRows: TArray<TAtlasPaintRow>;
  mChosen: TArray<string>;
begin
  mRows := TAtlasPropertyPainter.Rows(ButtonProps);
  mChosen := TAtlasPropertyPainter.Chosen(mRows, TAtlasPropertyPainter.Preselect(mRows,
    TAtlasPropertyPainter.ParseGroups('font, colors, size, layout'), nil, False));
  Assert.AreEqual('Font.Name,Font.Style,Font.Size,Width,Height,Anchors', string.Join(',', mChosen));
end;

procedure TAtlasPropertyPainterTests.PreselectRemembered;
var
  mRows: TArray<TAtlasPaintRow>;
  mChecked: TArray<Boolean>;
begin
  mRows := TAtlasPropertyPainter.Rows(ButtonProps);
  mChecked := TAtlasPropertyPainter.Preselect(mRows, [TAtlasPaintGroup.Font], ['font.style', 'Caption'], True);
  Assert.AreEqual('Font.Style,Caption', string.Join(',', TAtlasPropertyPainter.Chosen(mRows, mChecked)));
  Assert.IsFalse(mChecked[1], 'Knoten Font nur mit allen Kindern');
end;

procedure TAtlasPropertyPainterTests.NodeCoversChildren;
var
  mRows: TArray<TAtlasPaintRow>;
  mChecked: TArray<Boolean>;
begin
  mRows := TAtlasPropertyPainter.Rows(ButtonProps);
  SetLength(mChecked, Length(mRows));
  mChecked[1] := True;
  Assert.AreEqual('Font.Name,Font.Style,Font.Size', string.Join(',', TAtlasPropertyPainter.Chosen(mRows, mChecked)));
end;

procedure TAtlasPropertyPainterTests.MatchTypes;
var
  mSkipped: TArray<string>;
  mApply: TArray<string>;
begin
  // Vom TButton auf ein TLabel: Schrift passt, BevelKind fehlt, Width hat anderen Typ (konstruiert).
  mApply := TAtlasPropertyPainter.Match(ButtonProps, ['Font.Name', 'Font.Style', 'BevelKind', 'Width'],
    [P('Font.Name', 'TFontName'), P('Font.Style', 'TFontStyles'), P('Width', 'Int64')], mSkipped);
  Assert.AreEqual('Font.Name,Font.Style', string.Join(',', mApply));
  Assert.AreEqual('BevelKind,Width', string.Join(',', mSkipped));
end;

procedure TAtlasPropertyPainterTests.EventHandlerTypes;
var
  mSkipped: TArray<string>;
begin
  Assert.AreEqual(1, Integer(Length(TAtlasPropertyPainter.Match(ButtonProps, ['OnClick'],
    [TAtlasPaintProperty.Create('OnClick', 'TNotifyEvent', True)], mSkipped))));
  Assert.AreEqual(0, Integer(Length(TAtlasPropertyPainter.Match(ButtonProps, ['OnClick'],
    [TAtlasPaintProperty.Create('OnClick', 'TMouseEvent', True)], mSkipped))), 'anderer Handler-Typ');
  Assert.AreEqual('OnClick', mSkipped[0]);
end;

procedure TAtlasPropertyPainterTests.MemoryJson;
var
  mMemory, mLoaded: TAtlasPaintMemory;
  mPaths: TArray<string>;
begin
  mMemory := TAtlasPaintMemory.Create;
  mLoaded := TAtlasPaintMemory.Create;
  try
    mMemory.Put('TButton', ['Font.Style', 'Width']);
    Assert.IsTrue(mLoaded.LoadJson(mMemory.ToJson));
    Assert.IsTrue(mLoaded.TryGet('tbutton', mPaths));
    Assert.AreEqual('Font.Style,Width', string.Join(',', mPaths));
    Assert.IsFalse(mLoaded.TryGet('TLabel', mPaths));
    Assert.IsFalse(mLoaded.LoadJson('{'));
    Assert.IsFalse(mLoaded.TryGet('TButton', mPaths));
  finally
    mLoaded.Free;
    mMemory.Free;
  end;
end;

end.
