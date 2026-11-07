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
  System.Generics.Collections,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TValidationText = (NotAValidJSONObject, Line);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TValidationText] of string = (
    ('Kein gültiges JSON-Objekt',
     'Zeile %d: %s'),
    ('Not a valid JSON object',
     'Line %d: %s'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TValidationText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

{ TAtlasSettingIssue }

function TAtlasSettingIssue.Text: string;
begin
  if Line >= 0 then
  begin
    Result := Format(UiText(TValidationText.Line), [Line + 1, Message]);
  end
  else
  begin
    Result := Message;
  end;
end;

{ TAtlasSettingsValidation }

class function TAtlasSettingsValidation.FromAnswer(AAnswer: TJSONValue; out AIssues: TArray<TAtlasSettingIssue>;
  out AValid: Boolean): Boolean;
var
  mValid, mItems, mItem, mError: TJSONValue;
  mIssue: TAtlasSettingIssue;
begin
  AIssues := nil;
  AValid := False;
  Result := False;
  if not (AAnswer is TJSONObject) then
  begin
    Exit;
  end;
  mValid := TJSONObject(AAnswer).GetValue('valid');
  if not (mValid is TJSONBool) then
  begin
    Exit;
  end;
  Result := True;
  AValid := TJSONBool(mValid).AsBoolean;
  mItems := TJSONObject(AAnswer).GetValue('issues');
  if mItems is TJSONArray then
  begin
    for mItem in TJSONArray(mItems) do
    begin
      if mItem is TJSONObject then
      begin
        mIssue := Default(TAtlasSettingIssue);
        mIssue.Line := TJSONObject(mItem).GetValue<Integer>('line', -1);
        mIssue.Character := TJSONObject(mItem).GetValue<Integer>('character', -1);
        mIssue.Message := TJSONObject(mItem).GetValue<string>('message', '');
        mError := TJSONObject(mItem).GetValue('error');
        mIssue.Error := (mError is TJSONBool) and TJSONBool(mError).AsBoolean;
        AIssues := AIssues + [mIssue];
      end;
    end;
  end;
end;

class function TAtlasSettingsValidation.Syntax(const AText: string; out AIssues: TArray<TAtlasSettingIssue>): Boolean;
var
  mRoot: TJSONObject;
  mIssue: TAtlasSettingIssue;
begin
  AIssues := nil;
  if Trim(AText) = '' then
  begin
    Exit(True);
  end;
  mRoot := TAtlasJsonText.Parse(AText);
  Result := mRoot <> nil;
  mRoot.Free;
  if not Result then
  begin
    mIssue := Default(TAtlasSettingIssue);
    mIssue.Line := -1;
    mIssue.Character := -1;
    mIssue.Message := UiText(TValidationText.NotAValidJSONObject);
    mIssue.Error := True;
    AIssues := [mIssue];
  end;
end;

class function TAtlasSettingsValidation.Lines(const AIssues: TArray<TAtlasSettingIssue>): TArray<string>;
var
  mIssue: TAtlasSettingIssue;
begin
  Result := nil;
  for mIssue in AIssues do
  begin
    if mIssue.Error then
    begin
      Result := Result + [mIssue.Text];
    end;
  end;
  for mIssue in AIssues do
  begin
    if not mIssue.Error then
    begin
      Result := Result + [mIssue.Text];
    end;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Settings.Validation', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
