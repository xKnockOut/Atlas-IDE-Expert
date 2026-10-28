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
//     Tabellen zweispaltig.
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
  Atlas.Core.Documentation.Contract;

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
    class function German: TAtlasDocLabels; static;
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
    /// <summary>Weitere Abschnitte außer der Beschreibung: Nur dann gibt es den Schalter.</summary>
    class function IsCollapsible(const ADoc: TAtlasDoc): Boolean; static;
    /// <summary>Verborgenes im zugeklappten Zustand: Text und Farbe je Teil.</summary>
    class function HiddenParts(const ADoc: TAtlasDoc; const ASignature: TAtlasDocSignature;
      const ALabels: TAtlasDocLabels; out AColors: TArray<TAtlasDocColor>): TArray<string>; static;
    /// <summary>Aufgeklappt, ohne Signatur.</summary>
    class function Build(const ADoc: TAtlasDoc; AWidth: Integer; const AMetrics: TAtlasDocMetrics;
      const AMeasure: TAtlasDocMeasure; const ALabels: TAtlasDocLabels): TAtlasDocLayout; overload; static;
    /// <summary>ASignature aus der Deklaration ordnet die Parameter; AExpanded = aufgeklappt.</summary>
    class function Build(const ADoc: TAtlasDoc; AWidth: Integer; const AMetrics: TAtlasDocMetrics;
      const AMeasure: TAtlasDocMeasure; const ALabels: TAtlasDocLabels; const ASignature: TAtlasDocSignature;
      AExpanded: Boolean): TAtlasDocLayout; overload; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Style.Syntax;

type
  /// <summary>Zelle einer Zeile mit Spalten: Läufe oder ein Text in fester Schrift und Farbe.</summary>
  TDocCell = record
    HasRuns: Boolean;
    Runs: TAtlasDocRuns;
    Text: string;
    Face: TAtlasDocFace;
    Color: TAtlasDocColor;
    HasLink: Boolean;
    Link: TAtlasDocLink;
    class function OfRuns(const ARuns: TAtlasDocRuns; AColor: TAtlasDocColor): TDocCell; static;
    class function OfText(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor): TDocCell;
      static;
  end;

  TDocRow = TArray<TDocCell>;

  TLayoutBuilder = class
  private
    FMetrics: TAtlasDocMetrics;
    FMeasure: TAtlasDocMeasure;
    FLines: TArray<TAtlasDocLine>;
    FLinks: TArray<TAtlasDocLink>;
    FWidth: Integer;
    /// <summary>Linker Rand des Abschnitts; Absätze kehren dorthin zurück.</summary>
    FBase: Integer;
    /// <summary>Linker Rand nach einem Zeilenumbruch im Text bzw. nach automatischem Umbruch.</summary>
    FLeft: Integer;
    FHang: Integer;
    FNextStart: Integer;
    FX: Integer;
    FOpen: Boolean;
    FPendingGap: Integer;
    function HeightOf(const AFace: TAtlasDocFace): Integer;
    procedure OpenLine;
    procedure AddPill(const AText: string; const AFace: TAtlasDocFace);
    procedure FlowCode(const AText: string; AHighlight: Boolean);
    procedure LayoutTable(const ARuns: TAtlasDocRuns; var AIndex: Integer; ABaseColor: TAtlasDocColor);
    function IsTableRow(const ARuns: TAtlasDocRuns; AIndex: Integer): Boolean;
    function RowEnd(const ARuns: TAtlasDocRuns; AIndex: Integer): Integer;
    function SingleLineWidth(const ARuns: TAtlasDocRuns; AFrom, ATo: Integer): Integer;
    procedure Merge(const ABuilders: TArray<TLayoutBuilder>; const ALefts: TArray<Integer>; AGap: Integer);
  public
    constructor Create(AWidth: Integer; const AMetrics: TAtlasDocMetrics; const AMeasure: TAtlasDocMeasure);
    procedure NewLine;
    procedure Gap(AValue: Integer);
    procedure SetBase(ALeft: Integer);
    procedure AddSpan(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor;
      AUnderline: Boolean; ALink: Integer);
    function AddLink(const ALink: TAtlasDocLink): Integer;
    /// <summary>Text mit Umbruch an Wortgrenzen ab der aktuellen Stelle.</summary>
    procedure AddWords(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor); overload;
    procedure AddWords(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor;
      AUnderline: Boolean; ALink: Integer); overload;
    /// <summary>Text ohne Umbruch; passt er nicht mehr, in die nächste Zeile.</summary>
    procedure AddWhole(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor; ALink: Integer);
    procedure FlowRuns(const ARuns: TAtlasDocRuns; ABaseColor: TAtlasDocColor);
    /// <summary>Überschrift in Kapitälchen mit Linie bis zum rechten Rand.</summary>
    procedure Heading(const AText: string);
    /// <summary>Zeile mit Spalten der Breiten AWidths; die letzte Zelle füllt den Rest.</summary>
    procedure Columns(const ARow: TDocRow; const AWidths: TArray<Integer>);
    procedure Section(const ASection: TAtlasDocSection; AColor: TAtlasDocColor);
    function LineCount: Integer;
    property Lines: TArray<TAtlasDocLine> read FLines;
    property Links: TArray<TAtlasDocLink> read FLinks;
    property X: Integer read FX;
  end;

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

{ TAtlasDocLabels }

class function TAtlasDocLabels.German: TAtlasDocLabels;
begin
  Result.Params := 'PARAMETER';
  Result.TypeParams := 'TYPPARAMETER';
  Result.Returns := 'RÜCKGABE';
  Result.Value := 'WERT';
  Result.Exceptions := 'AUSNAHMEN';
  Result.Remarks := 'HINWEISE';
  Result.Example := 'BEISPIEL';
  Result.SeeAlso := 'SIEHE AUCH';
  Result.Rationale := 'BEGRÜNDUNG';
  Result.Undocumented := 'nicht dokumentiert';
  Result.More := 'Mehr anzeigen ▾';
  Result.Less := 'Weniger anzeigen ▴';
  Result.CountParam := '%d Parameter';
  Result.CountParams := '%d Parameter';
  Result.CountTypeParam := '%d Typparameter';
  Result.CountTypeParams := '%d Typparameter';
  Result.CountException := '%d Ausnahme';
  Result.CountExceptions := '%d Ausnahmen';
  Result.CountRationale := '%d weitere Begründung';
  Result.CountRationales := '%d weitere Begründungen';
  Result.ItemReturns := 'Rückgabe';
  Result.ItemValue := 'Wert';
  Result.ItemRemarks := 'Hinweis';
  Result.ItemExample := 'Beispiel';
  Result.ItemSeeAlso := 'Siehe auch';
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

