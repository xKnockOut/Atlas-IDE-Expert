unit Atlas.Core.Hover.Layout.DebugTree.Tests;

// Tests des aufgeklappten Debug-Werts im Hover-Satz (#895): Zeichen vor dem Ausdruck, eingerückte Zeilen mit
// Klickflächen, geänderte Werte mit altem Wert, gewählte Zeile und Rollbereich. Messwerte wie in
// Atlas.Core.Hover.Layout.TestSupport (Editorschrift 8 Pixel je Zeichen, 16 hoch).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  THoverLayoutDebugTreeTests = class
  public
    /// <summary>Zugeklappt: ▸ vor dem Ausdruck, Klickfläche DebugRow -1, keine Zeilen.</summary>
    [Test]
    procedure CollapsedValueShowsGlyphAndHit;
    /// <summary>Aufgeklappt: ▾, Zeilen „Name = Wert“ je Tiefe eingerückt, je Zeile eine Klickfläche.</summary>
    [Test]
    procedure ExpandedRowsAreIndentedWithHits;
    /// <summary>„auswerten“ und „weitere …“ in der Akzentfarbe, ausstehende gedimmt.</summary>
    [Test]
    procedure LazyMoreAndPendingColors;
    /// <summary>Geänderter Wert und geänderte Zeile: hinterlegt, alter Wert „← …“ gedimmt.</summary>
    [Test]
    procedure ChangedValuesShowOldText;
    /// <summary>Gewählte Zeile in der Auswahlfarbe hinter ihrem Text.</summary>
    [Test]
    procedure SelectedRowIsFilled;
    /// <summary>Mehr Zeilen als die Grenze: Rollbereich mit Daumen, verdeckte Klickflächen entfallen.</summary>
    [Test]
    procedure ManyRowsScroll;
    /// <summary>Nicht aufklappbar: wie bisher ohne Zeichen und Klickfläche.</summary>
    [Test]
    procedure PlainValueUnchanged;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.Layout,
  Atlas.Core.Hover.Layout.Contract,
  Atlas.Core.Hover.View,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Hover.Layout.TestSupport;

function Row(const AName, AText: string; ADepth: Integer): TAtlasDebugValueRow;
begin
  Result := Default(TAtlasDebugValueRow);
  Result.Expression := 'K.' + AName;
  Result.Name := AName;
  Result.Text := AText;
  Result.Depth := ADepth;
end;

function TreeValue(AExpanded: Boolean): TAtlasDebugValue;
begin
  Result := TAtlasDebugValue.Evaluated('K', '(Name: ''Meier''; Umsatz: 1250)');
  Result.Expandable := True;
  Result.Expanded := AExpanded;
  if AExpanded then
  begin
    Result.Rows := [Row('Name', '''Meier''', 0), Row('Adressen', '(2)', 0), Row('Ort', '''Köln''', 1)];
    Result.Rows[1].Expandable := True;
    Result.Rows[1].Expanded := True;
  end;
end;

function TreeInput(const AValue: TAtlasDebugValue): TAtlasHoverInput;
var
  mView: TAtlasHoverView;
begin
  mView := Default(TAtlasHoverView);
  mView.DebugValue := AValue;
  Result := HoverTestInput(mView, 400);
end;

function ItemOf(const ALayout: TAtlasHoverLayout; const AText: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ALayout.Items) do
  begin
    if ALayout.Items[mIndex].Text = AText then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Indizes der Klickflächen DebugRow in ihrer Reihenfolge, durch Komma getrennt.</summary>
function RowHits(const ALayout: TAtlasHoverLayout): string;
var
  mHit: TAtlasHoverHit;
begin
  Result := '';
  for mHit in ALayout.Hits do
  begin
    if mHit.Kind = TAtlasHoverHitKind.DebugRow then
    begin
      Result := Result + IntToStr(mHit.Index) + ',';
    end;
  end;
end;

/// <summary>Anzahl der Flächen in der Farbe AColor.</summary>
function FillCount(const ALayout: TAtlasHoverLayout; AColor: TAtlasColor): Integer;
var
  mItem: TAtlasHoverItem;
