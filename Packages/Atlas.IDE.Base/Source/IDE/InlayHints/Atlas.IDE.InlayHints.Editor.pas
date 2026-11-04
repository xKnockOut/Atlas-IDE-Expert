unit Atlas.IDE.InlayHints.Editor;

// Inlay-Hints im Editor (#401, ARG-040): Parameternamen vor Literal-Argumenten,
// standardmäßig aus (Einstellung „Inlay-Hints“).
// - Abruf: Ein Zeitgeber prüft den oberen Editor. 300 ms nach der letzten
//   Änderung gilt der neue Text; dann holt er textDocument/inlayHint nur für
//   die sichtbaren Zeilen (mit Rand), die im Zwischenspeicher noch fehlen
//   (TAtlasInlayHintStore, je Datei und Textstand). Startet keinen Server.
//   Der Abruf läuft im Hauptthread mit kurzem Zeitlimit; nach einem Fehler
//   wartet er einige Sekunden.
// - Zeichnen: nach dem Zeichnen jeder Zeile (plsEndPaint) kleine Marken mit
//   den Namen hinter dem Zeilenende, in der Reihenfolge der Argumente. Der
//   Editor kennt keinen eingeschobenen Text; so bleiben Datei, Undo und
//   Cursor unberührt. Gezeichnet wird nur, wenn die Zeile im Editor der im
//   Speicher entspricht.
// - Zeichnen ohne Objektkopien (P-10): reines GDI zwischen SaveDC und
//   RestoreDC wie im Problem-Zeichner; Schrift, Stift und Pinsel sind Felder
//   und werden nur bei geänderter Editorschrift bzw. geändertem Hintergrund
//   neu gebaut. Die Einstellung wird erst geprüft, wenn die Zeile Hinweise hat.
// - Pufferstand (P-04): über TAtlasEditorSnapshots, gelesen nur nach einer
//   Änderung; bei inaktiver IDE wird der Puffer nicht geprüft.
// - Blockende-Beschriftungen (#620, Einstellung BlockEndLabels): Die
//   Endmarkierungen des Servers (inlayHints.endMarkers, „// if …“) stehen
//   hinter dem end langer Blöcke als gedämpfter Text wie ein Kommentar, nicht
//   als Marke. Abgerufen wird, solange Inlay-Hints oder Beschriftungen an
//   sind; jede Art zeichnet nur mit ihrer Einstellung. Die Mindestlänge
//   (BlockEndLabelsMinLines, editor.blockEndLabels.minLines) geht mit jeder
//   Anfrage an den Server; ändert sie sich, wird neu geholt. Ein Linksklick
//   auf die Beschriftung springt zum Blockanfang.
// - Ausblenden am Element (#628): Inlay-Hints je Codezeile, Beschriftungen je
//   Text der Beschriftung (oder je Datei) über .atlas; jede gezeichnete Marke
//   meldet sich bei TAtlasIdeElements.
// - Typmarken (#453, Einstellung InlayTypeHints): der abgeleitete Typ von
//   var X := …, const X = … und for var X in … als „: TStringList“ in derselben
//   Pille wie die Parameternamen, hinter ihnen; ausblendbar je Codezeile.
// - Include-Symbole (#860, Einstellung InlayDefineHints): hinter {$I datei.inc}
//   „definiert COMPLIB_VCL“ in einer Pille; ausblendbar je Codezeile.
// - Steuerzeichen (#862, Einstellung InlayCharHints): hinter ^C in einer
//   Konstanten der Code „#3“ in einer Pille; ausblendbar je Codezeile.
// - Methoden ohne Self (#686, Einstellung InlayMethodHints): hinter dem Kopf
//   der Implementierung „ohne Self“ in einer Pille; ausblendbar je Codezeile.
// - Platz hinter dem Zeilenende (#509): teilt sich der Zeichner über
//   TAtlasLineTail mit dem Fehlertext am Zeilenende.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.Session,
  Atlas.Core.InlayHints.Store,
  Atlas.Core.Editor.Elements;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasInlayHintsSessionFunc = reference to function: TLspSession;

  TAtlasEditorInlayHints = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
    /// <summary>Gezeichnete Blockende-Beschriftung mit Ziel des Klicks (#620).</summary>
    TEndHit = record
      FileName: string;
      Line: Integer;
      TopRow: Integer;
      Rect: TRect;
      BlockLine: Integer;
      BlockCharacter: Integer;
    end;
    /// <summary>Eine Pille je Art: das Element für .atlas und die Beschriftungen.</summary>
    TPillRow = record
      Element: TAtlasDrawnElement;
      Labels: TArray<string>;
    end;

    /// <summary>Marken einer Zeile: Pillen und die Blockende-Beschriftung.</summary>
    TLineHints = record
      Line: Integer;
      Stored: string;
      TabWidth: Integer;
      Rows: TArray<TPillRow>;
      ShowEnd: Boolean;
      EndText: string;
      EndLabel: string;
      EndHint: TAtlasInlayHint;
    end;
  private const
    QuietMs = 300;
    TimeoutMs = 800;
    RetryMs = 5000;
    /// <summary>Mehr gemerkte Beschriftungen: alle vergessen (der Editor zeichnet sie ohnehin neu).</summary>
    MaxEndHits = 500;
  private
    FSession: TAtlasInlayHintsSessionFunc;
    FStore: TAtlasInlayHintStore;
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FFileName: string;
    FText: string;
    FVersion: Cardinal;
    FChangedAt: Cardinal;
    FRetryAt: Cardinal;
    FShowing: Boolean;
    FHintFont: TFont;
    FFontKey: string;
    FBack: COLORREF;
    FBackKnown: Boolean;
    FTextColor: COLORREF;
    FPen: HGDIOBJ;
    FBrush: HGDIOBJ;
    FMinLines: Integer;
    FEndHits: TArray<TEndHit>;
    /// <summary>Baut FHintFont nur neu, wenn sich Name, Größe oder PPI der Editorschrift geändert haben.</summary>
    procedure EnsureHintFont(const AEditorFont: TFont);
    /// <summary>Stift, Pinsel und Textfarbe nur neu, wenn sich der Hintergrund geändert hat.</summary>
    procedure EnsureColors(ABack: COLORREF);
    procedure FreeColors;
    procedure Tick(Sender: TObject);
    /// <summary>Alle Marken weg, wenn alle Arten aus sind.</summary>
    procedure ClearShown;
    /// <summary>Andere Mindestlänge der Beschriftungen (#620): alles neu holen.</summary>
    procedure SyncMinLines;
    /// <summary>Neuer Pufferstand in AView: merken und True (erst nach der Tipp-Pause holen).</summary>
    function SnapshotChanged(const AView: IOTAEditView): Boolean;
    procedure Fetch(const AView: IOTAEditView);
    /// <summary>Stift, Pinsel, Schrift und Textfarbe der Pillen in ADC wählen.</summary>
    procedure SelectHintStyle(ADC: HDC);
    procedure DrawHints(const ARect: TRect; const AContext: INTACodeEditorPaintContext; const AHints: TLineHints);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure RememberEnd(const AFileName: string; ALine, ATopRow: Integer; const ARect: TRect;
      const AHint: TAtlasInlayHint);
    class procedure Invalidate; static;
  public
    constructor Create(const ASession: TAtlasInlayHintsSessionFunc);
    destructor Destroy; override;
  end;

