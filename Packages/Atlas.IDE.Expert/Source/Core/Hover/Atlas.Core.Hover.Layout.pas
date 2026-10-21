unit Atlas.Core.Hover.Layout;

// Satz des Hover-Tooltips ohne VCL (P-09): Build rechnet aus dem Inhalt
// (TAtlasHoverView), der Breite und einem Mess-Rückruf alle Positionen,
// Klickflächen und Zeichenbausteine aus; das Fenster (Atlas.UI.Hover.Tip)
// zeichnet nur noch die Bausteine in Reihenfolge. Gebaut wird je Inhalt,
// Breite und Doku-Höhe, nicht je Paint oder Mausbewegung. Der Hot-Zustand
// (Maus über Link, Kette, Pfad, Aktion) ändert nur Farben, Unterstreichung und
// Linienstärke; dafür trägt ein Baustein Art und Index der Klickfläche.
// Aufbau wie bisher: Pfadzeile (angeheftet), Probleme, Kopfzeile, Deklaration
// mit Verweisen, Beschreibung mit Platz für die XMLDoc, Vererbung bzw.
// Zieltyp und Aktionsleiste auf Randflächen; die letzte Randfläche sitzt beim
// Zeichnen am unteren Fensterrand (Anchor).
// Unter einem Hinweis zu einem uses-Eintrag (#621) stehen seine Aktionen als
// Links: Entfernen, Alle ungenutzten entfernen (ab zwei), In implementation-uses
// verschieben; ihre Klickfläche trägt Problem und Aktion (ProblemActionCode).

interface

uses
  System.Types,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.History,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Documentation.Contract;

type
  {$SCOPEDENUMS ON}
  TAtlasHoverAction = (Navigate, Usages, Copy, Help);
  /// <summary>Schriften des Tooltips: UI, Editorschrift, beide verkleinert, Badge.</summary>
  TAtlasHoverFont = (Ui, Mono, SmallUi, SmallMono, Badge);
  TAtlasHoverHitKind = (Link, Ancestor, Path, Back, Action, ProblemAction);
  /// <summary>Aktion unter einem Problem im Tooltip (#621).</summary>
  TAtlasHoverProblemAction = (RemoveUses, RemoveAllUses, MoveUses);
  /// <summary>Fill: Fläche; Line: waagrechte Linie; Text: Text ab Rect.TopLeft; CenterText: zentriert in
  /// Rect; Frame: umrandetes Rechteck mit Fläche Back; RoundFill: gefülltes Rechteck mit Radius; Block:
  /// umbrechender Text in Rect (UI-Schrift, Ellipse); Styled: eingefärbte Deklaration From..Till; Doc: XMLDoc
  /// ab Rect.TopLeft.</summary>
  TAtlasHoverItemKind = (Fill, Line, Text, CenterText, Frame, RoundFill, Block, Styled, Doc);
  {$SCOPEDENUMS OFF}

  /// <summary>Was der Tooltip zeigt: Inhalt, Pfad und Zustand.</summary>
  TAtlasHoverView = record
    Data: TAtlasHoverData;
    Path: TArray<TAtlasHoverPathItem>;
    Pinned: Boolean;
    CanGoBack: Boolean;
    /// <summary>Anzahl der Verwendungen, wenn bekannt; sonst -1.</summary>
    UsagesCount: Integer;
    /// <summary>Probleme an der Mausposition (#398).</summary>
    Problems: TArray<TAtlasProblem>;
    /// <summary>Anzeige der XMLDoc (#654): Angabe des Servers bzw. Einstellungen des Plugins.</summary>
    Display: TAtlasDocDisplay;
    class function Create(const AData: TAtlasHoverData): TAtlasHoverView; static;
  end;

  TAtlasHoverFace = record
    Font: TAtlasHoverFont;
    Bold: Boolean;
    Underline: Boolean;
    class function Create(AFont: TAtlasHoverFont; ABold, AUnderline: Boolean): TAtlasHoverFace; static;
  end;

  /// <summary>Messen in der Oberfläche; Build ruft nur diese Funktionen.</summary>
  IAtlasHoverMeasure = interface
    function TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
    /// <summary>Zeilenhöhe der Schrift (Höhe von „Wg“).</summary>
    function TextHeight(const AFace: TAtlasHoverFace): Integer;
    /// <summary>Höhe von AText in der UI-Schrift, umbrochen an Wortgrenzen auf AWidth.</summary>
    function BlockHeight(const AText: string; AWidth: Integer): Integer;
    /// <summary>Breite der eingefärbten Deklaration [AFrom, ATill) in der Editorschrift.</summary>
    function DeclarationWidth(AFrom, ATill: Integer): Integer;
    /// <summary>Zeilen der eingefärbten Deklaration bei Umbruch an Leerzeichen.</summary>
    function DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
  end;

  /// <summary>Texte der Oberfläche in ihrer Sprache (Core kennt Atlas.UI.Strings nicht).</summary>
  TAtlasHoverTexts = record
    /// <summary>Art zu View.Data.Kind (Klasse, Methode …); '' wenn unbekannt.</summary>
    KindCaption: string;
    Pinned: string;
    Inheritance: string;
    /// <summary>Format mit %s für den Typ der Kette.</summary>
    TargetType: string;
    /// <summary>Format mit %s für den Titel.</summary>
    Navigate: string;
    Usages: string;
    /// <summary>Format mit %d für die Anzahl.</summary>
    UsagesCount: string;
    Copy: string;
    CopySelection: string;
    Help: string;
    KeyUsages: string;
    KeyCopy: string;
    SourceAtlas: string;
    SourceCompiler: string;
    SourceInactive: string;
    /// <summary>Herkunft eines uses-Hinweises und seine Aktionen (#621).</summary>
    SourceUses: string;
    UsesRemove: string;
    UsesRemoveAll: string;
    UsesMove: string;
    Stale: string;
    /// <summary>Zeile „Konfidenz: …“ je Problem in der Reihenfolge von View.Problems; '' ohne.</summary>
    Confidences: TArray<string>;
  end;

  TAtlasHoverItem = record
    Kind: TAtlasHoverItemKind;
    Rect: TRect;
    Text: string;
    Face: TAtlasHoverFace;
    Color: TAtlasColor;
    /// <summary>Farbe, solange die Klickfläche HotKind/HotIndex unter der Maus ist.</summary>
    HotColor: TAtlasColor;
    /// <summary>Fläche von Frame.</summary>
    Back: TAtlasColor;
    /// <summary>Radius von Frame und RoundFill in logischen Pixeln.</summary>
    Radius: Integer;
    PenWidth: Integer;
    HotPenWidth: Integer;
    HotUnderline: Boolean;
    HotKind: TAtlasHoverHitKind;
    /// <summary>-1: hängt an keiner Klickfläche.</summary>
    HotIndex: Integer;
    From: Integer;
    Till: Integer;
  end;

  TAtlasHoverHit = record
    Kind: TAtlasHoverHitKind;
    Index: Integer;
    Rect: TRect;
  end;

  TAtlasHoverInput = record
    View: TAtlasHoverView;
    Width: Integer;
    PPI: Integer;
    Colors: TAtlasColors;
    Texts: TAtlasHoverTexts;
    /// <summary>XMLDoc vorhanden und ihre (begrenzte) Höhe.</summary>
    HasDoc: Boolean;
    DocHeight: Integer;
    /// <summary>Markierung in der Doku: Aktion „Auswahl kopieren“ statt „Deklaration kopieren“.</summary>
    HasSelection: Boolean;
  end;

  TAtlasHoverLayout = record
    Items: TArray<TAtlasHoverItem>;
    Hits: TArray<TAtlasHoverHit>;
    Height: Integer;
    DocLeft: Integer;
    DocTop: Integer;
    /// <summary>Letzte Randfläche: erster Baustein und erste Klickfläche (-1 ohne), Lage und Verschiebung.</summary>
    AnchorItem: Integer;
    AnchorHit: Integer;
    AnchorTop: Integer;
    AnchorHeight: Integer;
    AnchorShift: Integer;
    class function Build(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure): TAtlasHoverLayout;
      static;
    /// <summary>Index der Klickfläche ProblemAction: Problem in View.Problems und Aktion (#621).</summary>
    class function ProblemActionCode(AProblem: Integer; AAction: TAtlasHoverProblemAction): Integer; static;
    class procedure DecodeProblemAction(ACode: Integer; out AProblem: Integer;
      out AAction: TAtlasHoverProblemAction); static;
    /// <summary>Index der Klickfläche unter APoint; -1 ohne.</summary>
    function HitAt(const APoint: TPoint): Integer;
    /// <summary>Ist die Klickfläche AHot (Index in Hits) von Art AKind und Index AIndex?</summary>
    function IsHot(AHot: Integer; AKind: TAtlasHoverHitKind; AIndex: Integer): Boolean;
    /// <summary>Letzte Randfläche an den unteren Rand eines Fensters der Höhe AClientHeight schieben (nie
    /// nach oben über ihre Lage hinaus); wiederholbar.</summary>
    procedure Anchor(AClientHeight: Integer);
  end;

