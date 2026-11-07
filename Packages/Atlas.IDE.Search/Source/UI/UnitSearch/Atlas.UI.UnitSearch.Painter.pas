unit Atlas.UI.UnitSearch.Painter;

// Zeichnen des Fensters „Units suchen“ (#777) aus TAtlasUnitSearchData:
//   Kopf:    Suchfeld mit Filterchips aus der Tippsyntax, rechts Projekt /
//            Ordner / Flach.
//   Modus:   „Unit verwenden in <Unit>“ mit Umschalter interface /
//            implementation (#786), „Formulare suchen“.
//   Chips:   Herkunft und Art.
//   Liste:   virtuell (nur sichtbare Zeilen), zwei Zeilen je Unit,
//            Gruppenköpfe mit Trefferzahl und Pfeil.
//   Vorschau rechts (TAtlasUnitSearchPreviewPainter), Aktionsleiste,
//   Fußzeile mit Tasten und „n von m“.
// Beim Zeichnen merkt sich der Painter, was wo liegt (HitAt).

interface

uses
  System.SysUtils,
  System.Types,
  System.Generics.Collections,
  Vcl.Graphics,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.Sections,
  Atlas.UI.UnitSearch.Data;

type
  /// <summary>Schriften des Fensters: Oberfläche, klein, nichtproportional.</summary>
  TAtlasUnitSearchFonts = record
    UI: TFont;
    Small: TFont;
    Mono: TFont;
  end;

  TAtlasUnitSearchPainter = class
  private
    FData: TAtlasUnitSearchData;
    FColors: TAtlasColors;
    FFonts: TAtlasUnitSearchFonts;
    FAreas: TList<TAtlasUnitSearchHitArea>;
    FCanvas: TCanvas;
    FClient: TRect;
    function S(AValue: Integer): Integer;
    procedure AddArea(AKind: TAtlasUnitSearchHit; const ARect: TRect; AValue: Integer);
    procedure Text(const AText: string; ARect: TRect; AFormat: Cardinal);
    procedure SetColors(AFill, APen, AFont: TAtlasColor);
    procedure DrawChip(var AX: Integer; AY: Integer; const ACaption: string; AOn: Boolean; AValue: Integer;
      ARight: Integer);
    /// <summary>Umschalter Projekt / Ordner / Flach rechts im Kopf; Ergebnis: linker Rand.</summary>
    function DrawGroupingSwitch: Integer;
    procedure DrawHeader;
    /// <summary>Umschalter interface / implementation in ABar; Ergebnis: linker Rand.</summary>
    function DrawSectionSwitch(const ABar: TRect): Integer;
    procedure DrawMode(const ACaption: string);
    procedure DrawChips;
    procedure DrawList;
    procedure DrawRow(ARow: Integer; const ARect: TRect);
    procedure DrawGroupRow(const ARow: TAtlasUnitRow; const ARect: TRect);
    /// <summary>Häkchen der Mehrfachauswahl; Ergebnis: linker Rand des Texts.</summary>
    function DrawCheck(ARow: Integer; const ARect: TRect; ALeft: Integer): Integer;
    /// <summary>Abzeichen rechtsbündig vor ARight; ARight wandert nach links.</summary>
    procedure DrawBadge(var ARight: Integer; const ARect: TRect; const AText: string; AMaxWidth, ARadius,
      AGap: Integer);
    procedure DrawRowBadges(const ARow: TAtlasUnitRow; const ARect: TRect; var ARight: Integer);
    procedure DrawNames(const AEntry: TAtlasUnitEntry; AInUses: Boolean; const ARect: TRect; ALeft, ARight: Integer);
    procedure DrawPath(const AEntry: TAtlasUnitEntry; const ARect: TRect; ALeft: Integer);
    /// <summary>Text mit hervorgehobenen Treffern, sonst in ABase; Ergebnis: rechter Rand des Gezeichneten.
    /// </summary>
    function DrawHighlighted(const AText: string; ARect: TRect; ABase: TAtlasColor): Integer;
    procedure DrawActions;
    procedure DrawFooter;
  public
    constructor Create(AData: TAtlasUnitSearchData; const AColors: TAtlasColors);
    destructor Destroy; override;
    /// <summary>Alles außer der Vorschau auf ACanvas in AClient zeichnen; ACaption steht in der Modus-Zeile.
    /// </summary>
    procedure Paint(ACanvas: TCanvas; const AClient: TRect; const ACaption: string);
    /// <summary>Oberste Fläche an (X, Y) aus dem letzten Zeichnen.</summary>
    function HitAt(AX, AY: Integer; out AArea: TAtlasUnitSearchHitArea): Boolean;
    property Fonts: TAtlasUnitSearchFonts read FFonts;
    property Colors: TAtlasColors read FColors;
  end;

  /// <summary>Vorschau rechts: Name, Kenndaten und Abschnitte (#876), die nicht passenden eingeklappt.</summary>
  TAtlasUnitSearchPreviewPainter = class
  private
    FPainter: TAtlasUnitSearchPainter;
    FData: TAtlasUnitSearchData;
    function Canvas: TCanvas;
    function Preview: TAtlasUnitPreview;
    procedure DrawFacts(const AArea: TRect; var ATop: Integer);
    procedure DrawSections(const AArea: TRect; ATop: Integer);
    procedure DrawSketch(var ATop: Integer; const AArea: TRect);
    function SketchHeight(AWidth: Integer): Integer;
    function SectionPresent(ASection: TAtlasPreviewSection): Boolean;
    function SectionCaption(ASection: TAtlasPreviewSection): string;
    procedure DrawSectionHead(ASection: TAtlasPreviewSection; const ARect: TRect);
    /// <summary>Zeichnet (ADraw) oder misst den Inhalt des Abschnitts; Ergebnis ist die Höhe.</summary>
    function SectionBody(ASection: TAtlasPreviewSection; const AArea: TRect; ADraw: Boolean): Integer;
    function PathBody(const AArea: TRect; ADraw: Boolean): Integer;
    function WrappedBody(const AText: string; const AArea: TRect; ADraw: Boolean; AMaxHeight: Integer;
      AFormat: Cardinal): Integer;
    function TypesBody(const AArea: TRect; ADraw: Boolean): Integer;
    procedure DrawType(const AType: TAtlasUnitType; const AArea: TRect; ATop: Integer);
  public
    constructor Create(APainter: TAtlasUnitSearchPainter; AData: TAtlasUnitSearchData);
    procedure Paint;
  end;

/// <summary>Beschriftung der Aktion AAction.</summary>
function UnitSearchActionCaption(AAction: TAtlasUnitSearchAction): string;
/// <summary>Aktion AAction wird angeboten (In uses aufnehmen nur mit AOptions.AddUses).</summary>
function UnitSearchActionVisible(const AOptions: TAtlasUnitSearchOptions; AAction: TAtlasUnitSearchAction): Boolean;

implementation

uses
  Winapi.Windows,
  System.Math,
  Atlas.Core.UnitSearch.UseUnit,
  Atlas.Core.Completion.Presentation,
  Atlas.UI.Strings,
  Atlas.UI.Search.Strings;

const
  cLine = DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX;
  cLineEllipsis = cLine or DT_END_ELLIPSIS;
  cCentered = cLine or DT_CENTER;

function C(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

function UnitSearchActionCaption(AAction: TAtlasUnitSearchAction): string;
begin
  case AAction of
    TAtlasUnitSearchAction.Open: Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchOpen);
    TAtlasUnitSearchAction.OpenForm: Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchOpenForm);
    TAtlasUnitSearchAction.AddUses: Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchAddUses);
    TAtlasUnitSearchAction.OpenTests: Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchOpenTests);
    TAtlasUnitSearchAction.CopyPaths: Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchCopyPaths);
    TAtlasUnitSearchAction.ShowProject: Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchShowProject);
  else
    Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchShowExplorer);
  end;
