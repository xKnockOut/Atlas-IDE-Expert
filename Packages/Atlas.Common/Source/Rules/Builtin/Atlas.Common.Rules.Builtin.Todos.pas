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
  cTodoCommentRuleId = 'todo-comment';
  cCommentedOutCodeRuleId = 'commented-out-code';
  /// <summary>Name der Option mit den Marken.</summary>
  cTodoKeywordsOption = 'keywords';

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
    cDefaultMinLines = 3;
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
  System.Generics.Collections,
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
  Atlas.Common.Rules.Engine,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTodosText = (TodoTitle, CommentedTitle, Commented, RemoveCommented);

const
  cTexts: array[TTodosText] of TAtlasText = (
    (De: 'Offener TODO-Kommentar'; En: 'Open TODO comment'),
    (De: 'Auskommentierter Code'; En: 'Commented-out code'),
    (De: '%d Zeilen auskommentierter Code; die Versionsverwaltung bewahrt ihn auf.';
     En: '%d lines of commented-out code; version control keeps it.'),
    (De: 'Auskommentierten Code entfernen'; En: 'Remove commented-out code'));

{$SCOPEDENUMS OFF}

{ TTodoRules }

class function TTodoRules.IsValidKeyword(const AKeyword: string): Boolean;
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
    if (mItem is TJSONString) and TTodoRules.IsValidKeyword(Trim(mItem.Value)) then
    begin
      Result := Result + [UpperCase(Trim(mItem.Value))];
    end;
  end;
end;

class function TTodoRules.KeywordsFromOptions(const AOptions: string): TArray<string>;
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

class function TTodoRules.Keywords(const ASettings: TServerSettings): TArray<string>;
begin
  Result := KeywordsFromOptions(TRuleEngine.RuleOptions(cTodoCommentRuleId, ASettings));
end;

{ TTodoRule }

function TTodoRule.Descriptor: TRuleDescriptor;
begin
  // Freiwillig (#68): läuft nur eingeschaltet, wie die experimentellen Regeln.
  Result := TRuleDescriptor.Create(cTodoCommentRuleId, TRuleSeverity.Hint, cTexts[TTodosText.TodoTitle].Text);
end;

procedure TTodoRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mEntries: TArray<TTodoEntry>;
  mEntry: TTodoEntry;
  mKeywords: TArray<string>;
begin
  mKeywords := TTodoRules.KeywordsFromOptions(AContext.Options);
  if AContext.Tree <> nil then
  begin
    mEntries := TTodoScanner.FromTokens(AContext.Tree.Tokens, mKeywords);
  end
  else
  begin
    mEntries := TTodoScanner.FromTokens(TPascalLexer.Tokenize(AContext.Text), mKeywords);
  end;
  for mEntry in mEntries do
  begin
    if not mEntry.Done then
    begin
      AReport.Add(mEntry.Range, TTodoReport.Caption(mEntry));
    end;
  end;
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
  Result := TRuleDescriptor.Create(cCommentedOutCodeRuleId, TRuleSeverity.Hint, cTexts[TTodosText.CommentedTitle].Text);
end;

class function TCommentedOutCodeRule.LooksLikeCode(const ALine: string): Boolean;
const
  cBlockWords: array[0..9] of string = ('begin', 'end', 'end;', 'try', 'finally', 'except', 'else', 'repeat',
    'end.', 'end else');
  cLastWords: array[0..4] of string = ('then', 'do', 'begin', 'of', 'else');
var
  mLine, mLast: string;
  mSpace: Integer;
begin
  mLine := Trim(ALine);
  if mLine = '' then
  begin
    Exit(False);
  end;
  if EndsStr(';', mLine) or (Pos(':=', mLine) > 0) or MatchText(mLine, cBlockWords) then
  begin
    Exit(True);
  end;
  mSpace := LastDelimiter(' ', mLine);
  mLast := Copy(mLine, mSpace + 1, MaxInt);
  Result := (mSpace > 0) and MatchText(mLast, cLastWords);
end;