/// <summary>Badge-Art zum Kürzel aus TAtlasHoverData.Badge.</summary>
function HoverBadgeKind(const ACode: string): TAtlasBadgeKind;

implementation

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  Atlas.Core.Problems.Colors;

const
  BandChain = 0;
  BandActions = 1;

type
  TBuilder = class
  private
    FInput: TAtlasHoverInput;
    FMeasure: IAtlasHoverMeasure;
    FData: TAtlasHoverData;
    FColors: TAtlasColors;
    FItems: TArray<TAtlasHoverItem>;
    FItemCount: Integer;
    FHits: TArray<TAtlasHoverHit>;
    FHitCount: Integer;
    FLeft, FRight, FY, FX, FRowHeight, FLineHeight: Integer;
    FFlowFont: TAtlasHoverFont;
    FNoWrap: Boolean;
    FLayout: TAtlasHoverLayout;
    function Scale(AValue: Integer): Integer;
    function Face(AFont: TAtlasHoverFont; ABold: Boolean): TAtlasHoverFace;
    function Height(const AFace: TAtlasHoverFace): Integer;
    function Width(const AFace: TAtlasHoverFace; const AText: string): Integer;
    function NewItem(AKind: TAtlasHoverItemKind; const ARect: TRect; AColor: TAtlasColor): TAtlasHoverItem;
    procedure Add(const AItem: TAtlasHoverItem);
    procedure Insert(AAt: Integer; const AItem: TAtlasHoverItem);
    procedure AddHit(AKind: TAtlasHoverHitKind; AIndex: Integer; const ARect: TRect);
    procedure AddText(AX, AY: Integer; const AText: string; const AFace: TAtlasHoverFace; AColor: TAtlasColor);
    procedure AddLine(ALeft, ATop, ARight: Integer; AColor: TAtlasColor);
    procedure HorizontalLine(ATop: Integer);
    procedure Block(const AText: string; AColor: TAtlasColor; AMaxLines: Integer);
    /// <summary>Fließtext mit Umbruch; AIndex >= 0 legt eine Klickfläche an. AHotIndex >= 0: bei Hot
    /// AHotColor und unterstrichen.</summary>
    procedure Flow(const AText: string; AColor: TAtlasColor; ABold: Boolean; AKind: TAtlasHoverHitKind;
      AIndex, AHotIndex: Integer; AHotColor: TAtlasColor);
    procedure EndFlow;
    procedure Chip(const AText: string; ACurrent: Boolean; AIndex: Integer);
    procedure ActionItem(const AKey, ACaption: string; AAction: TAtlasHoverAction; AEnabled: Boolean);
    procedure ProblemLink(const ACaption: string; AProblem: Integer; AAction: TAtlasHoverProblemAction);
    procedure BandContent(AKind: Integer);
    procedure Band(AKind: Integer; ALast: Boolean);
    procedure DrawPart(AFrom, ATill: Integer);
    procedure Navigation;
    procedure Problems;
    procedure Header;
    procedure Declaration;
    procedure Description;
    procedure Run;
  public
    constructor Create(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure);
    function Layout: TAtlasHoverLayout;
  end;

