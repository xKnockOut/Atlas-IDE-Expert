unit Atlas.Core.Documentation.Typeset;

// Satz der XMLDoc (#654, #770): baut aus der strukturierten Doku die Zeilen, Stücke und Links eines
// TAtlasDocLayout (Atlas.Core.Documentation.Layout, dort Typen und Abfragen). TLayoutBuilder setzt Läufe mit
// Umbruch, Codeblöcken, Listen und Spalten; TDocSections ordnet die Abschnitte in fester Reihenfolge (PARAMETER,
// TYPPARAMETER, RÜCKGABE, WERT, AUSNAHMEN, HINWEISE, BEISPIEL, SIEHE AUCH, BEGRÜNDUNG) und setzt den Schalter
// „Mehr/Weniger anzeigen“. Der Inhalt einer Unit (#1921) steht zuletzt und immer offen: je Überschrift des
// Servers die Gruppen als Zeilen mit Gruppenname und Namen.
//
// Mit offener Signatur (#1919, hover.signatureParams) stehen PARAMETER und RÜCKGABE aus der Deklaration auch
// zugeklappt und ohne XMLDoc unter der Beschreibung, wie bei Help Insight; der Schalter verbirgt dann nur den Rest.

interface

uses
  System.SysUtils,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Documentation.Layout;

{$SCOPEDENUMS ON}

type
  /// <summary>Was gesetzt wird: Doku, Signatur aus der Deklaration (ordnet die Parameter) und ob aufgeklappt.
  /// </summary>
  TAtlasDocContent = record
    Doc: TAtlasDoc;
    Signature: TAtlasDocSignature;
    Expanded: Boolean;
    /// <summary>Parameter und Rückgabe der Signatur immer offen, auch ohne XMLDoc (#1919).</summary>
    OpenSignature: Boolean;
    class function Create(const ADoc: TAtlasDoc; const ASignature: TAtlasDocSignature;
      AExpanded: Boolean): TAtlasDocContent; static;
    /// <summary>Offene Signatur mit Parametern oder Rückgabe: Diese Abschnitte stehen auch zugeklappt da.</summary>
    function SignatureShown: Boolean;
  end;

  TAtlasDocTypeset = class
  public
    /// <summary>Weitere Abschnitte außer der Beschreibung: Nur dann gibt es den Schalter.</summary>
    class function IsCollapsible(const ADoc: TAtlasDoc): Boolean; overload; static;
    /// <summary>Wie oben; bei offener Signatur zählen Parameter und Rückgabe nicht als verborgen.</summary>
    class function IsCollapsible(const AContent: TAtlasDocContent): Boolean; overload; static;
    /// <summary>Verborgenes im zugeklappten Zustand: Text und Farbe je Teil.</summary>
    class function HiddenParts(const ADoc: TAtlasDoc; const ASignature: TAtlasDocSignature;
      const ALabels: TAtlasDocLabels; out AColors: TArray<TAtlasDocColor>): TArray<string>; overload; static;
    /// <summary>Wie oben; bei offener Signatur ohne Parameter und Rückgabe, die schon dastehen.</summary>
    class function HiddenParts(const AContent: TAtlasDocContent; const ALabels: TAtlasDocLabels;
      out AColors: TArray<TAtlasDocColor>): TArray<string>; overload; static;
    /// <summary>Aufgeklappt, ohne Signatur.</summary>
    class function Build(const ADoc: TAtlasDoc; AWidth: Integer; const AMetrics: TAtlasDocMetrics;
      const AMeasure: TAtlasDocMeasure; const ALabels: TAtlasDocLabels): TAtlasDocLayout; overload; static;
    /// <summary>Signatur des Inhalts ordnet die Parameter; Expanded = aufgeklappt.</summary>
    class function Build(const AContent: TAtlasDocContent; AWidth: Integer; const AMetrics: TAtlasDocMetrics;
      const AMeasure: TAtlasDocMeasure; const ALabels: TAtlasDocLabels): TAtlasDocLayout; overload; static;
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

  /// <summary>Codefläche: Text ab Inner, Umbruch vor Right.</summary>
  TCodeArea = record
    Inner: Integer;
    Right: Integer;
  end;

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
    procedure OpenLine;
    procedure AddPill(const AText: string; const AFace: TAtlasDocFace);
    procedure FlowCode(const AText: string; AHighlight: Boolean);
    procedure LayoutTable(const ARuns: TAtlasDocRuns; var AIndex: Integer; ABaseColor: TAtlasDocColor);
    procedure Merge(const ABuilders: TArray<TLayoutBuilder>; const ALefts: TArray<Integer>; AGap: Integer);
    /// <summary>Weiter in der nächsten Zeile mit hängendem Einzug.</summary>
    procedure WrapLine;
    /// <summary>Platz in der Zeile ab der aktuellen Stelle.</summary>
    function Available: Integer;
    /// <summary>Ein Wort samt folgender Leerzeichen; zu breite Wörter an Zeichen getrennt.</summary>
    procedure AddWord(const AWord: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor; AUnderline: Boolean;
      ALink: Integer);
    /// <summary>Neue Codezeile auf schattierter Fläche ab AShade, Text ab AStart.</summary>
    procedure StartCodeLine(AStart, AShade: Integer);
    /// <summary>Stück einer Codezeile bis ARight, zu lange an Zeichen umgebrochen und eingerückt.</summary>
    procedure AddCodePiece(const APiece: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor;
      const ACode: TCodeArea);
    procedure FlowBullet(const ARun: TAtlasDocRun);
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

  /// <summary>Setzt die Abschnitte einer Doku in fester Reihenfolge in einen TLayoutBuilder.</summary>
  TDocSections = class
  private
    FBuilder: TLayoutBuilder;
    FDoc: TAtlasDoc;
    FSignature: TAtlasDocSignature;
    FLabels: TAtlasDocLabels;
    FWidth: Integer;
    FMeasure: TAtlasDocMeasure;
    FName: TAtlasDocFace;
    FMono: TAtlasDocFace;
    FUI: TAtlasDocFace;
    FNameWidth: Integer;
    FTypeWidth: Integer;
    FThreeColumns: Boolean;
    FOpenSignature: Boolean;
    function Width(const AText: string; const AFace: TAtlasDocFace; APercent: Integer): Integer;
    /// <summary>Breite der Namensspalte über die ersten ACount Abschnitte, mindestens 1.</summary>
    function NameColumn(const ASections: TArray<TAtlasDocSection>; ACount: Integer; const AFace: TAtlasDocFace;
      APercent: Integer): Integer;
    function LinkCell(const ASection: TAtlasDocSection): TDocCell;
    procedure TypeAndText(const AType: string; AKind: TAtlasDocSectionKind);
    procedure ParamRow(const AName, AType: string; const ARuns: TAtlasDocRuns; ANameColor, ATextColor: TAtlasDocColor);
    procedure MeasureParams;
    procedure KnownParams(const ASections: TArray<TAtlasDocSection>);
    procedure NamedRows(const ASections: TArray<TAtlasDocSection>; ACount: Integer);
    procedure Params;
    procedure TypeParams;
    procedure ReturnsAndValue;
    procedure Exceptions;
    procedure TextSections(AKind: TAtlasDocSectionKind; const ATitle: string; AColor: TAtlasDocColor);
    procedure SeeAlso(AGap: Integer);
  public
    constructor Create(ABuilder: TLayoutBuilder; const AContent: TAtlasDocContent; const ALabels: TAtlasDocLabels;
      AWidth: Integer; const AMeasure: TAtlasDocMeasure);
    procedure Summary;
    /// <summary>Alle Abschnitte außer Beschreibung und Begründung (nur aufgeklappt).</summary>
    procedure Details(AGap: Integer);
    /// <summary>Offene Signatur zugeklappt (#1919): PARAMETER und RÜCKGABE.</summary>
    procedure SignatureSections;
    procedure Rationale(AExpanded: Boolean);
    /// <summary>Inhalt der Unit (#1921), auch zugeklappt.</summary>
    procedure UnitContents;
    procedure Toggle(AExpanded: Boolean; AGap: Integer);
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

