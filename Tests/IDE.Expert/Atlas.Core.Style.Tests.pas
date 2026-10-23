unit Atlas.Core.Style.Tests;

// Tests für Farben, Palette, Syntaxfärbung und Darstellung der Einträge (#411, #420, #421).

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette;

type
  [TestFixture]
  TAtlasColorTests = class
  public
    [Test]
    procedure HexRoundTrip;
    [Test]
    procedure RejectsInvalidHex;
    [Test]
    procedure MixesLikeTranslucentLayer;
    [Test]
    procedure ContrastOfBlackAndWhiteIs21;
    [Test]
    procedure HslRoundTripAndLighten;
    [Test]
    procedure DetectsDarkBackgrounds;
    [Test]
    procedure DeltaE2000MatchesReference;
  end;

  [TestFixture]
  TAtlasPaletteTests = class
  private
    procedure CheckContrast(const AColors: TAtlasColors; const AMode: string);
    procedure CheckPairs(const AColors: TAtlasColors; const AMode: string; const ABackgrounds,
      ATexts: array of string);
  public
    [Test]
    procedure LightRolesMeetContrast;
    [Test]
    procedure DarkRolesMeetContrast;
    [Test]
    procedure AccentIsGreekBlue;
    [Test]
    procedure BadgeKindsDifferInLightness;
    [Test]
    procedure ChoosesModeByBackground;
    [Test]
    procedure LightPairsStandOut;
    [Test]
    procedure DarkPairsStandOut;
    /// <summary>#451: sechs unterscheidbare Platzhalterfarben, keine wie die Fehlerfarbe.</summary>
    [Test]
    procedure PlaceholderColorsDiffer;
    [Test]
    procedure InlayHintColorsMixFromBackground;
    [Test]
    procedure ChromeColorsFollowTheIdeToolbar;
  end;

  [TestFixture]
  TAtlasWrapTests = class
  private
    function Cum(const AText: string): TArray<Integer>;
  public
    [Test]
    procedure WrapFitsOneLine;
    [Test]
    procedure WrapBreaksAtSpace;
    [Test]
    procedure WrapIndentNarrowsFollowLines;
    [Test]
    procedure WrapLongWordStandsAlone;
    [Test]
    procedure WrapEmptyText;
  end;

  [TestFixture]
  TAtlasScalingTests = class
  public
    [Test]
    procedure NormalCaretIsNoZoom;
    [Test]
    procedure LargerCaretIsZoom;
    [Test]
    procedure ClampsAndIgnoresInvalidValues;
  end;

  [TestFixture]
  TAtlasSyntaxTests = class
  public
    [Test]
    procedure ColorsKeywordsAndStrings;
    [Test]
    procedure TokensCoverWholeText;
    [Test]
    procedure NameAfterDotIsNoKeyword;
    [Test]
    procedure FindsDefaultValues;
    [Test]
    procedure ParenStarIsComment;
    [Test]
    procedure CommentsSpanLines;
  end;

  [TestFixture]
  TAtlasPresentationTests = class
  public
    [Test]
    procedure BadgesFollowKind;
    [Test]
    procedure MethodBadgeFollowsSignature;
    [Test]
    procedure AttributeBadge;
    [Test]
    procedure MethodRefTag;
    [Test]
    procedure WithOriginAndShadowTags;
    [Test]
    procedure MissingUnitBecomesTag;
    [Test]
    procedure UnitDetailIsFileName;
    [Test]
    procedure DeprecatedAndConstructorTags;
    [Test]
    procedure ScopeTagsNameOrigin;
    [Test]
    procedure HighlightsPrefixWordStartsSubstringSubsequence;
    [Test]
    procedure NoHighlightsWithoutMatch;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Types,
  Atlas.Core.Style.Syntax,
  Atlas.Core.Style.Wrap,
  Atlas.Core.Style.Scaling,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Presentation;

function Positions(const AValues: TArray<Integer>): string;
var
  Value: Integer;
begin
  Result := '';
  for Value in AValues do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + Value.ToString;
  end;
end;

function Item(const AName: string; AKind: TAtlasItemKind; const ASignature: string = ''): TAtlasCompletionItem;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AName;
  Result.Kind := AKind;
  Result.Signature := ASignature;
  Result.UnitUsed := True;
end;

{ TAtlasColorTests }

procedure TAtlasColorTests.HexRoundTrip;
var
  Color: TAtlasColor;
begin
  Color := TAtlasColorMath.FromHex('#0D5EAF');
  Assert.AreEqual(Integer($0D), Integer(TAtlasColorMath.Red(Color)));
  Assert.AreEqual(Integer($5E), Integer(TAtlasColorMath.Green(Color)));
  Assert.AreEqual(Integer($AF), Integer(TAtlasColorMath.Blue(Color)));
  // Format von TColor: $00BBGGRR.
  Assert.AreEqual(Cardinal($00AF5E0D), Cardinal(Color));
  Assert.AreEqual('#0D5EAF', TAtlasColorMath.ToHex(Color));
end;

procedure TAtlasColorTests.RejectsInvalidHex;
begin
  Assert.WillRaise(
    procedure
    begin
      TAtlasColorMath.FromHex('0D5EAF');
    end, EConvertError);
  Assert.WillRaise(
    procedure
    begin
      TAtlasColorMath.FromHex('#0D5EAG');
    end, EConvertError);
end;