function HoverBadgeKind(const ACode: string): TAtlasBadgeKind;
begin
  case IndexStr(ACode, ['ty', 'fn', 'pp', 'fd', 'va', 'co', 'un']) of
    0: Result := TAtlasBadgeKind.Type_;
    1: Result := TAtlasBadgeKind.Function_;
    2: Result := TAtlasBadgeKind.Property_;
    3: Result := TAtlasBadgeKind.Field;
    4: Result := TAtlasBadgeKind.Variable;
    5: Result := TAtlasBadgeKind.Constant;
    6: Result := TAtlasBadgeKind.Unit_;
  else
    Result := TAtlasBadgeKind.Keyword;
  end;
end;

{ TAtlasHoverView }

class function TAtlasHoverView.Create(const AData: TAtlasHoverData): TAtlasHoverView;
begin
  Result := Default(TAtlasHoverView);
  Result.Data := AData;
  Result.UsagesCount := -1;
  Result.Display := TAtlasDocDisplay.Create(TAtlasDocExpand.Last, 0);
end;

{ TAtlasHoverFace }

class function TAtlasHoverFace.Create(AFont: TAtlasHoverFont; ABold, AUnderline: Boolean): TAtlasHoverFace;
begin
  Result.Font := AFont;
  Result.Bold := ABold;
  Result.Underline := AUnderline;
end;

{ TBuilder }

constructor TBuilder.Create(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure);
begin
  inherited Create;
  FInput := AInput;
  FMeasure := AMeasure;
  FData := AInput.View.Data;
  FColors := AInput.Colors;
  FItems := nil;
  FHits := nil;
  FLayout := Default(TAtlasHoverLayout);
  FLayout.AnchorItem := -1;
  FLayout.AnchorHit := -1;
end;

function TBuilder.Scale(AValue: Integer): Integer;
begin
  // Wie MulDiv(AValue, PPI, 96): auf ganze Pixel gerundet.
  Result := (AValue * FInput.PPI + 48) div 96;
end;

function TBuilder.Face(AFont: TAtlasHoverFont; ABold: Boolean): TAtlasHoverFace;
begin
  Result := TAtlasHoverFace.Create(AFont, ABold, False);
end;

function TBuilder.Height(const AFace: TAtlasHoverFace): Integer;
begin
  Result := FMeasure.TextHeight(AFace);
end;

function TBuilder.Width(const AFace: TAtlasHoverFace; const AText: string): Integer;
begin
  Result := FMeasure.TextWidth(AFace, AText);
end;

function TBuilder.NewItem(AKind: TAtlasHoverItemKind; const ARect: TRect; AColor: TAtlasColor): TAtlasHoverItem;
begin
  Result := Default(TAtlasHoverItem);
  Result.Kind := AKind;
  Result.Rect := ARect;
  Result.Color := AColor;
  Result.HotColor := AColor;
  Result.PenWidth := 1;
  Result.HotPenWidth := 1;
  Result.HotIndex := -1;
  Result.Face := Face(TAtlasHoverFont.Ui, False);
end;

procedure TBuilder.Add(const AItem: TAtlasHoverItem);
begin
  if FItemCount = Length(FItems) then
    SetLength(FItems, 2 * FItemCount + 16);
  FItems[FItemCount] := AItem;
  Inc(FItemCount);
end;

procedure TBuilder.Insert(AAt: Integer; const AItem: TAtlasHoverItem);
var
  Index: Integer;
begin
  Add(AItem);
  for Index := FItemCount - 1 downto AAt + 1 do
    FItems[Index] := FItems[Index - 1];
  FItems[AAt] := AItem;
end;

procedure TBuilder.AddHit(AKind: TAtlasHoverHitKind; AIndex: Integer; const ARect: TRect);
begin
  if FHitCount = Length(FHits) then
    SetLength(FHits, 2 * FHitCount + 8);
  FHits[FHitCount].Kind := AKind;
  FHits[FHitCount].Index := AIndex;
  FHits[FHitCount].Rect := ARect;
  Inc(FHitCount);
