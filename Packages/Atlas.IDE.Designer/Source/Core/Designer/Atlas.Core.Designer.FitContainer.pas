unit Atlas.Core.Designer.FitContainer;

// Container im Designer an seinen Inhalt anpassen (#742), ohne VCL und
// Windows. Gerechnet wird im Client des Containers; Rahmen, Beschriftung
// (TGroupBox) und Padding stecken im Unterschied Außen- gegen Clientgröße
// bzw. in Inset (Fläche für ausgerichtete Kinder):
// - Kinder ohne Align: rechte bzw. untere Kante + Rand (designer.
//   fitContainer.padding). Mit alignTopLeft rücken sie vorher so, dass der
//   kleinste Abstand links und oben der Rand ist.
// - Ausgerichtete Kinder zählen in der freien Richtung: alTop/alBottom mit
//   ihrer Höhe (gestapelt, plus Inset), alLeft/alRight mit ihrer Breite;
//   unten bzw. rechts ausgerichtete schieben den übrigen Inhalt davor.
//   alClient zählt nicht; sind nur solche da, bleibt alles (OnlyClient).
// - Kinder nur mit akRight bzw. akBottom stehen danach um den Rand vom
//   rechten bzw. unteren Rand; alle Kinder ohne Align bekommen ihre Lage
//   ausdrücklich, damit Anker sie beim Ändern der Größe nicht mitziehen.
// - Nur freie Richtungen (Align des Containers, Modus) ändern sich;
//   Constraints gelten für die Außengröße.
// - Mehrfachauswahl „alle auf dieselbe Breite“: MaxOuterWidth über alle
//   Ergebnisse, dann jeder Container mit ForceOuterWidth noch einmal.

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  TAtlasFitAlign = (None, Top, Bottom, Left, Right, Client);
  TAtlasFitAnchor = (Left, Top, Right, Bottom);
  TAtlasFitMode = (Both, Width, Height);
{$SCOPEDENUMS OFF}
  TAtlasFitAnchors = set of TAtlasFitAnchor;

  TAtlasFitChild = record
    Bounds: TRect;
    Align: TAtlasFitAlign;
    Anchors: TAtlasFitAnchors;
    class function Create(const ABounds: TRect; AAlign: TAtlasFitAlign; AAnchors: TAtlasFitAnchors): TAtlasFitChild;
      static;
  end;

  TAtlasFitBox = record
    /// <summary>Außengröße (beim Formular gleich Client).</summary>
    Outer: TSize;
    Client: TSize;
    /// <summary>Abstand der Fläche für ausgerichtete Kinder vom Client (Padding, Beschriftung).</summary>
    Inset: TRect;
    /// <summary>Darf sich die Breite bzw. Höhe ändern (Align des Containers)?</summary>
    FreeWidth: Boolean;
    FreeHeight: Boolean;
    /// <summary>Constraints der Außengröße; 0 = keine.</summary>
    MinSize: TSize;
    MaxSize: TSize;
  end;

  TAtlasFitOptions = record
    Mode: TAtlasFitMode;
    Margin: Integer;
    AlignTopLeft: Boolean;
    /// <summary>Außenbreite vorgeben („alle auf dieselbe Breite“); 0 = rechnen.</summary>
    ForceOuterWidth: Integer;
    class function Create(AMode: TAtlasFitMode; AMargin: Integer; AAlignTopLeft: Boolean): TAtlasFitOptions; static;
  end;

  TAtlasFitResult = record
    Outer: TSize;
    Client: TSize;
    /// <summary>Neue Lage je Kind (ausgerichtete unverändert).</summary>
    Children: TArray<TRect>;
    /// <summary>Nur alClient-Kinder: nichts zu rechnen.</summary>
    OnlyClient: Boolean;
  end;

  TAtlasFitContainer = class
  public
    class function Fit(const ABox: TAtlasFitBox; const AChildren: TArray<TAtlasFitChild>;
      const AOptions: TAtlasFitOptions): TAtlasFitResult; static;
    /// <summary>Größte Außenbreite der Ergebnisse.</summary>
    class function MaxOuterWidth(const AResults: TArray<TAtlasFitResult>): Integer; static;
  end;

implementation

uses
  System.Math;

{ TAtlasFitChild }

class function TAtlasFitChild.Create(const ABounds: TRect; AAlign: TAtlasFitAlign;
  AAnchors: TAtlasFitAnchors): TAtlasFitChild;
begin
  Result.Bounds := ABounds;
  Result.Align := AAlign;
  Result.Anchors := AAnchors;
end;

{ TAtlasFitOptions }

class function TAtlasFitOptions.Create(AMode: TAtlasFitMode; AMargin: Integer;
  AAlignTopLeft: Boolean): TAtlasFitOptions;
begin
  Result.Mode := AMode;
  Result.Margin := AMargin;
  Result.AlignTopLeft := AAlignTopLeft;
  Result.ForceOuterWidth := 0;