end;

function UnitSearchActionVisible(const AOptions: TAtlasUnitSearchOptions; AAction: TAtlasUnitSearchAction): Boolean;
begin
  Result := (AAction <> TAtlasUnitSearchAction.AddUses) or AOptions.AddUses;
end;

function OriginCaption(AOrigin: TAtlasUnitOrigin): string;
begin
  case AOrigin of
    TAtlasUnitOrigin.Active: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginActive);
    TAtlasUnitOrigin.Group: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginGroup);
    TAtlasUnitOrigin.SearchPath: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginSearchPath);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginLibrary);
  end;
end;

function KindCaption(AKind: TAtlasUnitKind): string;
begin
  case AKind of
    TAtlasUnitKind.Form: Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchKindForm);
    TAtlasUnitKind.Frame: Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchKindFrame);
    TAtlasUnitKind.DataModule: Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchKindDataModule);
    TAtlasUnitKind.Test: Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchKindTest);
    TAtlasUnitKind.Include: Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchKindInclude);
  else
    Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchKindUnit);
  end;
end;

function KindShort(AKind: TAtlasUnitKind): string;
begin
  case AKind of
    TAtlasUnitKind.Form: Result := 'FORM';
    TAtlasUnitKind.Frame: Result := 'FRAME';
    TAtlasUnitKind.DataModule: Result := 'DM';
    TAtlasUnitKind.Test: Result := 'TEST';
    TAtlasUnitKind.Include: Result := 'INC';
  else
    Result := 'UNIT';
  end;
end;

/// <summary>Feste Farbe je Projektname aus den Paarfarben der Palette.</summary>
function ProjectColor(const AColors: TAtlasColors; const AProject: string): TAtlasColor;
var
  mHash: Cardinal;
  mIndex: Integer;
begin
  mHash := 0;
  for mIndex := 1 to Length(AProject) do
  begin
    mHash := ((mHash and $FFFFFF) * 31 + Ord(UpCase(AProject[mIndex]))) and $FFFFFF;
  end;
  Result := AColors.Pairs[mHash mod Cardinal(Length(AColors.Pairs))];
end;

function GroupCaption(const AGroup: string; AGrouping: TAtlasUnitGrouping): string;
begin
  Result := AGroup;
  if (Result = '') and (AGrouping = TAtlasUnitGrouping.Folder) then
  begin
    Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchRootFolder);
  end
  else if Result = '' then
  begin
    Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchNoProject);
  end;
end;

/// <summary>Erste Zeile, die in den Bildlauf AScroll hineinreicht (Binärsuche: flüssig bei 5000 Units).</summary>
function FirstVisibleRow(const AList: TAtlasUnitSearchList): Integer;
var
  mLow, mHigh, mMiddle: Integer;
begin
  mLow := 0;
  mHigh := High(AList.Rows);
  Result := 0;
  while mLow <= mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if AList.RowTops[mMiddle + 1] <= AList.Scroll then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      Result := mMiddle;
      mHigh := mMiddle - 1;
    end;
  end;
end;

{ TAtlasUnitSearchPainter }

constructor TAtlasUnitSearchPainter.Create(AData: TAtlasUnitSearchData; const AColors: TAtlasColors);
begin
  inherited Create;
  FData := AData;
  FColors := AColors;
  FAreas := TList<TAtlasUnitSearchHitArea>.Create;
  FFonts.UI := TFont.Create;
  FFonts.UI.Name := 'Segoe UI';
  FFonts.UI.Size := 10;
  FFonts.Small := TFont.Create;
  FFonts.Small.Name := 'Segoe UI';
  FFonts.Small.Size := 8;
  FFonts.Mono := TFont.Create;
  FFonts.Mono.Name := 'Consolas';
  FFonts.Mono.Size := 9;
end;

destructor TAtlasUnitSearchPainter.Destroy;
begin
  FAreas.Free;
  FFonts.UI.Free;
  FFonts.Small.Free;
  FFonts.Mono.Free;
  inherited Destroy;
end;

function TAtlasUnitSearchPainter.S(AValue: Integer): Integer;
begin
  Result := FData.Metrics.S(AValue);
end;

procedure TAtlasUnitSearchPainter.AddArea(AKind: TAtlasUnitSearchHit; const ARect: TRect; AValue: Integer);
var
  mArea: TAtlasUnitSearchHitArea;
begin
  mArea.Kind := AKind;
  mArea.Rect := ARect;
  mArea.Value := AValue;
  FAreas.Add(mArea);
end;

function TAtlasUnitSearchPainter.HitAt(AX, AY: Integer; out AArea: TAtlasUnitSearchHitArea): Boolean;
var
  mIndex: Integer;
begin
  // Rückwärts: Häkchen und Chips liegen über Zeilen und Feld.
  for mIndex := FAreas.Count - 1 downto 0 do
  begin
    if PtInRect(FAreas[mIndex].Rect, Point(AX, AY)) then
    begin
      AArea := FAreas[mIndex];
      Exit(True);
    end;
  end;
  AArea := Default(TAtlasUnitSearchHitArea);
  Result := False;
end;

procedure TAtlasUnitSearchPainter.Text(const AText: string; ARect: TRect; AFormat: Cardinal);
begin
  DrawText(FCanvas.Handle, PChar(AText), -1, ARect, AFormat);
end;

procedure TAtlasUnitSearchPainter.SetColors(AFill, APen, AFont: TAtlasColor);
begin
  FCanvas.Brush.Color := C(AFill);
  FCanvas.Pen.Color := C(APen);
  FCanvas.Font.Color := C(AFont);
end;

procedure TAtlasUnitSearchPainter.Paint(ACanvas: TCanvas; const AClient: TRect; const ACaption: string);
begin
  FCanvas := ACanvas;
  FClient := AClient;
  FAreas.Clear;
  FCanvas.Brush.Color := C(FColors.Surface);
  FCanvas.FillRect(FClient);
  DrawHeader;
  DrawMode(ACaption);
  DrawChips;
  DrawList;
  TAtlasUnitSearchPreviewPainter.Create(Self, FData).Paint;
  DrawActions;
  DrawFooter;
  // Rahmen in Akzentfarbe (ältere Windows-Versionen ohne Rahmenfarbe des Fenstermanagers).
  FCanvas.Brush.Style := bsClear;
  FCanvas.Pen.Color := C(FColors.Accent);
  FCanvas.Rectangle(FClient);
  FCanvas.Brush.Style := bsSolid;
end;

procedure TAtlasUnitSearchPainter.DrawChip(var AX: Integer; AY: Integer; const ACaption: string; AOn: Boolean;
  AValue: Integer; ARight: Integer);
var
  mChip: TRect;
  mWidth: Integer;
begin
  mWidth := FCanvas.TextWidth(ACaption) + S(16);
  if AX + mWidth > ARight then
  begin
    Exit;
  end;
  mChip := Rect(AX, AY, AX + mWidth, AY + S(22));
  if AOn then
  begin
    SetColors(FColors.AccentSoft, FColors.Accent, FColors.Text);
  end
  else
  begin
    SetColors(FColors.Surface, FColors.Line, FColors.Muted);
  end;
  FCanvas.RoundRect(mChip.Left, mChip.Top, mChip.Right, mChip.Bottom, S(22), S(22));
  FCanvas.Brush.Style := bsClear;
  Text(ACaption, mChip, cCentered);
  FCanvas.Brush.Style := bsSolid;
  AddArea(TAtlasUnitSearchHit.Chip, mChip, AValue);
  AX := mChip.Right + S(6);
