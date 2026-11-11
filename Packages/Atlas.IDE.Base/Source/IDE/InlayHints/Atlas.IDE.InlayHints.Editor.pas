unit Atlas.IDE.InlayHints.Editor;

// Inlay-Hints im Editor (#401, ARG-040): Parameternamen vor Literal-Argumenten,
// standardmäßig aus (Einstellung „Inlay-Hints“).
// - Abruf: Ein Zeitgeber prüft den oberen Editor. 300 ms nach der letzten
//   Änderung gilt der neue Text; dann holt er textDocument/inlayHint nur für
//   die sichtbaren Zeilen (mit Rand), die im Zwischenspeicher noch fehlen
//   (TAtlasInlayHintStore, je Datei und Textstand). Startet keinen Server.
//   Der Abruf läuft im Hintergrund (TAtlasBackgroundRequest), höchstens einer
//   zugleich; nach einem Fehler wartet er einige Sekunden. Früher wartete der
//   Hauptthread bis zu 800 ms: Bei beschäftigtem Server hing die IDE alle
//   paar Sekunden, und keine Antwort kam je an (2.0-stable).
// - Zeichnen: nach dem Zeichnen jeder Zeile (plsEndPaint) kleine Marken mit
//   den Namen hinter dem Zeilenende, in der Reihenfolge der Argumente. Der
//   Editor kennt keinen eingeschobenen Text; so bleiben Datei, Undo und
//   Cursor unberührt. Gezeichnet wird nur, wenn die Zeile im Editor der im
//   Speicher entspricht.
// - Zeichnen ohne Objektkopien: reines GDI zwischen SaveDC und
//   RestoreDC wie im Problem-Zeichner; Schrift, Stift und Pinsel sind Felder
//   und werden nur bei geänderter Editorschrift bzw. geändertem Hintergrund
//   neu gebaut. Die Einstellung wird erst geprüft, wenn die Zeile Hinweise hat.
// - Pufferstand: über TAtlasEditorSnapshots, gelesen nur nach einer
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
//   der Implementierung „braucht kein Self“ in einer Pille; ausblendbar je
//   Codezeile. Ein Linksklick auf die Pille setzt den Cursor ans Ende des
//   Kopfs und öffnet dort die Code-Aktionen wie Strg+. (die Umwandlungen).
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
  Atlas.Core.Lsp.BackgroundRequest,
  Atlas.Core.InlayHints.Store,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Diagnostics.Deadline;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasInlayHintsSessionFunc = reference to function: TLspSession;

  /// <summary>Gezeichnete Blockende-Beschriftung (#620) oder Marke „braucht kein Self“ (#686) mit Ziel des
  /// Klicks.</summary>
  TAtlasInlayPillHit = record
    FileName: string;
    Line: Integer;
    TopRow: Integer;
    Rect: TRect;
    TargetLine: Integer;
    TargetCharacter: Integer;
    /// <summary>Marke einer Methode ohne Self: nach dem Sprung die Code-Aktionen öffnen.</summary>
    Actions: Boolean;
  end;

  /// <summary>Klickbare Marken: Ein Linksklick auf eine Blockende-Beschriftung springt zum Blockanfang, einer auf die
  /// Marke „braucht kein Self“ ans Ende des Methodenkopfs und öffnet dort die Code-Aktionen.</summary>
  TAtlasInlayHintClicks = class
  private const
    /// <summary>Mehr gemerkte Flächen: alle vergessen (der Editor zeichnet sie ohnehin neu).</summary>
    cMaxHits = 500;
  private
    FStore: TAtlasInlayHintStore;
    FMethodActions: TProc;
    FHits: TArray<TAtlasInlayPillHit>;
    /// <summary>Ist die Art von AHit noch an, und steht eine Marke „braucht kein Self“ noch im Speicher?</summary>
    function StillShown(const AHit: TAtlasInlayPillHit): Boolean;
    /// <summary>Gemerkte Fläche unter X, Y in der Ansicht AView, die noch gilt.</summary>
    function HitAt(const AView: IOTAEditView; AX, AY: Integer; out AHit: TAtlasInlayPillHit): Boolean;
    /// <summary>Sprung zum Ziel von AHit, bei einer Marke „braucht kein Self“ danach die Code-Aktionen.</summary>
    procedure Open(const AHit: TAtlasInlayPillHit);
  public
    /// <summary>AStore gehört dem Aufrufer. AMethodActions: Code-Aktionen an der Schreibmarke öffnen (wie Strg+.);
    /// nil = nur der Sprung.</summary>
    constructor Create(AStore: TAtlasInlayHintStore; const AMethodActions: TProc);
    procedure Remember(const AHit: TAtlasInlayPillHit);
    procedure Clear;
    /// <summary>Mausklick im Editor an X, Y; nur ein Linksklick ohne Umschalt, Strg und Alt zählt.</summary>
    procedure Click(AButton: TMouseButton; AShift: TShiftState; AX, AY: Integer);
  end;

  TAtlasEditorInlayHints = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
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
      /// <summary>Stelle der Marke „braucht kein Self“ (Ende des Kopfs, 0-basiert).</summary>
      MethodCharacter: Integer;
    end;
  private const
    cQuietMs = 300;
    cTimeoutMs = 5000;
    cRetryMs = 5000;
  private
    FSession: TAtlasInlayHintsSessionFunc;
    FStore: TAtlasInlayHintStore;
    FRequest: TAtlasBackgroundRequest;
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FFileName: string;
    FText: string;
    FVersion: Cardinal;
    FChangedAt: UInt64;
    FRetryAt: TAtlasDeadline;
    FShowing: Boolean;
    FHintFont: TFont;
    FFontKey: string;
    FBack: COLORREF;
    FBackKnown: Boolean;
    FTextColor: COLORREF;
    FPen: HGDIOBJ;
    FBrush: HGDIOBJ;
    FMinLines: Integer;
    FClicks: TAtlasInlayHintClicks;
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
    /// <summary>Antwort des Abrufs im Hauptthread übernehmen; AOk = False: später neu versuchen.</summary>
    procedure Fetched(AOk: Boolean; const AFileName, AText: string; AFrom, ATill: Integer;
      const AHints: TArray<TAtlasInlayHint>);
    /// <summary>Stift, Pinsel, Schrift und Textfarbe der Pillen in ADC wählen.</summary>
    procedure SelectHintStyle(ADC: HDC);
    procedure DrawHints(const ARect: TRect; const AContext: INTACodeEditorPaintContext; const AHints: TLineHints);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    class procedure Invalidate; static;
  public
    /// <summary>AMethodActions: Code-Aktionen an der Schreibmarke öffnen (wie Strg+.), für den Klick auf die Marke
    /// „braucht kein Self“; nil = nur der Sprung.</summary>
    constructor Create(const ASession: TAtlasInlayHintsSessionFunc; const AMethodActions: TProc);
    destructor Destroy; override;
  end;

