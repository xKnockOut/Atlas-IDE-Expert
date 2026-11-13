unit Atlas.Core.Hover.Items;

// Bausteine und Klickflächen des Hover-Satzes ohne VCL: Atlas.Core.Hover.Layout
// legt sie an, Atlas.UI.Hover.Tip zeichnet sie. Dazu der Rollbereich (#1841), in dem
// die published-Mitglieder großer Komponenten scrollen: Fit begrenzt ihn auf
// MaxLines Tabellenzeilen bzw. den Platz auf dem Bildschirm (mindestens MinRows
// Zeilen), Shift verschiebt Bausteine und Klickflächen um den Versatz und streicht
// verdeckte Klickflächen, Thumb liefert den Daumen am rechten Rand.

interface

uses
  System.Types,
  Atlas.Core.Style.Color;

type
  {$SCOPEDENUMS ON}
  /// <summary>Schriften des Tooltips: UI, Editorschrift, beide verkleinert, Badge.</summary>
  TAtlasHoverFont = (Ui, Mono, SmallUi, SmallMono, Badge);
  /// <summary>DebugFix: Korrektur unter „kein Zugriff“ (#840), Index in View.DebugValue.Note.Fixes.
  /// DebugAction: Aktion unter dem Wert (Anheften #526), Index in View.DebugValue.Actions.
  /// DebugRow: Zeile des aufgeklappten Werts (#895), Index in View.DebugValue.Rows, -1 der Wert selbst.</summary>
  TAtlasHoverHitKind = (Link, Ancestor, Path, Back, Action, ProblemAction, Published, DebugFix, DebugAction,
    DebugRow);
  /// <summary>Fill: Fläche; Line: waagrechte Linie; Text: Text ab Rect.TopLeft; CenterText: zentriert in
  /// Rect; Frame: umrandetes Rechteck mit Fläche Back; RoundFill: gefülltes Rechteck mit Radius; Block:
  /// umbrechender Text in Rect (UI-Schrift, Ellipse); Styled: eingefärbte Deklaration From..Till; Doc: XMLDoc
  /// ab Rect.TopLeft.</summary>
  TAtlasHoverItemKind = (Fill, Line, Text, CenterText, Frame, RoundFill, Block, Styled, Doc);
  {$SCOPEDENUMS OFF}

  TAtlasHoverFace = record
    Font: TAtlasHoverFont;
    Bold: Boolean;
    Underline: Boolean;
    class function Create(AFont: TAtlasHoverFont; ABold, AUnderline: Boolean): TAtlasHoverFace; static;
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

  /// <summary>Wunsch an den Rollbereich: höchstens MaxLines Zeilen (hover.membersMaxLines) bzw. Limit Pixel
  /// (Platz auf dem Bildschirm), je 0 = unbegrenzt; Scroll ist der gewünschte Versatz in Pixeln.</summary>
  TAtlasHoverScrollRequest = record
    MaxLines: Integer;
    Limit: Integer;
    Scroll: Integer;
  end;

  /// <summary>Rollbereich im Satz: View sichtbar (Höhe 0 ohne Inhalt), Content volle Höhe, Scroll Versatz,
  /// Row Höhe einer Zeile (Schritt des Mausrads); Bausteine [ClipFrom, ClipTill) zeichnet das Fenster
  /// beschnitten auf View, ClipFrom = -1 ohne.</summary>
  TAtlasHoverScroll = record
  public const
    cMinRows = 3;
  public
    View: TRect;
    Content: Integer;
    Scroll: Integer;
    Row: Integer;
    ClipFrom: Integer;
    ClipTill: Integer;
    class function None: TAtlasHoverScroll; static;
    /// <summary>Höchsthöhe aus ARequest bei Zeilenhöhe ARow; 0 = unbegrenzt.</summary>
    class function LimitOf(const ARequest: TAtlasHoverScrollRequest; ARow: Integer): Integer; static;
    /// <summary>Inhalt von ATop bis ABottom in der Breite AWidth; True, wenn er nach ARequest scrollen muss
    /// (View dann gekürzt, Scroll begrenzt).</summary>
    function Fit(const ARequest: TAtlasHoverScrollRequest; ATop, ABottom, AWidth, ARow: Integer): Boolean;
    /// <summary>Verschiebt AItems[AFirstItem..AItemCount) und AHits[AFirstHit..AHitCount) um Scroll nach oben,
    /// beschneidet die Klickflächen auf View, streicht verdeckte (AHitCount sinkt) und setzt ClipFrom/ClipTill.
    /// </summary>
    procedure Shift(var AItems: TArray<TAtlasHoverItem>; AFirstItem, AItemCount: Integer;
      var AHits: TArray<TAtlasHoverHit>; AFirstHit: Integer; var AHitCount: Integer);
    /// <summary>Daumen am rechten Rand: mindestens AMinHeight hoch, von AInset bis AEdge Pixel vor dem rechten
    /// Rand.</summary>
    function Thumb(AMinHeight, AInset, AEdge: Integer): TRect;
    function Scrollable: Boolean;
    /// <summary>Größter Versatz; 0, wenn der Bereich nicht scrollt.</summary>
    function MaxScroll: Integer;
  end;

