unit Atlas.Core.Documentation.Layout;

// Satz der XMLDoc (#654, #770) für Hover-Tooltip und Detailpanel, ohne VCL: Aus
// der strukturierten Doku werden Zeilen mit Stücken (Text, Schrift, Farbe,
// Position), Klickflächen für Verweise, Links und „Mehr/Weniger anzeigen“ und
// der Klartext zum Kopieren. Gemessen wird über einen Rückruf; so lässt sich der
// Satz ohne Fenster testen.
//
//   - Zugeklappt: Beschreibung, dazu „Mehr anzeigen ▾“ und gedämpft, was
//     verborgen ist („3 Parameter · Rückgabe · 1 Ausnahme · Hinweis“, Ausnahmen
//     in Fehlerfarbe). Ohne weitere Abschnitte kein Schalter.
//   - Aufgeklappt: Abschnitte unter Überschriften in Kapitälchen (gedämpft, mit
//     Linie bis zum rechten Rand) in fester Reihenfolge PARAMETER, TYPPARAMETER,
//     RÜCKGABE, WERT, AUSNAHMEN, HINWEISE, BEISPIEL; SIEHE AUCH in einer Zeile
//     mit den Verweisen; am Ende „Weniger anzeigen ▴“.
//   - Parameter dreispaltig in der Reihenfolge der Signatur: Name (Editorschrift,
//     halbfett, Akzent), Art und Typ (gedämpft), Beschreibung; ohne <param>
//     „nicht dokumentiert“ (kursiv, gedämpft); ein <param>, den die Signatur
//     nicht kennt, am Ende in Warnfarbe.
//   - Rückgabe: Ergebnistyp (Schlüsselwortfarbe) und Text; ohne <returns> nur der
//     Typ. Ausnahmen: Klasse in Fehlerfarbe, anklickbar mit Fundort.
//   - Läufe: Code in der Editorschrift, paramref als Pille (Akzent auf
//     AccentSoft), Verweise in Akzentfarbe, unterstrichen und anklickbar, wenn der
//     Server den Fundort kennt; Links öffnen den Browser; Codeblöcke eingefärbt
//     auf schattierter, gerahmter Fläche; Listen mit hängendem Einzug je Ebene;
//     Tabellen zweispaltig. Eine Listenmarke mit Ziel (Kästchen einer
//     Checkliste in der Issue-Vorschau, #1273) ist ein Link in Akzentfarbe.
//   - Begründungen (#1123) unter BEGRÜNDUNG nach allen XMLDoc-Abschnitten: je
//     Eintrag Marke (Editorschrift, halbfett, Akzent) und Text. Zugeklappt die
//     ersten MaxRationale, der Rest hinter „Mehr anzeigen“ („2 weitere
//     Begründungen“). ADR-Verweise mit Fundort öffnen die Datei, Issue-Links
//     "issue:312" die Adresse aus TAtlasDocIssueLinks; ohne Tracker bleiben sie
//     Text.
//   - TAtlasDocExpandState hält „wie zuletzt“ (hints.xmlDocExpand = last) je
//     Fläche (Tooltip, Detailpanel) für die Sitzung.

interface