end;

procedure TBuilder.AddText(AX, AY: Integer; const AText: string; const AFace: TAtlasHoverFace;
  AColor: TAtlasColor);
var
  Item: TAtlasHoverItem;
begin
  Item := NewItem(TAtlasHoverItemKind.Text, Rect(AX, AY, AX, AY), AColor);
  Item.Text := AText;
  Item.Face := AFace;
  Add(Item);
end;

procedure TBuilder.AddLine(ALeft, ATop, ARight: Integer; AColor: TAtlasColor);
begin
  Add(NewItem(TAtlasHoverItemKind.Line, Rect(ALeft, ATop, ARight, ATop), AColor));
end;

procedure TBuilder.HorizontalLine(ATop: Integer);
begin
  AddLine(0, ATop, FInput.Width, FColors.Line);
end;

procedure TBuilder.Block(const AText: string; AColor: TAtlasColor; AMaxLines: Integer);
var
  Bottom: Integer;
  Item: TAtlasHoverItem;
begin
  if AText = '' then
    Exit;
  Bottom := FY + FMeasure.BlockHeight(AText, FRight - FLeft);
  if AMaxLines > 0 then
    Bottom := Min(Bottom, FY + AMaxLines * Height(Face(TAtlasHoverFont.Ui, False)));
  Item := NewItem(TAtlasHoverItemKind.Block, Rect(FLeft, FY, FRight, Bottom), AColor);
  Item.Text := AText;
  Add(Item);
  FY := Bottom + Scale(6);
end;

procedure TBuilder.Flow(const AText: string; AColor: TAtlasColor; ABold: Boolean; AKind: TAtlasHoverHitKind;
  AIndex, AHotIndex: Integer; AHotColor: TAtlasColor);
var
  TextFace: TAtlasHoverFace;
  TextWidth, TextHeight: Integer;
  Cell: TRect;
  Item: TAtlasHoverItem;
begin
  TextFace := Face(FFlowFont, ABold);
  TextWidth := Width(TextFace, AText);
  TextHeight := Height(TextFace);
  if not FNoWrap and (FX + TextWidth > FRight) and (FX > FLeft) then
  begin
    FX := FLeft;
    Inc(FY, FRowHeight + Scale(4));
    FRowHeight := 0;
  end;
  Cell := Rect(FX, FY, FX + TextWidth, FY + TextHeight);
  Item := NewItem(TAtlasHoverItemKind.Text, Cell, AColor);
  Item.Text := AText;
  Item.Face := TextFace;
  if AHotIndex >= 0 then
  begin
    Item.HotKind := AKind;
    Item.HotIndex := AHotIndex;
    Item.HotColor := AHotColor;
    Item.HotUnderline := True;
  end;
  Add(Item);
  if AIndex >= 0 then
    AddHit(AKind, AIndex, Cell);
  Inc(FX, TextWidth);
  FRowHeight := Max(FRowHeight, TextHeight);
end;

procedure TBuilder.EndFlow;
begin
  Inc(FY, FRowHeight);
  FRowHeight := 0;
  FX := FLeft;
end;

procedure TBuilder.Chip(const AText: string; ACurrent: Boolean; AIndex: Integer);
var
  TextFace: TAtlasHoverFace;
  TextWidth, TextHeight: Integer;
  Cell: TRect;
  Item: TAtlasHoverItem;
begin
  // Glied der Vererbungskette als umrandetes Kästchen; das angezeigte in Akzentfarbe.
  TextFace := Face(TAtlasHoverFont.Mono, ACurrent);
  TextWidth := Width(TextFace, AText);
  TextHeight := Height(TextFace) + Scale(2);
  if (FX + TextWidth + Scale(AtlasChipPad) > FRight) and (FX > FLeft) then
  begin
    FX := FLeft;
    Inc(FY, FRowHeight + Scale(4));
    FRowHeight := 0;
  end;
  Cell := Rect(FX, FY, FX + TextWidth + Scale(AtlasChipPad), FY + TextHeight);
  if ACurrent then
    Item := NewItem(TAtlasHoverItemKind.Frame, Cell, FColors.Accent)
  else
  begin
    Item := NewItem(TAtlasHoverItemKind.Frame, Cell, FColors.Line);
    Item.HotKind := TAtlasHoverHitKind.Ancestor;
    Item.HotIndex := AIndex;
    Item.HotColor := FColors.Accent;
  end;
  Item.Back := FColors.Surface;
  Item.Radius := AtlasChipRadius;
  Add(Item);
  if ACurrent then
    Item := NewItem(TAtlasHoverItemKind.Text, Rect(Cell.Left + Scale(AtlasChipPad div 2), Cell.Top + Scale(1),
      Cell.Left + Scale(AtlasChipPad div 2), Cell.Top + Scale(1)), FColors.Accent)
  else
  begin
    Item := NewItem(TAtlasHoverItemKind.Text, Rect(Cell.Left + Scale(AtlasChipPad div 2), Cell.Top + Scale(1),
      Cell.Left + Scale(AtlasChipPad div 2), Cell.Top + Scale(1)), FColors.Text);
    Item.HotKind := TAtlasHoverHitKind.Ancestor;
    Item.HotIndex := AIndex;
    Item.HotColor := FColors.Accent;
  end;
  Item.Text := AText;
  Item.Face := TextFace;
  Add(Item);
  if not ACurrent then
    AddHit(TAtlasHoverHitKind.Ancestor, AIndex, Cell);
  FX := Cell.Right;
  FRowHeight := Max(FRowHeight, TextHeight);