{ TDocCell }

class function TDocCell.OfRuns(const ARuns: TAtlasDocRuns; AColor: TAtlasDocColor): TDocCell;
begin
  Result := Default(TDocCell);
  Result.HasRuns := True;
  Result.Runs := ARuns;
  Result.Color := AColor;
end;

class function TDocCell.OfText(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor): TDocCell;
begin
  Result := Default(TDocCell);
  Result.Text := AText;
  Result.Face := AFace;
  Result.Color := AColor;
end;

{ TLayoutBuilder }

constructor TLayoutBuilder.Create(AWidth: Integer; const AMetrics: TAtlasDocMetrics;
  const AMeasure: TAtlasDocMeasure);
begin
  inherited Create;
  FWidth := Max(1, AWidth);
  FMetrics := AMetrics;
  FMeasure := AMeasure;
end;

function TLayoutBuilder.LineCount: Integer;
begin
  Result := Length(FLines);
end;

function TLayoutBuilder.HeightOf(const AFace: TAtlasDocFace): Integer;
begin
  if AFace.Font = TAtlasDocFont.Mono then
    Result := FMetrics.MonoHeight
  else
    Result := FMetrics.LineHeight;
end;

procedure TLayoutBuilder.SetBase(ALeft: Integer);
begin
  FBase := ALeft;
  FLeft := ALeft;
  FHang := ALeft;
  FNextStart := ALeft;
end;

procedure TLayoutBuilder.NewLine;
begin
  FOpen := False;
  FNextStart := FLeft;
end;

procedure TLayoutBuilder.Gap(AValue: Integer);
begin
  NewLine;
  // Kein Abstand vor der ersten Zeile.
  if Length(FLines) > 0 then
    FPendingGap := Max(FPendingGap, AValue);
end;

procedure TLayoutBuilder.OpenLine;
var
  Line: TAtlasDocLine;
begin
  Line := Default(TAtlasDocLine);
  Line.GapBefore := FPendingGap;
  Line.Height := FMetrics.LineHeight;
  FLines := FLines + [Line];
  FPendingGap := 0;
  FOpen := True;
  FX := FNextStart;
end;

function TLayoutBuilder.AddLink(const ALink: TAtlasDocLink): Integer;
begin
  FLinks := FLinks + [ALink];
  Result := High(FLinks);
end;

procedure TLayoutBuilder.AddSpan(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor;
  AUnderline: Boolean; ALink: Integer);
var
  Span: TAtlasDocSpan;
  Width, Last: Integer;
begin
  if AText = '' then
    Exit;
  if not FOpen then
    OpenLine;
  Width := FMeasure(AText, AFace);
  Last := High(FLines);
  // Gleich gestaltetes Stück direkt davor verlängern.
  if Length(FLines[Last].Spans) > 0 then
  begin
    Span := FLines[Last].Spans[High(FLines[Last].Spans)];
    if (Span.Right = FX) and Span.Face.SameAs(AFace) and (Span.Color = AColor) and
      (Span.Underline = AUnderline) and (Span.Link = ALink) and not Span.Pill then
    begin
      Span.Text := Span.Text + AText;
      Span.Width := FMeasure(Span.Text, AFace);
      FLines[Last].Spans[High(FLines[Last].Spans)] := Span;
      FX := Span.Right;
      FLines[Last].Height := Max(FLines[Last].Height, HeightOf(AFace));
      Exit;
    end;
  end;
  Span := Default(TAtlasDocSpan);
  Span.Text := AText;
  Span.Left := FX;
  Span.Width := Width;
  Span.Face := AFace;
  Span.Color := AColor;
  Span.Underline := AUnderline;
  Span.Link := ALink;
  FLines[Last].Spans := FLines[Last].Spans + [Span];
  FLines[Last].Height := Max(FLines[Last].Height, HeightOf(AFace));
  Inc(FX, Width);
end;

procedure TLayoutBuilder.AddPill(const AText: string; const AFace: TAtlasDocFace);
var
  Span: TAtlasDocSpan;
  Width, Last: Integer;
  Bare: string;
begin
  Bare := Trim(AText);
  if Bare = '' then
    Exit;
  Width := FMeasure(Bare, AFace) + 2 * FMetrics.PillPad;
  // Die Pille bleibt ganz: passt sie nicht mehr, in die nächste Zeile.
  if FOpen and (FX > FNextStart) and (FX + Width > FWidth) then
  begin
    FOpen := False;
    FNextStart := FHang;
  end;
  if not FOpen then
    OpenLine;
  Last := High(FLines);
  Span := Default(TAtlasDocSpan);
  Span.Text := Bare;
  Span.Left := FX;
  Span.Width := Width;
  Span.Face := AFace;
  Span.Color := TAtlasDocColor.Accent;
  Span.Pill := True;
  Span.Pad := FMetrics.PillPad;
  Span.Link := -1;
  FLines[Last].Spans := FLines[Last].Spans + [Span];
  FLines[Last].Height := Max(FLines[Last].Height, HeightOf(AFace));
  Inc(FX, Width);
  // Leerzeichen nach dem Namen bleiben als Text.
  if Length(AText) > Length(TrimRight(AText)) then
    AddSpan(' ', TAtlasDocFace.Create(TAtlasDocFont.UI), TAtlasDocColor.Text, False, -1);
end;

procedure TLayoutBuilder.AddWords(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor);
begin
  AddWords(AText, AFace, AColor, False, -1);
end;

procedure TLayoutBuilder.AddWords(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor;
  AUnderline: Boolean; ALink: Integer);
var
  Index, Start, Count: Integer;
  Word, Bare: string;