uses
  System.SysUtils,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  TAtlasDocFont = (UI, Mono);

  TAtlasDocColor = (Text, Muted, Accent, Error, Keyword, StringLiteral, Comment, Number, Warn);

  TAtlasDocFace = record
    Font: TAtlasDocFont;
    Bold: Boolean;
    Italic: Boolean;
    /// <summary>Kleinere Schrift der Überschriften.</summary>
    Small: Boolean;
    class function Create(AFont: TAtlasDocFont): TAtlasDocFace; overload; static;
    class function Create(AFont: TAtlasDocFont; ABold: Boolean): TAtlasDocFace; overload; static;
    class function Create(AFont: TAtlasDocFont; ABold, AItalic: Boolean): TAtlasDocFace; overload; static;
    /// <summary>Überschrift: UI, halbfett, klein.</summary>
    class function Heading: TAtlasDocFace; static;
    function SameAs(const AOther: TAtlasDocFace): Boolean;
  end;

  /// <summary>Breite von AText in Pixeln in der Schrift AFace.</summary>
  TAtlasDocMeasure = reference to function(const AText: string; const AFace: TAtlasDocFace): Integer;

  TAtlasDocMetrics = record
    /// <summary>Zeilenhöhe der UI-Schrift bzw. der Editorschrift.</summary>
    LineHeight: Integer;
    MonoHeight: Integer;
    /// <summary>Einzug je Listenebene.</summary>
    Indent: Integer;
    /// <summary>Abstand zwischen den Spalten.</summary>
    ColumnGap: Integer;
    ParagraphGap: Integer;
    SectionGap: Integer;
    /// <summary>Innenabstand der Codefläche links und rechts.</summary>
    CodePad: Integer;
    /// <summary>Innenabstand der paramref-Pille links und rechts.</summary>
    PillPad: Integer;
    /// <summary>Werte für 96 dpi, mit AScale (Pixel je Zoll / 96) multipliziert.</summary>
    class function Create(ALineHeight, AMonoHeight: Integer; AScale: Double): TAtlasDocMetrics; static;
  end;

  /// <summary>Überschriften und Texte in der Sprache der IDE.</summary>
  TAtlasDocLabels = record
    Params: string;
    TypeParams: string;
    Returns: string;
    Value: string;
    Exceptions: string;
    Remarks: string;
    Example: string;
    SeeAlso: string;
    Rationale: string;
    Undocumented: string;
    More: string;
    Less: string;
    /// <summary>Verborgenes im zugeklappten Zustand; Count* mit %d.</summary>
    CountParam: string;
    CountParams: string;
    CountTypeParam: string;
    CountTypeParams: string;
    CountException: string;
    CountExceptions: string;
    CountRationale: string;
    CountRationales: string;
    ItemReturns: string;
    ItemValue: string;
    ItemRemarks: string;
    ItemExample: string;
    ItemSeeAlso: string;
    class function ForLanguage(ALanguage: TAtlasLanguage): TAtlasDocLabels; static;
    class function German: TAtlasDocLabels; static;
    /// <summary>Beschriftungen in der Sprache der Oberfläche (TAtlasTextLanguage).</summary>
    class function Current: TAtlasDocLabels; static;
  end;

  TAtlasDocSpan = record
    Text: string;
    Left: Integer;
    /// <summary>Breite samt Innenabstand.</summary>
    Width: Integer;
    Face: TAtlasDocFace;
    Color: TAtlasDocColor;
    Underline: Boolean;
    /// <summary>paramref: Hintergrund AccentSoft, Text um Pad eingerückt.</summary>
    Pill: Boolean;
    Pad: Integer;
    /// <summary>Index in Links; -1 ohne.</summary>
    Link: Integer;
    /// <summary>Anfang im Klartext (0-basiert).</summary>
    TextStart: Integer;
    function Right: Integer;
  end;

  TAtlasDocLine = record
    /// <summary>Abstand über der Zeile.</summary>
    GapBefore: Integer;
    Top: Integer;
    Height: Integer;
    Spans: TArray<TAtlasDocSpan>;
    /// <summary>Überschrift: Linie ab RuleFrom bis zum rechten Rand.</summary>
    Rule: Boolean;
    RuleFrom: Integer;
    /// <summary>Codezeile: schattierte, gerahmte Fläche ab ShadeLeft.</summary>
    Shaded: Boolean;
    ShadeLeft: Integer;
    function Bottom: Integer;
  end;

  TAtlasDocLinkKind = (Ref, Url, Toggle);

  TAtlasDocLink = record
    Kind: TAtlasDocLinkKind;
    /// <summary>Ref: Ziel mit Fundort.</summary>
    Target: TAtlasDocTarget;
    /// <summary>Url: Adresse.</summary>
    Url: string;
  end;

  /// <summary>Zustand „wie zuletzt“ (#770) je Fläche für die Sitzung; nach dem Start zugeklappt.</summary>
  TAtlasDocExpandState = class
  private class var
    FLast: array[TAtlasDocSurface] of Boolean;
  public
    /// <summary>Aufgeklappt beim Öffnen nach AExpand.</summary>
    class function Initial(AExpand: TAtlasDocExpand; ASurface: TAtlasDocSurface): Boolean; static;
    /// <summary>Nach einem Klick auf „Mehr“ bzw. „Weniger anzeigen“.</summary>
    class procedure Remember(ASurface: TAtlasDocSurface; AExpanded: Boolean); static;
    /// <summary>Wie nach dem Start (Tests).</summary>
    class procedure Reset; static;
  end;

  /// <summary>Issue-Links "issue:312" der Begründungen (#1123): Die IDE meldet den Tracker der Willkommensseite
  /// (#765) an und beim Entladen wieder ab. Nur im Hauptthread.</summary>
  TAtlasDocIssueLinks = class
  public const
    Prefix = 'issue:';
  private class var
    FResolver: TAtlasDocIssueUrl;
  public
    class procedure SetResolver(const AResolver: TAtlasDocIssueUrl); static;
    class procedure Clear; static;
    /// <summary>Adresse zu ATarget ("issue:312"); '' ohne Tracker oder bei anderen Zielen.</summary>
    class function Url(const ATarget: string): string; static;
  end;

  TAtlasDocLayout = record
  public const
    /// <summary>Begründungen, die zugeklappt sichtbar sind.</summary>
    MaxRationale = 3;
    /// <summary>Tabellen: Spalte der Begriffe höchstens so viel Prozent der Breite.</summary>
    TermColumnPercent = 45;
    /// <summary>Parameter: Namens- und Typspalte höchstens so viel Prozent der Breite.</summary>
    NameColumnPercent = 30;
    TypeColumnPercent = 35;
    Separator = ' · ';
  public
    Lines: TArray<TAtlasDocLine>;
    Links: TArray<TAtlasDocLink>;
    /// <summary>Klartext aller Zeilen (CRLF), Grundlage der Markierung.</summary>
    Text: string;
    Height: Integer;
    /// <summary>Mehr als die Beschreibung: Es gibt „Mehr/Weniger anzeigen“.</summary>
    Collapsible: Boolean;
    Expanded: Boolean;
    function IsEmpty: Boolean;
    /// <summary>Zeile an AY; -1 außerhalb.</summary>
    function LineAt(AY: Integer): Integer;
    /// <summary>Link unter (AX, AY); -1 ohne.</summary>
    function LinkAt(AX, AY: Integer): Integer;
    /// <summary>Anfang der ersten Zeile ab ALine mit Text; sonst Ende des Klartexts.</summary>
    function FirstTextFrom(ALine: Integer): Integer;
    /// <summary>Erste Zeile unterhalb von AY; -1 ohne.</summary>
    function LineBelow(AY: Integer): Integer;
    /// <summary>Stelle im Klartext unter (AX, AY) für die Markierung; oberhalb 0, unterhalb Ende.</summary>
    function PositionAt(AX, AY: Integer; const AMeasure: TAtlasDocMeasure): Integer;
    /// <summary>Pixelbereich [ALeft, ARight) des Stücks für den Klartextbereich [AFrom, ATo); False ohne
    /// Überschneidung.</summary>
    function SpanRange(const ASpan: TAtlasDocSpan; AFrom, ATo: Integer; const AMeasure: TAtlasDocMeasure;
      out ALeft, ARight: Integer): Boolean;
    /// <summary>Markierter Klartext; Reihenfolge von AFrom und ATo beliebig.</summary>
    function Selected(AFrom, ATo: Integer): string;
    /// <summary>Höhe der ersten ALines Zeilen samt Abständen (0 = alle).</summary>
    function HeightOfLines(ALines: Integer): Integer;
  end;

