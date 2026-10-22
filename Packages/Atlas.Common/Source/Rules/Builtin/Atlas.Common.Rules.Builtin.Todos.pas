unit Atlas.Common.Rules.Builtin.Todos;

// Offene TODO-Einträge als Hinweis-Diagnosen (#68), Regel todo-comment.
// Die Regel ist freiwillig: Sie läuft nur, wenn sie in atlas.json
// eingeschaltet ist (oder im Profil strict), z. B.
//   "rules": { "todo-comment": { "severity": "hint", "keywords": ["TODO", "FIXME", "HACK"] } }
// Der Treffer liegt auf dem ganzen Kommentar; erledigte Einträge ({ DONE … })
// meldet sie nie. Die Option "keywords" stellt die Marken offener Einträge
// ein (Vorgabe TODO und FIXME); sie gilt auch, wenn die Regel aus ist, für
// get_todos, atlas.server.todos und --todos (TTodoRules.Keywords).
//
// commented-out-code (#942): mindestens "minLines" (Vorgabe 3) aufeinander-
// folgende Kommentarzeilen (// je Zeile oder ein mehrzeiliger { }-Kommentar),
// die sich als Anweisungen, Deklarationen oder Klassenmitglieder parsen
// lassen. Prosa am Anfang und Ende des Blocks bleibt außen vor; mindestens
// die Hälfte der Zeilen muss nach Code aussehen (;, :=, begin, end, then, do).
// XMLDoc (///), Beispiele in <code> oder hinter einer Prosazeile mit
// Doppelpunkt ("so sieht es aus:") und Kommentare vor dem ersten Token
// (Lizenzköpfe) bleiben stumm. Korrektur: die Zeilen entfernen.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  TodoCommentRuleId = 'todo-comment';
  CommentedOutCodeRuleId = 'commented-out-code';
  /// <summary>Name der Option mit den Marken.</summary>
  TodoKeywordsOption = 'keywords';