implementation

uses
  System.Math,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.Navigation,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Editor.LineTail,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.EditorRefresh;

/// <summary>Zeichnet ALabels als Pillen ab AX (Höhe AHeight ab ATop) und rückt AX hinter die letzte; liefert die
/// Fläche aller Pillen, leer ohne.</summary>
function DrawPills(ADC: HDC; const ALabels: TArray<string>; ATop, AHeight: Integer; var AX: Integer): TRect;
var
  Name: string;
  Size: TSize;
  Pill: TRect;
begin
  Result := TRect.Empty;
  for Name in ALabels do
  begin
    GetTextExtentPoint32W(ADC, PChar(Name), Length(Name), Size);
    Pill := TRect.Create(AX, ATop, AX + Size.cx + 8, ATop + AHeight + 2);
    RoundRect(ADC, Pill.Left, Pill.Top, Pill.Right, Pill.Bottom, 6, 6);
    TextOutW(ADC, Pill.Left + 4, Pill.Top + 1, PChar(Name), Length(Name));
    AX := Pill.Right + 4;
    if Result.IsEmpty then
    begin
      Result := Pill;
    end
    else
    begin
      Result.Union(Pill);
    end;
  end;
end;

{ TAtlasEditorInlayHints.TEvents }

function TAtlasEditorInlayHints.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents];
end;

