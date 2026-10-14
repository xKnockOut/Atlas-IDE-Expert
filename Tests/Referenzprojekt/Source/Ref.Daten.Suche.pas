unit Ref.Daten.Suche;

// Kundensuche ohne Datenbank-Units, damit RefApp auch ohne FireDAC übersetzt
// (#94). Das optionale Projekt RefDaten meldet in Ref.Daten.Kunden eine Suche
// über FireDAC an; ohne Anmeldung liefert die Suche nichts.

interface

uses
  System.SysUtils;

type
  TKundenSuche = class
  private
    class var FAnbieter: TFunc<string, TArray<string>>;
  public
    /// <summary>Meldet die Suche an; nil meldet sie ab.</summary>
    class procedure Anmelden(const AAnbieter: TFunc<string, TArray<string>>); static;
    /// <summary>Namen der Kunden, die mit AName beginnen.</summary>
    class function Suchen(const AName: string): TArray<string>; static;
  end;

implementation

class procedure TKundenSuche.Anmelden(const AAnbieter: TFunc<string, TArray<string>>);
begin
  FAnbieter := AAnbieter;
end;

class function TKundenSuche.Suchen(const AName: string): TArray<string>;
begin
  if Assigned(FAnbieter) then
    Result := FAnbieter(AName)
  else
    Result := nil;
end;

end.
