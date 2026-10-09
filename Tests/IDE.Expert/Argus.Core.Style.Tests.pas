unit Argus.Core.Style.Tests;

// Tests für Farben, Palette, Syntaxfärbung und Darstellung der Einträge (#411, #420, #421).

interface

uses
  DUnitX.TestFramework,
  Argus.Core.Style.Color,
  Argus.Core.Style.Palette;

type
  [TestFixture]
  TArgusColorTests = class
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
  end;

  [TestFixture]
  TArgusPaletteTests = class
  private
    procedure CheckContrast(const AColors: TArgusColors; const AMode: string);
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
  end;

  [TestFixture]
  TArgusScalingTests = class
  public
    [Test]
    procedure NormalCaretIsNoZoom;
    [Test]
    procedure LargerCaretIsZoom;
    [Test]
    procedure ClampsAndIgnoresInvalidValues;
  end;

  [TestFixture]
  TArgusSyntaxTests = class
  public
    [Test]
    procedure ColorsKeywordsAndStrings;
    [Test]
    procedure TokensCoverWholeText;
    [Test]
    procedure NameAfterDotIsNoKeyword;
  end;

  [TestFixture]
  TArgusPresentationTests = class
  public
    [Test]
    procedure BadgesFollowKind;
    [Test]
    procedure MethodBadgeFollowsSignature;
    [Test]
    procedure MissingUnitBecomesTag;
    [Test]
    procedure UnitDetailIsFileName;
    [Test]
    procedure DeprecatedAndConstructorTags;
    [Test]
    procedure HighlightsPrefixWordStartsSubstringSubsequence;
    [Test]
    procedure NoHighlightsWithoutMatch;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Argus.Core.Style.Syntax,
  Argus.Core.Style.Scaling,
  Argus.Core.Completion.Contract,
  Argus.Core.Completion.Presentation;

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

function Item(const AName: string; AKind: TArgusItemKind; const ASignature: string = ''): TArgusCompletionItem;
begin
  Result := Default(TArgusCompletionItem);
  Result.Name := AName;
  Result.Kind := AKind;
  Result.Signature := ASignature;
  Result.UnitUsed := True;
end;

{ TArgusColorTests }

procedure TArgusColorTests.HexRoundTrip;
var
  Color: TArgusColor;
begin
  Color := TArgusColorMath.FromHex('#0D5EAF');
  Assert.AreEqual(Integer($0D), Integer(TArgusColorMath.Red(Color)));
  Assert.AreEqual(Integer($5E), Integer(TArgusColorMath.Green(Color)));
  Assert.AreEqual(Integer($AF), Integer(TArgusColorMath.Blue(Color)));
  // Format von TColor: $00BBGGRR.
  Assert.AreEqual(Cardinal($00AF5E0D), Cardinal(Color));
  Assert.AreEqual('#0D5EAF', TArgusColorMath.ToHex(Color));
end;

procedure TArgusColorTests.RejectsInvalidHex;
begin
  Assert.WillRaise(
    procedure
    begin
      TArgusColorMath.FromHex('0D5EAF');
    end, EConvertError);
  Assert.WillRaise(
    procedure
    begin
      TArgusColorMath.FromHex('#0D5EAG');
    end, EConvertError);
end;

procedure TArgusColorTests.MixesLikeTranslucentLayer;
var
  Mixed: TArgusColor;
begin
  // rgba(13,94,175,.12) über Weiß wie im Entwurf.
  Mixed := TArgusColorMath.Mix(TArgusColorMath.FromHex('#0D5EAF'), TArgusColorMath.FromHex('#FFFFFF'), 0.12);
  Assert.AreEqual('#E2ECF5', TArgusColorMath.ToHex(Mixed));
  Assert.AreEqual('#FFFFFF', TArgusColorMath.ToHex(TArgusColorMath.Mix(0, TArgusColorMath.FromHex('#FFFFFF'), 0)));
  Assert.AreEqual('#000000', TArgusColorMath.ToHex(TArgusColorMath.Mix(0, TArgusColorMath.FromHex('#FFFFFF'), 1)));
end;