function TAtlasEditorInlayHints.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasEditorInlayHints }

constructor TAtlasEditorInlayHints.Create(const ASession: TAtlasInlayHintsSessionFunc);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FStore := TAtlasInlayHintStore.Create;
  FIndex := -1;
  FHintFont := TFont.Create;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 150;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasEditorInlayHints.Destroy;
var
  Services: INTACodeEditorServices;
begin
  FTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    Services.RemoveEditorEventsNotifier(FIndex);
  end;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintLine := nil;
    FEvents.OnEditorMouseDown := nil;
  end;
  FEventsRef := nil;
  FreeColors;
  FHintFont.Free;
  FStore.Free;
  inherited Destroy;
end;

class procedure TAtlasEditorInlayHints.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
  end;
end;

function IsSource(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.pas') or (Extension = '.dpr') or (Extension = '.dpk') or (Extension = '.inc');
end;

/// <summary>Ist eine der Arten eingeschaltet (Namen, Typen, Include-Symbole, Steuerzeichen, ohne Self,
/// Blockende)?</summary>
function AnyInlayOn: Boolean;
begin
  Result := TAtlasIdeSettings.InlayHintsOn or TAtlasIdeSettings.InlayTypeHintsOn or
    TAtlasIdeSettings.InlayDefineHintsOn;
  Result := Result or TAtlasIdeSettings.InlayCharHintsOn or TAtlasIdeSettings.InlayMethodHintsOn or
    TAtlasIdeSettings.BlockEndLabelsOn;
end;

/// <summary>Vorderste Ansicht, wenn sie eine Pascal-Datei zeigt; sonst nil.</summary>
function TopSourceView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
  if (Result <> nil) and ((Result.Buffer = nil) or not IsSource(Result.Buffer.FileName)) then
  begin
    Result := nil;
  end;
end;

procedure TAtlasEditorInlayHints.ClearShown;
begin
  if not FShowing then
  begin
    Exit;
  end;
  FStore.Clear;
  FFileName := '';
  FText := '';
  FVersion := 0;
  FShowing := False;
  Invalidate;
end;

procedure TAtlasEditorInlayHints.SyncMinLines;
begin
  if FMinLines <> TAtlasIdeSettings.Current.BlockEndLabelsMinLines then
  begin
    FMinLines := TAtlasIdeSettings.Current.BlockEndLabelsMinLines;
    FStore.Clear;
    FEndHits := nil;
  end;
end;

function TAtlasEditorInlayHints.SnapshotChanged(const AView: IOTAEditView): Boolean;
var
  mSnapshot: TAtlasEditorSnapshot;
begin
  mSnapshot := TAtlasEditorSnapshots.Get(AView);
  Result := not SameText(FFileName, mSnapshot.FileName) or (FVersion <> mSnapshot.Version);
  if Result then
  begin
    FFileName := mSnapshot.FileName;
    FText := mSnapshot.Text;
    FVersion := mSnapshot.Version;
    FChangedAt := GetTickCount;
  end;
end;

procedure TAtlasEditorInlayHints.Tick(Sender: TObject);
var
  mView: IOTAEditView;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.InlayHints) then
  begin
    Exit;
  end;
  try
    if not AnyInlayOn then
    begin
      ClearShown;
      Exit;
    end;
    SyncMinLines;
    // Ohne Fokus ändert sich der Puffer nur über Neuladen; das markiert den Stand ohnehin als veraltet (P-04).
    mView := nil;
    if Application.Active then
    begin
      mView := TopSourceView;
    end;
    // Erst nach der Tipp-Pause; bis dahin bleiben die Marken unveränderter Zeilen stehen.
    if (mView <> nil) and not SnapshotChanged(mView) and (GetTickCount - FChangedAt >= QuietMs) and
      (GetTickCount >= FRetryAt) then
    begin
      Fetch(mView);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.InlayHints, E);
  end;
