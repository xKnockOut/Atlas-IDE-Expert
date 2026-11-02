unit Atlas.Core.Completion.Width;

// Breite des Vervollständigungs-Popups (#416) ohne Fenster: Die Liste wird so
// breit wie ihr breitester sichtbarer Eintrag, innerhalb fester Grenzen. Sie
// wächst sofort, schrumpft während einer Sitzung aber nicht (sonst springt
// das Popup beim Filtern von "A" zu "Add"). Eine von Hand gezogene Breite hat
// Vorrang vor der Automatik; 0 heißt automatisch. Liste und Detailpanel haben
// eigene Grenzen. Alle Werte in logischen Pixeln, Skalieren macht das Fenster.

interface

type
  TAtlasPopupWidth = class
  public const
    MinListWidth = 280;
    MaxListWidth = 720;
    MinPanelWidth = 220;
    MaxPanelWidth = 600;
  public
    /// <summary>AMeasured in die Grenzen AMin bis AMax.</summary>
    class function Fit(AMeasured, AMin, AMax: Integer): Integer; static;
    /// <summary>Breite der Sitzung nach einer neuen Messung: nur wachsen, nie schrumpfen.</summary>
    class function Grow(ASession, AMeasured: Integer): Integer; static;
    /// <summary>Gezogene Breite AManual, wenn gesetzt (größer 0), sonst die automatische AAuto.</summary>
    class function Effective(AManual, AAuto: Integer): Integer; static;
  end;

implementation

uses
  System.Math;

{ TAtlasPopupWidth }

class function TAtlasPopupWidth.Fit(AMeasured, AMin, AMax: Integer): Integer;
begin
  Result := EnsureRange(AMeasured, AMin, AMax);
end;

class function TAtlasPopupWidth.Grow(ASession, AMeasured: Integer): Integer;
begin
  Result := Max(ASession, AMeasured);
end;

class function TAtlasPopupWidth.Effective(AManual, AAuto: Integer): Integer;
begin
  Result := AAuto;
  if AManual > 0 then
    Result := AManual;
end;

end.