procedure TArgusColorTests.ContrastOfBlackAndWhiteIs21;
begin
  Assert.AreEqual(21.0, TArgusColorMath.Contrast(TArgusColorMath.FromHex('#000000'),
    TArgusColorMath.FromHex('#FFFFFF')), 0.001);
  Assert.AreEqual(1.0, TArgusColorMath.Contrast(TArgusColorMath.FromHex('#777777'),
    TArgusColorMath.FromHex('#777777')), 0.001);
  // Bekannter Wert: #767676 auf Weiß ist knapp 4,5 : 1.
  Assert.AreEqual(4.54, TArgusColorMath.Contrast(TArgusColorMath.FromHex('#767676'),
    TArgusColorMath.FromHex('#FFFFFF')), 0.01);
end;

procedure TArgusColorTests.HslRoundTripAndLighten;
var
  Hex: string;
  HSL: TArgusHSL;
begin
  for Hex in ['#0D5EAF', '#1B2230', '#FCEBDD', '#000000', '#FFFFFF', '#24634B'] do
    Assert.AreEqual(Hex, TArgusColorMath.ToHex(TArgusHSL.FromColor(TArgusColorMath.FromHex(Hex)).ToColor), Hex);
  HSL := TArgusHSL.FromColor(TArgusColorMath.FromHex('#0D5EAF'));
  Assert.AreEqual(210.0, HSL.H, 1.0);
  Assert.IsTrue(TArgusColorMath.Luminance(TArgusColorMath.Lighten(TArgusColorMath.FromHex('#0D5EAF'), 0.2)) >
    TArgusColorMath.Luminance(TArgusColorMath.FromHex('#0D5EAF')));
  Assert.IsTrue(TArgusColorMath.Luminance(TArgusColorMath.Darken(TArgusColorMath.FromHex('#0D5EAF'), 0.2)) <
    TArgusColorMath.Luminance(TArgusColorMath.FromHex('#0D5EAF')));
end;

procedure TArgusColorTests.DetectsDarkBackgrounds;
begin
  Assert.IsTrue(TArgusColorMath.IsDark(TArgusColorMath.FromHex('#1E1E1E')));
  Assert.IsTrue(TArgusColorMath.IsDark(TArgusColorMath.FromHex('#2B2B2B')));
  Assert.IsFalse(TArgusColorMath.IsDark(TArgusColorMath.FromHex('#FFFFFF')));
  // "Mountain Mist" der IDE: hellgrau.
  Assert.IsFalse(TArgusColorMath.IsDark(TArgusColorMath.FromHex('#E8E8EC')));
end;

{ TArgusPaletteTests }

procedure TArgusPaletteTests.CheckContrast(const AColors: TArgusColors; const AMode: string);

  procedure Pair(const AName: string; AFront, ABack: TArgusColor);
  var
    Ratio: Double;
  begin
    Ratio := TArgusColorMath.Contrast(AFront, ABack);
    Assert.IsTrue(Ratio >= 4.5, Format('%s %s: %s auf %s nur %.2f : 1', [AMode, AName,
      TArgusColorMath.ToHex(AFront), TArgusColorMath.ToHex(ABack), Ratio]));
  end;

var
  Kind: TArgusBadgeKind;
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
  Pair('Fehler auf Fehlerfläche', AColors.Error, AColors.ErrorSoft);
  Pair('Fehler auf Gutter', AColors.Error, AColors.Gutter);
  for Kind := Low(TArgusBadgeKind) to High(TArgusBadgeKind) do
    Pair('Badge ' + Ord(Kind).ToString, AColors.Badges[Kind].Text, AColors.Badges[Kind].Background);
end;

procedure TArgusPaletteTests.LightRolesMeetContrast;
begin
  CheckContrast(TArgusColors.Light, 'Hell');
end;

procedure TArgusPaletteTests.DarkRolesMeetContrast;
begin
  CheckContrast(TArgusColors.Dark, 'Dunkel');
end;

procedure TArgusPaletteTests.AccentIsGreekBlue;
begin
  Assert.AreEqual('#0D5EAF', TArgusColorMath.ToHex(TArgusColors.Light.Accent));
  Assert.AreEqual('#5B9BE6', TArgusColorMath.ToHex(TArgusColors.Dark.Accent));
