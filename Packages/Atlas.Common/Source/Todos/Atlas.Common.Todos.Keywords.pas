unit Atlas.Common.Todos.Keywords;

// Marken offener TODO-Einträge aus den Einstellungen (#68): Option "keywords" der Regel todo-comment, z. B.
//   "rules": { "todo-comment": { "keywords": ["TODO", "FIXME", "HACK"] } }
// Vorgabe TODO und FIXME. Sie gilt auch, wenn die Regel aus ist: für get_todos, atlas.server.todos, --todos und
// die Begründungen im Hover, die diese Marken nie zeigen.

interface

uses
  Atlas.Common.Configuration.Contract;

const
  /// <summary>Regel, deren Optionen die Marken tragen.</summary>
  cTodoCommentRuleId = 'todo-comment';
  /// <summary>Name der Option mit den Marken.</summary>
  cTodoKeywordsOption = 'keywords';

type
  TTodoKeywords = class abstract
  public
    /// <summary>Marken aus "keywords" in AOptions (JSON-Text des Regelobjekts): nicht leere Texte aus Buchstaben,
    /// in Großbuchstaben; fehlt die Option oder ist sie leer, TODO und FIXME.</summary>
    class function FromOptions(const AOptions: string): TArray<string>; static;
    /// <summary>Marken aus "rules" der Einstellungen.</summary>
    class function FromSettings(const ASettings: TServerSettings): TArray<string>; static;
    /// <summary>True, wenn AKeyword eine gültige Marke ist (nur Buchstaben, nicht DONE).</summary>
    class function IsValid(const AKeyword: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Todos.Contract;

{ TTodoKeywords }

class function TTodoKeywords.FromSettings(const ASettings: TServerSettings): TArray<string>;
begin
  Result := FromOptions(TRuleSetting.OptionsOf(ASettings.Rules, cTodoCommentRuleId));
end;

/// <summary>Gültige Schlüsselwörter aus der Option als JSON-Wert (Array von Strings), in Großbuchstaben.</summary>
function KeywordsFromJson(AKeywords: TJSONValue): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if not (AKeywords is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AKeywords) do
  begin
    if (mItem is TJSONString) and TTodoKeywords.IsValid(Trim(mItem.Value)) then
    begin
      Result := Result + [UpperCase(Trim(mItem.Value))];
    end;
  end;
end;

class function TTodoKeywords.FromOptions(const AOptions: string): TArray<string>;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AOptions <> '' then
  begin
    mValue := TJSONObject.ParseJSONValue(AOptions);
    try
      if mValue is TJSONObject then
      begin
        Result := KeywordsFromJson(TJSONObject(mValue).GetValue(cTodoKeywordsOption));
      end;
    finally
      mValue.Free;
    end;
  end;
  if Length(Result) = 0 then
  begin
    Result := TTodos.DefaultKeywords;
  end;
end;

class function TTodoKeywords.IsValid(const AKeyword: string): Boolean;
var
  mCh: Char;
begin
  Result := (AKeyword <> '') and not SameText(AKeyword, TTodos.cDoneKeyword);
  if Result then
  begin
    for mCh in AKeyword do
    begin
      if not CharInSet(mCh, ['A'..'Z', 'a'..'z']) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

end.
