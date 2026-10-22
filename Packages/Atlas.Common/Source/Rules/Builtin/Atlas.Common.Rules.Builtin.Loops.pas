unit Atlas.Common.Rules.Builtin.Loops;

// Regeln für Zählschleifen (#909, Gruppe Compiler vorab):
//   for-variable-misuse
//                     Die Variable einer for-Schleife wird im Rumpf zugewiesen
//                     oder mit Inc/Dec verändert (#1009, wie E2081), als
//                     var- bzw. out-Parameter an eine Routine dieser Datei
//                     übergeben (wie W1015) oder ist keine einfache lokale
//                     Variable: Feld der eigenen Klasse, globale Variable der
//                     Unit oder lokale Variable der umgebenden Routine (wie
//                     E1019). Parameter, unbekannte Namen und Schleifen in
//                     with-Anweisungen bleiben still, ebenso anonyme Methoden
//                     im Rumpf und Routinen mit Parserfehlern.
//                     Korrekturen: auf eine while-Schleife umstellen (nicht
//                     bei Continue im Rumpf) bzw. "for var" verwenden, wenn die
//                     Routine den Namen sonst nicht benutzt.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ForVariableMisuseRuleId = 'for-variable-misuse';

type
  TForVariableMisuseRule = class(TInterfacedObject, IRule)
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
  Atlas.Common.Pascal.Contract;

type
  TNameSet = TDictionary<string, Boolean>;

/// <summary>Hat der Parser im Bereich von AScope einen Fehler gemeldet?</summary>
function ParserBroken(ATree: TSyntaxTree; AScope: TSyntaxNode): Boolean;
var
  Diagnostic: TSyntaxDiagnostic;
begin
  for Diagnostic in ATree.Diagnostics do
    if (Diagnostic.StartPos.Line >= AScope.StartPos.Line) and (Diagnostic.StartPos.Line <= AScope.EndPos.Line) then
      Exit(True);
  Result := False;
end;

/// <summary>Fügt die Namen "A,B" in ASet ein (klein).</summary>
procedure AddNames(ASet: TNameSet; const ANames: string);
var
  Part: string;
begin
  for Part in ANames.Split([',']) do
    if Trim(Part) <> '' then
      ASet.AddOrSetValue(LowerCase(Trim(Part)), True);
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
      for Item := 0 to Section.ChildCount - 1 do
        if Section[Item].Kind = TSyntaxKind.VarDecl then
          AddNames(ASet, Section[Item].Name);
  end;
end;

/// <summary>Bezeichner ohne Kette (I, nicht Self.I oder X.I).</summary>
function IsPlainName(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName);
end;

{ TForVariableMisuseRule }

function TForVariableMisuseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ForVariableMisuseRuleId, TRuleSeverity.Error,
    'Schleifenvariable verändert oder nicht lokal');
end;

