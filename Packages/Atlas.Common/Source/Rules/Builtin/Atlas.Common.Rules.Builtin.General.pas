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
//   hardcoded-string          Text im Code statt resourcestring (Standard aus, niedrige Konfidenz). Still bei
//                             Texten, die niemand übersetzt: Argumente von Protokoll- und Prüfaufrufen (…Log,
//                             Log…, Diagnose, Trace, Debug, Assert, OutputDebugString), Vergleichs- und
//                             Registry-Aufrufen (StartsText, Pos, ReadString …), Masken von FormatDateTime und
//                             FormatFloat, Markup (HTML ab <, JSON ab { oder "Schlüssel":, Markdown # und ##) und
//                             Font.Name; Option "ignoreCalls" nennt weitere Routinen (z. B. ein eigenes
//                             Pick(Englisch, 'en', 'de')).

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
  Atlas.Text.Lines,
  Atlas.Common.Rules.Options,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TGeneralText = (GuidNotCreated, EmptyExceptTitle, EmptyExcept, InsertRaise, EmptyFinallyTitle, ReplaceTryByBegin,
    RemoveTry, EmptyFinallyFree, EmptyFinally, InterfaceGuidTitle, LikeE2232, InterfaceWithoutGuid, InsertGuid,
    DuplicateGuidTitle, DuplicateGuid, NewGuid, GuidSyntaxTitle, MissingBraces, MissingOpenBrace, MissingCloseBrace,
    BlockCount, BlockLength, NoHexDigit, AddBraces, LikeE2204, FileHeaderTitle, FileHeader, InsertFileHeader,
    HardcodedStringTitle, HardcodedString, First, Second, Third, Fourth, Last);

const
  cTexts: array[TGeneralText] of TAtlasText = (
    (De: 'GUID konnte nicht erzeugt werden'; En: 'Could not create GUID'),
    (De: 'Leerer except-Block'; En: 'Empty except block'),
    (De: 'Leerer except-Block verschluckt jede Ausnahme; behandeln, weiterwerfen oder mit einem Kommentar begründen';
     En: 'Empty except block swallows every exception; handle it, re-raise it or justify it with a comment'),
    (De: 'raise; einfügen'; En: 'Insert raise;'),
    (De: 'Leerer finally-Block'; En: 'Empty finally block'),
    (De: 'try … finally end durch begin … end ersetzen'; En: 'Replace try … finally end with begin … end'),
    (De: 'try … finally end entfernen (Rumpf bleibt)'; En: 'Remove try … finally end (body stays)'),
    (De: 'Leerer finally-Block; fehlt hier %s.Free?'; En: 'Empty finally block; is %s.Free missing here?'),
    (De: 'Leerer finally-Block; die Freigabe fehlt oder try … finally ist überflüssig.';
     En: 'Empty finally block; the release is missing or try … finally is superfluous.'),
    (De: 'Interface ohne GUID'; En: 'Interface without GUID'),
    (De: ' (wie E2232).'; En: ' (like E2232).'),
    (De: 'Interface %s hat keine GUID; Supports, as und QueryInterface brauchen eine%s';
     En: 'Interface %s has no GUID; Supports, as and QueryInterface need one%s'),
    (De: 'GUID einfügen'; En: 'Insert GUID'),
    (De: 'Zwei Interfaces mit derselben GUID'; En: 'Two interfaces with the same GUID'),
    (De: '%s hat dieselbe GUID wie %s; Supports und as verwechseln die beiden';
     En: '%s has the same GUID as %s; Supports and as confuse the two'),
    (De: 'Neue GUID erzeugen'; En: 'Generate new GUID'),
    (De: 'GUID mit falscher Schreibweise'; En: 'GUID with wrong notation'),
    (De: 'Der GUID fehlen die geschweiften Klammern'; En: 'The GUID lacks the curly braces'),
    (De: 'Der GUID fehlt die öffnende geschweifte Klammer'; En: 'The GUID lacks the opening curly brace'),
    (De: 'Der GUID fehlt die schließende geschweifte Klammer'; En: 'The GUID lacks the closing curly brace'),
    (De: 'Die GUID hat %d statt 5 Blöcke'; En: 'The GUID has %d instead of 5 blocks'),
    (De: 'Der %s Block der GUID hat %d statt %d Zeichen';
     En: 'The %s block of the GUID has %d instead of %d characters'),
    (De: 'Die GUID enthält „%s“, das ist keine Hexadezimalziffer';
     En: 'The GUID contains “%s”, which is not a hexadecimal digit'),
    (De: 'Geschweifte Klammern ergänzen'; En: 'Add curly braces'),
    (De: ' (wie E2204).'; En: ' (like E2204).'),
    (De: 'Dateikopf fehlt oder weicht ab'; En: 'File header missing or different'),
    (De: 'Der Dateikopf entspricht nicht der Vorlage'; En: 'The file header does not match the template'),
    (De: 'Dateikopf einfügen'; En: 'Insert file header'),
    (De: 'Text im Code statt resourcestring'; En: 'Text in code instead of resourcestring'),
    (De: 'Text im Code; für Übersetzungen in einen resourcestring auslagern';
     En: 'Text in code; move it into a resourcestring for translations'),
    (De: 'erste'; En: 'first'),
    (De: 'zweite'; En: 'second'),
    (De: 'dritte'; En: 'third'),
    (De: 'vierte'; En: 'fourth'),
    (De: 'letzte'; En: 'last'));

