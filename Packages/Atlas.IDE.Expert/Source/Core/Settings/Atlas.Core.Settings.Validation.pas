unit Atlas.Core.Settings.Validation;

// Prüfung der Einstellungen vor dem Speichern (#227): Der Server prüft den
// Text mit demselben Parser wie beim Laden (atlas.server.checkSettings);
// FromAnswer liest seine Antwort. Ohne Server bleibt nur die Syntaxprüfung
// (Syntax), und der Dialog sagt, dass die Inhalte ungeprüft sind.

interface

uses
  System.SysUtils,
  System.JSON;

type
  TAtlasSettingIssue = record
    /// <summary>Zeile und Zeichen ab 0; -1 ohne Stelle.</summary>
    Line: Integer;
    Character: Integer;
    Message: string;
    /// <summary>Fehler verhindert das Speichern; sonst nur Hinweis.</summary>
    Error: Boolean;
    /// <summary>"Zeile 3: Meldung" (Zeile ab 1) bzw. nur die Meldung.</summary>
    function Text: string;
  end;

  TAtlasSettingsValidation = class
  public
    /// <summary>Liest {"valid", "issues"}; False ohne gültige Antwort (kein Server, alter Server).</summary>
    class function FromAnswer(AAnswer: TJSONValue; out AIssues: TArray<TAtlasSettingIssue>;
      out AValid: Boolean): Boolean; static;
    /// <summary>Nur Syntax (JSON mit Kommentaren); True, wenn der Text ein Objekt oder leer ist.</summary>
    class function Syntax(const AText: string; out AIssues: TArray<TAtlasSettingIssue>): Boolean; static;
    /// <summary>Fehler zuerst, als Zeilen für eine Meldung.</summary>
    class function Lines(const AIssues: TArray<TAtlasSettingIssue>): TArray<string>; static;
  end;

implementation

uses
  Atlas.Core.Settings.JsonText;

{ TAtlasSettingIssue }

function TAtlasSettingIssue.Text: string;
begin
  if Line >= 0 then
    Result := Format('Zeile %d: %s', [Line + 1, Message])
  else
    Result := Message;
end;

{ TAtlasSettingsValidation }

class function TAtlasSettingsValidation.FromAnswer(AAnswer: TJSONValue; out AIssues: TArray<TAtlasSettingIssue>;
  out AValid: Boolean): Boolean;
var
  Valid, Items, Item, Error: TJSONValue;
  Issue: TAtlasSettingIssue;
begin
  AIssues := nil;
  AValid := False;
  Result := False;
  if not (AAnswer is TJSONObject) then
    Exit;
  Valid := TJSONObject(AAnswer).GetValue('valid');
  if not (Valid is TJSONBool) then
    Exit;
  Result := True;
  AValid := TJSONBool(Valid).AsBoolean;
  Items := TJSONObject(AAnswer).GetValue('issues');
  if Items is TJSONArray then
    for Item in TJSONArray(Items) do
      if Item is TJSONObject then
      begin
        Issue := Default(TAtlasSettingIssue);
        Issue.Line := TJSONObject(Item).GetValue<Integer>('line', -1);
        Issue.Character := TJSONObject(Item).GetValue<Integer>('character', -1);
        Issue.Message := TJSONObject(Item).GetValue<string>('message', '');
        Error := TJSONObject(Item).GetValue('error');
        Issue.Error := (Error is TJSONBool) and TJSONBool(Error).AsBoolean;
        AIssues := AIssues + [Issue];
      end;
end;

class function TAtlasSettingsValidation.Syntax(const AText: string; out AIssues: TArray<TAtlasSettingIssue>): Boolean;
var
  Root: TJSONObject;
  Issue: TAtlasSettingIssue;
begin
  AIssues := nil;
  if Trim(AText) = '' then
    Exit(True);
  Root := TAtlasJsonText.Parse(AText);
  Result := Root <> nil;
  Root.Free;
  if not Result then
  begin
    Issue := Default(TAtlasSettingIssue);
    Issue.Line := -1;
    Issue.Character := -1;
    Issue.Message := 'Kein gültiges JSON-Objekt';
    Issue.Error := True;
    AIssues := [Issue];
  end;
end;

class function TAtlasSettingsValidation.Lines(const AIssues: TArray<TAtlasSettingIssue>): TArray<string>;
var
  Issue: TAtlasSettingIssue;
begin
  Result := nil;
  for Issue in AIssues do
    if Issue.Error then
      Result := Result + [Issue.Text];
  for Issue in AIssues do
    if not Issue.Error then
      Result := Result + [Issue.Text];
end;

end.