implementation

uses
  System.Math;

{ TAtlasDocFace }

class function TAtlasDocFace.Create(AFont: TAtlasDocFont): TAtlasDocFace;
begin
  Result := Create(AFont, False, False);
end;

class function TAtlasDocFace.Create(AFont: TAtlasDocFont; ABold: Boolean): TAtlasDocFace;
begin
  Result := Create(AFont, ABold, False);
end;

class function TAtlasDocFace.Create(AFont: TAtlasDocFont; ABold, AItalic: Boolean): TAtlasDocFace;
begin
  Result.Font := AFont;
  Result.Bold := ABold;
  Result.Italic := AItalic;
  Result.Small := False;
end;

class function TAtlasDocFace.Heading: TAtlasDocFace;
begin
  Result := Create(TAtlasDocFont.UI, True, False);
  Result.Small := True;
end;

function TAtlasDocFace.SameAs(const AOther: TAtlasDocFace): Boolean;
begin
  Result := (Font = AOther.Font) and (Bold = AOther.Bold) and (Italic = AOther.Italic) and
    (Small = AOther.Small);
end;

{ TAtlasDocMetrics }

class function TAtlasDocMetrics.Create(ALineHeight, AMonoHeight: Integer; AScale: Double): TAtlasDocMetrics;
begin
  Result.LineHeight := ALineHeight;
  Result.MonoHeight := AMonoHeight;
  Result.Indent := Round(14 * AScale);
  Result.ColumnGap := Round(8 * AScale);
  Result.ParagraphGap := Round(5 * AScale);
  Result.SectionGap := Round(6 * AScale);
  Result.CodePad := Round(6 * AScale);
  Result.PillPad := Round(3 * AScale);
