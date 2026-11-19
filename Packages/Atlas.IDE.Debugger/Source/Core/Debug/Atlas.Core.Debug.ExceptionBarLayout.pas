unit Atlas.Core.Debug.ExceptionBarLayout;

// Aufteilung der Exception-Leiste (#783, #865) ohne VCL: welche Zeilen sie
// hat, wie hoch sie ist und wo ihre Knöpfe und die anklickbare Ortszeile
// liegen. Gezeichnet und gemessen wird in der Oberfläche
// (Atlas.UI.Debug.ExceptionBar); sie reicht die Breiten der Texte herein.
//   - Drei Zeilen: Klasse und Meldung, Ortszeile, Knöpfe.
//   - Mit Erklärung einer Zugriffsverletzung dazwischen: Ergebniszeile, die
//     geprüften Glieder (höchstens cMaxExplanationLines, dann „… n weitere“)
//     und eine Zeile mit den Knöpfen der Erklärung. Während Atlas prüft, nur
//     die Ergebniszeile.
//   - „Nur an dieser Stelle ignorieren“ und „Test daraus anlegen“ gibt es nur,
//     wenn die Info sie anbietet; die Knöpfe der Erklärung nur mit Inhalt.
// Maße bei 96 dpi, skaliert mit der Auflösung (nie kleiner als 96 dpi).

interface

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Debug.ExceptionBanner;

const
  /// <summary>Knöpfe der letzten Zeile der Leiste in Reihenfolge.</summary>
  cDebugBarButtons: array[0..6] of TAtlasDebugBarAction = (TAtlasDebugBarAction.BreakHere,
    TAtlasDebugBarAction.Continue, TAtlasDebugBarAction.IgnoreClass, TAtlasDebugBarAction.IgnoreLocation,
    TAtlasDebugBarAction.MessageRule, TAtlasDebugBarAction.Copy, TAtlasDebugBarAction.CreateTest);
  /// <summary>Knöpfe der Erklärung in Reihenfolge.</summary>
  cDebugExplanationButtons: array[0..2] of TAtlasDebugBarAction = (TAtlasDebugBarAction.WhereAssigned,
    TAtlasDebugBarAction.Evaluate, TAtlasDebugBarAction.CopyExplanation);

type
  /// <summary>Breite der Beschriftung eines Knopfs in Pixeln.</summary>
  TAtlasDebugBarTextWidth = reference to function(AAction: TAtlasDebugBarAction): Integer;

  TAtlasDebugBarLayout = class
  public const
    /// <summary>Höchstens so viele geprüfte Glieder; der Rest als „… n weitere“.</summary>
    cMaxExplanationLines = 6;
    cBaseRow = 24;
    cBarPadding = 6;
    cGap = 6;
    /// <summary>Zeilen ohne Erklärung.</summary>
    cBaseRows = 3;
    /// <summary>Innenabstand der Beschriftung eines Knopfs (links und rechts zusammen).</summary>
    cButtonPadding = 16;
    /// <summary>Abstand eines Knopfs zum oberen und unteren Rand seiner Zeile.</summary>
    cButtonMargin = 2;
    /// <summary>Auflösung, für die die Maße gelten; kleinere Auflösungen zählen wie diese.</summary>
    cBasePPI = 96;
  private
    FInfo: TAtlasDebugBannerInfo;
    FExplanation: TAtlasDebugBannerExplanation;
    FPPI: Integer;
    FRects: array[TAtlasDebugBarAction] of TRect;
    function ExplanationRows: Integer;
    /// <summary>Knöpfe von links nach rechts in der Zeile ARow; nur die, die AShown zulässt.</summary>
    procedure PlaceButtons(const AActions: array of TAtlasDebugBarAction; ARow: Integer;
      const AShown: TFunc<TAtlasDebugBarAction, Boolean>; const AWidth: TAtlasDebugBarTextWidth);
  public
    constructor Create;
    /// <summary>Inhalt und Auflösung; danach Arrange.</summary>
    procedure SetContent(const AInfo: TAtlasDebugBannerInfo; const AExplanation: TAtlasDebugBannerExplanation);
    /// <summary>Knöpfe und Ortszeile anordnen. AClientWidth: Breite der Leiste; ADetailWidth: Breite des Texts der
    /// Ortszeile; AWidth: Breite einer Knopfbeschriftung.</summary>
    procedure Arrange(AClientWidth, ADetailWidth: Integer; const AWidth: TAtlasDebugBarTextWidth);
    /// <summary>AValue Pixel bei 96 dpi in der Auflösung der Leiste.</summary>
    function Scale(AValue: Integer): Integer;
    function RowHeight: Integer;
    /// <summary>Oberkante der Zeile ARow (ab 0).</summary>
    function RowTop(ARow: Integer): Integer;
    /// <summary>Zeilen der Leiste: drei, mit Erklärung mehr.</summary>
    function Rows: Integer;
    /// <summary>Geprüfte Glieder, die zu sehen sind.</summary>
    function ShownLines: Integer;
    /// <summary>Knopf bzw. Ortszeile unter dem Punkt; None = nichts.</summary>
    function ActionAt(AX, AY: Integer): TAtlasDebugBarAction;
    /// <summary>Fläche eines Knopfs; leer, wenn er fehlt.</summary>
    function ActionRect(AAction: TAtlasDebugBarAction): TRect;
    /// <summary>Rechter Rand des letzten Knopfs der letzten Zeile; 0 ohne Knöpfe.</summary>
    function LastButtonRight: Integer;
    /// <summary>Darf AAction ausgelöst werden (gibt es den Knopf bzw. einen Ort)?</summary>
    function CanTrigger(AAction: TAtlasDebugBarAction): Boolean;
    /// <summary>Höhe bei APPI mit ARows Zeilen.</summary>
    class function BarHeight(APPI, ARows: Integer): Integer; static;
    /// <summary>Gibt es den Knopf AAction der Erklärung AExplanation?</summary>
    class function ExplanationHas(const AExplanation: TAtlasDebugBannerExplanation;
      AAction: TAtlasDebugBarAction): Boolean; static;
    /// <summary>Steht der Knopf AAction der letzten Zeile bei AInfo da?</summary>
    class function BarButtonShown(const AInfo: TAtlasDebugBannerInfo; AAction: TAtlasDebugBarAction): Boolean;
      static;
    property Info: TAtlasDebugBannerInfo read FInfo;
    property Explanation: TAtlasDebugBannerExplanation read FExplanation;
    /// <summary>Auflösung der Leiste (dpi).</summary>
    property PPI: Integer read FPPI write FPPI;
  end;

