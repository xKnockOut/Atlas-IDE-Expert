unit Atlas.Common.Rules.Builtin.General;

// Allgemeine Regeln, Stufe 1 aus #56 (syntaktisch, ohne Typen):
//   empty-except              except-Block ohne Anweisung und ohne erklärenden Kommentar
//   empty-finally             finally-Block ohne Anweisung, Kommentar und Direktive (#1065); nennt X.Free, wenn
//                             direkt davor X := T….Create steht. Korrektur: try/finally/end entfernen, Rumpf ausrücken
//                             (als einzige Anweisung eines if/while … mit mehreren Anweisungen: begin … end)
//   interface-guid            Interface ohne GUID; mit Supports/as/QueryInterface hohe Konfidenz (wie E2232)
//                             (dispinterface ohne GUID meldet dispinterface-invalid)
//   duplicate-interface-guid  zwei Interfaces der Datei mit derselben GUID
//   guid-syntax-invalid       GUID-Literal eines Interfaces oder einer TGUID-Konstante nicht in der Form
//                             '{8-4-4-4-12}' (#1072, wie E2204); Korrektur: neue GUID bzw. Klammern ergänzen
//   file-header               Dateikopf weicht von der Vorlage ab (Option "template", Standard aus)
//   hardcoded-string          Text im Code statt resourcestring (Standard aus, niedrige Konfidenz)

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TEmptyExceptRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TEmptyFinallyRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInterfaceGuidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDuplicateInterfaceGuidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TGuidSyntaxInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Was an der GUID AGuid (ohne Anführungszeichen) falsch ist, z. B. "Der letzte Block der GUID
    /// hat 11 statt 12 Zeichen"; '' bei der Form {8-4-4-4-12} aus Hexadezimalziffern.</summary>
    class function Problem(const AGuid: string): string; static;
  end;

  TFileHeaderRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorlage aus den Regeloptionen ({"template": "..."}); '' ohne.</summary>
    class function Template(const AOptions: string): string; static;
  end;

  THardcodedStringRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die allgemeinen Regeln.</summary>
procedure RegisterGeneralRules(const ARegistry: TRuleRegistry);

/// <summary>Neue GUID als Interface-Zeile ohne Einrückung: ['{…}'].</summary>
function GuidLine: string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Character,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Text.Lines;

function TokenRange(const AToken: TPascalToken): TTextRange;
begin
  Result := TTextRange.Create(AToken.StartPos, AToken.EndPos);
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Nächstes Token ab AIndex, das kein Kommentar und keine Direktive ist; Length(ATokens) ohne.</summary>
function NextCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

/// <summary>Vorheriges Token vor AIndex, das kein Kommentar und keine Direktive ist; -1 ohne.</summary>
function PreviousCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

/// <summary>Einrückung der Zeile ALine von AText.</summary>
function LineIndent(const AText: string; ALine: Integer): string;
var
  Lines: TArray<string>;
  Index: Integer;
