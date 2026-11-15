unit Atlas.Core.Rules.OwnershipPlan;

// Entscheidungen der Marke „Wer gibt das frei?“ im Editor (#1877), ohne VCL
// und Open Tools API. Atlas.IDE.Rules.OwnershipHints zeichnet, nimmt Klick
// und Maus und fragt den Server; was es dabei entscheidet, steht hier:
// - Ob die Marken laufen und welche Dateien sie bekommen (.pas, .dpr).
// - Ob ein Klick zur freigebenden Zeile springt.
// - Gemerkte Marken: welche eine neue ersetzt und wann alle verfallen
//   (gescrollt).
// - Überfahren: Tooltip zeigen, offen lassen oder schließen.

{$SCOPEDENUMS ON}

interface

type
  /// <summary>Was der Tooltip beim Takt tut.</summary>
  TAtlasOwnershipTipStep = (
    /// <summary>Nichts (Wartezeit läuft oder schon sichtbar).</summary>
    Stay,
    /// <summary>Maus nicht mehr über Marke oder Tooltip: schließen.</summary>
    Close,
    /// <summary>Lange genug überfahren: zeigen.</summary>
    Show);

  TAtlasOwnershipPlan = record
  public
    /// <summary>Laufen die Marken? Atlas an (AEnabled), editor.ownershipHints an, Prüfung nicht abgeschaltet.
    /// </summary>
    class function Wanted(AEnabled, AHints, ADisabled: Boolean): Boolean; static;
    /// <summary>Bekommt AFileName Marken (.pas, .dpr)?</summary>
    class function MarksFile(const AFileName: string): Boolean; static;
    /// <summary>Springt der Klick? Linke Taste ohne Umschalt, Alt und Strg, Marken gezeichnet, eingeschaltet.
    /// </summary>
    class function ClickJumps(ALeftButton, AModifier, AHasHits, AWanted: Boolean): Boolean; static;
    /// <summary>Verfallen die gemerkten Marken (erste mit oberster Zeile AFirstTopRow), weil die neue bei
    /// ATopRow gezeichnet wurde?</summary>
    class function ForgetsHits(AHasHits: Boolean; AFirstTopRow, ATopRow: Integer): Boolean; static;
    /// <summary>Index der gemerkten Marke derselben Zeile ALine unter ALines; -1 ohne.</summary>
    class function SameLine(const ALines: TArray<Integer>; ALine: Integer): Integer; static;
    /// <summary>Tooltip: Maus über Marke oder Tooltip (AInside), Tooltip sichtbar, überfahren seit ASince,
    /// Verzögerung ADelayMs.</summary>
    class function TipStep(AInside, ATipShown: Boolean; ASince, ANowMs, ADelayMs: UInt64): TAtlasOwnershipTipStep;
      static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasOwnershipPlan }

class function TAtlasOwnershipPlan.Wanted(AEnabled, AHints, ADisabled: Boolean): Boolean;
begin
  Result := AEnabled and AHints and not ADisabled;
end;

class function TAtlasOwnershipPlan.MarksFile(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := ExtractFileExt(AFileName);
  Result := SameText(mExtension, '.pas') or SameText(mExtension, '.dpr');
end;

class function TAtlasOwnershipPlan.ClickJumps(ALeftButton, AModifier, AHasHits, AWanted: Boolean): Boolean;
begin
  Result := ALeftButton and not AModifier and AHasHits and AWanted;
end;

class function TAtlasOwnershipPlan.ForgetsHits(AHasHits: Boolean; AFirstTopRow, ATopRow: Integer): Boolean;
begin
  Result := AHasHits and (AFirstTopRow <> ATopRow);
end;

class function TAtlasOwnershipPlan.SameLine(const ALines: TArray<Integer>; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ALines) do
  begin
    if ALines[mIndex] = ALine then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasOwnershipPlan.TipStep(AInside, ATipShown: Boolean; ASince, ANowMs,
  ADelayMs: UInt64): TAtlasOwnershipTipStep;
begin
  Result := TAtlasOwnershipTipStep.Stay;
  if not AInside then
  begin
    Result := TAtlasOwnershipTipStep.Close;
  end
  else if not ATipShown and (ANowMs - ASince >= ADelayMs) then
  begin
    Result := TAtlasOwnershipTipStep.Show;
  end;
end;

end.