/// <summary>Lässt sich ein Stück gleicher Gestalt direkt an ASpan anhängen?</summary>
function CanExtend(const ASpan: TAtlasDocSpan; AX: Integer; const AFace: TAtlasDocFace; AColor: TAtlasDocColor;
  AUnderline: Boolean; ALink: Integer): Boolean;
begin
  Result := (ASpan.Right = AX) and not ASpan.Pill and ASpan.Face.SameAs(AFace);
  if Result then
  begin
    Result := (ASpan.Color = AColor) and (ASpan.Underline = AUnderline) and (ASpan.Link = ALink);
  end;
end;

/// <summary>Farbe eines Tokens; andere Sprachen (Markdown der Issue-Vorschau, #1264) ohne Delphi-Farben.</summary>
function TokenColor(AKind: TAtlasTokenKind): TAtlasDocColor;
begin
  case AKind of
    TAtlasTokenKind.Keyword:
      Result := TAtlasDocColor.Keyword;
    TAtlasTokenKind.StringLiteral:
      Result := TAtlasDocColor.StringLiteral;
    TAtlasTokenKind.Comment:
      Result := TAtlasDocColor.Comment;
    TAtlasTokenKind.Number:
      Result := TAtlasDocColor.Number;
  else
    Result := TAtlasDocColor.Text;
  end;
end;

function RowEnd(const ARuns: TAtlasDocRuns; AIndex: Integer): Integer;
begin
  // AIndex ist ein Bullet; die Zeile endet vor dem nächsten Bullet bzw. Absatz.
  Result := AIndex + 1;
  while (Result <= High(ARuns)) and not (ARuns[Result].Kind in [TAtlasDocRunKind.Bullet,
    TAtlasDocRunKind.Paragraph]) do
  begin
    Inc(Result);
  end;
end;