implementation

uses
  System.Math,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
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
  mName: string;
  mSize: TSize;
  mPill: TRect;
begin
  Result := TRect.Empty;
  for mName in ALabels do
  begin
    GetTextExtentPoint32W(ADC, PChar(mName), Length(mName), mSize);
    mPill := TRect.Create(AX, ATop, AX + mSize.cx + 8, ATop + AHeight + 2);
    RoundRect(ADC, mPill.Left, mPill.Top, mPill.Right, mPill.Bottom, 6, 6);
    TextOutW(ADC, mPill.Left + 4, mPill.Top + 1, PChar(mName), Length(mName));
    AX := mPill.Right + 4;
    if Result.IsEmpty then
    begin
      Result := mPill;
    end
    else
    begin
      Result.Union(mPill);
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

constructor TAtlasEditorInlayHints.Create(const ASession: TAtlasInlayHintsSessionFunc; const AMethodActions: TProc);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FStore := TAtlasInlayHintStore.Create;
  FClicks := TAtlasInlayHintClicks.Create(FStore, AMethodActions);
  FRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.InlayHints);
  FIndex := -1;
  FHintFont := TFont.Create;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 150;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasEditorInlayHints.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  FTimer.Free;
  // Laufenden Abruf abwarten; seine Antwort verfällt.
  FRequest.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintLine := nil;
    FEvents.OnEditorMouseDown := nil;
  end;
  FEventsRef := nil;
  FreeColors;
  FHintFont.Free;
  FClicks.Free;
  FStore.Free;
  inherited Destroy;
end;

class procedure TAtlasEditorInlayHints.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

