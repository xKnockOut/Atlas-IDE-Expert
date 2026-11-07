unit Atlas.Common.Rules.Builtin.Events;

// Regeln für Ereignisse und Methodenzeiger:
//   event-call-without-assigned  FOnChange(Self) bzw. OnChange(Self) in einer Methode der Klasse, ohne dass
//                                Assigned(FOnChange) (oder FOnChange <> nil) den Aufruf schützt (#946): ohne
//                                Handler folgt eine Zugriffsverletzung. Ereignisse sind Felder und Properties
//                                der Klasse mit Methodenzeiger- oder Referenztyp: procedure/function … of object,
//                                reference to …, TNotifyEvent, TProc/TFunc, Typen auf …Event sowie Typen der Unit
//                                bzw. des Index mit solcher Deklaration. Schutz: der Aufruf steht im then-Zweig
//                                einer Bedingung mit Assigned (auch while), im else-Zweig von not Assigned, hinter
//                                "Assigned(F) and" oder nach "if not Assigned(F) then Exit/raise". Korrektur: in
//                                "if Assigned(F) then" einschließen, wenn der Aufruf als eigene Anweisung in
//                                einem Block steht. Still bleiben Felder, die ein Konstruktor mit einem Wert
//                                belegt (eingereichte Abhängigkeiten wie FReadText := AReadText), Properties
//                                auf solche Felder und gleichnamige lokale Variablen oder Parameter.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TEventCallWithoutAssignedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ist ATypeName ohne Blick in Unit und Index ein Ereignistyp (TNotifyEvent, TProc, …Event,
    /// procedure … of object, reference to …)?</summary>
    class function IsKnownEventType(const ATypeName: string): Boolean; static;
  end;

procedure RegisterEventRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TEventsText = (Title, WrapInAssigned, MayBeNil);

const
  cTexts: array[TEventsText] of TAtlasText = (
    (De: 'Ereignis ohne Assigned-Prüfung aufgerufen'; En: 'Event called without Assigned check'),
    (De: 'In if Assigned(%s) then einschließen'; En: 'Wrap in if Assigned(%s) then'),
    (De: '%s kann nil sein; ohne Assigned-Prüfung folgt eine Zugriffsverletzung.';
     En: '%s can be nil; without an Assigned check an access violation follows.'));

{$SCOPEDENUMS OFF}

const
  cEventCallWithoutAssignedRuleId = 'event-call-without-assigned';
  cKnownEventTypes: array[0..9] of string = ('TNotifyEvent', 'TProc', 'TFunc', 'TPredicate', 'TThreadProcedure',
    'TThreadMethod', 'TGetStrProc', 'TWndMethod', 'TMethod', 'TCallback');
  cProceduralPattern = '^\s*(reference\s+to\s+)?(procedure|function)\b';
  cStatementStarts: array[0..8] of string = (';', 'begin', 'then', 'do', 'else', 'try', 'finally', 'except',
    'repeat');

{ TEventCallWithoutAssignedRule }

function TEventCallWithoutAssignedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cEventCallWithoutAssignedRuleId, TRuleSeverity.Warning,
    cTexts[TEventsText.Title].Text);
end;

/// <summary>Name ohne Unit und ohne generische Argumente: System.SysUtils.TFunc&lt;Integer&gt; → TFunc.</summary>
function ShortTypeName(const ATypeName: string): string;
begin
  Result := Trim(ATypeName);
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

class function TEventCallWithoutAssignedRule.IsKnownEventType(const ATypeName: string): Boolean;
var
  mName: string;
begin
  if TRegEx.IsMatch(ATypeName, cProceduralPattern, [roIgnoreCase]) then
  begin
    Exit(True);
  end;
  mName := ShortTypeName(ATypeName);
  Result := (IndexText(mName, cKnownEventTypes) >= 0) or
    ((Length(mName) > 6) and StartsStr('T', mName) and EndsStr('Event', mName));
end;

procedure TEventCallWithoutAssignedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mCode: TArray<Integer>;
  mLines: TArray<string>;
  mLineBreak: string;
  mUnitTypes: TArray<TSyntaxNode>;
  mRoutines: TArray<TSyntaxNode>;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := mTokens[mCode[APosition]];
  end;

  // Erste Position in Code, deren Token bei oder hinter AOffset beginnt; Length(Code), wenn keines (#1323).
  function FirstCodeAt(AOffset: Integer): Integer;
  var
    mLow, mHigh, mMiddle: Integer;
  begin
    mLow := 0;
    mHigh := Length(mCode);
    while mLow < mHigh do
    begin
      mMiddle := (mLow + mHigh) div 2;
      if mTokens[mCode[mMiddle]].Offset < AOffset then
      begin
        mLow := mMiddle + 1;
      end
      else
      begin
        mHigh := mMiddle;
      end;
    end;
    Result := mLow;
  end;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  // Ohne Leerraum, klein und ohne "self.", für den Vergleich von Bedingungen.
  function Normalized(const AText: string): string;
  var
    mIndex: Integer;
  begin
    Result := '';
    for mIndex := 1 to Length(AText) do
    begin
      if not CharInSet(AText[mIndex], [' ', #9, #10, #13]) then
      begin
        Result := Result + AText[mIndex];
      end;
    end;
    Result := StringReplace(LowerCase(Result), 'self.', '', [rfReplaceAll]);
  end;

  procedure CollectTypes(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.TypeDecl then
        begin
          mUnitTypes := mUnitTypes + [mNode];
        end;
        if mNode.Kind = TSyntaxKind.RoutineDecl then
        begin
          mRoutines := mRoutines + [mNode];
        end;
        if mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.RoutineDecl] then
        begin
          Continue;
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

  // Ereignistyp: bekannt, als Methodenzeiger in der Unit deklariert oder im Index.
  function IsEventType(const ATypeName: string): Boolean;
  var
    mDecl: TSyntaxNode;
    mName, mText: string;
    mLocation: TSymbolLocation;
  begin
    if IsKnownEventType(ATypeName) then
    begin
      Exit(True);
    end;
    mName := ShortTypeName(ATypeName);
    for mDecl in mUnitTypes do
    begin
      if SameText(mDecl.Name, mName) then
      begin
        mText := NodeText(mDecl);
        mText := Copy(mText, Pos('=', mText) + 1, MaxInt);
        Exit(TRegEx.IsMatch(mText, cProceduralPattern, [roIgnoreCase]));
      end;
    end;
    if AContext.Index <> nil then
    begin
      for mLocation in AContext.Index.FindSymbols(mName) do
      begin
        if (mLocation.Symbol.Container = '') and (mLocation.Symbol.Kind = TIndexSymbolKind.TypeAlias) and
          (ContainsText(mLocation.Symbol.Signature, 'of object') or
          ContainsText(mLocation.Symbol.Signature, 'reference to')) then
        begin
          Exit(True);
        end;
      end;
    end;
    Result := False;
  end;

  // Weist der Rumpf ABlock dem Feld AName einen Wert ungleich nil zu? Nur die Token des Rumpfs statt aller
  // Token der Datei je Routine und Feld (#1323).
  function AssignsNonNil(ABlock: TSyntaxNode; const AName: string): Boolean;
  var
    mPosition: Integer;
  begin
    Result := False;
    mPosition := FirstCodeAt(ABlock.StartOffset);
    while not Result and (mPosition <= High(mCode) - 2) and (mTokens[mCode[mPosition]].Offset < ABlock.EndOffset) do
    begin
      Result := (mTokens[mCode[mPosition]].Kind = TPascalTokenKind.Identifier) and
        SameText(mTokens[mCode[mPosition]].Text, AName) and mTokens[mCode[mPosition + 1]].IsSymbol(':=') and
        not mTokens[mCode[mPosition + 2]].IsKeyword('nil');
      Inc(mPosition);
    end;
  end;

  // Rumpf der Routine ANode, wenn sie ein Konstruktor (bzw. mit AAnyMethod irgendeine Methode) von AClassName
  // ist; sonst nil.
  function InjectingBody(ANode: TSyntaxNode; const AClassName: string; AAnyMethod: Boolean): TSyntaxNode;
  begin
    Result := ANode.FindChild(TSyntaxKind.Block);
    if (Result <> nil) and (not StartsText(AClassName + '.', ANode.Name) or
      (not AAnyMethod and not StartsText('constructor', TrimLeft(NodeText(ANode))))) then
    begin
      Result := nil;
    end;
  end;

  // Weist ein Konstruktor (bzw. mit AAnyMethod irgendeine Methode) von AClassName dem Feld AName einen Wert
  // ungleich nil zu? Dann ist es eine eingereichte Abhängigkeit (FReadText := AReadText) und kein Ereignis,
  // das ein Nutzer setzt.
  function Injected(ARoot: TSyntaxNode; const AClassName, AName: string; AAnyMethod: Boolean): Boolean;
  var
    mIndex: Integer;
    mNode, mBlock: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while not Result and (mPending.Count > 0) do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.RoutineDecl then
        begin
          mBlock := InjectingBody(mNode, AClassName, AAnyMethod);
          Result := (mBlock <> nil) and AssignsNonNil(mBlock, AName);
          Continue;
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

  // Felder, die eine Property von AClass schreibt: Ereignisse, die der Nutzer der Klasse setzt.
  function WrittenFields(AClass: TSyntaxNode): TArray<string>;
  var
    mIndex: Integer;
    mField: TMatch;
  begin
    Result := nil;
    for mIndex := 0 to AClass.ChildCount - 1 do
    begin
      if AClass[mIndex].Kind = TSyntaxKind.PropertyDecl then
      begin
        mField := TRegEx.Match(NodeText(AClass[mIndex]), '\bwrite\s+(\w+)', [roIgnoreCase]);
        if mField.Success then
        begin
          Result := Result + [mField.Groups[1].Value];
        end;
      end;
    end;
  end;

  // Typknoten des Felds oder der Property AMember, wenn er ein Ereignistyp ist; sonst nil.
  function EventTypeOf(AMember: TSyntaxNode): TSyntaxNode;
  begin
    Result := nil;
    if AMember.Kind in [TSyntaxKind.Field, TSyntaxKind.PropertyDecl] then
    begin
      Result := AMember.FindChild(TSyntaxKind.ProcedureType);
      if Result = nil then
      begin
        Result := AMember.FindChild(TSyntaxKind.TypeReference);
      end;
      if (Result <> nil) and (Result.Kind = TSyntaxKind.TypeReference) and not IsEventType(NodeText(Result)) then
      begin
        Result := nil;
      end;
    end;
  end;

  // Felder und Properties der Klasse mit Ereignistyp; ohne Felder, die der Konstruktor belegt (ohne
  // schreibbare Property: irgendeine Methode der Klasse), und ohne Properties, die solche Felder lesen.
  function EventsOf(const AClassName: string; AClass: TSyntaxNode): TArray<string>;
  var
    mIndex: Integer;
    mMember: TSyntaxNode;
    mName: string;
    mWritten: TArray<string>;

    function IsInjected(const AField: string): Boolean;
    begin
      Result := Injected(AContext.Tree.Root, AClassName, AField, IndexText(AField, mWritten) < 0);
    end;

    // Liest die Property AMember ein eingereichtes Feld?
    function ReadsInjected(AMember: TSyntaxNode): Boolean;
    var
      mRead: TMatch;
    begin
      mRead := TRegEx.Match(NodeText(AMember), '\bread\s+(\w+)', [roIgnoreCase]);
      Result := mRead.Success and IsInjected(mRead.Groups[1].Value);
    end;

  begin
    Result := nil;
    mWritten := WrittenFields(AClass);
    for mIndex := 0 to AClass.ChildCount - 1 do
    begin
      mMember := AClass[mIndex];
      if (EventTypeOf(mMember) = nil) or ((mMember.Kind = TSyntaxKind.PropertyDecl) and ReadsInjected(mMember)) then
      begin
        Continue;
      end;
      for mName in mMember.Name.Split([',']) do
      begin
        if (Trim(mName) <> '') and ((mMember.Kind = TSyntaxKind.PropertyDecl) or not IsInjected(Trim(mName))) then
        begin
          Result := Result + [Trim(mName)];
        end;
      end;
    end;
  end;

  // Deklariert der Knoten ANode (Variable, Konstante, Parameter) den Namen AName?
  function DeclaresName(ANode: TSyntaxNode; const AName: string): Boolean;
  var
    mName: string;
  begin
    Result := False;
    if ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
    begin
      for mName in ANode.Name.Split([',']) do
      begin
        Result := Result or SameText(Trim(mName), AName);
      end;
    end;
  end;

  // Deklariert ARoutine (auch in anonymen Methoden) eine Variable, Konstante oder einen Parameter AName?
  function Shadowed(ARoot: TSyntaxNode; const AName: string): Boolean;
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while not Result and (mPending.Count > 0) do
      begin
        mNode := mPending.Pop;
        Result := DeclaresName(mNode, AName);
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  // Innerster Knoten unter ANode, der AOffset enthält.
  function NodeAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    mIndex: Integer;
    mFound: Boolean;
  begin
    // Iterativ (Bericht M1).
    Result := ANode;
    repeat
      mFound := False;
      for mIndex := 0 to Result.ChildCount - 1 do
      begin
        if (AOffset >= Result[mIndex].StartOffset) and (AOffset < Result[mIndex].EndOffset) then
        begin
          Result := Result[mIndex];
          mFound := True;
          Break;
        end;
      end;
    until not mFound;
  end;

  function Positive(const ACondition, AName: string): Boolean;
  var
    mStart: Integer;
  begin
    Result := ContainsStr(ACondition, AName + '<>nil') or ContainsStr(ACondition, 'nil<>' + AName);
    mStart := Pos('assigned(' + AName + ')', ACondition);
    while not Result and (mStart > 0) do
    begin
      Result := (mStart < 4) or (Copy(ACondition, mStart - 3, 3) <> 'not');
      mStart := PosEx('assigned(' + AName + ')', ACondition, mStart + 1);
    end;
  end;

  function Negative(const ACondition, AName: string): Boolean;
  begin
    Result := ContainsStr(ACondition, 'notassigned(' + AName + ')') or ContainsStr(ACondition, AName + '=nil') or
      ContainsStr(ACondition, 'nil=' + AName);
  end;

  // Endet ABranch (Zweig einer Bedingung) mit Exit oder raise?
  function Leaves(ABranch: TSyntaxNode): Boolean;
  begin
    Result := (ABranch.Kind = TSyntaxKind.RaiseStatement) or
      TRegEx.IsMatch(NodeText(ABranch), '\b(exit|raise)\b', [roIgnoreCase]);
  end;

  // "Ok := … and Assigned(F);" vor AOffset: Ok steht für die Prüfung.
  function AssignedFlag(ARoutine: TSyntaxNode; AOffset: Integer; const AFlag, AName: string): Boolean;
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mValue: string;
  begin
    Result := False;
    for mIndex := 0 to High(mCode) - 1 do
    begin
      if (Token(mIndex).Offset > ARoutine.StartOffset) and (Token(mIndex).Offset < AOffset) and
        SameText(Token(mIndex).Text, AFlag) and Token(mIndex + 1).IsSymbol(':=') then
      begin
        mNode := NodeAt(ARoutine, Token(mIndex).Offset);
        while (mNode <> nil) and (mNode.Kind <> TSyntaxKind.AssignStatement) and (mNode <> ARoutine) do
        begin
          mNode := mNode.Parent;
        end;
        if (mNode = nil) or (mNode.Kind <> TSyntaxKind.AssignStatement) then
        begin
          Continue;
        end;
        mValue := Copy(AContext.Text, Token(mIndex + 1).Offset + 3, mNode.EndOffset - Token(mIndex + 1).Offset - 2);
        Result := Positive(Normalized(mValue), AName) and not TRegEx.IsMatch(mValue, '\bor\b', [roIgnoreCase]);
      end;
    end;
  end;

  // Steht AFlag für Assigned(F): ein vorher belegter Merker oder eine Methode der Klasse ohne Parameter mit
  // "Result := … and Assigned(F)" (CanEnterCredentials)?
  function FlagFor(ARoutine: TSyntaxNode; AOffset: Integer; const AFlag, AName: string): Boolean;
  var
    mClassName: string;
    mCallee: TSyntaxNode;
  begin
    if not TRegEx.IsMatch(AFlag, '^\w+$') then
    begin
      Exit(False);
    end;
    if AssignedFlag(ARoutine, AOffset, AFlag, AName) then
    begin
      Exit(True);
    end;
    Result := False;
    mClassName := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
    if mClassName = '' then
    begin
      Exit;
    end;
    for mCallee in mRoutines do
    begin
      if SameText(mCallee.Name, mClassName + '.' + AFlag) and
        (Pos('(', Copy(NodeText(mCallee), 1, Pos(';', NodeText(mCallee)))) = 0) then
      begin
        Exit(AssignedFlag(mCallee, mCallee.EndOffset, 'Result', AName));
      end;
    end;
  end;

  // Steht ATerm in APrefix als eigenes Glied einer and-Kette ("(a)and", "xand(a)and")?
  function Conjunct(const APrefix, ATerm: string): Boolean;
  var
    mStart, mAfter: Integer;
  begin
    Result := False;
    mStart := Pos(ATerm, APrefix);
    while not Result and (mStart > 0) do
    begin
      mAfter := mStart + Length(ATerm);
      Result := ((mStart = 1) or (APrefix[mStart - 1] = '(') or ((mStart > 3) and (Copy(APrefix, mStart - 3, 3) = 'and')))
        and ((Copy(APrefix, mAfter, 3) = 'and') or (Copy(APrefix, mAfter, 1) = ')'));
      mStart := PosEx(ATerm, APrefix, mStart + 1);
    end;
  end;

  // "if … not Assigned(F) then Grund := 'aus';" vor dem Aufruf und "(Grund = '') and F(…)" bzw.
  // "not Fehler and F(…)": Der Merker ist nur leer bzw. False, wenn F zugewiesen ist (#1109).
  function MarkedUnassigned(ABranch: TSyntaxNode; const APrefix: string): Boolean;
  var
    mFlag, mValue: string;
  begin
    Result := False;
    if (ABranch.Kind <> TSyntaxKind.AssignStatement) or (ABranch.ChildCount <> 2) or
      (ABranch[0].Kind <> TSyntaxKind.Identifier) then
    begin
      Exit;
    end;
    mFlag := LowerCase(ABranch[0].Name);
    mValue := Normalized(NodeText(ABranch[1]));
    if (mValue = '''''') or (mValue = 'false') or (mValue = 'nil') then
    begin
      Exit;
    end;
    Result := Conjunct(APrefix, mFlag + '=''''') or ((mValue = 'true') and Conjunct(APrefix, 'not' + mFlag));
  end;

  // Anweisung oder Bedingung um ANode, in der ein Kurzschluss den Aufruf schützen kann; nil auf Ebene der Routine.
  function StatementOf(ARoutine, ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode;
    while (Result <> nil) and (Result <> ARoutine) and not (Result.Kind in [TSyntaxKind.AssignStatement,
      TSyntaxKind.CallStatement, TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement,
      TSyntaxKind.CaseStatement, TSyntaxKind.Block]) do
    begin
      Result := Result.Parent;
    end;
    if Result = ARoutine then
    begin
      Result := nil;
    end;
  end;

  // Text von AStatement bis AOffset, normalisiert und ab der Bedingung: "if (Grund = '') and not F(…)".
  function GuardPrefix(AStatement: TSyntaxNode; AOffset: Integer): string;
  begin
    Result := Normalized(Copy(AContext.Text, AStatement.StartOffset + 1, AOffset - AStatement.StartOffset));
    if AStatement.Kind = TSyntaxKind.IfStatement then
    begin
      Result := Copy(Result, 3, MaxInt);
    end
    else if AStatement.Kind = TSyntaxKind.WhileStatement then
    begin
      Result := Copy(Result, 6, MaxInt);
    end;
  end;

  // Kurzschluss im selben Ausdruck: "Assigned(F) and F(Self)", "not Assigned(F) or not F(Self)".
  function ShortCircuit(const APrefix, AName: string): Boolean;
  begin
    Result := Positive(APrefix, AName) and ContainsStr(APrefix, 'assigned(' + AName + ')and');
    Result := Result or ContainsStr(APrefix, AName + '<>niland');
    Result := Result or (Negative(APrefix, AName) and (ContainsStr(APrefix, 'notassigned(' + AName + ')or') or
      ContainsStr(APrefix, AName + '=nilor')));
  end;

  // Schützt die if-Anweisung AIf den Zweig ANode? Im then-Zweig ergänzt sie APrefix um ihre Bedingung (für
  // MarkedUnassigned: "if Grund = '' then F(Self)" wirkt wie "(Grund = '') and F(…)").
  function IfGuards(ARoutine, AIf, ANode: TSyntaxNode; const AName: string; var APrefix: string): Boolean;
  var
    mCondition: string;
  begin
    mCondition := Normalized(NodeText(AIf[0]));
    if ANode = AIf[1] then
    begin
      Result := Positive(mCondition, AName) or FlagFor(ARoutine, AIf.StartOffset, mCondition, AName);
      APrefix := APrefix + '(' + mCondition + ')and';
    end
    else
    begin
      Result := (AIf.ChildCount > 2) and (ANode = AIf[2]) and Negative(mCondition, AName);
    end;
  end;

  // Schützt eine umgebende if- oder while-Bedingung ("while Assigned(F) do F(Self);") den Knoten ANode?
  function EnclosingGuard(ARoutine, ANode: TSyntaxNode; const AName: string; var APrefix: string): Boolean;
  var
    mNode, mParent: TSyntaxNode;
  begin
    Result := False;
    mNode := ANode;
    while not Result and (mNode <> nil) and (mNode <> ARoutine) do
    begin
      mParent := mNode.Parent;
      if (mParent <> nil) and (mParent.ChildCount > 1) and (mParent.Kind = TSyntaxKind.IfStatement) then
      begin
        Result := IfGuards(ARoutine, mParent, mNode, AName, APrefix);
      end
      else if (mParent <> nil) and (mParent.ChildCount > 1) and (mParent.Kind = TSyntaxKind.WhileStatement) then
      begin
        Result := (mNode = mParent[1]) and Positive(Normalized(NodeText(mParent[0])), AName);
      end;
      mNode := mParent;
    end;
  end;

  // Die if-Anweisung, die mit dem Token AIndex beginnt und ganz vor AOffset in ARoutine liegt; sonst nil.
  function IfBefore(ARoutine: TSyntaxNode; AIndex, AOffset: Integer): TSyntaxNode;
  begin
    Result := nil;
    if (Token(AIndex).Offset <= ARoutine.StartOffset) or (Token(AIndex).Offset >= AOffset) or
      not Token(AIndex).IsKeyword('if') then
    begin
      Exit;
    end;
    Result := NodeAt(ARoutine, Token(AIndex).Offset);
    while (Result <> nil) and (Result.Kind <> TSyntaxKind.IfStatement) and (Result <> ARoutine) do
    begin
      Result := Result.Parent;
    end;
    if (Result = nil) or (Result.Kind <> TSyntaxKind.IfStatement) or (Result.ChildCount < 2) or
      (Result.EndOffset > AOffset) then
    begin
      Result := nil;
    end;
  end;

  // "if not CanAssign or (Name = '') then Exit;": Steht ein Glied der or-Kette von AIf für "not Assigned(F)"
  // (#1371)?
  function OrTermFlag(ARoutine, AIf: TSyntaxNode; const AName: string): Boolean;
  var
    mTerm, mCondition: string;
  begin
    Result := False;
    for mTerm in TRegEx.Split(NodeText(AIf[0]), '\bor\b', [roIgnoreCase]) do
    begin
      mCondition := Normalized(mTerm);
      while StartsStr('(', mCondition) and EndsStr(')', mCondition) do
      begin
        mCondition := Copy(mCondition, 2, Length(mCondition) - 2);
      end;
      Result := Result or (StartsStr('not', mCondition) and FlagFor(ARoutine, AIf.StartOffset,
        Copy(mCondition, 4, MaxInt), AName));
    end;
  end;

  // Verhindert die vorangehende if-Anweisung AIf den Aufruf: "if not Assigned(F) then Exit;" bzw.
  // "if not Ok then Exit;" mit "Ok := … and Assigned(F)", oder ein Merker nach MarkedUnassigned?
  function ExitGuard(ARoutine, AIf: TSyntaxNode; const AName, APrefix: string): Boolean;
  var
    mCondition: string;
  begin
    mCondition := Normalized(NodeText(AIf[0]));
    Result := Negative(mCondition, AName) and MarkedUnassigned(AIf[1], APrefix);
    if not Result and Leaves(AIf[1]) then
    begin
      Result := Negative(mCondition, AName) or (StartsStr('not', mCondition) and FlagFor(ARoutine, AIf.StartOffset,
        Copy(mCondition, 4, MaxInt), AName)) or OrTermFlag(ARoutine, AIf, AName);
    end;
  end;

  // Schützt eine if-Anweisung vor dem Aufruf bei AOffset ihn, indem sie die Routine verlässt?
  function EarlierExit(ARoutine: TSyntaxNode; AOffset: Integer; const AName, APrefix: string): Boolean;
  var
    mIndex: Integer;
    mIf: TSyntaxNode;
  begin
    Result := False;
    mIndex := 0;
    while not Result and (mIndex <= High(mCode)) do
    begin
      mIf := IfBefore(ARoutine, mIndex, AOffset);
      Result := (mIf <> nil) and ExitGuard(ARoutine, mIf, AName, APrefix);
      Inc(mIndex);
    end;
  end;

  // Schützt eine Bedingung den Aufruf bei AOffset in ARoutine?
  function Guarded(ARoutine: TSyntaxNode; AOffset: Integer; const AName: string): Boolean;
  var
    mNode, mStatement: TSyntaxNode;
    mPrefix: string;
  begin
    mPrefix := '';
    mNode := NodeAt(ARoutine, AOffset);
    mStatement := StatementOf(ARoutine, mNode);
    if mStatement <> nil then
    begin
      mPrefix := GuardPrefix(mStatement, AOffset);
    end;
    Result := ShortCircuit(mPrefix, AName) or EnclosingGuard(ARoutine, mNode, AName, mPrefix);
    // EnclosingGuard hat mPrefix um die Bedingungen der then-Zweige ergänzt.
    Result := Result or EarlierExit(ARoutine, AOffset, AName, mPrefix);
  end;

  // "if Assigned(F) then" vor die Anweisung; nur in Blöcken und wenn die Anweisung allein am Zeilenanfang steht.
  function WrapFix(ARoutine: TSyntaxNode; AFirst: Integer; const AName: string; out AFix: TRuleFix): Boolean;
  var
    mStatement: TSyntaxNode;
    mLine: Integer;
    mIndent: string;
  begin
    Result := False;
    mStatement := NodeAt(ARoutine, Token(AFirst).Offset);
    while (mStatement <> nil) and (mStatement.Kind <> TSyntaxKind.CallStatement) and (mStatement <> ARoutine) do
    begin
      mStatement := mStatement.Parent;
    end;
    if (mStatement = nil) or (mStatement.Kind <> TSyntaxKind.CallStatement) or (mStatement.Parent = nil) or
      not (mStatement.Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock,
      TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement]) or (mStatement.StartOffset <> Token(AFirst).Offset) then
    begin
      Exit;
    end;
    mLine := mStatement.StartPos.Line;
    if (mLine > High(mLines)) or (Trim(Copy(mLines[mLine], 1, mStatement.StartPos.Character)) <> '') then
    begin
      Exit;
    end;
    mIndent := Copy(mLines[mLine], 1, mStatement.StartPos.Character);
    AFix := TRuleFix.Create(cTexts[TEventsText.WrapInAssigned].Fmt([AName]),
      [TTextEdit.Create(TTextRange.Create(mStatement.StartPos, mStatement.StartPos), 'if Assigned(' + AName +
      ') then' + mLineBreak + mIndent + '  ')]);
    Result := True;
  end;

  // Steht bei APosition im Rumpf ABlock der Name eines Ereignisses aus AEvents?
  function IsEventToken(ABlock: TSyntaxNode; APosition: Integer; const AEvents: TArray<string>): Boolean;
  begin
    Result := (Token(APosition).Offset >= ABlock.StartOffset) and (Token(APosition).Offset < ABlock.EndOffset) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier) and (IndexText(Token(APosition).Text, AEvents) >= 0);
  end;

  // Erstes Token des Zugriffs auf das Ereignis bei APosition ("Self.FOnX" ab Self); False bei einem anderen
  // Objekt davor.
  function AccessStart(APosition: Integer; out AFirst: Integer): Boolean;
  begin
    AFirst := APosition;
    Result := (APosition = 0) or not Token(APosition - 1).IsSymbol('.');
    if not Result and (APosition >= 2) and SameText(Token(APosition - 2).Text, 'Self') then
    begin
      AFirst := APosition - 2;
      Result := True;
    end;
  end;

  // Wird das Ereignis bei APosition aufgerufen? Ohne Argumente nur als eigene Anweisung: "FOnIdle;".
  function IsCalled(AFirst, APosition: Integer): Boolean;
  begin
    Result := Token(APosition + 1).IsSymbol('(');
    if not Result and ((AFirst = 0) or MatchText(Token(AFirst - 1).Text, cStatementStarts)) then
    begin
      Result := Token(APosition + 1).IsSymbol(';') or Token(APosition + 1).IsKeyword('end') or
        Token(APosition + 1).IsKeyword('else');
    end;
  end;

  // Ist der Aufruf bei APosition geschützt oder meint er eine gleichnamige lokale Variable?
  function SafeCall(ARoutine: TSyntaxNode; AFirst, APosition: Integer): Boolean;
  var
    mName: string;
  begin
    mName := LowerCase(Token(APosition).Text);
    Result := ((AFirst = APosition) and Shadowed(ARoutine, mName)) or Guarded(ARoutine, Token(APosition).Offset,
      mName);
  end;

  procedure ReportCall(ARoutine: TSyntaxNode; AFirst, APosition: Integer);
  var
    mWritten: string;
    mFix: TRuleFix;
    mFixes: TArray<TRuleFix>;
  begin
    mWritten := Token(APosition).Text;
    mFixes := nil;
    if WrapFix(ARoutine, AFirst, mWritten, mFix) then
    begin
      mFixes := [mFix];
    end;
    AReport.Add(TTextRange.Create(Token(APosition).StartPos, Token(APosition).EndPos),
      cTexts[TEventsText.MayBeNil].Fmt([mWritten]), mFixes);
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode; const AEvents: TArray<string>);
  var
    mBlock: TSyntaxNode;
    mPosition, mFirst: Integer;
  begin
    mBlock := ARoutine.FindChild(TSyntaxKind.Block);
    if mBlock = nil then
    begin
      Exit;
    end;
    for mPosition := 0 to High(mCode) - 1 do
    begin
      if IsEventToken(mBlock, mPosition, AEvents) and AccessStart(mPosition, mFirst) and
        IsCalled(mFirst, mPosition) and not SafeCall(ARoutine, mFirst, mPosition) then
      begin
        ReportCall(ARoutine, mFirst, mPosition);
      end;
    end;
  end;

  procedure CheckRoutines(ARoot: TSyntaxNode; const AClassName: string; const AEvents: TArray<string>);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.RoutineDecl then
        begin
          if StartsText(AClassName + '.', mNode.Name) then
          begin
            CheckRoutine(mNode, AEvents);
          end;
          Continue;
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

var
  Index: Integer;
  Decl, mClassNode: TSyntaxNode;
  mEvents: TArray<string>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mCode := nil;
  for Index := 0 to High(mTokens) do
  begin
    if not (mTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      mCode := mCode + [Index];
    end;
  end;
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
  mUnitTypes := nil;
  mRoutines := nil;
  CollectTypes(AContext.Tree.Root);
  for Decl in mUnitTypes do
  begin
    mClassNode := Decl.FindChild(TSyntaxKind.ClassType);
    if mClassNode = nil then
    begin
      mClassNode := Decl.FindChild(TSyntaxKind.RecordType);
    end;
    if mClassNode = nil then
    begin
      Continue;
    end;
    mEvents := EventsOf(Decl.Name, mClassNode);
    if mEvents <> nil then
    begin
      CheckRoutines(AContext.Tree.Root, Decl.Name, mEvents);
    end;
  end;
end;

procedure RegisterEventRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TEventCallWithoutAssignedRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Events', cTexts);

end.