procedure TAtlasColorTests.MixesLikeTranslucentLayer;
var
  Mixed: TAtlasColor;
begin
  // rgba(13,94,175,.12) über Weiß wie im Entwurf.
  Mixed := TAtlasColorMath.Mix(TAtlasColorMath.FromHex('#0D5EAF'), TAtlasColorMath.FromHex('#FFFFFF'), 0.12);
  Assert.AreEqual('#E2ECF5', TAtlasColorMath.ToHex(Mixed));
  Assert.AreEqual('#FFFFFF', TAtlasColorMath.ToHex(TAtlasColorMath.Mix(0, TAtlasColorMath.FromHex('#FFFFFF'), 0)));
  Assert.AreEqual('#000000', TAtlasColorMath.ToHex(TAtlasColorMath.Mix(0, TAtlasColorMath.FromHex('#FFFFFF'), 1)));
end;

procedure TAtlasColorTests.ContrastOfBlackAndWhiteIs21;
begin
  Assert.AreEqual(21.0, TAtlasColorMath.Contrast(TAtlasColorMath.FromHex('#000000'),
    TAtlasColorMath.FromHex('#FFFFFF')), 0.001);
  Assert.AreEqual(1.0, TAtlasColorMath.Contrast(TAtlasColorMath.FromHex('#777777'),
    TAtlasColorMath.FromHex('#777777')), 0.001);
  // Bekannter Wert: #767676 auf Weiß ist knapp 4,5 : 1.
  Assert.AreEqual(4.54, TAtlasColorMath.Contrast(TAtlasColorMath.FromHex('#767676'),
    TAtlasColorMath.FromHex('#FFFFFF')), 0.01);
end;

procedure TAtlasColorTests.HslRoundTripAndLighten;
var
  Hex: string;
  HSL: TAtlasHSL;
begin
  for Hex in ['#0D5EAF', '#1B2230', '#FCEBDD', '#000000', '#FFFFFF', '#24634B'] do
    Assert.AreEqual(Hex, TAtlasColorMath.ToHex(TAtlasHSL.FromColor(TAtlasColorMath.FromHex(Hex)).ToColor), Hex);
  HSL := TAtlasHSL.FromColor(TAtlasColorMath.FromHex('#0D5EAF'));
  Assert.AreEqual(210.0, HSL.H, 1.0);
  Assert.IsTrue(TAtlasColorMath.Luminance(TAtlasColorMath.Lighten(TAtlasColorMath.FromHex('#0D5EAF'), 0.2)) >
    TAtlasColorMath.Luminance(TAtlasColorMath.FromHex('#0D5EAF')));
  Assert.IsTrue(TAtlasColorMath.Luminance(TAtlasColorMath.Darken(TAtlasColorMath.FromHex('#0D5EAF'), 0.2)) <
    TAtlasColorMath.Luminance(TAtlasColorMath.FromHex('#0D5EAF')));
end;

procedure TAtlasColorTests.DetectsDarkBackgrounds;
begin
  Assert.IsTrue(TAtlasColorMath.IsDark(TAtlasColorMath.FromHex('#1E1E1E')));
  Assert.IsTrue(TAtlasColorMath.IsDark(TAtlasColorMath.FromHex('#2B2B2B')));
  Assert.IsFalse(TAtlasColorMath.IsDark(TAtlasColorMath.FromHex('#FFFFFF')));
  // "Mountain Mist" der IDE: hellgrau.
  Assert.IsFalse(TAtlasColorMath.IsDark(TAtlasColorMath.FromHex('#E8E8EC')));
end;

procedure TAtlasColorTests.DeltaE2000MatchesReference;
begin
  // Prüfdaten von Sharma, Wu und Dalal (2005), Paare 1, 3, 7 und 17.
  Assert.AreEqual(2.0425, TAtlasColorMath.DeltaE2000(TAtlasLab.Create(50, 2.6772, -79.7751),
    TAtlasLab.Create(50, 0, -82.7485)), 0.0001);
  Assert.AreEqual(1.0, TAtlasColorMath.DeltaE2000(TAtlasLab.Create(50, -1.3802, -84.2814),
    TAtlasLab.Create(50, 0, -82.7485)), 0.0001);
  Assert.AreEqual(1.2644, TAtlasColorMath.DeltaE2000(TAtlasLab.Create(60.2574, -34.0099, 36.2677),
    TAtlasLab.Create(60.4626, -34.1751, 39.4387)), 0.0001);
  Assert.AreEqual(27.1492, TAtlasColorMath.DeltaE2000(TAtlasLab.Create(50, 2.5, 0),
    TAtlasLab.Create(73, 25, -18)), 0.0001);
  Assert.AreEqual(100.0, TAtlasColorMath.DeltaE2000(TAtlasColorMath.FromHex('#000000'),
    TAtlasColorMath.FromHex('#FFFFFF')), 0.01);
end;

{ TAtlasPaletteTests }

procedure TAtlasPaletteTests.CheckPairs(const AColors: TAtlasColors; const AMode: string; const ABackgrounds,
  ATexts: array of string);
var
  Index: Integer;
  Pair, Other: TAtlasColor;
  Hex: string;
  Name: string;

  procedure CheckText(AText: TAtlasColor);
  begin
    Assert.IsTrue((TAtlasColorMath.Contrast(Pair, AText) >= 1.8) or
      (TAtlasColorMath.DeltaE2000(Pair, AText) >= 30), Name + ' gegen Text ' + TAtlasColorMath.ToHex(AText));
  end;

