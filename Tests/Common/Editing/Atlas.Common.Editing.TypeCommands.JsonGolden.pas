unit Atlas.Common.Editing.TypeCommands.JsonGolden;

// Golden-Datei für /json (#298): genau das, was /json aus der Klasse ohne
// ToJson und FromJson erzeugt. Der Test vergleicht die Ausgabe mit dieser
// Datei und prüft mit dem übersetzten Code, dass FromJson(ToJson(X)) gleiche
// Feldwerte ergibt. Nicht von Hand ändern, sondern neu erzeugen.

interface

uses
  System.Generics.Collections,
  System.JSON;

type
  TJsonKunde = class
  public
    FName: string;
    FAlter: Integer;
    FUmsatz: Double;
    FAktiv: Boolean;
  public
    function ToJson: TJSONObject;
    class function FromJson(AJson: TJSONObject): TJsonKunde; static;
  end;

implementation

function TJsonKunde.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('Name', FName);
  Result.AddPair('Alter', TJSONNumber.Create(FAlter));
  Result.AddPair('Umsatz', TJSONNumber.Create(FUmsatz));
  Result.AddPair('Aktiv', TJSONBool.Create(FAktiv));
end;

class function TJsonKunde.FromJson(AJson: TJSONObject): TJsonKunde;
begin
  Result := TJsonKunde.Create;
  Result.FName := AJson.GetValue<string>('Name');
  Result.FAlter := AJson.GetValue<Integer>('Alter');
  Result.FUmsatz := AJson.GetValue<Double>('Umsatz');
  Result.FAktiv := AJson.GetValue<Boolean>('Aktiv');
end;

end.
