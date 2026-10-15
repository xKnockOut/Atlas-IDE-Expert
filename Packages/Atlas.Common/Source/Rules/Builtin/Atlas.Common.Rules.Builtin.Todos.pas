unit Atlas.Common.Rules.Builtin.Todos;

// Offene TODO-Einträge als Hinweis-Diagnosen (#68), Regel todo-comment.
// Die Regel ist freiwillig: Sie läuft nur, wenn sie in atlas.json
// eingeschaltet ist (oder im Profil strict), z. B.
//   "rules": { "todo-comment": { "severity": "hint", "keywords": ["TODO", "FIXME", "HACK"] } }
// Der Treffer liegt auf dem ganzen Kommentar; erledigte Einträge ({ DONE … })
// meldet sie nie. Die Option "keywords" stellt die Marken offener Einträge
// ein (Vorgabe TODO und FIXME); sie gilt auch, wenn die Regel aus ist, für
// get_todos, atlas.server.todos und --todos (TTodoRules.Keywords).

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  TodoCommentRuleId = 'todo-comment';
  /// <summary>Name der Option mit den Marken.</summary>
  TodoKeywordsOption = 'keywords';

type
  /// <summary>Meldet jeden offenen TODO-Eintrag.</summary>
  TTodoRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TTodoRules = class
  public
    /// <summary>Marken aus "keywords" in AOptions (JSON-Text des Regelobjekts): nicht leere Texte aus Buchstaben,
    /// in Großbuchstaben; fehlt die Option oder ist sie leer, TODO und FIXME.</summary>
    class function KeywordsFromOptions(const AOptions: string): TArray<string>; static;
    /// <summary>Marken aus "rules" der Einstellungen.</summary>
    class function Keywords(const ASettings: TServerSettings): TArray<string>; static;
    /// <summary>True, wenn AKeyword eine gültige Marke ist (nur Buchstaben, nicht DONE).</summary>
    class function IsValidKeyword(const AKeyword: string): Boolean; static;
  end;

procedure RegisterTodoRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Todos.Scanner,
  Atlas.Common.Todos.Report,
  Atlas.Common.Rules.Engine;

{ TTodoRules }

class function TTodoRules.IsValidKeyword(const AKeyword: string): Boolean;
var
  Ch: Char;
begin
  Result := (AKeyword <> '') and not SameText(AKeyword, TTodos.DoneKeyword);
  if Result then
    for Ch in AKeyword do
      if not CharInSet(Ch, ['A'..'Z', 'a'..'z']) then
        Exit(False);
end;

class function TTodoRules.KeywordsFromOptions(const AOptions: string): TArray<string>;
var
  Value, Keywords, Item: TJSONValue;
begin
  Result := nil;
  if AOptions <> '' then
  begin
    Value := TJSONObject.ParseJSONValue(AOptions);
    try
      if Value is TJSONObject then
      begin
        Keywords := TJSONObject(Value).GetValue(TodoKeywordsOption);
        if Keywords is TJSONArray then
          for Item in TJSONArray(Keywords) do
            if (Item is TJSONString) and IsValidKeyword(Trim(Item.Value)) then
              Result := Result + [UpperCase(Trim(Item.Value))];
      end;
    finally
      Value.Free;
    end;
  end;
  if Length(Result) = 0 then
    Result := TTodos.DefaultKeywords;
end;

class function TTodoRules.Keywords(const ASettings: TServerSettings): TArray<string>;
begin
  Result := KeywordsFromOptions(TRuleEngine.RuleOptions(TodoCommentRuleId, ASettings));
end;

{ TTodoRule }

function TTodoRule.Descriptor: TRuleDescriptor;
begin
  // Freiwillig (#68): läuft nur eingeschaltet, wie die experimentellen Regeln.
  Result := TRuleDescriptor.Create(TodoCommentRuleId, TRuleSeverity.Hint, 'Offener TODO-Kommentar', True);
end;

procedure TTodoRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Entries: TArray<TTodoEntry>;
  Entry: TTodoEntry;
  Keywords: TArray<string>;
begin
  Keywords := TTodoRules.KeywordsFromOptions(AContext.Options);
  if AContext.Tree <> nil then
    Entries := TTodoScanner.FromTokens(AContext.Tree.Tokens, Keywords)
  else
    Entries := TTodoScanner.FromTokens(TPascalLexer.Tokenize(AContext.Text), Keywords);
  for Entry in Entries do
    if not Entry.Done then
      AReport.Add(Entry.Range, TTodoReport.Caption(Entry));
end;

procedure RegisterTodoRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TTodoRule.Create);
end;

end.