begin
  // Regeln aus #653: lesbar auf dem Hintergrund, vom normalen Text und von der Nachbartiefe verschieden.
  for Index := 0 to High(AColors.Pairs) do
  begin
    Pair := AColors.Pairs[Index];
    Name := Format('%s Paar %d (%s)', [AMode, Index, TAtlasColorMath.ToHex(Pair)]);
    for Hex in ABackgrounds do
      Assert.IsTrue(TAtlasColorMath.Contrast(Pair, TAtlasColorMath.FromHex(Hex)) >= 4.5,
        Name + ' auf ' + Hex);
    Assert.IsTrue(TAtlasColorMath.Contrast(Pair, AColors.Surface) >= 4.5, Name + ' auf Surface');
    for Hex in ATexts do
      CheckText(TAtlasColorMath.FromHex(Hex));
    CheckText(AColors.Text);
    Other := AColors.Pairs[(Index + 1) mod Length(AColors.Pairs)];
    Assert.IsTrue(TAtlasColorMath.DeltaE2000(Pair, Other) >= 20, Name + ' gegen die nächste Tiefe');
    // Unpaarige erkennt man am roten Grund, nicht an der Schriftfarbe: Paarfarben dürfen rot sein.
  end;
end;

procedure TAtlasPaletteTests.LightPairsStandOut;
begin
  // Editor hell: weißer Hintergrund, schwarzer Text, dunkelblaue Schlüsselwörter.
  CheckPairs(TAtlasColors.Light, 'Hell', ['#FFFFFF'], ['#000000', '#000080']);
end;

procedure TAtlasPaletteTests.DarkPairsStandOut;
begin
  // Editor dunkel: Hintergrund und Text des dunklen Schemas der IDE.
  CheckPairs(TAtlasColors.Dark, 'Dunkel', ['#1E1E1E', '#2B2B2B'], ['#D4D4D4', '#FFFFFF']);
end;

procedure TAtlasPaletteTests.PlaceholderColorsDiffer;

  procedure Check(const AColors: TAtlasColors; const AMode: string);
  var
    Index, Other: Integer;
  begin
    for Index := 0 to High(AColors.Placeholders) do
    begin
      Assert.IsTrue(TAtlasColorMath.DeltaE2000(AColors.Placeholders[Index], AColors.Error) >= 20,
        Format('%s Platzhalter %d gegen Fehler', [AMode, Index]));
      for Other := Index + 1 to High(AColors.Placeholders) do
        Assert.IsTrue(TAtlasColorMath.DeltaE2000(AColors.Placeholders[Index], AColors.Placeholders[Other]) >= 15,
          Format('%s Platzhalter %d gegen %d', [AMode, Index, Other]));
    end;
  end;

begin
  Check(TAtlasColors.Light, 'Hell');
  Check(TAtlasColors.Dark, 'Dunkel');
end;

procedure TAtlasPaletteTests.CheckContrast(const AColors: TAtlasColors; const AMode: string);

  procedure Pair(const AName: string; AFront, ABack: TAtlasColor);
  var
    Ratio: Double;
  begin
    Ratio := TAtlasColorMath.Contrast(AFront, ABack);
    Assert.IsTrue(Ratio >= 4.5, Format('%s %s: %s auf %s nur %.2f : 1', [AMode, AName,
      TAtlasColorMath.ToHex(AFront), TAtlasColorMath.ToHex(ABack), Ratio]));
  end;

var
  Kind: TAtlasBadgeKind;
  Index: Integer;
begin
  Pair('Text', AColors.Text, AColors.Surface);
  Pair('Text auf Auswahl', AColors.Text, AColors.Selection);
  Pair('Text auf Gutter', AColors.Text, AColors.Gutter);
  Pair('Gedämpft', AColors.Muted, AColors.Surface);
  Pair('Gedämpft auf Gutter', AColors.Muted, AColors.Gutter);
  Pair('Gedämpft auf Auswahl', AColors.Muted, AColors.Selection);
  Pair('Akzent', AColors.Accent, AColors.Surface);
  Pair('Akzent auf Auswahl', AColors.Accent, AColors.Selection);
  Pair('Akzent auf Akzentfläche', AColors.Accent, AColors.AccentSoft);
  Pair('Akzent auf Gutter', AColors.Accent, AColors.Gutter);
  Pair('Schlüsselwort', AColors.Keyword, AColors.Surface);
  Pair('String', AColors.StringLiteral, AColors.Surface);
  Pair('Hinzufügen', AColors.Add, AColors.Surface);
  Pair('Hinzufügen auf Auswahl', AColors.Add, AColors.Selection);
  Pair('Warnung', AColors.Warn, AColors.Surface);
  Pair('Warnung auf Gutter', AColors.Warn, AColors.Gutter);
  Pair('Warnung auf Warnfläche', AColors.Warn, AColors.WarnSoft);
  Pair('Fehler', AColors.Error, AColors.Surface);
  // Klammer- und Blockpaare (#514): jede Tiefe lesbar.
  for Index := 0 to High(AColors.Pairs) do
    Pair('Paar ' + IntToStr(Index), AColors.Pairs[Index], AColors.Surface);
  Pair('Fehler auf Fehlerfläche', AColors.Error, AColors.ErrorSoft);
  Pair('Fehler auf Gutter', AColors.Error, AColors.Gutter);
  for Kind := Low(TAtlasBadgeKind) to High(TAtlasBadgeKind) do
    Pair('Badge ' + Ord(Kind).ToString, AColors.Badges[Kind].Text, AColors.Badges[Kind].Background);
