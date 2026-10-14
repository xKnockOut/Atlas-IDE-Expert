unit Atlas.Core.Documentation.Layout;

// Satz der XMLDoc (#654) für Hover-Tooltip und Detailpanel, ohne VCL: Aus der
// strukturierten Doku werden Zeilen mit Stücken (Text, Schrift, Farbe,
// Position), Klickflächen für Verweise und Links und der Klartext zum Kopieren.
// Gemessen wird über einen Rückruf; so lässt sich der Satz ohne Fenster testen.
//
//   - summary: Fließtext mit Umbruch an Wortgrenzen; zu lange Wörter an Zeichen.
//   - param, returns (→), value (Wert), exception (! Klasse, anklickbar):
//     zweispaltig, die Namensspalte höchstens ein Drittel breit; typeparam
//     ebenso unter der Überschrift „Typparameter“.
//   - remarks unter einer Linie, example unter „Beispiel“, seealso als
//     „Siehe auch:“ mit Verweisen.
//   - Läufe: Code und paramref in der Editorschrift (paramref in Akzentfarbe),
//     Verweise in Akzentfarbe, unterstrichen und anklickbar, wenn der Server den
//     Fundort kennt; Links öffnen den Browser; Codeblöcke eingefärbt mit
//     Einrückung; Listen mit hängendem Einzug je Ebene; Tabellen zweispaltig.
//   - Kurzform (Einstellung hints.xmlDocFull aus): Beschreibung höchstens vier,
//     Bemerkungen drei Zeilen (mit „…“), ohne Beispiel und Siehe auch.

interface

uses
  System.SysUtils,
  Atlas.Core.Documentation.Contract;

{$SCOPEDENUMS ON}

type
  TAtlasDocFont = (UI, Mono);

  TAtlasDocColor = (Text, Muted, Accent, Error, Keyword, StringLiteral, Comment, Number);

  TAtlasDocFace = record
    Font: TAtlasDocFont;
    Bold: Boolean;
    Italic: Boolean;
    class function Create(AFont: TAtlasDocFont; ABold: Boolean = False;
      AItalic: Boolean = False): TAtlasDocFace; static;
  end;

  /// <summary>Breite von AText in Pixeln in der Schrift AFace.</summary>
  TAtlasDocMeasure = reference to function(const AText: string; const AFace: TAtlasDocFace): Integer;

  TAtlasDocMetrics = record
    /// <summary>Zeilenhöhe der UI-Schrift bzw. der Editorschrift.</summary>
    LineHeight: Integer;
    MonoHeight: Integer;
    /// <summary>Einzug je Listenebene.</summary>
    Indent: Integer;
    /// <summary>Abstand zwischen Namens- und Textspalte.</summary>
    ColumnGap: Integer;
    ParagraphGap: Integer;
    SectionGap: Integer;
    /// <summary>Höhe der Zeile mit der Trennlinie.</summary>
    SeparatorHeight: Integer;
    /// <summary>Werte für 96 dpi, mit AScale (Pixel je Zoll / 96) multipliziert.</summary>
    class function Create(ALineHeight, AMonoHeight: Integer; AScale: Double): TAtlasDocMetrics; static;
  end;

  /// <summary>Überschriften in der Sprache der IDE.</summary>
  TAtlasDocLabels = record
    TypeParams: string;
    Value: string;
    Example: string;
    SeeAlso: string;
    class function German: TAtlasDocLabels; static;
  end;

  TAtlasDocSpan = record
    Text: string;
    Left: Integer;
    Width: Integer;
    Face: TAtlasDocFace;
    Color: TAtlasDocColor;
    Underline: Boolean;
    /// <summary>Index in Links; -1 ohne.</summary>
    Link: Integer;
    /// <summary>Anfang im Klartext (0-basiert).</summary>
    TextStart: Integer;
    function Right: Integer;
  end;

  TAtlasDocLineKind = (Text, Separator);

  TAtlasDocLine = record
    Kind: TAtlasDocLineKind;
    /// <summary>Abstand über der Zeile.</summary>
    GapBefore: Integer;
    Top: Integer;
    Height: Integer;
    Spans: TArray<TAtlasDocSpan>;
    function Bottom: Integer;
  end;

  TAtlasDocLinkKind = (Ref, Url);

  TAtlasDocLink = record
    Kind: TAtlasDocLinkKind;
    /// <summary>Ref: Ziel mit Fundort.</summary>
    Target: TAtlasDocTarget;
    /// <summary>Url: Adresse.</summary>
    Url: string;
  end;

  TAtlasDocLayout = record
  public const
    /// <summary>Tabellen: Spalte der Begriffe höchstens so viel Prozent der Breite.</summary>
    TermColumnPercent = 45;
    Ellipsis = '…';
  public
    Lines: TArray<TAtlasDocLine>;
    Links: TArray<TAtlasDocLink>;
    /// <summary>Klartext aller Zeilen (CRLF), Grundlage der Markierung.</summary>
    Text: string;
    Height: Integer;
    /// <summary>Kurzform hat Text weggelassen.</summary>
    Shortened: Boolean;
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
    class function Build(const ADoc: TAtlasDoc; AWidth: Integer; const AMetrics: TAtlasDocMetrics;
      const AMeasure: TAtlasDocMeasure; const ALabels: TAtlasDocLabels; AFull: Boolean): TAtlasDocLayout; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Style.Syntax;