procedure TForVariableMisuseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Globals, Fields: TNameSet;
  VarRoutines: TDictionary<string, TArray<TArray<Boolean>>>;
  LineBreak: string;

  function TokenAt(AOffset: Integer): Integer;
  var
    Low, High, Middle: Integer;
  begin
    Low := 0;
    High := Length(Tokens);
    while Low < High do
    begin
      Middle := (Low + High) div 2;
      if Tokens[Middle].Offset < AOffset then
        Low := Middle + 1
      else
        High := Middle;
    end;
    Result := Low;
  end;

  function NextCode(AIndex: Integer): Integer;
  begin
    Result := AIndex;
    while (Result <= High(Tokens)) and (Tokens[Result].Kind in [TPascalTokenKind.Comment,
      TPascalTokenKind.Directive]) do
      Inc(Result);
  end;

  function PreviousCode(AIndex: Integer): Integer;
  begin
    Result := AIndex - 1;
    while (Result >= 0) and (Tokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
      Dec(Result);
  end;

  function SourceOf(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  // Leerraum am Anfang der Zeile, in der die Stelle AOffset (Spalte ACharacter) liegt.
  function IndentAt(AOffset, ACharacter: Integer): string;
  var
    LineStart, Index: Integer;
  begin
    LineStart := AOffset - ACharacter;
    Index := LineStart + 1;
    while (Index <= AOffset) and CharInSet(AContext.Text[Index], [' ', #9]) do
      Inc(Index);
    Result := Copy(AContext.Text, LineStart + 1, Index - LineStart - 1);
  end;

  // Felder der Klassen dieser Datei (Typname klein -> Feldnamen) und Routinen mit var/out-Parametern.
  procedure CollectDeclarations(ANode: TSyntaxNode; const AClass: string);
  var
    Index, Item, Count: Integer;
    Child, Params: TSyntaxNode;
    Modes: TArray<Boolean>;
    Key: string;
    Known: TArray<TArray<Boolean>>;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Child := ANode[Index];
      if (Child.Kind = TSyntaxKind.Field) and (AClass <> '') then
      begin
        for Key in Child.Name.Split([',']) do
          Fields.AddOrSetValue(AClass + '.' + LowerCase(Trim(Key)), True);
      end
      else if Child.Kind = TSyntaxKind.TypeDecl then
      begin
        CollectDeclarations(Child, LowerCase(Child.Name));
        Continue;
      end
      else if Child.Kind = TSyntaxKind.RoutineHeader then
      begin
        Params := Child.FindChild(TSyntaxKind.Parameters);
        Modes := nil;
        if Params <> nil then
          for Item := 0 to Params.ChildCount - 1 do
            if Params[Item].Kind = TSyntaxKind.Parameter then
              for Count := 1 to Length(Params[Item].Name.Split([','])) do
                Modes := Modes + [Params[Item].Modifier in [TParameterModifier.VarParam,
                  TParameterModifier.OutParam]];
        Key := LowerCase(Child.Name);
        if Pos('.', Key) > 0 then
          Key := Copy(Key, LastDelimiter('.', Key) + 1, MaxInt);
        if not VarRoutines.TryGetValue(Key, Known) then
          Known := nil;
        VarRoutines.AddOrSetValue(Key, Known + [Modes]);
      end;
      CollectDeclarations(Child, AClass);
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
      Exit;
    for Modes in Known do
      if (AArgument > High(Modes)) or not Modes[AArgument] then
        Exit(False);
    Result := True;
  end;

  // Kommt im Rumpf ein Continue dieser Schleife vor (nicht in einer inneren Schleife)?
  function HasOwnContinue(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    if ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
      TSyntaxKind.RepeatStatement, TSyntaxKind.AnonymousMethod] then
      Exit(False);
    if (ANode.Kind = TSyntaxKind.CallStatement) and SameText(ANode.Name, 'Continue') then
      Exit(True);
    for Index := 0 to ANode.ChildCount - 1 do
      if HasOwnContinue(ANode[Index]) then
        Exit(True);
    Result := False;
  end;

  // Korrektur: for I := A to B do S wird I := A; while I <= B do begin S; Inc(I); end.
  function WhileFix(ALoop: TSyntaxNode; AInline: Boolean): TArray<TRuleFix>;
  var
    StartExpr, StopExpr, Body, TypeRef: TSyntaxNode;
    DoToken, EndToken, Before, Index: Integer;
    Indent, Head, Step, Compare: string;
    Edits: TArray<TRuleEdit>;
  begin
    Result := nil;
    if ALoop.ChildCount < 3 then
      Exit;
    StartExpr := ALoop[ALoop.ChildCount - 3];
    StopExpr := ALoop[ALoop.ChildCount - 2];
    Body := ALoop[ALoop.ChildCount - 1];
    TypeRef := ALoop.FindChild(TSyntaxKind.TypeReference);
    if HasOwnContinue(Body) then
      Exit;
    Compare := '<=';
    Step := 'Inc';
    for Index := TokenAt(StartExpr.EndOffset) to TokenAt(StopExpr.StartOffset) do
      if (Index <= High(Tokens)) and Tokens[Index].IsKeyword('downto') then
      begin
        Compare := '>=';
        Step := 'Dec';
      end;
    DoToken := PreviousCode(TokenAt(Body.StartOffset));
    if (DoToken < 0) or not Tokens[DoToken].IsKeyword('do') then
      Exit;
    Indent := IndentAt(ALoop.StartOffset, ALoop.StartPos.Character);
    Head := ALoop.Name + ' := ' + SourceOf(StartExpr) + ';';
    if AInline and (TypeRef <> nil) then
      Head := 'var ' + ALoop.Name + ': ' + SourceOf(TypeRef) + ' := ' + SourceOf(StartExpr) + ';'
    else if AInline then
      Head := 'var ' + Head;
    Head := Head + LineBreak + Indent + 'while ' + ALoop.Name + ' ' + Compare + ' ' + SourceOf(StopExpr) + ' do';
    if Body.Kind = TSyntaxKind.Block then
    begin
      // Vor dem end des Blocks: Inc(I); fehlt das Semikolon nach der letzten Anweisung, kommt es dazu.
      EndToken := PreviousCode(TokenAt(Body.EndOffset));
      if (EndToken < 0) or not Tokens[EndToken].IsKeyword('end') then
        Exit;
      Edits := [TRuleEdit.Create(TTextRange.Create(ALoop.StartPos, Tokens[DoToken].EndPos), Head)];
      Before := PreviousCode(EndToken);
      if (Before >= 0) and not Tokens[Before].IsSymbol(';') and not Tokens[Before].IsKeyword('begin') then
        Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Tokens[Before].EndPos, Tokens[Before].EndPos), ';')];
      Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Tokens[EndToken].StartPos, Tokens[EndToken].StartPos),
        '  ' + Step + '(' + ALoop.Name + ');' + LineBreak + IndentAt(Tokens[EndToken].Offset,
        Tokens[EndToken].StartPos.Character))];
    end
    else
      Edits := [TRuleEdit.Create(TTextRange.Create(ALoop.StartPos, Tokens[DoToken].EndPos),
        Head + LineBreak + Indent + 'begin'),
        TRuleEdit.Create(TTextRange.Create(Body.EndPos, Body.EndPos), ';' + LineBreak + Indent + '  ' + Step + '(' +
        ALoop.Name + ');' + LineBreak + Indent + 'end')];
    Result := [TRuleFix.Create('Auf while-Schleife umstellen', Edits)];
  end;

  // Meldungen im Rumpf: Zuweisung, Inc/Dec und var-Übergabe der Schleifenvariablen AName.
  procedure CheckBody(ANode, ALoop: TSyntaxNode; const AName: string; AInline: Boolean);
  var
    Index: Integer;
    Target, Call: TSyntaxNode;
    Name: string;
  begin
    // Anonyme Methoden laufen später, with kann den Namen umdeuten, eine innere Schleife mit demselben
    // Namen prüft der eigene Durchlauf.
    if (ANode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.WithStatement]) or
      ((ANode.Kind = TSyntaxKind.ForStatement) and SameText(ANode.Name, AName)) then
      Exit;
    if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount > 0) and IsPlainName(ANode[0], AName) then
      AReport.Add(TTextRange.Create(ANode[0].StartPos, ANode[0].EndPos),
        Format('Schleifenvariable %s darf im Rumpf nicht zugewiesen werden (wie E2081).', [AName]),
        TRuleConfidence.High, WhileFix(ALoop, AInline))
    else if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount = 1) and
      (ANode[0].Kind = TSyntaxKind.Call) and (ANode[0].ChildCount > 1) and
      (ANode[0][0].Kind = TSyntaxKind.Identifier) then
    begin
      Call := ANode[0];
      Name := Call[0].Name;
      for Index := 1 to Call.ChildCount - 1 do
      begin
        Target := Call[Index];
        if not IsPlainName(Target, AName) then
          Continue;
        if (Index = 1) and (SameText(Name, 'Inc') or SameText(Name, 'Dec')) and not VarRoutines.ContainsKey('inc') and
          not VarRoutines.ContainsKey('dec') then
          AReport.Add(TTextRange.Create(Target.StartPos, Target.EndPos),
            Format('Schleifenvariable %s darf im Rumpf nicht verändert werden (wie E2081).', [AName]),
            TRuleConfidence.High, WhileFix(ALoop, AInline))
        else if PassesByReference(Name, Index - 1) then
          AReport.Add(TTextRange.Create(Target.StartPos, Target.EndPos),
            Format('Schleifenvariable %s wird als var-Parameter an %s übergeben (wie W1015).', [AName, Name]),
            TRuleConfidence.High);
      end;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      CheckBody(ANode[Index], ALoop, AName, AInline);
  end;

  // Kommt AName in ANode außerhalb von ALoop vor?
  function UsedOutside(ANode, ALoop: TSyntaxNode; const AName: string): Boolean;
  var
    Index: Integer;
  begin
    if ANode = ALoop then
      Exit(False);
    if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName) then
      Exit(True);
    for Index := 0 to ANode.ChildCount - 1 do
      if UsedOutside(ANode[Index], ALoop, AName) then
        Exit(True);
    Result := False;
  end;

  // Schleifen der Routine ARoutine (Rumpf ABody); AOuterLocals: Variablen der umgebenden Routinen.
  procedure CheckRoutine(ARoutine, ABody: TSyntaxNode; AOuterLocals: TNameSet; const AClass: string);
  var
    Locals: TNameSet;
    Header, Params: TSyntaxNode;
    Index: Integer;

    procedure CollectInline(ANode: TSyntaxNode);
    var
      Child: Integer;
    begin
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        Exit;
      if ANode.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
        AddNames(Locals, ANode.Name);
      for Child := 0 to ANode.ChildCount - 1 do
        CollectInline(ANode[Child]);
    end;

    procedure VisitLoops(ANode: TSyntaxNode; AInWith: Boolean);
    var
      Child, ForToken: Integer;
      Name, Key, Kind: string;
      IsInline: Boolean;
      Fixes: TArray<TRuleFix>;
    begin
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        Exit;
      if ANode.Kind = TSyntaxKind.WithStatement then
        AInWith := True;
      if (ANode.Kind = TSyntaxKind.ForStatement) and (ANode.Name <> '') and not AInWith then
      begin
        Name := ANode.Name;
        ForToken := TokenAt(ANode.StartOffset);
        IsInline := (NextCode(ForToken + 1) <= High(Tokens)) and Tokens[NextCode(ForToken + 1)].IsKeyword('var');
        Key := LowerCase(Name);
        if not IsInline and not Locals.ContainsKey(Key) then
        begin
          // Nicht lokal: lokale Variable einer umgebenden Routine, Feld der eigenen Klasse oder globale Variable.
          Kind := '';
          if AOuterLocals.ContainsKey(Key) then
            Kind := 'eine Variable der umgebenden Routine'
          else if (AClass <> '') and Fields.ContainsKey(AClass + '.' + Key) then
            Kind := 'ein Feld'
          else if Globals.ContainsKey(Key) then
            Kind := 'eine globale Variable';
          if Kind <> '' then
          begin
            Fixes := nil;
            if not UsedOutside(ABody, ANode, Name) then
              Fixes := [TRuleFix.Create('for var ' + Name + ' verwenden',
                [TRuleEdit.Create(TTextRange.Create(Tokens[NextCode(ForToken + 1)].StartPos,
                Tokens[NextCode(ForToken + 1)].StartPos), 'var ')])];
            AReport.Add(TTextRange.Create(Tokens[NextCode(ForToken + 1)].StartPos,
              Tokens[NextCode(ForToken + 1)].EndPos), Format('Schleifenvariable %s ist %s, keine einfache ' +
              'lokale Variable (wie E1019).', [Name, Kind]), TRuleConfidence.High, Fixes);
          end;
        end;
        if ANode.ChildCount > 0 then
          CheckBody(ANode[ANode.ChildCount - 1], ANode, Name, IsInline);
      end;
      for Child := 0 to ANode.ChildCount - 1 do
        VisitLoops(ANode[Child], AInWith);
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
          for Index := 0 to Params.ChildCount - 1 do
            AddNames(Locals, Params[Index].Name);
      end;
      CollectInline(ABody);
      if not ParserBroken(AContext.Tree, ARoutine) then
        VisitLoops(ABody, False);
      // Lokale Routinen: deren umgebende Variablen sind diese plus die äußeren.
      for Pair in AOuterLocals do
        Outer.AddOrSetValue(Pair.Key, True);
      for Pair in Locals do
        Outer.AddOrSetValue(Pair.Key, True);
      for Index := 0 to ARoutine.ChildCount - 1 do
      begin
        Child := ARoutine[Index];
        if (Child.Kind = TSyntaxKind.RoutineDecl) and (Child.FindChild(TSyntaxKind.Block) <> nil) then
          CheckRoutine(Child, Child.FindChild(TSyntaxKind.Block), Outer, AClass);
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
          ClassName := LowerCase(Copy(Body.Name, 1, LastDelimiter('.', Body.Name) - 1));
        NoOuter := TNameSet.Create;
        try
          CheckRoutine(Body, Body.FindChild(TSyntaxKind.Block), NoOuter, ClassName);
        finally
          NoOuter.Free;
        end;
      end
      else if Body.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
        VisitRoutines(Body);
    end;
  end;

  procedure CollectGlobals(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    AddVariables(Globals, ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      if ANode[Index].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
        AddVariables(Globals, ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'for') then
    Exit;
  Tokens := AContext.Tree.Tokens;
  LineBreak := #10;
  if Pos(#13#10, AContext.Text) > 0 then
    LineBreak := #13#10;
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

procedure RegisterLoopRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TForVariableMisuseRule.Create);
end;

end.