end;

procedure TAtlasPaletteTests.LightRolesMeetContrast;
begin
  CheckContrast(TAtlasColors.Light, 'Hell');
end;

procedure TAtlasPaletteTests.DarkRolesMeetContrast;
begin
  CheckContrast(TAtlasColors.Dark, 'Dunkel');
end;

procedure TAtlasPaletteTests.AccentIsGreekBlue;
begin
  Assert.AreEqual('#0D5EAF', TAtlasColorMath.ToHex(TAtlasColors.Light.Accent));
  Assert.AreEqual('#5B9BE6', TAtlasColorMath.ToHex(TAtlasColors.Dark.Accent));
end;

procedure TAtlasPaletteTests.BadgeKindsDifferInLightness;

  procedure Check(const AColors: TAtlasColors; const AMode: string);
  begin
    // Funktion und Typ teilen den Farbton, unterscheiden sich aber in der Helligkeit (#421).
    Assert.IsTrue(TAtlasColorMath.Contrast(AColors.Badges[TAtlasBadgeKind.Function_].Background,
      AColors.Badges[TAtlasBadgeKind.Type_].Background) >= 1.15, AMode);
    Assert.AreNotEqual(Cardinal(AColors.Badges[TAtlasBadgeKind.Function_].Background),
      Cardinal(AColors.Badges[TAtlasBadgeKind.Procedure_].Background), AMode);
  end;

begin
  Check(TAtlasColors.Light, 'Hell');
  Check(TAtlasColors.Dark, 'Dunkel');
end;

procedure TAtlasPaletteTests.ChoosesModeByBackground;
begin
  Assert.IsTrue(TAtlasColors.ForBackground(TAtlasColorMath.FromHex('#1E1E1E')).IsDark);
  Assert.IsFalse(TAtlasColors.ForBackground(TAtlasColorMath.FromHex('#FFFFFF')).IsDark);
  Assert.IsTrue(TAtlasColors.Dark.IsDark);
  Assert.IsFalse(TAtlasColors.Light.IsDark);
end;

{ TAtlasScalingTests }

procedure TAtlasScalingTests.NormalCaretIsNoZoom;
begin
  // Caret so hoch wie der Text oder mit Zeilenabstand: 100 %.
  Assert.AreEqual(1.0, TAtlasScaling.ZoomFromCaret(15, 15), 0.001);
  Assert.AreEqual(1.0, TAtlasScaling.ZoomFromCaret(17, 15), 0.001);
  Assert.AreEqual(1.0, TAtlasScaling.ZoomFromCaret(14, 15), 0.001);
end;

procedure TAtlasScalingTests.LargerCaretIsZoom;
begin
  // 150 % mit Zeilenabstand von einem Achtel: Caret 1,5 × 1,125 × Text.
  Assert.AreEqual(1.5, TAtlasScaling.ZoomFromCaret(Round(15 * 1.5 * 1.125), 15), 0.05);
  Assert.AreEqual(2.0, TAtlasScaling.ZoomFromCaret(Round(15 * 2 * 1.125), 15), 0.05);
  // Verkleinert.
  Assert.AreEqual(0.6, TAtlasScaling.ZoomFromCaret(9, 15), 0.01);
end;

procedure TAtlasScalingTests.ClampsAndIgnoresInvalidValues;
begin
  Assert.AreEqual(1.0, TAtlasScaling.ZoomFromCaret(0, 15), 0.001);
  Assert.AreEqual(1.0, TAtlasScaling.ZoomFromCaret(15, 0), 0.001);
  Assert.AreEqual(TAtlasScaling.MaxZoom, TAtlasScaling.ZoomFromCaret(500, 10), 0.001);
  Assert.AreEqual(TAtlasScaling.MinZoom, TAtlasScaling.ZoomFromCaret(2, 15), 0.001);
end;

{ TAtlasSyntaxTests }

function Describe(const AText: string): string;
var
  Token: TAtlasToken;
const
  Names: array[TAtlasTokenKind] of string = ('p', 'k', 's', 'c', 'n');
begin
  Result := '';
  for Token in TAtlasSyntax.Tokens(AText) do
    Result := Result + Names[Token.Kind] + ':' + Copy(AText, Token.Start + 1, Token.Stop - Token.Start) + '|';
end;

procedure TAtlasSyntaxTests.ColorsKeywordsAndStrings;
begin
  Assert.AreEqual('k:function|p: Add(|k:const|p: S: |k:string|p:): Integer|',
    Describe('function Add(const S: string): Integer'));
  Assert.AreEqual('k:procedure|p: Log(Msg: |k:string|p: = |s:''x''|p:; Level: Integer = |n:1|p:)|',
    Describe('procedure Log(Msg: string = ''x''; Level: Integer = 1)'));
  Assert.AreEqual('k:property|p: Count: Integer |k:read|p: GetCount; |c:{ Anzahl }|',
    Describe('property Count: Integer read GetCount; { Anzahl }'));
end;

procedure TAtlasSyntaxTests.TokensCoverWholeText;
var
  Text: string;
  Tokens: TAtlasTokens;
  Index: Integer;