begin
  Index := 1;
  while Index <= Length(AText) do
  begin
    // Wort samt folgender Leerzeichen.
    Start := Index;
    while (Index <= Length(AText)) and (AText[Index] <> ' ') do
      Inc(Index);
    while (Index <= Length(AText)) and (AText[Index] = ' ') do
      Inc(Index);
    Word := Copy(AText, Start, Index - Start);
    Bare := TrimRight(Word);
    // Am Zeilenanfang keine Leerzeichen.
    if (not FOpen or (FX = FNextStart)) and (Bare = '') then
      Continue;
    if FOpen and (FX > FNextStart) and (Bare <> '') and (FX + FMeasure(Bare, AFace) > FWidth) then
    begin
      FOpen := False;
      FNextStart := FHang;
    end;
    // Wort breiter als die Zeile: an Zeichen trennen, mindestens ein Zeichen je Zeile.
    while (Bare <> '') and (FMeasure(Bare, AFace) > FWidth - IfThen(FOpen, FX, FNextStart)) do
    begin
      Count := Length(Bare) - 1;
      while (Count > 1) and (FMeasure(Copy(Bare, 1, Count), AFace) > FWidth - IfThen(FOpen, FX, FNextStart)) do
        Dec(Count);
      if Count < 1 then
        Break;
      AddSpan(Copy(Bare, 1, Count), AFace, AColor, AUnderline, ALink);
      Delete(Bare, 1, Count);
      Delete(Word, 1, Count);
      FOpen := False;
      FNextStart := FHang;
    end;
    AddSpan(Word, AFace, AColor, AUnderline, ALink);
  end;
end;

procedure TLayoutBuilder.AddWhole(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor;
  ALink: Integer);
begin
  if FOpen and (FX > FNextStart) and (FX + FMeasure(AText, AFace) > FWidth) then
  begin
    FOpen := False;
    FNextStart := FHang;
  end;
  AddSpan(AText, AFace, AColor, False, ALink);
end;

procedure TLayoutBuilder.FlowCode(const AText: string; AHighlight: Boolean);
var
  CodeLine: string;
  Tokens: TAtlasTokens;
  Token: TAtlasToken;
  mKind: TAtlasTokenKind;
  Color: TAtlasDocColor;
  Piece: string;
  Face: TAtlasDocFace;
  Count, Shade, Inner, Right: Integer;

  procedure StartCodeLine(AStart: Integer);
  begin
    FOpen := False;
    FNextStart := AStart;
    OpenLine;
    FLines[High(FLines)].Shaded := True;
    FLines[High(FLines)].ShadeLeft := Shade;
    FLines[High(FLines)].Height := FMetrics.MonoHeight;
  end;

