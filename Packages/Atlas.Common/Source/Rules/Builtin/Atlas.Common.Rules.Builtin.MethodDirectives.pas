unit Atlas.Common.Rules.Builtin.MethodDirectives;

// Direktiven an Methoden und Klassen (#909, Gruppe Compiler vorab):
//   abstract-declaration-invalid  abstract, final oder static falsch kombiniert
//                                 (#998): abstract ohne virtual oder dynamic
//                                 (E2167), Rumpf zu einer abstrakten Methode
//                                 (E2136), final ohne virtual (E2351), abstract
//                                 zusammen mit final (E2371), eine Klasse
//                                 abstract sealed (E2383) und static an einer
//                                 Instanzmethode oder virtuellen Klassenmethode
//                                 (E2376).
//
// Die Regel liest die Direktiven aus dem Syntaxbaum und braucht keinen Index.
// override und message zählen wie virtual (override; abstract; deklariert eine
// geerbte Methode neu als abstrakt). Ein Rumpf gilt nur dann als Rumpf einer
// abstrakten Methode, wenn keine gleichnamige nicht abstrakte Methode derselben
// Klasse mit ihm übersetzt wird (Überladungen, Zweige von {$IFDEF} über
// TConditionalBranches).
//
// Korrekturen: "virtual;" vor abstract einfügen (E2167) bzw. den Rumpf
// entfernen (E2136).

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  AbstractDeclarationInvalidRuleId = 'abstract-declaration-invalid';

type
  TAbstractDeclarationInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterMethodDirectiveRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Text.Lines;

type
  /// <summary>Methodendeklaration einer Klasse: abstrakt oder nicht, mit Zweig der bedingten Übersetzung.</summary>
  TDeclaredMethod = record
    ClassName: string;
    Name: string;
    IsAbstract: Boolean;
    Path: string;
  end;