begin
  for Text in ['', 'x', 'function F(''unclosed', '{ offen', 'a // Rest', 'const Ä: Byte = $FF;'] do
  begin
    Tokens := TAtlasSyntax.Tokens(Text);
    if Text = '' then
    begin
      Assert.AreEqual(0, Integer(Length(Tokens)));
      Continue;
    end;
    Assert.AreEqual(0, Tokens[0].Start, Text);
    for Index := 1 to High(Tokens) do
      Assert.AreEqual(Tokens[Index - 1].Stop, Tokens[Index].Start, Text);
    Assert.AreEqual(Integer(Length(Text)), Tokens[High(Tokens)].Stop, Text);
  end;
end;

procedure TAtlasSyntaxTests.NameAfterDotIsNoKeyword;
begin
  Assert.AreEqual('k:constructor|p: TFoo.Create(Owner: TComponent)|',
    Describe('constructor TFoo.Create(Owner: TComponent)'));
  Assert.AreEqual('p:Stream.Read(Buffer)|', Describe('Stream.Read(Buffer)'));
end;

function Defaults(const ASignature: string): string;
var
  Range: TPoint;
begin
  Result := '';
  for Range in TAtlasSyntax.DefaultRanges(ASignature) do
    Result := Result + '[' + Copy(ASignature, Range.X + 1, Range.Y - Range.X) + ']';
end;

procedure TAtlasSyntaxTests.FindsDefaultValues;
begin
  Assert.AreEqual('[ = 1]', Defaults('function Pos(const SubStr, Str: string; Offset: Integer = 1): Integer'));
  Assert.AreEqual('[ = ''a;b''][ = 1]', Defaults('procedure Log(Msg: string = ''a;b''; Level: Integer = 1)'));
  Assert.AreEqual('[ = nil][ = []]', Defaults('procedure P(A: TFoo = nil; B: TArray<Integer> = [])'));
  Assert.AreEqual('', Defaults('procedure X(A: array of Integer)'));
  Assert.AreEqual('', Defaults('property Items[Index: Integer]: string read Get; default;'));
end;

procedure TAtlasSyntaxTests.ParenStarIsComment;
begin
  Assert.AreEqual('k:begin|p: |c:(* alt *)|p: X|', Describe('begin (* alt *) X'));
  Assert.AreEqual('p:Add(A)|', Describe('Add(A)'));
end;

function DescribeLines(const ALines: TArray<string>): string;
var
  Lines: TArray<TAtlasTokens>;
  Line: Integer;
  Token: TAtlasToken;
const
  Names: array[TAtlasTokenKind] of string = ('p', 'k', 's', 'c', 'n');
begin
  Result := '';
  Lines := TAtlasSyntax.LineTokens(ALines);
  for Line := 0 to High(Lines) do
  begin
    for Token in Lines[Line] do
      Result := Result + Names[Token.Kind] + ':' + Copy(ALines[Line], Token.Start + 1, Token.Stop - Token.Start) + '|';
    Result := Result + '/';
  end;
end;

procedure TAtlasSyntaxTests.CommentsSpanLines;
begin
  Assert.AreEqual('k:begin|p: |c:{ eins|/c:zwei|/c:drei }|p: X;|/k:end|p:;|/',
    DescribeLines(['begin { eins', 'zwei', 'drei } X;', 'end;']));
  Assert.AreEqual('c:(* a|/c:*)|p: |k:if|/',
    DescribeLines(['(* a', '*) if']));
  // Im String und nach // öffnet "{" keinen Kommentar.
  Assert.AreEqual('p:S := |s:''{''|p:;|/p:X|/',
    DescribeLines(['S := ''{'';', 'X']));
  Assert.AreEqual('p:X; |c:// {|/k:end|/',
    DescribeLines(['X; // {', 'end']));
  Assert.AreEqual('/c:{|/', DescribeLines(['', '{']));
end;

{ TAtlasPresentationTests }

procedure TAtlasPresentationTests.BadgesFollowKind;
begin
  Assert.AreEqual('fn', TAtlasItemPresentation.Badge(Item('Length', TAtlasItemKind.Function_)).Code);
  Assert.AreEqual('pr', TAtlasItemPresentation.Badge(Item('Clear', TAtlasItemKind.Procedure_)).Code);
  Assert.AreEqual('pp', TAtlasItemPresentation.Badge(Item('Count', TAtlasItemKind.Property_)).Code);
  Assert.AreEqual('fd', TAtlasItemPresentation.Badge(Item('FCount', TAtlasItemKind.Field)).Code);
  Assert.AreEqual('ev', TAtlasItemPresentation.Badge(Item('OnClick', TAtlasItemKind.Event)).Code);
  Assert.AreEqual('co', TAtlasItemPresentation.Badge(Item('alClient', TAtlasItemKind.EnumMember)).Code);
  Assert.AreEqual('ty', TAtlasItemPresentation.Badge(Item('TStringList', TAtlasItemKind.Class_)).Code);
  Assert.AreEqual('va', TAtlasItemPresentation.Badge(Item('Total', TAtlasItemKind.Variable)).Code);
  Assert.AreEqual('un', TAtlasItemPresentation.Badge(Item('System.Classes', TAtlasItemKind.Unit_)).Code);
  Assert.AreEqual('sn', TAtlasItemPresentation.Badge(Item('tryf', TAtlasItemKind.Snippet)).Code);
  Assert.AreEqual('fn', TAtlasItemPresentation.Badge(Item('Create', TAtlasItemKind.Constructor_)).Code);
  Assert.AreEqual('pr', TAtlasItemPresentation.Badge(Item('Destroy', TAtlasItemKind.Destructor_)).Code);
  Assert.IsTrue(TAtlasItemPresentation.Badge(Item('TStringList', TAtlasItemKind.Class_)).Kind =
    TAtlasBadgeKind.Type_);