end;

procedure TBuilder.ActionItem(const AKey, ACaption: string; AAction: TAtlasHoverAction; AEnabled: Boolean);
var
  KeyColor: TAtlasColor;
  Total, Start, HotIndex: Integer;
begin
  // Taste in Akzentfarbe, Beschriftung gedämpft; bleibt in einer Zeile.
  if FX > FLeft then
    Inc(FX, Scale(14));
  Total := Width(Face(TAtlasHoverFont.SmallUi, True), AKey + ' ') +
    Width(Face(TAtlasHoverFont.SmallUi, False), ACaption);
  if (FX + Total > FRight) and (FX > FLeft) then
  begin
    FX := FLeft;
    Inc(FY, FRowHeight + Scale(3));
    FRowHeight := 0;
  end;
  if AEnabled then
    KeyColor := FColors.Accent
  else
    KeyColor := FColors.Muted;
  HotIndex := -1;
  if AEnabled then
    HotIndex := Ord(AAction);
  Start := FX;
  Flow(AKey + ' ', KeyColor, True, TAtlasHoverHitKind.Action, -1, -1, KeyColor);
  Flow(ACaption, FColors.Muted, False, TAtlasHoverHitKind.Action, -1, HotIndex, FColors.Text);
  if AEnabled then
    AddHit(TAtlasHoverHitKind.Action, Ord(AAction), Rect(Start, FY, FX, FY + FRowHeight));
end;

procedure TBuilder.ProblemLink(const ACaption: string; AProblem: Integer; AAction: TAtlasHoverProblemAction);
var
  Code: Integer;
begin
  if FX > FLeft then
    Inc(FX, Scale(12));
  Code := TAtlasHoverLayout.ProblemActionCode(AProblem, AAction);
  Flow(ACaption, FColors.Accent, False, TAtlasHoverHitKind.ProblemAction, Code, Code, FColors.Accent);
end;

procedure TBuilder.BandContent(AKind: Integer);
var
  Chain: TArray<Integer>;
  Item: Integer;
  Caption: string;
  CaptionFace: TAtlasHoverFace;
begin
  FX := FLeft;
  FRowHeight := 0;
  case AKind of
    BandChain:
      begin
        Inc(FY, Scale(8));
        if FData.Kind = TAtlasHoverData.KindClassRef then
          Caption := Format(FInput.Texts.TargetType, [FData.ChainOf])
        else
          Caption := FInput.Texts.Inheritance;
        CaptionFace := Face(TAtlasHoverFont.SmallMono, True);
        AddText(FLeft, FY, AnsiUpperCase(Caption), CaptionFace, FColors.Muted);
        Inc(FY, Height(CaptionFace) + Scale(6));
        FFlowFont := TAtlasHoverFont.Mono;
        Chain := FData.VisibleChain;
        for Item := 0 to High(Chain) do
        begin
          if Item > 0 then
            Flow(' › ', FColors.Muted, False, TAtlasHoverHitKind.Ancestor, -1, -1, FColors.Muted);
          if Chain[Item] < 0 then
            Flow('…', FColors.Muted, False, TAtlasHoverHitKind.Ancestor, -1, -1, FColors.Muted)
          else
            Chip(FData.Ancestors[Chain[Item]].Name, FData.Ancestors[Chain[Item]].Key = FData.Location.Key,
              Chain[Item]);
        end;
        EndFlow;
        Inc(FY, Scale(8));
      end;
    BandActions:
      begin
        Inc(FY, Scale(6));
        FFlowFont := TAtlasHoverFont.SmallUi;
        ActionItem('F12', Format(FInput.Texts.Navigate, [FData.Title]), TAtlasHoverAction.Navigate, True);
        if FInput.View.UsagesCount >= 0 then
          Caption := Format(FInput.Texts.UsagesCount, [FInput.View.UsagesCount])
        else
          Caption := FInput.Texts.Usages;
        ActionItem(FInput.Texts.KeyUsages, Caption, TAtlasHoverAction.Usages, True);
        // Mit Markierung in der Doku kopiert Strg+C diese, sonst die Deklaration.
        if FInput.HasSelection then
          Caption := FInput.Texts.CopySelection
        else
          Caption := FInput.Texts.Copy;
        ActionItem(FInput.Texts.KeyCopy, Caption, TAtlasHoverAction.Copy, True);
        ActionItem('F1', FInput.Texts.Help, TAtlasHoverAction.Help, FData.DocWiki <> '');
        EndFlow;
        Inc(FY, Scale(6));
      end;
  end;
  FFlowFont := TAtlasHoverFont.Ui;
end;

procedure TBuilder.Band(AKind: Integer; ALast: Boolean);
var
  Top, BandHeight, FirstItem, FirstHit: Integer;
begin
  // Abschnitt auf Randfläche mit Linie oben; Fläche und Linie vor den Inhalt, Höhe aus dem Inhalt.
  Top := FY;
  FirstItem := FItemCount;
  FirstHit := FHitCount;
  BandContent(AKind);
  BandHeight := FY - Top;
  Insert(FirstItem, NewItem(TAtlasHoverItemKind.Line, Rect(0, Top, FInput.Width, Top), FColors.Line));
  Insert(FirstItem, NewItem(TAtlasHoverItemKind.Fill, Rect(0, Top, FInput.Width, Top + BandHeight),
    FColors.Gutter));
  if ALast then
  begin
    FLayout.AnchorItem := FirstItem;
    FLayout.AnchorHit := FirstHit;
    FLayout.AnchorTop := Top;
    FLayout.AnchorHeight := BandHeight;
  end;