end;

function TAtlasUnitSearchPainter.DrawGroupingSwitch: Integer;
var
  mSegment: TRect;
  mX, mWidth: Integer;
  mGrouping: TAtlasUnitGrouping;
  mCaptions: array[TAtlasUnitGrouping] of string;
begin
  mCaptions[TAtlasUnitGrouping.Project] := TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupProject);
  mCaptions[TAtlasUnitGrouping.Folder] := TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupFolder);
  mCaptions[TAtlasUnitGrouping.None] := TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupNone);
  mWidth := 0;
  for mGrouping := Low(TAtlasUnitGrouping) to High(TAtlasUnitGrouping) do
  begin
    mWidth := Max(mWidth, FCanvas.TextWidth(mCaptions[mGrouping]) + S(20));
  end;
  Result := FClient.Width - S(10) - 3 * mWidth;
  mX := Result;
  for mGrouping in [TAtlasUnitGrouping.Project, TAtlasUnitGrouping.Folder, TAtlasUnitGrouping.None] do
  begin
    mSegment := Rect(mX, S(9), mX + mWidth, FData.Metrics.HeaderHeight - S(9));
    if mGrouping = FData.List.Grouping then
    begin
      SetColors(FColors.Selection, FColors.Line, FColors.Text);
    end
    else
    begin
      SetColors(FColors.Gutter, FColors.Line, FColors.Muted);
    end;
    FCanvas.Rectangle(mSegment);
    FCanvas.Brush.Style := bsClear;
    Text(mCaptions[mGrouping], mSegment, cCentered);
    FCanvas.Brush.Style := bsSolid;
    AddArea(TAtlasUnitSearchHit.Grouping, mSegment, Ord(mGrouping));
    Inc(mX, mWidth);
  end;
end;

procedure TAtlasUnitSearchPainter.DrawHeader;
var
  mInput: TRect;
  mX, mIndex: Integer;
  mText: string;
begin
  FCanvas.Font.Assign(FFonts.UI);
  // Suchfeld mit Akzentrahmen und getippten Filtern als Chips, rechts davon der Umschalter.
  mInput := Rect(S(10), S(7), DrawGroupingSwitch - S(10), FData.Metrics.HeaderHeight - S(7));
  FCanvas.Pen.Color := C(FColors.Accent);
  FCanvas.Brush.Color := C(FColors.Gutter);
  FCanvas.RoundRect(mInput.Left, mInput.Top, mInput.Right, mInput.Bottom, S(8), S(8));
  mX := mInput.Left + S(8);
  FCanvas.Font.Assign(FFonts.Small);
  for mIndex := 0 to High(FData.Filter.Typed) do
  begin
    DrawChip(mX, mInput.Top + (mInput.Height - S(22)) div 2, FData.Filter.Typed[mIndex] + '  ×', True,
      cChipTyped + mIndex, mInput.Right - S(80));
  end;
  FCanvas.Font.Assign(FFonts.UI);
  mInput.Left := mX;
  InflateRect(mInput, -S(4), 0);
  FCanvas.Brush.Style := bsClear;
  FCanvas.Font.Color := C(FColors.Text);
  mText := FData.Filter.Pattern + '|';
  if (FData.Filter.Pattern = '') and (Length(FData.Filter.Typed) = 0) then
  begin
    FCanvas.Font.Color := C(FColors.Muted);
    mText := TAtlasStrings.Text(TAtlasTextId.UnitSearchTitle) + ' …';
    if FData.Options.FilterSyntax then
    begin
      mText := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchPrompt);
    end;
  end;
  Text(mText, mInput, cLineEllipsis);
  FCanvas.Brush.Style := bsSolid;
end;

function TAtlasUnitSearchPainter.DrawSectionSwitch(const ABar: TRect): Integer;
var
  mSegment: TRect;
  mX, mWidth: Integer;
  mSection: TAtlasUseUnitSection;
begin
  FCanvas.Font.Assign(FFonts.Small);
  mWidth := Max(FCanvas.TextWidth('interface'), FCanvas.TextWidth('implementation')) + S(20);
  Result := ABar.Right - S(10) - 2 * mWidth;
  mX := Result;
  for mSection := Low(TAtlasUseUnitSection) to High(TAtlasUseUnitSection) do
  begin
    mSegment := Rect(mX, ABar.Top + S(4), mX + mWidth, ABar.Bottom - S(4));
    FCanvas.Brush.Style := bsSolid;
    if mSection = FData.Use.Section then
    begin
      SetColors(FColors.AccentSoft, FColors.Accent, FColors.Text);
    end
    else
    begin
      SetColors(FColors.Gutter, FColors.Line, FColors.Muted);
    end;
    FCanvas.Rectangle(mSegment);
    FCanvas.Brush.Style := bsClear;
    Text(TAtlasUseUnit.SectionText(mSection), mSegment, cCentered);
    AddArea(TAtlasUnitSearchHit.SectionSwitch, mSegment, Ord(mSection));
    Inc(mX, mWidth);
  end;
end;

procedure TAtlasUnitSearchPainter.DrawMode(const ACaption: string);
var
  mBar, mPart: TRect;
begin
  if FData.Options.Mode = TAtlasUnitSearchMode.Search then
  begin
    Exit;
  end;
  mBar := Rect(0, FData.Metrics.HeaderHeight, FClient.Width, FData.Metrics.HeaderHeight + FData.Metrics.ModeHeight);
  mPart := Rect(mBar.Left + S(12), mBar.Top, mBar.Right - S(10), mBar.Bottom);
  // Umschalter interface / implementation rechts (Strg+I).
  if FData.Options.Mode = TAtlasUnitSearchMode.UseUnit then
  begin
    mPart.Right := DrawSectionSwitch(mBar) - S(10);
  end;
  FCanvas.Font.Assign(FFonts.UI);
  FCanvas.Font.Style := [fsBold];
  FCanvas.Font.Color := C(FColors.Text);
  FCanvas.Brush.Style := bsClear;
  Text(ACaption, mPart, cLineEllipsis);
  FCanvas.Font.Style := [];
  FCanvas.Brush.Style := bsSolid;
  FCanvas.Pen.Color := C(FColors.Line);
  FCanvas.MoveTo(mBar.Left, mBar.Bottom - 1);
  FCanvas.LineTo(mBar.Right, mBar.Bottom - 1);
end;

procedure TAtlasUnitSearchPainter.DrawChips;
var
  mX, mY: Integer;
  mOrigin: TAtlasUnitOrigin;
  mKind: TAtlasUnitKind;
begin
  if not FData.Options.Filters then
  begin
    Exit;
  end;
  FCanvas.Font.Assign(FFonts.Small);
  mX := S(10);
  mY := FData.Metrics.HeaderHeight + FData.Metrics.ModeHeight + (FData.Metrics.ChipHeight - S(22)) div 2 - S(2);
  for mOrigin := Low(TAtlasUnitOrigin) to High(TAtlasUnitOrigin) do
  begin
    DrawChip(mX, mY, OriginCaption(mOrigin), mOrigin in FData.Filter.Origins, cChipOrigins + Ord(mOrigin),
      FClient.Width - S(10));
  end;
  // Trenner zwischen Herkunft und Art.
  FCanvas.Pen.Color := C(FColors.Line);
  FCanvas.MoveTo(mX + S(2), mY + S(3));
  FCanvas.LineTo(mX + S(2), mY + S(19));
  Inc(mX, S(10));
  for mKind in [TAtlasUnitKind.Form, TAtlasUnitKind.Frame, TAtlasUnitKind.DataModule, TAtlasUnitKind.Unit_,
    TAtlasUnitKind.Test, TAtlasUnitKind.Include] do
  begin
    DrawChip(mX, mY, KindCaption(mKind), mKind in FData.Filter.Kinds, cChipKinds + Ord(mKind), FClient.Width - S(10));
  end;