end;

procedure TArgusPaletteTests.BadgeKindsDifferInLightness;

  procedure Check(const AColors: TArgusColors; const AMode: string);
  begin
    // Funktion und Typ teilen den Farbton, unterscheiden sich aber in der Helligkeit (#421).
    Assert.IsTrue(TArgusColorMath.Contrast(AColors.Badges[TArgusBadgeKind.Function_].Background,
      AColors.Badges[TArgusBadgeKind.Type_].Background) >= 1.15, AMode);
    Assert.AreNotEqual(Cardinal(AColors.Badges[TArgusBadgeKind.Function_].Background),
      Cardinal(AColors.Badges[TArgusBadgeKind.Procedure_].Background), AMode);
  end;

begin
  Check(TArgusColors.Light, 'Hell');
  Check(TArgusColors.Dark, 'Dunkel');
end;

procedure TArgusPaletteTests.ChoosesModeByBackground;
begin
  Assert.IsTrue(TArgusColors.ForBackground(TArgusColorMath.FromHex('#1E1E1E')).IsDark);
  Assert.IsFalse(TArgusColors.ForBackground(TArgusColorMath.FromHex('#FFFFFF')).IsDark);
  Assert.IsTrue(TArgusColors.Dark.IsDark);
  Assert.IsFalse(TArgusColors.Light.IsDark);
end;

{ TArgusScalingTests }

procedure TArgusScalingTests.NormalCaretIsNoZoom;
begin
  // Caret so hoch wie der Text oder mit Zeilenabstand: 100 %.
  Assert.AreEqual(1.0, TArgusScaling.ZoomFromCaret(15, 15), 0.001);
  Assert.AreEqual(1.0, TArgusScaling.ZoomFromCaret(17, 15), 0.001);
  Assert.AreEqual(1.0, TArgusScaling.ZoomFromCaret(14, 15), 0.001);
end;

procedure TArgusScalingTests.LargerCaretIsZoom;
begin
  // 150 % mit Zeilenabstand von einem Achtel: Caret 1,5 × 1,125 × Text.
  Assert.AreEqual(1.5, TArgusScaling.ZoomFromCaret(Round(15 * 1.5 * 1.125), 15), 0.05);
  Assert.AreEqual(2.0, TArgusScaling.ZoomFromCaret(Round(15 * 2 * 1.125), 15), 0.05);
  // Verkleinert.
  Assert.AreEqual(0.6, TArgusScaling.ZoomFromCaret(9, 15), 0.01);
end;

procedure TArgusScalingTests.ClampsAndIgnoresInvalidValues;
begin
  Assert.AreEqual(1.0, TArgusScaling.ZoomFromCaret(0, 15), 0.001);
  Assert.AreEqual(1.0, TArgusScaling.ZoomFromCaret(15, 0), 0.001);
  Assert.AreEqual(TArgusScaling.MaxZoom, TArgusScaling.ZoomFromCaret(500, 10), 0.001);
  Assert.AreEqual(TArgusScaling.MinZoom, TArgusScaling.ZoomFromCaret(2, 15), 0.001);
end;

{ TArgusSyntaxTests }

function Describe(const AText: string): string;
var
  Token: TArgusToken;
const
  Names: array[TArgusTokenKind] of string = ('p', 'k', 's', 'c', 'n');
begin
  Result := '';
  for Token in TArgusSyntax.Tokens(AText) do
    Result := Result + Names[Token.Kind] + ':' + Copy(AText, Token.Start + 1, Token.Stop - Token.Start) + '|';
end;

procedure TArgusSyntaxTests.ColorsKeywordsAndStrings;
begin
  Assert.AreEqual('k:function|p: Add(|k:const|p: S: |k:string|p:): Integer|',
    Describe('function Add(const S: string): Integer'));
  Assert.AreEqual('k:procedure|p: Log(Msg: |k:string|p: = |s:''x''|p:; Level: Integer = |n:1|p:)|',
    Describe('procedure Log(Msg: string = ''x''; Level: Integer = 1)'));
  Assert.AreEqual('k:property|p: Count: Integer |k:read|p: GetCount; |c:{ Anzahl }|',
    Describe('property Count: Integer read GetCount; { Anzahl }'));