end;

type
  /// <summary>Beschriftungen von TAtlasDocLabels in Feldreihenfolge.</summary>
  TDocLabel = (Params, TypeParams, Returns, Value, Exceptions, Remarks, Example, SeeAlso, Rationale, Undocumented,
    More, Less, CountParam, CountParams, CountTypeParam, CountTypeParams, CountException, CountExceptions,
    CountRationale, CountRationales, ItemReturns, ItemValue, ItemRemarks, ItemExample, ItemSeeAlso);

const
  cDocLabels: array[TAtlasLanguage, TDocLabel] of string = (
    ('PARAMETER',
     'TYPPARAMETER',
     'RÜCKGABE',
     'WERT',
     'AUSNAHMEN',
     'HINWEISE',
     'BEISPIEL',
     'SIEHE AUCH',
     'BEGRÜNDUNG',
     'nicht dokumentiert',
     'Mehr anzeigen ▾',
     'Weniger anzeigen ▴',
     '%d Parameter',
     '%d Parameter',
     '%d Typparameter',
     '%d Typparameter',
     '%d Ausnahme',
     '%d Ausnahmen',
     '%d weitere Begründung',
     '%d weitere Begründungen',
     'Rückgabe',
     'Wert',
     'Hinweis',
     'Beispiel',
     'Siehe auch'),
    ('PARAMETERS',
     'TYPE PARAMETERS',
     'RETURNS',
     'VALUE',
     'EXCEPTIONS',
     'REMARKS',
     'EXAMPLE',
     'SEE ALSO',
     'RATIONALE',
     'not documented',
     'Show more ▾',
     'Show less ▴',
     '%d parameter',
     '%d parameters',
     '%d type parameter',
     '%d type parameters',
     '%d exception',
     '%d exceptions',
     '%d more rationale',
     '%d more rationales',
     'Returns',
     'Value',
     'Remark',
     'Example',
     'See also'));

{ TAtlasDocLabels }

class function TAtlasDocLabels.ForLanguage(ALanguage: TAtlasLanguage): TAtlasDocLabels;
begin
  Result.Params := cDocLabels[ALanguage, TDocLabel.Params];
  Result.TypeParams := cDocLabels[ALanguage, TDocLabel.TypeParams];
  Result.Returns := cDocLabels[ALanguage, TDocLabel.Returns];
  Result.Value := cDocLabels[ALanguage, TDocLabel.Value];
  Result.Exceptions := cDocLabels[ALanguage, TDocLabel.Exceptions];
  Result.Remarks := cDocLabels[ALanguage, TDocLabel.Remarks];
  Result.Example := cDocLabels[ALanguage, TDocLabel.Example];
  Result.SeeAlso := cDocLabels[ALanguage, TDocLabel.SeeAlso];
  Result.Rationale := cDocLabels[ALanguage, TDocLabel.Rationale];
  Result.Undocumented := cDocLabels[ALanguage, TDocLabel.Undocumented];
  Result.More := cDocLabels[ALanguage, TDocLabel.More];
  Result.Less := cDocLabels[ALanguage, TDocLabel.Less];
  Result.CountParam := cDocLabels[ALanguage, TDocLabel.CountParam];
  Result.CountParams := cDocLabels[ALanguage, TDocLabel.CountParams];
  Result.CountTypeParam := cDocLabels[ALanguage, TDocLabel.CountTypeParam];
  Result.CountTypeParams := cDocLabels[ALanguage, TDocLabel.CountTypeParams];
  Result.CountException := cDocLabels[ALanguage, TDocLabel.CountException];
  Result.CountExceptions := cDocLabels[ALanguage, TDocLabel.CountExceptions];
  Result.CountRationale := cDocLabels[ALanguage, TDocLabel.CountRationale];
  Result.CountRationales := cDocLabels[ALanguage, TDocLabel.CountRationales];
  Result.ItemReturns := cDocLabels[ALanguage, TDocLabel.ItemReturns];
  Result.ItemValue := cDocLabels[ALanguage, TDocLabel.ItemValue];
  Result.ItemRemarks := cDocLabels[ALanguage, TDocLabel.ItemRemarks];
  Result.ItemExample := cDocLabels[ALanguage, TDocLabel.ItemExample];
  Result.ItemSeeAlso := cDocLabels[ALanguage, TDocLabel.ItemSeeAlso];