end;

procedure TBuilder.DrawPart(AFrom, ATill: Integer);
var
  Item: TAtlasHoverItem;
begin
  Item := NewItem(TAtlasHoverItemKind.Styled, Rect(FX, FY, FRight, FY + FLineHeight), FColors.Text);
  Item.From := AFrom;
  Item.Till := ATill;
  Add(Item);
  Inc(FX, FMeasure.DeclarationWidth(AFrom, ATill));
end;

procedure TBuilder.Navigation;
var
  NavHeight, Index, CaptionWidth: Integer;
  Box: TRect;
  Item: TAtlasHoverItem;
  Caption: string;
  Path: TArray<TAtlasHoverPathItem>;
  SmallFace: TAtlasHoverFace;
begin
  // Pfadzeile (nur angeheftet) auf Randfläche: Zurück-Knopf, besuchte Typen, rechts „angeheftet“.
  NavHeight := Scale(30);
  Add(NewItem(TAtlasHoverItemKind.Fill, Rect(0, 0, FInput.Width, NavHeight), FColors.Gutter));
  HorizontalLine(NavHeight - 1);
  Box := Rect(Scale(8), (NavHeight - Scale(20)) div 2, Scale(30), (NavHeight - Scale(20)) div 2 + Scale(20));
  Item := NewItem(TAtlasHoverItemKind.Frame, Box, FColors.Line);
  Item.Back := FColors.Surface;
  Item.Radius := 4;
  if FInput.View.CanGoBack then
  begin
    Item.HotKind := TAtlasHoverHitKind.Back;
    Item.HotIndex := 0;
    Item.HotColor := FColors.Accent;
  end;
  Add(Item);
  if FInput.View.CanGoBack then
    Item := NewItem(TAtlasHoverItemKind.CenterText, Box, FColors.Text)
  else
    Item := NewItem(TAtlasHoverItemKind.CenterText, Box, FColors.Muted);
  Item.Text := '‹';
  Item.Face := Face(TAtlasHoverFont.Mono, True);
  Add(Item);
  if FInput.View.CanGoBack then
    AddHit(TAtlasHoverHitKind.Back, 0, Box);
  FFlowFont := TAtlasHoverFont.Mono;
  FNoWrap := True;
  FY := (NavHeight - Height(Face(TAtlasHoverFont.Mono, False))) div 2;
  FX := Box.Right + Scale(6);
  Path := FInput.View.Path;
  for Index := 0 to High(Path) do
  begin
    if Index > 0 then
      Flow(' › ', FColors.Muted, False, TAtlasHoverHitKind.Path, -1, -1, FColors.Muted);
    if Index = High(Path) then
      Flow(Path[Index].Caption, FColors.Text, True, TAtlasHoverHitKind.Path, -1, -1, FColors.Text)
    else if Path[Index].Index < 0 then
      Flow(Path[Index].Caption, FColors.Muted, False, TAtlasHoverHitKind.Path, -1, -1, FColors.Muted)
    else
      Flow(Path[Index].Caption, FColors.Muted, False, TAtlasHoverHitKind.Path, Path[Index].Index,
        Path[Index].Index, FColors.Muted);
  end;
  SmallFace := Face(TAtlasHoverFont.SmallUi, False);
  Caption := FInput.Texts.Pinned;
  CaptionWidth := Width(SmallFace, Caption);
  if FX + CaptionWidth + Scale(12) < FRight then
    AddText(FRight - CaptionWidth, (NavHeight - Height(SmallFace)) div 2, Caption, SmallFace, FColors.Muted);
  FNoWrap := False;
  FFlowFont := TAtlasHoverFont.Ui;
  FRowHeight := 0;
  FY := NavHeight + Scale(8);
  FX := FLeft;
end;

procedure TBuilder.Problems;
var
  Index, Start: Integer;
  Problem: TAtlasProblem;
  Caption: string;
  SmallFace: TAtlasHoverFace;
  Bar: TAtlasHoverItem;
  OldFont: TAtlasHoverFont;