end;

procedure TAtlasEditorInlayHints.Fetch(const AView: IOTAEditView);
var
  Session: TLspSession;
  First, Last, From, Till: Integer;
  Hints: TArray<TAtlasInlayHint>;
  Percent: Integer;
begin
  FStore.SetText(FFileName, FText);
  First := AView.TopRow - 1;
  Last := First + AView.ViewSize.cy;
  if not FStore.Missing(FFileName, First, Last, From, Till) then
  begin
    Exit;
  end;
  Session := FSession();
  if Session = nil then
  begin
    Exit;
  end;
  // Server indexiert: Er antwortet erst danach, der Hauptthread würde warten (#874). Später noch einmal.
  if Session.Indexing(Percent) then
  begin
    FRetryAt := GetTickCount + RetryMs;
    Exit;
  end;
  try
    Session.Sync(FFileName, FText);
    Hints := Session.InlayHints(FFileName, From, Till, FMinLines, TimeoutMs);
  except
    on E: ELspClientError do
    begin
      // Server beschäftigt oder weg: später noch einmal, ohne den Editor zu bremsen.
      FRetryAt := GetTickCount + RetryMs;
      Exit;
    end;
  end;
  FStore.Put(FFileName, FText, From, Till, Hints);
  FShowing := True;
  Invalidate;
end;

/// <summary>Editorspalte (1-basiert) zum Zeichenindex (0-basiert) in ALine; Tabs aufgelöst.</summary>
function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(Copy(ALine, 1, Max(0, ACharacter)), ATabWidth)) + 1;
end;

procedure TAtlasEditorInlayHints.FreeColors;
begin
  if FPen <> 0 then
  begin
    DeleteObject(FPen);
  end;
  if FBrush <> 0 then
  begin
    DeleteObject(FBrush);
  end;
  FPen := 0;
  FBrush := 0;
  FBackKnown := False;
end;

procedure TAtlasEditorInlayHints.EnsureColors(ABack: COLORREF);
var
  Colors: TAtlasHintColors;
begin
  if FBackKnown and (FBack = ABack) then
  begin
    Exit;
  end;
  FreeColors;
  Colors := TAtlasColors.InlayHint(TAtlasColor(ABack));
  FTextColor := COLORREF(ColorToRGB(TColor(Colors.Text)));
  FPen := CreatePen(PS_SOLID, 1, ColorToRGB(TColor(Colors.Pen)));
  FBrush := CreateSolidBrush(ColorToRGB(TColor(Colors.Fill)));
  FBack := ABack;
  FBackKnown := True;
end;

procedure TAtlasEditorInlayHints.EnsureHintFont(const AEditorFont: TFont);
var
  Key: string;
begin
  Key := AEditorFont.Name + '|' + IntToStr(AEditorFont.Size) + '|' + IntToStr(AEditorFont.PixelsPerInch);
  if Key = FFontKey then
  begin
    Exit;
  end;
  FHintFont.Assign(AEditorFont);
  FHintFont.Size := Max(6, AEditorFont.Size - 1);
  FHintFont.Style := [];
  FFontKey := Key;
end;

type
  TPillRow = TAtlasEditorInlayHints.TPillRow;
  TLineHints = TAtlasEditorInlayHints.TLineHints;

procedure AddRow(var AHints: TLineHints; AElement: TAtlasDrawnElement; const ALabels: TArray<string>);
var
  mRow: TPillRow;