function IsSource(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk') or (mExtension = '.inc');
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
    FClicks.Clear;
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
    FChangedAt := TAtlasTicks.Now;
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
    // Ohne Fokus ändert sich der Puffer nur über Neuladen; das markiert den Stand ohnehin als veraltet.
    mView := nil;
    if Application.Active then
    begin
      mView := TopSourceView;
    end;
    // Erst nach der Tipp-Pause; bis dahin bleiben die Marken unveränderter Zeilen stehen.
    if (mView <> nil) and not SnapshotChanged(mView) and (TAtlasTicks.Since(FChangedAt) >= cQuietMs) and
      FRetryAt.Reached then
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
  mSession: TLspSession;
  mFirst, mLast, mFrom, mTill, mPercent, mMinLines: Integer;
  mFileName, mText: string;
  mHints: TArray<TAtlasInlayHint>;
begin
  FStore.SetText(FFileName, FText);
  mFirst := AView.TopRow - 1;
  mLast := mFirst + AView.ViewSize.cy;
  if FRequest.Busy or not FStore.Missing(FFileName, mFirst, mLast, mFrom, mTill) then
  begin
    Exit;
  end;
  mSession := FSession();
  if mSession = nil then
  begin
    Exit;
  end;
  // Server indexiert: Er antwortet erst danach (#874). Später noch einmal.
  if mSession.Indexing(mPercent) then
  begin
    FRetryAt := TAtlasDeadline.After(cRetryMs);
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mSession.Sync(FFileName, FText);
  mFileName := FFileName;
  mText := FText;
  mMinLines := FMinLines;
  mHints := nil;
  // Server beschäftigt oder weg (AOk = False): später noch einmal, ohne den Editor zu bremsen.
  FRequest.Start(
    procedure
    begin
      mHints := mSession.InlayHints(mFileName, mFrom, mTill, mMinLines, cTimeoutMs);
    end,
    procedure(AOk: Boolean; const AError: string)
    begin
      Fetched(AOk, mFileName, mText, mFrom, mTill, mHints);
    end);
end;

procedure TAtlasEditorInlayHints.Fetched(AOk: Boolean; const AFileName, AText: string; AFrom, ATill: Integer;
  const AHints: TArray<TAtlasInlayHint>);
begin
  if not AOk then
  begin
    FRetryAt := TAtlasDeadline.After(cRetryMs);
    Exit;
  end;
  // Der Speicher gilt je Datei und Textstand; eine Antwort für einen älteren Stand zeichnet nichts Falsches.
  FStore.Put(AFileName, AText, AFrom, ATill, AHints);
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
  mColors: TAtlasHintColors;
begin
  if FBackKnown and (FBack = ABack) then
  begin
    Exit;
  end;
  FreeColors;
  mColors := TAtlasColors.InlayHint(TAtlasColor(ABack));
  FTextColor := COLORREF(ColorToRGB(TColor(mColors.Text)));
  FPen := CreatePen(PS_SOLID, 1, ColorToRGB(TColor(mColors.Pen)));
  FBrush := CreateSolidBrush(ColorToRGB(TColor(mColors.Fill)));
  FBack := ABack;
  FBackKnown := True;
end;

procedure TAtlasEditorInlayHints.EnsureHintFont(const AEditorFont: TFont);
var
  mKey: string;
begin
  mKey := AEditorFont.Name + '|' + IntToStr(AEditorFont.Size) + '|' + IntToStr(AEditorFont.PixelsPerInch);
  if mKey = FFontKey then
  begin
    Exit;
  end;
  FHintFont.Assign(AEditorFont);
  FHintFont.Size := Max(6, AEditorFont.Size - 1);
  FHintFont.Style := [];
  FFontKey := mKey;
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
  // Methode ohne Self (#686): „braucht kein Self“ in der Sprache der IDE hinter dem Kopf.
  if AStore.MethodOnLine(AFileName, ALine, AHints.MethodCharacter) then
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

/// <summary>Klickfläche ARect in Zeile ALine mit Ziel ATargetLine/ATargetCharacter (0-basiert).</summary>
function PillHit(const AContext: INTACodeEditorPaintContext; ALine: Integer; const ARect: TRect;
  ATargetLine, ATargetCharacter: Integer; AActions: Boolean): TAtlasInlayPillHit;
begin
  Result.FileName := AContext.FileName;
  Result.Line := ALine;
  Result.TopRow := AContext.EditView.TopRow;
  Result.Rect := ARect;
  Result.TargetLine := ATargetLine;
  Result.TargetCharacter := ATargetCharacter;
  Result.Actions := AActions;
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
      // Marke „braucht kein Self“ (#686): Ein Klick öffnet die Umwandlungen am Ende des Kopfs.
      if mRow.Element = TAtlasDrawnElement.InlayMethodHints then
      begin
        FClicks.Remember(PillHit(AContext, AHints.Line, mPill, AHints.Line, AHints.MethodCharacter, True));
      end;
    end;
    if AHints.ShowEnd then
    begin
      mPill := DrawEndLabel(mDC, AHints.EndLabel, mX, mTop, mHeight);
      TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.BlockEndLabels, AContext.FileName,
        AHints.Line, AHints.EndText), mPill, AContext.EditView.TopRow, ARect.Height);
      if AHints.EndHint.HasBlock then
      begin
        FClicks.Remember(PillHit(AContext, AHints.Line, mPill, AHints.EndHint.BlockLine, AHints.EndHint.BlockCharacter,
          False));
      end;
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
    // Einstellungen erst, wenn die Zeile Marken hat: die meisten Zeilen haben keine.
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