begin
  // Probleme an der Mausposition: Farbbalken, Meldung, darunter Code und Herkunft
  // und bei Regeltreffern die Konfidenz.
  SmallFace := Face(TAtlasHoverFont.SmallUi, False);
  for Index := 0 to High(FInput.View.Problems) do
  begin
    Problem := FInput.View.Problems[Index];
    Start := FY;
    FLeft := Scale(20);
    Block(Problem.Caption, FColors.Text, 3);
    Dec(FY, Scale(4));
    if Problem.IsCompiler then
      Caption := FInput.Texts.SourceCompiler
    else if Problem.IsUses then
      Caption := FInput.Texts.SourceUses
    else if Problem.Unnecessary then
      // Inaktiver {$IFDEF}-Zweig (#615).
      Caption := FInput.Texts.SourceInactive
    else
      Caption := FInput.Texts.SourceAtlas;
    if Problem.Stale then
      Caption := Caption + ' · ' + FInput.Texts.Stale;
    AddText(FLeft, FY, Caption, SmallFace, FColors.Muted);
    // Konfidenz eines Regeltreffers als eigene Zeile (#144).
    Caption := '';
    if Index <= High(FInput.Texts.Confidences) then
      Caption := FInput.Texts.Confidences[Index];
    if Caption <> '' then
    begin
      Inc(FY, Height(SmallFace) + Scale(2));
      AddText(FLeft, FY, Caption, SmallFace, FColors.Muted);
    end;
    Inc(FY, Height(SmallFace) + Scale(6));
    // Aktionen zum uses-Eintrag (#621).
    if (Problem.UsesState = TAtlasProblem.UsesUnused) or (Problem.UsesState = TAtlasProblem.UsesImplementation) then
    begin
      OldFont := FFlowFont;
      FFlowFont := TAtlasHoverFont.SmallUi;
      FX := FLeft;
      FRowHeight := 0;
      if Problem.UsesState = TAtlasProblem.UsesUnused then
      begin
        ProblemLink(FInput.Texts.UsesRemove, Index, TAtlasHoverProblemAction.RemoveUses);
        if Problem.UsesUnusedCount > 1 then
          ProblemLink(FInput.Texts.UsesRemoveAll, Index, TAtlasHoverProblemAction.RemoveAllUses);
      end
      else
        ProblemLink(FInput.Texts.UsesMove, Index, TAtlasHoverProblemAction.MoveUses);
      EndFlow;
      Inc(FY, Scale(6));
      FFlowFont := OldFont;
    end;
    FLeft := Scale(11);
    Bar := NewItem(TAtlasHoverItemKind.RoundFill, Rect(FLeft, Start + Scale(1), FLeft + Scale(3), FY - Scale(7)),
      ProblemColor(FColors, Problem));
    Bar.Radius := 1;
    Add(Bar);
  end;
end;

procedure TBuilder.Header;
var
  Caption, Location: string;
  Badge: TAtlasBadgeKind;
  Box: TRect;
  Item: TAtlasHoverItem;
  SmallFace, LocationFace: TAtlasHoverFace;
  Start: Integer;
begin
  // Kopfzeile: Badge, Art · Herkunft, rechts der Fundort.
  Caption := FInput.Texts.KindCaption;
  if (Caption <> '') and (FData.Origin <> '') then
    Caption := Caption + ' · ' + FData.Origin;
  Location := FData.LocationText;
  if (Caption = '') and (Location = '') then
    Exit;
  FLineHeight := Max(Height(Face(TAtlasHoverFont.Ui, False)), Scale(17));
  FX := FLeft;
  if FData.Kind <> '' then
  begin
    Badge := HoverBadgeKind(FData.Badge);
    Box := Rect(FLeft, FY, FLeft + Scale(24), FY + Scale(17));
    Item := NewItem(TAtlasHoverItemKind.RoundFill, Box, FColors.Badges[Badge].Background);
    Item.Radius := 4;
    Add(Item);
    Item := NewItem(TAtlasHoverItemKind.CenterText, Box, FColors.Badges[Badge].Text);
    Item.Text := FData.Badge;
    Item.Face := Face(TAtlasHoverFont.Badge, True);
    Add(Item);
    FX := Box.Right + Scale(7);
  end;
  SmallFace := Face(TAtlasHoverFont.SmallUi, False);
  AddText(FX, FY + (FLineHeight - Height(SmallFace)) div 2, Caption, SmallFace, FColors.Muted);
  if Location <> '' then
  begin
    Start := FX + Width(SmallFace, Caption) + Scale(12);
    LocationFace := Face(TAtlasHoverFont.SmallMono, False);
    AddText(Max(Start, FRight - Width(LocationFace, Location)), FY + (FLineHeight - Height(LocationFace)) div 2,
      Location, LocationFace, FColors.Muted);
  end;
  Inc(FY, FLineHeight + Scale(5));
  FX := FLeft;
end;

procedure TBuilder.Declaration;
var
  Lines: TArray<TPoint>;
  Line, Index, From, Till, Pos, Next, LinkFrom, LinkTill, Start: Integer;
  Links: TArray<TAtlasHoverLink>;
  Area: TRect;
  Item: TAtlasHoverItem;
  MonoFace: TAtlasHoverFace;
begin
  // Deklaration eingefärbt, an Leerzeichen umbrochen; Typnamen als Verweise in Akzentfarbe, unterstrichen.
  MonoFace := Face(TAtlasHoverFont.Mono, False);
  FLineHeight := Height(MonoFace) + Scale(2);
  Lines := FMeasure.DeclarationLines(FRight - FLeft, Scale(16));
  Links := FData.Links;
  for Line := 0 to High(Lines) do
  begin
    FX := FLeft;
    if Line > 0 then
      FX := FLeft + Scale(16);
    From := Lines[Line].X;
    Till := Lines[Line].Y;
    Pos := From;
    while Pos < Till do
    begin
      // Nächster Verweis, der in [Pos, Till) hineinreicht.
      Next := -1;
      for Index := 0 to High(Links) do
        if (Links[Index].Start + Links[Index].Length > Pos) and (Links[Index].Start < Till) and
          ((Next < 0) or (Links[Index].Start < Links[Next].Start)) then
          Next := Index;
      if Next < 0 then
      begin
        DrawPart(Pos, Till);
        Pos := Till;
        Continue;
      end;
      LinkFrom := Max(Pos, Links[Next].Start);
      LinkTill := Min(Till, Links[Next].Start + Links[Next].Length);
      if LinkFrom > Pos then
        DrawPart(Pos, LinkFrom);
      Start := FX;
      Inc(FX, FMeasure.DeclarationWidth(LinkFrom, LinkTill));
      Area := Rect(Start, FY, FX, FY + FLineHeight);
      AddHit(TAtlasHoverHitKind.Link, Next, Area);
      AddText(Start, FY + (FLineHeight - Height(MonoFace)) div 2,
        Copy(FData.Declaration, LinkFrom + 1, LinkTill - LinkFrom), MonoFace, FColors.Accent);
      Item := NewItem(TAtlasHoverItemKind.Line, Rect(Area.Left, Area.Bottom - Scale(2), Area.Right,
        Area.Bottom - Scale(2)), FColors.Accent);
      Item.HotKind := TAtlasHoverHitKind.Link;
      Item.HotIndex := Next;
      Item.HotPenWidth := Scale(2);
      Add(Item);
      Pos := LinkTill;
    end;
    Inc(FY, FLineHeight);
  end;
  Inc(FY, Scale(6));
  FX := FLeft;
