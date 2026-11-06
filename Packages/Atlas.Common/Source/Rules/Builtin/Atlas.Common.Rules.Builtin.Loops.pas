unit Atlas.Common.Rules.Builtin.Loops;

// Regeln für Zählschleifen (#909, Gruppe Compiler vorab):
//   for-variable-misuse
//                     Die Variable einer for-Schleife wird im Rumpf zugewiesen
//                     oder mit Inc/Dec verändert (#1009, wie E2081), als
//                     var- bzw. out-Parameter an eine Routine dieser Datei
//                     übergeben (wie W1015) oder ist keine einfache lokale
//                     Variable: Feld der eigenen Klasse oder lokale Variable der
//                     umgebenden Routine (wie E1019), globale Variable der
//                     Unit (wie W1019). Parameter, unbekannte Namen und Schleifen in
//                     with-Anweisungen bleiben still, ebenso anonyme Methoden
//                     im Rumpf und Routinen mit Parserfehlern.
//                     Korrekturen: auf eine while-Schleife umstellen (nicht
//                     bei Continue im Rumpf) bzw. "for var" verwenden, wenn die
//                     Routine den Namen sonst nicht benutzt.
//   for-variable-after-loop
//                     Nach einer for-Schleife ist die Variable undefiniert,
//                     wenn die Schleife ohne Break endet (#1010, wie W1037).
//                     Vom normalen Ausgang der Schleife (Bedingungsknoten im
//                     Kontrollflussgraphen, Semantics.ControlFlow) folgt die
//                     Regel den Wegen bis zu einer Zuweisung; liest ein Knoten
//                     die Variable vorher sicher, meldet sie die Stelle. Eine
//                     unsichere Änderung (var-Argument, with, anonyme Methode)
//                     beendet den Weg ohne Meldung; Wege nur über mögliche
//                     Ausnahmen zählen nicht. Nur lokale Variablen der Routine,
//                     nicht for var. Korrektur wie oben: auf while umstellen,
//                     dann hat die Variable nach der Schleife einen Wert.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ForVariableMisuseRuleId = 'for-variable-misuse';
  ForVariableAfterLoopRuleId = 'for-variable-after-loop';

type
  TForVariableMisuseRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TForVariableAfterLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterLoopRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TLoopsText = (ToWhile, LoopVarTitle, Modified, VarParam, Assigned, OuterVariable, FieldKind, GlobalVariable,
    NonLocal, ReadAfterTitle, ReadAfter, UseForVar);

const
  cTexts: array[TLoopsText] of TAtlasText = (
    (De: 'Auf while-Schleife umstellen'; En: 'Convert to while loop'),
    (De: 'Schleifenvariable verändert oder nicht lokal'; En: 'Loop variable modified or not local'),
    (De: 'Schleifenvariable %s darf im Rumpf nicht verändert werden (wie E2081).';
     En: 'Loop variable %s must not be modified in the body (like E2081).'),
    (De: 'Schleifenvariable %s wird als var-Parameter an %s übergeben (wie W1015).';
     En: 'Loop variable %s is passed as var parameter to %s (like W1015).'),
    (De: 'Schleifenvariable %s darf im Rumpf nicht zugewiesen werden (wie E2081).';
     En: 'Loop variable %s must not be assigned in the body (like E2081).'),
    (De: 'eine Variable der umgebenden Routine'; En: 'a variable of the enclosing routine'),
    (De: 'ein Feld'; En: 'a field'),
    (De: 'eine globale Variable'; En: 'a global variable'),
    (De: 'Schleifenvariable %s ist %s, keine einfache lokale Variable (wie %s).';
     En: 'Loop variable %s is %s, not a simple local variable (like %s).'),
    (De: 'Schleifenvariable nach der Schleife gelesen'; En: 'Loop variable read after the loop'),
    (De: '%s ist nach der Schleife undefiniert, wenn kein Break erreicht wurde (wie W1037).';
     En: '%s is undefined after the loop if no Break was reached (like W1037).'),
    (De: 'for var %s verwenden'; En: 'Use for var %s'));

{$SCOPEDENUMS OFF}

type
  TNameSet = TDictionary<string, Boolean>;

/// <summary>Hat der Parser im Bereich von AScope einen Fehler gemeldet?</summary>
function ParserBroken(ATree: TSyntaxTree; AScope: TSyntaxNode): Boolean;
var
  Diagnostic: TSyntaxDiagnostic;
begin
  for Diagnostic in ATree.Diagnostics do
  begin
    if (Diagnostic.StartPos.Line >= AScope.StartPos.Line) and (Diagnostic.StartPos.Line <= AScope.EndPos.Line) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Fügt die Namen "A,B" in ASet ein (klein).</summary>
