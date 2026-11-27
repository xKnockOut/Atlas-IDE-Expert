unit Rules.Builtin.Texts.Concat;

// Regel für zusammengesetzte Texte (#3042):
//   text-concat-without-space  Zwei String-Literale mit + verkettet, an der Naht weder Leerzeichen noch Trenner:
//                              'Bli Bla Blubb' + 'Bla Bla Bla' ergibt „…BlubbBla…“. Gemeldet, wenn Buchstabe oder
//                              Ziffer auf Buchstabe oder Ziffer trifft oder , ; : ! ? auf einen Großbuchstaben.
//                              Still, wenn der zusammengesetzte Text nicht nach Text für Menschen aussieht
//                              (Bezeichner, Klassennamen), wenn das Wort an der Naht ein Pfad, eine URL,
//                              Markup, ein Name mit Punkt (Unit.Klasse) oder Zahlendaten ('1-1z' + 'M10' aus einem
//                              SVG-Pfad) ist, wenn die Naht an einem Zeichencode liegt ('ung' + #$00FC'ltig'), wenn
//                              links ein
//                              Format-Platzhalter endet (er kann selbst der Trenner sein) und bei maschinell
//                              umbrochenen langen Texten (linkes Literal ab "wrapLength"
//                              Zeichen). Mittlere Konfidenz. Option "expressions" (Standard aus, niedrige
//                              Konfidenz): auch Literal + Ausdruck und Ausdruck + Literal ('Datei' + Name);
//                              Trenner wie sLineBreak, PathDelim oder QuotedStr bleiben still.
//                              Korrektur: Leerzeichen ans Ende des linken Literals (beim Ausdruck links an den
//                              Anfang des rechten).

interface

uses
  Rules.Contract,
  Rules.Registry;

const
  cTextConcatWithoutSpaceRuleId = 'text-concat-without-space';

type
  TTextConcatWithoutSpaceRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Fehlt zwischen dem Klartext ALeft und dem Klartext ARight ein Leerzeichen? Nur die Naht zählt:
    /// Buchstabe oder Ziffer gefolgt von Buchstabe oder Ziffer, oder , ; : ! ? gefolgt von einem Großbuchstaben;
    /// ein Format-Platzhalter am Ende von ALeft gilt als Trenner.</summary>
    class function MissingSpace(const ALeft, ARight: string): Boolean; static;
    /// <summary>Ist das Wort an der Naht (letztes Wort von ALeft und erstes von ARight) ein Pfad, eine URL, eine
    /// Mailadresse, ein Bezeichner mit _, ein Name mit Punkt (A.B, Unit1.pas) oder Markup?</summary>
    class function SeamIsTechnical(const ALeft, ARight: string): Boolean; static;
  end;

procedure RegisterTextRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Character,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.SyntaxNodes,
  Atlas.Common.Pascal.StringLiterals,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.RuleOptions,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Findings.Contract,
  Atlas.Text.Lines,
  Rules.Builtin.Texts.Shared,
  Rules.Trees;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TConcatText = (Title, Joined, Between, SpaceAtEnd, SpaceAtStart);

const
  cTexts: array[TConcatText] of TAtlasText = (
    (De: 'Text ohne Leerzeichen zusammengesetzt'; En: 'Text joined without a space'),
    (De: 'Text ohne Leerzeichen zusammengesetzt: ''%s'' + ''%s'' ergibt ''%s''.';
     En: 'Text joined without a space: ''%s'' + ''%s'' gives ''%s''.'),
    (De: 'Kein Leerzeichen zwischen %s und %s.'; En: 'No space between %s and %s.'),
    (De: 'Leerzeichen am Ende des Textes einfügen'; En: 'Add a space at the end of the text'),
    (De: 'Leerzeichen am Anfang des Textes einfügen'; En: 'Add a space at the start of the text'));

{$SCOPEDENUMS OFF}