function IsTableRow(const ARuns: TAtlasDocRuns; AIndex: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if (AIndex > High(ARuns)) or (ARuns[AIndex].Kind <> TAtlasDocRunKind.Bullet) then
  begin
    Exit;
  end;
  for mIndex := AIndex + 1 to RowEnd(ARuns, AIndex) - 1 do
  begin
    if ARuns[mIndex].Kind = TAtlasDocRunKind.Cell then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Verweis: anklickbar, wenn der Server den Fundort kennt.</summary>
procedure FlowRef(ABuilder: TLayoutBuilder; const ARun: TAtlasDocRun);
var
  mLink: TAtlasDocLink;
  mFace: TAtlasDocFace;
begin
  mFace := TAtlasDocFace.Create(TAtlasDocFont.Mono, ARun.Bold, ARun.Italic);
  if not ARun.Location.HasLocation then
  begin
    ABuilder.AddWords(ARun.Text, mFace, TAtlasDocColor.Accent);
    Exit;
  end;
  mLink := Default(TAtlasDocLink);
  mLink.Kind := TAtlasDocLinkKind.Ref;
  mLink.Target := ARun.Location;
  ABuilder.AddWords(ARun.Text, mFace, TAtlasDocColor.Accent, True, ABuilder.AddLink(mLink));
end;

/// <summary>Link; Issue ohne Tracker (#1123) bleibt Text.</summary>
procedure FlowLink(ABuilder: TLayoutBuilder; const ARun: TAtlasDocRun; ABaseColor: TAtlasDocColor);
var
  mLink: TAtlasDocLink;
  mFace: TAtlasDocFace;
  mIsIssue: Boolean;
  mLinkIndex: Integer;
begin
  mFace := TAtlasDocFace.Create(TAtlasDocFont.UI, ARun.Bold, ARun.Italic);
  mIsIssue := ARun.Target.StartsWith(TAtlasDocIssueLinks.cPrefix, True);
  if mIsIssue and (TAtlasDocIssueLinks.Url(ARun.Target) = '') then
  begin
    ABuilder.AddWords(ARun.Text, mFace, ABaseColor);
    Exit;
  end;
  mLinkIndex := -1;
  if ARun.Target <> '' then
  begin
    mLink := Default(TAtlasDocLink);
    mLink.Kind := TAtlasDocLinkKind.Url;
    mLink.Url := ARun.Target;
    if mIsIssue then
    begin
      mLink.Url := TAtlasDocIssueLinks.Url(ARun.Target);
    end;
    mLinkIndex := ABuilder.AddLink(mLink);
  end;
  ABuilder.AddWords(ARun.Text, mFace, TAtlasDocColor.Accent, mLinkIndex >= 0, mLinkIndex);
end;

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

function HeightOf(const AFace: TAtlasDocFace; const AMetrics: TAtlasDocMetrics): Integer;
begin
  if AFace.Font = TAtlasDocFont.Mono then
  begin
    Result := AMetrics.MonoHeight;
  end
  else
  begin
    Result := AMetrics.LineHeight;
  end;
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
  begin
    FPendingGap := Max(FPendingGap, AValue);
  end;
end;

procedure TLayoutBuilder.OpenLine;
var
  mLine: TAtlasDocLine;
begin
  mLine := Default(TAtlasDocLine);
  mLine.GapBefore := FPendingGap;
  mLine.Height := FMetrics.LineHeight;
  FLines := FLines + [mLine];
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
  mSpan: TAtlasDocSpan;
  mWidth, mLast: Integer;
begin
  if AText = '' then
  begin
    Exit;
  end;
  if not FOpen then
  begin
    OpenLine;
  end;
  mWidth := FMeasure(AText, AFace);
  mLast := High(FLines);
  // Gleich gestaltetes Stück direkt davor verlängern.
  if Length(FLines[mLast].Spans) > 0 then
  begin
    mSpan := FLines[mLast].Spans[High(FLines[mLast].Spans)];
    if CanExtend(mSpan, FX, AFace, AColor, AUnderline, ALink) then
    begin
      mSpan.Text := mSpan.Text + AText;
      mSpan.Width := FMeasure(mSpan.Text, AFace);
      FLines[mLast].Spans[High(FLines[mLast].Spans)] := mSpan;
      FX := mSpan.Right;
      FLines[mLast].Height := Max(FLines[mLast].Height, HeightOf(AFace, FMetrics));
      Exit;
    end;
  end;
  mSpan := Default(TAtlasDocSpan);
  mSpan.Text := AText;
  mSpan.Left := FX;
  mSpan.Width := mWidth;
  mSpan.Face := AFace;
  mSpan.Color := AColor;
  mSpan.Underline := AUnderline;
  mSpan.Link := ALink;
  FLines[mLast].Spans := FLines[mLast].Spans + [mSpan];
  FLines[mLast].Height := Max(FLines[mLast].Height, HeightOf(AFace, FMetrics));
  Inc(FX, mWidth);
end;

procedure TLayoutBuilder.AddPill(const AText: string; const AFace: TAtlasDocFace);
var
  mSpan: TAtlasDocSpan;
  mWidth, mLast: Integer;
  mBare: string;
begin
  mBare := Trim(AText);
  if mBare = '' then
  begin
    Exit;
  end;
  mWidth := FMeasure(mBare, AFace) + 2 * FMetrics.PillPad;
  // Die Pille bleibt ganz: passt sie nicht mehr, in die nächste Zeile.
  if FOpen and (FX > FNextStart) and (FX + mWidth > FWidth) then
  begin
    WrapLine;
  end;
  if not FOpen then
  begin
    OpenLine;
  end;
  mLast := High(FLines);
  mSpan := Default(TAtlasDocSpan);
  mSpan.Text := mBare;
  mSpan.Left := FX;
  mSpan.Width := mWidth;
  mSpan.Face := AFace;
  mSpan.Color := TAtlasDocColor.Accent;
  mSpan.Pill := True;
  mSpan.Pad := FMetrics.PillPad;
  mSpan.Link := -1;
  FLines[mLast].Spans := FLines[mLast].Spans + [mSpan];
  FLines[mLast].Height := Max(FLines[mLast].Height, HeightOf(AFace, FMetrics));
  Inc(FX, mWidth);
  // Leerzeichen nach dem Namen bleiben als Text.
  if Length(AText) > Length(TrimRight(AText)) then
  begin
    AddSpan(' ', TAtlasDocFace.Create(TAtlasDocFont.UI), TAtlasDocColor.Text, False, -1);
  end;
end;

procedure TLayoutBuilder.AddWords(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor);
begin
  AddWords(AText, AFace, AColor, False, -1);
end;

procedure TLayoutBuilder.WrapLine;
begin
  FOpen := False;
  FNextStart := FHang;
end;

function TLayoutBuilder.Available: Integer;
begin
  if FOpen then
  begin
    Result := FWidth - FX;
  end
  else
  begin
    Result := FWidth - FNextStart;
  end;
end;

procedure TLayoutBuilder.AddWord(const AWord: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor;
  AUnderline: Boolean; ALink: Integer);
var
  mWord, mBare: string;
  mCount: Integer;
begin
  mWord := AWord;
  mBare := TrimRight(mWord);
  // Am Zeilenanfang keine Leerzeichen.
  if mBare = '' then
  begin
    if FOpen and (FX <> FNextStart) then
    begin
      AddSpan(mWord, AFace, AColor, AUnderline, ALink);
    end;
    Exit;
  end;
  if FOpen and (FX > FNextStart) and (FX + FMeasure(mBare, AFace) > FWidth) then
  begin
    WrapLine;
  end;
  // Wort breiter als die Zeile: an Zeichen trennen, mindestens ein Zeichen je Zeile.
  while (mBare <> '') and (FMeasure(mBare, AFace) > Available) do
  begin
    mCount := Length(mBare) - 1;
    while (mCount > 1) and (FMeasure(Copy(mBare, 1, mCount), AFace) > Available) do
    begin
      Dec(mCount);
    end;
    if mCount < 1 then
    begin
      Break;
    end;
    AddSpan(Copy(mBare, 1, mCount), AFace, AColor, AUnderline, ALink);
    Delete(mBare, 1, mCount);
    Delete(mWord, 1, mCount);
    WrapLine;
  end;
  AddSpan(mWord, AFace, AColor, AUnderline, ALink);
end;

procedure TLayoutBuilder.AddWords(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor;
  AUnderline: Boolean; ALink: Integer);
var
  mIndex, mStart: Integer;
begin
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    // Wort samt folgender Leerzeichen.
    mStart := mIndex;
    while (mIndex <= Length(AText)) and (AText[mIndex] <> ' ') do
    begin
      Inc(mIndex);
    end;
    while (mIndex <= Length(AText)) and (AText[mIndex] = ' ') do
    begin
      Inc(mIndex);
    end;
    AddWord(Copy(AText, mStart, mIndex - mStart), AFace, AColor, AUnderline, ALink);
  end;
end;

procedure TLayoutBuilder.AddWhole(const AText: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor;
  ALink: Integer);
begin
  if FOpen and (FX > FNextStart) and (FX + FMeasure(AText, AFace) > FWidth) then
  begin
    WrapLine;
  end;
  AddSpan(AText, AFace, AColor, False, ALink);
end;

procedure TLayoutBuilder.StartCodeLine(AStart, AShade: Integer);
begin
  FOpen := False;
  FNextStart := AStart;
  OpenLine;
  FLines[High(FLines)].Shaded := True;
  FLines[High(FLines)].ShadeLeft := AShade;
  FLines[High(FLines)].Height := FMetrics.MonoHeight;
end;

procedure TLayoutBuilder.AddCodePiece(const APiece: string; const AFace: TAtlasDocFace; AColor: TAtlasDocColor;
  const ACode: TCodeArea);
var
  mPiece: string;
  mCount: Integer;
begin
  // Einrückung bleibt; zu lange Zeilen brechen an Zeichen um
  // (kein waagrechtes Scrollen), die Fortsetzung eingerückt.
  mPiece := APiece;
  while mPiece <> '' do
  begin
    if FX + FMeasure(mPiece, AFace) <= ACode.Right then
    begin
      AddSpan(mPiece, AFace, AColor, False, -1);
      Exit;
    end;
    mCount := Length(mPiece);
    while (mCount > 0) and (FX + FMeasure(Copy(mPiece, 1, mCount), AFace) > ACode.Right) do
    begin
      Dec(mCount);
    end;
    if (mCount = 0) and (FX <= ACode.Inner + FMetrics.Indent) then
    begin
      mCount := 1;
    end;
    if mCount > 0 then
    begin
      AddSpan(Copy(mPiece, 1, mCount), AFace, AColor, False, -1);
      Delete(mPiece, 1, mCount);
    end;
    StartCodeLine(ACode.Inner + FMetrics.Indent, FLeft);
  end;
end;

procedure TLayoutBuilder.FlowCode(const AText: string; AHighlight: Boolean);
var
  mCodeLine: string;
  mToken: TAtlasToken;
  mKind: TAtlasTokenKind;
  mCode: TCodeArea;
begin
  // Schattierte, gerahmte Fläche ab dem linken Rand; Text um CodePad eingerückt.
  mCode.Inner := FLeft + FMetrics.CodePad;
  mCode.Right := Max(mCode.Inner + 1, FWidth - FMetrics.CodePad);
  Gap(FMetrics.ParagraphGap);
  for mCodeLine in AText.Split([#10]) do
  begin
    StartCodeLine(mCode.Inner, FLeft);
    for mToken in TAtlasSyntax.Tokens(mCodeLine) do
    begin
      mKind := mToken.Kind;
      if not AHighlight then
      begin
        mKind := TAtlasTokenKind.Plain;
      end;
      // Schlüsselwörter halbfett wie in der Deklaration (TAtlasStyledText).
      AddCodePiece(Copy(mCodeLine, mToken.Start + 1, mToken.Stop - mToken.Start),
        TAtlasDocFace.Create(TAtlasDocFont.Mono, mKind = TAtlasTokenKind.Keyword), TokenColor(mKind), mCode);
    end;
  end;
  FOpen := False;
  FNextStart := FLeft;
  Gap(FMetrics.ParagraphGap);
end;

/// <summary>Breite der Läufe [AFrom, ATo) in einer Zeile ohne Umbruch.</summary>
function SingleLineWidth(const ARuns: TAtlasDocRuns; AFrom, ATo: Integer; const AMeasure: TAtlasDocMeasure;
  APillPad: Integer): Integer;
var
  mIndex: Integer;
  mFont: TAtlasDocFont;
begin
  Result := 0;
  for mIndex := AFrom to ATo - 1 do
  begin
    if ARuns[mIndex].Kind in [TAtlasDocRunKind.Code, TAtlasDocRunKind.Ref, TAtlasDocRunKind.ParamRef,
      TAtlasDocRunKind.Keyword] then
    begin
      mFont := TAtlasDocFont.Mono;
    end
    else
    begin
      mFont := TAtlasDocFont.UI;
    end;
    Inc(Result, AMeasure(ARuns[mIndex].Text, TAtlasDocFace.Create(mFont, ARuns[mIndex].Bold, ARuns[mIndex].Italic)));
    if ARuns[mIndex].Kind = TAtlasDocRunKind.ParamRef then
    begin
      Inc(Result, 2 * APillPad);
    end;
  end;
end;

/// <summary>Zeile ARow von ASource um ALeft verschoben in ALine übernehmen; Links landen in ATarget.</summary>
procedure MergeColumn(var ALine: TAtlasDocLine; ATarget, ASource: TLayoutBuilder; ARow, ALeft: Integer);
var
  mSpan: TAtlasDocSpan;
begin
  if ARow >= ASource.LineCount then
  begin
    Exit;
  end;
  ALine.Height := Max(ALine.Height, ASource.Lines[ARow].Height);
  if ASource.Lines[ARow].Shaded and not ALine.Shaded then
  begin
    ALine.Shaded := True;
    ALine.ShadeLeft := ASource.Lines[ARow].ShadeLeft + ALeft;
  end;
  for mSpan in ASource.Lines[ARow].Spans do
  begin
    ALine.Spans := ALine.Spans + [mSpan];
    Inc(ALine.Spans[High(ALine.Spans)].Left, ALeft);
    if mSpan.Link >= 0 then
    begin
      ALine.Spans[High(ALine.Spans)].Link := ATarget.AddLink(ASource.Links[mSpan.Link]);
    end;
  end;
end;

procedure TLayoutBuilder.Merge(const ABuilders: TArray<TLayoutBuilder>; const ALefts: TArray<Integer>;
  AGap: Integer);
var
  mRow, mCount, mColumn: Integer;
  mLine: TAtlasDocLine;
  mSource: TLayoutBuilder;
begin
  // Zeilen der Spalten nebeneinander; Links der Spalten werden übernommen.
  mCount := 0;
  for mSource in ABuilders do
  begin
    mCount := Max(mCount, mSource.LineCount);
  end;
  NewLine;
  for mRow := 0 to mCount - 1 do
  begin
    mLine := Default(TAtlasDocLine);
    mLine.Height := FMetrics.LineHeight;
    if (mRow = 0) and (Length(FLines) > 0) then
    begin
      mLine.GapBefore := Max(FPendingGap, AGap);
    end;
    for mColumn := 0 to High(ABuilders) do
    begin
      MergeColumn(mLine, Self, ABuilders[mColumn], mRow, ALefts[mColumn]);
    end;
    FLines := FLines + [mLine];
  end;
  FPendingGap := 0;
end;

procedure TLayoutBuilder.LayoutTable(const ARuns: TAtlasDocRuns; var AIndex: Integer;
  ABaseColor: TAtlasDocColor);
var
  mIndex, mStop, mCell, mColumn, mTermWidth, mLeft: Integer;
  mTerm, mDescription: TLayoutBuilder;

  function CellOf(AFrom, ATo: Integer): Integer;
  var
    mProbe: Integer;
  begin
    for mProbe := AFrom to ATo - 1 do
    begin
      if ARuns[mProbe].Kind = TAtlasDocRunKind.Cell then
      begin
        Exit(mProbe);
      end;
    end;
    Result := ATo;
  end;

begin
  mLeft := FLeft + (Max(1, ARuns[AIndex].Level) - 1) * FMetrics.Indent;
  // Breite der Begriffsspalte über alle Zeilen der Tabelle.
  mColumn := 0;
  mIndex := AIndex;
  while IsTableRow(ARuns, mIndex) do
  begin
    mStop := RowEnd(ARuns, mIndex);
    mColumn := Max(mColumn, SingleLineWidth(ARuns, mIndex + 1, CellOf(mIndex + 1, mStop), FMeasure,
      FMetrics.PillPad));
    mIndex := mStop;
  end;
  mTermWidth := Min(mColumn, (FWidth - mLeft) * TAtlasDocLayout.cTermColumnPercent div 100);
  mTermWidth := Max(mTermWidth, 1);
  while IsTableRow(ARuns, AIndex) do
  begin
    mStop := RowEnd(ARuns, AIndex);
    mCell := CellOf(AIndex + 1, mStop);
    mTerm := TLayoutBuilder.Create(mTermWidth, FMetrics, FMeasure);
    mDescription := TLayoutBuilder.Create(Max(1, FWidth - mLeft - mTermWidth - FMetrics.ColumnGap), FMetrics,
      FMeasure);
    try
      mTerm.FlowRuns(Copy(ARuns, AIndex + 1, mCell - AIndex - 1), ABaseColor);
      mDescription.FlowRuns(Copy(ARuns, mCell + 1, mStop - mCell - 1), ABaseColor);
      Merge([mTerm, mDescription], [mLeft, mLeft + mTermWidth + FMetrics.ColumnGap], FMetrics.ParagraphGap div 2);
    finally
      mTerm.Free;
      mDescription.Free;
    end;
    AIndex := mStop;
  end;
  // AIndex steht auf dem Lauf nach der Tabelle; FlowRuns zählt selbst weiter.
  Dec(AIndex);
  NewLine;
end;

procedure TLayoutBuilder.FlowBullet(const ARun: TAtlasDocRun);
var
  mLink: TAtlasDocLink;
  mLinkIndex: Integer;
  mColor: TAtlasDocColor;
begin
  NewLine;
  FLeft := FBase + (Max(1, ARun.Level) - 1) * FMetrics.Indent;
  FHang := FLeft;
  FNextStart := FLeft;
  OpenLine;
  if ARun.Text = '' then
  begin
    Exit;
  end;
  // Marke mit Ziel (Kästchen einer Checkliste, #1273): anklickbar in Akzentfarbe, ohne Unterstrich.
  mLinkIndex := -1;
  mColor := TAtlasDocColor.Muted;
  if ARun.Target <> '' then
  begin
    mLink := Default(TAtlasDocLink);
    mLink.Kind := TAtlasDocLinkKind.Url;
    mLink.Url := ARun.Target;
    mLinkIndex := AddLink(mLink);
    mColor := TAtlasDocColor.Accent;
  end;
  AddSpan(ARun.Text, TAtlasDocFace.Create(TAtlasDocFont.UI, ARun.Bold), mColor, False, mLinkIndex);
  // Fester Platz für die Marke, damit die Texte der Punkte bündig stehen.
  FX := FLeft + Max(FMeasure(ARun.Text + ' ', TAtlasDocFace.Create(TAtlasDocFont.UI, ARun.Bold)),
    FMeasure('00. ', TAtlasDocFace.Create(TAtlasDocFont.UI)));
  FHang := FX;
end;

procedure TLayoutBuilder.FlowRuns(const ARuns: TAtlasDocRuns; ABaseColor: TAtlasDocColor);
var
  mIndex: Integer;
  mRun: TAtlasDocRun;
begin
  mIndex := 0;
  while mIndex <= High(ARuns) do
  begin
    mRun := ARuns[mIndex];
    case mRun.Kind of
      TAtlasDocRunKind.Text:
        AddWords(mRun.Text, TAtlasDocFace.Create(TAtlasDocFont.UI, mRun.Bold, mRun.Italic), ABaseColor);
      TAtlasDocRunKind.Code:
        AddWords(mRun.Text, TAtlasDocFace.Create(TAtlasDocFont.Mono, mRun.Bold, mRun.Italic), ABaseColor);
      TAtlasDocRunKind.ParamRef:
        AddPill(mRun.Text, TAtlasDocFace.Create(TAtlasDocFont.Mono, mRun.Bold, mRun.Italic));
      TAtlasDocRunKind.Keyword:
        AddWords(mRun.Text, TAtlasDocFace.Create(TAtlasDocFont.Mono, mRun.Bold, mRun.Italic),
          TAtlasDocColor.Keyword);
      TAtlasDocRunKind.Ref:
        FlowRef(Self, mRun);
      TAtlasDocRunKind.Link:
        FlowLink(Self, mRun, ABaseColor);
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
          FlowCode(mRun.Text, mRun.IsDelphiCode);
        end;
      TAtlasDocRunKind.Bullet:
        if IsTableRow(ARuns, mIndex) then
        begin
          FLeft := FBase;
          LayoutTable(ARuns, mIndex, ABaseColor);
        end
        else
        begin
          FlowBullet(mRun);
        end;
      TAtlasDocRunKind.Cell:
        AddWords(' – ', TAtlasDocFace.Create(TAtlasDocFont.UI), ABaseColor);
    end;
    Inc(mIndex);
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
  mBuilders: TArray<TLayoutBuilder>;
  mLefts: TArray<Integer>;
  mIndex, mLeft, mWidth, mLinkIndex: Integer;
  mCell: TDocCell;
begin
  SetLength(mBuilders, Length(ARow));
  SetLength(mLefts, Length(ARow));
  try
    mLeft := 0;
    for mIndex := 0 to High(ARow) do
    begin
      if mIndex < High(ARow) then
      begin
        mWidth := AWidths[mIndex];
      end
      else
      begin
        mWidth := FWidth - mLeft;
      end;
      mLefts[mIndex] := mLeft;
      mBuilders[mIndex] := TLayoutBuilder.Create(Max(1, mWidth), FMetrics, FMeasure);
      mCell := ARow[mIndex];
      if mCell.HasRuns then
      begin
        mBuilders[mIndex].FlowRuns(mCell.Runs, mCell.Color);
      end
      else
      begin
        mLinkIndex := -1;
        if mCell.HasLink then
        begin
          mLinkIndex := mBuilders[mIndex].AddLink(mCell.Link);
        end;
        mBuilders[mIndex].AddWords(mCell.Text, mCell.Face, mCell.Color, mCell.HasLink, mLinkIndex);
      end;
      Inc(mLeft, mWidth + FMetrics.ColumnGap);
    end;
    SetBase(0);
    Merge(mBuilders, mLefts, FMetrics.ParagraphGap div 2);
    NewLine;
  finally
    for mIndex := 0 to High(mBuilders) do
    begin
      mBuilders[mIndex].Free;
    end;
  end;
end;

procedure TLayoutBuilder.Section(const ASection: TAtlasDocSection; AColor: TAtlasDocColor);
begin
  SetBase(0);
  NewLine;
  FlowRuns(ASection.Runs, AColor);
  NewLine;
end;

type
  TSectionKinds = set of TAtlasDocSectionKind;

/// <summary>Verbirgt der Schalter etwas? Abschnitte der Arten AShown stehen auch zugeklappt da.</summary>
function HasHidden(const ADoc: TAtlasDoc; const AShown: TSectionKinds): Boolean;
var
  mSection: TAtlasDocSection;
  mRationale: Integer;
begin
  // Begründungen sind zugeklappt sichtbar, nur über MaxRationale hinaus nicht.
  mRationale := 0;
  for mSection in ADoc.Sections do
  begin
    if mSection.Kind = TAtlasDocSectionKind.Rationale then
    begin
      Inc(mRationale);
    end
    else if not (mSection.Kind in AShown) then
    begin
      Exit(True);
    end;
  end;
  Result := mRationale > TAtlasDocLayout.cMaxRationale;
end;

class function TAtlasDocTypeset.IsCollapsible(const ADoc: TAtlasDoc): Boolean;
begin
  // Der Inhalt einer Unit (#1921) steht immer da.
  Result := HasHidden(ADoc, [TAtlasDocSectionKind.Summary, TAtlasDocSectionKind.UnitContents]);
end;

class function TAtlasDocTypeset.IsCollapsible(const AContent: TAtlasDocContent): Boolean;
begin
  if AContent.SignatureShown then
  begin
    Result := HasHidden(AContent.Doc, [TAtlasDocSectionKind.Summary, TAtlasDocSectionKind.Param,
      TAtlasDocSectionKind.Returns, TAtlasDocSectionKind.UnitContents]);
  end
  else
  begin
    Result := IsCollapsible(AContent.Doc);
  end;
end;

function SectionsOf(const ADoc: TAtlasDoc; AKind: TAtlasDocSectionKind): TArray<TAtlasDocSection>;
var
  mSection: TAtlasDocSection;
begin
  Result := nil;
  for mSection in ADoc.Sections do
  begin
    if mSection.Kind = AKind then
    begin
      Result := Result + [mSection];
    end;
  end;
end;

/// <summary>Parameter der Doku, die die Signatur nicht kennt; ohne erkannte Signatur keine.</summary>
function UnknownParams(const ADoc: TAtlasDoc; const ASignature: TAtlasDocSignature): TArray<TAtlasDocSection>;
var
  mSection: TAtlasDocSection;
begin
  Result := nil;
  if not ASignature.Known then
  begin
    Exit;
  end;
  for mSection in SectionsOf(ADoc, TAtlasDocSectionKind.Param) do
  begin
    if ASignature.IndexOf(mSection.Name) < 0 then
    begin
      Result := Result + [mSection];
    end;
  end;
end;

function ParamCount(const ADoc: TAtlasDoc; const ASignature: TAtlasDocSignature): Integer;
begin
  if ASignature.Known then
  begin
    Result := Length(ASignature.Params) + Length(UnknownParams(ADoc, ASignature));
  end
  else
  begin
    Result := Length(SectionsOf(ADoc, TAtlasDocSectionKind.Param));
  end;
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

/// <summary>Verborgenes im zugeklappten Zustand; AOpen: Parameter und Rückgabe stehen schon da (#1919).</summary>
function CollectHiddenParts(const ADoc: TAtlasDoc; const ASignature: TAtlasDocSignature;
  const ALabels: TAtlasDocLabels; AOpen: Boolean; out AColors: TArray<TAtlasDocColor>): TArray<string>;
var
  mCount: Integer;
  mParts: TArray<string>;
  mColors: TArray<TAtlasDocColor>;

  procedure Add(const AText: string; AColor: TAtlasDocColor);
  begin
    mParts := mParts + [AText];
    mColors := mColors + [AColor];
  end;

  function Counted(ACount: Integer; const AOne, AMany: string): string;
  begin
    if ACount = 1 then
    begin
      Result := Format(AOne, [ACount]);
    end
    else
    begin
      Result := Format(AMany, [ACount]);
    end;
  end;

begin
  mParts := nil;
  mColors := nil;
  mCount := 0;
  if not AOpen then
  begin
    mCount := ParamCount(ADoc, ASignature);
  end;
  if mCount > 0 then
  begin
    Add(Counted(mCount, ALabels.CountParam, ALabels.CountParams), TAtlasDocColor.Muted);
  end;
  mCount := Length(SectionsOf(ADoc, TAtlasDocSectionKind.TypeParam));
  if mCount > 0 then
  begin
    Add(Counted(mCount, ALabels.CountTypeParam, ALabels.CountTypeParams), TAtlasDocColor.Muted);
  end;
  if not AOpen and HasReturns(ADoc, ASignature) then
  begin
    Add(ALabels.ItemReturns, TAtlasDocColor.Muted);
  end;
  if HasValue(ADoc, ASignature) then
  begin
    Add(ALabels.ItemValue, TAtlasDocColor.Muted);
  end;
  mCount := Length(SectionsOf(ADoc, TAtlasDocSectionKind.Exception));
  if mCount > 0 then
  begin
    Add(Counted(mCount, ALabels.CountException, ALabels.CountExceptions), TAtlasDocColor.Error);
  end;
  if ADoc.Has(TAtlasDocSectionKind.Remarks) then
  begin
    Add(ALabels.ItemRemarks, TAtlasDocColor.Muted);
  end;
  if ADoc.Has(TAtlasDocSectionKind.Example) then
  begin
    Add(ALabels.ItemExample, TAtlasDocColor.Muted);
  end;
  if ADoc.Has(TAtlasDocSectionKind.SeeAlso) then
  begin
    Add(ALabels.ItemSeeAlso, TAtlasDocColor.Muted);
  end;
  mCount := Length(SectionsOf(ADoc, TAtlasDocSectionKind.Rationale)) - TAtlasDocLayout.cMaxRationale;
  if mCount > 0 then
  begin
    Add(Counted(mCount, ALabels.CountRationale, ALabels.CountRationales), TAtlasDocColor.Muted);
  end;
  AColors := mColors;
  Result := mParts;
end;

class function TAtlasDocTypeset.HiddenParts(const ADoc: TAtlasDoc; const ASignature: TAtlasDocSignature;
  const ALabels: TAtlasDocLabels; out AColors: TArray<TAtlasDocColor>): TArray<string>;
begin
  Result := CollectHiddenParts(ADoc, ASignature, ALabels, False, AColors);
end;

class function TAtlasDocTypeset.HiddenParts(const AContent: TAtlasDocContent; const ALabels: TAtlasDocLabels;
  out AColors: TArray<TAtlasDocColor>): TArray<string>;
begin
  Result := CollectHiddenParts(AContent.Doc, AContent.Signature, ALabels, AContent.SignatureShown, AColors);
end;

function SectionIndex(const ASections: TArray<TAtlasDocSection>; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ASections) do
  begin
    if SameText(ASections[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

{ TDocSections }

constructor TDocSections.Create(ABuilder: TLayoutBuilder; const AContent: TAtlasDocContent;
  const ALabels: TAtlasDocLabels; AWidth: Integer; const AMeasure: TAtlasDocMeasure);
begin
  inherited Create;
  FBuilder := ABuilder;
  FDoc := AContent.Doc;
  FSignature := AContent.Signature;
  FOpenSignature := AContent.SignatureShown;
  FLabels := ALabels;
  FWidth := AWidth;
  FMeasure := AMeasure;
  FName := TAtlasDocFace.Create(TAtlasDocFont.Mono, True);
  FMono := TAtlasDocFace.Create(TAtlasDocFont.Mono);
  FUI := TAtlasDocFace.Create(TAtlasDocFont.UI);
end;

function TDocSections.Width(const AText: string; const AFace: TAtlasDocFace; APercent: Integer): Integer;
begin
  Result := Min(FMeasure(AText, AFace), FWidth * APercent div 100);
end;

function TDocSections.NameColumn(const ASections: TArray<TAtlasDocSection>; ACount: Integer;
  const AFace: TAtlasDocFace; APercent: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 1;
  for mIndex := 0 to Min(ACount, Length(ASections)) - 1 do
  begin
    Result := Max(Result, Width(ASections[mIndex].Name, AFace, APercent));
  end;
end;

function TDocSections.LinkCell(const ASection: TAtlasDocSection): TDocCell;
begin
  Result := TDocCell.OfText(ASection.Name, FMono, TAtlasDocColor.Error);
  // Klasse anklickbar, wenn der Server sie gefunden hat.
  if ASection.NameRef.HasLocation then
  begin
    Result.HasLink := True;
    Result.Link.Kind := TAtlasDocLinkKind.Ref;
    Result.Link.Target := ASection.NameRef;
  end;
end;

procedure TDocSections.TypeAndText(const AType: string; AKind: TAtlasDocSectionKind);
var
  mDocs: TArray<TAtlasDocSection>;
begin
  mDocs := SectionsOf(FDoc, AKind);
  if (AType <> '') and (Length(mDocs) > 0) then
  begin
    FBuilder.Columns([TDocCell.OfText(AType, FMono, TAtlasDocColor.Keyword),
      TDocCell.OfRuns(mDocs[0].Runs, TAtlasDocColor.Muted)],
      [Width(AType, FMono, TAtlasDocLayout.cTypeColumnPercent)]);
  end
  else if AType <> '' then
  begin
    FBuilder.Columns([TDocCell.OfText(AType, FMono, TAtlasDocColor.Keyword)], nil);
  end
  else if Length(mDocs) > 0 then
  begin
    FBuilder.Columns([TDocCell.OfRuns(mDocs[0].Runs, TAtlasDocColor.Muted)], nil);
  end;
end;

procedure TDocSections.ParamRow(const AName, AType: string; const ARuns: TAtlasDocRuns;
  ANameColor, ATextColor: TAtlasDocColor);
begin
  if FThreeColumns then
  begin
    FBuilder.Columns([TDocCell.OfText(AName, FName, ANameColor), TDocCell.OfText(AType, FMono,
      TAtlasDocColor.Muted), TDocCell.OfRuns(ARuns, ATextColor)], [FNameWidth, FTypeWidth]);
  end
  else
  begin
    FBuilder.Columns([TDocCell.OfText(AName, FName, ANameColor), TDocCell.OfRuns(ARuns, ATextColor)],
      [FNameWidth]);
  end;
end;

procedure TDocSections.MeasureParams;
var
  mParam: TAtlasDocParam;
begin
  FThreeColumns := FSignature.Known and FSignature.HasTypes;
  FNameWidth := NameColumn(SectionsOf(FDoc, TAtlasDocSectionKind.Param), MaxInt, FName,
    TAtlasDocLayout.cNameColumnPercent);
  FTypeWidth := 1;
  for mParam in FSignature.Params do
  begin
    FNameWidth := Max(FNameWidth, Width(mParam.Name, FName, TAtlasDocLayout.cNameColumnPercent));
    FTypeWidth := Max(FTypeWidth, Width(mParam.TypeText, FMono, TAtlasDocLayout.cTypeColumnPercent));
  end;
end;

procedure TDocSections.KnownParams(const ASections: TArray<TAtlasDocSection>);
var
  mParam: TAtlasDocParam;
  mSection: TAtlasDocSection;
  mFound: Integer;
  mUndocumented: TAtlasDocRuns;
begin
  mUndocumented := [TAtlasDocRun.Create(TAtlasDocRunKind.Text, FLabels.Undocumented)];
  mUndocumented[0].Italic := True;
  // Offene Signatur ohne einen dokumentierten Parameter: Textspalte leer statt lauter „nicht dokumentiert“.
  if FOpenSignature and (Length(ASections) = 0) then
  begin
    mUndocumented := nil;
  end;
  for mParam in FSignature.Params do
  begin
    mFound := SectionIndex(ASections, mParam.Name);
    if mFound >= 0 then
    begin
      ParamRow(mParam.Name, mParam.TypeText, ASections[mFound].Runs, TAtlasDocColor.Accent, TAtlasDocColor.Text);
    end
    else
    begin
      ParamRow(mParam.Name, mParam.TypeText, mUndocumented, TAtlasDocColor.Accent, TAtlasDocColor.Muted);
    end;
  end;
  for mSection in UnknownParams(FDoc, FSignature) do
  begin
    ParamRow(mSection.Name, '', mSection.Runs, TAtlasDocColor.Warn, TAtlasDocColor.Warn);
  end;
end;

procedure TDocSections.Summary;
var
  mSection: TAtlasDocSection;
begin
  for mSection in SectionsOf(FDoc, TAtlasDocSectionKind.Summary) do
  begin
    FBuilder.Section(mSection, TAtlasDocColor.Text);
  end;
end;

procedure TDocSections.Params;
var
  mSections: TArray<TAtlasDocSection>;
  mSection: TAtlasDocSection;
begin
  // PARAMETER: in der Reihenfolge der Signatur, dann unbekannte in Warnfarbe.
  if ParamCount(FDoc, FSignature) = 0 then
  begin
    Exit;
  end;
  FBuilder.Heading(FLabels.Params);
  MeasureParams;
  mSections := SectionsOf(FDoc, TAtlasDocSectionKind.Param);
  if FSignature.Known then
  begin
    KnownParams(mSections);
    Exit;
  end;
  for mSection in mSections do
  begin
    ParamRow(mSection.Name, '', mSection.Runs, TAtlasDocColor.Accent, TAtlasDocColor.Text);
  end;
end;

procedure TDocSections.NamedRows(const ASections: TArray<TAtlasDocSection>; ACount: Integer);
var
  mNameWidth, mIndex: Integer;
begin
  mNameWidth := NameColumn(ASections, ACount, FName, TAtlasDocLayout.cNameColumnPercent);
  for mIndex := 0 to Min(ACount, Length(ASections)) - 1 do
  begin
    FBuilder.Columns([TDocCell.OfText(ASections[mIndex].Name, FName, TAtlasDocColor.Accent),
      TDocCell.OfRuns(ASections[mIndex].Runs, TAtlasDocColor.Text)], [mNameWidth]);
  end;
end;

procedure TDocSections.TypeParams;
var
  mSections: TArray<TAtlasDocSection>;
begin
  mSections := SectionsOf(FDoc, TAtlasDocSectionKind.TypeParam);
  if Length(mSections) > 0 then
  begin
    FBuilder.Heading(FLabels.TypeParams);
    NamedRows(mSections, MaxInt);
  end;
end;

procedure TDocSections.ReturnsAndValue;
var
  mReturnType, mValueType: string;
begin
  // Bei Properties ist der Typ der Wert, sonst die Rückgabe.
  mReturnType := FSignature.ResultType;
  mValueType := '';
  if FSignature.IsProperty then
  begin
    mValueType := mReturnType;
    mReturnType := '';
  end;
  if HasReturns(FDoc, FSignature) then
  begin
    FBuilder.Heading(FLabels.Returns);
    TypeAndText(mReturnType, TAtlasDocSectionKind.Returns);
  end;
  if HasValue(FDoc, FSignature) then
  begin
    FBuilder.Heading(FLabels.Value);
    TypeAndText(mValueType, TAtlasDocSectionKind.Value);
  end;
end;

procedure TDocSections.Exceptions;
var
  mSections: TArray<TAtlasDocSection>;
  mSection: TAtlasDocSection;
  mNameWidth: Integer;
begin
  mSections := SectionsOf(FDoc, TAtlasDocSectionKind.Exception);
  if Length(mSections) = 0 then
  begin
    Exit;
  end;
  FBuilder.Heading(FLabels.Exceptions);
  mNameWidth := NameColumn(mSections, MaxInt, FMono, 50);
  for mSection in mSections do
  begin
    FBuilder.Columns([LinkCell(mSection), TDocCell.OfRuns(mSection.Runs, TAtlasDocColor.Muted)], [mNameWidth]);
  end;
end;

procedure TDocSections.TextSections(AKind: TAtlasDocSectionKind; const ATitle: string; AColor: TAtlasDocColor);
var
  mSections: TArray<TAtlasDocSection>;
  mSection: TAtlasDocSection;
begin
  mSections := SectionsOf(FDoc, AKind);
  if Length(mSections) = 0 then
  begin
    Exit;
  end;
  FBuilder.Heading(ATitle);
  for mSection in mSections do
  begin
    FBuilder.Section(mSection, AColor);
  end;
end;

procedure TDocSections.SeeAlso(AGap: Integer);
var
  mSections: TArray<TAtlasDocSection>;
  mIndex: Integer;
begin
  // SIEHE AUCH in einer Zeile mit den Verweisen.
  mSections := SectionsOf(FDoc, TAtlasDocSectionKind.SeeAlso);
  if Length(mSections) = 0 then
  begin
    Exit;
  end;
  FBuilder.SetBase(0);
  FBuilder.Gap(AGap);
  FBuilder.AddSpan(FLabels.SeeAlso, TAtlasDocFace.Heading, TAtlasDocColor.Muted, False, -1);
  FBuilder.AddSpan('  ', FUI, TAtlasDocColor.Muted, False, -1);
  for mIndex := 0 to High(mSections) do
  begin
    if mIndex > 0 then
    begin
      FBuilder.AddWords(', ', FUI, TAtlasDocColor.Muted);
    end;
    FBuilder.FlowRuns(mSections[mIndex].Runs, TAtlasDocColor.Text);
  end;
  FBuilder.NewLine;
end;

procedure TDocSections.Details(AGap: Integer);
begin
  Params;
  TypeParams;
  ReturnsAndValue;
  Exceptions;
  TextSections(TAtlasDocSectionKind.Remarks, FLabels.Remarks, TAtlasDocColor.Muted);
  TextSections(TAtlasDocSectionKind.Example, FLabels.Example, TAtlasDocColor.Text);
  SeeAlso(AGap);
end;

procedure TDocSections.SignatureSections;
var
  mReturnType: string;
begin
  Params;
  if HasReturns(FDoc, FSignature) then
  begin
    mReturnType := '';
    if not FSignature.IsProperty then
    begin
      mReturnType := FSignature.ResultType;
    end;
    FBuilder.Heading(FLabels.Returns);
    TypeAndText(mReturnType, TAtlasDocSectionKind.Returns);
  end;
end;

procedure TDocSections.Rationale(AExpanded: Boolean);
var
  mSections: TArray<TAtlasDocSection>;
  mShown: Integer;
begin
  // BEGRÜNDUNG (#1123) nach der XMLDoc; zugeklappt die ersten MaxRationale.
  mSections := SectionsOf(FDoc, TAtlasDocSectionKind.Rationale);
  if Length(mSections) = 0 then
  begin
    Exit;
  end;
  FBuilder.Heading(FLabels.Rationale);
  mShown := Length(mSections);
  if not AExpanded then
  begin
    mShown := Min(mShown, TAtlasDocLayout.cMaxRationale);
  end;
  NamedRows(mSections, mShown);
end;

procedure TDocSections.UnitContents;
var
  mSections: TArray<TAtlasDocSection>;
  mFirst, mLast: Integer;
begin
  // Gruppen unter derselben Überschrift folgen aufeinander; je Überschrift eine Tabelle.
  mSections := SectionsOf(FDoc, TAtlasDocSectionKind.UnitContents);
  mFirst := 0;
  while mFirst <= High(mSections) do
  begin
    mLast := mFirst;
    while (mLast < High(mSections)) and (mSections[mLast + 1].Heading = mSections[mFirst].Heading) do
    begin
      Inc(mLast);
    end;
    FBuilder.Heading(mSections[mFirst].Heading);
    NamedRows(Copy(mSections, mFirst, mLast - mFirst + 1), MaxInt);
    mFirst := mLast + 1;
  end;
end;

procedure TDocSections.Toggle(AExpanded: Boolean; AGap: Integer);
var
  mToggle: TAtlasDocLink;
  mParts: TArray<string>;
  mColors: TArray<TAtlasDocColor>;
  mIndex: Integer;
begin
  // Schalter: zugeklappt mit dem, was verborgen ist.
  mToggle := Default(TAtlasDocLink);
  mToggle.Kind := TAtlasDocLinkKind.Toggle;
  FBuilder.SetBase(0);
  FBuilder.Gap(AGap);
  if AExpanded then
  begin
    FBuilder.AddWhole(FLabels.Less, FUI, TAtlasDocColor.Accent, FBuilder.AddLink(mToggle));
    FBuilder.NewLine;
    Exit;
  end;
  FBuilder.AddWhole(FLabels.More, FUI, TAtlasDocColor.Accent, FBuilder.AddLink(mToggle));
  mParts := CollectHiddenParts(FDoc, FSignature, FLabels, FOpenSignature, mColors);
  if Length(mParts) > 0 then
  begin
    FBuilder.AddSpan('   ', FUI, TAtlasDocColor.Muted, False, -1);
  end;
  for mIndex := 0 to High(mParts) do
  begin
    if mIndex > 0 then
    begin
      FBuilder.AddWords(TAtlasDocLayout.cSeparator, FUI, TAtlasDocColor.Muted);
    end;
    FBuilder.AddWords(mParts[mIndex], FUI, mColors[mIndex]);
  end;
  FBuilder.NewLine;
end;

{ TAtlasDocContent }

class function TAtlasDocContent.Create(const ADoc: TAtlasDoc; const ASignature: TAtlasDocSignature;
  AExpanded: Boolean): TAtlasDocContent;
begin
  Result.Doc := ADoc;
  Result.Signature := ASignature;
  Result.Expanded := AExpanded;
  Result.OpenSignature := False;
end;

function TAtlasDocContent.SignatureShown: Boolean;
begin
  Result := OpenSignature and Signature.Known and ((Length(Signature.Params) > 0) or
    ((Signature.ResultType <> '') and not Signature.IsProperty));
end;

/// <summary>Klartext einer Zeile anhängen und die Anfänge der Stücke darin merken; ein Sprung in eine andere
/// Spalte wird zum Tabulator.</summary>
procedure AppendLineText(var ALine: TAtlasDocLine; AText: TStringBuilder);
var
  mPen, mIndex: Integer;
  mSpan: TAtlasDocSpan;
begin
  if AText.Length > 0 then
  begin
    AText.Append(#13#10);
  end;
  mPen := -1;
  for mIndex := 0 to High(ALine.Spans) do
  begin
    mSpan := ALine.Spans[mIndex];
    if (mPen >= 0) and (mSpan.Left > mPen + 1) and (AText.Length > 0) and
      not CharInSet(AText.Chars[AText.Length - 1], [' ', #9]) then
    begin
      AText.Append(#9);
    end;
    ALine.Spans[mIndex].TextStart := AText.Length;
    AText.Append(mSpan.Text);
    mPen := mSpan.Right;
  end;
end;

/// <summary>Leere Zeilen am Ende weg; dann Positionen, Höhe und Klartext.</summary>
procedure PlaceLines(var ALayout: TAtlasDocLayout);
var
  mY, mIndex: Integer;
  mText: TStringBuilder;
begin
  while (Length(ALayout.Lines) > 0) and (Length(ALayout.Lines[High(ALayout.Lines)].Spans) = 0) do
  begin
    SetLength(ALayout.Lines, Length(ALayout.Lines) - 1);
  end;
  if Length(ALayout.Lines) > 0 then
  begin
    ALayout.Lines[0].GapBefore := 0;
  end;
  mY := 0;
  mText := TStringBuilder.Create;
  try
    for mIndex := 0 to High(ALayout.Lines) do
    begin
      Inc(mY, ALayout.Lines[mIndex].GapBefore);
      ALayout.Lines[mIndex].Top := mY;
      Inc(mY, ALayout.Lines[mIndex].Height);
      AppendLineText(ALayout.Lines[mIndex], mText);
    end;
    ALayout.Text := mText.ToString;
  finally
    mText.Free;
  end;
  ALayout.Height := mY;
end;

class function TAtlasDocTypeset.Build(const ADoc: TAtlasDoc; AWidth: Integer; const AMetrics: TAtlasDocMetrics;
  const AMeasure: TAtlasDocMeasure; const ALabels: TAtlasDocLabels): TAtlasDocLayout;
begin
  Result := Build(TAtlasDocContent.Create(ADoc, Default(TAtlasDocSignature), True), AWidth, AMetrics, AMeasure,
    ALabels);
end;

class function TAtlasDocTypeset.Build(const AContent: TAtlasDocContent; AWidth: Integer;
  const AMetrics: TAtlasDocMetrics; const AMeasure: TAtlasDocMeasure;
  const ALabels: TAtlasDocLabels): TAtlasDocLayout;
var
  mBuilder: TLayoutBuilder;
  mSections: TDocSections;
begin
  Result := Default(TAtlasDocLayout);
  if AContent.Doc.IsEmpty and not AContent.SignatureShown then
  begin
    Exit;
  end;
  Result.Collapsible := IsCollapsible(AContent);
  Result.Expanded := AContent.Expanded or not Result.Collapsible;
  mBuilder := TLayoutBuilder.Create(AWidth, AMetrics, AMeasure);
  mSections := TDocSections.Create(mBuilder, AContent, ALabels, AWidth, AMeasure);
  try
    mSections.Summary;
    if Result.Expanded and Result.Collapsible then
    begin
      mSections.Details(AMetrics.SectionGap);
    end
    else if AContent.SignatureShown then
    begin
      mSections.SignatureSections;
    end;
    mSections.Rationale(Result.Expanded);
    mSections.UnitContents;
    if Result.Collapsible then
    begin
      mSections.Toggle(Result.Expanded, AMetrics.SectionGap);
    end;
    Result.Lines := mBuilder.Lines;
    Result.Links := mBuilder.Links;
  finally
    mSections.Free;
    mBuilder.Free;
  end;
  PlaceLines(Result);
end;

end.