end;

procedure TAtlasPresentationTests.MethodBadgeFollowsSignature;
begin
  Assert.AreEqual('pr', TAtlasItemPresentation.Badge(Item('Add', TAtlasItemKind.Method,
    'procedure Add(const S: string)')).Code);
  Assert.AreEqual('fn', TAtlasItemPresentation.Badge(Item('Add', TAtlasItemKind.Method,
    'function Add(const S: string): Integer')).Code);
  // Ohne Signatur: Funktion.
  Assert.AreEqual('fn', TAtlasItemPresentation.Badge(Item('Add', TAtlasItemKind.Method)).Code);
end;

procedure TAtlasPresentationTests.AttributeBadge;
var
  Entry: TAtlasCompletionItem;
begin
  // Attribut nach "[" (#465): "at" statt "ty", auch bei Compiler-Attributen (Art Schlüsselwort).
  Entry := Item('TestCase', TAtlasItemKind.Class_);
  Entry.Attribute := True;
  Assert.AreEqual('at', TAtlasItemPresentation.Badge(Entry).Code);
  Entry := Item('weak', TAtlasItemKind.Keyword);
  Entry.Attribute := True;
  Assert.AreEqual('at', TAtlasItemPresentation.Badge(Entry).Code);
  Assert.AreEqual('ty', TAtlasItemPresentation.Badge(Item('TKunde', TAtlasItemKind.Class_)).Code);
end;

procedure TAtlasPresentationTests.MethodRefTag;
var
  Entry: TAtlasCompletionItem;
begin
  // Gerüst einer anonymen Methode (#468): Badge "sn" der Vorlage, Tag mit dem erwarteten Typ.
  Entry := Item('function(const Value: TCustomer): Boolean', TAtlasItemKind.Snippet);
  Entry.MethodRef := 'TPredicate<TCustomer>';
  Assert.AreEqual('sn', TAtlasItemPresentation.Badge(Entry).Code);
  Assert.AreEqual('TPredicate<TCustomer>', TAtlasItemPresentation.TagText(Entry));
  Assert.AreEqual('', TAtlasItemPresentation.TagText(Item('procedure', TAtlasItemKind.Snippet)));
end;

procedure TAtlasPresentationTests.WithOriginAndShadowTags;
var
  Entry: TAtlasCompletionItem;
  Tags: TAtlasTags;
begin
  // with-Objekt (#481): „aus …“, dann je verdecktem Namen eine Warnmarke mit Fläche.
  Entry := Item('Name', TAtlasItemKind.Field);
  Entry.Scope := 6;
  Entry.WithOrigin := 'qryOrders';
  Entry.WithShadows := ['Self.Name', 'lokale Variable Name'];
  Tags := TAtlasItemPresentation.Tags(Entry);
  Assert.AreEqual('aus qryOrders, verdeckt Self.Name, verdeckt lokale Variable Name',
    TAtlasItemPresentation.TagText(Entry));
  Assert.AreEqual(Ord(TAtlasTagKind.Accent), Ord(Tags[0].Kind));
  Assert.IsFalse(Tags[0].Filled);
  Assert.AreEqual(Ord(TAtlasTagKind.Warn), Ord(Tags[1].Kind));
  Assert.IsTrue(Tags[1].Filled);
  // Ohne Verdeckung nur die Herkunft.
  Entry.WithShadows := nil;
  Assert.AreEqual('aus qryOrders', TAtlasItemPresentation.TagText(Entry));
end;

procedure TAtlasPresentationTests.MissingUnitBecomesTag;
var
  Entry: TAtlasCompletionItem;
  Edit: TAtlasTextEdit;
  Tags: TAtlasTags;
begin
  Entry := Item('TStringList', TAtlasItemKind.Class_, 'System.Classes (uses ergänzen)');
  Entry.UnitUsed := False;
  Assert.AreEqual('System.Classes', TAtlasItemPresentation.MissingUnit(Entry));
  Assert.AreEqual('', TAtlasItemPresentation.Detail(Entry));
  Tags := TAtlasItemPresentation.Tags(Entry);
  Assert.AreEqual(1, Integer(Length(Tags)));
  Assert.AreEqual('+ System.Classes', Tags[0].Text);
  Assert.IsTrue(Tags[0].Kind = TAtlasTagKind.Add);
  // Ohne Hinweis im Detail: aus der uses-Ergänzung.
  Entry := Item('TStringList', TAtlasItemKind.Class_, 'TStringList');
  Entry.UnitUsed := False;
  Edit := Default(TAtlasTextEdit);
  Edit.NewText := ', System.Classes';
  Entry.AdditionalEdits := [Edit];
  Assert.AreEqual('System.Classes', TAtlasItemPresentation.MissingUnit(Entry));
  Edit.NewText := sLineBreak + 'uses' + sLineBreak + '  System.Classes;';
  Entry.AdditionalEdits := [Edit];
  Assert.AreEqual('System.Classes', TAtlasItemPresentation.MissingUnit(Entry));
  // Eingebunden: keine Marke.
  Entry.UnitUsed := True;
  Assert.AreEqual('', TAtlasItemPresentation.MissingUnit(Entry));
  Assert.AreEqual(0, Integer(Length(TAtlasItemPresentation.Tags(Entry))));