type
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
    procedure AddSpan(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor;
      AUnderline: Boolean; ALink: Integer);
    function AddLink(const ALink: TAtlasDocLink): Integer;
    procedure FlowCode(const AText: string);
    procedure LayoutTable(const ARuns: TAtlasDocRuns; var AIndex: Integer; ABaseColor: TAtlasDocColor);
    function IsTableRow(const ARuns: TAtlasDocRuns; AIndex: Integer): Boolean;
    function RowEnd(const ARuns: TAtlasDocRuns; AIndex: Integer): Integer;
    function SingleLineWidth(const ARuns: TAtlasDocRuns; AFrom, ATo: Integer): Integer;
    procedure Shorten(AFirstLine, AMaxLines: Integer);
  public
    Shortened: Boolean;
    constructor Create(AWidth: Integer; const AMetrics: TAtlasDocMetrics; const AMeasure: TAtlasDocMeasure);
    procedure NewLine;
    procedure Gap(AValue: Integer);
    procedure SetBase(ALeft: Integer);
    /// <summary>Text mit Umbruch an Wortgrenzen ab der aktuellen Stelle.</summary>
    procedure AddWords(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor;
      AUnderline: Boolean = False; ALink: Integer = -1);
    procedure FlowRuns(const ARuns: TAtlasDocRuns; ABaseColor: TAtlasDocColor);
    procedure Separator;
    procedure Heading(const AText: string);
    /// <summary>Name links (in Spalte AColumn), Läufe rechts davon.</summary>
    procedure Entry(const ALabel: string; const ALabelFace: TAtlasDocFace; ALabelColor: TAtlasDocColor;
      ALabelLink: Integer; AColumn: Integer; const ARuns: TAtlasDocRuns; AColor: TAtlasDocColor);
    procedure Section(const ASection: TAtlasDocSection; AColor: TAtlasDocColor; AMaxLines: Integer);
    function LineCount: Integer;
    property Lines: TArray<TAtlasDocLine> read FLines;
    property Links: TArray<TAtlasDocLink> read FLinks;
  end;

{ TAtlasDocFace }

class function TAtlasDocFace.Create(AFont: TAtlasDocFont; ABold, AItalic: Boolean): TAtlasDocFace;
begin
  Result.Font := AFont;
  Result.Bold := ABold;
  Result.Italic := AItalic;
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
  Result.SeparatorHeight := Round(9 * AScale);