begin
  if Length(ALabels) = 0 then
  begin
    Exit;
  end;
  mRow.Element := AElement;
  mRow.Labels := ALabels;
  AHints.Rows := AHints.Rows + [mRow];
end;

/// <summary>Include-Symbole (#860): „definiert COMPLIB_VCL“ in der Sprache der IDE.</summary>
function DefineLabels(const ADefines: TArray<string>): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ADefines));
  for mIndex := 0 to High(ADefines) do
  begin
    Result[mIndex] := TAtlasStrings.Fmt(TAtlasTextId.InlayDefinesLabel, [ADefines[mIndex]]);
  end;
end;

/// <summary>Marken der Zeile aus dem Speicher, ohne Einstellungen; False, wenn es keine gibt.</summary>
function StoredHints(AStore: TAtlasInlayHintStore; const AFileName: string; ALine: Integer;
  out AHints: TLineHints): Boolean;
begin
  AHints := Default(TLineHints);
  AHints.Line := ALine;
  AddRow(AHints, TAtlasDrawnElement.InlayHints, AStore.OnLine(AFileName, ALine));
  // Typmarken (#453): „: TStringList“ in derselben Pille.
  AddRow(AHints, TAtlasDrawnElement.InlayTypeHints, AStore.TypesOnLine(AFileName, ALine));
  AddRow(AHints, TAtlasDrawnElement.InlayDefineHints, DefineLabels(AStore.DefinesOnLine(AFileName, ALine)));
  // Steuerzeichen (#862): „#3“ hinter ^C.
  AddRow(AHints, TAtlasDrawnElement.InlayCharHints, AStore.CharsOnLine(AFileName, ALine));
  // Methode ohne Self (#686): „ohne Self“ in der Sprache der IDE hinter dem Kopf.
  if AStore.MethodOnLine(AFileName, ALine) then
  begin
    AddRow(AHints, TAtlasDrawnElement.InlayMethodHints,
      TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.InlayMethodWithoutSelf)));
  end;
  AHints.ShowEnd := AStore.EndLabelOn(AFileName, ALine, AHints.EndText, AHints.EndLabel, AHints.EndHint);
  Result := (Length(AHints.Rows) > 0) or AHints.ShowEnd;
end;

function ElementOn(AElement: TAtlasDrawnElement): Boolean;
begin
  case AElement of
    TAtlasDrawnElement.InlayHints:
      Result := TAtlasIdeSettings.InlayHintsOn;
    TAtlasDrawnElement.InlayTypeHints:
      Result := TAtlasIdeSettings.InlayTypeHintsOn;
    TAtlasDrawnElement.InlayDefineHints:
      Result := TAtlasIdeSettings.InlayDefineHintsOn;
    TAtlasDrawnElement.InlayCharHints:
      Result := TAtlasIdeSettings.InlayCharHintsOn;
  else
    Result := TAtlasIdeSettings.InlayMethodHintsOn;
  end;
end;

/// <summary>Nur eingeschaltete Arten, die in .atlas nicht ausgeblendet sind (#628): Inlay-Hints an dieser
/// Codezeile, Beschriftung mit diesem Text. AWithHidden prüft zusätzlich .atlas. True, wenn etwas bleibt.</summary>
function KeepShown(var AHints: TLineHints; const AFileName: string; AWithHidden: Boolean): Boolean;
var
  mKept: TArray<TPillRow>;
  mRow: TPillRow;
begin
  mKept := nil;
  for mRow in AHints.Rows do
  begin
    if ElementOn(mRow.Element) and
      not (AWithHidden and TAtlasIdeElements.Hidden(mRow.Element, AFileName, AHints.Stored)) then
    begin
      mKept := mKept + [mRow];
    end;
  end;
  AHints.Rows := mKept;
  AHints.ShowEnd := AHints.ShowEnd and TAtlasIdeSettings.BlockEndLabelsOn and
    not (AWithHidden and TAtlasIdeElements.Hidden(TAtlasDrawnElement.BlockEndLabels, AFileName, AHints.EndText));
  Result := (Length(AHints.Rows) > 0) or AHints.ShowEnd;