procedure AddNames(ASet: TNameSet; const ANames: string);
var
  Part: string;
begin
  for Part in ANames.Split([',']) do
  begin
    if Trim(Part) <> '' then
    begin
      ASet.AddOrSetValue(LowerCase(Trim(Part)), True);
    end;
  end;
end;

/// <summary>Variablen der Abschnitte var direkt unter AOwner (Routine oder Unit-Abschnitt).</summary>
procedure AddVariables(ASet: TNameSet; AOwner: TSyntaxNode);
var
  Index, Item: Integer;
  Section: TSyntaxNode;
begin
  for Index := 0 to AOwner.ChildCount - 1 do
  begin
    Section := AOwner[Index];
    if Section.Kind = TSyntaxKind.VarSection then
    begin
      for Item := 0 to Section.ChildCount - 1 do
      begin
        if Section[Item].Kind = TSyntaxKind.VarDecl then
        begin
          AddNames(ASet, Section[Item].Name);
        end;
      end;
    end;
  end;
end;

/// <summary>Bezeichner ohne Kette (I, nicht Self.I oder X.I).</summary>
function IsPlainName(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName);
end;

function TokenAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(ATokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if ATokens[Middle].Offset < AOffset then
    begin
      Low := Middle + 1;
    end
    else
    begin
      High := Middle;
    end;
  end;
  Result := Low;
end;

function NextCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and (ATokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(Result);
  end;
end;

function PreviousCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and (ATokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(Result);
  end;
end;

function SourceOf(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

// Leerraum am Anfang der Zeile, in der die Stelle AOffset (Spalte ACharacter) liegt.
function IndentAt(const AText: string; AOffset, ACharacter: Integer): string;
var
  LineStart, Index: Integer;
begin
  LineStart := AOffset - ACharacter;
  Index := LineStart + 1;
  while (Index <= AOffset) and CharInSet(AText[Index], [' ', #9]) do
  begin
    Inc(Index);
  end;
  Result := Copy(AText, LineStart + 1, Index - LineStart - 1);
end;

// Kommt im Rumpf ein Continue dieser Schleife vor (nicht in einer inneren Schleife)?
function HasOwnContinue(ANode: TSyntaxNode): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if Node.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
        TSyntaxKind.RepeatStatement, TSyntaxKind.AnonymousMethod] then
      begin
        Continue;
      end;
      if (Node.Kind = TSyntaxKind.CallStatement) and SameText(Node.Name, 'Continue') then
      begin
        Exit(True);
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

type
  /// <summary>Teile der Umstellung einer for- auf eine while-Schleife.</summary>
  TWhileParts = record
    /// <summary>Ersatz für "for … do": Startzuweisung und "while … do".</summary>
    Head: string;
    /// <summary>Inc bzw. Dec.</summary>
    Step: string;
    LineBreak: string;
    Indent: string;
    /// <summary>Das do der for-Schleife.</summary>
    DoToken: Integer;
  end;

/// <summary>Vergleich und Schritt der Schleife: downto zwischen AStart und AStop zählt rückwärts.</summary>
procedure LoopDirection(const ATokens: TArray<TPascalToken>; AStart, AStop: TSyntaxNode; out ACompare,
  AStep: string);
var
  mIndex: Integer;
begin
  ACompare := '<=';
  AStep := 'Inc';
  for mIndex := TokenAt(ATokens, AStart.EndOffset) to TokenAt(ATokens, AStop.StartOffset) do
  begin
    if (mIndex <= High(ATokens)) and ATokens[mIndex].IsKeyword('downto') then
    begin
      ACompare := '>=';
      AStep := 'Dec';
    end;
  end;
end;

/// <summary>Startzuweisung "I := A;", mit AInline als "var I: Typ := A;".</summary>
function LoopStart(const AText: string; ALoop, AStartExpr: TSyntaxNode; AInline: Boolean): string;
var
  mTypeRef: TSyntaxNode;
begin
  mTypeRef := ALoop.FindChild(TSyntaxKind.TypeReference);
  Result := ALoop.Name + ' := ' + SourceOf(AText, AStartExpr) + ';';
  if AInline and (mTypeRef <> nil) then
  begin
    Result := 'var ' + ALoop.Name + ': ' + SourceOf(AText, mTypeRef) + ' := ' + SourceOf(AText, AStartExpr) + ';';
  end
  else if AInline then
  begin
    Result := 'var ' + Result;
  end;
end;

/// <summary>Änderungen für einen Rumpf mit begin … end: vor dem end Inc(I); fehlt das Semikolon nach der letzten
/// Anweisung, kommt es dazu. False ohne end.</summary>
function BlockLoopEdits(const AText: string; const ATokens: TArray<TPascalToken>; ALoop, ABody: TSyntaxNode;
  const AParts: TWhileParts; out AEdits: TArray<TRuleEdit>): Boolean;
var
  mEnd, mBefore: Integer;
begin
  AEdits := nil;
  mEnd := PreviousCode(ATokens, TokenAt(ATokens, ABody.EndOffset));
  Result := (mEnd >= 0) and ATokens[mEnd].IsKeyword('end');
  if not Result then
  begin
    Exit;
  end;
  AEdits := [TRuleEdit.Create(TTextRange.Create(ALoop.StartPos, ATokens[AParts.DoToken].EndPos), AParts.Head)];
  mBefore := PreviousCode(ATokens, mEnd);
  if (mBefore >= 0) and not ATokens[mBefore].IsSymbol(';') and not ATokens[mBefore].IsKeyword('begin') then
  begin
    AEdits := AEdits + [TRuleEdit.Create(TTextRange.Create(ATokens[mBefore].EndPos, ATokens[mBefore].EndPos), ';')];
  end;
  AEdits := AEdits + [TRuleEdit.Create(TTextRange.Create(ATokens[mEnd].StartPos, ATokens[mEnd].StartPos),
    '  ' + AParts.Step + '(' + ALoop.Name + ');' + AParts.LineBreak + IndentAt(AText, ATokens[mEnd].Offset,
    ATokens[mEnd].StartPos.Character))];
end;

/// <summary>Änderungen für einen Rumpf aus einer Anweisung: in begin … end mit Inc(I) einschließen.</summary>
function SingleLoopEdits(const ATokens: TArray<TPascalToken>; ALoop, ABody: TSyntaxNode;
  const AParts: TWhileParts): TArray<TRuleEdit>;
begin
  Result := [TRuleEdit.Create(TTextRange.Create(ALoop.StartPos, ATokens[AParts.DoToken].EndPos),
    AParts.Head + AParts.LineBreak + AParts.Indent + 'begin'),
    TRuleEdit.Create(TTextRange.Create(ABody.EndPos, ABody.EndPos), ';' + AParts.LineBreak + AParts.Indent + '  ' +
    AParts.Step + '(' + ALoop.Name + ');' + AParts.LineBreak + AParts.Indent + 'end')];
end;

// Korrektur: for I := A to B do S wird I := A; while I <= B do begin S; Inc(I); end.
function WhileLoopFix(const AText: string; const ATokens: TArray<TPascalToken>; ALoop: TSyntaxNode;
  AInline: Boolean): TArray<TRuleFix>;
var
  mStartExpr, mStopExpr, mBody: TSyntaxNode;
  mCompare: string;
  mParts: TWhileParts;
  mEdits: TArray<TRuleEdit>;
begin
  Result := nil;
  if (ALoop.ChildCount < 3) or HasOwnContinue(ALoop[ALoop.ChildCount - 1]) then
  begin
    Exit;
  end;
  mStartExpr := ALoop[ALoop.ChildCount - 3];
  mStopExpr := ALoop[ALoop.ChildCount - 2];
  mBody := ALoop[ALoop.ChildCount - 1];
  mParts := Default(TWhileParts);
  mParts.LineBreak := #10;
  if Pos(#13#10, AText) > 0 then
  begin
    mParts.LineBreak := #13#10;
  end;
  LoopDirection(ATokens, mStartExpr, mStopExpr, mCompare, mParts.Step);
  mParts.DoToken := PreviousCode(ATokens, TokenAt(ATokens, mBody.StartOffset));
  if (mParts.DoToken < 0) or not ATokens[mParts.DoToken].IsKeyword('do') then
  begin
    Exit;
  end;
  mParts.Indent := IndentAt(AText, ALoop.StartOffset, ALoop.StartPos.Character);
  mParts.Head := LoopStart(AText, ALoop, mStartExpr, AInline) + mParts.LineBreak + mParts.Indent + 'while ' +
    ALoop.Name + ' ' + mCompare + ' ' + SourceOf(AText, mStopExpr) + ' do';
  if mBody.Kind <> TSyntaxKind.Block then
  begin
    mEdits := SingleLoopEdits(ATokens, ALoop, mBody, mParts);
  end
  else if not BlockLoopEdits(AText, ATokens, ALoop, mBody, mParts, mEdits) then
  begin
    Exit;
  end;
  Result := [TRuleFix.Create(cTexts[TLoopsText.ToWhile].Text, mEdits)];
end;

{ TForVariableMisuseRule }

function TForVariableMisuseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ForVariableMisuseRuleId, TRuleSeverity.Error,
    cTexts[TLoopsText.LoopVarTitle].Text);
end;

procedure TForVariableMisuseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Globals, Fields: TNameSet;
  VarRoutines: TDictionary<string, TArray<TArray<Boolean>>>;


  // var- bzw. out-Modus jedes Parameters des Kopfs AHeader in Reihenfolge.
  function ParameterModes(AHeader: TSyntaxNode): TArray<Boolean>;
  var
    mParams: TSyntaxNode;
    mItem, mCount: Integer;
  begin
    Result := nil;
    mParams := AHeader.FindChild(TSyntaxKind.Parameters);
    if mParams = nil then
    begin
      Exit;
    end;
    for mItem := 0 to mParams.ChildCount - 1 do
    begin
      if mParams[mItem].Kind <> TSyntaxKind.Parameter then
      begin
        Continue;
      end;
      for mCount := 1 to Length(mParams[mItem].Name.Split([','])) do
      begin
        Result := Result + [mParams[mItem].Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam]];
      end;
    end;
  end;

  // Merkt sich die Parametermodi der Routine mit dem Kopf AHeader unter ihrem Namen ohne Klasse.
  procedure AddVarRoutine(AHeader: TSyntaxNode);
  var
    mKey: string;
    mKnown: TArray<TArray<Boolean>>;
  begin
    mKey := LowerCase(AHeader.Name);
    if Pos('.', mKey) > 0 then
    begin
      mKey := Copy(mKey, LastDelimiter('.', mKey) + 1, MaxInt);
    end;
    if not VarRoutines.TryGetValue(mKey, mKnown) then
    begin
      mKnown := nil;
    end;
    VarRoutines.AddOrSetValue(mKey, mKnown + [ParameterModes(AHeader)]);
  end;

  procedure AddFields(AField: TSyntaxNode; const AClassName: string);
  var
    mKey: string;
  begin
    for mKey in AField.Name.Split([',']) do
    begin
      Fields.AddOrSetValue(AClassName + '.' + LowerCase(Trim(mKey)), True);
    end;
  end;

  // Felder der Klassen dieser Datei (Typname klein -> Feldnamen) und Routinen mit var/out-Parametern.
  procedure CollectDeclarations(ANode: TSyntaxNode; const AClass: string);
  var
    mIndex: Integer;
    mChild: TSyntaxNode;
    mClassName: string;
    mPending: TStack<TSyntaxNode>;
    mClasses: TStack<string>;
  begin
    // Iterativ (Bericht M1): zu jedem Kind auf dem Stapel der Name der umgebenden Klasse.
    mPending := TStack<TSyntaxNode>.Create;
    mClasses := TStack<string>.Create;
    try
      for mIndex := ANode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(ANode[mIndex]);
        mClasses.Push(AClass);
      end;
      while mPending.Count > 0 do
      begin
        mChild := mPending.Pop;
        mClassName := mClasses.Pop;
        if (mChild.Kind = TSyntaxKind.Field) and (mClassName <> '') then
        begin
          AddFields(mChild, mClassName);
        end
        else if mChild.Kind = TSyntaxKind.TypeDecl then
        begin
          mClassName := LowerCase(mChild.Name);
        end
        else if mChild.Kind = TSyntaxKind.RoutineHeader then
        begin
          AddVarRoutine(mChild);
        end;
        for mIndex := mChild.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mChild[mIndex]);
          mClasses.Push(mClassName);
        end;
      end;
    finally
      mClasses.Free;
      mPending.Free;
    end;
  end;

  // Übergibt jede Deklaration von AName an der Stelle AArgument einen var- bzw. out-Parameter?
  function PassesByReference(const AName: string; AArgument: Integer): Boolean;
  var
    Known: TArray<TArray<Boolean>>;
    Modes: TArray<Boolean>;
  begin
    Result := False;
    if not VarRoutines.TryGetValue(LowerCase(AName), Known) then
    begin
      Exit;
    end;
    for Modes in Known do
    begin
      if (AArgument > High(Modes)) or not Modes[AArgument] then
      begin
        Exit(False);
      end;
    end;
    Result := True;
  end;


  // Inc/Dec und var-Übergabe der Schleifenvariablen AName als Argument des Aufrufs ACall.
  procedure CheckCallArguments(ACall, ALoop: TSyntaxNode; const AName: string; AInline: Boolean);
  var
    mIndex: Integer;
    mTarget: TSyntaxNode;
    mName: string;
  begin
    mName := ACall[0].Name;
    for mIndex := 1 to ACall.ChildCount - 1 do
    begin
      mTarget := ACall[mIndex];
      if not IsPlainName(mTarget, AName) then
      begin
        Continue;
      end;
      if (mIndex = 1) and MatchText(mName, ['Inc', 'Dec']) and not VarRoutines.ContainsKey('inc') and
        not VarRoutines.ContainsKey('dec') then
      begin
        AReport.Add(TTextRange.Create(mTarget.StartPos, mTarget.EndPos),
          cTexts[TLoopsText.Modified].Fmt([AName]),
          TRuleConfidence.High, WhileLoopFix(AContext.Text, Tokens, ALoop, AInline));
      end
      else if PassesByReference(mName, mIndex - 1) then
      begin
        AReport.Add(TTextRange.Create(mTarget.StartPos, mTarget.EndPos),
          cTexts[TLoopsText.VarParam].Fmt([AName, mName]),
          TRuleConfidence.High);
      end;
    end;
  end;

  // Anweisung "Name(Argumente);" mit einfachem Namen?
  function IsNamedCall(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount = 1) and
      (ANode[0].Kind = TSyntaxKind.Call) and (ANode[0].ChildCount > 1);
    Result := Result and (ANode[0][0].Kind = TSyntaxKind.Identifier);
  end;

  // Anonyme Methoden laufen später, with kann den Namen umdeuten, eine innere Schleife mit demselben Namen prüft
  // der eigene Durchlauf.
  function SkipsBody(ANode: TSyntaxNode; const AName: string): Boolean;
  begin
    Result := (ANode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.WithStatement]) or
      ((ANode.Kind = TSyntaxKind.ForStatement) and SameText(ANode.Name, AName));
  end;

  // Meldungen im Rumpf: Zuweisung, Inc/Dec und var-Übergabe der Schleifenvariablen AName.
  procedure CheckBody(ABody, ALoop: TSyntaxNode; const AName: string; AInline: Boolean);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ABody);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if SkipsBody(mNode, AName) then
        begin
          Continue;
        end;
        if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode.ChildCount > 0) and IsPlainName(mNode[0], AName) then
        begin
          AReport.Add(TTextRange.Create(mNode[0].StartPos, mNode[0].EndPos),
            cTexts[TLoopsText.Assigned].Fmt([AName]),
            TRuleConfidence.High, WhileLoopFix(AContext.Text, Tokens, ALoop, AInline));
        end
        else if IsNamedCall(mNode) then
        begin
          CheckCallArguments(mNode[0], ALoop, AName, AInline);
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

  // Kommt AName in ANode außerhalb von ALoop vor?
  function UsedOutside(ANode, ALoop: TSyntaxNode; const AName: string): Boolean;
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node = ALoop then
        begin
          Continue;
        end;
        if (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, AName) then
        begin
          Exit(True);
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

  // Schleifen der Routine ARoutine (Rumpf ABody); AOuterLocals: Variablen der umgebenden Routinen.
  procedure CheckRoutine(ARoutine, ABody: TSyntaxNode; AOuterLocals: TNameSet; const AClass: string);
  var
    Locals: TNameSet;
    Header, Params: TSyntaxNode;
    Index: Integer;

    procedure CollectInline(ARoot: TSyntaxNode);
    var
      Child: Integer;
      Node: TSyntaxNode;
      Pending: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1).
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
          begin
            Continue;
          end;
          if Node.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
          begin
            AddNames(Locals, Node.Name);
          end;
          for Child := Node.ChildCount - 1 downto 0 do
          begin
            Pending.Push(Node[Child]);
          end;
        end;
      finally
        Pending.Free;
      end;
    end;

    // Art der nicht lokalen Schleifenvariablen AKey ('' bei unbekannter) und der Code der Meldung. Eine globale
    // Variable übersetzt Delphi 13 mit Warnung W1019, die anderen Fälle sind Fehler E1019.
    function NonLocalKind(const AKey: string; out ACode: string): string;
    begin
      Result := '';
      ACode := 'E1019';
      if AOuterLocals.ContainsKey(AKey) then
      begin
        Result := cTexts[TLoopsText.OuterVariable].Text;
      end
      else if (AClass <> '') and Fields.ContainsKey(AClass + '.' + AKey) then
      begin
        Result := cTexts[TLoopsText.FieldKind].Text;
      end
      else if Globals.ContainsKey(AKey) then
      begin
        Result := cTexts[TLoopsText.GlobalVariable].Text;
        ACode := 'W1019';
      end;
    end;

    // Nicht lokal: lokale Variable einer umgebenden Routine, Feld der eigenen Klasse oder globale Variable.
    procedure CheckNonLocal(ALoop: TSyntaxNode; AForToken: Integer);
    var
      mKind, mCode: string;
      mFixes: TArray<TRuleFix>;
    begin
      mKind := NonLocalKind(LowerCase(ALoop.Name), mCode);
      if mKind = '' then
      begin
        Exit;
      end;
      mFixes := nil;
      if not UsedOutside(ABody, ALoop, ALoop.Name) then
      begin
        mFixes := [TRuleFix.Create(cTexts[TLoopsText.UseForVar].Fmt([ALoop.Name]),
          [TRuleEdit.Create(TTextRange.Create(Tokens[AForToken].StartPos, Tokens[AForToken].StartPos), 'var ')])];
      end;
      AReport.Add(TTextRange.Create(Tokens[AForToken].StartPos, Tokens[AForToken].EndPos),
        cTexts[TLoopsText.NonLocal].Fmt([ALoop.Name, mKind, mCode]),
        TRuleConfidence.High, mFixes);
    end;

    procedure CheckFor(ALoop: TSyntaxNode);
    var
      mForToken: Integer;
      mIsInline: Boolean;
    begin
      // Erstes Code-Token nach for: var bei for var I, sonst der Name.
      mForToken := NextCode(Tokens, TokenAt(Tokens, ALoop.StartOffset) + 1);
      mIsInline := (mForToken <= High(Tokens)) and Tokens[mForToken].IsKeyword('var');
      if not mIsInline and not Locals.ContainsKey(LowerCase(ALoop.Name)) then
      begin
        CheckNonLocal(ALoop, mForToken);
      end;
      if ALoop.ChildCount > 0 then
      begin
        CheckBody(ALoop[ALoop.ChildCount - 1], ALoop, ALoop.Name, mIsInline);
      end;
    end;

    procedure VisitLoops(ARoot: TSyntaxNode);
    var
      mChild: Integer;
      mInWith: Boolean;
      mNode: TSyntaxNode;
      mPending: TStack<TSyntaxNode>;
      mPendingInWith: TStack<Boolean>;
    begin
      // Iterativ (Bericht M1): zu jedem Knoten auf dem Stapel, ob er in einer with-Anweisung liegt.
      mPending := TStack<TSyntaxNode>.Create;
      mPendingInWith := TStack<Boolean>.Create;
      try
        mPending.Push(ARoot);
        mPendingInWith.Push(False);
        while mPending.Count > 0 do
        begin
          mNode := mPending.Pop;
          mInWith := mPendingInWith.Pop or (mNode.Kind = TSyntaxKind.WithStatement);
          if mNode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
          begin
            Continue;
          end;
          if (mNode.Kind = TSyntaxKind.ForStatement) and (mNode.Name <> '') and not mInWith then
          begin
            CheckFor(mNode);
          end;
          for mChild := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode[mChild]);
            mPendingInWith.Push(mInWith);
          end;
        end;
      finally
        mPendingInWith.Free;
        mPending.Free;
      end;
    end;

  var
    Outer: TNameSet;
    Child: TSyntaxNode;
    Pair: TPair<string, Boolean>;
  begin
    Locals := TNameSet.Create;
    Outer := TNameSet.Create;
    try
      AddVariables(Locals, ARoutine);
      Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
      if Header <> nil then
      begin
        Params := Header.FindChild(TSyntaxKind.Parameters);
        if Params <> nil then
        begin
          for Index := 0 to Params.ChildCount - 1 do
          begin
            AddNames(Locals, Params[Index].Name);
          end;
        end;
      end;
      CollectInline(ABody);
      if not ParserBroken(AContext.Tree, ARoutine) then
      begin
        VisitLoops(ABody);
      end;
      // Lokale Routinen: deren umgebende Variablen sind diese plus die äußeren. Die Rekursion bleibt (Bericht M1):
      // sie geht nur über verschachtelte Routinendeklarationen, nicht über Ausdrücke oder Anweisungsketten.
      for Pair in AOuterLocals do
      begin
        Outer.AddOrSetValue(Pair.Key, True);
      end;
      for Pair in Locals do
      begin
        Outer.AddOrSetValue(Pair.Key, True);
      end;
      for Index := 0 to ARoutine.ChildCount - 1 do
      begin
        Child := ARoutine[Index];
        if (Child.Kind = TSyntaxKind.RoutineDecl) and (Child.FindChild(TSyntaxKind.Block) <> nil) then
        begin
          CheckRoutine(Child, Child.FindChild(TSyntaxKind.Block), Outer, AClass);
        end;
      end;
    finally
      Outer.Free;
      Locals.Free;
    end;
  end;

  procedure VisitRoutines(ANode: TSyntaxNode);
  var
    Index: Integer;
    Body: TSyntaxNode;
    ClassName: string;
    NoOuter: TNameSet;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Body := ANode[Index];
      if (Body.Kind = TSyntaxKind.RoutineDecl) and (Body.FindChild(TSyntaxKind.Block) <> nil) then
      begin
        ClassName := '';
        if Pos('.', Body.Name) > 0 then
        begin
          ClassName := LowerCase(Copy(Body.Name, 1, LastDelimiter('.', Body.Name) - 1));
        end;
        NoOuter := TNameSet.Create;
        try
          CheckRoutine(Body, Body.FindChild(TSyntaxKind.Block), NoOuter, ClassName);
        finally
          NoOuter.Free;
        end;
      end
      else if Body.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
      begin
        VisitRoutines(Body);
      end;
    end;
  end;

  procedure CollectGlobals(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    AddVariables(Globals, ANode);
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[Index].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
      begin
        AddVariables(Globals, ANode[Index]);
      end;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'for') then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Globals := TNameSet.Create;
  Fields := TNameSet.Create;
  VarRoutines := TDictionary<string, TArray<TArray<Boolean>>>.Create;
  try
    CollectGlobals(AContext.Tree.Root);
    CollectDeclarations(AContext.Tree.Root, '');
    VisitRoutines(AContext.Tree.Root);
  finally
    VarRoutines.Free;
    Fields.Free;
    Globals.Free;
  end;
