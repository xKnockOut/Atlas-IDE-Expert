unit Atlas.Core.Designer.Scale;

// Formular in einer anderen Skalierung, auf einem kleineren Bildschirm und
// mit längeren Texten (#607), ohne VCL und Windows. Die echten Komponenten im
// Designer werden nicht angefasst, die DFM bleibt unverändert.
// - Skalierung nach den Regeln der VCL (ChangeScale): Left, Top, Width,
//   Height, Margins, Padding, Constraints und Schrifthöhe werden einzeln mit
//   PPI / PixelsPerInch gerundet; bei Scaled = False bleibt alles, nur Rahmen
//   und Taskleiste wachsen mit der Skalierung von Windows.
// - Lange Texte: jede Zeile um AFactor Prozent verlängert (aufgerundet), mit
//   den eigenen Zeichen aufgefüllt („Speichern“ + 30 % = „SpeichernSpe“).
// - Textbreiten misst der Aufrufer (GDI im Plugin, feste Breite in Tests).
// - Befunde: alle aus TAtlasFormLayout.Problems, dazu abgeschnittene Texte
//   (AutoSize und WordWrap aus, Text + Anteil des Steuerelements breiter als
//   die Komponente) und ein Formular, das samt Rahmen und Taskleiste nicht
//   auf den gewählten Bildschirm passt. AutoSize-Labels wachsen mit dem Text;
//   ragen sie dann heraus oder überlappen, meldet das die Layoutprüfung.

interface

uses
  System.Types,
  Atlas.Core.Designer.Layout;

type
  /// <summary>Text eines Steuerelements für die Prüfung auf abgeschnittene Beschriftungen.</summary>
  TAtlasScaleText = record
    /// <summary>Caption bzw. Einträge (Zeilen mit LF getrennt); leer = nichts zu prüfen.</summary>
    Text: string;
    FontName: string;
    /// <summary>Schrifthöhe in Pixeln der DFM wie TFont.Height (negativ = Zeichenhöhe).</summary>
    FontHeight: Integer;
    Bold: Boolean;
    Italic: Boolean;
    /// <summary>Platz neben dem Text (Kästchen, Pfeil, Glyph, Innenabstand) in Pixeln der DFM.</summary>
    Extra: Integer;
    /// <summary>Breite folgt dem Text (AutoSize eines Labels).</summary>
    AutoSize: Boolean;
    WordWrap: Boolean;
  end;

  /// <summary>Breite einer Zeile in der Schrift von AText bei APpi.</summary>
  TAtlasTextWidth = reference to function(const AText: TAtlasScaleText; const ALine: string; APpi: Integer): Integer;

  TAtlasScaleSetup = record
    /// <summary>PixelsPerInch der DFM.</summary>
    DesignPpi: Integer;
    /// <summary>Gewählte Skalierung als PPI (96 = 100 %).</summary>
    Ppi: Integer;
    Scaled: Boolean;
    /// <summary>Client des Formulars in Pixeln der DFM.</summary>
    Client: TSize;
    /// <summary>Rahmen und Titel (ganze Größe minus Client) in Pixeln der DFM.</summary>
    Frame: TSize;
    /// <summary>Bildschirm in physischen Pixeln; 0 = kein Limit.</summary>
    Screen: TSize;
    /// <summary>Verlängerung der Texte in Prozent; 0 = Original.</summary>
    LongFactor: Integer;
  end;

  TAtlasScaleView = record
    /// <summary>Knoten mit skalierten Werten (Pixel bei der gewählten Skalierung).</summary>
    Nodes: TArray<TAtlasLayoutNode>;
    Bounds: TArray<TRect>;
    Client: TSize;
    /// <summary>Gezeigter Text je Knoten (verlängert, ohne „&amp;“); leer ohne Text.</summary>
    Texts: TArray<string>;
    Findings: TArray<TAtlasLayoutFinding>;
    /// <summary>Nutzbarer Client auf dem Bildschirm (ohne Rahmen und Taskleiste); 0 = kein Limit.</summary>
    Usable: TSize;
  end;

  TAtlasFormScale = class
  public const
    cBasePpi = 96;
    /// <summary>Höhe der Taskleiste bei 100 %.</summary>
    cTaskbar = 48;
    cMinPercent = 50;
    cMaxPercent = 400;
  public
    /// <summary>AValue von ADesignPpi auf APpi, gerundet wie MulDiv.</summary>
    class function Value(AValue, ADesignPpi, APpi: Integer): Integer; static;
    /// <summary>Alle Knoten auf APpi skaliert (Lage, Margins, Padding, Rand, Constraints).</summary>
    class function Nodes(const ANodes: TArray<TAtlasLayoutNode>; ADesignPpi, APpi: Integer): TArray<TAtlasLayoutNode>;
      static;
    /// <summary>AText um AFactor Prozent verlängert (aufgerundet), aufgefüllt mit den eigenen Zeichen.</summary>
    class function LongText(const AText: string; AFactor: Integer): string; static;
    /// <summary>Prozentwerte aus „100, 125, 150“ (50 bis 400); Unbrauchbares entfällt, leer ergibt [100].</summary>
    class function ParseLevels(const AText: string): TArray<Integer>; static;
    /// <summary>Formular nach ASetup: skalierte Lagen, gezeigte Texte und Befunde.</summary>
    class function View(const ANodes: TArray<TAtlasLayoutNode>; const ATexts: TArray<TAtlasScaleText>;
      const ASetup: TAtlasScaleSetup; const AWidth: TAtlasTextWidth): TAtlasScaleView; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Designer.FitText;