end;

procedure TArgusSyntaxTests.TokensCoverWholeText;
var
  Text: string;
  Tokens: TArgusTokens;
  Index: Integer;
begin
  for Text in ['', 'x', 'function F(''unclosed', '{ offen', 'a // Rest', 'const Ä: Byte = $FF;'] do
  begin
    Tokens := TArgusSyntax.Tokens(Text);
    if Text = '' then
    begin
      Assert.AreEqual(0, Integer(Length(Tokens)));
      Continue;
    end;
    Assert.AreEqual(0, Tokens[0].Start, Text);
    for Index := 1 to High(Tokens) do
      Assert.AreEqual(Tokens[Index - 1].Stop, Tokens[Index].Start, Text);
    Assert.AreEqual(Length(Text), Tokens[High(Tokens)].Stop, Text);
  end;
end;

procedure TArgusSyntaxTests.NameAfterDotIsNoKeyword;
begin
  Assert.AreEqual('k:constructor|p: TFoo.Create(Owner: TComponent)|',
    Describe('constructor TFoo.Create(Owner: TComponent)'));
  Assert.AreEqual('p:Stream.Read(Buffer)|', Describe('Stream.Read(Buffer)'));
end;

{ TArgusPresentationTests }

procedure TArgusPresentationTests.BadgesFollowKind;
begin
  Assert.AreEqual('fn', TArgusItemPresentation.Badge(Item('Length', TArgusItemKind.Function_)).Code);
  Assert.AreEqual('pr', TArgusItemPresentation.Badge(Item('Clear', TArgusItemKind.Procedure_)).Code);
  Assert.AreEqual('pp', TArgusItemPresentation.Badge(Item('Count', TArgusItemKind.Property_)).Code);
  Assert.AreEqual('fd', TArgusItemPresentation.Badge(Item('FCount', TArgusItemKind.Field)).Code);
  Assert.AreEqual('ev', TArgusItemPresentation.Badge(Item('OnClick', TArgusItemKind.Event)).Code);
  Assert.AreEqual('co', TArgusItemPresentation.Badge(Item('alClient', TArgusItemKind.EnumMember)).Code);
  Assert.AreEqual('ty', TArgusItemPresentation.Badge(Item('TStringList', TArgusItemKind.Class_)).Code);
  Assert.AreEqual('va', TArgusItemPresentation.Badge(Item('Total', TArgusItemKind.Variable)).Code);
  Assert.AreEqual('un', TArgusItemPresentation.Badge(Item('System.Classes', TArgusItemKind.Unit_)).Code);
  Assert.AreEqual('sn', TArgusItemPresentation.Badge(Item('tryf', TArgusItemKind.Snippet)).Code);
  Assert.AreEqual('fn', TArgusItemPresentation.Badge(Item('Create', TArgusItemKind.Constructor_)).Code);
  Assert.AreEqual('pr', TArgusItemPresentation.Badge(Item('Destroy', TArgusItemKind.Destructor_)).Code);
  Assert.IsTrue(TArgusItemPresentation.Badge(Item('TStringList', TArgusItemKind.Class_)).Kind =
    TArgusBadgeKind.Type_);
end;

procedure TArgusPresentationTests.MethodBadgeFollowsSignature;
begin
  Assert.AreEqual('pr', TArgusItemPresentation.Badge(Item('Add', TArgusItemKind.Method,
    'procedure Add(const S: string)')).Code);
  Assert.AreEqual('fn', TArgusItemPresentation.Badge(Item('Add', TArgusItemKind.Method,
    'function Add(const S: string): Integer')).Code);
  // Ohne Signatur: Funktion.
  Assert.AreEqual('fn', TArgusItemPresentation.Badge(Item('Add', TArgusItemKind.Method)).Code);
end;

procedure TArgusPresentationTests.MissingUnitBecomesTag;
var
  Entry: TArgusCompletionItem;
  Edit: TArgusTextEdit;
  Tags: TArgusTags;