/// <summary>Typname ohne Typparameter ("TListe&lt;T&gt;" wird "TListe").</summary>
function WithoutTypeParams(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
    Result := Copy(Result, 1, Pos('<', Result) - 1);
end;

function TAbstractDeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(AbstractDeclarationInvalidRuleId, TRuleSeverity.Error,
    'abstract, final oder static falsch kombiniert');
end;

procedure TAbstractDeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;
  Declared: TArray<TDeclaredMethod>;
  Lines: TArray<string>;

  /// <summary>Erstes Token ab AOffset (Index); Length(Tokens) ohne.</summary>
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

  function TokenRange(AIndex: Integer): TTextRange;
  begin
    Result := TTextRange.Create(Tokens[AIndex].StartPos, Tokens[AIndex].EndPos);
  end;

  /// <summary>Token der Direktive ADirective im Kopf AHeader; -1 ohne.</summary>
  function DirectiveToken(AHeader: TSyntaxNode; const ADirective: string): Integer;
  var
    Index: Integer;
  begin
    for Index := 0 to AHeader.ChildCount - 1 do
      if (AHeader[Index].Kind = TSyntaxKind.Directive) and SameText(AHeader[Index].Name, ADirective) then
      begin
        Result := TokenAt(AHeader[Index].StartOffset);
        if Result < Length(Tokens) then
          Exit;
      end;
    Result := -1;
  end;

  function HasDirective(AHeader: TSyntaxNode; const ADirective: string): Boolean;
  begin
    Result := DirectiveToken(AHeader, ADirective) >= 0;
  end;

  procedure CheckHeader(const AClassName: string; AHeader: TSyntaxNode);
  var
    First, Abstract_, Final, Static: Integer;
    IsVirtual, IsClassMethod: Boolean;
    Method: TDeclaredMethod;
  begin
    First := TokenAt(AHeader.StartOffset);
    if First >= Length(Tokens) then
      Exit;
    IsClassMethod := Tokens[First].IsKeyword('class');
    IsVirtual := HasDirective(AHeader, 'virtual') or HasDirective(AHeader, 'dynamic') or
      HasDirective(AHeader, 'override') or HasDirective(AHeader, 'message');
    Abstract_ := DirectiveToken(AHeader, 'abstract');
    Final := DirectiveToken(AHeader, 'final');
    Static := DirectiveToken(AHeader, 'static');
    if (Abstract_ >= 0) and not IsVirtual then
      AReport.Add(TokenRange(Abstract_), 'abstract nur zusammen mit virtual oder dynamic (wie E2167).',
        TRuleConfidence.High, [TRuleFix.Create('"virtual;" vor abstract einfügen',
        [TRuleEdit.Create(TTextRange.Create(Tokens[Abstract_].StartPos, Tokens[Abstract_].StartPos), 'virtual; ')])]);
    if (Abstract_ >= 0) and (Final >= 0) then
      AReport.Add(TokenRange(Final), Format('%s ist abstract und final zugleich; eine abstrakte Methode muss ' +
        'sich überschreiben lassen (wie E2371).', [AHeader.Name]), TRuleConfidence.High)
    else if (Final >= 0) and not IsVirtual then
      AReport.Add(TokenRange(Final), Format('final nur an virtuellen Methoden; %s ist nicht virtual, dynamic ' +
        'oder override (wie E2351).', [AHeader.Name]), TRuleConfidence.High);
    if Static >= 0 then
      if not IsClassMethod then
        AReport.Add(TokenRange(Static), Format('static nur an Klassenmethoden; %s ist eine Instanzmethode ' +
          '(wie E2376).', [AHeader.Name]), TRuleConfidence.High)
      else if IsVirtual or (Abstract_ >= 0) then
        AReport.Add(TokenRange(Static), Format('static nur an nicht virtuellen Klassenmethoden; %s ist virtuell ' +
          '(wie E2376).', [AHeader.Name]), TRuleConfidence.High);
    Method.ClassName := AClassName;
    Method.Name := AHeader.Name;
    Method.IsAbstract := Abstract_ >= 0;
    Method.Path := TConditionalBranches.PathAt(Paths, First);
    Declared := Declared + [Method];
  end;

  /// <summary>E2383: "class abstract sealed" bzw. "class sealed abstract".</summary>
  procedure CheckClassHeader(ABody: TSyntaxNode);
  var
    Index: Integer;
    Abstract_, Sealed: Boolean;
  begin
    Index := TokenAt(ABody.StartOffset);
    if (Index >= Length(Tokens)) or not Tokens[Index].IsKeyword('class') then
      Exit;
    Abstract_ := False;
    Sealed := False;
    Inc(Index);
    while (Index < Length(Tokens)) and (Tokens[Index].Kind in [TPascalTokenKind.Identifier,
      TPascalTokenKind.Keyword, TPascalTokenKind.Comment]) do
    begin
      if Tokens[Index].Kind <> TPascalTokenKind.Comment then
      begin
        if SameText(Tokens[Index].Text, 'abstract') then
          Abstract_ := True
        else if SameText(Tokens[Index].Text, 'sealed') then
          Sealed := True
        else
          Break;
        if Abstract_ and Sealed then
        begin
          AReport.Add(TokenRange(Index), 'Eine Klasse ist entweder abstract oder sealed, nicht beides ' +
            '(wie E2383).', TRuleConfidence.High);
          Exit;
        end;
      end;
      Inc(Index);
    end;
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node, Body: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.TypeDecl then
        begin
          Body := Node.FindChild(TSyntaxKind.ClassType);
          if Body = nil then
            Body := Node.FindChild(TSyntaxKind.ObjectType);
          if Body <> nil then
          begin
            if Body.Kind = TSyntaxKind.ClassType then
              CheckClassHeader(Body);
            for Index := 0 to Body.ChildCount - 1 do
              if Body[Index].Kind = TSyntaxKind.RoutineHeader then
                CheckHeader(WithoutTypeParams(Node.Name), Body[Index]);
            Node := Body;
          end;
        end;
        // Nur Deklarationscontainer: Anweisungen und Ausdrücke enthalten keine Typen (#1094).
        for Index := Node.ChildCount - 1 downto 0 do
          if Node[Index].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
            TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl, TSyntaxKind.RoutineDecl] then
            Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  /// <summary>Wird mit dem Rumpf an APath eine nicht abstrakte Deklaration AClassName.AName übersetzt? Und
  /// eine abstrakte (AAbstract)?</summary>
  procedure Lookup(const AClassName, AName, APath: string; out AAbstract, AConcrete: Boolean);
  var
    Method: TDeclaredMethod;
  begin
    AAbstract := False;
    AConcrete := False;
    for Method in Declared do
      if SameText(Method.ClassName, AClassName) and SameText(Method.Name, AName) and
        not TConditionalBranches.Exclusive(Method.Path, APath) then
        if Method.IsAbstract then
          AAbstract := True
        else
          AConcrete := True;
  end;

  /// <summary>Korrektur: den Rumpf mit seinen Zeilen und einer folgenden Leerzeile entfernen.</summary>
  function RemoveBody(ARoutine: TSyntaxNode): TArray<TRuleFix>;
  var
    StartPos, EndPos: TTextPosition;
  begin
    Result := nil;
    StartPos := ARoutine.StartPos;
    EndPos := ARoutine.EndPos;
    if (StartPos.Line >= Length(Lines)) or (EndPos.Line >= Length(Lines)) or
      (Trim(Copy(Lines[StartPos.Line], 1, StartPos.Character)) <> '') or
      (Trim(Copy(Lines[EndPos.Line], EndPos.Character + 1, MaxInt)) <> '') then
      Exit;
    StartPos.Character := 0;
    EndPos.Line := EndPos.Line + 1;
    EndPos.Character := 0;
    if (EndPos.Line < Length(Lines)) and (Trim(Lines[EndPos.Line]) = '') and (StartPos.Line > 0) and
      (Trim(Lines[StartPos.Line - 1]) = '') then
      EndPos.Line := EndPos.Line + 1;
    Result := [TRuleFix.Create('Rumpf entfernen', [TRuleEdit.Create(TTextRange.Create(StartPos, EndPos), '')])];
  end;

  procedure CheckBody(ARoutine: TSyntaxNode);
  var
    Parts: TArray<string>;
    ClassName, Name: string;
    IsAbstract, IsConcrete: Boolean;
    Header: TSyntaxNode;
    First: Integer;
  begin
    if (ARoutine.FindChild(TSyntaxKind.Block) = nil) and (ARoutine.FindChild(TSyntaxKind.AsmBlock) = nil) then
      Exit;
    Parts := ARoutine.Name.Split(['.']);
    if Length(Parts) < 2 then
      Exit;
    ClassName := Parts[High(Parts) - 1];
    Name := Parts[High(Parts)];
    First := TokenAt(ARoutine.StartOffset);
    Lookup(ClassName, Name, TConditionalBranches.PathAt(Paths, First), IsAbstract, IsConcrete);
    if not IsAbstract or IsConcrete then
      Exit;
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if Header = nil then
      Exit;
    // Den Namen hinter dem Klassennamen markieren.
    First := TokenAt(Header.StartOffset);
    while (First < Length(Tokens)) and (Tokens[First].Offset < Header.EndOffset) and
      not ((Tokens[First].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[First].Text, Name) and
      (First > 0) and Tokens[First - 1].IsSymbol('.')) do
      Inc(First);
    if (First >= Length(Tokens)) or (Tokens[First].Offset >= Header.EndOffset) then
      Exit;
    AReport.Add(TokenRange(First), Format('%s.%s ist abstract und darf keinen Rumpf haben (wie E2136).',
      [ClassName, Name]), TRuleConfidence.High, RemoveBody(ARoutine));
  end;

  // Rekursion nur in den implementation-Abschnitt (höchstens zwei Ebenen, unabhängig von der Ausdruckstiefe).
  procedure VisitBodies(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
      if ANode[Index].Kind = TSyntaxKind.RoutineDecl then
        CheckBody(ANode[Index])
      else if ANode[Index].Kind = TSyntaxKind.ImplementationSection then
        VisitBodies(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  Lines := TTextLines.SplitLines(AContext.Text);
  Declared := nil;
  Visit(AContext.Tree.Root);
  if Declared <> nil then
    VisitBodies(AContext.Tree.Root);
end;

procedure RegisterMethodDirectiveRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TAbstractDeclarationInvalidRule.Create);
end;

end.