end;

{ Rechnung je Achse }

type
  /// <summary>Eine Achse: Breite (Horizontal) oder Höhe.</summary>
  TAxis = record
    Horizontal: Boolean;
    function Lo(const ARect: TRect): Integer;
    function Hi(const ARect: TRect): Integer;
    function Size(const ARect: TRect): Integer;
    function NearAlign: TAtlasFitAlign;
    function FarAlign: TAtlasFitAlign;
    function NearAnchor: TAtlasFitAnchor;
    function FarAnchor: TAtlasFitAnchor;
    function InsetSum(const AInset: TRect): Integer;
    function Pick(const ASize: TSize): Integer;
  end;

function TAxis.Lo(const ARect: TRect): Integer;
begin
  Result := ARect.Top;
  if Horizontal then
  begin
    Result := ARect.Left;
  end;
end;

function TAxis.Hi(const ARect: TRect): Integer;
begin
  Result := ARect.Bottom;
  if Horizontal then
  begin
    Result := ARect.Right;
  end;
end;

function TAxis.Size(const ARect: TRect): Integer;
begin
  Result := Hi(ARect) - Lo(ARect);
end;

function TAxis.NearAlign: TAtlasFitAlign;
begin
  Result := TAtlasFitAlign.Top;
  if Horizontal then
  begin
    Result := TAtlasFitAlign.Left;
  end;
end;

function TAxis.FarAlign: TAtlasFitAlign;
begin
  Result := TAtlasFitAlign.Bottom;
  if Horizontal then
  begin
    Result := TAtlasFitAlign.Right;
  end;
end;

function TAxis.NearAnchor: TAtlasFitAnchor;
begin
  Result := TAtlasFitAnchor.Top;
  if Horizontal then
  begin
    Result := TAtlasFitAnchor.Left;
  end;
end;

function TAxis.FarAnchor: TAtlasFitAnchor;
begin
  Result := TAtlasFitAnchor.Bottom;
  if Horizontal then
  begin
    Result := TAtlasFitAnchor.Right;
  end;
end;

function TAxis.InsetSum(const AInset: TRect): Integer;
begin
  Result := AInset.Top + AInset.Bottom;
  if Horizontal then
  begin
    Result := AInset.Left + AInset.Right;
  end;
end;

function TAxis.Pick(const ASize: TSize): Integer;
begin
  Result := ASize.cy;
  if Horizontal then
  begin
    Result := ASize.cx;
  end;
end;

function AxisOf(AHorizontal: Boolean): TAxis;
begin
  Result.Horizontal := AHorizontal;
end;

/// <summary>Nötige Clientgröße entlang AAxis; -1, wenn nichts sie bestimmt.</summary>
function Needed(const AAxis: TAxis; const ABox: TAtlasFitBox; const AChildren: TArray<TAtlasFitChild>;
  const ABounds: TArray<TRect>; AMargin: Integer): Integer;
var
  mIndex, mContent, mStack, mFar: Integer;
  mAligned: Boolean;
begin
  mContent := -1;
  mStack := AAxis.InsetSum(ABox.Inset);
  mFar := 0;
  mAligned := False;
  for mIndex := 0 to High(AChildren) do
  begin
    if AChildren[mIndex].Align = TAtlasFitAlign.None then
    begin
      mContent := Max(mContent, AAxis.Hi(ABounds[mIndex]));
    end
    else if AChildren[mIndex].Align in [AAxis.NearAlign, AAxis.FarAlign] then
    begin
      mAligned := True;
      Inc(mStack, AAxis.Size(ABounds[mIndex]));
      if AChildren[mIndex].Align = AAxis.FarAlign then
      begin
        Inc(mFar, AAxis.Size(ABounds[mIndex]));
      end;
    end;
  end;
  Result := -1;
  if mAligned then
  begin
    Result := mStack;
  end;
  if mContent >= 0 then
  begin
    Result := Max(Result, mContent + AMargin + mFar);
  end;
end;

function Clamp(AValue, AMin, AMax: Integer): Integer;
begin
  Result := AValue;
  if AMin > 0 then
  begin
    Result := Max(Result, AMin);
  end;
  if AMax > 0 then
  begin
    Result := Min(Result, AMax);
  end;
end;

/// <summary>Darf sich die Größe entlang AAxis ändern (Align des Containers, Modus)?</summary>
function IsFree(const AAxis: TAxis; const ABox: TAtlasFitBox; const AOptions: TAtlasFitOptions): Boolean;
begin
  if AAxis.Horizontal then
  begin
    Result := ABox.FreeWidth and (AOptions.Mode <> TAtlasFitMode.Height);
  end
  else
  begin
    Result := ABox.FreeHeight and (AOptions.Mode <> TAtlasFitMode.Width);
  end;
end;