end;

procedure TAtlasUnitSearchPainter.DrawGroupRow(const ARow: TAtlasUnitRow; const ARect: TRect);
var
  mText: string;
begin
  FCanvas.Font.Assign(FFonts.Small);
  FCanvas.Font.Style := [fsBold];
  FCanvas.Font.Color := C(FColors.Muted);
  mText := '▾  ';
  if ARow.Collapsed then
  begin
    mText := '▸  ';
  end;
  mText := mText + GroupCaption(ARow.Group, FData.List.Grouping) + '   ' + IntToStr(ARow.Count);
  Text(mText, Rect(ARect.Left + S(10), ARect.Top, ARect.Right - S(10), ARect.Bottom), cLineEllipsis);
  if FData.List.Grouping = TAtlasUnitGrouping.Project then
  begin
    FCanvas.Brush.Style := bsSolid;
    FCanvas.Brush.Color := C(ProjectColor(FColors, ARow.Group));
    FCanvas.FillRect(Rect(ARect.Left + S(2), ARect.Top + S(6), ARect.Left + S(5), ARect.Bottom - S(6)));
  end;
  FCanvas.Font.Style := [];
  FCanvas.Brush.Style := bsSolid;
end;

function TAtlasUnitSearchPainter.DrawCheck(ARow: Integer; const ARect: TRect; ALeft: Integer): Integer;
var
  mBox: TRect;
  mMarked: Boolean;
begin
  mMarked := FData.Marked.ContainsKey(FData.EntryKey(FData.List.Rows[ARow].Entry));
  mBox := Rect(ALeft, ARect.Top + (ARect.Height - S(14)) div 2, ALeft + S(14),
    ARect.Top + (ARect.Height - S(14)) div 2 + S(14));
  FCanvas.Brush.Style := bsSolid;
  FCanvas.Pen.Color := C(FColors.Line);
  FCanvas.Brush.Color := C(FColors.Surface);
  if mMarked then
  begin
    FCanvas.Brush.Color := C(FColors.Accent);
    FCanvas.Pen.Color := C(FColors.Accent);
  end;
  FCanvas.RoundRect(mBox.Left, mBox.Top, mBox.Right, mBox.Bottom, S(4), S(4));
  if mMarked then
  begin
    FCanvas.Pen.Color := C(FColors.Surface);
    FCanvas.Pen.Width := Max(1, S(2));
    FCanvas.MoveTo(mBox.Left + S(3), mBox.Top + S(7));
    FCanvas.LineTo(mBox.Left + S(6), mBox.Top + S(10));
    FCanvas.LineTo(mBox.Left + S(11), mBox.Top + S(4));
    FCanvas.Pen.Width := 1;
  end;
  AddArea(TAtlasUnitSearchHit.Check, mBox, ARow);
  FCanvas.Brush.Style := bsClear;
  Result := mBox.Right + S(8);
end;

procedure TAtlasUnitSearchPainter.DrawBadge(var ARight: Integer; const ARect: TRect; const AText: string;
  AMaxWidth, ARadius, AGap: Integer);
var
  mBadge: TRect;
  mWidth: Integer;
begin
  // Farben setzt der Aufrufer (Füllung, Rahmen, Schrift).
  mWidth := Min(FCanvas.TextWidth(AText) + S(12), AMaxWidth);
  mBadge := Rect(ARight - mWidth, ARect.Top + S(4), ARight, ARect.Top + S(20));
  FCanvas.Brush.Style := bsSolid;
  FCanvas.RoundRect(mBadge.Left, mBadge.Top, mBadge.Right, mBadge.Bottom, ARadius, ARadius);
  FCanvas.Brush.Style := bsClear;
  InflateRect(mBadge, -S(5), 0);
  Text(AText, mBadge, cCentered or DT_END_ELLIPSIS);
  ARight := mBadge.Left - AGap;
end;

/// <summary>Hinweis „schon in uses“ bzw. der Kreis, den die Aufnahme schlösse (#786); '' ohne.</summary>
function UseText(AData: TAtlasUnitSearchData; AEntry: Integer; out AWarning: Boolean): string;
var
  mCycle: TAtlasUseUnitCycle;
begin
  Result := '';
  AWarning := False;
  if AData.UseInUses(AEntry) then
  begin
    Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UseUnitInUses);
  end
  else if AData.UseCycle(AEntry, mCycle) then
  begin
    AWarning := TAtlasUseUnit.CycleState(mCycle, AData.Use.Section) = TAtlasUseUnitCycleState.Warning;
    Result := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UseUnitCycle, [TAtlasUseUnit.CycleVia(mCycle,
      AData.Use.Section)]);
    if AWarning then
    begin
      Result := '⚠ ' + Result;
    end;
  end;
end;

/// <summary>Füllfarbe des Abzeichens der Art.</summary>
function KindColor(const AColors: TAtlasColors; AKind: TAtlasUnitKind): TAtlasColor;
begin
  Result := AColors.Gutter;
  if AKind = TAtlasUnitKind.Test then
  begin
    Result := AColors.AddSoft;
  end
  else if AKind in [TAtlasUnitKind.Form, TAtlasUnitKind.Frame, TAtlasUnitKind.DataModule] then
  begin
    Result := AColors.WarnSoft;
  end;
end;

procedure TAtlasUnitSearchPainter.DrawRowBadges(const ARow: TAtlasUnitRow; const ARect: TRect; var ARight: Integer);
var
  mEntry: TAtlasUnitEntry;
  mText: string;
  mWarning: Boolean;
begin
  mEntry := FData.Entries[ARow.Entry];
  FCanvas.Font.Assign(FFonts.Small);
  // Rechts: Projekt, Art, uses bzw. Kreis, geöffnet.
  if mEntry.Project <> '' then
  begin
    SetColors(TAtlasColorMath.Mix(ProjectColor(FColors, mEntry.Project), FColors.Surface, 0.25),
      ProjectColor(FColors, mEntry.Project), FColors.Text);
    DrawBadge(ARight, ARect, mEntry.Project, S(150), S(8), S(11));
  end;
  SetColors(KindColor(FColors, mEntry.Kind), FColors.Line, FColors.Text);
  DrawBadge(ARight, ARect, KindShort(mEntry.Kind), MaxInt, S(6), S(13));
  mText := UseText(FData, ARow.Entry, mWarning);
  if (mText <> '') and mWarning then
  begin
    SetColors(FColors.WarnSoft, FColors.Warn, FColors.Text);
  end
  else
  begin
    SetColors(FColors.Gutter, FColors.Line, FColors.Muted);
  end;
  if mText <> '' then
  begin
    DrawBadge(ARight, ARect, mText, S(220), S(8), S(13));
  end;
  if mEntry.IsOpen then
  begin
    SetColors(FColors.Accent, FColors.Accent, FColors.Text);
    FCanvas.Brush.Style := bsSolid;
    FCanvas.Ellipse(ARight - S(8), ARect.Top + S(8), ARight, ARect.Top + S(16));
    FCanvas.Brush.Style := bsClear;
    ARight := ARight - S(14);
  end;
end;

procedure TAtlasUnitSearchPainter.DrawNames(const AEntry: TAtlasUnitEntry; AInUses: Boolean; const ARect: TRect;
  ALeft, ARight: Integer);