const
  cDefaultWrapLength = 120;
  // Höchstens so viele Zeichen je Seite in der Meldung.
  cShownChars = 20;
  // Satzzeichen, nach denen vor einem Großbuchstaben ein Leerzeichen fehlt. Der Punkt fehlt mit Absicht:
  // 'System.' + 'SysUtils' ist ein Unit-Name.
  cPunctuation: TSysCharSet = [',', ';', ':', '!', '?'];
  // Zeichen im Wort an der Naht, die auf Pfad, URL, Mailadresse, Bezeichner oder Markup deuten.
  cTechnicalChars: TSysCharSet = ['\', '/', '@', '_', '=', '&', '<', '>', '{', '}', '[', ']', '|'];
  // Namensteile von Ausdrücken, die selbst Trenner oder Rahmen liefern (sLineBreak, PathDelim, QuotedStr …).
  cSeparatorParts: array[0..11] of string = ('LineBreak', 'Delim', 'Separator', 'CRLF', 'Space', 'Indent',
    'NewLine', 'EOL', 'Prefix', 'Suffix', 'Quote', 'Blank');

{ TTextConcatWithoutSpaceRule }

function TTextConcatWithoutSpaceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cTextConcatWithoutSpaceRuleId, TRuleSeverity.Hint,
    cTexts[TConcatText.Title].Text);
end;

class function TTextConcatWithoutSpaceRule.MissingSpace(const ALeft, ARight: string): Boolean;
var
  mLast, mFirst: Char;
begin
  if (ALeft = '') or (ARight = '') then
  begin
    Exit(False);
  end;
  mLast := ALeft[Length(ALeft)];
  mFirst := ARight[1];
  if not mFirst.IsLetterOrDigit then
  begin
    Exit(False);
  end;
  if mLast.IsLetterOrDigit then
  begin
    Result := not TLiteralTexts.EndsWithFormatSpecifier(ALeft);
  end
  else
  begin
    Result := CharInSet(mLast, cPunctuation) and mFirst.IsUpper;
  end;
end;

/// <summary>Letztes Wort von AText (ab dem letzten Leerraum).</summary>
function TrailingWord(const AText: string): string;
var
  mIndex: Integer;
begin
  mIndex := Length(AText);
  while (mIndex > 0) and not AText[mIndex].IsWhiteSpace do
  begin
    Dec(mIndex);
  end;
  Result := Copy(AText, mIndex + 1, MaxInt);
end;

/// <summary>Erstes Wort von AText (bis zum ersten Leerraum).</summary>
function LeadingWord(const AText: string): string;
var
  mIndex: Integer;
begin
  mIndex := 1;
  while (mIndex <= Length(AText)) and not AText[mIndex].IsWhiteSpace do
  begin
    Inc(mIndex);
  end;
  Result := Copy(AText, 1, mIndex - 1);
end;

/// <summary>Zahlendaten statt eines Worts: Ziffern mit höchstens einzelnen Buchstaben dazwischen ('1-1z', 'M10',
/// '2.5h3a1' aus einem SVG-Pfad, 'x64'). Ein Wort mit mindestens zwei Buchstaben in Folge (Win64) zählt nicht,
/// eine reine Zahl ('Anzahl 3' + '4 Teile') auch nicht.</summary>
function IsNumericData(const AWord: string): Boolean;
var
  mIndex: Integer;
  mDigit, mLetter: Boolean;
begin
  mDigit := False;
  mLetter := False;
  for mIndex := 1 to Length(AWord) do
  begin
    mDigit := mDigit or AWord[mIndex].IsDigit;
    mLetter := mLetter or AWord[mIndex].IsLetter;
    if AWord[mIndex].IsLetter and (mIndex < Length(AWord)) and AWord[mIndex + 1].IsLetter then
    begin
      Exit(False);
    end;
  end;
  Result := mDigit and mLetter;
end;

class function TTextConcatWithoutSpaceRule.SeamIsTechnical(const ALeft, ARight: string): Boolean;
var
  mWord: string;
  mChar: Char;
  mIndex: Integer;
begin
  if IsNumericData(TrailingWord(ALeft)) or IsNumericData(LeadingWord(ARight)) then
  begin
    Exit(True);
  end;
  mWord := TrailingWord(ALeft) + LeadingWord(ARight);
  for mIndex := 1 to Length(mWord) do
  begin
    mChar := mWord[mIndex];
    // Punkt mitten im Wort: Unit- oder Klassenname, Dateiname, Versionsnummer (A.B, Unit1.pas, 1.2).
    if CharInSet(mChar, cTechnicalChars) or ((mChar = '.') and (mIndex < Length(mWord)) and
      mWord[mIndex + 1].IsLetterOrDigit) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Klartext des String-Literals ANode in AText; False bei anderen Knoten und Zahlen.</summary>