end;

class function TAtlasDocLabels.German: TAtlasDocLabels;
begin
  Result := ForLanguage(TAtlasLanguage.German);
end;

class function TAtlasDocLabels.Current: TAtlasDocLabels;
begin
  Result := ForLanguage(TAtlasTextLanguage.Current);
end;

{ TAtlasDocSpan }

function TAtlasDocSpan.Right: Integer;
begin
  Result := Left + Width;
end;

{ TAtlasDocLine }

function TAtlasDocLine.Bottom: Integer;
begin
  Result := Top + Height;
end;

{ TAtlasDocExpandState }

class function TAtlasDocExpandState.Initial(AExpand: TAtlasDocExpand; ASurface: TAtlasDocSurface): Boolean;
begin
  case AExpand of
    TAtlasDocExpand.Collapsed:
      Result := False;
    TAtlasDocExpand.Expanded:
      Result := True;
  else
    Result := FLast[ASurface];
  end;
end;

class procedure TAtlasDocExpandState.Remember(ASurface: TAtlasDocSurface; AExpanded: Boolean);
begin
  FLast[ASurface] := AExpanded;
end;

class procedure TAtlasDocExpandState.Reset;
var
  Surface: TAtlasDocSurface;
begin
  for Surface := Low(TAtlasDocSurface) to High(TAtlasDocSurface) do
  begin
    FLast[Surface] := False;
  end;
end;

{ TAtlasDocIssueLinks }

class procedure TAtlasDocIssueLinks.SetResolver(const AResolver: TAtlasDocIssueUrl);
begin
  FResolver := AResolver;
end;

class procedure TAtlasDocIssueLinks.Clear;
begin
  FResolver := nil;
end;

class function TAtlasDocIssueLinks.Url(const ATarget: string): string;
begin
  Result := '';
  if not ATarget.StartsWith(Prefix, True) or not Assigned(FResolver) then
  begin
    Exit;
  end;
  Result := FResolver(Copy(ATarget, Length(Prefix) + 1, MaxInt));
  // Nur Web-Adressen, wie beim Öffnen aus „Meine Issues“.
  if not (Result.StartsWith('https://', True) or Result.StartsWith('http://', True)) then
  begin
    Result := '';
  end;
end;

{ TAtlasDocLayout }

function TAtlasDocLayout.IsEmpty: Boolean;
begin
  Result := Length(Lines) = 0;
end;

function TAtlasDocLayout.LineAt(AY: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Lines) do
  begin
    if (AY >= Lines[Index].Top - Lines[Index].GapBefore) and (AY < Lines[Index].Bottom) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function TAtlasDocLayout.LinkAt(AX, AY: Integer): Integer;
var
  Line: Integer;
  Span: TAtlasDocSpan;
begin
  Result := -1;
  Line := LineAt(AY);
  if (Line < 0) or (AY < Lines[Line].Top) then
  begin
    Exit;
  end;
  for Span in Lines[Line].Spans do
  begin
    if (Span.Link >= 0) and (AX >= Span.Left) and (AX < Span.Right) then
    begin
      Exit(Span.Link);
    end;
  end;
end;

/// <summary>Stelle im Stück unter AX: Zeichen, deren Mitte links von AX liegt, gehören dazu.</summary>
function SpanPosition(const ASpan: TAtlasDocSpan; AX: Integer; const AMeasure: TAtlasDocMeasure): Integer;
var
  mCount: Integer;