begin
  Result := 0;
  for mItem in ALayout.Items do
  begin
    if (mItem.Kind = TAtlasHoverItemKind.Fill) and (mItem.Color = AColor) then
    begin
      Inc(Result);
    end;
  end;
end;

procedure THoverLayoutDebugTreeTests.CollapsedValueShowsGlyphAndHit;
var
  mLayout: TAtlasHoverLayout;
begin
  mLayout := BuildLayout(TreeInput(TreeValue(False)));
  Assert.IsTrue(ItemOf(mLayout, '▸ K') >= 0);
  Assert.AreEqual('-1,', RowHits(mLayout));
  Assert.IsFalse(mLayout.DebugRows.Scrollable);
end;

procedure THoverLayoutDebugTreeTests.ExpandedRowsAreIndentedWithHits;
var
  mLayout: TAtlasHoverLayout;
  mName, mOrt: Integer;
begin
  mLayout := BuildLayout(TreeInput(TreeValue(True)));
  Assert.IsTrue(ItemOf(mLayout, '▾ K') >= 0);
  mName := ItemOf(mLayout, 'Name = ''Meier''');
  mOrt := ItemOf(mLayout, 'Ort = ''Köln''');
  Assert.IsTrue(mName >= 0);
  Assert.IsTrue(ItemOf(mLayout, '▾ Adressen = (2)') >= 0);
  Assert.IsTrue(mOrt >= 0);
  // Eine Ebene tiefer: 12 Pixel weiter rechts; Zeilenabstand 16 + 3.
  Assert.AreEqual(mLayout.Items[mName].Rect.Left + 12, mLayout.Items[mOrt].Rect.Left);
  Assert.AreEqual(mLayout.Items[mName].Rect.Top + 2 * 19, mLayout.Items[mOrt].Rect.Top);
  Assert.AreEqual('-1,0,1,2,', RowHits(mLayout));
  Assert.IsFalse(mLayout.DebugRows.Scrollable);
end;

procedure THoverLayoutDebugTreeTests.LazyMoreAndPendingColors;
var
  mValue: TAtlasDebugValue;
  mLayout: TAtlasHoverLayout;
  mColors: TAtlasColors;
begin
  mValue := TreeValue(True);
  mValue.Rows[0].Lazy := True;
  mValue.Rows[0].Text := 'auswerten';
  mValue.Rows[1].Expanded := False;
  mValue.Rows[2] := Row('', 'weitere 100 …', 0);
  mValue.Rows[2].More := True;
  mValue.Rows := mValue.Rows + [Row('Umsatz', '…', 0)];
  mValue.Rows[3].Pending := True;
  mLayout := BuildLayout(TreeInput(mValue));
  mColors := TAtlasColors.Light;
  Assert.AreEqual(mColors.Accent, mLayout.Items[ItemOf(mLayout, 'Name = auswerten')].Color);
  Assert.AreEqual(mColors.Accent, mLayout.Items[ItemOf(mLayout, 'weitere 100 …')].Color);
  Assert.AreEqual(mColors.Muted, mLayout.Items[ItemOf(mLayout, 'Umsatz = …')].Color);
  Assert.AreEqual(mColors.Text, mLayout.Items[ItemOf(mLayout, '▸ Adressen = (2)')].Color);
end;

procedure THoverLayoutDebugTreeTests.ChangedValuesShowOldText;
var
  mValue: TAtlasDebugValue;
  mLayout: TAtlasHoverLayout;
  mColors: TAtlasColors;
  mOld: Integer;
