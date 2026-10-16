unit Atlas.Core.Settings.RuleTable;

// Tabelle der Prüfregeln im Einstellungsdialog (#227): Zeilen aus dem
// Regelkatalog des Servers (atlas.server.settingsCatalog) und dem Wert von
// "rules" der bearbeiteten Datei. Regeln, die nur in "rules" stehen, kommen
// hinten dazu. Setzen eines Schweregrads behält Optionen einer Regel, die als
// Objekt eingestellt ist: Dann ändert sich nur "severity".

interface

uses
  System.SysUtils,
  System.JSON;

type
  TAtlasRuleRow = record
    Id: string;
    Name: string;
    Category: string;
    /// <summary>Vorgabe des Katalogs, z. B. "warning".</summary>
    DefaultSeverity: string;
    /// <summary>Eingestellter Schweregrad; '' = Vorgabe.</summary>
    Severity: string;
    /// <summary>Die Regel ist als Objekt mit Optionen eingestellt.</summary>
    HasOptions: Boolean;
    /// <summary>Steht im Katalog des Servers.</summary>
    Known: Boolean;
    /// <summary>Im Projekt: Schweregrad aus den globalen Einstellungen; '' = dort nicht gesetzt.</summary>
    GlobalSeverity: string;
  end;

  TAtlasRuleTable = class
  public const
    Severities: array[0..4] of string = ('off', 'hint', 'info', 'warning', 'error');
  public
    /// <summary>ACatalog: Antwort von atlas.server.settingsCatalog (darf nil sein). ARulesJson: Wert von
    /// "rules" ('' ohne).</summary>
    class function Rows(ACatalog: TJSONValue; const ARulesJson: string): TArray<TAtlasRuleRow>; overload; static;
    /// <summary>Wie oben, dazu je Regel der Schweregrad aus "rules" der globalen Datei (AGlobalRulesJson).
    /// Das Projekt übersteuert ihn je Regel.</summary>
    class function Rows(ACatalog: TJSONValue; const ARulesJson, AGlobalRulesJson: string): TArray<TAtlasRuleRow>;
      overload; static;
    /// <summary>Pfad und JSON-Text für TAtlasJsonText, um ASeverity für AId zu setzen ('' = entfernen):
    /// "rules.<id>" oder bei einer Regel mit Optionen "rules.<id>.severity". So ändert sich in der Datei nur
    /// dieser Wert.</summary>
    class procedure SeverityChange(const ARulesJson, AId, ASeverity: string; out APath, AJson: string); static;
    /// <summary>Neuer Wert von "rules" mit ASeverity für AId; '' entfernt die Regel (bei Optionen nur
    /// "severity"). Ergebnis '' für ein leeres Objekt.</summary>
    class function WithSeverity(const ARulesJson, AId, ASeverity: string): string; static;
  end;

implementation

function SeverityOf(AValue: TJSONValue; out AHasOptions: Boolean): string;
begin
  Result := '';
  AHasOptions := AValue is TJSONObject;
  if (AValue is TJSONString) and not (AValue is TJSONNumber) then
    Result := TJSONString(AValue).Value
  else if AHasOptions then
    Result := TJSONObject(AValue).GetValue<string>('severity', '');
end;

{ TAtlasRuleTable }

class function TAtlasRuleTable.Rows(ACatalog: TJSONValue; const ARulesJson,
  AGlobalRulesJson: string): TArray<TAtlasRuleRow>;
var
  Global: TArray<TAtlasRuleRow>;
  Index, Other: Integer;
begin
  Result := Rows(ACatalog, ARulesJson);
  if AGlobalRulesJson = '' then
    Exit;
  Global := Rows(nil, AGlobalRulesJson);
  for Other := 0 to High(Global) do
    for Index := 0 to High(Result) do
      if SameText(Result[Index].Id, Global[Other].Id) then
        Result[Index].GlobalSeverity := Global[Other].Severity;