end;

procedure TAtlasPresentationTests.UnitDetailIsFileName;
begin
  Assert.AreEqual('System.Classes.pas', TAtlasItemPresentation.Detail(Item('System.Classes', TAtlasItemKind.Unit_,
    'C:\Program Files\Embarcadero\source\rtl\common\System.Classes.pas')));
  Assert.AreEqual(': Integer', TAtlasItemPresentation.Detail(Item('Count', TAtlasItemKind.Property_, ': Integer')));
end;

procedure TAtlasPresentationTests.DeprecatedAndConstructorTags;
var
  Entry: TAtlasCompletionItem;
  Tags: TAtlasTags;
begin
  Entry := Item('Create', TAtlasItemKind.Constructor_);
  Entry.Directives := ['overload', 'deprecated'];
  Tags := TAtlasItemPresentation.Tags(Entry);
  Assert.AreEqual(2, Integer(Length(Tags)));
  Assert.AreEqual('constructor', Tags[0].Text);
  Assert.AreEqual('deprecated', Tags[1].Text);
  Assert.IsTrue(Tags[1].Kind = TAtlasTagKind.Warn);
end;

procedure TAtlasPresentationTests.ScopeTagsNameOrigin;

  function TagOf(const AName: string; AKind: TAtlasItemKind; AScope: Integer; const AClass: string = '';
    const AUnit: string = ''): string;
  var
    Entry: TAtlasCompletionItem;
    Tags: TAtlasTags;
  begin
    Entry := Item(AName, AKind);
    Entry.Scope := AScope;
    Entry.DeclaringClass := AClass;
    Entry.DeclaringUnit := AUnit;
    Tags := TAtlasItemPresentation.Tags(Entry);
    if Length(Tags) = 0 then
      Exit('');
    Result := Tags[0].Text;
  end;

begin
  // #488: woher ein Name ohne Punkt davor stammt.
  Assert.AreEqual('lokal', TagOf('Total', TAtlasItemKind.Variable, 1));
  Assert.AreEqual('Parameter', TagOf('ACustomer', TAtlasItemKind.Variable, 2));
  Assert.AreEqual('Feld', TagOf('FDiscount', TAtlasItemKind.Field, 3, 'TKasse'));
  Assert.AreEqual('Eigenschaft', TagOf('Discount', TAtlasItemKind.Property_, 3, 'TKasse'));
  Assert.AreEqual('TKasse', TagOf('Calc', TAtlasItemKind.Method, 3, 'TKasse'));
  Assert.AreEqual('Unit', TagOf('TKasse', TAtlasItemKind.Class_, 4));
  Assert.AreEqual('System.SysUtils', TagOf('Format', TAtlasItemKind.Method, 5, '', 'System.SysUtils'));
  // Nach einem Punkt keine Herkunft.
  Assert.AreEqual('', TagOf('Count', TAtlasItemKind.Property_, 0, 'TStrings'));
end;

procedure TAtlasPresentationTests.HighlightsPrefixWordStartsSubstringSubsequence;
begin
  Assert.AreEqual('1,2,3', Positions(TAtlasItemPresentation.Highlights('tst', 'TStringList')));
  Assert.AreEqual('1,2,8', Positions(TAtlasItemPresentation.Highlights('TSL', 'TStringList')));
  Assert.AreEqual('4,5,6', Positions(TAtlasItemPresentation.Highlights('rin', 'TStringList')));
  Assert.AreEqual('2,3,8', Positions(TAtlasItemPresentation.Highlights('stl', 'TStringList')));
  Assert.AreEqual('1,2,3,4,5,6', Positions(TAtlasItemPresentation.Highlights('length', 'Length')));
end;

procedure TAtlasPresentationTests.NoHighlightsWithoutMatch;
begin
  Assert.AreEqual('', Positions(TAtlasItemPresentation.Highlights('xyz', 'TStringList')));
  Assert.AreEqual('', Positions(TAtlasItemPresentation.Highlights('', 'TStringList')));
  // Verstreute Treffer zählen nicht (wie beim Filtern).
  Assert.AreEqual('', Positions(TAtlasItemPresentation.Highlights('myLis', 'ERROR_TOO_MANY_LINKS')));
end;

procedure TAtlasPaletteTests.InlayHintColorsMixFromBackground;
var
  Back: TAtlasColor;
  Colors: TAtlasColors;
  Hint: TAtlasHintColors;
begin
  // Hell: Rollen der hellen Palette, gemischt mit den bisherigen Anteilen 0,8 / 0,45 / 0,2.
  Back := TAtlasColorMath.FromHex('#FFFFFF');
  Colors := TAtlasColors.Light;
  Hint := TAtlasColors.InlayHint(Back);
  Assert.AreEqual(TAtlasColorMath.Mix(Colors.Text, Back, 0.8), Hint.Text);
  Assert.AreEqual(TAtlasColorMath.Mix(Colors.Accent, Back, 0.45), Hint.Pen);
  Assert.AreEqual(TAtlasColorMath.Mix(Colors.Accent, Back, 0.2), Hint.Fill);
  // Dunkel: Rollen der dunklen Palette.
  Back := TAtlasColorMath.FromHex('#1E1E1E');
  Colors := TAtlasColors.Dark;
  Hint := TAtlasColors.InlayHint(Back);
  Assert.AreEqual(TAtlasColorMath.Mix(Colors.Text, Back, 0.8), Hint.Text);
  Assert.AreEqual(TAtlasColorMath.Mix(Colors.Accent, Back, 0.2), Hint.Fill);
