unit Atlas.Common.Rules.Builtin.Performance;

// Performance-Regeln (#278, abgetrennt aus #57). Alle standardmäßig aus:
//   string-concat-in-loop     S := S + … in einer Schleife; in Delphi meist harmlos
//                             (In-place-Vergrößerung), deshalb nur niedrige Konfidenz
//   loop-invariant-call       teurer Aufruf in der Bedingung von while bzw. until, die bei
//                             jedem Durchlauf neu ausgewertet wird (die Grenzen von for nicht)
//   missing-begin-update      Items/Lines/Strings.Add in einer Schleife ohne BeginUpdate
// Standardmäßig an (#974):
//   setlength-in-loop         SetLength(A, Length(A) + 1) in einer Schleife kopiert das
//                             dynamische Array bei jedem Durchlauf; gemeldet wird nur, wenn A
//                             sicher ein dynamisches Array ist (Typ in der Datei bzw. bekannter
//                             RTL-Typ, nie Strings). Bei einer for-Schleife ist die Anzahl
//                             bekannt; dann setzt die Korrektur die Länge vor der Schleife,
//                             wenn A eine lokale Variable ist, die vorher nicht benutzt wird,
//                             und A in der Schleife nur über A[High(A)] bzw. A[Length(A) - 1]
//                             beschrieben wird.
// ParamByName in Schleifen und DisableControls gehören zu #70.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TStringConcatInLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TLoopInvariantCallRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TMissingBeginUpdateRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSetLengthInLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die Performance-Regeln.</summary>
procedure RegisterPerformanceRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Rules.Derived;

type
  TTokens = TArray<TPascalToken>;

  /// <summary>Schleife mit Rumpf und (bei while/repeat) Bedingung als Tokenbereiche.</summary>
  TLoop = record
    Keyword: Integer;
    BodyFirst: Integer;
    BodyLast: Integer;
    /// <summary>Bedingung von while bzw. until; CondFirst > CondLast bei for.</summary>
    CondFirst: Integer;
    CondLast: Integer;
  end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