end;

{ TAtlasDocLabels }

class function TAtlasDocLabels.German: TAtlasDocLabels;
begin
  Result.TypeParams := 'Typparameter';
  Result.Value := 'Wert';
  Result.Example := 'Beispiel';
  Result.SeeAlso := 'Siehe auch:';
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
  Line.Kind := TAtlasDocLineKind.Text;
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
    if (Span.Right = FX) and (Span.Face.Font = AFace.Font) and (Span.Face.Bold = AFace.Bold) and
      (Span.Face.Italic = AFace.Italic) and (Span.Color = AColor) and (Span.Underline = AUnderline) and
      (Span.Link = ALink) then
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

procedure TLayoutBuilder.FlowCode(const AText: string);
var
  CodeLine: string;
  Tokens: TAtlasTokens;
  Token: TAtlasToken;
  Color: TAtlasDocColor;
  Piece: string;
  Face: TAtlasDocFace;
  Count: Integer;
begin
  Gap(FMetrics.ParagraphGap);
  for CodeLine in AText.Split([#10]) do
  begin
    NewLine;
    OpenLine;
    Tokens := TAtlasSyntax.Tokens(CodeLine);
    for Token in Tokens do
    begin
      case Token.Kind of
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
      Face := TAtlasDocFace.Create(TAtlasDocFont.Mono, Token.Kind = TAtlasTokenKind.Keyword);
      Piece := Copy(CodeLine, Token.Start + 1, Token.Stop - Token.Start);
      // Einrückung bleibt; zu lange Zeilen brechen an Zeichen um (kein waagrechtes Scrollen), die
      // Fortsetzung eingerückt.
      while Piece <> '' do
      begin
        if FX + FMeasure(Piece, Face) <= FWidth then
        begin
          AddSpan(Piece, Face, Color, False, -1);
          Break;
        end;
        Count := Length(Piece);
        while (Count > 0) and (FX + FMeasure(Copy(Piece, 1, Count), Face) > FWidth) do
          Dec(Count);
        if (Count = 0) and (FX <= FLeft + FMetrics.Indent) then
          Count := 1;
        if Count > 0 then
        begin
          AddSpan(Copy(Piece, 1, Count), Face, Color, False, -1);
          Delete(Piece, 1, Count);
        end;
        FOpen := False;
        FNextStart := FLeft + FMetrics.Indent;
        OpenLine;
      end;
    end;
  end;
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
  end;
end;

procedure TLayoutBuilder.LayoutTable(const ARuns: TAtlasDocRuns; var AIndex: Integer;
  ABaseColor: TAtlasDocColor);
var
  Index, Stop, Cell, Column, TermWidth, Left, Row: Integer;
  Term, Description: TLayoutBuilder;
  Line: TAtlasDocLine;
  Span: TAtlasDocSpan;

  function CellOf(AFrom, ATo: Integer): Integer;
  var
    Probe: Integer;
  begin
    for Probe := AFrom to ATo - 1 do
      if ARuns[Probe].Kind = TAtlasDocRunKind.Cell then
        Exit(Probe);
    Result := ATo;
  end;

  procedure Take(ASource: TLayoutBuilder; ARow, AOffset: Integer; var ALine: TAtlasDocLine);
  var
    Item: TAtlasDocSpan;
  begin
    if ARow >= ASource.LineCount then
      Exit;
    ALine.Height := Max(ALine.Height, ASource.Lines[ARow].Height);
    for Item in ASource.Lines[ARow].Spans do
    begin
      Span := Item;
      Inc(Span.Left, AOffset);
      if Span.Link >= 0 then
        Span.Link := AddLink(ASource.Links[Span.Link]);
      ALine.Spans := ALine.Spans + [Span];
    end;
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
      NewLine;
      for Row := 0 to Max(Term.LineCount, Description.LineCount) - 1 do
      begin
        Line := Default(TAtlasDocLine);
        Line.Kind := TAtlasDocLineKind.Text;
        Line.Height := FMetrics.LineHeight;
        if Row = 0 then
          Line.GapBefore := Max(FPendingGap, FMetrics.ParagraphGap div 2);
        Take(Term, Row, Left, Line);
        Take(Description, Row, Left + TermWidth + FMetrics.ColumnGap, Line);
        if Length(FLines) = 0 then
          Line.GapBefore := 0;
        FLines := FLines + [Line];
      end;
      FPendingGap := 0;
      Shortened := Shortened or Term.Shortened or Description.Shortened;
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
        AddWords(Run.Text, TAtlasDocFace.Create(TAtlasDocFont.Mono, Run.Bold, Run.Italic),
          TAtlasDocColor.Accent);
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
        begin
          LinkIndex := -1;
          if Run.Target <> '' then
          begin
            Link := Default(TAtlasDocLink);
            Link.Kind := TAtlasDocLinkKind.Url;
            Link.Url := Run.Target;
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
          FlowCode(Run.Text);
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

procedure TLayoutBuilder.Separator;
var
  Line: TAtlasDocLine;
begin
  NewLine;
  Line := Default(TAtlasDocLine);
  Line.Kind := TAtlasDocLineKind.Separator;
  Line.GapBefore := FPendingGap;
  Line.Height := FMetrics.SeparatorHeight;
  FLines := FLines + [Line];
  FPendingGap := 0;
end;

procedure TLayoutBuilder.Heading(const AText: string);
begin
  SetBase(0);
  Gap(FMetrics.SectionGap);
  AddSpan(AText, TAtlasDocFace.Create(TAtlasDocFont.UI, True), TAtlasDocColor.Muted, False, -1);
  NewLine;
end;

procedure TLayoutBuilder.Entry(const ALabel: string; const ALabelFace: TAtlasDocFace; ALabelColor: TAtlasDocColor;
  ALabelLink: Integer; AColumn: Integer; const ARuns: TAtlasDocRuns; AColor: TAtlasDocColor);
begin
  SetBase(0);
  Gap(FMetrics.ParagraphGap div 2);
  OpenLine;
  AddSpan(ALabel, ALabelFace, ALabelColor, ALabelLink >= 0, ALabelLink);
  SetBase(AColumn);
  // Name breiter als die Spalte: Text in der nächsten Zeile.
  if FX + FMetrics.ColumnGap > AColumn then
    NewLine
  else
    FX := AColumn;
  FlowRuns(ARuns, AColor);
  SetBase(0);
  NewLine;
end;

procedure TLayoutBuilder.Shorten(AFirstLine, AMaxLines: Integer);
var
  Last, SpanIndex: Integer;
  Span: TAtlasDocSpan;
begin
  if Length(FLines) - AFirstLine <= AMaxLines then
    Exit;
  Shortened := True;
  SetLength(FLines, AFirstLine + AMaxLines);
  Last := High(FLines);
  if Length(FLines[Last].Spans) = 0 then
    Exit;
  // „…“ an das Ende der letzten Zeile; passt es nicht, das letzte Stück kürzen.
  SpanIndex := High(FLines[Last].Spans);
  Span := FLines[Last].Spans[SpanIndex];
  while (Length(Span.Text) > 1) and (Span.Left + FMeasure(TrimRight(Span.Text) + TAtlasDocLayout.Ellipsis,
    Span.Face) > FWidth) do
    Span.Text := Copy(Span.Text, 1, Length(Span.Text) - 1);
  Span.Text := TrimRight(Span.Text) + TAtlasDocLayout.Ellipsis;
  Span.Width := FMeasure(Span.Text, Span.Face);
  FLines[Last].Spans[SpanIndex] := Span;
  FOpen := False;
end;

procedure TLayoutBuilder.Section(const ASection: TAtlasDocSection; AColor: TAtlasDocColor; AMaxLines: Integer);
var
  First: Integer;
begin
  SetBase(0);
  NewLine;
  First := Length(FLines);
  FlowRuns(ASection.Runs, AColor);
  NewLine;
  if AMaxLines > 0 then
    Shorten(First, AMaxLines);
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
    // Unterhalb bzw. zwischen Zeilen (Linie): Ende bzw. nächste Zeile.
    for Index := 0 to High(Lines) do
      if AY < Lines[Index].Top then
        Exit(PositionAt(AX, Lines[Index].Top, AMeasure));
    Exit(Length(Text));
  end;
  // Leere Zeile bzw. Linie: Anfang der nächsten Zeile mit Text.
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
      if AX < Span.Left then
        Exit(Span.TextStart);
      // Zeichen, dessen Mitte links von AX liegt, gehören dazu.
      Count := 0;
      while (Count < Length(Span.Text)) and
        (Span.Left + (AMeasure(Copy(Span.Text, 1, Count), Span.Face) +
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
  ALeft := ASpan.Left + AMeasure(Copy(ASpan.Text, 1, From), ASpan.Face);
  ARight := ASpan.Left + AMeasure(Copy(ASpan.Text, 1, Till), ASpan.Face);
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

class function TAtlasDocLayout.Build(const ADoc: TAtlasDoc; AWidth: Integer; const AMetrics: TAtlasDocMetrics;
  const AMeasure: TAtlasDocMeasure; const ALabels: TAtlasDocLabels; AFull: Boolean): TAtlasDocLayout;
var
  Builder: TLayoutBuilder;
  Section: TAtlasDocSection;
  Column, Index, LineIndex, SpanIndex, Y, Pen: Integer;
  Mono, Bold: TAtlasDocFace;
  Link: TAtlasDocLink;
  LinkIndex: Integer;
  HeadingDone: Boolean;
  Text_: TStringBuilder;
  Span: TAtlasDocSpan;

  function Limit(AKind: TAtlasDocSectionKind): Integer;
  begin
    Result := 0;
    if AFull then
      Exit;
    if AKind = TAtlasDocSectionKind.Summary then
      Result := TAtlasDocDisplay.ShortSummaryLines
    else if AKind = TAtlasDocSectionKind.Remarks then
      Result := TAtlasDocDisplay.ShortRemarksLines;
  end;

  function LabelOf(const ASection: TAtlasDocSection): string;
  begin
    case ASection.Kind of
      TAtlasDocSectionKind.Returns:
        Result := '→';
      TAtlasDocSectionKind.Value:
        Result := ALabels.Value;
      TAtlasDocSectionKind.Exception:
        Result := '! ' + ASection.Name;
    else
      Result := ASection.Name;
    end;
  end;

begin
  Result := Default(TAtlasDocLayout);
  if ADoc.IsEmpty then
    Exit;
  Mono := TAtlasDocFace.Create(TAtlasDocFont.Mono, True);
  Bold := TAtlasDocFace.Create(TAtlasDocFont.UI, True);
  // Namensspalte: breitester Name der zweispaltigen Abschnitte, höchstens ein Drittel.
  Column := 0;
  for Section in ADoc.Sections do
    if Section.Kind in [TAtlasDocSectionKind.Param, TAtlasDocSectionKind.TypeParam,
      TAtlasDocSectionKind.Returns] then
      Column := Max(Column, AMeasure(LabelOf(Section), Mono))
    else if Section.Kind = TAtlasDocSectionKind.Value then
      Column := Max(Column, AMeasure(LabelOf(Section), Bold));
  Column := Min(Column, AWidth div 3);
  Builder := TLayoutBuilder.Create(AWidth, AMetrics, AMeasure);
  try
    HeadingDone := False;
    for Index := 0 to High(ADoc.Sections) do
    begin
      Section := ADoc.Sections[Index];
      case Section.Kind of
        TAtlasDocSectionKind.Summary:
          Builder.Section(Section, TAtlasDocColor.Text, Limit(Section.Kind));
        TAtlasDocSectionKind.Param:
          Builder.Entry(LabelOf(Section), Mono, TAtlasDocColor.Accent, -1, Column + AMetrics.ColumnGap,
            Section.Runs, TAtlasDocColor.Muted);
        TAtlasDocSectionKind.TypeParam:
          begin
            if not HeadingDone then
              Builder.Heading(ALabels.TypeParams);
            HeadingDone := True;
            Builder.Entry(LabelOf(Section), Mono, TAtlasDocColor.Accent, -1, Column + AMetrics.ColumnGap,
              Section.Runs, TAtlasDocColor.Muted);
          end;
        TAtlasDocSectionKind.Returns:
          Builder.Entry(LabelOf(Section), Mono, TAtlasDocColor.Accent, -1, Column + AMetrics.ColumnGap,
            Section.Runs, TAtlasDocColor.Muted);
        TAtlasDocSectionKind.Value:
          Builder.Entry(LabelOf(Section), Bold, TAtlasDocColor.Accent, -1, Column + AMetrics.ColumnGap,
            Section.Runs, TAtlasDocColor.Muted);
        TAtlasDocSectionKind.Exception:
          begin
            // Klasse anklickbar, wenn der Server sie gefunden hat; eigene Spalte bis zur halben Breite.
            LinkIndex := -1;
            if Section.NameRef.HasLocation then
            begin
              Link := Default(TAtlasDocLink);
              Link.Kind := TAtlasDocLinkKind.Ref;
              Link.Target := Section.NameRef;
              LinkIndex := Builder.AddLink(Link);
            end;
            Builder.Entry(LabelOf(Section), Mono, TAtlasDocColor.Error, LinkIndex,
              Min(AMeasure(LabelOf(Section), Mono), AWidth div 2) + AMetrics.ColumnGap, Section.Runs,
              TAtlasDocColor.Muted);
          end;
        TAtlasDocSectionKind.Remarks:
          begin
            if Index > 0 then
            begin
              Builder.Gap(AMetrics.ParagraphGap);
              Builder.Separator;
            end;
            Builder.Section(Section, TAtlasDocColor.Muted, Limit(Section.Kind));
          end;
        TAtlasDocSectionKind.Example:
          if AFull then
          begin
            Builder.Heading(ALabels.Example);
            Builder.Section(Section, TAtlasDocColor.Text, 0);
          end
          else
            Builder.Shortened := True;
        TAtlasDocSectionKind.SeeAlso:
          if AFull then
          begin
            Builder.SetBase(0);
            Builder.Gap(AMetrics.SectionGap);
            Builder.AddSpan(ALabels.SeeAlso + ' ', TAtlasDocFace.Create(TAtlasDocFont.UI, True),
              TAtlasDocColor.Muted, False, -1);
            Builder.FlowRuns(Section.Runs, TAtlasDocColor.Text);
            Builder.NewLine;
          end
          else
            Builder.Shortened := True;
      end;
      // Nach dem Abschnitt Abstand; zwischen gleichartigen Einträgen nur der halbe.
      if (Index < High(ADoc.Sections)) and (ADoc.Sections[Index + 1].Kind <> Section.Kind) then
        Builder.Gap(AMetrics.SectionGap);
    end;
    Result.Lines := Builder.Lines;
    Result.Links := Builder.Links;
    Result.Shortened := Builder.Shortened;
  finally
    Builder.Free;
  end;
  // Leere Zeilen am Ende weg; dann Positionen und Klartext.
  while (Length(Result.Lines) > 0) and (Result.Lines[High(Result.Lines)].Kind = TAtlasDocLineKind.Text) and
    (Length(Result.Lines[High(Result.Lines)].Spans) = 0) do
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
      if Result.Lines[LineIndex].Kind = TAtlasDocLineKind.Separator then
        Continue;
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