end;

procedure TAtlasPaletteTests.ChromeColorsFollowTheIdeToolbar;
var
  Face, Text: TAtlasColor;
  Colors: TAtlasColors;
begin
  // Dunkles IDE-Thema: Fläche der Werkzeugleiste statt des fast schwarzen Gutter der Palette.
  Face := TAtlasColorMath.FromHex('#2D2D30');
  Text := TAtlasColorMath.FromHex('#F1F1F1');
  Colors := TAtlasColors.ForChrome(Face, Text);
  Assert.IsTrue(Colors.IsDark);
  Assert.AreEqual(Face, Colors.Gutter);
  Assert.AreEqual(Face, Colors.Surface);
  Assert.AreEqual(Text, Colors.Text);
  Assert.AreEqual(TAtlasColorMath.Mix(Text, Face, 0.7), Colors.Muted);
  Assert.AreEqual(TAtlasColorMath.Mix(Text, Face, 0.18), Colors.Line);
  Assert.AreEqual(TAtlasColors.Dark.Badges[TAtlasBadgeKind.Type_].Background,
    Colors.Badges[TAtlasBadgeKind.Type_].Background, 'Badges aus der dunklen Palette');
  Assert.IsTrue(TAtlasColorMath.Contrast(Colors.Muted, Face) >= 4.5, 'gedämpfter Text lesbar');
  // Helles Thema.
  Face := TAtlasColorMath.FromHex('#F0F0F0');
  Text := TAtlasColorMath.FromHex('#000000');
  Colors := TAtlasColors.ForChrome(Face, Text);
  Assert.IsFalse(Colors.IsDark);
  Assert.AreEqual(Face, Colors.Gutter);
  Assert.IsTrue(TAtlasColorMath.Contrast(Colors.Muted, Face) >= 4.5, 'gedämpfter Text lesbar (hell)');
  Assert.AreNotEqual(Face, Colors.Selection, 'Auswahl abgesetzt');
end;

{ TAtlasWrapTests }

function TAtlasWrapTests.Cum(const AText: string): TArray<Integer>;
var
  Index: Integer;
begin
  // Jedes Zeichen 10 Pixel breit.
  Result := nil;
  SetLength(Result, Length(AText) + 1);
  for Index := 0 to Length(AText) do
    Result[Index] := 10 * Index;
end;

procedure TAtlasWrapTests.WrapFitsOneLine;
var
  Lines: TArray<TPoint>;
begin
  Lines := TAtlasWrap.AtSpaces('a bc d', Cum('a bc d'), 100, 0);
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.AreEqual(0, Lines[0].X);
  Assert.AreEqual(6, Lines[0].Y);
end;

procedure TAtlasWrapTests.WrapBreaksAtSpace;
var
  Lines: TArray<TPoint>;
begin
  // „procedure Foo(A: Integer)“: 25 Zeichen, Breite 150 = 15 Zeichen.
  Lines := TAtlasWrap.AtSpaces('procedure Foo(A: Integer)', Cum('procedure Foo(A: Integer)'), 150, 0);
  Assert.AreEqual(2, Integer(Length(Lines)));
  Assert.AreEqual(0, Lines[0].X);
  Assert.AreEqual(10, Lines[0].Y);
  Assert.AreEqual(10, Lines[1].X);
  Assert.AreEqual(25, Lines[1].Y);
end;

procedure TAtlasWrapTests.WrapIndentNarrowsFollowLines;
var
  Lines: TArray<TPoint>;
begin
  // Erste Zeile 8 Zeichen, Folgezeilen um 3 Zeichen schmaler (5).
  Lines := TAtlasWrap.AtSpaces('aa bb cc dd ee', Cum('aa bb cc dd ee'), 80, 30);
  Assert.AreEqual(3, Integer(Length(Lines)));
  Assert.IsTrue(Lines[0] = Point(0, 6));
  Assert.IsTrue(Lines[1] = Point(6, 9));
  Assert.IsTrue(Lines[2] = Point(9, 14));
end;

procedure TAtlasWrapTests.WrapLongWordStandsAlone;
var
  Lines: TArray<TPoint>;
begin
  Lines := TAtlasWrap.AtSpaces('a Sehrlangeswort b', Cum('a Sehrlangeswort b'), 50, 0);
  Assert.AreEqual(3, Integer(Length(Lines)));
  Assert.IsTrue(Lines[0] = Point(0, 2));
  Assert.IsTrue(Lines[1] = Point(2, 17));
  Assert.IsTrue(Lines[2] = Point(17, 18));
end;

procedure TAtlasWrapTests.WrapEmptyText;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasWrap.AtSpaces('', Cum(''), 100, 0))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasColorTests);
  TDUnitX.RegisterTestFixture(TAtlasWrapTests);
  TDUnitX.RegisterTestFixture(TAtlasPaletteTests);
  TDUnitX.RegisterTestFixture(TAtlasScalingTests);
  TDUnitX.RegisterTestFixture(TAtlasSyntaxTests);
  TDUnitX.RegisterTestFixture(TAtlasPresentationTests);

end.