function StringValue(ANode: TSyntaxNode; out AText: string): Boolean;
begin
  AText := '';
  Result := (ANode.Kind = TSyntaxKind.Literal) and (StartsStr('''', ANode.Name) or StartsStr('#', ANode.Name)) and
    TStringLiterals.PlainText(ANode.Name, AText);
end;

/// <summary>Liefert der Ausdruck ANode wahrscheinlich selbst einen Trenner oder Rahmen (sLineBreak, PathDelim,
/// QuotedStr(…), FSeparator …)?</summary>
function IsSeparatorExpression(ANode: TSyntaxNode; const AText: string): Boolean;
var
  mSource, mPart: string;
begin
  mSource := TSyntaxNodes.SourceOf(AText, ANode);
  for mPart in cSeparatorParts do
  begin
    if ContainsText(mSource, mPart) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function Shortened(const AText: string; AFromEnd: Boolean): string;
begin
  if Length(AText) <= cShownChars then
  begin
    Exit(AText);
  end;
  if AFromEnd then
  begin
    Result := '…' + Copy(AText, Length(AText) - cShownChars + 1, cShownChars);
  end
  else
  begin
    Result := Copy(AText, 1, cShownChars) + '…';
  end;
end;

/// <summary>Endet AText mit einem Buchstaben oder einer Ziffer, die nicht zu einem Format-Platzhalter gehört?
/// </summary>
function EndsWithWord(const AText: string): Boolean;
begin
  Result := (AText <> '') and AText[Length(AText)].IsLetterOrDigit and
    not TLiteralTexts.EndsWithFormatSpecifier(AText);
end;

/// <summary>Korrektur: ein Leerzeichen vor das schließende (AAtEnd) bzw. hinter das öffnende Hochkomma des
/// Literals ALiteral. Nil, wenn das Literal dort kein Hochkomma hat (#13, mehrzeiliges ''').</summary>
function SpaceFix(const AText: string; ALiteral: TSyntaxNode; AAtEnd: Boolean): TArray<TRuleFix>;
var
  mSource: string;
  mPosition: TTextPosition;
  mFix: TRuleFix;
begin
  Result := nil;
  mSource := TSyntaxNodes.SourceOf(AText, ALiteral);
  if (ALiteral.StartPos.Line <> ALiteral.EndPos.Line) or StartsStr('''''''', mSource) then
  begin
    Exit;
  end;
  if AAtEnd then
  begin
    if not EndsStr('''', mSource) then
    begin
      Exit;
    end;
    mPosition := TTextPosition.Create(ALiteral.EndPos.Line, ALiteral.EndPos.Character - 1);
    mFix := TRuleFix.Create(cTexts[TConcatText.SpaceAtEnd].Text,
      [TTextEdit.Create(TTextRange.Create(mPosition, mPosition), ' ')]);
  end
  else
  begin
    if not StartsStr('''', mSource) then
    begin
      Exit;
    end;
    mPosition := TTextPosition.Create(ALiteral.StartPos.Line, ALiteral.StartPos.Character + 1);
    mFix := TRuleFix.Create(cTexts[TConcatText.SpaceAtStart].Text,
      [TTextEdit.Create(TTextRange.Create(mPosition, mPosition), ' ')]);
  end;
  SetLength(Result, 1);
  Result[0] := mFix;
end;

procedure TTextConcatWithoutSpaceRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mText: string;
  mWrapLength: Integer;
  mExpressions: Boolean;
  mPluses: TArray<TSyntaxNode>;
  mPlus: TSyntaxNode;

  procedure CheckLiterals(ALeft, ARight: TSyntaxNode; const ALeftText, ARightText: string);
  var
    mLeftWord, mRightWord: string;
  begin
    // Naht an einem Zeichencode ('ung' + #$00FC'ltige'): Der Umbruch folgt der Schreibweise, nicht den Wörtern.
    if StartsStr('#', TSyntaxNodes.SourceOf(mText, ARight)) or
      not EndsStr('''', TSyntaxNodes.SourceOf(mText, ALeft)) then
    begin
      Exit;
    end;
    if (Length(ALeftText) >= mWrapLength) or not MissingSpace(ALeftText, ARightText) or
      not TLiteralTexts.LooksLikeText(ALeftText + ARightText) or SeamIsTechnical(ALeftText, ARightText) then
    begin
      Exit;
    end;
    mLeftWord := Shortened(TrailingWord(ALeftText), True);
    mRightWord := Shortened(LeadingWord(ARightText), False);
    AReport.Add(TTextRange.Create(ALeft.StartPos, ARight.EndPos),
      cTexts[TConcatText.Joined].Fmt([mLeftWord, mRightWord, mLeftWord + mRightWord]), TRuleConfidence.Medium,
      SpaceFix(mText, ALeft, True));
  end;

  procedure CheckLiteralThenExpression(ALeft, ARight: TSyntaxNode; const ALeftText: string);
  begin
    if not EndsWithWord(ALeftText) or not TLiteralTexts.LooksLikeText(ALeftText) or SeamIsTechnical(ALeftText, '') or
      IsSeparatorExpression(ARight, mText) then
    begin
      Exit;
    end;
    AReport.Add(TTextRange.Create(ALeft.StartPos, ARight.EndPos), cTexts[TConcatText.Between].Fmt(
      ['''' + Shortened(TrailingWord(ALeftText), True) + '''',
      TSyntaxNodes.OneLineText(mText, ARight, cShownChars)]),
      TRuleConfidence.Low, SpaceFix(mText, ALeft, True));
  end;

  procedure CheckExpressionThenLiteral(ALeft, ARight: TSyntaxNode; const ARightText: string);
  begin
    if (ARightText = '') or not ARightText[1].IsLetterOrDigit or not TLiteralTexts.LooksLikeText(ARightText) or
      SeamIsTechnical('', ARightText) or IsSeparatorExpression(ALeft, mText) then
    begin
      Exit;
    end;
    AReport.Add(TTextRange.Create(ALeft.StartPos, ARight.EndPos), cTexts[TConcatText.Between].Fmt(
      [TSyntaxNodes.OneLineText(mText, ALeft, cShownChars),
      '''' + Shortened(LeadingWord(ARightText), False) + '''']),
      TRuleConfidence.Low, SpaceFix(mText, ARight, False));
  end;

  procedure CheckPlus(APlus: TSyntaxNode);
  var
    mLeft, mRight: TSyntaxNode;
    mLeftText, mRightText: string;
    mLeftIsText, mRightIsText: Boolean;
  begin
    mLeft := TSyntaxNodes.LastOperand(APlus[0], '+');
    mRight := TSyntaxNodes.FirstOperand(APlus[1], '+');
    if (mLeft = nil) or (mRight = nil) then
    begin
      Exit;
    end;
    mLeftIsText := StringValue(mLeft, mLeftText);
    mRightIsText := StringValue(mRight, mRightText);
    if mLeftIsText and mRightIsText then
    begin
      CheckLiterals(mLeft, mRight, mLeftText, mRightText);
    end
    else if mExpressions and mLeftIsText and (mRight.Kind <> TSyntaxKind.Literal) then
    begin
      CheckLiteralThenExpression(mLeft, mRight, mLeftText);
    end
    else if mExpressions and mRightIsText and (mLeft.Kind <> TSyntaxKind.Literal) then
    begin
      CheckExpressionThenLiteral(mLeft, mRight, mRightText);
    end;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mText := AContext.Text;
  mWrapLength := TRuleOptions.Int(AContext.Options, 'wrapLength', cDefaultWrapLength);
  if mWrapLength <= 0 then
  begin
    mWrapLength := MaxInt;
  end;
  mExpressions := TRuleOptions.Bool(AContext.Options, 'expressions', False);
  mPluses := TSyntaxNodes.OfKind(AContext.Tree.Root, TSyntaxKind.BinaryExpr);
  for mPlus in mPluses do
  begin
    if TSyntaxNodes.IsBinary(mPlus, '+') then
    begin
      CheckPlus(mPlus);
    end;
  end;
end;

procedure RegisterTextRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TTextConcatWithoutSpaceRule.Create);
end;

end.