end;

procedure TBuilder.Description;
begin
  // Beschreibung unter einer Linie; nur die XMLDoc scrollt.
  if not (((FData.LocationText = '') and (FData.UnitName <> '')) or (FData.Value <> '') or
    (FData.Deprecation <> '') or FInput.HasDoc) then
    Exit;
  HorizontalLine(FY);
  Inc(FY, Scale(7));
  if FData.LocationText = '' then
    Block(FData.UnitName, FColors.Muted, 0);
  if FData.Value <> '' then
    Block('= ' + FData.Value, FColors.Muted, 0);
  Block(FData.Deprecation, FColors.Warn, 0);
  FLayout.DocLeft := FLeft;
  FLayout.DocTop := FY;
  if FInput.HasDoc then
  begin
    Add(NewItem(TAtlasHoverItemKind.Doc, Rect(FLeft, FY, FLeft, FY), FColors.Text));
    Inc(FY, FInput.DocHeight + Scale(6));
  end;
  Inc(FY, Scale(1));
end;

procedure TBuilder.Run;
begin
  FFlowFont := TAtlasHoverFont.Ui;
  FNoWrap := False;
  FRowHeight := 0;
  FLeft := Scale(11);
  FRight := FInput.Width - Scale(11);
  FY := Scale(8);
  FX := FLeft;
  if FInput.View.Pinned then
    Navigation;
  if Length(FInput.View.Problems) > 0 then
  begin
    Problems;
    // Ohne Bezeichner zeigt der Tooltip nur die Probleme.
    if FData.Declaration = '' then
    begin
      FY := FY + Scale(2);
      Exit;
    end;
    HorizontalLine(FY);
    Inc(FY, Scale(8));
  end;
  Header;
  Declaration;
  Description;
  // Vererbung bzw. Zieltyp und Aktionsleiste auf eigener Randfläche.
  if Length(FData.Ancestors) > 0 then
    Band(BandChain, not FData.Location.HasLocation);
  if FData.Location.HasLocation then
    Band(BandActions, True);
end;

function TBuilder.Layout: TAtlasHoverLayout;
begin
  Run;
  SetLength(FItems, FItemCount);
  SetLength(FHits, FHitCount);
  Result := FLayout;
  Result.Items := FItems;
  Result.Hits := FHits;
  Result.Height := FY;
end;

{ TAtlasHoverLayout }

class function TAtlasHoverLayout.Build(const AInput: TAtlasHoverInput;
  const AMeasure: IAtlasHoverMeasure): TAtlasHoverLayout;
var
  Builder: TBuilder;
begin
  Builder := TBuilder.Create(AInput, AMeasure);
  try
    Result := Builder.Layout;
  finally
    Builder.Free;
  end;
end;

function TAtlasHoverLayout.HitAt(const APoint: TPoint): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Hits) do
    if Hits[Index].Rect.Contains(APoint) then
      Exit(Index);
  Result := -1;
end;

class function TAtlasHoverLayout.ProblemActionCode(AProblem: Integer; AAction: TAtlasHoverProblemAction): Integer;
begin
  Result := AProblem * (Ord(High(TAtlasHoverProblemAction)) + 1) + Ord(AAction);
end;

class procedure TAtlasHoverLayout.DecodeProblemAction(ACode: Integer; out AProblem: Integer;
  out AAction: TAtlasHoverProblemAction);
begin
  AProblem := ACode div (Ord(High(TAtlasHoverProblemAction)) + 1);
  AAction := TAtlasHoverProblemAction(ACode mod (Ord(High(TAtlasHoverProblemAction)) + 1));
end;

function TAtlasHoverLayout.IsHot(AHot: Integer; AKind: TAtlasHoverHitKind; AIndex: Integer): Boolean;
begin
  Result := (AHot >= 0) and (AHot <= High(Hits)) and (Hits[AHot].Kind = AKind) and (Hits[AHot].Index = AIndex);
end;

procedure TAtlasHoverLayout.Anchor(AClientHeight: Integer);
var
  Wanted, Delta, Index: Integer;
begin
  if AnchorItem < 0 then
    Exit;
  Wanted := Max(0, AClientHeight - AnchorHeight - AnchorTop);
  Delta := Wanted - AnchorShift;
  if Delta = 0 then
    Exit;
  for Index := AnchorItem to High(Items) do
    Items[Index].Rect.Offset(0, Delta);
  for Index := AnchorHit to High(Hits) do
    Hits[Index].Rect.Offset(0, Delta);
  AnchorShift := Wanted;
end;

end.