/// <summary>Neue Clientgröße entlang einer freien Achse nach Vorgabe und Constraints.</summary>
function NewClient(const AAxis: TAxis; const ABox: TAtlasFitBox; ANeeded: Integer;
  const AOptions: TAtlasFitOptions): Integer;
var
  mChrome, mOuter: Integer;
begin
  Result := AAxis.Pick(ABox.Client);
  mChrome := AAxis.Pick(ABox.Outer) - AAxis.Pick(ABox.Client);
  if AAxis.Horizontal and (AOptions.ForceOuterWidth > 0) then
  begin
    ANeeded := AOptions.ForceOuterWidth - mChrome;
  end;
  if ANeeded < 0 then
  begin
    Exit;
  end;
  mOuter := Clamp(ANeeded + mChrome, AAxis.Pick(ABox.MinSize), AAxis.Pick(ABox.MaxSize));
  Result := mOuter - mChrome;
end;

/// <summary>Kinder ohne Align so verschoben, dass der kleinste Abstand links bzw. oben AMargin ist.</summary>
procedure AlignTopLeft(const AAxis: TAxis; const AChildren: TArray<TAtlasFitChild>; var ABounds: TArray<TRect>;
  AMargin: Integer);
var
  mIndex, mMin: Integer;
begin
  mMin := MaxInt;
  for mIndex := 0 to High(AChildren) do
  begin
    if AChildren[mIndex].Align = TAtlasFitAlign.None then
    begin
      mMin := Min(mMin, AAxis.Lo(ABounds[mIndex]));
    end;
  end;
  if mMin = MaxInt then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AChildren) do
  begin
    if (AChildren[mIndex].Align = TAtlasFitAlign.None) and AAxis.Horizontal then
    begin
      ABounds[mIndex].Offset(AMargin - mMin, 0);
    end
    else if AChildren[mIndex].Align = TAtlasFitAlign.None then
    begin
      ABounds[mIndex].Offset(0, AMargin - mMin);
    end;
  end;
end;

/// <summary>Kinder nur mit dem fernen Anker an den Rand (AClient − AMargin).</summary>
procedure PlaceFar(const AAxis: TAxis; const AChildren: TArray<TAtlasFitChild>; var ABounds: TArray<TRect>;
  AClient, AMargin: Integer);
var
  mIndex, mShift: Integer;
begin
  for mIndex := 0 to High(AChildren) do
  begin
    if (AChildren[mIndex].Align <> TAtlasFitAlign.None) or not (AAxis.FarAnchor in AChildren[mIndex].Anchors) or
      (AAxis.NearAnchor in AChildren[mIndex].Anchors) then
    begin
      Continue;
    end;
    mShift := AClient - AMargin - AAxis.Hi(ABounds[mIndex]);
    if AAxis.Horizontal then
    begin
      ABounds[mIndex].Offset(mShift, 0);
    end
    else
    begin
      ABounds[mIndex].Offset(0, mShift);
    end;
  end;
end;

{ TAtlasFitContainer }

class function TAtlasFitContainer.Fit(const ABox: TAtlasFitBox; const AChildren: TArray<TAtlasFitChild>;
  const AOptions: TAtlasFitOptions): TAtlasFitResult;
var
  mIndex: Integer;
  mAxis: TAxis;
  mHorizontal: Boolean;
  mClient: array [Boolean] of Integer;
begin
  SetLength(Result.Children, Length(AChildren));
  Result.OnlyClient := Length(AChildren) > 0;
  for mIndex := 0 to High(AChildren) do
  begin
    Result.Children[mIndex] := AChildren[mIndex].Bounds;
    Result.OnlyClient := Result.OnlyClient and (AChildren[mIndex].Align = TAtlasFitAlign.Client);
  end;
  for mHorizontal := False to True do
  begin
    mAxis := AxisOf(mHorizontal);
    mClient[mHorizontal] := mAxis.Pick(ABox.Client);
    if Result.OnlyClient or not IsFree(mAxis, ABox, AOptions) then
    begin
      Continue;
    end;
    if AOptions.AlignTopLeft then
    begin
      AlignTopLeft(mAxis, AChildren, Result.Children, AOptions.Margin);
    end;
    mClient[mHorizontal] := NewClient(mAxis, ABox, Needed(mAxis, ABox, AChildren, Result.Children, AOptions.Margin),
      AOptions);
    PlaceFar(mAxis, AChildren, Result.Children, mClient[mHorizontal], AOptions.Margin);
  end;
  Result.Client := TSize.Create(mClient[True], mClient[False]);
  Result.Outer := TSize.Create(ABox.Outer.cx - ABox.Client.cx + mClient[True],
    ABox.Outer.cy - ABox.Client.cy + mClient[False]);
end;

class function TAtlasFitContainer.MaxOuterWidth(const AResults: TArray<TAtlasFitResult>): Integer;
var
  mResult: TAtlasFitResult;
begin
  Result := 0;
  for mResult in AResults do
  begin
    Result := Max(Result, mResult.Outer.cx);
  end;
end;

end.