begin
  if AX < ASpan.Left + ASpan.Pad then
  begin
    Exit(ASpan.TextStart);
  end;
  mCount := 0;
  while (mCount < Length(ASpan.Text)) and
    (ASpan.Left + ASpan.Pad + (AMeasure(Copy(ASpan.Text, 1, mCount), ASpan.Face) +
    AMeasure(Copy(ASpan.Text, 1, mCount + 1), ASpan.Face)) div 2 <= AX) do
  begin
    Inc(mCount);
  end;
  Result := ASpan.TextStart + mCount;
end;

/// <summary>Stelle in einer Zeile mit Stücken; links davor Anfang, rechts dahinter Ende.</summary>
function LinePosition(const ASpans: TArray<TAtlasDocSpan>; AX: Integer; const AMeasure: TAtlasDocMeasure): Integer;
var
  mSpan: TAtlasDocSpan;
begin
  if AX < ASpans[0].Left then
  begin
    Exit(ASpans[0].TextStart);
  end;
  for mSpan in ASpans do
  begin
    if AX < mSpan.Right then
    begin
      Exit(SpanPosition(mSpan, AX, AMeasure));
    end;
  end;
  mSpan := ASpans[High(ASpans)];
  Result := mSpan.TextStart + Length(mSpan.Text);
end;

function TAtlasDocLayout.FirstTextFrom(ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := ALine to High(Lines) do
  begin
    if Length(Lines[mIndex].Spans) > 0 then
    begin
      Exit(Lines[mIndex].Spans[0].TextStart);
    end;
  end;
  Result := Length(Text);
end;

function TAtlasDocLayout.LineBelow(AY: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Lines) do
  begin
    if AY < Lines[mIndex].Top then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasDocLayout.PositionAt(AX, AY: Integer; const AMeasure: TAtlasDocMeasure): Integer;
var
  mLine: Integer;
begin
  if (Length(Lines) = 0) or (AY < Lines[0].Top - Lines[0].GapBefore) then
  begin
    Exit(0);
  end;
  mLine := LineAt(AY);
  if mLine < 0 then
  begin
    // Unterhalb bzw. zwischen Zeilen: Ende bzw. nächste Zeile.
    mLine := LineBelow(AY);
    if mLine < 0 then
    begin
      Exit(Length(Text));
    end;
    Exit(PositionAt(AX, Lines[mLine].Top, AMeasure));
  end;
  // Leere Zeile: Anfang der nächsten Zeile mit Text.
  if Length(Lines[mLine].Spans) = 0 then
  begin
    Exit(FirstTextFrom(mLine + 1));
  end;
  Result := LinePosition(Lines[mLine].Spans, AX, AMeasure);
end;

function TAtlasDocLayout.SpanRange(const ASpan: TAtlasDocSpan; AFrom, ATo: Integer;
  const AMeasure: TAtlasDocMeasure; out ALeft, ARight: Integer): Boolean;
var
  From, Till: Integer;
begin
  From := Max(AFrom, ASpan.TextStart) - ASpan.TextStart;
  Till := Min(ATo, ASpan.TextStart + Length(ASpan.Text)) - ASpan.TextStart;
  Result := Till > From;
  if not Result then
  begin
    Exit;
  end;
  ALeft := ASpan.Left + ASpan.Pad + AMeasure(Copy(ASpan.Text, 1, From), ASpan.Face);
  ARight := ASpan.Left + ASpan.Pad + AMeasure(Copy(ASpan.Text, 1, Till), ASpan.Face);
end;

function TAtlasDocLayout.Selected(AFrom, ATo: Integer): string;
var
  From, Till: Integer;
begin
  From := EnsureRange(Min(AFrom, ATo), 0, Length(Text));
  Till := EnsureRange(Max(AFrom, ATo), 0, Length(Text));
  Result := Copy(Text, From + 1, Till - From);
end;

function TAtlasDocLayout.HeightOfLines(ALines: Integer): Integer;
begin
  if (ALines <= 0) or (ALines >= Length(Lines)) then
  begin
    Exit(Height);
  end;
  Result := Lines[ALines - 1].Bottom;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Documentation.Layout', cDocLabels[TAtlasLanguage.German],
    cDocLabels[TAtlasLanguage.English]);

end.