function OpensBlock(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('begin') or AToken.IsKeyword('try') or AToken.IsKeyword('case') or
    AToken.IsKeyword('asm') or AToken.IsKeyword('repeat');
end;

/// <summary>Letztes Token der Anweisung ab AFirst: bis zum passenden end bzw. vor ; oder end.</summary>
function StatementEnd(const ATokens: TTokens; AFirst: Integer): Integer;
var
  Index, Depth: Integer;
begin
  Depth := 0;
  Index := AFirst;
  Result := AFirst;
  while Index <= High(ATokens) do
  begin
    if OpensBlock(ATokens[Index]) then
      Inc(Depth)
    else if ATokens[Index].IsKeyword('until') then
      Dec(Depth)
    else if ATokens[Index].IsKeyword('end') then
    begin
      if Depth = 0 then
        Exit;
      Dec(Depth);
      if Depth = 0 then
        Exit(Index);
    end
    else if (Depth = 0) and (ATokens[Index].IsSymbol(';') or ATokens[Index].IsKeyword('else')) then
      Exit;
    if not IsTrivia(ATokens[Index]) then
      Result := Index;
    Inc(Index);
  end;
end;

/// <summary>Index von do bzw. until ab AFirst auf gleicher Klammerebene; -1 ohne.</summary>
function FindKeyword(const ATokens: TTokens; AFirst: Integer; const AKeyword: string): Integer;
var
  Index, Depth: Integer;
begin
  Depth := 0;
  for Index := AFirst to High(ATokens) do
    if (Depth = 0) and ATokens[Index].IsKeyword(AKeyword) then
      Exit(Index)
    else if (AKeyword = 'until') and ATokens[Index].IsKeyword('repeat') then
      Inc(Depth)
    else if (AKeyword = 'until') and ATokens[Index].IsKeyword('until') then
      Dec(Depth)
    else if (AKeyword = 'do') and ATokens[Index].IsSymbol(';') then
      Exit(-1);
  Result := -1;
end;

function Loops(const ATokens: TTokens): TArray<TLoop>;
var
  Index, Mark: Integer;
  Loop: TLoop;
begin
  Result := nil;
  for Index := 0 to High(ATokens) do
  begin
    Loop := Default(TLoop);
    Loop.Keyword := Index;
    if ATokens[Index].IsKeyword('for') or ATokens[Index].IsKeyword('while') then
    begin
      Mark := FindKeyword(ATokens, Index + 1, 'do');
      if Mark < 0 then
        Continue;
      Loop.BodyFirst := NextCode(ATokens, Mark + 1);
      if Loop.BodyFirst > High(ATokens) then
        Continue;
      Loop.BodyLast := StatementEnd(ATokens, Loop.BodyFirst);
      if ATokens[Index].IsKeyword('while') then
      begin
        Loop.CondFirst := NextCode(ATokens, Index + 1);
        Loop.CondLast := PreviousCode(ATokens, Mark);
      end
      else
      begin
        Loop.CondFirst := 1;
        Loop.CondLast := 0;
      end;
    end
    else if ATokens[Index].IsKeyword('repeat') then
    begin
      Mark := FindKeyword(ATokens, Index + 1, 'until');
      if Mark < 0 then
        Continue;
      Loop.BodyFirst := Index + 1;
      Loop.BodyLast := PreviousCode(ATokens, Mark);
      Loop.CondFirst := NextCode(ATokens, Mark + 1);
      Loop.CondLast := StatementEnd(ATokens, Loop.CondFirst);
    end
    else
      Continue;
    Result := Result + [Loop];
  end;
end;

/// <summary>Liegt Token AIndex im Rumpf einer der Schleifen?</summary>
function InLoopBody(const ALoops: TArray<TLoop>; AIndex: Integer): Boolean;
var
  Loop: TLoop;
begin
  for Loop in ALoops do
    if (AIndex >= Loop.BodyFirst) and (AIndex <= Loop.BodyLast) then
      Exit(True);
  Result := False;
end;

/// <summary>Beginnt an AIndex ein Bezeichner, dem kein Punkt vorausgeht?</summary>
function StartsDesignator(const ATokens: TTokens; AIndex: Integer): Boolean;
begin
  Result := (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    ((AIndex = 0) or not ATokens[PreviousCode(ATokens, AIndex)].IsSymbol('.'));
end;

/// <summary>Punktkette ab AIndex (A.B.C) als Text in Kleinbuchstaben; ALast = letztes Token.</summary>
function Chain(const ATokens: TTokens; AIndex: Integer; out ALast: Integer): string;
var
  Dot: Integer;
begin
  Result := LowerCase(ATokens[AIndex].Text);
  ALast := AIndex;
  Dot := NextCode(ATokens, ALast + 1);
  while (Dot < High(ATokens)) and ATokens[Dot].IsSymbol('.') and
    (ATokens[NextCode(ATokens, Dot + 1)].Kind = TPascalTokenKind.Identifier) do
  begin
    ALast := NextCode(ATokens, Dot + 1);
    Result := Result + '.' + LowerCase(ATokens[ALast].Text);
    Dot := NextCode(ATokens, ALast + 1);
  end;
end;

{ TStringConcatInLoopRule }

function TStringConcatInLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('string-concat-in-loop', TRuleSeverity.Hint,
    'String-Verkettung in einer Schleife', True);
end;

procedure TStringConcatInLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Found: TArray<TLoop>;
  Types: TDeclaredTypes;
  Index, Assign, Same, Plus, Last: Integer;
  TypeName: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Found := Loops(Tokens);
  if Found = nil then
    Exit;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      // S := S + …
      if not StartsDesignator(Tokens, Index) or not InLoopBody(Found, Index) then
        Continue;
      Assign := NextCode(Tokens, Index + 1);
      Same := NextCode(Tokens, Assign + 1);
      Plus := NextCode(Tokens, Same + 1);
      if (Plus > High(Tokens)) or not Tokens[Assign].IsSymbol(':=') or
        not SameText(Tokens[Same].Text, Tokens[Index].Text) or not Tokens[Plus].IsSymbol('+') then
        Continue;
      TypeName := Types.DeclaredType(Tokens[Index].Text, Tokens[Index].StartPos);
      if not MatchText(TypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'UTF8String',
        'RawByteString']) then
        Continue;
      Last := StatementEnd(Tokens, Index);
      AReport.Add(RangeOf(Tokens, Index, Last), Format('%s wird in der Schleife schrittweise verlängert; bei ' +
        'vielen Durchläufen ist TStringBuilder schneller', [Tokens[Index].Text]), TRuleConfidence.Low);
    end;
  finally
    Types.Free;
  end;
end;

{ TLoopInvariantCallRule }

const
  ExpensiveCalls: array[0..17] of string = ('Trim', 'TrimLeft', 'TrimRight', 'LowerCase', 'UpperCase',
    'AnsiLowerCase', 'AnsiUpperCase', 'Format', 'StrToInt', 'StrToFloat', 'IntToStr', 'FileExists',
    'DirectoryExists', 'ExtractFileName', 'ExtractFilePath', 'StringReplace', 'Copy', 'ComponentCount');
  ExpensiveProperties: array[0..2] of string = ('Text', 'CommaText', 'DelimitedText');

function TLoopInvariantCallRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('loop-invariant-call', TRuleSeverity.Hint,
    'Teurer Aufruf in der Schleifenbedingung', True);
end;

procedure TLoopInvariantCallRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Loop: TLoop;
  Index, Previous: Integer;
  Name: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Loop in Loops(Tokens) do
    for Index := Loop.CondFirst to Loop.CondLast do
    begin
      if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
        Continue;
      Name := Tokens[Index].Text;
      Previous := PreviousCode(Tokens, Index);
      if MatchText(Name, ExpensiveProperties) and (Previous >= 0) and Tokens[Previous].IsSymbol('.') then
        AReport.Add(RangeOf(Tokens, Index, Index), Format('.%s baut bei jeder Prüfung der Bedingung einen neuen ' +
          'String auf; vor der Schleife in eine Variable übernehmen', [Name]), TRuleConfidence.Medium)
      else if MatchText(Name, ExpensiveCalls) and StartsDesignator(Tokens, Index) then
        AReport.Add(RangeOf(Tokens, Index, Index), Format('%s wird bei jeder Prüfung der Bedingung erneut ' +
          'ausgeführt; ändert sich das Ergebnis nicht, vor der Schleife berechnen', [Name]), TRuleConfidence.Medium);
    end;
end;

{ TMissingBeginUpdateRule }

function TMissingBeginUpdateRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('missing-begin-update', TRuleSeverity.Hint,
    'Hinzufügen in einer Schleife ohne BeginUpdate', True);
end;

procedure TMissingBeginUpdateRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Found: TArray<TLoop>;
  Updated, Reported: TArray<string>;
  Index, Last, Dot: Integer;
  Text, Receiver, Method, Collection, ReceiverText: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Found := Loops(Tokens);
  if Found = nil then
    Exit;
  // Empfänger, für die irgendwo in der Datei BeginUpdate aufgerufen wird.
  Updated := nil;
  for Index := 0 to High(Tokens) do
    if StartsDesignator(Tokens, Index) then
    begin
      Text := Chain(Tokens, Index, Last);
      if EndsText('.beginupdate', Text) then
        Updated := Updated + [Copy(Text, 1, Length(Text) - Length('.beginupdate'))];
    end;
  Reported := nil;
  for Index := 0 to High(Tokens) do
  begin
    if not StartsDesignator(Tokens, Index) or not InLoopBody(Found, Index) then
      Continue;
    Text := Chain(Tokens, Index, Last);
    Dot := LastDelimiter('.', Text);
    if Dot = 0 then
      Continue;
    Receiver := Copy(Text, 1, Dot - 1);
    Method := Copy(Text, Dot + 1, MaxInt);
    Collection := Copy(Receiver, LastDelimiter('.', Receiver) + 1, MaxInt);
    // Nur sichtbare Listen: ListBox1.Items, Memo1.Lines, TreeView1.Items; Receiver hat mindestens zwei Glieder.
    if (Pos('.', Receiver) = 0) or not MatchText(Collection, ['items', 'lines', 'strings']) or
      not MatchText(Method, ['add', 'addobject', 'append', 'insert', 'addchild', 'addchildobject', 'addpair']) then
      Continue;
    if MatchText(Receiver, Updated) or MatchText(Copy(Receiver, 1, LastDelimiter('.', Receiver) - 1), Updated) or
      MatchText(Receiver, Reported) then
      Continue;
    Reported := Reported + [Receiver];
    ReceiverText := Copy(AContext.Text, Tokens[Index].Offset + 1,
      Tokens[PreviousCode(Tokens, Last)].Offset - Tokens[Index].Offset);
    AReport.Add(RangeOf(Tokens, Index, Last), Format('Jedes %s in der Schleife zeichnet das Steuerelement neu; ' +
      'die Schleife mit %s.BeginUpdate und try … finally %s.EndUpdate umschließen',
      [Tokens[Last].Text, ReceiverText, ReceiverText]),
      TRuleConfidence.Medium);
  end;
end;

{ TSetLengthInLoopRule }

const
  /// <summary>Dynamische Arrays der RTL, die nicht in der Datei deklariert sind.</summary>
  RtlDynamicArrays: array[0..13] of string = ('TBytes', 'TStringDynArray', 'TIntegerDynArray',
    'TInt64DynArray', 'TCardinalDynArray', 'TDoubleDynArray', 'TSingleDynArray', 'TByteDynArray',
    'TWordDynArray', 'TBooleanDynArray', 'TShortIntDynArray', 'TSmallIntDynArray', 'TLongWordDynArray',
    'TExtendedDynArray');

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Ist ANode der Aufruf AName(X) mit genau einem Argument, dessen Text ATarget ist?</summary>
function IsCallOf(const AText: string; ANode: TSyntaxNode; const AName, ATarget: string): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
    SameText(ANode.Name, AName) and SameText(NodeText(AText, ANode[1]), ATarget);
end;

/// <summary>Ganzzahliges Literal ab 1?</summary>
function IsPositiveLiteral(ANode: TSyntaxNode): Boolean;
var
  Value: Integer;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and TryStrToInt(ANode.Name, Value) and (Value >= 1);
end;

/// <summary>Vergrößert ALength die Länge von ATarget um einen festen Schritt: Length(A) + n, n + Length(A),
/// Succ(Length(A)) oder High(A) + n mit n ab 2?</summary>
function IsGrowth(const AText: string; ALength: TSyntaxNode; const ATarget: string): Boolean;
begin
  Result := False;
  if (ALength.Kind = TSyntaxKind.Call) and SameText(ALength.Name, 'Succ') and (ALength.ChildCount = 2) then
    Exit(IsCallOf(AText, ALength[1], 'Length', ATarget));
  if (ALength.Kind <> TSyntaxKind.BinaryExpr) or (ALength.Name <> '+') or (ALength.ChildCount <> 2) then
    Exit;
  if IsCallOf(AText, ALength[0], 'Length', ATarget) then
    Result := IsPositiveLiteral(ALength[1])
  else if IsCallOf(AText, ALength[1], 'Length', ATarget) then
    Result := IsPositiveLiteral(ALength[0])
  else if IsCallOf(AText, ALength[0], 'High', ATarget) then
    Result := IsPositiveLiteral(ALength[1]) and (ALength[1].Name <> '1');
end;

/// <summary>Letztes Element von ATarget als Index: High(A) bzw. Length(A) - 1?</summary>
function IsLastIndex(const AText: string; AIndex: TSyntaxNode; const ATarget: string): Boolean;
begin
  Result := IsCallOf(AText, AIndex, 'High', ATarget) or
    ((AIndex.Kind = TSyntaxKind.BinaryExpr) and (AIndex.Name = '-') and (AIndex.ChildCount = 2) and
    IsCallOf(AText, AIndex[0], 'Length', ATarget) and (AIndex[1].Kind = TSyntaxKind.Literal) and
    (AIndex[1].Name = '1'));
end;

function IsLoop(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
end;

/// <summary>Innerste Schleife um ANode innerhalb derselben Routine; nil ohne.</summary>
function EnclosingLoop(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and not IsLoop(Result) do
  begin
    if Result.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      Exit(nil);
    Result := Result.Parent;
  end;
end;

/// <summary>Rumpf der Schleife; bei repeat nil (mehrere Anweisungen).</summary>
function LoopBody(ALoop: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ALoop.Kind <> TSyntaxKind.RepeatStatement) and (ALoop.ChildCount > 0) then
    Result := ALoop[ALoop.ChildCount - 1];
end;

/// <summary>Steht AStatement direkt im Rumpf von ALoop, wird es also bei jedem Durchlauf ausgeführt?</summary>
function RunsEveryIteration(ALoop, AStatement: TSyntaxNode): Boolean;
var
  Body: TSyntaxNode;
begin
  if ALoop.Kind = TSyntaxKind.RepeatStatement then
    Exit(AStatement.Parent = ALoop);
  Body := LoopBody(ALoop);
  Result := (Body = AStatement) or ((Body <> nil) and (Body.Kind = TSyntaxKind.Block) and (AStatement.Parent = Body));
end;

/// <summary>Ist ATypeText ein dynamisches Array? ADeclared: Namen der Array-Typen der Datei.</summary>
function IsDynamicArrayType(const ATypeText: string; const ADeclared: TArray<string>): Boolean;
var
  Text: string;
begin
  Text := Trim(ATypeText);
  Result := StartsText('array of ', Text) or StartsText('TArray<', Text) or MatchText(Text, RtlDynamicArrays) or
    MatchText(Text, ADeclared);
end;

/// <summary>Namen der Typen der Datei, die als dynamisches Array deklariert sind (T = array of X bzw. TArray&lt;X&gt;).
/// </summary>
function DynamicArrayTypes(const AText: string; ARoot: TSyntaxNode): TArray<string>;
var
  Found: TArray<string>;
begin
  Found := nil;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Child: TSyntaxNode;
      Text: string;
    begin
      Result := not (ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.ClassType, TSyntaxKind.RecordType]);
      if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.ChildCount > 0) then
      begin
        Child := ANode[ANode.ChildCount - 1];
        Text := Trim(NodeText(AText, Child));
        if ((Child.Kind = TSyntaxKind.ArrayType) and StartsText('array of ', Text)) or
          ((Child.Kind = TSyntaxKind.TypeReference) and StartsText('TArray<', Text)) then
          Found := Found + [ANode.Name];
      end;
    end);
  Result := Found;