var
  mNameEnd: Integer;
begin
  // Zeile 1: Name mit Treffern.
  FCanvas.Font.Assign(FFonts.UI);
  if AInUses then
  begin
    // Ausgegraut: steht schon in uses.
    FCanvas.Font.Color := C(FColors.Muted);
    Text(AEntry.Name, Rect(ALeft, ARect.Top + S(2), ARight, ARect.Top + S(22)), cLineEllipsis);
    Exit;
  end;
  mNameEnd := DrawHighlighted(AEntry.Name, Rect(ALeft, ARect.Top + S(2), ARight, ARect.Top + S(22)), FColors.Text);
  // Caption des Formulars (#1310) grau hinter dem Namen: Damit ist ein Treffer über sie erkennbar.
  if (AEntry.Caption <> '') and (mNameEnd + S(30) < ARight) then
  begin
    DrawHighlighted(AEntry.Caption, Rect(mNameEnd + S(10), ARect.Top + S(2), ARight, ARect.Top + S(22)),
      FColors.Muted);
  end;
end;

procedure TAtlasUnitSearchPainter.DrawPath(const AEntry: TAtlasUnitEntry; const ARect: TRect; ALeft: Integer);
var
  mPath: string;
  mMaxChars: Integer;
  mPart: TRect;
begin
  // Zeile 2: Pfad, in der Mitte gekürzt.
  FCanvas.Font.Assign(FFonts.Small);
  FCanvas.Font.Color := C(FColors.Muted);
  mPath := TAtlasUnitSearch.DisplayPath(AEntry.FileName, FData.Options.Root, FData.Options.PathStyle, 0);
  mMaxChars := Length(mPath);
  mPart := Rect(ALeft, ARect.Top + S(21), ARect.Right - S(10), ARect.Bottom - S(2));
  while (FData.Options.PathStyle <> TAtlasUnitPathStyle.Absolute) and (mMaxChars > 8) and
    (FCanvas.TextWidth(TAtlasUnitSearch.MiddleEllipsis(mPath, mMaxChars)) > mPart.Width) do
  begin
    Dec(mMaxChars, Max(1, (mMaxChars div 20)));
  end;
  Text(TAtlasUnitSearch.MiddleEllipsis(mPath, mMaxChars), mPart, cLine or DT_PATH_ELLIPSIS);
end;

procedure TAtlasUnitSearchPainter.DrawRow(ARow: Integer; const ARect: TRect);
var
  mRow: TAtlasUnitRow;
  mLeft, mRight: Integer;
begin
  mRow := FData.List.Rows[ARow];
  if ARow = FData.List.Selected then
  begin
    FCanvas.Brush.Color := C(FColors.Selection);
    FCanvas.FillRect(ARect);
  end;
  FCanvas.Brush.Style := bsClear;
  if mRow.IsGroup then
  begin
    DrawGroupRow(mRow, ARect);
    Exit;
  end;
  mLeft := ARect.Left + S(10);
  if FData.Options.MultiSelect then
  begin
    mLeft := DrawCheck(ARow, ARect, mLeft);
  end;
  mRight := ARect.Right - S(10);
  DrawRowBadges(mRow, ARect, mRight);
  DrawNames(FData.Entries[mRow.Entry], FData.UseInUses(mRow.Entry), ARect, mLeft, mRight);
  DrawPath(FData.Entries[mRow.Entry], ARect, mLeft);
  FCanvas.Brush.Style := bsSolid;
end;

procedure TAtlasUnitSearchPainter.DrawList;
var
  mRow: Integer;
  mRowRect, mThumb, mList: TRect;
  mTotal: Integer;
  mClip: HRGN;
begin
  mList := FData.List.Rect;
  FCanvas.Font.Assign(FFonts.UI);
  if FData.List.Loading or (Length(FData.List.Rows) = 0) then
  begin
    FCanvas.Font.Color := C(FColors.Muted);
    FCanvas.Brush.Style := bsClear;
    if FData.List.Loading then
    begin
      Text(TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchLoading), mList, cCentered);
    end
    else
    begin
      Text('—', mList, cCentered);
    end;
    FCanvas.Brush.Style := bsSolid;
    Exit;
  end;
  mClip := CreateRectRgn(mList.Left, mList.Top, mList.Right, mList.Bottom);
  try
    SelectClipRgn(FCanvas.Handle, mClip);
    mRow := FirstVisibleRow(FData.List);
    while (mRow <= High(FData.List.Rows)) and
      (mList.Top + FData.List.RowTops[mRow] - FData.List.Scroll < mList.Bottom) do
    begin
      mRowRect := Rect(mList.Left + S(4), mList.Top + FData.List.RowTops[mRow] - FData.List.Scroll, mList.Right - S(10),
        mList.Top + FData.List.RowTops[mRow + 1] - FData.List.Scroll);
      DrawRow(mRow, mRowRect);
      AddArea(TAtlasUnitSearchHit.Row, mRowRect, mRow);
      Inc(mRow);
    end;
  finally
    SelectClipRgn(FCanvas.Handle, 0);
    DeleteObject(mClip);
  end;
  // Schmale Bildlaufleiste.
  mTotal := FData.List.RowTops[Length(FData.List.Rows)];
  if mTotal > mList.Height then
  begin
    mThumb := Rect(mList.Right - S(6), 0, mList.Right - S(2), 0);
    mThumb.Top := mList.Top + MulDiv(FData.List.Scroll, mList.Height, mTotal);
    mThumb.Bottom := mThumb.Top + Max(S(20), MulDiv(mList.Height, mList.Height, mTotal));
    FCanvas.Brush.Color := C(FColors.Line);
    FCanvas.FillRect(mThumb);
  end;
end;

function TAtlasUnitSearchPainter.DrawHighlighted(const AText: string; ARect: TRect; ABase: TAtlasColor): Integer;
var
  mMarks: TArray<Boolean>;
  mPosition, mIndex, mRun, mX: Integer;
  mChunk, mWord: string;
begin
  SetLength(mMarks, Length(AText) + 1);
  for mWord in FData.Query.Words do
  begin
    for mPosition in TAtlasItemPresentation.Highlights(mWord, AText) do
    begin
      if (mPosition >= 1) and (mPosition <= Length(AText)) then
      begin
        mMarks[mPosition] := True;
      end;
    end;
  end;
  mX := ARect.Left;
  mIndex := 1;
  while (mIndex <= Length(AText)) and (mX < ARect.Right) do
  begin
    mRun := mIndex;
    while (mRun < Length(AText)) and (mMarks[mRun + 1] = mMarks[mIndex]) do
    begin
      Inc(mRun);
    end;
    mChunk := Copy(AText, mIndex, mRun - mIndex + 1);
    FCanvas.Font.Style := [];
    FCanvas.Font.Color := C(ABase);
    if mMarks[mIndex] then
    begin
      FCanvas.Font.Style := [fsBold];
      FCanvas.Font.Color := C(FColors.Accent);
    end;
    Text(mChunk, Rect(mX, ARect.Top, ARect.Right, ARect.Bottom), cLineEllipsis);
    Inc(mX, FCanvas.TextWidth(mChunk));
    mIndex := mRun + 1;
  end;
  FCanvas.Font.Style := [];
  Result := Min(mX, ARect.Right);
end;

procedure TAtlasUnitSearchPainter.DrawActions;
var
  mBar, mButton: TRect;
  mX: Integer;
  mAction: TAtlasUnitSearchAction;
  mText: string;