implementation

uses
  System.Math;

/// <summary>AValue (nicht negativ) mal APPI / cBasePPI, gerundet wie MulDiv; nie kleiner als bei cBasePPI.</summary>
function ScaleFor(AValue, APPI: Integer): Integer;
var
  mPPI: Integer;
begin
  mPPI := Max(APPI, TAtlasDebugBarLayout.cBasePPI);
  Result := (AValue * mPPI + TAtlasDebugBarLayout.cBasePPI div 2) div TAtlasDebugBarLayout.cBasePPI;
end;

{ TAtlasDebugBarLayout }

constructor TAtlasDebugBarLayout.Create;
begin
  inherited Create;
  FPPI := cBasePPI;
end;

procedure TAtlasDebugBarLayout.SetContent(const AInfo: TAtlasDebugBannerInfo;
  const AExplanation: TAtlasDebugBannerExplanation);
begin
  FInfo := AInfo;
  FExplanation := AExplanation;
end;

function TAtlasDebugBarLayout.Scale(AValue: Integer): Integer;
begin
  Result := ScaleFor(AValue, FPPI);
end;

function TAtlasDebugBarLayout.RowHeight: Integer;
begin
  Result := Scale(cBaseRow);
end;

function TAtlasDebugBarLayout.RowTop(ARow: Integer): Integer;
begin
  Result := Scale(cBarPadding div 2) + ARow * RowHeight;
end;

function TAtlasDebugBarLayout.ExplanationRows: Integer;
begin
  Result := 0;
  if not FExplanation.Active then
  begin
    Exit;
  end;
  // Ergebniszeile; fertig auch Glieder, „… n weitere“ und die Knöpfe.
  Result := 1;
  if FExplanation.Busy then
  begin
    Exit;
  end;
  Inc(Result, ShownLines);
  if Length(FExplanation.Lines) > cMaxExplanationLines then
  begin
    Inc(Result);
  end;
  if (FExplanation.WhereName <> '') or (FExplanation.EvaluateExpression <> '') or (FExplanation.CopyText <> '') then
  begin
    Inc(Result);
  end;
end;

function TAtlasDebugBarLayout.Rows: Integer;
begin
  Result := cBaseRows + ExplanationRows;
end;

function TAtlasDebugBarLayout.ShownLines: Integer;
begin
  Result := Min(Length(FExplanation.Lines), cMaxExplanationLines);
end;

procedure TAtlasDebugBarLayout.PlaceButtons(const AActions: array of TAtlasDebugBarAction; ARow: Integer;
  const AShown: TFunc<TAtlasDebugBarAction, Boolean>; const AWidth: TAtlasDebugBarTextWidth);
var
  mAction: TAtlasDebugBarAction;
  mLeft, mTop, mWidth: Integer;
begin
  mTop := RowTop(ARow) + Scale(cButtonMargin);
  mLeft := Scale(cBarPadding + cGap);
  for mAction in AActions do
  begin
    if not AShown(mAction) then
    begin
      Continue;
    end;
    mWidth := AWidth(mAction) + Scale(cButtonPadding);
    FRects[mAction] := Rect(mLeft, mTop, mLeft + mWidth, mTop + RowHeight - Scale(2 * cButtonMargin));
    Inc(mLeft, mWidth + Scale(cGap));
  end;
end;

procedure TAtlasDebugBarLayout.Arrange(AClientWidth, ADetailWidth: Integer; const AWidth: TAtlasDebugBarTextWidth);
var
  mAction: TAtlasDebugBarAction;
  mWidth: Integer;
  mInfo: TAtlasDebugBannerInfo;
  mExplanation: TAtlasDebugBannerExplanation;
