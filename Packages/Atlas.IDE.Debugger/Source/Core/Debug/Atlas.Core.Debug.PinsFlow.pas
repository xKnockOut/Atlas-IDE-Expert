unit Atlas.Core.Debug.PinsFlow;

// Entscheidungen der angehefteten Werte (#526) außerhalb der Ablage, ohne IDE prüfbar (#1967): ob der Halt noch
// gilt, wann die Grenze gemeldet wird, welche Felder in einer Zeile stehen, ob ein Klick zählt und welches Kreuz er
// trifft. Atlas.IDE.Debug.Pins fragt Debugger und Editor und zeichnet.

interface

uses
  System.Types,
  Atlas.Core.Debug.Pins;

type
  /// <summary>Kreuz eines gezeichneten Felds, für den Klick.</summary>
  TAtlasPinHit = record
    Pin: TAtlasDebugPin;
    Rect: TRect;
  end;

  TAtlasPinsFlow = class
  public
    /// <summary>Gilt der Halt AStop noch: Felder sichtbar, kein neuer Halt (AStopCount), Thread steht?</summary>
    class function StillStopped(AVisible: Boolean; AStop, AStopCount: Integer; AHasThread: Boolean): Boolean;
      static;
    /// <summary>Nicht angeheftet, weil das Projekt schon ACount Einträge hat: Grenze melden?</summary>
    class function ReportLimit(AAdded: Boolean; ACount: Integer): Boolean; static;
    /// <summary>„Anheften“ anbieten: Teil läuft und der Wert hat einen Ausdruck.</summary>
    class function CanOffer(AStarted: Boolean; const AExpression: string): Boolean; static;
    /// <summary>Einträge an Zeile ALine (1-basiert) aus APins, in ihrer Reihenfolge.</summary>
    class function OnLine(const APins: TAtlasDebugPinList; ALine: Integer): TAtlasDebugPinList; static;
    /// <summary>Kann ein Mausklick ein Feld lösen: linke Taste ohne Umschalt, Strg, Alt, Felder sichtbar?</summary>
    class function WantsClick(ALeft, AModifier, AVisible: Boolean): Boolean; static;
    /// <summary>Kreuz unter APoint; bei Überlappung gewinnt das zuletzt gezeichnete.</summary>
    class function HitAt(const AHits: TArray<TAtlasPinHit>; const APoint: TPoint; out APin: TAtlasDebugPin): Boolean;
      static;
  end;

implementation

{ TAtlasPinsFlow }

class function TAtlasPinsFlow.StillStopped(AVisible: Boolean; AStop, AStopCount: Integer;
  AHasThread: Boolean): Boolean;
begin
  Result := AVisible and (AStopCount = AStop) and AHasThread;
end;

class function TAtlasPinsFlow.ReportLimit(AAdded: Boolean; ACount: Integer): Boolean;
begin
  Result := not AAdded and (ACount >= TAtlasDebugPins.cLimit);
end;

class function TAtlasPinsFlow.CanOffer(AStarted: Boolean; const AExpression: string): Boolean;
begin
  Result := AStarted and (AExpression <> '');
end;

class function TAtlasPinsFlow.OnLine(const APins: TAtlasDebugPinList; ALine: Integer): TAtlasDebugPinList;
var
  mPin: TAtlasDebugPin;
  mCount: Integer;
begin
  Result := nil;
  SetLength(Result, Length(APins));
  mCount := 0;
  for mPin in APins do
  begin
    if mPin.Line = ALine then
    begin
      Result[mCount] := mPin;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

class function TAtlasPinsFlow.WantsClick(ALeft, AModifier, AVisible: Boolean): Boolean;
begin
  Result := ALeft and not AModifier and AVisible;
end;

class function TAtlasPinsFlow.HitAt(const AHits: TArray<TAtlasPinHit>; const APoint: TPoint;
  out APin: TAtlasDebugPin): Boolean;
var
  mHit: TAtlasPinHit;
begin
  Result := False;
  APin := Default(TAtlasDebugPin);
  for mHit in AHits do
  begin
    if mHit.Rect.Contains(APoint) then
    begin
      APin := mHit.Pin;
      Result := True;
    end;
  end;
end;

end.