implementation

uses
  System.Math;

{ TAtlasHoverFace }

class function TAtlasHoverFace.Create(AFont: TAtlasHoverFont; ABold, AUnderline: Boolean): TAtlasHoverFace;
begin
  Result.Font := AFont;
  Result.Bold := ABold;
  Result.Underline := AUnderline;
end;

{ TAtlasHoverScroll }

class function TAtlasHoverScroll.None: TAtlasHoverScroll;
begin
  Result := Default(TAtlasHoverScroll);
  Result.ClipFrom := -1;
end;

class function TAtlasHoverScroll.LimitOf(const ARequest: TAtlasHoverScrollRequest; ARow: Integer): Integer;
begin
  Result := 0;
  if ARequest.MaxLines > 0 then
  begin
    Result := ARequest.MaxLines * ARow;
  end;
  if (ARequest.Limit > 0) and ((Result = 0) or (ARequest.Limit < Result)) then
  begin
    Result := ARequest.Limit;
  end;
  if Result > 0 then
  begin
    Result := Max(Result, cMinRows * ARow);
  end;
end;

function TAtlasHoverScroll.Fit(const ARequest: TAtlasHoverScrollRequest; ATop, ABottom, AWidth,
  ARow: Integer): Boolean;
var
  mLimit: Integer;
begin
  Row := ARow;
  Content := ABottom - ATop;
  View := Rect(0, ATop, AWidth, ABottom);
  mLimit := LimitOf(ARequest, ARow);
  Result := (mLimit > 0) and (Content > mLimit);
  if Result then
  begin
    View.Bottom := ATop + mLimit;
    Scroll := EnsureRange(ARequest.Scroll, 0, MaxScroll);
  end;
end;

procedure TAtlasHoverScroll.Shift(var AItems: TArray<TAtlasHoverItem>; AFirstItem, AItemCount: Integer;
  var AHits: TArray<TAtlasHoverHit>; AFirstHit: Integer; var AHitCount: Integer);
var
  mIndex, mKept: Integer;
  mRect: TRect;
begin
  for mIndex := AFirstItem to AItemCount - 1 do
  begin
    AItems[mIndex].Rect.Offset(0, -Scroll);
  end;
  mKept := AFirstHit;
  for mIndex := AFirstHit to AHitCount - 1 do
  begin
    mRect := AHits[mIndex].Rect;
    mRect.Offset(0, -Scroll);
    mRect.Intersect(View);
    if not mRect.IsEmpty then
    begin
      AHits[mKept] := AHits[mIndex];
      AHits[mKept].Rect := mRect;
      Inc(mKept);
    end;
  end;
  AHitCount := mKept;
  ClipFrom := AFirstItem;
  ClipTill := AItemCount;
end;

function TAtlasHoverScroll.Thumb(AMinHeight, AInset, AEdge: Integer): TRect;
var
  mHeight, mTop: Integer;
begin
  // Höhe im Verhältnis sichtbar zu ganz, Lage im Verhältnis Versatz zu größtem Versatz.
  mHeight := Max(AMinHeight, Integer(Int64(View.Height) * View.Height div Max(1, Content)));
  mTop := View.Top;
  if MaxScroll > 0 then
  begin
    mTop := View.Top + Integer(Int64(View.Height - mHeight) * Scroll div MaxScroll);
  end;
  Result := Rect(View.Right - AInset, mTop, View.Right - AEdge, mTop + mHeight);
end;

function TAtlasHoverScroll.Scrollable: Boolean;
begin
  Result := Content > View.Height;
end;

function TAtlasHoverScroll.MaxScroll: Integer;
begin
  Result := Max(0, Content - View.Height);
end;

end.