const
  cPercent = 100;
  cLineBreak = #10;

class function TAtlasFormScale.Value(AValue, ADesignPpi, APpi: Integer): Integer;
var
  mProduct: Int64;
begin
  if (ADesignPpi <= 0) or (ADesignPpi = APpi) then
  begin
    Exit(AValue);
  end;
  // Wie MulDiv: halbe Pixel von der Null weg runden.
  mProduct := Int64(AValue) * APpi;
  if mProduct >= 0 then
  begin
    Result := Integer((2 * mProduct + ADesignPpi) div (2 * ADesignPpi));
  end
  else
  begin
    Result := -Integer((-2 * mProduct + ADesignPpi) div (2 * ADesignPpi));
  end;
end;

function ScaleRect(const ARect: TRect; ADesignPpi, APpi: Integer): TRect;
begin
  Result := Rect(TAtlasFormScale.Value(ARect.Left, ADesignPpi, APpi), TAtlasFormScale.Value(ARect.Top, ADesignPpi,
    APpi), TAtlasFormScale.Value(ARect.Right, ADesignPpi, APpi), TAtlasFormScale.Value(ARect.Bottom, ADesignPpi,
    APpi));
end;

class function TAtlasFormScale.Nodes(const ANodes: TArray<TAtlasLayoutNode>; ADesignPpi,
  APpi: Integer): TArray<TAtlasLayoutNode>;
var
  mIndex: Integer;
  mBounds: TRect;
begin
  Result := Copy(ANodes);
  for mIndex := 0 to High(Result) do
  begin
    mBounds := ANodes[mIndex].Bounds;
    // ChangeScale rundet Lage und Größe einzeln, nicht die rechte Kante.
    Result[mIndex].Bounds := Bounds(Value(mBounds.Left, ADesignPpi, APpi), Value(mBounds.Top, ADesignPpi, APpi),
      Value(mBounds.Width, ADesignPpi, APpi), Value(mBounds.Height, ADesignPpi, APpi));
    Result[mIndex].Margins := ScaleRect(ANodes[mIndex].Margins, ADesignPpi, APpi);
    Result[mIndex].Padding := ScaleRect(ANodes[mIndex].Padding, ADesignPpi, APpi);
    Result[mIndex].Inset := ScaleRect(ANodes[mIndex].Inset, ADesignPpi, APpi);
    Result[mIndex].MinWidth := Value(ANodes[mIndex].MinWidth, ADesignPpi, APpi);
    Result[mIndex].MinHeight := Value(ANodes[mIndex].MinHeight, ADesignPpi, APpi);
    Result[mIndex].MaxWidth := Value(ANodes[mIndex].MaxWidth, ADesignPpi, APpi);
    Result[mIndex].MaxHeight := Value(ANodes[mIndex].MaxHeight, ADesignPpi, APpi);
  end;
end;

class function TAtlasFormScale.LongText(const AText: string; AFactor: Integer): string;
var
  mTarget, mIndex: Integer;
begin
  Result := AText;
  if (AFactor <= 0) or (AText = '') then
  begin
    Exit;
  end;
  mTarget := (Length(AText) * (cPercent + AFactor) + cPercent - 1) div cPercent;
  mIndex := 1;
  while Length(Result) < mTarget do
  begin
    Result := Result + AText[mIndex];
    Inc(mIndex);
    if mIndex > Length(AText) then
    begin
      mIndex := 1;
    end;
  end;
end;

class function TAtlasFormScale.ParseLevels(const AText: string): TArray<Integer>;
var
  mPart: string;
  mValue: Integer;