type
  /// <summary>Meldet jeden offenen TODO-Eintrag.</summary>
  TTodoRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  /// <summary>Meldet Blöcke auskommentierten Codes (#942).</summary>
  TCommentedOutCodeRule = class(TInterfacedObject, IRule)
  public const
    DefaultMinLines = 3;
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Lassen sich ALines (Kommentarinhalt ohne //) als Pascal parsen: Anweisungen, Deklarationen
    /// oder Klassenmitglieder?</summary>
    class function ParsesAsCode(const ALines: TArray<string>): Boolean; static;
    /// <summary>Sieht die Zeile nach Code aus: endet auf ;, enthält := oder ist ein Blockwort?</summary>
    class function LooksLikeCode(const ALine: string): Boolean; static;
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
  System.StrUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Rules.Options,
  Atlas.Text.Lines,
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

type
  // Eine Kommentarzeile: Zeilennummer, Inhalt ohne Kommentarzeichen, Bereich des Tokens.
  TCommentLine = record
    Line: Integer;
    Text: string;
    Range: TTextRange;
  end;

{ TCommentedOutCodeRule }

function TCommentedOutCodeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(CommentedOutCodeRuleId, TRuleSeverity.Hint, 'Auskommentierter Code');
end;

class function TCommentedOutCodeRule.LooksLikeCode(const ALine: string): Boolean;
const
  BlockWords: array[0..9] of string = ('begin', 'end', 'end;', 'try', 'finally', 'except', 'else', 'repeat',
    'end.', 'end else');
  LastWords: array[0..4] of string = ('then', 'do', 'begin', 'of', 'else');
var
  Line, Last: string;
  Space: Integer;
begin
  Line := Trim(ALine);
  if Line = '' then
    Exit(False);
  if EndsStr(';', Line) or (Pos(':=', Line) > 0) or MatchText(Line, BlockWords) then
    Exit(True);
  Space := LastDelimiter(' ', Line);
  Last := Copy(Line, Space + 1, MaxInt);
  Result := (Space > 0) and MatchText(Last, LastWords);
end;

class function TCommentedOutCodeRule.ParsesAsCode(const ALines: TArray<string>): Boolean;
const
  Wrappers: array[0..2, 0..1] of string = (
    ('unit X;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10, #10'end;'#10'end.'),
    ('unit X;'#10'interface'#10'implementation'#10, #10'end.'),
    ('unit X;'#10'interface'#10'type'#10'  T = class'#10, #10'  end;'#10'implementation'#10'end.'));
var
  Code: string;
  Index: Integer;
  Tree: TSyntaxTree;
begin
  Code := string.Join(#10, ALines);
  for Index := Low(Wrappers) to High(Wrappers) do
  begin
    Tree := TSyntaxTreeCache.Parse(Wrappers[Index, 0] + Code + Wrappers[Index, 1]);
    try
      if Length(Tree.Diagnostics) = 0 then
        Exit(True);
    finally
      Tree.Free;
    end;
  end;
  Result := False;
end;

procedure TCommentedOutCodeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  MinLines: Integer;
  Run: TArray<TCommentLine>;

  // Sind die Zeilen nach Abzug der Prosa am Anfang und Ende Code? AFirst/ALast: der Codeteil.
  function IsCode(const ALines: TArray<TCommentLine>; out AFirst, ALast: Integer): Boolean;
  var
    Index, Signals, Previous: Integer;
    Texts: TArray<string>;
  begin
    Result := False;
    AFirst := 0;
    ALast := High(ALines);
    while (AFirst <= ALast) and not LooksLikeCode(ALines[AFirst].Text) do
      Inc(AFirst);
    while (ALast >= AFirst) and not LooksLikeCode(ALines[ALast].Text) do
      Dec(ALast);
    if ALast - AFirst + 1 < MinLines then
      Exit;
    // Beispiel in der Dokumentation: <code> im Kommentar oder eingeleitet von „…:“.
    for Index := 0 to High(ALines) do
      if ContainsText(ALines[Index].Text, '<code') then
        Exit;
    Previous := AFirst - 1;
    while (Previous >= 0) and (Trim(ALines[Previous].Text) = '') do
      Dec(Previous);
    if (Previous >= 0) and EndsStr(':', Trim(ALines[Previous].Text)) then
      Exit;
    Texts := nil;
    Signals := 0;
    for Index := AFirst to ALast do
    begin
      Texts := Texts + [ALines[Index].Text];
      if LooksLikeCode(ALines[Index].Text) then
        Inc(Signals);
    end;
    Result := (Signals * 2 >= Length(Texts)) and ParsesAsCode(Texts);
  end;

  procedure Report(const ARange: TTextRange; ACount, AFirstLine, ALastLine: Integer);
  begin
    AReport.Add(ARange, Format('%d Zeilen auskommentierter Code; die Versionsverwaltung bewahrt ihn auf.',
      [ACount]), TRuleConfidence.Medium, [TRuleFix.Create('Auskommentierten Code entfernen',
      [TRuleEdit.Create(TTextRange.Create(AFirstLine, 0, ALastLine + 1, 0), '')])]);
  end;

  // Aufeinanderfolgende //-Zeilen: nur der Codeteil wird gemeldet und entfernt.
  procedure Flush;
  var
    First, Last: Integer;
  begin
    if (Length(Run) >= MinLines) and IsCode(Run, First, Last) then
      Report(TTextRange.Create(Run[First].Range.StartPos, Run[Last].Range.EndPos), Last - First + 1,
        Run[First].Line, Run[Last].Line);
    Run := nil;
  end;

  // Steht das Token als Erstes in seiner Zeile?
  function FirstInLine(AIndex: Integer): Boolean;
  begin
    Result := (AIndex = 0) or (Tokens[AIndex - 1].EndPos.Line < Tokens[AIndex].StartPos.Line);
  end;

  // Mehrzeiliger { }- bzw. (* *)-Kommentar: jede Zeile des Inhalts für sich; entfernt wird der ganze Kommentar.
  procedure JudgeBlock(AIndex: Integer);
  var
    Token: TPascalToken;
    Inner: string;
    Parts: TArray<string>;
    Lines: TArray<TCommentLine>;
    Index, First, Last: Integer;
    Item: TCommentLine;
  begin
    Token := Tokens[AIndex];
    if StartsStr('(*', Token.Text) then
      Inner := Copy(Token.Text, 3, Length(Token.Text) - 4)
    else
      Inner := Copy(Token.Text, 2, Length(Token.Text) - 2);
    Parts := TTextLines.SplitLines(Inner);
    Lines := nil;
    for Index := 0 to High(Parts) do
    begin
      Item.Line := Token.StartPos.Line + Index;
      Item.Text := Parts[Index];
      Item.Range := TTextRange.Create(Token.StartPos, Token.EndPos);
      Lines := Lines + [Item];
    end;
    // Nur wenn der Kommentar allein in seinen Zeilen steht, lässt er sich zeilenweise entfernen.
    if not FirstInLine(AIndex) or ((AIndex < High(Tokens)) and
      (Tokens[AIndex + 1].StartPos.Line = Token.EndPos.Line)) then
      Exit;
    if IsCode(Lines, First, Last) then
      Report(TTextRange.Create(Token.StartPos, Token.EndPos), Last - First + 1, Token.StartPos.Line,
        Token.EndPos.Line);
  end;

var
  Index, FirstCode: Integer;
  Token: TPascalToken;
  Item: TCommentLine;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  MinLines := TRuleOptions.Int(AContext.Options, 'minLines', DefaultMinLines);
  if MinLines < 1 then
    MinLines := DefaultMinLines;
  // Kommentare vor dem ersten Token sind der Dateikopf (Lizenz, Beschreibung).
  FirstCode := 0;
  while (FirstCode <= High(Tokens)) and (Tokens[FirstCode].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
    Inc(FirstCode);
  Run := nil;
  for Index := FirstCode to High(Tokens) do
  begin
    Token := Tokens[Index];
    if (Token.Kind <> TPascalTokenKind.Comment) or not FirstInLine(Index) then
    begin
      Flush;
      Continue;
    end;
    if StartsStr('//', Token.Text) then
    begin
      // XMLDoc bleibt stumm.
      if StartsStr('///', Token.Text) then
      begin
        Flush;
        Continue;
      end;
      if (Run <> nil) and (Run[High(Run)].Line + 1 <> Token.StartPos.Line) then
        Flush;
      Item.Line := Token.StartPos.Line;
      Item.Text := Copy(Token.Text, 3, MaxInt);
      Item.Range := TTextRange.Create(Token.StartPos, Token.EndPos);
      Run := Run + [Item];
    end
    else
    begin
      Flush;
      if Token.EndPos.Line > Token.StartPos.Line then
        JudgeBlock(Index);
    end;
  end;
  Flush;
end;

procedure RegisterTodoRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TTodoRule.Create);
  ARegistry.Register(TCommentedOutCodeRule.Create);
end;

end.
