unit Atlas.Core.Rules.CustomLayer;

// Assistent „Eigene Prüfregel“ in Datei › Neu › Weitere (#1821), ohne VCL und
// Open Tools API. Eigene Regeln schreibt man in Atlas als Schichtregel der
// Prüfregel forbidden-uses ("layers": je Regel "from", "deny", "allow"; ohne
// "deny" meldet sie nichts). NewLayer hängt an "rules" der Projektdatei eine
// neue Schicht an, deren "from" den Namensraum der Unit im Editor trifft
// (LayerFrom), und liefert Pfad und JSON für TAtlasProjectSettings.WriteValue;
// danach öffnet die IDE-Schicht den Regel-Editor bei forbidden-uses.

interface

type
  TAtlasCustomLayer = class
  public const
    /// <summary>Prüfregel mit den eigenen Schichtregeln.</summary>
    cRuleId = 'forbidden-uses';
  public
    /// <summary>Glob auf den Namensraum von AUnitName (Kunden.Logik.Engine → Kunden.Logik.*); ohne Punkt der Name
    /// selbst, ohne Unit '*'.</summary>
    class function LayerFrom(const AUnitName: string): string; static;
    /// <summary>Neue Schicht {"from": AFrom, "deny": [], "allow": []} hinter den vorhandenen von forbidden-uses in
    /// ARulesJson (Wert von "rules", '' = keiner). APath: Schlüssel der Regel ("rules.forbidden-uses"), AJson: ihr
    /// neuer Wert (Schweregrad und übrige Optionen bleiben); Ergebnis: Stelle der neuen Schicht.</summary>
    class function NewLayer(const ARulesJson, AFrom: string; out APath, AJson: string): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

class function TAtlasCustomLayer.LayerFrom(const AUnitName: string): string;
var
  mDot: Integer;
begin
  Result := Trim(AUnitName);
  if Result = '' then
  begin
    Exit('*');
  end;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, 1, mDot) + '*';
  end;
end;

/// <summary>Objekt der Regel aus ARules (Text wird zu {"severity": Text}); neu, wenn sie fehlt. Der Aufrufer
/// gibt es frei.</summary>
function RuleCopy(ARules: TJSONValue): TJSONObject;
var
  mExisting: TJSONValue;
begin
  mExisting := nil;
  if ARules is TJSONObject then
  begin
    mExisting := TJSONObject(ARules).GetValue(TAtlasCustomLayer.cRuleId);
  end;
  if mExisting is TJSONObject then
  begin
    Exit(TJSONObject(mExisting.Clone));
  end;
  Result := TJSONObject.Create;
  // TJSONNumber erbt von TJSONString.
  if (mExisting is TJSONString) and not (mExisting is TJSONNumber) then
  begin
    Result.AddPair('severity', TJSONString(mExisting).Value);
  end;
end;

function NewLayerObject(const AFrom: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('from', AFrom);
  Result.AddPair('deny', TJSONArray.Create);
  Result.AddPair('allow', TJSONArray.Create);
end;

class function TAtlasCustomLayer.NewLayer(const ARulesJson, AFrom: string; out APath, AJson: string): Integer;
var
  mRules: TJSONValue;
  mRule: TJSONObject;
  mLayers: TJSONArray;
  mExisting: TJSONValue;
  mPair: TJSONPair;
begin
  APath := 'rules.' + cRuleId;
  mRules := nil;
  if Trim(ARulesJson) <> '' then
  begin
    mRules := TJSONObject.ParseJSONValue(ARulesJson);
  end;
  try
    mRule := RuleCopy(mRules);
  finally
    mRules.Free;
  end;
  try
    mExisting := mRule.GetValue('layers');
    if mExisting is TJSONArray then
    begin
      mLayers := TJSONArray(mExisting);
    end
    else
    begin
      mPair := mRule.RemovePair('layers');
      mPair.Free;
      mLayers := TJSONArray.Create;
      mRule.AddPair('layers', mLayers);
    end;
    mLayers.AddElement(NewLayerObject(AFrom));
    Result := mLayers.Count - 1;
    AJson := mRule.ToJSON;
  finally
    mRule.Free;
  end;
end;

end.