{$SCOPEDENUMS OFF}

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
  begin
    Inc(Result);
  end;
end;

/// <summary>Vorheriges Token vor AIndex, das kein Kommentar und keine Direktive ist; -1 ohne.</summary>
function PreviousCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
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
  begin
    Exit;
  end;
  Index := 1;
  while (Index <= Length(Lines[ALine])) and CharInSet(Lines[ALine][Index], [' ', #9]) do
  begin
    Inc(Index);
  end;
  Result := Copy(Lines[ALine], 1, Index - 1);
end;

function GuidLine: string;
var
  Guid: TGUID;
begin
  if CreateGUID(Guid) <> 0 then
  begin
    raise EOSError.Create(cTexts[TGeneralText.GuidNotCreated].Text);
  end;
  Result := '[''' + GUIDToString(Guid) + ''']';
end;

{ TEmptyExceptRule }

function TEmptyExceptRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('empty-except', TRuleSeverity.Warning, cTexts[TGeneralText.EmptyExceptTitle].Text);
end;

procedure TEmptyExceptRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Index, Next: Integer;
  Commented: Boolean;
  Indent: string;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].Kind <> TPascalTokenKind.Keyword) or not Tokens[Index].IsKeyword('except') then
    begin
      Continue;
    end;
    // Zwischen except und end steht nichts außer Kommentaren und Direktiven.
    Next := Index + 1;
    Commented := False;
    while (Next <= High(Tokens)) and IsTrivia(Tokens[Next]) do
    begin
      if Tokens[Next].Kind = TPascalTokenKind.Comment then
      begin
        Commented := True;
      end;
      Inc(Next);
    end;
    if (Next > High(Tokens)) or not Tokens[Next].IsKeyword('end') or Commented then
    begin
      Continue;
    end;
    Indent := LineIndent(AContext.Text, Tokens[Index].StartPos.Line);
    AReport.Add(TokenRange(Tokens[Index]), cTexts[TGeneralText.EmptyExcept].Text, TRuleConfidence.High,
      [TRuleFix.Create(cTexts[TGeneralText.InsertRaise].Text, [TRuleEdit.Create(TTextRange.Create(Tokens[Index].EndPos,
        Tokens[Index].EndPos), TTextLines.LineBreakOf(AContext.Text) + Indent + '  raise;')])]);
  end;
end;

{ TEmptyFinallyRule }

function TEmptyFinallyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('empty-finally', TRuleSeverity.Hint, cTexts[TGeneralText.EmptyFinallyTitle].Text);
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
    begin
      if ABlock[Index].Kind <> TSyntaxKind.EmptyStatement then
      begin
        Exit(False);
      end;
    end;
    Result := True;
  end;

  // Index des Tokens mit dem Schlüsselwort AWord ab Offset AFrom (erstes) bzw. vor ABefore (letztes); -1 ohne.
  function FirstKeyword(const AWord: string; AFrom: Integer): Integer;
  begin
    for Result := 0 to High(Tokens) do
    begin
      if (Tokens[Result].Offset >= AFrom) and Tokens[Result].IsKeyword(AWord) then
      begin
        Exit;
      end;
    end;
    Result := -1;
  end;

  function LastKeyword(const AWord: string; ABefore: Integer): Integer;
  begin
    for Result := High(Tokens) downto 0 do
    begin
      if (Tokens[Result].Offset < ABefore) and Tokens[Result].IsKeyword(AWord) then
      begin
        Exit;
      end;
    end;
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
    begin
      Exit;
    end;
    Previous := nil;
    for Index := 1 to Parent.ChildCount - 1 do
    begin
      if Parent[Index] = ATry then
      begin
        Previous := Parent[Index - 1];
      end;
    end;
    if (Previous = nil) or (Previous.Kind <> TSyntaxKind.AssignStatement) or (Previous.ChildCount <> 2) or
      (Previous[0].Kind <> TSyntaxKind.Identifier) then
    begin
      Exit;
    end;
    Value := Previous[1];
    if (Value.Kind = TSyntaxKind.Call) and (Value.ChildCount > 0) then
    begin
      Value := Value[0];
    end;
    if (Value.Kind = TSyntaxKind.MemberAccess) and SameText(Value.Name, 'Create') then
    begin
      Result := Previous[0].Name;
    end;
  end;

  // Steht ATry in einer Anweisungsliste (begin … end, try, repeat …)? Sonst ist sie die einzige Anweisung
  // eines if, while, for, with oder case-Zweigs.
  function InStatementList(ATry: TSyntaxNode): Boolean;
  begin
    Result := (ATry.Parent <> nil) and (ATry.Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement,
      TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement, TSyntaxKind.CaseElse]);
  end;

  /// <summary>Anweisungen im try-Teil von ATry (ohne finally und leere Anweisungen).</summary>
  function StatementCount(ATry: TSyntaxNode): Integer;
  var
    mIndex: Integer;
  begin
    Result := 0;
    for mIndex := 0 to ATry.ChildCount - 1 do
    begin
      if not (ATry[mIndex].Kind in [TSyntaxKind.FinallyBlock, TSyntaxKind.EmptyStatement]) then
      begin
        Inc(Result);
      end;
    end;
  end;

  /// <summary>Stehen try, finally und end je allein auf ihrer Zeile? AEnding: die Zeile von end, getrimmt.
  /// </summary>
  function OwnLines(ATryLine, AFinallyLine, AEndLine: Integer; out AEnding: string): Boolean;
  begin
    AEnding := '';
    Result := (AEndLine <= High(Lines)) and (Trim(Lines[ATryLine]) = 'try') and
      (Trim(Lines[AFinallyLine]) = 'finally');
    if Result then
    begin
      AEnding := Trim(Lines[AEndLine]);
      Result := (AEnding = 'end') or (AEnding = 'end;');
    end;
  end;

  /// <summary>Rumpf zwischen try und finally als begin … end.</summary>
  function BeginEndBody(ATryLine, AFinallyLine, AEndLine: Integer): TArray<string>;
  var
    mLine: Integer;
  begin
    Result := [TTextLines.IndentOf(Lines[ATryLine]) + 'begin'];
    for mLine := ATryLine + 1 to AFinallyLine - 1 do
    begin
      Result := Result + [Lines[mLine]];
    end;
    Result := Result + [Lines[AEndLine]];
  end;

  /// <summary>Unterschied zwischen der Einrückung des Rumpfs und der von try; 0, wenn er nicht weiter
  /// eingerückt ist.</summary>
  function BodyShift(ATryLine, AFinallyLine: Integer): Integer;
  var
    mLine: Integer;
  begin
    Result := MaxInt;
    for mLine := ATryLine + 1 to AFinallyLine - 1 do
    begin
      if Trim(Lines[mLine]) <> '' then
      begin
        Result := Min(Result, TTextLines.IndentLength(Lines[mLine]) - TTextLines.IndentLength(Lines[ATryLine]));
      end;
    end;
    if (Result = MaxInt) or (Result < 0) then
    begin
      Result := 0;
    end;
  end;

  /// <summary>Rumpf zwischen try und finally, um seine zusätzliche Einrückung ausgerückt; nil ohne Zeilen.
  /// end; trennte die Anweisung von der folgenden: Das Semikolon wandert an die letzte Zeile des Rumpfs.
  /// </summary>
  function OutdentedBody(ATryLine, AFinallyLine: Integer; const AEnding: string): TArray<string>;
  var
    mLine, mShift: Integer;
    mText: string;
  begin
    mShift := BodyShift(ATryLine, AFinallyLine);
    Result := nil;
    for mLine := ATryLine + 1 to AFinallyLine - 1 do
    begin
      if Trim(Lines[mLine]) = '' then
      begin
        Result := Result + [''];
      end
      else
      begin
        Result := Result + [Copy(Lines[mLine], mShift + 1, MaxInt)];
      end;
    end;
    if Result = nil then
    begin
      Exit;
    end;
    mText := TrimRight(Result[High(Result)]);
    if (AEnding = 'end;') and not EndsStr(';', mText) then
    begin
      Result[High(Result)] := mText + ';';
    end;
  end;

  // try, finally und end stehen je allein auf ihrer Zeile (end mit oder ohne Semikolon): Dann entfernt die
  // Korrektur die drei Zeilen und rückt den Rumpf aus; als einzige Anweisung mit mehreren Anweisungen im Rumpf
  // wird aus try begin.
  function Fix(ATry: TSyntaxNode; ATryToken, AFinallyToken, AEndToken: Integer; out AFix: TRuleFix): Boolean;
  var
    mTryLine, mFinallyLine, mEndLine: Integer;
    mBody: TArray<string>;
    mEnding: string;
    mRange: TTextRange;
  begin
    mTryLine := Tokens[ATryToken].StartPos.Line;
    mFinallyLine := Tokens[AFinallyToken].StartPos.Line;
    mEndLine := Tokens[AEndToken].StartPos.Line;
    if not OwnLines(mTryLine, mFinallyLine, mEndLine, mEnding) then
    begin
      Exit(False);
    end;
    mRange := TTextRange.Create(TTextPosition.Create(mTryLine, 0), TTextPosition.Create(mEndLine,
      Length(Lines[mEndLine])));
    if not InStatementList(ATry) and (StatementCount(ATry) > 1) then
    begin
      AFix := TRuleFix.Create(cTexts[TGeneralText.ReplaceTryByBegin].Text,
        [TRuleEdit.Create(mRange, TTextLines.JoinLines(BeginEndBody(mTryLine, mFinallyLine, mEndLine), LineBreak))]);
      Exit(True);
    end;
    // Rumpf um den Unterschied zwischen seiner Einrückung und der von try ausrücken.
    mBody := OutdentedBody(mTryLine, mFinallyLine, mEnding);
    Result := mBody <> nil;
    if Result then
    begin
      AFix := TRuleFix.Create(cTexts[TGeneralText.RemoveTry].Text,
        [TRuleEdit.Create(mRange, TTextLines.JoinLines(mBody, LineBreak))]);
    end;
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
    begin
      Exit;
    end;
    TryToken := FirstKeyword('try', ATry.StartOffset);
    FinallyToken := LastKeyword('finally', ATry.EndOffset);
    EndToken := LastKeyword('end', ATry.EndOffset);
    if (TryToken < 0) or (FinallyToken < 0) or (EndToken <= FinallyToken) then
    begin
      Exit;
    end;
    // Ein Kommentar begründet den leeren Block; eine Direktive kann Code eines anderen Zweigs enthalten.
    for Index := FinallyToken + 1 to EndToken - 1 do
    begin
      if Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
      begin
        Exit;
      end;
    end;
    Variable := CreatedVariable(ATry);
    if Variable <> '' then
    begin
      Message := cTexts[TGeneralText.EmptyFinallyFree].Fmt([Variable]);
    end
    else
    begin
      Message := cTexts[TGeneralText.EmptyFinally].Text;
    end;
    if Fix(ATry, TryToken, FinallyToken, EndToken, RuleFix) then
    begin
      AReport.Add(TokenRange(Tokens[FinallyToken]), Message, TRuleConfidence.High, [RuleFix]);
    end
    else
    begin
      AReport.Add(TokenRange(Tokens[FinallyToken]), Message, TRuleConfidence.High, []);
    end;
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
        begin
          CheckTry(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
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

/// <summary>"IFoo = interface": vor dem Schlüsselwort an AKeyword steht "=", davor der Name. Token des
/// Namens; -1 ohne.</summary>
function InterfaceNameToken(const ATokens: TArray<TPascalToken>; AKeyword: Integer): Integer;
var
  mEquals: Integer;
begin
  Result := -1;
  mEquals := PreviousCode(ATokens, AKeyword);
  if (mEquals >= 0) and ATokens[mEquals].IsSymbol('=') then
  begin
    Result := PreviousCode(ATokens, mEquals);
    if (Result >= 0) and (ATokens[Result].Kind <> TPascalTokenKind.Identifier) then
    begin
      Result := -1;
    end;
  end;
end;

/// <summary>GUID ab dem Token ANext nach dem Kopf in ADeclaration eintragen.</summary>
procedure ReadGuid(const ATokens: TArray<TPascalToken>; ANext: Integer; var ADeclaration: TInterfaceDeclaration);
begin
  if (ANext + 2 > High(ATokens)) or not ATokens[ANext].IsSymbol('[') then
  begin
    Exit;
  end;
  if ATokens[ANext + 1].Kind = TPascalTokenKind.StringLiteral then
  begin
    ADeclaration.Guid := UpperCase(AnsiDequotedStr(ATokens[ANext + 1].Text, ''''));
    ADeclaration.GuidToken := ANext + 1;
  end
  else
  begin
    // GUID über eine Konstante: vorhanden, aber nicht vergleichbar.
    ADeclaration.GuidToken := ANext;
  end;
end;

/// <summary>Deklaration zum Schlüsselwort interface bzw. dispinterface an AKeyword mit dem Namen an AName;
/// False bei einer Vorwärtsdeklaration "IFoo = interface;" (ohne GUID).</summary>
function ReadDeclaration(const ATokens: TArray<TPascalToken>; AKeyword, AName: Integer;
  out ADeclaration: TInterfaceDeclaration): Boolean;
var
  mNext: Integer;
begin
  ADeclaration := Default(TInterfaceDeclaration);
  ADeclaration.Name := ATokens[AName].Text;
  ADeclaration.NameToken := AName;
  ADeclaration.HeaderEnd := AKeyword;
  ADeclaration.GuidToken := -1;
  ADeclaration.IsDispinterface := ATokens[AKeyword].IsKeyword('dispinterface');
  mNext := NextCode(ATokens, AKeyword + 1);
  if (mNext <= High(ATokens)) and ATokens[mNext].IsSymbol(';') then
  begin
    Exit(False);
  end;
  if (mNext <= High(ATokens)) and ATokens[mNext].IsSymbol('(') then
  begin
    while (mNext <= High(ATokens)) and not ATokens[mNext].IsSymbol(')') do
    begin
      Inc(mNext);
    end;
    ADeclaration.HeaderEnd := mNext;
    mNext := NextCode(ATokens, mNext + 1);
  end;
  ReadGuid(ATokens, mNext, ADeclaration);
  Result := True;
end;

function InterfaceDeclarations(const ATokens: TArray<TPascalToken>): TArray<TInterfaceDeclaration>;
var
  mIndex, mName: Integer;
  mDeclaration: TInterfaceDeclaration;
begin
  Result := nil;
  for mIndex := 0 to High(ATokens) do
  begin
    if not (ATokens[mIndex].IsKeyword('interface') or ATokens[mIndex].IsKeyword('dispinterface')) then
    begin
      Continue;
    end;
    mName := InterfaceNameToken(ATokens, mIndex);
    if (mName >= 0) and ReadDeclaration(ATokens, mIndex, mName, mDeclaration) then
    begin
      Result := Result + [mDeclaration];
    end;
  end;
end;

{ TInterfaceGuidRule }

function TInterfaceGuidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('interface-guid', TRuleSeverity.Warning,
    cTexts[TGeneralText.InterfaceGuidTitle].Text);
end;

/// <summary>Wird AName mit Supports, as oder QueryInterface abgefragt?</summary>
function IsQueried(const ATokens: TArray<TPascalToken>; const AName: string): Boolean;
var
  Index, Previous, Inner: Integer;
begin
  for Index := 0 to High(ATokens) do
  begin
    if (ATokens[Index].Kind <> TPascalTokenKind.Identifier) or not SameText(ATokens[Index].Text, AName) then
    begin
      Continue;
    end;
    Previous := PreviousCode(ATokens, Index);
    if (Previous >= 0) and ATokens[Previous].IsKeyword('as') then
    begin
      Exit(True);
    end;
    // Supports(X, IFoo, …) bzw. QueryInterface(IFoo, …): der Name steht in der Argumentliste.
    for Inner := Index - 1 downto Max(0, Index - 8) do
    begin
      if (ATokens[Inner].Kind = TPascalTokenKind.Identifier) and
        (SameText(ATokens[Inner].Text, 'Supports') or SameText(ATokens[Inner].Text, 'QueryInterface')) then
      begin
        Exit(True);
      end
      else if ATokens[Inner].IsSymbol(';') then
      begin
        Break;
      end;
    end;
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
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  for Declaration in InterfaceDeclarations(Tokens) do
  begin
    // Ein dispinterface ohne GUID übersetzt nicht; das meldet dispinterface-invalid als Fehler (wie E2229, #1374).
    if (Declaration.GuidToken >= 0) or Declaration.IsDispinterface then
    begin
      Continue;
    end;
    // Nur die Abfrage meldet dcc, an ihrer Stelle (E2232, #1382).
    mCode := '';
    if IsQueried(Tokens, Declaration.Name) then
    begin
      Confidence := TRuleConfidence.High;
      mCode := cTexts[TGeneralText.LikeE2232].Text;
    end
    else
    begin
      Confidence := TRuleConfidence.Low;
    end;
    Indent := LineIndent(AContext.Text, Tokens[Declaration.NameToken].StartPos.Line);
    AReport.Add(TokenRange(Tokens[Declaration.NameToken]),
      cTexts[TGeneralText.InterfaceWithoutGuid].Fmt([Declaration.Name, mCode]), Confidence,
      [TRuleFix.Create(cTexts[TGeneralText.InsertGuid].Text,
        [TRuleEdit.Create(TTextRange.Create(Tokens[Declaration.HeaderEnd].EndPos,
        Tokens[Declaration.HeaderEnd].EndPos),
        TTextLines.LineBreakOf(AContext.Text) + Indent + '  ' + GuidLine)], True)]);
  end;
end;

{ TDuplicateInterfaceGuidRule }

function TDuplicateInterfaceGuidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('duplicate-interface-guid', TRuleSeverity.Error,
    cTexts[TGeneralText.DuplicateGuidTitle].Text);
end;

procedure TDuplicateInterfaceGuidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Declarations: TArray<TInterfaceDeclaration>;
  Index, Other: Integer;
  Token: TPascalToken;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Declarations := InterfaceDeclarations(Tokens);
  for Index := 0 to High(Declarations) do
  begin
    if Declarations[Index].Guid = '' then
    begin
      Continue;
    end;
    for Other := 0 to High(Declarations) do
    begin
      if (Other <> Index) and (Declarations[Other].Guid = Declarations[Index].Guid) then
      begin
        Token := Tokens[Declarations[Index].GuidToken];
        AReport.Add(TokenRange(Token), cTexts[TGeneralText.DuplicateGuid].Fmt([Declarations[Index].Name,
          Declarations[Other].Name]), TRuleConfidence.High,
          [TRuleFix.Create(cTexts[TGeneralText.NewGuid].Text, [TRuleEdit.Create(TokenRange(Token),
            Copy(GuidLine, 2, Length(GuidLine) - 2))])]);
        Break;
      end;
    end;
  end;
end;

{ TGuidSyntaxInvalidRule }

function TGuidSyntaxInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('guid-syntax-invalid', TRuleSeverity.Error,
    cTexts[TGeneralText.GuidSyntaxTitle].Text);
end;

/// <summary>Fehlende geschweifte Klammern der GUID AGuid; '' ohne Fehler.</summary>
function BraceProblem(const AGuid: string): string;
begin
  Result := '';
  if not AGuid.StartsWith('{') and not AGuid.EndsWith('}') then
  begin
    Result := cTexts[TGeneralText.MissingBraces].Text;
  end
  else if not AGuid.StartsWith('{') then
  begin
    Result := cTexts[TGeneralText.MissingOpenBrace].Text;
  end
  else if not AGuid.EndsWith('}') or (Length(AGuid) < 2) then
  begin
    Result := cTexts[TGeneralText.MissingCloseBrace].Text;
  end;
end;

/// <summary>Anzahl und Längen der Blöcke; '' ohne Fehler.</summary>
function BlockProblem(const ABlocks: TArray<string>): string;
const
  Lengths: array[0..4] of Integer = (8, 4, 4, 4, 12);
  Ordinals: array[0..4] of TGeneralText = (TGeneralText.First, TGeneralText.Second, TGeneralText.Third,
    TGeneralText.Fourth, TGeneralText.Last);
var
  mIndex: Integer;
begin
  if Length(ABlocks) <> Length(Lengths) then
  begin
    Exit(cTexts[TGeneralText.BlockCount].Fmt([Length(ABlocks)]));
  end;
  for mIndex := 0 to High(ABlocks) do
  begin
    if Length(ABlocks[mIndex]) <> Lengths[mIndex] then
    begin
      Exit(cTexts[TGeneralText.BlockLength].Fmt([cTexts[Ordinals[mIndex]].Text, Length(ABlocks[mIndex]),
        Lengths[mIndex]]));
    end;
  end;
  Result := '';
end;

/// <summary>Zeichen, die keine Hexadezimalziffern sind; '' ohne Fehler.</summary>
function HexProblem(const ABlocks: TArray<string>): string;
var
  mBlock: string;
  mChar: Char;
begin
  for mBlock in ABlocks do
  begin
    for mChar in mBlock do
    begin
      if not CharInSet(mChar, ['0'..'9', 'A'..'F', 'a'..'f']) then
      begin
        Exit(cTexts[TGeneralText.NoHexDigit].Fmt([mChar]));
      end;
    end;
  end;
  Result := '';
end;

class function TGuidSyntaxInvalidRule.Problem(const AGuid: string): string;
var
  mBlocks: TArray<string>;
begin
  Result := BraceProblem(AGuid);
  if Result = '' then
  begin
    mBlocks := Copy(AGuid, 2, Length(AGuid) - 2).Split(['-']);
    Result := BlockProblem(mBlocks);
    if Result = '' then
    begin
      Result := HexProblem(mBlocks);
    end;
  end;
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
    begin
      Exit;
    end;
    Next := NextCode(Tokens, AIndex + 1);
    if (Next > High(Tokens)) or not (Tokens[Next].IsSymbol(']') or Tokens[Next].IsSymbol(';')) then
    begin
      Exit;
    end;
    Guid := AnsiDequotedStr(Text, '''');
    Message := TGuidSyntaxInvalidRule.Problem(Guid);
    if Message = '' then
    begin
      Exit;
    end;
    Fixes := nil;
    if TGuidSyntaxInvalidRule.Problem('{' + Guid + '}') = '' then
    begin
      Fixes := [TRuleFix.Create(cTexts[TGeneralText.AddBraces].Text, [TRuleEdit.Create(TokenRange(Tokens[AIndex]),
        '''{' + Guid + '}''')], True)];
    end;
    Fixes := Fixes + [TRuleFix.Create(cTexts[TGeneralText.NewGuid].Text, [TRuleEdit.Create(TokenRange(Tokens[AIndex]),
      Copy(GuidLine, 2, Length(GuidLine) - 2))])];
    AReport.Add(TokenRange(Tokens[AIndex]), Message + cTexts[TGeneralText.LikeE2204].Text, TRuleConfidence.High, Fixes);
  end;

var
  Declaration: TInterfaceDeclaration;
  Index, Colon, Equals: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  for Declaration in InterfaceDeclarations(Tokens) do
  begin
    if (Declaration.GuidToken >= 0) and (Tokens[Declaration.GuidToken].Kind = TPascalTokenKind.StringLiteral) then
    begin
      CheckLiteral(Declaration.GuidToken);
    end;
  end;
  // Typisierte Konstanten: Name: TGUID = '…';
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].Kind <> TPascalTokenKind.StringLiteral) then
    begin
      Continue;
    end;
    Equals := PreviousCode(Tokens, Index);
    if (Equals < 0) or not Tokens[Equals].IsSymbol('=') then
    begin
      Continue;
    end;
    Colon := PreviousCode(Tokens, PreviousCode(Tokens, Equals));
    if (Colon >= 0) and Tokens[Colon].IsSymbol(':') and
      SameText(Tokens[PreviousCode(Tokens, Equals)].Text, 'TGUID') then
    begin
      CheckLiteral(Index);
    end;
  end;
end;

{ TFileHeaderRule }

function TFileHeaderRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('file-header', TRuleSeverity.Hint, cTexts[TGeneralText.FileHeaderTitle].Text, True);
end;

class function TFileHeaderRule.Template(const AOptions: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if Value is TJSONObject then
    begin
      TJSONObject(Value).TryGetValue<string>('template', Result);
    end;
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
  begin
    Exit;
  end;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Header := StringReplace(StringReplace(Header, #13#10, #10, [rfReplaceAll]), #10, LineBreak, [rfReplaceAll]);
  Text := AContext.Text;
  if (Text <> '') and (Text[1] = #$FEFF) then
  begin
    Delete(Text, 1, 1);
  end;
  if StartsStr(Header, Text) then
  begin
    Exit;
  end;
  AReport.Add(TTextRange.Create(0, 0, 0, 0), cTexts[TGeneralText.FileHeader].Text, TRuleConfidence.High,
    [TRuleFix.Create(cTexts[TGeneralText.InsertFileHeader].Text, [TRuleEdit.Create(TTextRange.Create(0, 0, 0, 0),
      Header + LineBreak)])]);
end;

{ THardcodedStringRule }

function THardcodedStringRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('hardcoded-string', TRuleSeverity.Hint,
    cTexts[TGeneralText.HardcodedStringTitle].Text,
    True);
end;

/// <summary>Sieht der Literalinhalt nach Text für Menschen aus: mindestens zwei Wörter mit Buchstaben?</summary>
function LooksLikeText(const AValue: string): Boolean;
var
  Index, Letters: Integer;
begin
  Letters := 0;
  for Index := 1 to Length(AValue) do
  begin
    if AValue[Index].IsLetter then
    begin
      Inc(Letters);
    end;
  end;
  Result := (Letters >= 3) and (Pos(' ', Trim(AValue)) > 0);
end;

/// <summary>Tiefe der Anweisungsblöcke ADepth zum Schlüsselwort AToken nachführen.</summary>
procedure TrackBlockDepth(const AToken: TPascalToken; var ADepth: Integer);
begin
  if AToken.IsKeyword('begin') then
  begin
    Inc(ADepth);
  end
  else if (ADepth > 0) and (AToken.IsKeyword('try') or AToken.IsKeyword('case') or AToken.IsKeyword('asm')) then
  begin
    Inc(ADepth);
  end
  else if (ADepth > 0) and AToken.IsKeyword('end') then
  begin
    Dec(ADepth);
  end;
end;

const
  /// <summary>Routinen, deren Text-Argumente kein Benutzer liest: Prüfungen, Vergleiche, Registry, Masken.</summary>
  cMachineTextCalls: array[0..30] of string = ('Assert', 'OutputDebugString', 'Diagnose', 'Trace', 'Debug',
    'StartsText', 'EndsText', 'StartsStr', 'EndsStr', 'ContainsText', 'ContainsStr', 'SameText', 'SameStr',
    'AnsiSameText', 'Pos', 'PosEx', 'IndexText', 'IndexStr', 'MatchText', 'MatchStr', 'StartsWith', 'EndsWith',
    'ReadString', 'ReadInteger', 'ReadBool', 'WriteString', 'ValueExists', 'OpenKey', 'OpenKeyReadOnly',
    'FormatDateTime', 'FormatFloat');

/// <summary>Protokoll- oder Maschinenaufruf AName (auch mit Präfix F/A wie FLog, ADiagnose) oder einer aus
/// AIgnored?</summary>
function IsMachineTextCall(const AName: string; const AIgnored: TArray<string>): Boolean;
var
  mName: string;
begin
  mName := AName;
  if (Length(mName) > 2) and CharInSet(mName[1], ['F', 'A']) and CharInSet(mName[2], ['A'..'Z']) then
  begin
    mName := Copy(mName, 2, MaxInt);
  end;
  Result := StartsStr('Log', mName) or EndsStr('Log', mName) or MatchText(mName, cMachineTextCalls) or
    MatchText(AName, AIgnored);
end;

/// <summary>Steht das Literal AIndex in den Argumenten eines Aufrufs aus IsMachineTextCall, auch verschachtelt
/// (Log(Format('…')))? Gesucht wird rückwärts bis zum Anfang der Anweisung.</summary>
function InMachineTextCall(const ATokens: TArray<TPascalToken>; AIndex: Integer;
  const AIgnored: TArray<string>): Boolean;
var
  mIndex, mDepth, mCallee: Integer;
begin
  Result := False;
  mDepth := 0;
  mIndex := PreviousCode(ATokens, AIndex);
  while mIndex >= 0 do
  begin
    if ATokens[mIndex].IsSymbol(')') or ATokens[mIndex].IsSymbol(']') then
    begin
      Inc(mDepth);
    end
    else if (ATokens[mIndex].IsSymbol('(') or ATokens[mIndex].IsSymbol('[')) and (mDepth > 0) then
    begin
      Dec(mDepth);
    end
    else if ATokens[mIndex].IsSymbol('(') then
    begin
      mCallee := PreviousCode(ATokens, mIndex);
      if (mCallee >= 0) and (ATokens[mCallee].Kind = TPascalTokenKind.Identifier) and
        IsMachineTextCall(ATokens[mCallee].Text, AIgnored) then
      begin
        Exit(True);
      end;
    end
    else if (mDepth = 0) and (ATokens[mIndex].IsSymbol(';') or (ATokens[mIndex].Kind = TPascalTokenKind.Keyword)) then
    begin
      Exit;
    end;
    mIndex := PreviousCode(ATokens, mIndex);
  end;
end;

/// <summary>Font.Name := 'Segoe UI': Schriftnamen übersetzt niemand.</summary>
function IsFontName(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mAssign, mName, mDot: Integer;
begin
  mAssign := PreviousCode(ATokens, AIndex);
  mName := PreviousCode(ATokens, mAssign);
  mDot := PreviousCode(ATokens, mName);
  Result := (mDot > 0) and ATokens[mAssign].IsSymbol(':=') and SameText(ATokens[mName].Text, 'Name') and
    ATokens[mDot].IsSymbol('.') and SameText(ATokens[PreviousCode(ATokens, mDot)].Text, 'Font');
end;

/// <summary>Markup oder Daten statt Text: HTML/XML (&lt;), JSON ({ oder "Schlüssel":), Markdown-Überschrift (# bzw.
/// ##). Ein Text, der nur mit einem Zitat beginnt ('"%s" ist keine Formulardatei'), zählt nicht.</summary>
function LooksLikeMarkup(const AValue: string): Boolean;
var
  mText: string;
begin
  mText := TrimLeft(AValue);
  if mText = '' then
  begin
    Exit(False);
  end;
  case mText[1] of
    '<', '{':
      Result := True;
    '"':
      Result := Pos('":', mText) > 0;
    '#':
      Result := (Length(mText) > 1) and CharInSet(mText[2], ['#', ' ']);
  else
    Result := False;
  end;
end;

procedure THardcodedStringRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Index, Depth: Integer;
  Value: string;
  Ignored: TArray<string>;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Ignored := TRuleOptions.Strings(AContext.Options, 'ignoreCalls', nil);
  Tokens := AContext.Tree.Tokens;
  Depth := 0;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Kind = TPascalTokenKind.Keyword then
    begin
      TrackBlockDepth(Tokens[Index], Depth);
      Continue;
    end;
    // Nur Anweisungen: Konstanten- und resourcestring-Abschnitte stehen außerhalb von begin … end.
    if (Depth = 0) or (Tokens[Index].Kind <> TPascalTokenKind.StringLiteral) then
    begin
      Continue;
    end;
    Value := AnsiDequotedStr(Tokens[Index].Text, '''');
    if LooksLikeText(Value) and not LooksLikeMarkup(Value) and not IsFontName(Tokens, Index) and
      not InMachineTextCall(Tokens, Index, Ignored) then
    begin
      AReport.Add(TokenRange(Tokens[Index]), cTexts[TGeneralText.HardcodedString].Text,
        TRuleConfidence.Low);
    end;
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.General', cTexts);

end.