begin
  if not FData.Options.Actions then
  begin
    Exit;
  end;
  mBar := Rect(0, FClient.Height - FData.Metrics.FooterHeight - FData.Metrics.ActionHeight, FClient.Width,
    FClient.Height - FData.Metrics.FooterHeight);
  FCanvas.Pen.Color := C(FColors.Line);
  FCanvas.MoveTo(mBar.Left, mBar.Top);
  FCanvas.LineTo(mBar.Right, mBar.Top);
  FCanvas.Font.Assign(FFonts.Small);
  mX := S(10);
  for mAction := Low(TAtlasUnitSearchAction) to High(TAtlasUnitSearchAction) do
  begin
    mText := UnitSearchActionCaption(mAction);
    mButton := Rect(mX, mBar.Top + S(6), mX + FCanvas.TextWidth(mText) + S(18), mBar.Bottom - S(6));
    if not UnitSearchActionVisible(FData.Options, mAction) then
    begin
      Continue;
    end;
    if mButton.Right > mBar.Right - S(10) then
    begin
      Break;
    end;
    if mAction = TAtlasUnitSearchAction.Open then
    begin
      SetColors(FColors.Accent, FColors.Accent, FColors.Surface);
    end
    else
    begin
      SetColors(FColors.Gutter, FColors.Line, FColors.Text);
    end;
    FCanvas.RoundRect(mButton.Left, mButton.Top, mButton.Right, mButton.Bottom, S(6), S(6));
    FCanvas.Brush.Style := bsClear;
    Text(mText, mButton, cCentered);
    FCanvas.Brush.Style := bsSolid;
    AddArea(TAtlasUnitSearchHit.Action, mButton, Ord(mAction));
    mX := mButton.Right + S(6);
  end;
end;

/// <summary>Linker Teil der Fußzeile: Kreis der aktuellen Unit (#786), sonst ihr voller Pfad, sonst die Tasten.
/// </summary>
function FooterText(AData: TAtlasUnitSearchData): string;
var
  mIndex: Integer;
  mCycle: TAtlasUseUnitCycle;
begin
  if AData.CurrentEntry(mIndex) and AData.UseCycle(mIndex, mCycle) then
  begin
    if TAtlasUseUnit.CycleState(mCycle, AData.Use.Section) = TAtlasUseUnitCycleState.Warning then
    begin
      Exit(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UseUnitCycleWarning,
        [TAtlasUseUnit.CyclePath(mCycle, AData.Use.Section)]));
    end;
    Exit(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UseUnitCycleHint, [TAtlasUseUnit.CyclePath(mCycle,
      AData.Use.Section)]));
  end;
  if mIndex >= 0 then
  begin
    Exit(AData.Entries[mIndex].FileName);
  end;
  case AData.Options.Mode of
    TAtlasUnitSearchMode.UseUnit:
      Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UseUnitHints);
    TAtlasUnitSearchMode.Forms:
      Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.FormsHints);
  else
    Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchHints);
  end;
end;

procedure TAtlasUnitSearchPainter.DrawFooter;
var
  mBar, mPart: TRect;
  mText: string;
begin
  mBar := Rect(0, FClient.Height - FData.Metrics.FooterHeight, FClient.Width, FClient.Height);
  FCanvas.Brush.Color := C(FColors.Gutter);
  FCanvas.FillRect(mBar);
  FCanvas.Font.Assign(FFonts.Small);
  FCanvas.Font.Color := C(FColors.Muted);
  FCanvas.Brush.Style := bsClear;
  mText := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchCount, [Length(FData.Filter.Order),
    Length(FData.Entries)]);
  if FData.Marked.Count > 0 then
  begin
    mText := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchMarked, [FData.Marked.Count]) + ' · ' + mText;
  end;
  mPart := Rect(mBar.Right - S(10) - FCanvas.TextWidth(mText), mBar.Top, mBar.Right - S(10), mBar.Bottom);
  Text(mText, mPart, cLine);
  mPart := Rect(mBar.Left + S(10), mBar.Top, mPart.Left - S(16), mBar.Bottom);
  Text(FooterText(FData), mPart, cLine or DT_PATH_ELLIPSIS);
  FCanvas.Brush.Style := bsSolid;
end;

{ TAtlasUnitSearchPreviewPainter }

constructor TAtlasUnitSearchPreviewPainter.Create(APainter: TAtlasUnitSearchPainter; AData: TAtlasUnitSearchData);
begin
  inherited Create;
  FPainter := APainter;
  FData := AData;
end;

function TAtlasUnitSearchPreviewPainter.Canvas: TCanvas;
begin
  Result := FPainter.FCanvas;
end;

function TAtlasUnitSearchPreviewPainter.Preview: TAtlasUnitPreview;
begin
  Result := FData.Preview.Data;
end;

procedure TAtlasUnitSearchPreviewPainter.Paint;
var
  mArea, mRect: TRect;
  mTop, mIndex: Integer;