end;

/// <summary>Ergebnistyp der Funktion um ANode als Quelltext; '' ohne.</summary>
function ResultType(const AText: string; ANode: TSyntaxNode): string;
var
  Routine, Header: TSyntaxNode;
begin
  Result := '';
  Routine := ANode.Parent;
  while (Routine <> nil) and (Routine.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    if Routine.Kind = TSyntaxKind.AnonymousMethod then
      Exit;
    Routine := Routine.Parent;
  end;
  if Routine = nil then
    Exit;
  Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
  if (Header <> nil) and (Header.ChildCount > 0) and (Header[Header.ChildCount - 1].Kind <> TSyntaxKind.Parameters) then
  begin
    Header := Header.FindChild(TSyntaxKind.TypeReference);
    if Header <> nil then
      Result := NodeText(AText, Header);
  end;
end;

/// <summary>Anzahl der Durchläufe einer for-Schleife als Quelltext; '' wenn sie nicht sicher zu bestimmen ist.
/// ALoopIndex: Ausdruck für den Index des I-ten Elements (I bzw. I - Start).</summary>
function ForCount(const AText: string; ALoop: TSyntaxNode; out ALoopIndex: string): string;
var
  First, Last: TSyntaxNode;
  LowText, HighText: string;
begin
  Result := '';
  ALoopIndex := '';
  if (ALoop.Kind <> TSyntaxKind.ForStatement) or (ALoop.ChildCount < 3) then
    Exit;
  First := ALoop[ALoop.ChildCount - 3];
  Last := ALoop[ALoop.ChildCount - 2];
  if ContainsText(Copy(AText, First.EndOffset + 1, Last.StartOffset - First.EndOffset), 'downto') then
    Exit;
  LowText := Trim(NodeText(AText, First));
  HighText := Trim(NodeText(AText, Last));
  if LowText = '0' then
  begin
    ALoopIndex := ALoop.Name;
    if (Last.Kind = TSyntaxKind.BinaryExpr) and (Last.Name = '-') and (Last.ChildCount = 2) and
      (Last[1].Kind = TSyntaxKind.Literal) and (Last[1].Name = '1') then
      Result := Trim(NodeText(AText, Last[0]))
    else
      Result := HighText + ' + 1';
  end
  else if LowText = '1' then
  begin
    Result := HighText;
    ALoopIndex := ALoop.Name + ' - 1';
  end
  else
  begin
    Result := Format('%s - %s + 1', [HighText, LowText]);
    ALoopIndex := Format('%s - %s', [ALoop.Name, LowText]);
  end;
end;

function TSetLengthInLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('setlength-in-loop', TRuleSeverity.Hint,
    'Dynamisches Array wächst in einer Schleife um je ein Element');
end;

procedure TSetLengthInLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Types: TDeclaredTypes;
  ArrayTypes: TArray<string>;
  Calls: TArray<TSyntaxNode>;
  Call, Statement, Loop: TSyntaxNode;
  Target, Count, LoopIndex, TypeText: string;
  Fixes: TArray<TRuleFix>;

  function Range(AStart, AEnd: Integer): TTextRange;
  begin
    Result := TRuleDerived.OffsetRange(Cache, AContext, AStart, AEnd);
  end;

  function LineStart(AOffset: Integer): Integer;
  begin
    Result := AOffset;
    while (Result > 0) and not CharInSet(AContext.Text[Result], [#10, #13]) do
      Dec(Result);
  end;

  function Indent(AOffset: Integer): string;
  var
    Start, Index: Integer;
  begin
    Start := LineStart(AOffset);
    Index := Start;
    while (Index < AOffset) and CharInSet(AContext.Text[Index + 1], [' ', #9]) do
      Inc(Index);
    Result := Copy(AContext.Text, Start + 1, Index - Start);
  end;

  /// <summary>Bereich der ganzen Zeile(n) von AStatement samt folgendem ; und Zeilenende; False, wenn mehr in der
  /// Zeile steht.</summary>
  function WholeLines(AStatement: TSyntaxNode; out AStart, AEnd: Integer): Boolean;
  begin
    AStart := LineStart(AStatement.StartOffset);
    Result := Trim(Copy(AContext.Text, AStart + 1, AStatement.StartOffset - AStart)) = '';
    AEnd := AStatement.EndOffset;
    while (AEnd < Length(AContext.Text)) and CharInSet(AContext.Text[AEnd + 1], [' ', #9]) do
      Inc(AEnd);
    if (AEnd < Length(AContext.Text)) and (AContext.Text[AEnd + 1] = ';') then
      Inc(AEnd);
    while (AEnd < Length(AContext.Text)) and CharInSet(AContext.Text[AEnd + 1], [' ', #9]) do
      Inc(AEnd);
    if (AEnd < Length(AContext.Text)) and (AContext.Text[AEnd + 1] = #13) then
      Inc(AEnd);
    if (AEnd < Length(AContext.Text)) and (AContext.Text[AEnd + 1] = #10) then
      Inc(AEnd)
    else
      Result := False;
  end;

  /// <summary>Lokale Variable ATarget der Routine um ALoop, die vor der Schleife nicht vorkommt?</summary>
  function FreshLocal(ALoop: TSyntaxNode): Boolean;
  var
    Routine, Section, Body: TSyntaxNode;
    Index, Inner: Integer;
    Declared, Used: Boolean;
    Name, Wanted: string;
  begin
    Wanted := Target;
    Routine := ALoop.Parent;
    while (Routine <> nil) and (Routine.Kind <> TSyntaxKind.RoutineDecl) do
    begin
      if Routine.Kind = TSyntaxKind.AnonymousMethod then
        Exit(False);
      Routine := Routine.Parent;
    end;
    if Routine = nil then
      Exit(False);
    Declared := False;
    for Index := 0 to Routine.ChildCount - 1 do
    begin
      Section := Routine[Index];
      if Section.Kind = TSyntaxKind.VarSection then
        for Inner := 0 to Section.ChildCount - 1 do
          for Name in SplitString(Section[Inner].Name, ',') do
            if SameText(Trim(Name), Target) then
              Declared := True;
    end;
    Body := Routine.FindChild(TSyntaxKind.Block);
    if not Declared or (Body = nil) then
      Exit(False);
    Used := False;
    Body.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := not Used;
        if (ANode.Kind = TSyntaxKind.Identifier) and (ANode.EndOffset <= ALoop.StartOffset) and
          SameText(ANode.Name, Wanted) then
          Used := True;
      end);
    Result := not Used;
  end;

  /// <summary>Text von AFrom bis ATo mit den Ersetzungen in AEdits (Offsets) darin.</summary>
  function Rewrite(AFrom, ATo: Integer; const AReplaced: TArray<TSyntaxNode>; const ANew: string): string;
  var
    Index: Integer;
  begin
    Result := Copy(AContext.Text, AFrom + 1, ATo - AFrom);
    for Index := High(AReplaced) downto 0 do
      if (AReplaced[Index].StartOffset >= AFrom) and (AReplaced[Index].EndOffset <= ATo) then
        Result := Copy(Result, 1, AReplaced[Index].StartOffset - AFrom) + ANew +
          Copy(Result, AReplaced[Index].EndOffset - AFrom + 1, MaxInt);
  end;

  function OnOwnLine(AOffset: Integer): Boolean;
  begin
    Result := Trim(Copy(AContext.Text, LineStart(AOffset) + 1, AOffset - LineStart(AOffset))) = '';
  end;

  /// <summary>Korrektur: Länge vor der Schleife setzen, SetLength entfernen, A[High(A)] durch A[I] ersetzen.
  /// Bleibt im begin … end nur eine Anweisung, entfällt der Block.</summary>
  function CountFix(ALoop, AStatement: TSyntaxNode): TArray<TRuleFix>;
  var
    Body, Other: TSyntaxNode;
    Edits: TArray<TRuleEdit>;
    Replaced: TArray<TSyntaxNode>;
    Safe: Boolean;
    Start, Stop, Index, Remaining: Integer;
    Wanted, Text: string;
  begin
    Result := nil;
    Wanted := Target;
    Text := AContext.Text;
    Body := LoopBody(ALoop);
    if (LoopIndex = '') or (Body = nil) or not FreshLocal(ALoop) or not WholeLines(AStatement, Start, Stop) then
      Exit;
    // Jede andere Stelle mit A im Rumpf muss A[High(A)] bzw. A[Length(A) - 1] sein; Sprünge verkürzen das Array.
    Safe := True;
    Replaced := nil;
    Body.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := Safe and (ANode <> AStatement);
        if not Result then
          Exit;
        if (ANode.Kind = TSyntaxKind.IndexAccess) and (ANode.ChildCount = 2) and
          (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, Wanted) and
          IsLastIndex(Text, ANode[1], Wanted) then
        begin
          Replaced := Replaced + [ANode[1]];
          Exit(False);
        end;
        if ((ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, Wanted)) or
          ((ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.CallStatement]) and
          MatchText(ANode.Name, ['Break', 'Continue', 'Exit'])) or (ANode.Kind = TSyntaxKind.GotoStatement) then
          Safe := False;
      end);
    if not Safe or (Replaced = nil) then
      Exit;
    Edits := [TRuleEdit.Create(Range(LineStart(ALoop.StartOffset), LineStart(ALoop.StartOffset)),
      Indent(ALoop.StartOffset) + Format('SetLength(%s, %s);', [Target, Count]) + TTextLines.LineBreakOf(AContext.Text))];
    Remaining := 0;
    Other := nil;
    if Body.Kind = TSyntaxKind.Block then
      for Index := 0 to Body.ChildCount - 1 do
        if Body[Index] <> AStatement then
        begin
          Inc(Remaining);
          Other := Body[Index];
        end;
    if (Remaining = 1) and OnOwnLine(Body.StartOffset) and OnOwnLine(Body.EndOffset - 3) and
      OnOwnLine(Other.StartOffset) and (Other.StartOffset > AStatement.StartOffset) then
      // Die Anweisung steht schon zwei Zeichen tiefer als begin, also dort, wo sie ohne Block hingehört.
      Edits := Edits + [TRuleEdit.Create(Range(LineStart(Body.StartOffset), Body.EndOffset),
        Rewrite(LineStart(Other.StartOffset), Other.EndOffset, Replaced, LoopIndex))]
    else
    begin
      Edits := Edits + [TRuleEdit.Create(Range(Start, Stop), '')];
      for Index := 0 to High(Replaced) do
        Edits := Edits + [TRuleEdit.Create(Range(Replaced[Index].StartOffset, Replaced[Index].EndOffset), LoopIndex)];
    end;
    Result := [TRuleFix.Create(Format('Länge von %s vor der Schleife setzen', [Target]), Edits)];
  end;

begin
  if AContext.Tree = nil then
    Exit;
  // Vorfilter: ohne SetLength keine Arbeit.
  if not ContainsText(AContext.Text, 'SetLength') then
    Exit;
  Calls := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount = 1) and
        (ANode[0].Kind = TSyntaxKind.Call) and SameText(ANode[0].Name, 'SetLength') and (ANode[0].ChildCount = 3) then
        Calls := Calls + [ANode];
    end);
  if Calls = nil then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  ArrayTypes := DynamicArrayTypes(AContext.Text, AContext.Tree.Root);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Statement in Calls do
    begin
      Call := Statement[0];
      if Call[1].Kind <> TSyntaxKind.Identifier then
        Continue;
      Target := Call[1].Name;
      Loop := EnclosingLoop(Statement);
      if (Loop = nil) or not IsGrowth(AContext.Text, Call[2], Target) then
        Continue;
      TypeText := Types.DeclaredType(Target, Call[1].StartPos);
      if (TypeText = '') and SameText(Target, 'Result') then
        TypeText := ResultType(AContext.Text, Statement);
      if not IsDynamicArrayType(TypeText, ArrayTypes) then
        Continue;
      Count := '';
      LoopIndex := '';
      if RunsEveryIteration(Loop, Statement) then
        Count := ForCount(AContext.Text, Loop, LoopIndex);
      if Count <> '' then
      begin
        Fixes := CountFix(Loop, Statement);
        AReport.Add(Range(Statement.StartOffset, Statement.EndOffset), Format('SetLength in der Schleife kopiert ' +
          '%s bei jedem Durchlauf; die Anzahl %s ist vorher bekannt.', [Target, Count]), Fixes);
      end
      else
        AReport.Add(Range(Statement.StartOffset, Statement.EndOffset), Format('SetLength in der Schleife kopiert ' +
          '%s bei jedem Durchlauf; die Länge vor der Schleife setzen oder die Werte in einer TList<T> sammeln.',
          [Target]));
    end;
  finally
    Types.Free;
  end;
end;

procedure RegisterPerformanceRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TStringConcatInLoopRule.Create);
  ARegistry.Register(TLoopInvariantCallRule.Create);
  ARegistry.Register(TMissingBeginUpdateRule.Create);
  ARegistry.Register(TSetLengthInLoopRule.Create);
end;

end.
