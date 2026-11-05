unit Atlas.Core.Problems.Explanation;

// „Regel erklären“ (#909) im Fenster „Atlas-Prüfung“: Katalogtext einer Regel
// aus der Antwort von atlas.server.settingsCatalog ({"rules": [{"id": …,
// "name": …, "description": …, "bad": …, "good": …, "experimental": …}]}).
// Erklären bleibt in Base (#1755): Es braucht nur den Katalog des Servers,
// nicht die Regeltabelle des Moduls Prüfregeln.

interface

uses
  System.JSON;

type
  /// <summary>Katalogtext einer Regel (atlas.server.settingsCatalog).</summary>
  TAtlasRuleExplanation = record
    Id: string;
    Name: string;
    Description: string;
    Bad: string;
    Good: string;
    Experimental: Boolean;
    /// <summary>Eintrag von ARule (Groß-/Kleinschreibung egal) aus ACatalog (darf nil sein); False ohne ihn.
    /// </summary>
    class function Find(ACatalog: TJSONValue; const ARule: string; out AExplanation: TAtlasRuleExplanation): Boolean;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections;

/// <summary>Eintrag mit "id" = ARule in der Liste "rules" von ACatalog; nil ohne.</summary>
function RuleItem(ACatalog: TJSONValue; const ARule: string): TJSONObject;
var
  mItems, mItem: TJSONValue;
begin
  Result := nil;
  if not (ACatalog is TJSONObject) then
  begin
    Exit;
  end;
  mItems := TJSONObject(ACatalog).GetValue('rules');
  if not (mItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mItems) do
  begin
    if (mItem is TJSONObject) and SameText(TJSONObject(mItem).GetValue<string>('id', ''), ARule) then
    begin
      Exit(TJSONObject(mItem));
    end;
  end;
end;

{ TAtlasRuleExplanation }

class function TAtlasRuleExplanation.Find(ACatalog: TJSONValue; const ARule: string;
  out AExplanation: TAtlasRuleExplanation): Boolean;
var
  mItem: TJSONObject;
begin
  AExplanation := Default(TAtlasRuleExplanation);
  mItem := nil;
  if ARule <> '' then
  begin
    mItem := RuleItem(ACatalog, ARule);
  end;
  Result := mItem <> nil;
  if not Result then
  begin
    Exit;
  end;
  AExplanation.Id := mItem.GetValue<string>('id', '');
  AExplanation.Name := mItem.GetValue<string>('name', '');
  AExplanation.Description := mItem.GetValue<string>('description', '');
  AExplanation.Bad := mItem.GetValue<string>('bad', '');
  AExplanation.Good := mItem.GetValue<string>('good', '');
  AExplanation.Experimental := mItem.GetValue<Boolean>('experimental', False);
end;

end.