begin
  try
    if not FData.Preview.Visible then
    begin
      Exit;
    end;
    mRect := FData.Preview.Rect;
    Canvas.Brush.Color := C(FPainter.FColors.Gutter);
    Canvas.FillRect(mRect);
    Canvas.Pen.Color := C(FPainter.FColors.Line);
    Canvas.MoveTo(mRect.Left, mRect.Top);
    Canvas.LineTo(mRect.Left, mRect.Bottom);
    FPainter.AddArea(TAtlasUnitSearchHit.Splitter, Rect(mRect.Left - FPainter.S(3), mRect.Top,
      mRect.Left + FPainter.S(3), mRect.Bottom), 0);
    mArea := mRect;
    InflateRect(mArea, -FPainter.S(12), -FPainter.S(10));
    mTop := mArea.Top;
    Canvas.Brush.Style := bsClear;
    if not FData.CurrentEntry(mIndex) or (Preview.FileName = '') then
    begin
      Canvas.Font.Assign(FPainter.FFonts.UI);
      Canvas.Font.Color := C(FPainter.FColors.Muted);
      FPainter.Text(TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchPreviewNone), mArea, cCentered);
    end
    else
    begin
      // Name und Kenndaten.
      Canvas.Font.Assign(FPainter.FFonts.UI);
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := C(FPainter.FColors.Text);
      FPainter.Text(FData.Entries[mIndex].Name, Rect(mArea.Left, mTop, mArea.Right, mTop + FPainter.S(20)),
        DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
      Inc(mTop, FPainter.S(22));
      DrawFacts(mArea, mTop);
      DrawSections(mArea, mTop);
    end;
    Canvas.Brush.Style := bsSolid;
  finally
    Free;
  end;
end;

/// <summary>Stand in git als Text; '' ohne bekannten Stand.</summary>
function GitText(const AGit: string): string;
const
  cStates: array[0..6] of string = ('clean', 'modified', 'added', 'untracked', 'deleted', 'renamed', 'conflict');
  cTexts: array[0..6] of TAtlasSearchTextId = (TAtlasSearchTextId.UnitSearchGitClean,
    TAtlasSearchTextId.UnitSearchGitModified, TAtlasSearchTextId.UnitSearchGitAdded,
    TAtlasSearchTextId.UnitSearchGitUntracked, TAtlasSearchTextId.UnitSearchGitDeleted,
    TAtlasSearchTextId.UnitSearchGitRenamed, TAtlasSearchTextId.UnitSearchGitConflict);
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := Low(cStates) to High(cStates) do
  begin
    if AGit = cStates[mIndex] then
    begin
      Result := TAtlasSearchStrings.Text(cTexts[mIndex]);
    end;
  end;
end;

procedure TAtlasUnitSearchPreviewPainter.DrawFacts(const AArea: TRect; var ATop: Integer);
var
  mFacts: TArray<string>;
  mGit: string;
begin
  Canvas.Font.Assign(FPainter.FFonts.Small);
  Canvas.Font.Color := C(FPainter.FColors.Muted);
  mFacts := TArray<string>.Create(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchPreviewLines,
    [Preview.Lines]));
  if Preview.Modified > 0 then
  begin
    mFacts := mFacts + [TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchPreviewModified,
      [FormatDateTime('dd.mm.yyyy hh":"nn', Preview.Modified)])];
  end;
  mGit := GitText(Preview.Git);
  if mGit <> '' then
  begin
    mFacts := mFacts + [mGit];
  end;
  FPainter.Text(string.Join(' · ', mFacts), Rect(AArea.Left, ATop, AArea.Right, ATop + FPainter.S(16)),
    DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  Inc(ATop, FPainter.S(22));
end;

procedure TAtlasUnitSearchPreviewPainter.DrawSections(const AArea: TRect; ATop: Integer);
var
  mSection: TAtlasPreviewSection;
  mInputs: TAtlasSectionInputs;
  mHead: Integer;
begin
  // Abschnitte (#876): erst messen, dann einklappen, was nicht passt.
  mHead := FData.Metrics.SectionHeadHeight;
  for mSection := Low(TAtlasPreviewSection) to High(TAtlasPreviewSection) do
  begin
    mInputs[mSection].Present := SectionPresent(mSection);
    mInputs[mSection].ClosedHeight := mHead;
    mInputs[mSection].OpenHeight := 0;
    if mInputs[mSection].Present then
    begin
      mInputs[mSection].OpenHeight := mHead + SectionBody(mSection, Rect(AArea.Left, 0, AArea.Right, MaxInt div 2),
        False) + FData.Metrics.SectionGap;
    end;
  end;
  FData.Preview.Sections := TAtlasPreviewSections.Arrange(mInputs, FData.State.Sections, AArea.Bottom - ATop,
    FData.Options.PreviewAutoCollapse);
  for mSection := Low(TAtlasPreviewSection) to High(TAtlasPreviewSection) do
  begin
    if FData.Preview.Sections[mSection] = TAtlasSectionState.Hidden then
    begin
      Continue;
    end;
    if ATop + mHead > AArea.Bottom then
    begin
      Break;
    end;
    DrawSectionHead(mSection, Rect(AArea.Left, ATop, AArea.Right, ATop + mHead));
    Inc(ATop, mHead);
    if TAtlasPreviewSections.IsOpen(FData.Preview.Sections[mSection]) then
    begin
      Inc(ATop, SectionBody(mSection, Rect(AArea.Left, ATop, AArea.Right, AArea.Bottom), True) +
        FData.Metrics.SectionGap);
    end;
  end;
end;

procedure TAtlasUnitSearchPreviewPainter.DrawSketch(var ATop: Integer; const AArea: TRect);
var
  mScale: Double;
  mFrame, mBox: TRect;
  mItem: TAtlasUnitSketchItem;
  mBody: Integer;
begin
  if (Preview.FormWidth <= 0) or (Preview.FormHeight <= 0) then
  begin
    Exit;
  end;
  mScale := Min(AArea.Width / Preview.FormWidth, FPainter.S(180) / Preview.FormHeight);
  mFrame := Rect(AArea.Left, ATop, AArea.Left + Round(Preview.FormWidth * mScale), ATop + SketchHeight(AArea.Width));
  // Titelleiste der Skizze.
  mBody := mFrame.Top + FPainter.S(14);
  FPainter.SetColors(FPainter.FColors.AccentSoft, FPainter.FColors.Line, FPainter.FColors.Text);
  Canvas.Rectangle(mFrame.Left, mFrame.Top, mFrame.Right, mBody);
  Canvas.Font.Assign(FPainter.FFonts.Small);
  Canvas.Font.Size := 7;
  Canvas.Font.Color := C(FPainter.FColors.Text);
  Canvas.Brush.Style := bsClear;
  FPainter.Text(Preview.FormCaption, Rect(mFrame.Left + FPainter.S(4), mFrame.Top, mFrame.Right - FPainter.S(4),
    mBody), cLineEllipsis);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := C(FPainter.FColors.Gutter);
  Canvas.Rectangle(mFrame.Left, mBody - FPainter.S(1), mFrame.Right, mFrame.Bottom);
  for mItem in Preview.FormItems do
  begin
    mBox := Rect(mFrame.Left + Round(mItem.Left * mScale), mBody + Round(mItem.Top * mScale),
      mFrame.Left + Round((mItem.Left + mItem.Width) * mScale), mBody + Round((mItem.Top + mItem.Height) * mScale));
    if (mBox.Width < 2) or (mBox.Height < 2) then
    begin
      Continue;
    end;
    Canvas.Brush.Color := C(TAtlasColorMath.Mix(FPainter.FColors.Accent, FPainter.FColors.Gutter,
      Min(0.45, 0.08 * mItem.Depth)));
    Canvas.Pen.Color := C(FPainter.FColors.Line);
    Canvas.Rectangle(mBox);
    if (mItem.Caption <> '') and (mBox.Height >= FPainter.S(10)) then
    begin
      Canvas.Brush.Style := bsClear;
      FPainter.Text(mItem.Caption, mBox, cCentered or DT_END_ELLIPSIS);
      Canvas.Brush.Style := bsSolid;
    end;
  end;
  ATop := mFrame.Bottom + FPainter.S(10);
end;

function TAtlasUnitSearchPreviewPainter.SketchHeight(AWidth: Integer): Integer;
begin
  Result := 0;
  if (Preview.FormWidth > 0) and (Preview.FormHeight > 0) then
  begin
    Result := Round(Preview.FormHeight * Min(AWidth / Preview.FormWidth, FPainter.S(180) / Preview.FormHeight)) +
      FPainter.S(14);
  end;
end;

function TAtlasUnitSearchPreviewPainter.SectionPresent(ASection: TAtlasPreviewSection): Boolean;
begin
  case ASection of
    TAtlasPreviewSection.Path:
      Result := Preview.FileName <> '';
    TAtlasPreviewSection.Header:
      Result := Preview.Header <> '';
    TAtlasPreviewSection.Form:
      Result := Preview.HasForm and (Preview.FormWidth > 0) and (Preview.FormHeight > 0);
    TAtlasPreviewSection.Types:
      Result := Preview.TypeCount > 0;
    TAtlasPreviewSection.Uses_:
      Result := Length(Preview.Uses_) > 0;
    TAtlasPreviewSection.UsedBy:
      Result := Preview.UsedBy >= 0;
  else
    Result := False;
  end;
end;

function TAtlasUnitSearchPreviewPainter.SectionCaption(ASection: TAtlasPreviewSection): string;
begin
  case ASection of
    TAtlasPreviewSection.Path:
      Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchPreviewPath);
    TAtlasPreviewSection.Header:
      Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchPreviewHeader);
    TAtlasPreviewSection.Form:
      Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchPreviewForm);
    TAtlasPreviewSection.Types:
      Result := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchPreviewTypes, [Preview.TypeCount]);
    TAtlasPreviewSection.Uses_:
      Result := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchPreviewUses, [Length(Preview.Uses_)]);
    TAtlasPreviewSection.UsedBy:
      Result := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchPreviewUsedBy, [Preview.UsedBy]);
  else
    Result := '';
  end;
  Result := AnsiUpperCase(Result);
end;