begin
  Lines := StringReplace(AText, #13#10, #10, [rfReplaceAll]).Split([#10]);
  Result := '';
  if ALine > High(Lines) then
    Exit;
  Index := 1;
  while (Index <= Length(Lines[ALine])) and CharInSet(Lines[ALine][Index], [' ', #9]) do
    Inc(Index);
  Result := Copy(Lines[ALine], 1, Index - 1);
end;

function GuidLine: string;
var
  Guid: TGUID;
begin
  if CreateGUID(Guid) <> 0 then
    raise EOSError.Create('GUID konnte nicht erzeugt werden');
  Result := '[''' + GUIDToString(Guid) + ''']';
end;

{ TEmptyExceptRule }

function TEmptyExceptRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('empty-except', TRuleSeverity.Warning, 'Leerer except-Block');
end;

procedure TEmptyExceptRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Index, Next: Integer;
  Commented: Boolean;
  Indent: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].Kind <> TPascalTokenKind.Keyword) or not Tokens[Index].IsKeyword('except') then
      Continue;
    // Zwischen except und end steht nichts außer Kommentaren und Direktiven.
    Next := Index + 1;
    Commented := False;
    while (Next <= High(Tokens)) and IsTrivia(Tokens[Next]) do
    begin
      if Tokens[Next].Kind = TPascalTokenKind.Comment then
        Commented := True;
      Inc(Next);
    end;
    if (Next > High(Tokens)) or not Tokens[Next].IsKeyword('end') or Commented then
      Continue;
    Indent := LineIndent(AContext.Text, Tokens[Index].StartPos.Line);
    AReport.Add(TokenRange(Tokens[Index]), 'Leerer except-Block verschluckt jede Ausnahme; behandeln, ' +
      'weiterwerfen oder mit einem Kommentar begründen', TRuleConfidence.High,
      [TRuleFix.Create('raise; einfügen', [TRuleEdit.Create(TTextRange.Create(Tokens[Index].EndPos,
        Tokens[Index].EndPos), TTextLines.LineBreakOf(AContext.Text) + Indent + '  raise;')])]);
  end;
end;

{ TEmptyFinallyRule }

function TEmptyFinallyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('empty-finally', TRuleSeverity.Hint, 'Leerer finally-Block');
end;

procedure TEmptyFinallyRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Lines: TArray<string>;
  LineBreak: string;

  function IsEmptyBlock(ABlock: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    for Index := 0 to ABlock.ChildCount - 1 do
      if ABlock[Index].Kind <> TSyntaxKind.EmptyStatement then
        Exit(False);
    Result := True;
  end;

  // Index des Tokens mit dem Schlüsselwort AWord ab Offset AFrom (erstes) bzw. vor ABefore (letztes); -1 ohne.
  function FirstKeyword(const AWord: string; AFrom: Integer): Integer;
  begin
    for Result := 0 to High(Tokens) do
      if (Tokens[Result].Offset >= AFrom) and Tokens[Result].IsKeyword(AWord) then
        Exit;
    Result := -1;
  end;

  function LastKeyword(const AWord: string; ABefore: Integer): Integer;
  begin
    for Result := High(Tokens) downto 0 do
      if (Tokens[Result].Offset < ABefore) and Tokens[Result].IsKeyword(AWord) then
        Exit;
    Result := -1;
  end;

  // Variable aus X := T….Create direkt vor dem try; '' ohne.
  function CreatedVariable(ATry: TSyntaxNode): string;
  var
    Parent, Previous, Value: TSyntaxNode;
    Index: Integer;
  begin
    Result := '';
    Parent := ATry.Parent;
    if Parent = nil then
      Exit;
    Previous := nil;
    for Index := 1 to Parent.ChildCount - 1 do
      if Parent[Index] = ATry then
        Previous := Parent[Index - 1];
    if (Previous = nil) or (Previous.Kind <> TSyntaxKind.AssignStatement) or (Previous.ChildCount <> 2) or
      (Previous[0].Kind <> TSyntaxKind.Identifier) then
      Exit;
    Value := Previous[1];
    if (Value.Kind = TSyntaxKind.Call) and (Value.ChildCount > 0) then
      Value := Value[0];
    if (Value.Kind = TSyntaxKind.MemberAccess) and SameText(Value.Name, 'Create') then
      Result := Previous[0].Name;
  end;

  // Steht ATry in einer Anweisungsliste (begin … end, try, repeat …)? Sonst ist sie die einzige Anweisung
  // eines if, while, for, with oder case-Zweigs.
  function InStatementList(ATry: TSyntaxNode): Boolean;
  begin
    Result := (ATry.Parent <> nil) and (ATry.Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement,
      TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement, TSyntaxKind.CaseElse]);
  end;

  // try, finally und end stehen je allein auf ihrer Zeile (end mit oder ohne Semikolon): Dann entfernt die
  // Korrektur die drei Zeilen und rückt den Rumpf aus; als einzige Anweisung mit mehreren Anweisungen im Rumpf
  // wird aus try begin.
  function Fix(ATry: TSyntaxNode; ATryToken, AFinallyToken, AEndToken: Integer; out AFix: TRuleFix): Boolean;
  var
    TryLine, FinallyLine, EndLine, Line, Shift, Statements, Index: Integer;
    Body: TArray<string>;
    Ending, Text: string;
    Range: TTextRange;
  begin
    Result := False;
    TryLine := Tokens[ATryToken].StartPos.Line;
    FinallyLine := Tokens[AFinallyToken].StartPos.Line;
    EndLine := Tokens[AEndToken].StartPos.Line;
    if (EndLine > High(Lines)) or (Trim(Lines[TryLine]) <> 'try') or (Trim(Lines[FinallyLine]) <> 'finally') then
      Exit;
    Ending := Trim(Lines[EndLine]);
    if (Ending <> 'end') and (Ending <> 'end;') then
      Exit;
    Statements := 0;
    for Index := 0 to ATry.ChildCount - 1 do
      if not (ATry[Index].Kind in [TSyntaxKind.FinallyBlock, TSyntaxKind.EmptyStatement]) then
        Inc(Statements);
    Range := TTextRange.Create(TTextPosition.Create(TryLine, 0), TTextPosition.Create(EndLine, Length(Lines[EndLine])));
    if not InStatementList(ATry) and (Statements > 1) then
    begin
      Body := [TTextLines.IndentOf(Lines[TryLine]) + 'begin'];
      for Line := TryLine + 1 to FinallyLine - 1 do
        Body := Body + [Lines[Line]];
      Body := Body + [Lines[EndLine]];
      AFix := TRuleFix.Create('try … finally end durch begin … end ersetzen',
        [TRuleEdit.Create(Range, TTextLines.JoinLines(Body, LineBreak))]);
      Exit(True);
    end;
    // Rumpf um den Unterschied zwischen seiner Einrückung und der von try ausrücken.
    Shift := MaxInt;
    for Line := TryLine + 1 to FinallyLine - 1 do
      if Trim(Lines[Line]) <> '' then
        Shift := Min(Shift, TTextLines.IndentLength(Lines[Line]) - TTextLines.IndentLength(Lines[TryLine]));
    if (Shift = MaxInt) or (Shift < 0) then
      Shift := 0;
    Body := nil;
    for Line := TryLine + 1 to FinallyLine - 1 do
      if Trim(Lines[Line]) = '' then
        Body := Body + ['']
      else
        Body := Body + [Copy(Lines[Line], Shift + 1, MaxInt)];
    if Body = nil then
      Exit;
    // end; trennte die Anweisung von der folgenden: Das Semikolon wandert an die letzte Zeile des Rumpfs.
    Text := TrimRight(Body[High(Body)]);
    if (Ending = 'end;') and not EndsStr(';', Text) then
      Body[High(Body)] := Text + ';';
    AFix := TRuleFix.Create('try … finally end entfernen (Rumpf bleibt)',
      [TRuleEdit.Create(Range, TTextLines.JoinLines(Body, LineBreak))]);
    Result := True;
  end;

  procedure CheckTry(ATry: TSyntaxNode);
  var
    Block: TSyntaxNode;
    TryToken, FinallyToken, EndToken, Index: Integer;
    Variable, Message: string;
    RuleFix: TRuleFix;
  begin
    Block := ATry[ATry.ChildCount - 1];
    if (Block.Kind <> TSyntaxKind.FinallyBlock) or not IsEmptyBlock(Block) then
      Exit;
    TryToken := FirstKeyword('try', ATry.StartOffset);
    FinallyToken := LastKeyword('finally', ATry.EndOffset);
    EndToken := LastKeyword('end', ATry.EndOffset);
    if (TryToken < 0) or (FinallyToken < 0) or (EndToken <= FinallyToken) then
      Exit;
    // Ein Kommentar begründet den leeren Block; eine Direktive kann Code eines anderen Zweigs enthalten.
    for Index := FinallyToken + 1 to EndToken - 1 do
      if Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
        Exit;
    Variable := CreatedVariable(ATry);
    if Variable <> '' then
      Message := Format('Leerer finally-Block; fehlt hier %s.Free?', [Variable])
    else
      Message := 'Leerer finally-Block; die Freigabe fehlt oder try … finally ist überflüssig.';
    if Fix(ATry, TryToken, FinallyToken, EndToken, RuleFix) then
      AReport.Add(TokenRange(Tokens[FinallyToken]), Message, TRuleConfidence.High, [RuleFix])
    else
      AReport.Add(TokenRange(Tokens[FinallyToken]), Message, TRuleConfidence.High, []);
  end;

  // Iterativ (Bericht M1).
  procedure Walk(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.TryStatement) and (Node.ChildCount > 0) then
          CheckTry(Node);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Walk(AContext.Tree.Root);
end;

{ Interface-Deklarationen }

type
  /// <summary>Interface-Typ der Datei mit seiner GUID ('' ohne).</summary>
  TInterfaceDeclaration = record
    Name: string;
    NameToken: Integer;
    /// <summary>Token, hinter dem die GUID-Zeile eingefügt wird: interface bzw. die schließende Klammer der Vorfahren.</summary>
    HeaderEnd: Integer;
    Guid: string;
    GuidToken: Integer;
    /// <summary>dispinterface statt interface: Ohne GUID ist das ein Compilerfehler (dispinterface-invalid).</summary>
    IsDispinterface: Boolean;
  end;

function InterfaceDeclarations(const ATokens: TArray<TPascalToken>): TArray<TInterfaceDeclaration>;
var
  Index, Equals, Name, Next: Integer;
  Declaration: TInterfaceDeclaration;
begin
  Result := nil;
  for Index := 0 to High(ATokens) do
  begin
    if not (ATokens[Index].IsKeyword('interface') or ATokens[Index].IsKeyword('dispinterface')) then
      Continue;
    // "IFoo = interface": vor dem Schlüsselwort steht "=", davor der Name.
    Equals := PreviousCode(ATokens, Index);
    if (Equals < 0) or not ATokens[Equals].IsSymbol('=') then
      Continue;
    Name := PreviousCode(ATokens, Equals);
    if (Name < 0) or (ATokens[Name].Kind <> TPascalTokenKind.Identifier) then
      Continue;
    Declaration := Default(TInterfaceDeclaration);
    Declaration.Name := ATokens[Name].Text;
    Declaration.NameToken := Name;
    Declaration.HeaderEnd := Index;
    Declaration.GuidToken := -1;
    Declaration.IsDispinterface := ATokens[Index].IsKeyword('dispinterface');
    Next := NextCode(ATokens, Index + 1);
    // Vorwärtsdeklaration "IFoo = interface;" hat keine GUID.
    if (Next <= High(ATokens)) and ATokens[Next].IsSymbol(';') then
      Continue;
    if (Next <= High(ATokens)) and ATokens[Next].IsSymbol('(') then
    begin
      while (Next <= High(ATokens)) and not ATokens[Next].IsSymbol(')') do
        Inc(Next);
      Declaration.HeaderEnd := Next;
      Next := NextCode(ATokens, Next + 1);
    end;
    if (Next + 2 <= High(ATokens)) and ATokens[Next].IsSymbol('[') and
      (ATokens[Next + 1].Kind = TPascalTokenKind.StringLiteral) then
    begin
      Declaration.Guid := UpperCase(AnsiDequotedStr(ATokens[Next + 1].Text, ''''));
      Declaration.GuidToken := Next + 1;
    end
    else if (Next + 2 <= High(ATokens)) and ATokens[Next].IsSymbol('[') then
      // GUID über eine Konstante: vorhanden, aber nicht vergleichbar.
      Declaration.GuidToken := Next;
    Result := Result + [Declaration];
  end;
end;

{ TInterfaceGuidRule }

function TInterfaceGuidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('interface-guid', TRuleSeverity.Warning, 'Interface ohne GUID');
end;

/// <summary>Wird AName mit Supports, as oder QueryInterface abgefragt?</summary>
function IsQueried(const ATokens: TArray<TPascalToken>; const AName: string): Boolean;
var
  Index, Previous, Inner: Integer;
begin
  for Index := 0 to High(ATokens) do
  begin
    if (ATokens[Index].Kind <> TPascalTokenKind.Identifier) or not SameText(ATokens[Index].Text, AName) then
      Continue;
    Previous := PreviousCode(ATokens, Index);
    if (Previous >= 0) and ATokens[Previous].IsKeyword('as') then
      Exit(True);
    // Supports(X, IFoo, …) bzw. QueryInterface(IFoo, …): der Name steht in der Argumentliste.
    for Inner := Index - 1 downto Max(0, Index - 8) do
      if (ATokens[Inner].Kind = TPascalTokenKind.Identifier) and
        (SameText(ATokens[Inner].Text, 'Supports') or SameText(ATokens[Inner].Text, 'QueryInterface')) then
        Exit(True)
      else if ATokens[Inner].IsSymbol(';') then
        Break;
  end;
  Result := False;
end;

procedure TInterfaceGuidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Declaration: TInterfaceDeclaration;
  Confidence: TRuleConfidence;
  Indent, mCode: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Declaration in InterfaceDeclarations(Tokens) do
  begin
    // Ein dispinterface ohne GUID übersetzt nicht; das meldet dispinterface-invalid als Fehler (wie E2229, #1374).
    if (Declaration.GuidToken >= 0) or Declaration.IsDispinterface then
      Continue;
    // Nur die Abfrage meldet dcc, an ihrer Stelle (E2232, #1382).
    mCode := '';
    if IsQueried(Tokens, Declaration.Name) then
    begin
      Confidence := TRuleConfidence.High;
      mCode := ' (wie E2232).';
    end
    else
      Confidence := TRuleConfidence.Low;
    Indent := LineIndent(AContext.Text, Tokens[Declaration.NameToken].StartPos.Line);
    AReport.Add(TokenRange(Tokens[Declaration.NameToken]), Format('Interface %s hat keine GUID; Supports, as ' +
      'und QueryInterface brauchen eine%s', [Declaration.Name, mCode]), Confidence,
      [TRuleFix.Create('GUID einfügen', [TRuleEdit.Create(TTextRange.Create(Tokens[Declaration.HeaderEnd].EndPos,
        Tokens[Declaration.HeaderEnd].EndPos),
        TTextLines.LineBreakOf(AContext.Text) + Indent + '  ' + GuidLine)], True)]);
  end;
end;

{ TDuplicateInterfaceGuidRule }

function TDuplicateInterfaceGuidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('duplicate-interface-guid', TRuleSeverity.Error,
    'Zwei Interfaces mit derselben GUID');
end;

procedure TDuplicateInterfaceGuidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Declarations: TArray<TInterfaceDeclaration>;
  Index, Other: Integer;
  Token: TPascalToken;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Declarations := InterfaceDeclarations(Tokens);
  for Index := 0 to High(Declarations) do
  begin
    if Declarations[Index].Guid = '' then
      Continue;
    for Other := 0 to High(Declarations) do
      if (Other <> Index) and (Declarations[Other].Guid = Declarations[Index].Guid) then
      begin
        Token := Tokens[Declarations[Index].GuidToken];
        AReport.Add(TokenRange(Token), Format('%s hat dieselbe GUID wie %s; Supports und as verwechseln die ' +
          'beiden', [Declarations[Index].Name, Declarations[Other].Name]), TRuleConfidence.High,
          [TRuleFix.Create('Neue GUID erzeugen', [TRuleEdit.Create(TokenRange(Token),
            Copy(GuidLine, 2, Length(GuidLine) - 2))])]);
        Break;
      end;
  end;
end;

{ TGuidSyntaxInvalidRule }

function TGuidSyntaxInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('guid-syntax-invalid', TRuleSeverity.Error, 'GUID mit falscher Schreibweise');
end;

class function TGuidSyntaxInvalidRule.Problem(const AGuid: string): string;
const
  Lengths: array[0..4] of Integer = (8, 4, 4, 4, 12);
  Ordinals: array[0..4] of string = ('erste', 'zweite', 'dritte', 'vierte', 'letzte');
var
  Blocks: TArray<string>;
  Index, Position: Integer;
begin
  Result := '';
  if not AGuid.StartsWith('{') and not AGuid.EndsWith('}') then
    Exit('Der GUID fehlen die geschweiften Klammern');
  if not AGuid.StartsWith('{') then
    Exit('Der GUID fehlt die öffnende geschweifte Klammer');
  if not AGuid.EndsWith('}') or (Length(AGuid) < 2) then
    Exit('Der GUID fehlt die schließende geschweifte Klammer');
  Blocks := Copy(AGuid, 2, Length(AGuid) - 2).Split(['-']);
  if Length(Blocks) <> Length(Lengths) then
    Exit(Format('Die GUID hat %d statt 5 Blöcke', [Length(Blocks)]));
  for Index := 0 to High(Blocks) do
    if Length(Blocks[Index]) <> Lengths[Index] then
      Exit(Format('Der %s Block der GUID hat %d statt %d Zeichen', [Ordinals[Index], Length(Blocks[Index]),
        Lengths[Index]]));
  for Index := 0 to High(Blocks) do
    for Position := 1 to Length(Blocks[Index]) do
      if not CharInSet(Blocks[Index][Position], ['0'..'9', 'A'..'F', 'a'..'f']) then
        Exit(Format('Die GUID enthält „%s“, das ist keine Hexadezimalziffer', [Blocks[Index][Position]]));
end;

procedure TGuidSyntaxInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;

  procedure CheckLiteral(AIndex: Integer);
  var
    Text, Guid, Message: string;
    Fixes: TArray<TRuleFix>;
    Next: Integer;
  begin
    Text := Tokens[AIndex].Text;
    // Nur ein einzelnes Literal ohne #-Zeichen; Verkettungen wertet erst der Compiler aus.
    if not Text.StartsWith('''') or not Text.EndsWith('''') or (Length(Text) < 2) then
      Exit;
    Next := NextCode(Tokens, AIndex + 1);
    if (Next > High(Tokens)) or not (Tokens[Next].IsSymbol(']') or Tokens[Next].IsSymbol(';')) then
      Exit;
    Guid := AnsiDequotedStr(Text, '''');
    Message := TGuidSyntaxInvalidRule.Problem(Guid);
    if Message = '' then
      Exit;
    Fixes := nil;
    if TGuidSyntaxInvalidRule.Problem('{' + Guid + '}') = '' then
      Fixes := [TRuleFix.Create('Geschweifte Klammern ergänzen', [TRuleEdit.Create(TokenRange(Tokens[AIndex]),
        '''{' + Guid + '}''')], True)];
    Fixes := Fixes + [TRuleFix.Create('Neue GUID erzeugen', [TRuleEdit.Create(TokenRange(Tokens[AIndex]),
      Copy(GuidLine, 2, Length(GuidLine) - 2))])];
    AReport.Add(TokenRange(Tokens[AIndex]), Message + ' (wie E2204).', TRuleConfidence.High, Fixes);
  end;

var
  Declaration: TInterfaceDeclaration;
  Index, Colon, Equals: Integer;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Declaration in InterfaceDeclarations(Tokens) do
    if (Declaration.GuidToken >= 0) and (Tokens[Declaration.GuidToken].Kind = TPascalTokenKind.StringLiteral) then
      CheckLiteral(Declaration.GuidToken);
  // Typisierte Konstanten: Name: TGUID = '…';
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].Kind <> TPascalTokenKind.StringLiteral) then
      Continue;
    Equals := PreviousCode(Tokens, Index);
    if (Equals < 0) or not Tokens[Equals].IsSymbol('=') then
      Continue;
    Colon := PreviousCode(Tokens, PreviousCode(Tokens, Equals));
    if (Colon >= 0) and Tokens[Colon].IsSymbol(':') and
      SameText(Tokens[PreviousCode(Tokens, Equals)].Text, 'TGUID') then
      CheckLiteral(Index);
  end;
end;

{ TFileHeaderRule }

function TFileHeaderRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('file-header', TRuleSeverity.Hint, 'Dateikopf fehlt oder weicht ab', True);
end;

class function TFileHeaderRule.Template(const AOptions: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if Trim(AOptions) = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if Value is TJSONObject then
      TJSONObject(Value).TryGetValue<string>('template', Result);
  finally
    Value.Free;
  end;
end;

procedure TFileHeaderRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Header, Text, LineBreak: string;
begin
  Header := Template(AContext.Options);
  if Header = '' then
    Exit;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Header := StringReplace(StringReplace(Header, #13#10, #10, [rfReplaceAll]), #10, LineBreak, [rfReplaceAll]);
  Text := AContext.Text;
  if (Text <> '') and (Text[1] = #$FEFF) then
    Delete(Text, 1, 1);
  if StartsStr(Header, Text) then
    Exit;
  AReport.Add(TTextRange.Create(0, 0, 0, 0), 'Der Dateikopf entspricht nicht der Vorlage', TRuleConfidence.High,
    [TRuleFix.Create('Dateikopf einfügen', [TRuleEdit.Create(TTextRange.Create(0, 0, 0, 0), Header + LineBreak)])]);
end;

{ THardcodedStringRule }

function THardcodedStringRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('hardcoded-string', TRuleSeverity.Hint, 'Text im Code statt resourcestring',
    True);
end;

/// <summary>Sieht der Literalinhalt nach Text für Menschen aus: mindestens zwei Wörter mit Buchstaben?</summary>
function LooksLikeText(const AValue: string): Boolean;
var
  Index, Letters: Integer;
begin
  Letters := 0;
  for Index := 1 to Length(AValue) do
    if AValue[Index].IsLetter then
      Inc(Letters);
  Result := (Letters >= 3) and (Pos(' ', Trim(AValue)) > 0);
end;

procedure THardcodedStringRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Index, Depth: Integer;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Depth := 0;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Kind = TPascalTokenKind.Keyword then
    begin
      if Tokens[Index].IsKeyword('begin') then
        Inc(Depth)
      else if (Depth > 0) and (Tokens[Index].IsKeyword('try') or Tokens[Index].IsKeyword('case') or
        Tokens[Index].IsKeyword('asm')) then
        Inc(Depth)
      else if (Depth > 0) and Tokens[Index].IsKeyword('end') then
        Dec(Depth);
      Continue;
    end;
    // Nur Anweisungen: Konstanten- und resourcestring-Abschnitte stehen außerhalb von begin … end.
    if (Depth = 0) or (Tokens[Index].Kind <> TPascalTokenKind.StringLiteral) then
      Continue;
    if LooksLikeText(AnsiDequotedStr(Tokens[Index].Text, '''')) then
      AReport.Add(TokenRange(Tokens[Index]), 'Text im Code; für Übersetzungen in einen resourcestring auslagern',
        TRuleConfidence.Low);
  end;
end;

procedure RegisterGeneralRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TEmptyExceptRule.Create);
  ARegistry.Register(TEmptyFinallyRule.Create);
  ARegistry.Register(TInterfaceGuidRule.Create);
  ARegistry.Register(TDuplicateInterfaceGuidRule.Create);
  ARegistry.Register(TGuidSyntaxInvalidRule.Create);
  ARegistry.Register(TFileHeaderRule.Create);
  ARegistry.Register(THardcodedStringRule.Create);
end;

end.