end;

/// <summary>Nur, wenn die Zeile im Editor der im Speicher entspricht; setzt Stored und TabWidth.</summary>
function LineMatches(AStore: TAtlasInlayHintStore; const AContext: INTACodeEditorPaintContext;
  var AHints: TLineHints): Boolean;
var
  mLineState: INTACodeEditorLineState;
begin
  mLineState := AContext.LineState;
  Result := (mLineState <> nil) and (AContext.EditView <> nil) and (AContext.EditView.Buffer <> nil) and
    AStore.LineText(AContext.FileName, AHints.Line, AHints.Stored);
  if not Result then
  begin
    Exit;
  end;
  AHints.TabWidth := TAtlasEditorBuffer.TabWidth(AContext.EditView.Buffer);
  Result := TrimRight(TAtlasPairs.DisplayLine(mLineState.Text, AHints.TabWidth)) =
    TrimRight(TAtlasPairs.DisplayLine(AHints.Stored, AHints.TabWidth));
end;

/// <summary>Blockende-Beschriftung (#620): gedämpfter Text wie ein Kommentar, ohne Rahmen; liefert ihre Fläche.
/// </summary>
function DrawEndLabel(ADC: HDC; const ALabel: string; AX, ATop, AHeight: Integer): TRect;
var
  mSize: TSize;
begin
  GetTextExtentPoint32W(ADC, PChar(ALabel), Length(ALabel), mSize);
  Result := TRect.Create(AX, ATop, AX + mSize.cx + 4, ATop + AHeight + 2);
  TextOutW(ADC, Result.Left + 2, Result.Top + 1, PChar(ALabel), Length(ALabel));
end;

procedure TAtlasEditorInlayHints.SelectHintStyle(ADC: HDC);
begin
  SelectObject(ADC, FHintFont.Handle);
  SelectObject(ADC, FPen);
  SelectObject(ADC, FBrush);
  SetTextColor(ADC, FTextColor);
  SetBkMode(ADC, TRANSPARENT);
end;

procedure TAtlasEditorInlayHints.DrawHints(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  const AHints: TLineHints);
var
  mDC: HDC;
  mCell, mPill: TRect;
  mTailKey: string;
  mX, mTop, mHeight, mSaved: Integer;
  mSample: COLORREF;
  mSize: TSize;
  mRow: TPillRow;
begin
  mDC := AContext.Canvas.Handle;
  // Zwei Zeichen Abstand hinter dem letzten Zeichen der Zeile.
  mCell := AContext.EditorState.GetCharacterPosPx(ColumnOf(AHints.Stored, Length(TrimRight(AHints.Stored)),
    AHints.TabWidth) + 2, AContext.EditorLineNum);
  mTailKey := TAtlasLineTail.KeyOf(AContext.FileName, AContext.LogicalLineNum, AContext.EditorLineNum, ARect.Top);
  mX := TAtlasLineTail.Start(Self, mTailKey, mCell.Left);
  // Hintergrund des Editor-Farbschemas an der Stelle des Hinweises (hinter dem Zeilenende), nicht das
  // IDE-Thema: Sonst stand gedämpftes Grau auf fast gleichem Grau. Farben nur bei Abweichung neu.
  mSample := GetPixel(mDC, mX, ARect.Top + 1);
  if mSample = CLR_INVALID then
  begin
    mSample := COLORREF(ColorToRGB(AContext.Canvas.Brush.Color));
  end;
  EnsureColors(mSample);
  EnsureHintFont(AContext.Canvas.Font);
  // Reines GDI: Zustand der VCL-Canvas der IDE bleibt unberührt.
  mSaved := SaveDC(mDC);
  try
    SelectHintStyle(mDC);
    GetTextExtentPoint32W(mDC, 'Xg', 2, mSize);
    mHeight := mSize.cy;
    mTop := ARect.Top + Max(0, (ARect.Bottom - ARect.Top - mHeight - 2) div 2);
    for mRow in AHints.Rows do
    begin
      mPill := DrawPills(mDC, mRow.Labels, mTop, mHeight, mX);
      TAtlasIdeElements.Painted(TAtlasIdeElements.Target(mRow.Element, AContext.FileName, AHints.Line,
        AHints.Stored), mPill, AContext.EditView.TopRow, ARect.Height);
    end;
    if AHints.ShowEnd then
    begin
      mPill := DrawEndLabel(mDC, AHints.EndLabel, mX, mTop, mHeight);
      TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.BlockEndLabels, AContext.FileName,
        AHints.Line, AHints.EndText), mPill, AContext.EditView.TopRow, ARect.Height);
      RememberEnd(AContext.FileName, AHints.Line, AContext.EditView.TopRow, mPill, AHints.EndHint);
      mX := mPill.Right;
    end;
    TAtlasLineTail.Finish(Self, mTailKey, mX);
  finally
    RestoreDC(mDC, mSaved);
  end;