begin
  Result := nil;
  for mPart in AText.Split([',', ';', ' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    if TryStrToInt(mPart.Replace('%', '').Trim, mValue) and (mValue >= cMinPercent) and (mValue <= cMaxPercent) then
    begin
      Result := Result + [mValue];
    end;
  end;
  if Length(Result) = 0 then
  begin
    Result := [cPercent];
  end;
end;

/// <summary>Zeilen des Texts, jede verlängert, wieder mit LF verbunden.</summary>
function ShownText(const AText: string; AFactor: Integer): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in TAtlasFitText.Lines(AText) do
  begin
    if Result <> '' then
    begin
      Result := Result + cLineBreak;
    end;
    Result := Result + TAtlasFormScale.LongText(mLine, AFactor);
  end;
end;

function WidestLine(const AText: TAtlasScaleText; const AShown: string; APpi: Integer;
  const AWidth: TAtlasTextWidth): Integer;
var
  mLine: string;
  mWidth: Integer;
begin
  Result := 0;
  for mLine in AShown.Split([cLineBreak]) do
  begin
    mWidth := AWidth(AText, mLine, APpi);
    if mWidth > Result then
    begin
      Result := mWidth;
    end;
  end;
end;

function Finding(ANode: Integer; AProblem: TAtlasLayoutProblem; AAmount: Integer): TAtlasLayoutFinding;
begin
  Result := Default(TAtlasLayoutFinding);
  Result.Node := ANode;
  Result.Problem := AProblem;
  Result.Amount := AAmount;
end;

/// <summary>Breite der Texte prüfen; AutoSize-Labels wachsen in AView.Bounds mit.</summary>
function TextFindings(var AView: TAtlasScaleView; const ATexts: TArray<TAtlasScaleText>; APpi, ADesignPpi: Integer;
  const AWidth: TAtlasTextWidth): TArray<TAtlasLayoutFinding>;
var
  mIndex, mNeed: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AView.Nodes) do
  begin
    if (mIndex > High(ATexts)) or (AView.Texts[mIndex] = '') or ATexts[mIndex].WordWrap or
      not AView.Nodes[mIndex].Visible then
    begin
      Continue;
    end;
    mNeed := WidestLine(ATexts[mIndex], AView.Texts[mIndex], APpi, AWidth) +
      TAtlasFormScale.Value(ATexts[mIndex].Extra, ADesignPpi, APpi);
    if ATexts[mIndex].AutoSize then
    begin
      if AView.Nodes[mIndex].Align = TAtlasLayoutAlign.None then
      begin
        AView.Bounds[mIndex].Right := AView.Bounds[mIndex].Left + mNeed;
      end;
    end
    else if mNeed > AView.Bounds[mIndex].Width then
    begin
      Result := Result + [Finding(mIndex, TAtlasLayoutProblem.Clipped, mNeed - AView.Bounds[mIndex].Width)];
    end;
  end;
end;

function ScreenFindings(const ASetup: TAtlasScaleSetup; const AClient: TSize; out AUsable: TSize):
  TArray<TAtlasLayoutFinding>;
var
  mFrame: TSize;
  mTaskbar: Integer;
begin
  Result := nil;
  AUsable := TSize.Create(0, 0);
  if (ASetup.Screen.cx <= 0) or (ASetup.Screen.cy <= 0) then
  begin
    Exit;
  end;
  // Rahmen und Taskleiste zeichnet Windows in seiner Skalierung, auch bei Scaled = False.
  mFrame := TSize.Create(TAtlasFormScale.Value(ASetup.Frame.cx, ASetup.DesignPpi, ASetup.Ppi),
    TAtlasFormScale.Value(ASetup.Frame.cy, ASetup.DesignPpi, ASetup.Ppi));
  mTaskbar := TAtlasFormScale.Value(TAtlasFormScale.cTaskbar, TAtlasFormScale.cBasePpi, ASetup.Ppi);
  AUsable := TSize.Create(ASetup.Screen.cx - mFrame.cx, ASetup.Screen.cy - mFrame.cy - mTaskbar);
  if AClient.cx > AUsable.cx then
  begin
    Result := Result + [Finding(-1, TAtlasLayoutProblem.ScreenWidth, AClient.cx - AUsable.cx)];
  end;
  if AClient.cy > AUsable.cy then
  begin
    Result := Result + [Finding(-1, TAtlasLayoutProblem.ScreenHeight, AClient.cy - AUsable.cy)];
  end;
end;

class function TAtlasFormScale.View(const ANodes: TArray<TAtlasLayoutNode>; const ATexts: TArray<TAtlasScaleText>;
  const ASetup: TAtlasScaleSetup; const AWidth: TAtlasTextWidth): TAtlasScaleView;
var
  mPpi, mIndex: Integer;
  mUsable: TSize;
begin
  Result := Default(TAtlasScaleView);
  // Scaled = False: die VCL skaliert weder Lage noch Schrift.
  mPpi := ASetup.DesignPpi;
  if ASetup.Scaled then
  begin
    mPpi := ASetup.Ppi;
  end;
  Result.Nodes := Nodes(ANodes, ASetup.DesignPpi, mPpi);
  Result.Client := TSize.Create(Value(ASetup.Client.cx, ASetup.DesignPpi, mPpi), Value(ASetup.Client.cy,
    ASetup.DesignPpi, mPpi));
  Result.Bounds := TAtlasFormLayout.Arrange(Result.Nodes, Result.Client, Result.Client);
  SetLength(Result.Texts, Length(ANodes));
  for mIndex := 0 to High(ANodes) do
  begin
    if mIndex <= High(ATexts) then
    begin
      Result.Texts[mIndex] := ShownText(ATexts[mIndex].Text, ASetup.LongFactor);
    end;
  end;
  Result.Findings := TextFindings(Result, ATexts, mPpi, ASetup.DesignPpi, AWidth);
  Result.Findings := TAtlasFormLayout.Problems(Result.Nodes, Result.Bounds, Result.Client) + Result.Findings +
    ScreenFindings(ASetup, Result.Client, mUsable);
  Result.Usable := mUsable;
end;

end.