procedure TAtlasEditorInlayHints.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  try
    FClicks.Click(Button, Shift, X, Y);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.InlayHints, E);
  end;
end;

{ TAtlasInlayHintClicks }

constructor TAtlasInlayHintClicks.Create(AStore: TAtlasInlayHintStore; const AMethodActions: TProc);
begin
  inherited Create;
  FStore := AStore;
  FMethodActions := AMethodActions;
end;

procedure TAtlasInlayHintClicks.Clear;
begin
  FHits := nil;
end;

procedure TAtlasInlayHintClicks.Remember(const AHit: TAtlasInlayPillHit);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FHits) do
  begin
    if (FHits[mIndex].Line = AHit.Line) and (FHits[mIndex].Actions = AHit.Actions) and
      SameText(FHits[mIndex].FileName, AHit.FileName) then
    begin
      FHits[mIndex] := AHit;
      Exit;
    end;
  end;
  if Length(FHits) >= cMaxHits then
  begin
    FHits := nil;
  end;
  FHits := FHits + [AHit];
end;

function TAtlasInlayHintClicks.StillShown(const AHit: TAtlasInlayPillHit): Boolean;
var
  mCharacter: Integer;
begin
  if not AHit.Actions then
  begin
    Exit(TAtlasIdeSettings.BlockEndLabelsOn);
  end;
  // Nach einer Änderung bleibt die alte Fläche gemerkt, bis die Zeile neu gezeichnet wird.
  Result := TAtlasIdeSettings.InlayMethodHintsOn and FStore.MethodOnLine(AHit.FileName, AHit.Line, mCharacter) and
    (mCharacter = AHit.TargetCharacter);
end;

function TAtlasInlayHintClicks.HitAt(const AView: IOTAEditView; AX, AY: Integer; out AHit: TAtlasInlayPillHit): Boolean;
var
  mHit: TAtlasInlayPillHit;
begin
  for mHit in FHits do
  begin
    // Nur, wenn die Marke noch dort steht (gleiche Datei, nicht gescrollt) und ihre Art noch an ist.
    if SameText(mHit.FileName, AView.Buffer.FileName) and (mHit.TopRow = AView.TopRow) and
      PtInRect(mHit.Rect, Point(AX, AY)) and StillShown(mHit) then
    begin
      AHit := mHit;
      Exit(True);
    end;
  end;
  AHit := Default(TAtlasInlayPillHit);
  Result := False;
end;

procedure TAtlasInlayHintClicks.Open(const AHit: TAtlasInlayPillHit);
var
  mHit: TAtlasInlayPillHit;
  mActions: TProc;
begin
  mHit := AHit;
  mActions := nil;
  if AHit.Actions then
  begin
    mActions := FMethodActions;
  end;
  // Erst nach dem Mausereignis: der Editor setzt den Cursor sonst an die Klickstelle.
  TAtlasMainThread.ForceQueue(TAtlasFeature.InlayHints,
    procedure
    begin
      TAtlasIdeNavigation.GoToLocation(mHit.FileName, mHit.TargetLine, mHit.TargetCharacter);
      if Assigned(mActions) then
      begin
        mActions();
      end;
    end);
end;

procedure TAtlasInlayHintClicks.Click(AButton: TMouseButton; AShift: TShiftState; AX, AY: Integer);
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mHit: TAtlasInlayPillHit;
begin
  if (AButton <> mbLeft) or (AShift * [ssShift, ssCtrl, ssAlt] <> []) or (Length(FHits) = 0) then
  begin
    Exit;
  end;
  mView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
  end;
  if (mView <> nil) and (mView.Buffer <> nil) and HitAt(mView, AX, AY, mHit) then
  begin
    Open(mHit);
  end;
end;

end.
