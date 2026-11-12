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
  Atlas.Common.Pascal.TokenCursor,
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

/// <summary>Einrückung der Zeile ALine von AText.</summary>
function LineIndent(const AText: string; ALine: Integer): string;
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  mLines := StringReplace(AText, #13#10, #10, [rfReplaceAll]).Split([#10]);
  Result := '';
  if ALine > High(mLines) then
  begin
    Exit;
  end;
  mIndex := 1;
  while (mIndex <= Length(mLines[ALine])) and CharInSet(mLines[ALine][mIndex], [' ', #9]) do
  begin
    Inc(mIndex);
  end;
  Result := Copy(mLines[ALine], 1, mIndex - 1);
end;

function GuidLine: string;
var
  mGuid: TGUID;
begin
  if CreateGUID(mGuid) <> 0 then
  begin
    raise EOSError.Create(cTexts[TGeneralText.GuidNotCreated].Text);
  end;
  Result := '[''' + GUIDToString(mGuid) + ''']';
end;

{ TEmptyExceptRule }

function TEmptyExceptRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('empty-except', TRuleSeverity.Warning, cTexts[TGeneralText.EmptyExceptTitle].Text);
end;

procedure TEmptyExceptRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mIndex, mNext: Integer;
  mCommented: Boolean;
  mIndent: string;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if (mTokens[mIndex].Kind <> TPascalTokenKind.Keyword) or not mTokens[mIndex].IsKeyword('except') then
    begin
      Continue;
    end;
    // Zwischen except und end steht nichts außer Kommentaren und Direktiven.
    mNext := mIndex + 1;
    mCommented := False;
    while (mNext <= High(mTokens)) and IsTrivia(mTokens[mNext]) do
    begin
      if mTokens[mNext].Kind = TPascalTokenKind.Comment then
      begin
        mCommented := True;
      end;
      Inc(mNext);
    end;
    if (mNext > High(mTokens)) or not mTokens[mNext].IsKeyword('end') or mCommented then
    begin
      Continue;
    end;
    mIndent := LineIndent(AContext.Text, mTokens[mIndex].StartPos.Line);
    AReport.Add(TokenRange(mTokens[mIndex]), cTexts[TGeneralText.EmptyExcept].Text, TRuleConfidence.High,
      [TRuleFix.Create(cTexts[TGeneralText.InsertRaise].Text,
        [TRuleEdit.Create(TTextRange.Create(mTokens[mIndex].EndPos,
        mTokens[mIndex].EndPos), TTextLines.LineBreakOf(AContext.Text) + mIndent + '  raise;')])]);
  end;
end;

{ TEmptyFinallyRule }

function TEmptyFinallyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('empty-finally', TRuleSeverity.Hint, cTexts[TGeneralText.EmptyFinallyTitle].Text);
end;

procedure TEmptyFinallyRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mLines: TArray<string>;
  mLineBreak: string;

  function IsEmptyBlock(ABlock: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to ABlock.ChildCount - 1 do
    begin
      if ABlock[mIndex].Kind <> TSyntaxKind.EmptyStatement then
      begin
        Exit(False);
      end;
    end;
    Result := True;
  end;

  // Index des Tokens mit dem Schlüsselwort AWord ab Offset AFrom (erstes) bzw. vor ABefore (letztes); -1 ohne.
  function FirstKeyword(const AWord: string; AFrom: Integer): Integer;
  begin
    for Result := 0 to High(mTokens) do
    begin
      if (mTokens[Result].Offset >= AFrom) and mTokens[Result].IsKeyword(AWord) then
      begin
        Exit;
      end;
    end;
    Result := -1;
  end;

  function LastKeyword(const AWord: string; ABefore: Integer): Integer;
  begin
    for Result := High(mTokens) downto 0 do
    begin
      if (mTokens[Result].Offset < ABefore) and mTokens[Result].IsKeyword(AWord) then
      begin
        Exit;
      end;
    end;
    Result := -1;
  end;

  // Variable aus X := T….Create direkt vor dem try; '' ohne.
  function CreatedVariable(ATry: TSyntaxNode): string;
  var
    mParent, mPrevious, mValue: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := '';
    mParent := ATry.Parent;
    if mParent = nil then
    begin
      Exit;
    end;
    mPrevious := nil;
    for mIndex := 1 to mParent.ChildCount - 1 do
    begin
      if mParent[mIndex] = ATry then
      begin
        mPrevious := mParent[mIndex - 1];
      end;
    end;
    if (mPrevious = nil) or (mPrevious.Kind <> TSyntaxKind.AssignStatement) or (mPrevious.ChildCount <> 2) or
      (mPrevious[0].Kind <> TSyntaxKind.Identifier) then
    begin
      Exit;
    end;
    mValue := mPrevious[1];
    if (mValue.Kind = TSyntaxKind.Call) and (mValue.ChildCount > 0) then
    begin
      mValue := mValue[0];
    end;
    if (mValue.Kind = TSyntaxKind.MemberAccess) and SameText(mValue.Name, 'Create') then
    begin
      Result := mPrevious[0].Name;
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
    Result := (AEndLine <= High(mLines)) and (Trim(mLines[ATryLine]) = 'try') and
      (Trim(mLines[AFinallyLine]) = 'finally');
    if Result then
    begin
      AEnding := Trim(mLines[AEndLine]);
      Result := (AEnding = 'end') or (AEnding = 'end;');
    end;
  end;

  /// <summary>Rumpf zwischen try und finally als begin … end.</summary>
  function BeginEndBody(ATryLine, AFinallyLine, AEndLine: Integer): TArray<string>;
  var
    mLine: Integer;
  begin
    Result := [TTextLines.IndentOf(mLines[ATryLine]) + 'begin'];
    for mLine := ATryLine + 1 to AFinallyLine - 1 do
    begin
      Result := Result + [mLines[mLine]];
    end;
    Result := Result + [mLines[AEndLine]];
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
      if Trim(mLines[mLine]) <> '' then
      begin
        Result := Min(Result, TTextLines.IndentLength(mLines[mLine]) - TTextLines.IndentLength(mLines[ATryLine]));
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
      if Trim(mLines[mLine]) = '' then
      begin
        Result := Result + [''];
      end
      else
      begin
        Result := Result + [Copy(mLines[mLine], mShift + 1, MaxInt)];
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
    mTryLine := mTokens[ATryToken].StartPos.Line;
    mFinallyLine := mTokens[AFinallyToken].StartPos.Line;
    mEndLine := mTokens[AEndToken].StartPos.Line;
    if not OwnLines(mTryLine, mFinallyLine, mEndLine, mEnding) then
    begin
      Exit(False);
    end;
    mRange := TTextRange.Create(TTextPosition.Create(mTryLine, 0), TTextPosition.Create(mEndLine,
      Length(mLines[mEndLine])));
    if not InStatementList(ATry) and (StatementCount(ATry) > 1) then
    begin
      AFix := TRuleFix.Create(cTexts[TGeneralText.ReplaceTryByBegin].Text,
        [TRuleEdit.Create(mRange, TTextLines.JoinLines(BeginEndBody(mTryLine, mFinallyLine, mEndLine), mLineBreak))]);
      Exit(True);
    end;
    // Rumpf um den Unterschied zwischen seiner Einrückung und der von try ausrücken.
    mBody := OutdentedBody(mTryLine, mFinallyLine, mEnding);
    Result := mBody <> nil;
    if Result then
    begin
      AFix := TRuleFix.Create(cTexts[TGeneralText.RemoveTry].Text,
        [TRuleEdit.Create(mRange, TTextLines.JoinLines(mBody, mLineBreak))]);
    end;
  end;

  procedure CheckTry(ATry: TSyntaxNode);
  var
    mBlock: TSyntaxNode;
    mTryToken, mFinallyToken, mEndToken, mIndex: Integer;
    mVariable, mMessage: string;
    mRuleFix: TRuleFix;
  begin
    mBlock := ATry[ATry.ChildCount - 1];
    if (mBlock.Kind <> TSyntaxKind.FinallyBlock) or not IsEmptyBlock(mBlock) then
    begin
      Exit;
    end;
    mTryToken := FirstKeyword('try', ATry.StartOffset);
    mFinallyToken := LastKeyword('finally', ATry.EndOffset);
    mEndToken := LastKeyword('end', ATry.EndOffset);
    if (mTryToken < 0) or (mFinallyToken < 0) or (mEndToken <= mFinallyToken) then
    begin
      Exit;
    end;
    // Ein Kommentar begründet den leeren Block; eine Direktive kann Code eines anderen Zweigs enthalten.
    for mIndex := mFinallyToken + 1 to mEndToken - 1 do
    begin
      if mTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
      begin
        Exit;
      end;
    end;
    mVariable := CreatedVariable(ATry);
    if mVariable <> '' then
    begin
      mMessage := cTexts[TGeneralText.EmptyFinallyFree].Fmt([mVariable]);
    end
    else
    begin
      mMessage := cTexts[TGeneralText.EmptyFinally].Text;
    end;
    if Fix(ATry, mTryToken, mFinallyToken, mEndToken, mRuleFix) then
    begin
      AReport.Add(TokenRange(mTokens[mFinallyToken]), mMessage, TRuleConfidence.High, [mRuleFix]);
    end
    else
    begin
      AReport.Add(TokenRange(mTokens[mFinallyToken]), mMessage, TRuleConfidence.High, []);
    end;
  end;

  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  procedure Walk(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.TryStatement) and (mNode.ChildCount > 0) then
        begin
          CheckTry(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
  Walk(AContext.Tree.Root);
end;

{ Interface-Deklarationen }

type
  /// <summary>Interface-Typ der Datei mit seiner GUID ('' ohne).</summary>
  TInterfaceDeclaration = record
    Name: string;
    NameToken: Integer;
    /// <summary>Token, hinter dem die GUID-Zeile eingefügt wird: interface bzw. die schließende Klammer der
    /// Vorfahren.</summary>
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
  mIndex, mPrevious, mInner: Integer;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    if (ATokens[mIndex].Kind <> TPascalTokenKind.Identifier) or not SameText(ATokens[mIndex].Text, AName) then
    begin
      Continue;
    end;
    mPrevious := PreviousCode(ATokens, mIndex);
    if (mPrevious >= 0) and ATokens[mPrevious].IsKeyword('as') then
    begin
      Exit(True);
    end;
    // Supports(X, IFoo, …) bzw. QueryInterface(IFoo, …): der Name steht in der Argumentliste.
    for mInner := mIndex - 1 downto Max(0, mIndex - 8) do
    begin
      if (ATokens[mInner].Kind = TPascalTokenKind.Identifier) and
        (SameText(ATokens[mInner].Text, 'Supports') or SameText(ATokens[mInner].Text, 'QueryInterface')) then
      begin
        Exit(True);
      end
      else if ATokens[mInner].IsSymbol(';') then
      begin
        Break;
      end;
    end;
  end;
  Result := False;
end;

procedure TInterfaceGuidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mDeclaration: TInterfaceDeclaration;
  mConfidence: TRuleConfidence;
  mIndent, mCode: string;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  for mDeclaration in InterfaceDeclarations(mTokens) do
  begin
    // Ein dispinterface ohne GUID übersetzt nicht; das meldet dispinterface-invalid als Fehler (wie E2229, #1374).
    if (mDeclaration.GuidToken >= 0) or mDeclaration.IsDispinterface then
    begin
      Continue;
    end;
    // Nur die Abfrage meldet dcc, an ihrer Stelle (E2232, #1382).
    mCode := '';
    if IsQueried(mTokens, mDeclaration.Name) then
    begin
      mConfidence := TRuleConfidence.High;
      mCode := cTexts[TGeneralText.LikeE2232].Text;
    end
    else
    begin
      mConfidence := TRuleConfidence.Low;
    end;
    mIndent := LineIndent(AContext.Text, mTokens[mDeclaration.NameToken].StartPos.Line);
    AReport.Add(TokenRange(mTokens[mDeclaration.NameToken]),
      cTexts[TGeneralText.InterfaceWithoutGuid].Fmt([mDeclaration.Name, mCode]), mConfidence,
      [TRuleFix.Create(cTexts[TGeneralText.InsertGuid].Text,
        [TRuleEdit.Create(TTextRange.Create(mTokens[mDeclaration.HeaderEnd].EndPos,
        mTokens[mDeclaration.HeaderEnd].EndPos),
        TTextLines.LineBreakOf(AContext.Text) + mIndent + '  ' + GuidLine)], True)]);
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
  mTokens: TArray<TPascalToken>;
  mDeclarations: TArray<TInterfaceDeclaration>;
  mIndex, mOther: Integer;
  mToken: TPascalToken;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mDeclarations := InterfaceDeclarations(mTokens);
  for mIndex := 0 to High(mDeclarations) do
  begin
    if mDeclarations[mIndex].Guid = '' then
    begin
      Continue;
    end;
    for mOther := 0 to High(mDeclarations) do
    begin
      if (mOther <> mIndex) and (mDeclarations[mOther].Guid = mDeclarations[mIndex].Guid) then
      begin
        mToken := mTokens[mDeclarations[mIndex].GuidToken];
        AReport.Add(TokenRange(mToken), cTexts[TGeneralText.DuplicateGuid].Fmt([mDeclarations[mIndex].Name,
          mDeclarations[mOther].Name]), TRuleConfidence.High,
          [TRuleFix.Create(cTexts[TGeneralText.NewGuid].Text, [TRuleEdit.Create(TokenRange(mToken),
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
  cLengths: array[0..4] of Integer = (8, 4, 4, 4, 12);
  cOrdinals: array[0..4] of TGeneralText = (TGeneralText.First, TGeneralText.Second, TGeneralText.Third,
    TGeneralText.Fourth, TGeneralText.Last);
var
  mIndex: Integer;
begin
  if Length(ABlocks) <> Length(cLengths) then
  begin
    Exit(cTexts[TGeneralText.BlockCount].Fmt([Length(ABlocks)]));
  end;
  for mIndex := 0 to High(ABlocks) do
  begin
    if Length(ABlocks[mIndex]) <> cLengths[mIndex] then
    begin
      Exit(cTexts[TGeneralText.BlockLength].Fmt([cTexts[cOrdinals[mIndex]].Text, Length(ABlocks[mIndex]),
        cLengths[mIndex]]));
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
  mTokens: TArray<TPascalToken>;

  procedure CheckLiteral(AIndex: Integer);
  var
    mText, mGuid, mMessage: string;
    mFixes: TArray<TRuleFix>;
    mNext: Integer;
  begin
    mText := mTokens[AIndex].Text;
    // Nur ein einzelnes Literal ohne #-Zeichen; Verkettungen wertet erst der Compiler aus.
    if not mText.StartsWith('''') or not mText.EndsWith('''') or (Length(mText) < 2) then
    begin
      Exit;
    end;
    mNext := NextCode(mTokens, AIndex + 1);
    if (mNext > High(mTokens)) or not (mTokens[mNext].IsSymbol(']') or mTokens[mNext].IsSymbol(';')) then
    begin
      Exit;
    end;
    mGuid := AnsiDequotedStr(mText, '''');
    mMessage := TGuidSyntaxInvalidRule.Problem(mGuid);
    if mMessage = '' then
    begin
      Exit;
    end;
    mFixes := nil;
    if TGuidSyntaxInvalidRule.Problem('{' + mGuid + '}') = '' then
    begin
      mFixes := [TRuleFix.Create(cTexts[TGeneralText.AddBraces].Text, [TRuleEdit.Create(TokenRange(mTokens[AIndex]),
        '''{' + mGuid + '}''')], True)];
    end;
    mFixes := mFixes + [TRuleFix.Create(cTexts[TGeneralText.NewGuid].Text,
      [TRuleEdit.Create(TokenRange(mTokens[AIndex]),
      Copy(GuidLine, 2, Length(GuidLine) - 2))])];
    AReport.Add(TokenRange(mTokens[AIndex]), mMessage + cTexts[TGeneralText.LikeE2204].Text, TRuleConfidence.High,
      mFixes);
  end;

var
  mDeclaration: TInterfaceDeclaration;
  mIndex, mColon, mEquals: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  for mDeclaration in InterfaceDeclarations(mTokens) do
  begin
    if (mDeclaration.GuidToken >= 0) and (mTokens[mDeclaration.GuidToken].Kind = TPascalTokenKind.StringLiteral) then
    begin
      CheckLiteral(mDeclaration.GuidToken);
    end;
  end;
  // Typisierte Konstanten: Name: TGUID = '…';
  for mIndex := 0 to High(mTokens) do
  begin
    if mTokens[mIndex].Kind <> TPascalTokenKind.StringLiteral then
    begin
      Continue;
    end;
    mEquals := PreviousCode(mTokens, mIndex);
    if (mEquals < 0) or not mTokens[mEquals].IsSymbol('=') then
    begin
      Continue;
    end;
    mColon := PreviousCode(mTokens, PreviousCode(mTokens, mEquals));
    if (mColon >= 0) and mTokens[mColon].IsSymbol(':') and
      SameText(mTokens[PreviousCode(mTokens, mEquals)].Text, 'TGUID') then
    begin
      CheckLiteral(mIndex);
    end;
  end;
end;

{ TFileHeaderRule }

function TFileHeaderRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('file-header', TRuleSeverity.Hint, cTexts[TGeneralText.FileHeaderTitle].Text);
end;

class function TFileHeaderRule.Template(const AOptions: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AOptions);
  try
    if mValue is TJSONObject then
    begin
      TJSONObject(mValue).TryGetValue<string>('template', Result);
    end;
  finally
    mValue.Free;
  end;
end;

procedure TFileHeaderRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mHeader, mText, mLineBreak: string;
begin
  mHeader := Template(AContext.Options);
  if mHeader = '' then
  begin
    Exit;
  end;
  mLineBreak := TTextLines.LineBreakOf(AContext.Text);
  mHeader := StringReplace(StringReplace(mHeader, #13#10, #10, [rfReplaceAll]), #10, mLineBreak, [rfReplaceAll]);
  mText := AContext.Text;
  if (mText <> '') and (mText[1] = #$FEFF) then
  begin
    Delete(mText, 1, 1);
  end;
  if StartsStr(mHeader, mText) then
  begin
    Exit;
  end;
  AReport.Add(TTextRange.Create(0, 0, 0, 0), cTexts[TGeneralText.FileHeader].Text, TRuleConfidence.High,
    [TRuleFix.Create(cTexts[TGeneralText.InsertFileHeader].Text, [TRuleEdit.Create(TTextRange.Create(0, 0, 0, 0),
      mHeader + mLineBreak)])]);
end;

{ THardcodedStringRule }

function THardcodedStringRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('hardcoded-string', TRuleSeverity.Hint,
    cTexts[TGeneralText.HardcodedStringTitle].Text);
end;

/// <summary>Sieht der Literalinhalt nach Text für Menschen aus: mindestens zwei Wörter mit Buchstaben?</summary>
function LooksLikeText(const AValue: string): Boolean;
var
  mIndex, mLetters: Integer;
begin
  mLetters := 0;
  for mIndex := 1 to Length(AValue) do
  begin
    if AValue[mIndex].IsLetter then
    begin
      Inc(mLetters);
    end;
  end;
  Result := (mLetters >= 3) and (Pos(' ', Trim(AValue)) > 0);
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
  mTokens: TArray<TPascalToken>;
  mIndex, mDepth: Integer;
  mValue: string;
  mIgnored: TArray<string>;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mIgnored := TRuleOptions.Strings(AContext.Options, 'ignoreCalls', nil);
  mTokens := AContext.Tree.Tokens;
  mDepth := 0;
  for mIndex := 0 to High(mTokens) do
  begin
    if mTokens[mIndex].Kind = TPascalTokenKind.Keyword then
    begin
      TrackBlockDepth(mTokens[mIndex], mDepth);
      Continue;
    end;
    // Nur Anweisungen: Konstanten- und resourcestring-Abschnitte stehen außerhalb von begin … end.
    if (mDepth = 0) or (mTokens[mIndex].Kind <> TPascalTokenKind.StringLiteral) then
    begin
      Continue;
    end;
    mValue := AnsiDequotedStr(mTokens[mIndex].Text, '''');
    if LooksLikeText(mValue) and not LooksLikeMarkup(mValue) and not IsFontName(mTokens, mIndex) and
      not InMachineTextCall(mTokens, mIndex, mIgnored) then
    begin
      AReport.Add(TokenRange(mTokens[mIndex]), cTexts[TGeneralText.HardcodedString].Text,
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