end;

{ TForVariableAfterLoopRule }

function TForVariableAfterLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ForVariableAfterLoopRuleId, TRuleSeverity.Warning,
    cTexts[TLoopsText.ReadAfterTitle].Text);
end;

procedure TForVariableAfterLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Graph: TControlFlowGraph;
  Tokens: TArray<TPascalToken>;
  Reported: TDictionary<TSyntaxNode, Boolean>;

  function IsInside(ANode, AOuter: TSyntaxNode): Boolean;
  begin
    while (ANode <> nil) and (ANode <> AOuter) do
    begin
      ANode := ANode.Parent;
    end;
    Result := ANode <> nil;
  end;

  // Erster Bezeichner AName im Ausdrucksteil von ASyntax (nicht in eingebetteten Anweisungen oder anonymen
  // Methoden); nil ohne.
  function FindName(ASyntax: TSyntaxNode; const AName: string): TSyntaxNode;
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := nil;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ASyntax);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Continue;
        end;
        if (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, AName) then
        begin
          Exit(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          if not (Node[Index].Kind in [TSyntaxKind.Block, TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
            TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.CaseItem, TSyntaxKind.CaseElse,
            TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
            TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement,
            TSyntaxKind.RaiseStatement, TSyntaxKind.LabeledStatement]) then
          begin
            Pending.Push(Node[Index]);
          end;
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Führt ANext in den Rumpf von ALoop? Knoten ohne Syntax (Sprungziel am Anfang von repeat) bis zur ersten
  // Anweisung verfolgen.
  function EntersBody(ANext: TFlowNode; ALoop: TSyntaxNode): Boolean;
  var
    Node, Next: TFlowNode;
    Pending: TStack<TFlowNode>;
    Seen: TDictionary<TFlowNode, Boolean>;
  begin
    Result := False;
    Pending := TStack<TFlowNode>.Create;
    Seen := TDictionary<TFlowNode, Boolean>.Create;
    try
      Pending.Push(ANext);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Seen.ContainsKey(Node) then
        begin
          Continue;
        end;
        Seen.Add(Node, True);
        if Node.Syntax <> nil then
        begin
          if IsInside(Node.Syntax, ALoop) and (Node.Syntax <> ALoop) then
          begin
            Exit(True);
          end;
          Continue;
        end;
        for Next in Node.Successors do
        begin
          Pending.Push(Next);
        end;
      end;
    finally
      Seen.Free;
      Pending.Free;
    end;
  end;

  // Erreichbarer Bedingungsknoten der Schleife ALoop; nil ohne.
  function ConditionOf(ALoop: TSyntaxNode): TFlowNode;
  var
    mNode: TFlowNode;
  begin
    Result := nil;
    for mNode in Graph.Nodes do
    begin
      if (mNode.Kind = TFlowNodeKind.Condition) and (mNode.Syntax = ALoop) then
      begin
        Result := mNode;
      end;
    end;
    if (Result <> nil) and (Graph.IsReachable(Result) <> TFlowAnswer.Yes) then
    begin
      Result := nil;
    end;
  end;

  // Normaler Ausgang: Nachfolger ANext der Bedingung ACondition außerhalb der Schleife.
  function IsLoopExit(ANext, ACondition: TFlowNode; ALoop: TSyntaxNode): Boolean;
  begin
    Result := (ANext <> ACondition) and (((ANext.Syntax = nil) and not EntersBody(ANext, ALoop)) or
      ((ANext.Syntax <> nil) and not IsInside(ANext.Syntax, ALoop)));
  end;

  procedure ReportRead(ANode: TFlowNode; ALoop: TSyntaxNode);
  var
    mTarget: TSyntaxNode;
  begin
    mTarget := FindName(ANode.Syntax, ALoop.Name);
    if (mTarget = nil) or Reported.ContainsKey(mTarget) then
    begin
      Exit;
    end;
    Reported.Add(mTarget, True);
    AReport.Add(TTextRange.Create(mTarget.StartPos, mTarget.EndPos), cTexts[TLoopsText.ReadAfter].Fmt([ALoop.Name]),
      TRuleConfidence.High,
      WhileLoopFix(AContext.Text, Tokens, ALoop, False));
  end;

  // Folgt dem Fluss ab ANode, solange die Schleifenvariable weder neu belegt noch gelesen wird; ein Lesen meldet
  // ReportRead.
  procedure FollowFlow(ANode: TFlowNode; ALoop: TSyntaxNode; APending: TStack<TFlowNode>);
  var
    mNext: TFlowNode;
  begin
    if SameText(ANode.Defines, ALoop.Name) or ANode.TouchesName(ALoop.Name) then
    begin
      Exit;
    end;
    if ANode.ReadsName(ALoop.Name) and (ANode.Syntax <> nil) then
    begin
      ReportRead(ANode, ALoop);
      Exit;
    end;
    for mNext in ANode.Successors do
    begin
      if not ANode.IsImplicitRaiseEdge(mNext) then
      begin
        APending.Push(mNext);
      end;
    end;
  end;

  procedure CheckLoop(ALoop: TSyntaxNode);
  var
    mCondition, mNode, mNext: TFlowNode;
    mPending: TStack<TFlowNode>;
    mSeen: TDictionary<TFlowNode, Boolean>;
  begin
    mCondition := ConditionOf(ALoop);
    if mCondition = nil then
    begin
      Exit;
    end;
    mPending := TStack<TFlowNode>.Create;
    mSeen := TDictionary<TFlowNode, Boolean>.Create;
    try
      for mNext in mCondition.Successors do
      begin
        if IsLoopExit(mNext, mCondition, ALoop) then
        begin
          mPending.Push(mNext);
        end;
      end;
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mSeen.ContainsKey(mNode) then
        begin
          Continue;
        end;
        mSeen.Add(mNode, True);
        FollowFlow(mNode, ALoop, mPending);
      end;
    finally
      mSeen.Free;
      mPending.Free;
    end;
  end;

  procedure VisitLoops(ARoot: TSyntaxNode; ALocals: TNameSet);
  var
    Index, ForToken: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        begin
          Continue;
        end;
        if (Node.Kind = TSyntaxKind.ForStatement) and ALocals.ContainsKey(LowerCase(Node.Name)) then
        begin
          ForToken := NextCode(Tokens, TokenAt(Tokens, Node.StartOffset) + 1);
          if (ForToken <= High(Tokens)) and not Tokens[ForToken].IsKeyword('var') then
          begin
            CheckLoop(Node);
          end;
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

var
  Routine, Block: TSyntaxNode;
  Locals: TNameSet;
begin
  if (AContext.Tree = nil) or not ContainsText(AContext.Text, 'for') then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Cache := TRuleDerived.Open(AContext);
  Reported := TDictionary<TSyntaxNode, Boolean>.Create;
  Locals := TNameSet.Create;
  try
    for Routine in TRuleDerived.Routines(Cache, AContext) do
    begin
      Block := Routine.FindChild(TSyntaxKind.Block);
      if Block = nil then
      begin
        Continue;
      end;
      Locals.Clear;
      AddVariables(Locals, Routine);
      if Locals.Count = 0 then
      begin
        Continue;
      end;
      Graph := TRuleDerived.Graph(Cache, AContext, Routine);
      if (Graph = nil) or not Graph.Complete then
      begin
        Continue;
      end;
      VisitLoops(Block, Locals);
    end;
  finally
    Locals.Free;
    Reported.Free;
  end;
end;

procedure RegisterLoopRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TForVariableMisuseRule.Create);
  ARegistry.Register(TForVariableAfterLoopRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Loops', cTexts);

end.