begin
  mValue := TreeValue(True);
  mValue.OldText := '(Name: ''Meier''; Umsatz: 980)';
  mValue.Rows[0].OldText := '''Maier''';
  mLayout := BuildLayout(TreeInput(mValue));
  mColors := TAtlasColors.Light;
  mOld := ItemOf(mLayout, '← (Name: ''Meier''; Umsatz: 980)');
  Assert.IsTrue(mOld >= 0);
  Assert.AreEqual(mColors.Muted, mLayout.Items[mOld].Color);
  mOld := ItemOf(mLayout, '← ''Maier''');
  Assert.IsTrue(mOld >= 0);
  // Der alte Wert der Zeile steht hinter ihrem Text: „Name = 'Meier' “ sind 15 Zeichen zu 8 Pixeln.
  Assert.AreEqual(mLayout.Items[ItemOf(mLayout, 'Name = ''Meier''')].Rect.Left + 15 * 8,
    mLayout.Items[mOld].Rect.Left);
  // Wert und Zeile hinterlegt, jeweils vor ihrem Text.
  Assert.AreEqual(2, FillCount(mLayout, mColors.WarnSoft));
  Assert.AreEqual<TAtlasHoverItemKind>(TAtlasHoverItemKind.Fill,
    mLayout.Items[ItemOf(mLayout, 'Name = ''Meier''') - 1].Kind);
end;

procedure THoverLayoutDebugTreeTests.SelectedRowIsFilled;
var
  mInput: TAtlasHoverInput;
  mLayout: TAtlasHoverLayout;
  mColors: TAtlasColors;
  mText: Integer;
begin
  mInput := TreeInput(TreeValue(True));
  mColors := TAtlasColors.Light;
  Assert.AreEqual(0, FillCount(BuildLayout(mInput), mColors.Selection));
  mInput.DebugSelectedRow := 2;
  mLayout := BuildLayout(mInput);
  Assert.AreEqual(1, FillCount(mLayout, mColors.Selection));
  mText := ItemOf(mLayout, '▾ Adressen = (2)');
  Assert.AreEqual<TAtlasHoverItemKind>(TAtlasHoverItemKind.Fill, mLayout.Items[mText - 1].Kind);
  Assert.AreEqual(mColors.Selection, mLayout.Items[mText - 1].Color);
  Assert.AreEqual(mLayout.Items[mText].Rect.Top, mLayout.Items[mText - 1].Rect.Top);
end;

procedure THoverLayoutDebugTreeTests.ManyRowsScroll;
var
  mValue: TAtlasDebugValue;
  mInput: TAtlasHoverInput;
  mLayout: TAtlasHoverLayout;
  mIndex: Integer;
begin
  mValue := TreeValue(True);
  mValue.Rows := nil;
  for mIndex := 0 to 29 do
  begin
    mValue.Rows := mValue.Rows + [Row('[' + IntToStr(mIndex) + ']', IntToStr(mIndex), 0)];
  end;
  mInput := TreeInput(mValue);
  mInput.DebugRows.MaxLines := 5;
  mLayout := BuildLayout(mInput);
  Assert.IsTrue(mLayout.DebugRows.Scrollable);
  Assert.AreEqual(19, mLayout.DebugRows.Row);
  Assert.AreEqual(5 * 19, mLayout.DebugRows.View.Height);
  Assert.AreEqual(30 * 19, mLayout.DebugRows.Content);
  // Sichtbar sind der Ausdruck und fünf Zeilen (die sechste ragt höchstens an den Rand).
  Assert.IsTrue(Length(RowHits(mLayout)) < Length('-1,0,1,2,3,4,5,6,'));
  // Versatz um zwei Zeilen: Zeile 0 nicht mehr klickbar.
  mInput.DebugRows.Scroll := 2 * 19;
  mLayout := BuildLayout(mInput);
  Assert.AreEqual(2 * 19, mLayout.DebugRows.Scroll);
  Assert.IsFalse(RowHits(mLayout).StartsWith('-1,0,'));
end;

procedure THoverLayoutDebugTreeTests.PlainValueUnchanged;
var
  mLayout: TAtlasHoverLayout;
begin
  mLayout := BuildLayout(TreeInput(TAtlasDebugValue.Evaluated('Count', '3')));
  Assert.IsTrue(ItemOf(mLayout, 'Count') >= 0);
  Assert.AreEqual('', RowHits(mLayout));
  Assert.AreEqual(0, FillCount(mLayout, TAtlasColors.Light.WarnSoft));
end;

initialization
  TDUnitX.RegisterTestFixture(THoverLayoutDebugTreeTests);

end.