begin
  // Schattierte, gerahmte Fläche ab dem linken Rand; Text um CodePad eingerückt.
  Shade := FLeft;
  Inner := FLeft + FMetrics.CodePad;
  Right := Max(Inner + 1, FWidth - FMetrics.CodePad);
  Gap(FMetrics.ParagraphGap);
  for CodeLine in AText.Split([#10]) do
  begin
    StartCodeLine(Inner);
    Tokens := TAtlasSyntax.Tokens(CodeLine);
    for Token in Tokens do
    begin
      // Andere Sprachen (Markdown der Issue-Vorschau, #1264) ohne Delphi-Farben.
      mKind := Token.Kind;
      if not AHighlight then
        mKind := TAtlasTokenKind.Plain;
      case mKind of
        TAtlasTokenKind.Keyword:
          Color := TAtlasDocColor.Keyword;
        TAtlasTokenKind.StringLiteral:
          Color := TAtlasDocColor.StringLiteral;
        TAtlasTokenKind.Comment:
          Color := TAtlasDocColor.Comment;
        TAtlasTokenKind.Number:
          Color := TAtlasDocColor.Number;
      else
        Color := TAtlasDocColor.Text;
      end;
      // Schlüsselwörter halbfett wie in der Deklaration (TAtlasStyledText).
      Face := TAtlasDocFace.Create(TAtlasDocFont.Mono, mKind = TAtlasTokenKind.Keyword);
      Piece := Copy(CodeLine, Token.Start + 1, Token.Stop - Token.Start);
      // Einrückung bleibt; zu lange Zeilen brechen an Zeichen um (kein waagrechtes Scrollen), die
      // Fortsetzung eingerückt.
      while Piece <> '' do
      begin
        if FX + FMeasure(Piece, Face) <= Right then
        begin
          AddSpan(Piece, Face, Color, False, -1);
          Break;
        end;
        Count := Length(Piece);
        while (Count > 0) and (FX + FMeasure(Copy(Piece, 1, Count), Face) > Right) do
          Dec(Count);
        if (Count = 0) and (FX <= Inner + FMetrics.Indent) then
          Count := 1;
        if Count > 0 then
        begin
          AddSpan(Copy(Piece, 1, Count), Face, Color, False, -1);
          Delete(Piece, 1, Count);
        end;
        StartCodeLine(Inner + FMetrics.Indent);
      end;
    end;
  end;
  FOpen := False;
  FNextStart := FLeft;
  Gap(FMetrics.ParagraphGap);
end;

function TLayoutBuilder.RowEnd(const ARuns: TAtlasDocRuns; AIndex: Integer): Integer;
begin
  // AIndex ist ein Bullet; die Zeile endet vor dem nächsten Bullet bzw. Absatz.
  Result := AIndex + 1;
  while (Result <= High(ARuns)) and not (ARuns[Result].Kind in [TAtlasDocRunKind.Bullet,
    TAtlasDocRunKind.Paragraph]) do
    Inc(Result);
end;

function TLayoutBuilder.IsTableRow(const ARuns: TAtlasDocRuns; AIndex: Integer): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if (AIndex > High(ARuns)) or (ARuns[AIndex].Kind <> TAtlasDocRunKind.Bullet) then
    Exit;
  for Index := AIndex + 1 to RowEnd(ARuns, AIndex) - 1 do
    if ARuns[Index].Kind = TAtlasDocRunKind.Cell then
      Exit(True);
end;

function TLayoutBuilder.SingleLineWidth(const ARuns: TAtlasDocRuns; AFrom, ATo: Integer): Integer;
var
  Index: Integer;
  Font: TAtlasDocFont;
begin
  Result := 0;
  for Index := AFrom to ATo - 1 do
  begin
    if ARuns[Index].Kind in [TAtlasDocRunKind.Code, TAtlasDocRunKind.Ref, TAtlasDocRunKind.ParamRef,
      TAtlasDocRunKind.Keyword] then
      Font := TAtlasDocFont.Mono
    else
      Font := TAtlasDocFont.UI;
    Inc(Result, FMeasure(ARuns[Index].Text, TAtlasDocFace.Create(Font, ARuns[Index].Bold, ARuns[Index].Italic)));
    if ARuns[Index].Kind = TAtlasDocRunKind.ParamRef then
      Inc(Result, 2 * FMetrics.PillPad);
  end;
end;

procedure TLayoutBuilder.Merge(const ABuilders: TArray<TLayoutBuilder>; const ALefts: TArray<Integer>;
  AGap: Integer);
var
  Row, Count, Column: Integer;
  Line: TAtlasDocLine;
  Span: TAtlasDocSpan;
  Source: TLayoutBuilder;
begin
  // Zeilen der Spalten nebeneinander; Links der Spalten werden übernommen.
  Count := 0;
  for Source in ABuilders do
    Count := Max(Count, Source.LineCount);
  NewLine;
  for Row := 0 to Count - 1 do
  begin
    Line := Default(TAtlasDocLine);
    Line.Height := FMetrics.LineHeight;
    if Row = 0 then
      Line.GapBefore := Max(FPendingGap, AGap);
    for Column := 0 to High(ABuilders) do
    begin
      Source := ABuilders[Column];
      if Row >= Source.LineCount then
        Continue;
      Line.Height := Max(Line.Height, Source.Lines[Row].Height);
      if Source.Lines[Row].Shaded and not Line.Shaded then
      begin
        Line.Shaded := True;
        Line.ShadeLeft := Source.Lines[Row].ShadeLeft + ALefts[Column];
      end;
      for Span in Source.Lines[Row].Spans do
      begin
        Line.Spans := Line.Spans + [Span];
        Inc(Line.Spans[High(Line.Spans)].Left, ALefts[Column]);
        if Span.Link >= 0 then
          Line.Spans[High(Line.Spans)].Link := AddLink(Source.Links[Span.Link]);
      end;
    end;
    if Length(FLines) = 0 then
      Line.GapBefore := 0;
    FLines := FLines + [Line];
  end;
  FPendingGap := 0;
end;

procedure TLayoutBuilder.LayoutTable(const ARuns: TAtlasDocRuns; var AIndex: Integer;
  ABaseColor: TAtlasDocColor);
var
  Index, Stop, Cell, Column, TermWidth, Left: Integer;
  Term, Description: TLayoutBuilder;

  function CellOf(AFrom, ATo: Integer): Integer;
  var
    Probe: Integer;
  begin
    for Probe := AFrom to ATo - 1 do
      if ARuns[Probe].Kind = TAtlasDocRunKind.Cell then
        Exit(Probe);
    Result := ATo;
  end;

begin
  Left := FLeft + (Max(1, ARuns[AIndex].Level) - 1) * FMetrics.Indent;
  // Breite der Begriffsspalte über alle Zeilen der Tabelle.
  Column := 0;
  Index := AIndex;
  while IsTableRow(ARuns, Index) do
  begin
    Stop := RowEnd(ARuns, Index);
    Column := Max(Column, SingleLineWidth(ARuns, Index + 1, CellOf(Index + 1, Stop)));
    Index := Stop;
  end;
  TermWidth := Min(Column, (FWidth - Left) * TAtlasDocLayout.TermColumnPercent div 100);
  TermWidth := Max(TermWidth, 1);
  while IsTableRow(ARuns, AIndex) do
  begin
    Stop := RowEnd(ARuns, AIndex);
    Cell := CellOf(AIndex + 1, Stop);
    Term := TLayoutBuilder.Create(TermWidth, FMetrics, FMeasure);
    Description := TLayoutBuilder.Create(Max(1, FWidth - Left - TermWidth - FMetrics.ColumnGap), FMetrics,
      FMeasure);
    try
      Term.FlowRuns(Copy(ARuns, AIndex + 1, Cell - AIndex - 1), ABaseColor);
      Description.FlowRuns(Copy(ARuns, Cell + 1, Stop - Cell - 1), ABaseColor);
      Merge([Term, Description], [Left, Left + TermWidth + FMetrics.ColumnGap], FMetrics.ParagraphGap div 2);
    finally
      Term.Free;
      Description.Free;
    end;
    AIndex := Stop;
  end;
  // AIndex steht auf dem Lauf nach der Tabelle; FlowRuns zählt selbst weiter.
  Dec(AIndex);
  NewLine;
end;

procedure TLayoutBuilder.FlowRuns(const ARuns: TAtlasDocRuns; ABaseColor: TAtlasDocColor);
var
  Index: Integer;
  Run: TAtlasDocRun;
  Link: TAtlasDocLink;
  LinkIndex, Bullet: Integer;
begin
  Index := 0;
  while Index <= High(ARuns) do
  begin
    Run := ARuns[Index];
    case Run.Kind of
      TAtlasDocRunKind.Text:
        AddWords(Run.Text, TAtlasDocFace.Create(TAtlasDocFont.UI, Run.Bold, Run.Italic), ABaseColor);
      TAtlasDocRunKind.Code:
        AddWords(Run.Text, TAtlasDocFace.Create(TAtlasDocFont.Mono, Run.Bold, Run.Italic), ABaseColor);
      TAtlasDocRunKind.ParamRef:
        AddPill(Run.Text, TAtlasDocFace.Create(TAtlasDocFont.Mono, Run.Bold, Run.Italic));
      TAtlasDocRunKind.Keyword:
        AddWords(Run.Text, TAtlasDocFace.Create(TAtlasDocFont.Mono, Run.Bold, Run.Italic),
          TAtlasDocColor.Keyword);
      TAtlasDocRunKind.Ref:
        if Run.Location.HasLocation then
        begin
          Link := Default(TAtlasDocLink);
          Link.Kind := TAtlasDocLinkKind.Ref;
          Link.Target := Run.Location;
          LinkIndex := AddLink(Link);
          AddWords(Run.Text, TAtlasDocFace.Create(TAtlasDocFont.Mono, Run.Bold, Run.Italic),
            TAtlasDocColor.Accent, True, LinkIndex);
        end
        else
          AddWords(Run.Text, TAtlasDocFace.Create(TAtlasDocFont.Mono, Run.Bold, Run.Italic),
            TAtlasDocColor.Accent);
      TAtlasDocRunKind.Link:
        if Run.Target.StartsWith(TAtlasDocIssueLinks.Prefix, True) and
          (TAtlasDocIssueLinks.Url(Run.Target) = '') then
          // Issue ohne Tracker (#1123): nicht anklickbar.
          AddWords(Run.Text, TAtlasDocFace.Create(TAtlasDocFont.UI, Run.Bold, Run.Italic), ABaseColor)
        else
        begin
          LinkIndex := -1;
          if Run.Target <> '' then
          begin
            Link := Default(TAtlasDocLink);
            Link.Kind := TAtlasDocLinkKind.Url;
            Link.Url := Run.Target;
            if Run.Target.StartsWith(TAtlasDocIssueLinks.Prefix, True) then
              Link.Url := TAtlasDocIssueLinks.Url(Run.Target);
            LinkIndex := AddLink(Link);
          end;
          AddWords(Run.Text, TAtlasDocFace.Create(TAtlasDocFont.UI, Run.Bold, Run.Italic), TAtlasDocColor.Accent,
            LinkIndex >= 0, LinkIndex);
        end;
      TAtlasDocRunKind.LineBreak:
        begin
          // Innerhalb eines Listenpunkts bleibt der hängende Einzug.
          FOpen := False;
          FLeft := FHang;
          FNextStart := FHang;
        end;
      TAtlasDocRunKind.Paragraph:
        begin
          FLeft := FBase;
          FHang := FBase;
          Gap(FMetrics.ParagraphGap);
        end;
      TAtlasDocRunKind.CodeBlock:
        begin
          FLeft := FBase;
          FHang := FBase;
          FlowCode(Run.Text, Run.IsDelphiCode);
        end;
      TAtlasDocRunKind.Bullet:
        if IsTableRow(ARuns, Index) then
        begin
          FLeft := FBase;
          LayoutTable(ARuns, Index, ABaseColor);
        end
        else
        begin
          NewLine;
          FLeft := FBase + (Max(1, Run.Level) - 1) * FMetrics.Indent;
          FHang := FLeft;
          FNextStart := FLeft;
          OpenLine;
          if Run.Text <> '' then
          begin
            AddSpan(Run.Text, TAtlasDocFace.Create(TAtlasDocFont.UI, Run.Bold), TAtlasDocColor.Muted, False, -1);
            // Fester Platz für die Marke, damit die Texte der Punkte bündig stehen.
            Bullet := Max(FMeasure(Run.Text + ' ', TAtlasDocFace.Create(TAtlasDocFont.UI, Run.Bold)),
              FMeasure('00. ', TAtlasDocFace.Create(TAtlasDocFont.UI)));
            FX := FLeft + Bullet;
            FHang := FX;
          end;
        end;
      TAtlasDocRunKind.Cell:
        AddWords(' – ', TAtlasDocFace.Create(TAtlasDocFont.UI), ABaseColor);
    end;
    Inc(Index);
  end;
end;

procedure TLayoutBuilder.Heading(const AText: string);
begin
  SetBase(0);
  Gap(FMetrics.SectionGap);
  AddSpan(AText, TAtlasDocFace.Heading, TAtlasDocColor.Muted, False, -1);
  FLines[High(FLines)].Rule := True;
  FLines[High(FLines)].RuleFrom := FX + FMetrics.ColumnGap;
  NewLine;
end;

procedure TLayoutBuilder.Columns(const ARow: TDocRow; const AWidths: TArray<Integer>);
var
  Builders: TArray<TLayoutBuilder>;
  Lefts: TArray<Integer>;
  Index, Left, Width, LinkIndex: Integer;
  Cell: TDocCell;
begin
  SetLength(Builders, Length(ARow));
  SetLength(Lefts, Length(ARow));
  try
    Left := 0;
    for Index := 0 to High(ARow) do
    begin
      if Index < High(ARow) then
        Width := AWidths[Index]
      else
        Width := FWidth - Left;
      Lefts[Index] := Left;
      Builders[Index] := TLayoutBuilder.Create(Max(1, Width), FMetrics, FMeasure);
      Cell := ARow[Index];
      if Cell.HasRuns then
        Builders[Index].FlowRuns(Cell.Runs, Cell.Color)
      else
      begin
        LinkIndex := -1;
        if Cell.HasLink then
          LinkIndex := Builders[Index].AddLink(Cell.Link);
        Builders[Index].AddWords(Cell.Text, Cell.Face, Cell.Color, Cell.HasLink, LinkIndex);
      end;
      Inc(Left, Width + FMetrics.ColumnGap);
    end;
    SetBase(0);
    Merge(Builders, Lefts, FMetrics.ParagraphGap div 2);
    NewLine;
  finally
    for Index := 0 to High(Builders) do
      Builders[Index].Free;
  end;
end;

procedure TLayoutBuilder.Section(const ASection: TAtlasDocSection; AColor: TAtlasDocColor);
begin
  SetBase(0);
  NewLine;
  FlowRuns(ASection.Runs, AColor);
  NewLine;
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
    FLast[Surface] := False;
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
    Exit;
  Result := FResolver(Copy(ATarget, Length(Prefix) + 1, MaxInt));
  // Nur Web-Adressen, wie beim Öffnen aus „Meine Issues“.
  if not (Result.StartsWith('https://', True) or Result.StartsWith('http://', True)) then
    Result := '';
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
    if (AY >= Lines[Index].Top - Lines[Index].GapBefore) and (AY < Lines[Index].Bottom) then
      Exit(Index);
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
    Exit;
  for Span in Lines[Line].Spans do
    if (Span.Link >= 0) and (AX >= Span.Left) and (AX < Span.Right) then
      Exit(Span.Link);
end;

function TAtlasDocLayout.PositionAt(AX, AY: Integer; const AMeasure: TAtlasDocMeasure): Integer;
var
  Line, Index, Count: Integer;
  Span: TAtlasDocSpan;
  Spans: TArray<TAtlasDocSpan>;
begin
  if (Length(Lines) = 0) or (AY < Lines[0].Top - Lines[0].GapBefore) then
    Exit(0);
  Line := LineAt(AY);
  if Line < 0 then
  begin
    // Unterhalb bzw. zwischen Zeilen: Ende bzw. nächste Zeile.
    for Index := 0 to High(Lines) do
      if AY < Lines[Index].Top then
        Exit(PositionAt(AX, Lines[Index].Top, AMeasure));
    Exit(Length(Text));
  end;
  // Leere Zeile: Anfang der nächsten Zeile mit Text.
  Spans := Lines[Line].Spans;
  if Length(Spans) = 0 then
  begin
    for Index := Line + 1 to High(Lines) do
      if Length(Lines[Index].Spans) > 0 then
        Exit(Lines[Index].Spans[0].TextStart);
    Exit(Length(Text));
  end;
  if AX < Spans[0].Left then
    Exit(Spans[0].TextStart);
  for Span in Spans do
    if AX < Span.Right then
    begin
      if AX < Span.Left + Span.Pad then
        Exit(Span.TextStart);
      // Zeichen, dessen Mitte links von AX liegt, gehören dazu.
      Count := 0;
      while (Count < Length(Span.Text)) and
        (Span.Left + Span.Pad + (AMeasure(Copy(Span.Text, 1, Count), Span.Face) +
        AMeasure(Copy(Span.Text, 1, Count + 1), Span.Face)) div 2 <= AX) do
        Inc(Count);
      Exit(Span.TextStart + Count);
    end;
  Span := Spans[High(Spans)];
  Result := Span.TextStart + Length(Span.Text);
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
    Exit;
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
    Exit(Height);
  Result := Lines[ALines - 1].Bottom;
end;

class function TAtlasDocLayout.IsCollapsible(const ADoc: TAtlasDoc): Boolean;
var
  Section: TAtlasDocSection;
  Rationale: Integer;
begin
  // Begründungen sind zugeklappt sichtbar, nur über MaxRationale hinaus nicht.
  Rationale := 0;
  for Section in ADoc.Sections do
    if Section.Kind = TAtlasDocSectionKind.Rationale then
      Inc(Rationale)
    else if Section.Kind <> TAtlasDocSectionKind.Summary then
      Exit(True);
  Result := Rationale > MaxRationale;
end;

function SectionsOf(const ADoc: TAtlasDoc; AKind: TAtlasDocSectionKind): TArray<TAtlasDocSection>;
var
  Section: TAtlasDocSection;
begin
  Result := nil;
  for Section in ADoc.Sections do
    if Section.Kind = AKind then
      Result := Result + [Section];
end;

/// <summary>Parameter der Doku, die die Signatur nicht kennt; ohne erkannte Signatur keine.</summary>
function UnknownParams(const ADoc: TAtlasDoc; const ASignature: TAtlasDocSignature): TArray<TAtlasDocSection>;
var
  Section: TAtlasDocSection;
begin
  Result := nil;
  if not ASignature.Known then
    Exit;
  for Section in SectionsOf(ADoc, TAtlasDocSectionKind.Param) do
    if ASignature.IndexOf(Section.Name) < 0 then
      Result := Result + [Section];
end;

function ParamCount(const ADoc: TAtlasDoc; const ASignature: TAtlasDocSignature): Integer;
begin
  if ASignature.Known then
    Result := Length(ASignature.Params) + Length(UnknownParams(ADoc, ASignature))
  else
    Result := Length(SectionsOf(ADoc, TAtlasDocSectionKind.Param));
end;

function HasReturns(const ADoc: TAtlasDoc; const ASignature: TAtlasDocSignature): Boolean;
begin
  Result := ADoc.Has(TAtlasDocSectionKind.Returns) or
    ((ASignature.ResultType <> '') and not ASignature.IsProperty);
end;

function HasValue(const ADoc: TAtlasDoc; const ASignature: TAtlasDocSignature): Boolean;
begin
  Result := ADoc.Has(TAtlasDocSectionKind.Value) or ((ASignature.ResultType <> '') and ASignature.IsProperty);
end;

class function TAtlasDocLayout.HiddenParts(const ADoc: TAtlasDoc; const ASignature: TAtlasDocSignature;
  const ALabels: TAtlasDocLabels; out AColors: TArray<TAtlasDocColor>): TArray<string>;
var
  Count: Integer;
  Parts: TArray<string>;
  Colors: TArray<TAtlasDocColor>;

  procedure Add(const AText: string; AColor: TAtlasDocColor);
  begin
    Parts := Parts + [AText];
    Colors := Colors + [AColor];
  end;

  function Counted(ACount: Integer; const AOne, AMany: string): string;
  begin
    if ACount = 1 then
      Result := Format(AOne, [ACount])
    else
      Result := Format(AMany, [ACount]);
  end;

begin
  Parts := nil;
  Colors := nil;
  Count := ParamCount(ADoc, ASignature);
  if Count > 0 then
    Add(Counted(Count, ALabels.CountParam, ALabels.CountParams), TAtlasDocColor.Muted);
  Count := Length(SectionsOf(ADoc, TAtlasDocSectionKind.TypeParam));
  if Count > 0 then
    Add(Counted(Count, ALabels.CountTypeParam, ALabels.CountTypeParams), TAtlasDocColor.Muted);
  if HasReturns(ADoc, ASignature) then
    Add(ALabels.ItemReturns, TAtlasDocColor.Muted);
  if HasValue(ADoc, ASignature) then
    Add(ALabels.ItemValue, TAtlasDocColor.Muted);
  Count := Length(SectionsOf(ADoc, TAtlasDocSectionKind.Exception));
  if Count > 0 then
    Add(Counted(Count, ALabels.CountException, ALabels.CountExceptions), TAtlasDocColor.Error);
  if ADoc.Has(TAtlasDocSectionKind.Remarks) then
    Add(ALabels.ItemRemarks, TAtlasDocColor.Muted);
  if ADoc.Has(TAtlasDocSectionKind.Example) then
    Add(ALabels.ItemExample, TAtlasDocColor.Muted);
  if ADoc.Has(TAtlasDocSectionKind.SeeAlso) then
    Add(ALabels.ItemSeeAlso, TAtlasDocColor.Muted);
  Count := Length(SectionsOf(ADoc, TAtlasDocSectionKind.Rationale)) - MaxRationale;
  if Count > 0 then
    Add(Counted(Count, ALabels.CountRationale, ALabels.CountRationales), TAtlasDocColor.Muted);
  AColors := Colors;
  Result := Parts;
end;

class function TAtlasDocLayout.Build(const ADoc: TAtlasDoc; AWidth: Integer; const AMetrics: TAtlasDocMetrics;
  const AMeasure: TAtlasDocMeasure; const ALabels: TAtlasDocLabels): TAtlasDocLayout;
begin
  Result := Build(ADoc, AWidth, AMetrics, AMeasure, ALabels, Default(TAtlasDocSignature), True);
end;

class function TAtlasDocLayout.Build(const ADoc: TAtlasDoc; AWidth: Integer; const AMetrics: TAtlasDocMetrics;
  const AMeasure: TAtlasDocMeasure; const ALabels: TAtlasDocLabels; const ASignature: TAtlasDocSignature;
  AExpanded: Boolean): TAtlasDocLayout;
var
  Builder: TLayoutBuilder;
  Section: TAtlasDocSection;
  Sections: TArray<TAtlasDocSection>;
  Param: TAtlasDocParam;
  Parts: TArray<string>;
  PartColors: TArray<TAtlasDocColor>;
  Name, Mono, Muted, UI: TAtlasDocFace;
  NameWidth, TypeWidth, Index, LineIndex, SpanIndex, Y, Pen, Found, Shown: Integer;
  ThreeColumns: Boolean;
  Toggle: TAtlasDocLink;
  Text_: TStringBuilder;
  Span: TAtlasDocSpan;
  Undocumented: TAtlasDocRuns;

  function Width(const AText: string; const AFace: TAtlasDocFace; APercent: Integer): Integer;
  begin
    Result := Min(AMeasure(AText, AFace), AWidth * APercent div 100);
  end;

  function LinkCell(const ASection: TAtlasDocSection): TDocCell;
  begin
    Result := TDocCell.OfText(ASection.Name, Mono, TAtlasDocColor.Error);
    // Klasse anklickbar, wenn der Server sie gefunden hat.
    if ASection.NameRef.HasLocation then
    begin
      Result.HasLink := True;
      Result.Link.Kind := TAtlasDocLinkKind.Ref;
      Result.Link.Target := ASection.NameRef;
    end;
  end;

  procedure TypeAndText(const AType: string; AKind: TAtlasDocSectionKind);
  var
    Docs: TArray<TAtlasDocSection>;
  begin
    Docs := SectionsOf(ADoc, AKind);
    if (AType <> '') and (Length(Docs) > 0) then
      Builder.Columns([TDocCell.OfText(AType, Mono, TAtlasDocColor.Keyword),
        TDocCell.OfRuns(Docs[0].Runs, TAtlasDocColor.Muted)], [Width(AType, Mono, TypeColumnPercent)])
    else if AType <> '' then
      Builder.Columns([TDocCell.OfText(AType, Mono, TAtlasDocColor.Keyword)], nil)
    else if Length(Docs) > 0 then
      Builder.Columns([TDocCell.OfRuns(Docs[0].Runs, TAtlasDocColor.Muted)], nil);
  end;

  procedure ParamRow(const AName, AType: string; const ARuns: TAtlasDocRuns;
    ANameColor, ATextColor: TAtlasDocColor);
  begin
    if ThreeColumns then
      Builder.Columns([TDocCell.OfText(AName, Name, ANameColor), TDocCell.OfText(AType, Muted,
        TAtlasDocColor.Muted), TDocCell.OfRuns(ARuns, ATextColor)], [NameWidth, TypeWidth])
    else
      Builder.Columns([TDocCell.OfText(AName, Name, ANameColor), TDocCell.OfRuns(ARuns, ATextColor)],
        [NameWidth]);
  end;

begin
  Result := Default(TAtlasDocLayout);
  if ADoc.IsEmpty then
    Exit;
  Result.Collapsible := IsCollapsible(ADoc);
  Result.Expanded := AExpanded or not Result.Collapsible;
  Name := TAtlasDocFace.Create(TAtlasDocFont.Mono, True);
  Mono := TAtlasDocFace.Create(TAtlasDocFont.Mono);
  Muted := TAtlasDocFace.Create(TAtlasDocFont.Mono);
  UI := TAtlasDocFace.Create(TAtlasDocFont.UI);
  Undocumented := [TAtlasDocRun.Create(TAtlasDocRunKind.Text, ALabels.Undocumented)];
  Undocumented[0].Italic := True;
  Builder := TLayoutBuilder.Create(AWidth, AMetrics, AMeasure);
  try
    for Section in SectionsOf(ADoc, TAtlasDocSectionKind.Summary) do
      Builder.Section(Section, TAtlasDocColor.Text);
    if Result.Expanded and Result.Collapsible then
    begin
      // PARAMETER: in der Reihenfolge der Signatur, dann unbekannte in Warnfarbe.
      if ParamCount(ADoc, ASignature) > 0 then
      begin
        Builder.Heading(ALabels.Params);
        NameWidth := 0;
        TypeWidth := 0;
        ThreeColumns := ASignature.Known and ASignature.HasTypes;
        for Param in ASignature.Params do
        begin
          NameWidth := Max(NameWidth, Width(Param.Name, Name, NameColumnPercent));
          TypeWidth := Max(TypeWidth, Width(Param.TypeText, Muted, TypeColumnPercent));
        end;
        for Section in SectionsOf(ADoc, TAtlasDocSectionKind.Param) do
          NameWidth := Max(NameWidth, Width(Section.Name, Name, NameColumnPercent));
        NameWidth := Max(NameWidth, 1);
        TypeWidth := Max(TypeWidth, 1);
        Sections := SectionsOf(ADoc, TAtlasDocSectionKind.Param);
        if ASignature.Known then
        begin
          for Param in ASignature.Params do
          begin
            Found := -1;
            for Index := 0 to High(Sections) do
              if SameText(Sections[Index].Name, Param.Name) then
              begin
                Found := Index;
                Break;
              end;
            if Found >= 0 then
              ParamRow(Param.Name, Param.TypeText, Sections[Found].Runs, TAtlasDocColor.Accent,
                TAtlasDocColor.Text)
            else
              ParamRow(Param.Name, Param.TypeText, Undocumented, TAtlasDocColor.Accent, TAtlasDocColor.Muted);
          end;
          for Section in UnknownParams(ADoc, ASignature) do
            ParamRow(Section.Name, '', Section.Runs, TAtlasDocColor.Warn, TAtlasDocColor.Warn);
        end
        else
          for Section in Sections do
            ParamRow(Section.Name, '', Section.Runs, TAtlasDocColor.Accent, TAtlasDocColor.Text);
      end;
      Sections := SectionsOf(ADoc, TAtlasDocSectionKind.TypeParam);
      if Length(Sections) > 0 then
      begin
        Builder.Heading(ALabels.TypeParams);
        NameWidth := 1;
        for Section in Sections do
          NameWidth := Max(NameWidth, Width(Section.Name, Name, NameColumnPercent));
        for Section in Sections do
          Builder.Columns([TDocCell.OfText(Section.Name, Name, TAtlasDocColor.Accent),
            TDocCell.OfRuns(Section.Runs, TAtlasDocColor.Text)], [NameWidth]);
      end;
      if HasReturns(ADoc, ASignature) then
      begin
        Builder.Heading(ALabels.Returns);
        if ASignature.IsProperty then
          TypeAndText('', TAtlasDocSectionKind.Returns)
        else
          TypeAndText(ASignature.ResultType, TAtlasDocSectionKind.Returns);
      end;
      if HasValue(ADoc, ASignature) then
      begin
        Builder.Heading(ALabels.Value);
        if ASignature.IsProperty then
          TypeAndText(ASignature.ResultType, TAtlasDocSectionKind.Value)
        else
          TypeAndText('', TAtlasDocSectionKind.Value);
      end;
      Sections := SectionsOf(ADoc, TAtlasDocSectionKind.Exception);
      if Length(Sections) > 0 then
      begin
        Builder.Heading(ALabels.Exceptions);
        NameWidth := 1;
        for Section in Sections do
          NameWidth := Max(NameWidth, Width(Section.Name, Mono, 50));
        for Section in Sections do
          Builder.Columns([LinkCell(Section), TDocCell.OfRuns(Section.Runs, TAtlasDocColor.Muted)], [NameWidth]);
      end;
      Sections := SectionsOf(ADoc, TAtlasDocSectionKind.Remarks);
      if Length(Sections) > 0 then
      begin
        Builder.Heading(ALabels.Remarks);
        for Section in Sections do
          Builder.Section(Section, TAtlasDocColor.Muted);
      end;
      Sections := SectionsOf(ADoc, TAtlasDocSectionKind.Example);
      if Length(Sections) > 0 then
      begin
        Builder.Heading(ALabels.Example);
        for Section in Sections do
          Builder.Section(Section, TAtlasDocColor.Text);
      end;
      // SIEHE AUCH in einer Zeile mit den Verweisen.
      Sections := SectionsOf(ADoc, TAtlasDocSectionKind.SeeAlso);
      if Length(Sections) > 0 then
      begin
        Builder.SetBase(0);
        Builder.Gap(AMetrics.SectionGap);
        Builder.AddSpan(ALabels.SeeAlso, TAtlasDocFace.Heading, TAtlasDocColor.Muted, False, -1);
        Builder.AddSpan('  ', UI, TAtlasDocColor.Muted, False, -1);
        for Index := 0 to High(Sections) do
        begin
          if Index > 0 then
            Builder.AddWords(', ', UI, TAtlasDocColor.Muted);
          Builder.FlowRuns(Sections[Index].Runs, TAtlasDocColor.Text);
        end;
        Builder.NewLine;
      end;
    end;
    // BEGRÜNDUNG (#1123) nach der XMLDoc; zugeklappt die ersten MaxRationale.
    Sections := SectionsOf(ADoc, TAtlasDocSectionKind.Rationale);
    if Length(Sections) > 0 then
    begin
      Builder.Heading(ALabels.Rationale);
      Shown := Length(Sections);
      if not Result.Expanded then
        Shown := Min(Shown, MaxRationale);
      NameWidth := 1;
      for Index := 0 to Shown - 1 do
        NameWidth := Max(NameWidth, Width(Sections[Index].Name, Name, NameColumnPercent));
      for Index := 0 to Shown - 1 do
        Builder.Columns([TDocCell.OfText(Sections[Index].Name, Name, TAtlasDocColor.Accent),
          TDocCell.OfRuns(Sections[Index].Runs, TAtlasDocColor.Text)], [NameWidth]);
    end;
    // Schalter: zugeklappt mit dem, was verborgen ist.
    if Result.Collapsible then
    begin
      Toggle := Default(TAtlasDocLink);
      Toggle.Kind := TAtlasDocLinkKind.Toggle;
      Builder.SetBase(0);
      Builder.Gap(AMetrics.SectionGap);
      if Result.Expanded then
        Builder.AddWhole(ALabels.Less, UI, TAtlasDocColor.Accent, Builder.AddLink(Toggle))
      else
      begin
        Builder.AddWhole(ALabels.More, UI, TAtlasDocColor.Accent, Builder.AddLink(Toggle));
        Parts := HiddenParts(ADoc, ASignature, ALabels, PartColors);
        if Length(Parts) > 0 then
          Builder.AddSpan('   ', UI, TAtlasDocColor.Muted, False, -1);
        for Index := 0 to High(Parts) do
        begin
          if Index > 0 then
            Builder.AddWords(Separator, UI, TAtlasDocColor.Muted);
          Builder.AddWords(Parts[Index], UI, PartColors[Index]);
        end;
      end;
      Builder.NewLine;
    end;
    Result.Lines := Builder.Lines;
    Result.Links := Builder.Links;
  finally
    Builder.Free;
  end;
  // Leere Zeilen am Ende weg; dann Positionen und Klartext.
  while (Length(Result.Lines) > 0) and (Length(Result.Lines[High(Result.Lines)].Spans) = 0) do
    SetLength(Result.Lines, Length(Result.Lines) - 1);
  Y := 0;
  Text_ := TStringBuilder.Create;
  try
    for LineIndex := 0 to High(Result.Lines) do
    begin
      if LineIndex = 0 then
        Result.Lines[LineIndex].GapBefore := 0;
      Inc(Y, Result.Lines[LineIndex].GapBefore);
      Result.Lines[LineIndex].Top := Y;
      Inc(Y, Result.Lines[LineIndex].Height);
      if Text_.Length > 0 then
        Text_.Append(#13#10);
      Pen := -1;
      for SpanIndex := 0 to High(Result.Lines[LineIndex].Spans) do
      begin
        Span := Result.Lines[LineIndex].Spans[SpanIndex];
        // Sprung in eine andere Spalte als Tabulator.
        if (Pen >= 0) and (Span.Left > Pen + 1) and (Text_.Length > 0) and
          not CharInSet(Text_.Chars[Text_.Length - 1], [' ', #9]) then
          Text_.Append(#9);
        Result.Lines[LineIndex].Spans[SpanIndex].TextStart := Text_.Length;
        Text_.Append(Span.Text);
        Pen := Span.Right;
      end;
    end;
    Result.Text := Text_.ToString;
  finally
    Text_.Free;
  end;
  Result.Height := Y;
end;

end.