procedure TAtlasUnitSearchPreviewPainter.DrawSectionHead(ASection: TAtlasPreviewSection; const ARect: TRect);
var
  mLine, mTag: TRect;
  mText, mAuto: string;
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(FPainter.FFonts.Small);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := C(FPainter.FColors.Muted);
  mText := #$25B8' ' + SectionCaption(ASection);
  if TAtlasPreviewSections.IsOpen(FData.Preview.Sections[ASection]) then
  begin
    mText := #$25BE' ' + SectionCaption(ASection);
  end;
  mLine := ARect;
  mLine.Bottom := mLine.Bottom - FPainter.S(4);
  // Marke rechts, wenn Atlas den Abschnitt eingeklappt hat.
  if FData.Preview.Sections[ASection] = TAtlasSectionState.AutoCollapsed then
  begin
    Canvas.Font.Style := [];
    mAuto := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchPreviewAutoCollapsed);
    mTag := mLine;
    mTag.Left := Max(mLine.Left, mLine.Right - Canvas.TextWidth(mAuto));
    FPainter.Text(mAuto, mTag, DT_SINGLELINE or DT_VCENTER or DT_RIGHT or DT_NOPREFIX or DT_END_ELLIPSIS);
    mLine.Right := mTag.Left - FPainter.S(8);
    Canvas.Font.Style := [fsBold];
  end;
  FPainter.Text(mText, mLine, cLineEllipsis);
  FPainter.AddArea(TAtlasUnitSearchHit.Section, ARect, Ord(ASection));
end;

/// <summary>Units, die die Unit verwendet bzw. die sie verwenden (mit „…“, wenn es mehr gibt).</summary>
function UnitsText(const APreview: TAtlasUnitPreview; ASection: TAtlasPreviewSection): string;
begin
  if ASection = TAtlasPreviewSection.Uses_ then
  begin
    Exit(string.Join(', ', APreview.Uses_));
  end;
  Result := string.Join(', ', APreview.UsedByUnits);
  if APreview.UsedBy > Length(APreview.UsedByUnits) then
  begin
    Result := Result + ' …';
  end;
end;

function TAtlasUnitSearchPreviewPainter.SectionBody(ASection: TAtlasPreviewSection; const AArea: TRect;
  ADraw: Boolean): Integer;
var
  mTop: Integer;
begin
  case ASection of
    TAtlasPreviewSection.Path:
      Result := PathBody(AArea, ADraw);
    TAtlasPreviewSection.Header:
      begin
        Canvas.Font.Assign(FPainter.FFonts.Mono);
        Canvas.Font.Color := C(FPainter.FColors.Comment);
        Result := WrappedBody(Preview.Header.Replace(#10, sLineBreak), AArea, ADraw, FPainter.S(140),
          DT_EDITCONTROL);
      end;
    TAtlasPreviewSection.Form:
      begin
        Result := SketchHeight(AArea.Width);
        mTop := AArea.Top;
        if ADraw then
        begin
          DrawSketch(mTop, AArea);
        end;
      end;
    TAtlasPreviewSection.Types:
      Result := TypesBody(AArea, ADraw);
    TAtlasPreviewSection.Uses_, TAtlasPreviewSection.UsedBy:
      begin
        Canvas.Font.Assign(FPainter.FFonts.Small);
        Canvas.Font.Color := C(FPainter.FColors.Text);
        Result := WrappedBody(UnitsText(Preview, ASection), AArea, ADraw, MaxInt, 0);
      end;
  else
    Result := 0;
  end;
end;

function TAtlasUnitSearchPreviewPainter.PathBody(const AArea: TRect; ADraw: Boolean): Integer;
begin
  Canvas.Font.Assign(FPainter.FFonts.Mono);
  Canvas.Font.Color := C(FPainter.FColors.Text);
  Result := FPainter.S(16);
  if ADraw then
  begin
    FPainter.Text(ExtractFilePath(Preview.FileName), Rect(AArea.Left, AArea.Top, AArea.Right, Min(AArea.Bottom,
      AArea.Top + Result)), DT_SINGLELINE or DT_NOPREFIX or DT_PATH_ELLIPSIS);
  end;
end;

function TAtlasUnitSearchPreviewPainter.WrappedBody(const AText: string; const AArea: TRect; ADraw: Boolean;
  AMaxHeight: Integer; AFormat: Cardinal): Integer;
var
  mLine: TRect;
begin
  // Höhe des umbrochenen Texts messen (höchstens AMaxHeight), dann zeichnen.
  mLine := Rect(AArea.Left, AArea.Top, AArea.Right, AArea.Top);
  DrawText(Canvas.Handle, PChar(AText), -1, mLine, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX or AFormat);
  Result := Min(mLine.Height, AMaxHeight);
  if ADraw then
  begin
    FPainter.Text(AText, Rect(AArea.Left, AArea.Top, AArea.Right, Min(AArea.Bottom, AArea.Top + Result)),
      DT_WORDBREAK or DT_NOPREFIX or DT_END_ELLIPSIS or AFormat);
  end;
end;

procedure TAtlasUnitSearchPreviewPainter.DrawType(const AType: TAtlasUnitType; const AArea: TRect; ATop: Integer);
var
  mLine: TRect;
  mBadge: TAtlasBadgeColors;
begin
  // Symbol: Anfangsbuchstabe der Art im Kästchen.
  mBadge := FPainter.FColors.Badges[TAtlasBadgeKind.Type_];
  mLine := Rect(AArea.Left, ATop + FPainter.S(1), AArea.Left + FPainter.S(16), ATop + FPainter.S(15));
  Canvas.Brush.Style := bsSolid;
  FPainter.SetColors(mBadge.Background, mBadge.Background, mBadge.Text);
  Canvas.RoundRect(mLine.Left, mLine.Top, mLine.Right, mLine.Bottom, FPainter.S(4), FPainter.S(4));
  Canvas.Brush.Style := bsClear;
  FPainter.Text(UpperCase(Copy(AType.Kind, 1, 1)), mLine, cCentered);
  Canvas.Font.Color := C(FPainter.FColors.Text);
  FPainter.Text(AType.Name + '   ' + AType.Kind, Rect(AArea.Left + FPainter.S(22), ATop, AArea.Right,
    ATop + FPainter.S(16)), cLineEllipsis);
end;

function TAtlasUnitSearchPreviewPainter.TypesBody(const AArea: TRect; ADraw: Boolean): Integer;
var
  mTop, mCount, mRest, mStep: Integer;
begin
  Canvas.Font.Assign(FPainter.FFonts.Small);
  mStep := FPainter.S(17);
  mRest := Preview.TypeCount - Length(Preview.Types);
  Result := Length(Preview.Types) * mStep;
  if mRest > 0 then
  begin
    Inc(Result, mStep);
  end;
  if not ADraw then
  begin
    Exit;
  end;
  mTop := AArea.Top;
  mCount := 0;
  // Platz für die Zeile „+ n weitere“ lassen, wenn danach noch Typen kommen.
  while (mCount <= High(Preview.Types)) and (mTop + mStep <= AArea.Bottom) and
    ((mCount = High(Preview.Types)) or (mTop + 2 * mStep <= AArea.Bottom)) do
  begin
    DrawType(Preview.Types[mCount], AArea, mTop);
    Inc(mTop, mStep);
    Inc(mCount);
  end;
  mRest := Preview.TypeCount - mCount;
  if (mRest > 0) and (mTop + FPainter.S(16) <= AArea.Bottom) then
  begin
    Canvas.Font.Color := C(FPainter.FColors.Muted);
    FPainter.Text(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchPreviewMore, [mRest]), Rect(AArea.Left +
      FPainter.S(22), mTop, AArea.Right, mTop + FPainter.S(16)), cLine);
    Inc(mTop, mStep);
  end;
  Result := mTop - AArea.Top;
end;

end.