end;

procedure TAtlasEditorInlayHints.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mHints: TLineHints;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.InlayHints) or BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
  begin
    Exit;
  end;
  try
    // Einstellungen erst, wenn die Zeile Marken hat: die meisten Zeilen haben keine (P-10).
    if StoredHints(FStore, Context.FileName, Context.LogicalLineNum - 1, mHints) and
      KeepShown(mHints, Context.FileName, False) and LineMatches(FStore, Context, mHints) and
      KeepShown(mHints, Context.FileName, True) then
    begin
      DrawHints(Rect, Context, mHints);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.InlayHints, E);
  end;
end;

procedure TAtlasEditorInlayHints.RememberEnd(const AFileName: string; ALine, ATopRow: Integer; const ARect: TRect;
  const AHint: TAtlasInlayHint);
var
  Hit: TEndHit;
  Index: Integer;
begin
  if not AHint.HasBlock then
  begin
    Exit;
  end;
  Hit.FileName := AFileName;
  Hit.Line := ALine;
  Hit.TopRow := ATopRow;
  Hit.Rect := ARect;
  Hit.BlockLine := AHint.BlockLine;
  Hit.BlockCharacter := AHint.BlockCharacter;
  for Index := 0 to High(FEndHits) do
  begin
    if (FEndHits[Index].Line = ALine) and SameText(FEndHits[Index].FileName, AFileName) then
    begin
      FEndHits[Index] := Hit;
      Exit;
    end;
  end;
  if Length(FEndHits) >= MaxEndHits then
  begin
    FEndHits := nil;
  end;
  FEndHits := FEndHits + [Hit];
end;

procedure TAtlasEditorInlayHints.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Hit: TEndHit;
  FileName: string;
  Line, Character: Integer;
begin
  if (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or (Length(FEndHits) = 0) or
    not TAtlasIdeSettings.BlockEndLabelsOn then
  begin
    Exit;
  end;
  try
    View := nil;
    if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    begin
      View := Editors.TopView;
    end;
    if (View = nil) or (View.Buffer = nil) then
    begin
      Exit;
    end;
    for Hit in FEndHits do
    begin
      // Nur, wenn die Beschriftung noch dort steht: gleiche Datei, nicht gescrollt.
      if SameText(Hit.FileName, View.Buffer.FileName) and (Hit.TopRow = View.TopRow) and
        PtInRect(Hit.Rect, Point(X, Y)) then
      begin
        FileName := Hit.FileName;
        Line := Hit.BlockLine;
        Character := Hit.BlockCharacter;
        // Erst nach dem Mausereignis: der Editor setzt den Cursor sonst an die Klickstelle.
        TAtlasMainThread.ForceQueue(TAtlasFeature.InlayHints,
          procedure
          begin
            TAtlasIdeNavigation.GoToLocation(FileName, Line, Character);
          end);
        Exit;
      end;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.InlayHints, E);
  end;
end;

end.