begin
  for mAction := Low(TAtlasDebugBarAction) to High(TAtlasDebugBarAction) do
  begin
    FRects[mAction] := TRect.Empty;
  end;
  // Ortszeile: nur der Teil mit Routine und Datei ist anklickbar, und nur mit Datei.
  if FInfo.HasLocation then
  begin
    mWidth := Min(ADetailWidth, AClientWidth - 2 * Scale(cBarPadding + cGap));
    FRects[TAtlasDebugBarAction.Open] := Rect(Scale(cBarPadding + cGap), Scale(cBarPadding div 2) + RowHeight,
      Scale(cBarPadding + cGap) + mWidth, Scale(cBarPadding div 2) + 2 * RowHeight);
  end;
  // Knöpfe der Erklärung in ihrer letzten Zeile (über den Knöpfen der Leiste).
  mExplanation := FExplanation;
  if FExplanation.Active and not FExplanation.Busy then
  begin
    PlaceButtons(cDebugExplanationButtons, Rows - 2,
      function(AAction: TAtlasDebugBarAction): Boolean
      begin
        Result := ExplanationHas(mExplanation, AAction);
      end, AWidth);
  end;
  mInfo := FInfo;
  PlaceButtons(cDebugBarButtons, Rows - 1,
    function(AAction: TAtlasDebugBarAction): Boolean
    begin
      Result := BarButtonShown(mInfo, AAction);
    end, AWidth);
end;

function TAtlasDebugBarLayout.ActionAt(AX, AY: Integer): TAtlasDebugBarAction;
var
  mAction: TAtlasDebugBarAction;
begin
  for mAction := Succ(TAtlasDebugBarAction.None) to High(TAtlasDebugBarAction) do
  begin
    if not FRects[mAction].IsEmpty and FRects[mAction].Contains(Point(AX, AY)) then
    begin
      Exit(mAction);
    end;
  end;
  Result := TAtlasDebugBarAction.None;
end;

function TAtlasDebugBarLayout.ActionRect(AAction: TAtlasDebugBarAction): TRect;
begin
  Result := FRects[AAction];
end;

function TAtlasDebugBarLayout.LastButtonRight: Integer;
var
  mAction: TAtlasDebugBarAction;
begin
  Result := 0;
  for mAction in cDebugBarButtons do
  begin
    Result := Max(Result, FRects[mAction].Right);
  end;
end;

function TAtlasDebugBarLayout.CanTrigger(AAction: TAtlasDebugBarAction): Boolean;
begin
  Result := False;
  // Ohne Ort gibt es weder „Nur an dieser Stelle ignorieren“ noch den Sprung.
  if (AAction = TAtlasDebugBarAction.None) or not BarButtonShown(FInfo, AAction) then
  begin
    Exit;
  end;
  if (AAction = TAtlasDebugBarAction.Open) and not FInfo.HasLocation then
  begin
    Exit;
  end;
  if (AAction in [TAtlasDebugBarAction.WhereAssigned, TAtlasDebugBarAction.Evaluate,
    TAtlasDebugBarAction.CopyExplanation]) and not ExplanationHas(FExplanation, AAction) then
  begin
    Exit;
  end;
  Result := True;
end;

class function TAtlasDebugBarLayout.BarHeight(APPI, ARows: Integer): Integer;
begin
  Result := ScaleFor(ARows * cBaseRow + cBarPadding, APPI);
end;

class function TAtlasDebugBarLayout.ExplanationHas(const AExplanation: TAtlasDebugBannerExplanation;
  AAction: TAtlasDebugBarAction): Boolean;
begin
  Result := False;
  if not AExplanation.Active or AExplanation.Busy then
  begin
    Exit;
  end;
  case AAction of
    TAtlasDebugBarAction.WhereAssigned:
      Result := AExplanation.WhereName <> '';
    TAtlasDebugBarAction.Evaluate:
      Result := AExplanation.EvaluateExpression <> '';
    TAtlasDebugBarAction.CopyExplanation:
      Result := AExplanation.CopyText <> '';
    TAtlasDebugBarAction.None, TAtlasDebugBarAction.BreakHere, TAtlasDebugBarAction.Continue,
    TAtlasDebugBarAction.IgnoreClass, TAtlasDebugBarAction.IgnoreLocation, TAtlasDebugBarAction.Copy,
    TAtlasDebugBarAction.Open, TAtlasDebugBarAction.CreateTest, TAtlasDebugBarAction.MessageRule: ;
  end;
end;

class function TAtlasDebugBarLayout.BarButtonShown(const AInfo: TAtlasDebugBannerInfo;
  AAction: TAtlasDebugBarAction): Boolean;
begin
  case AAction of
    TAtlasDebugBarAction.IgnoreLocation:
      Result := AInfo.CanIgnoreLocation;
    TAtlasDebugBarAction.CreateTest:
      Result := AInfo.CanCreateTest;
    TAtlasDebugBarAction.MessageRule:
      Result := AInfo.CanMessageRule;
  else
    Result := True;
  end;
end;

end.
