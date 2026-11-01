unit Atlas.UI.Tracker.CiLogin;

// Abfrage des Zugangs zum Build-Server (#763) und zum Issue-Tracker (#765):
// Benutzer und API-Token bzw. nur ein Token, verdeckt eingegeben. Das Token
// wird nie vorbelegt (es steht nur im Anmeldespeicher von Windows) und nach
// dem Lesen im Feld überschrieben. Seit #1455 eigene Unit des Moduls Tracker
// (vorher Teil des Bereichs „Testergebnisse“ der Willkommensseite).

interface

type
  /// <summary>Abfrage von Benutzer und API-Token für „Zugang zum Build-Server hinterlegen …“ (#763); das Token
  /// wird verdeckt eingegeben.</summary>
  TAtlasCiLoginPrompt = class
  public
    /// <summary>AUser vorbelegt; das Token nie (es steht nur im Anmeldespeicher). False bei Abbruch. Beide leer =
    /// Zugang entfernen.</summary>
    class function Ask(const AServer: string; var AUser, AToken: string): Boolean; static;
    /// <summary>Nur ein Token, verdeckt, mit eigenem Titel und eigener Beschriftung (Issue-Tracker, #765). False bei
    /// Abbruch; leer = Zugang entfernen.</summary>
    class function AskToken(const ATitle, ALabel: string; var AToken: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Dialogs,
  Atlas.UI.Tracker.Strings;

const
  // Ein Steuerzeichen am Anfang der Beschriftung lässt InputQuery das Feld verdecken.
  cHidden = #31;

{ TAtlasCiLoginPrompt }

class function TAtlasCiLoginPrompt.Ask(const AServer: string; var AUser, AToken: string): Boolean;
var
  mValues: array of string;
begin
  SetLength(mValues, 2);
  mValues[0] := AUser;
  mValues[1] := '';
  Result := InputQuery(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.CiLoginTitle, [AServer]),
    [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.CiLoginUser),
    cHidden + TAtlasTrackerStrings.Text(TAtlasTrackerTextId.CiLoginToken)], mValues);
  if Result then
  begin
    AUser := Trim(mValues[0]);
    AToken := Trim(mValues[1]);
  end;
  mValues[1] := '';
end;

class function TAtlasCiLoginPrompt.AskToken(const ATitle, ALabel: string; var AToken: string): Boolean;
var
  mValues: array of string;
begin
  SetLength(mValues, 1);
  mValues[0] := '';
  Result := InputQuery(ATitle, [cHidden + ALabel], mValues);
  if Result then
  begin
    AToken := Trim(mValues[0]);
  end;
  mValues[0] := '';
end;

end.