class function TCommentedOutCodeRule.ParsesAsCode(const ALines: TArray<string>): Boolean;
const
  cWrappers: array[0..2, 0..1] of string = (
    ('unit X;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10, #10'end;'#10'end.'),
    ('unit X;'#10'interface'#10'implementation'#10, #10'end.'),
    ('unit X;'#10'interface'#10'type'#10'  T = class'#10, #10'  end;'#10'implementation'#10'end.'));
var
  mCode: string;
  mIndex: Integer;
  mTree: TSyntaxTree;
begin
  mCode := string.Join(#10, ALines);
  for mIndex := Low(cWrappers) to High(cWrappers) do
  begin
    mTree := TSyntaxTreeCache.Parse(cWrappers[mIndex, 0] + mCode + cWrappers[mIndex, 1]);
    try
      if Length(mTree.Diagnostics) = 0 then
      begin
        Exit(True);
      end;
    finally
      mTree.Free;
    end;
  end;
  Result := False;
end;

procedure TCommentedOutCodeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mMinLines: Integer;
  mRun: TArray<TCommentLine>;

  // Sind die Zeilen nach Abzug der Prosa am Anfang und Ende Code? AFirst/ALast: der Codeteil.
  function IsCode(const ALines: TArray<TCommentLine>; out AFirst, ALast: Integer): Boolean;
  var
    mIndex, mSignals, mPrevious: Integer;
    mTexts: TArray<string>;
  begin
    Result := False;
    AFirst := 0;
    ALast := High(ALines);
    while (AFirst <= ALast) and not LooksLikeCode(ALines[AFirst].Text) do
    begin
      Inc(AFirst);
    end;
    while (ALast >= AFirst) and not LooksLikeCode(ALines[ALast].Text) do
    begin
      Dec(ALast);
    end;
    if ALast - AFirst + 1 < mMinLines then
    begin
      Exit;
    end;
    // Beispiel in der Dokumentation: <code> im Kommentar oder eingeleitet von „…:“.
    for mIndex := 0 to High(ALines) do
    begin
      if ContainsText(ALines[mIndex].Text, '<code') then
      begin
        Exit;
      end;
    end;
    mPrevious := AFirst - 1;
    while (mPrevious >= 0) and (Trim(ALines[mPrevious].Text) = '') do
    begin
      Dec(mPrevious);
    end;
    if (mPrevious >= 0) and EndsStr(':', Trim(ALines[mPrevious].Text)) then
    begin
      Exit;
    end;
    mTexts := nil;
    mSignals := 0;
    for mIndex := AFirst to ALast do
    begin
      mTexts := mTexts + [ALines[mIndex].Text];
      if LooksLikeCode(ALines[mIndex].Text) then
      begin
        Inc(mSignals);
      end;
    end;
    Result := (mSignals * 2 >= Length(mTexts)) and ParsesAsCode(mTexts);
  end;

  procedure Report(const ARange: TTextRange; ACount, AFirstLine, ALastLine: Integer);
  begin
    AReport.Add(ARange, cTexts[TTodosText.Commented].Fmt(
      [ACount]), TRuleConfidence.Medium, [TRuleFix.Create(cTexts[TTodosText.RemoveCommented].Text,
      [TRuleEdit.Create(TTextRange.Create(AFirstLine, 0, ALastLine + 1, 0), '')])]);
  end;

  // Aufeinanderfolgende //-Zeilen: nur der Codeteil wird gemeldet und entfernt.
  procedure Flush;
  var
    mFirst, mLast: Integer;
  begin
    if (Length(mRun) >= mMinLines) and IsCode(mRun, mFirst, mLast) then
    begin
      Report(TTextRange.Create(mRun[mFirst].Range.StartPos, mRun[mLast].Range.EndPos), mLast - mFirst + 1,
        mRun[mFirst].Line, mRun[mLast].Line);
    end;
    mRun := nil;
  end;

  // Steht das Token als Erstes in seiner Zeile?
  function FirstInLine(AIndex: Integer): Boolean;
  begin
    Result := (AIndex = 0) or (mTokens[AIndex - 1].EndPos.Line < mTokens[AIndex].StartPos.Line);
  end;

  // Mehrzeiliger { }- bzw. (* *)-Kommentar: jede Zeile des Inhalts für sich; entfernt wird der ganze Kommentar.
  procedure JudgeBlock(AIndex: Integer);
  var
    mToken: TPascalToken;
    mInner: string;
    mParts: TArray<string>;
    mLines: TArray<TCommentLine>;
    mIndex, mFirst, mLast: Integer;
    mItem: TCommentLine;
  begin
    mToken := mTokens[AIndex];
    if StartsStr('(*', mToken.Text) then
    begin
      mInner := Copy(mToken.Text, 3, Length(mToken.Text) - 4);
    end
    else
    begin
      mInner := Copy(mToken.Text, 2, Length(mToken.Text) - 2);
    end;
    mParts := TTextLines.SplitLines(mInner);
    mLines := nil;
    for mIndex := 0 to High(mParts) do
    begin
      mItem.Line := mToken.StartPos.Line + mIndex;
      mItem.Text := mParts[mIndex];
      mItem.Range := TTextRange.Create(mToken.StartPos, mToken.EndPos);
      mLines := mLines + [mItem];
    end;
    // Nur wenn der Kommentar allein in seinen Zeilen steht, lässt er sich zeilenweise entfernen.
    if not FirstInLine(AIndex) or ((AIndex < High(mTokens)) and
      (mTokens[AIndex + 1].StartPos.Line = mToken.EndPos.Line)) then
    begin
      Exit;
    end;
    if IsCode(mLines, mFirst, mLast) then
    begin
      Report(TTextRange.Create(mToken.StartPos, mToken.EndPos), mLast - mFirst + 1, mToken.StartPos.Line,
        mToken.EndPos.Line);
    end;
  end;

  // Zeilenkommentar: an den laufenden Block anhängen bzw. einen neuen beginnen.
  procedure AddLineComment(const AToken: TPascalToken);
  var
    mItem: TCommentLine;
  begin
    // XMLDoc bleibt stumm.
    if StartsStr('///', AToken.Text) then
    begin
      Flush;
      Exit;
    end;
    if (mRun <> nil) and (mRun[High(mRun)].Line + 1 <> AToken.StartPos.Line) then
    begin
      Flush;
    end;
    mItem.Line := AToken.StartPos.Line;
    mItem.Text := Copy(AToken.Text, 3, MaxInt);
    mItem.Range := TTextRange.Create(AToken.StartPos, AToken.EndPos);
    mRun := mRun + [mItem];
  end;

  // Kommentare vor dem ersten Token sind der Dateikopf (Lizenz, Beschreibung).
  function FirstCodeToken: Integer;
  begin
    Result := 0;
    while (Result <= High(mTokens)) and (mTokens[Result].Kind in [TPascalTokenKind.Comment,
      TPascalTokenKind.Directive]) do
    begin
      Inc(Result);
    end;
  end;

var
  mIndex: Integer;
  mToken: TPascalToken;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mMinLines := TRuleOptions.Int(AContext.Options, 'minLines', cDefaultMinLines);
  if mMinLines < 1 then
  begin
    mMinLines := cDefaultMinLines;
  end;
  mRun := nil;
  for mIndex := FirstCodeToken to High(mTokens) do
  begin
    mToken := mTokens[mIndex];
    if (mToken.Kind <> TPascalTokenKind.Comment) or not FirstInLine(mIndex) then
    begin
      Flush;
    end
    else if StartsStr('//', mToken.Text) then
    begin
      AddLineComment(mToken);
    end
    else
    begin
      Flush;
      if mToken.EndPos.Line > mToken.StartPos.Line then
      begin
        JudgeBlock(mIndex);
      end;
    end;
  end;
  Flush;
end;

procedure RegisterTodoRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TTodoRule.Create);
  ARegistry.Register(TCommentedOutCodeRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Todos', cTexts);

end.