begin
  Entry := Item('TStringList', TArgusItemKind.Class_, 'System.Classes (uses ergänzen)');
  Entry.UnitUsed := False;
  Assert.AreEqual('System.Classes', TArgusItemPresentation.MissingUnit(Entry));
  Assert.AreEqual('', TArgusItemPresentation.Detail(Entry));
  Tags := TArgusItemPresentation.Tags(Entry);
  Assert.AreEqual(1, Integer(Length(Tags)));
  Assert.AreEqual('+ System.Classes', Tags[0].Text);
  Assert.IsTrue(Tags[0].Kind = TArgusTagKind.Add);
  // Ohne Hinweis im Detail: aus der uses-Ergänzung.
  Entry := Item('TStringList', TArgusItemKind.Class_, 'TStringList');
  Entry.UnitUsed := False;
  Edit := Default(TArgusTextEdit);
  Edit.NewText := ', System.Classes';
  Entry.AdditionalEdits := [Edit];
  Assert.AreEqual('System.Classes', TArgusItemPresentation.MissingUnit(Entry));
  Edit.NewText := sLineBreak + 'uses' + sLineBreak + '  System.Classes;';
  Entry.AdditionalEdits := [Edit];
  Assert.AreEqual('System.Classes', TArgusItemPresentation.MissingUnit(Entry));
  // Eingebunden: keine Marke.
  Entry.UnitUsed := True;
  Assert.AreEqual('', TArgusItemPresentation.MissingUnit(Entry));
  Assert.AreEqual(0, Integer(Length(TArgusItemPresentation.Tags(Entry))));
end;

procedure TArgusPresentationTests.UnitDetailIsFileName;
begin
  Assert.AreEqual('System.Classes.pas', TArgusItemPresentation.Detail(Item('System.Classes', TArgusItemKind.Unit_,
    'C:\Program Files\Embarcadero\source\rtl\common\System.Classes.pas')));
  Assert.AreEqual(': Integer', TArgusItemPresentation.Detail(Item('Count', TArgusItemKind.Property_, ': Integer')));
end;

procedure TArgusPresentationTests.DeprecatedAndConstructorTags;
var
  Entry: TArgusCompletionItem;
  Tags: TArgusTags;
begin
  Entry := Item('Create', TArgusItemKind.Constructor_);
  Entry.Directives := ['overload', 'deprecated'];
  Tags := TArgusItemPresentation.Tags(Entry);
  Assert.AreEqual(2, Integer(Length(Tags)));
  Assert.AreEqual('constructor', Tags[0].Text);
  Assert.AreEqual('deprecated', Tags[1].Text);
  Assert.IsTrue(Tags[1].Kind = TArgusTagKind.Warn);
end;

procedure TArgusPresentationTests.HighlightsPrefixWordStartsSubstringSubsequence;
begin
  Assert.AreEqual('1,2,3', Positions(TArgusItemPresentation.Highlights('tst', 'TStringList')));
  Assert.AreEqual('1,2,8', Positions(TArgusItemPresentation.Highlights('TSL', 'TStringList')));
  Assert.AreEqual('4,5,6', Positions(TArgusItemPresentation.Highlights('rin', 'TStringList')));
  Assert.AreEqual('2,3,8', Positions(TArgusItemPresentation.Highlights('stl', 'TStringList')));
  Assert.AreEqual('1,2,3,4,5,6', Positions(TArgusItemPresentation.Highlights('length', 'Length')));
end;

procedure TArgusPresentationTests.NoHighlightsWithoutMatch;
begin
  Assert.AreEqual('', Positions(TArgusItemPresentation.Highlights('xyz', 'TStringList')));
  Assert.AreEqual('', Positions(TArgusItemPresentation.Highlights('', 'TStringList')));
  // Verstreute Treffer zählen nicht (wie beim Filtern).
  Assert.AreEqual('', Positions(TArgusItemPresentation.Highlights('myLis', 'ERROR_TOO_MANY_LINKS')));
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusColorTests);
  TDUnitX.RegisterTestFixture(TArgusPaletteTests);
  TDUnitX.RegisterTestFixture(TArgusScalingTests);
  TDUnitX.RegisterTestFixture(TArgusSyntaxTests);
  TDUnitX.RegisterTestFixture(TArgusPresentationTests);

end.