end;

class function TAtlasRuleTable.Rows(ACatalog: TJSONValue; const ARulesJson: string): TArray<TAtlasRuleRow>;
var
  Rules, Items, Item: TJSONValue;
  Row: TAtlasRuleRow;
  Pair: TJSONPair;
  Index: Integer;
  Found: Boolean;
begin
  Result := nil;
  Rules := nil;
  if ARulesJson <> '' then
    Rules := TJSONObject.ParseJSONValue(ARulesJson);
  try
    Items := nil;
    if ACatalog is TJSONObject then
      Items := TJSONObject(ACatalog).GetValue('rules');
    if Items is TJSONArray then
      for Item in TJSONArray(Items) do
        if Item is TJSONObject then
        begin
          Row := Default(TAtlasRuleRow);
          Row.Id := TJSONObject(Item).GetValue<string>('id', '');
          if Row.Id = '' then
            Continue;
          Row.Name := TJSONObject(Item).GetValue<string>('name', '');
          Row.Category := TJSONObject(Item).GetValue<string>('category', '');
          Row.DefaultSeverity := TJSONObject(Item).GetValue<string>('severity', '');
          Row.Known := True;
          if Rules is TJSONObject then
            Row.Severity := SeverityOf(TJSONObject(Rules).GetValue(Row.Id), Row.HasOptions);
          Result := Result + [Row];
        end;
    // Regeln, die der Katalog nicht kennt (oder ohne Server): trotzdem zeigen.
    if Rules is TJSONObject then
      for Pair in TJSONObject(Rules) do
      begin
        Found := False;
        for Index := 0 to High(Result) do
          if SameText(Result[Index].Id, Pair.JsonString.Value) then
            Found := True;
        if Found then
          Continue;
        Row := Default(TAtlasRuleRow);
        Row.Id := Pair.JsonString.Value;
        Row.Severity := SeverityOf(Pair.JsonValue, Row.HasOptions);
        Result := Result + [Row];
      end;
  finally
    Rules.Free;
  end;
end;

class procedure TAtlasRuleTable.SeverityChange(const ARulesJson, AId, ASeverity: string; out APath,
  AJson: string);
var
  Value, Existing: TJSONValue;
begin
  APath := 'rules.' + AId;
  Value := nil;
  if ARulesJson <> '' then
    Value := TJSONObject.ParseJSONValue(ARulesJson);
  try
    Existing := nil;
    if Value is TJSONObject then
      Existing := TJSONObject(Value).GetValue(AId);
    if Existing is TJSONObject then
      APath := APath + '.severity';
  finally
    Value.Free;
  end;
  AJson := '';
  if ASeverity <> '' then
    AJson := '"' + ASeverity + '"';
end;

class function TAtlasRuleTable.WithSeverity(const ARulesJson, AId, ASeverity: string): string;
var
  Value: TJSONValue;
  Rules: TJSONObject;
  Existing: TJSONValue;
  Pair: TJSONPair;
begin
  Value := nil;
  if ARulesJson <> '' then
    Value := TJSONObject.ParseJSONValue(ARulesJson);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    Value := TJSONObject.Create;
  end;
  Rules := TJSONObject(Value);
  try
    Existing := Rules.GetValue(AId);
    if Existing is TJSONObject then
    begin
      // Optionen bleiben; nur der Schweregrad wechselt.
      Pair := TJSONObject(Existing).RemovePair('severity');
      Pair.Free;
      if ASeverity <> '' then
        TJSONObject(Existing).AddPair('severity', ASeverity);
    end
    else
    begin
      Pair := Rules.RemovePair(AId);
      Pair.Free;
      if ASeverity <> '' then
        Rules.AddPair(AId, ASeverity);
    end;
    if Rules.Count = 0 then
      Result := ''
    else
      Result := Rules.ToJSON;
  finally
    Rules.Free;
  end;
end;

end.
