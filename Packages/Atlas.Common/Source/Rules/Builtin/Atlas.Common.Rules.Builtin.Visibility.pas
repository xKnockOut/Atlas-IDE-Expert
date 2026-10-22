unit Atlas.Common.Rules.Builtin.Visibility;

// Regeln zur Sichtbarkeit von Klassenmitgliedern (#909, Gruppe Compiler vorab):
//   inaccessible-member  Zugriff auf ein Mitglied, das an der Stelle nicht
//                        sichtbar ist (#1008): A.B mit B private bzw. strict
//                        private einer anderen Unit oder Klasse (wie E2361),
//                        protected bzw. strict protected außerhalb der Unit und
//                        der Nachfahren (wie E2362); Instanzmitglieder in einer
//                        Klassenmethode oder statischen Methode (wie E2124);
//                        Properties, die auf ein private-Mitglied eines
//                        Vorfahren derselben Unit verweisen (wie W1045, als
//                        Warnung).
//
// Grundlage ist die Namensauflösung: Ein Zugriff gilt erst als unsichtbar, wenn
// die Auflösung den Empfänger und seinen Typ sicher kennt, das Mitglied mit
// Rücksicht auf die Sichtbarkeit nicht findet und ohne sie (DeclaredMember)
// schon. Deklarationen in bedingten Zweigen, Methoden von Helfern und
// verschachtelten Typen (die mehr sehen dürfen) bleiben still.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  InaccessibleMemberRuleId = 'inaccessible-member';

type
  TInaccessibleMemberRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterVisibilityRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance;

const
  Restricted = [TIndexVisibility.Private, TIndexVisibility.StrictPrivate, TIndexVisibility.Protected,
    TIndexVisibility.StrictProtected];

function VisibilityText(AVisibility: TIndexVisibility): string;
begin
  case AVisibility of
    TIndexVisibility.Private:
      Result := 'private';
    TIndexVisibility.StrictPrivate:
      Result := 'strict private';
    TIndexVisibility.Protected:
      Result := 'protected';
    TIndexVisibility.StrictProtected:
      Result := 'strict protected';
  else
    Result := 'public';
  end;
end;

/// <summary>Trägt ADirectives die Direktive ADirective?</summary>
function HasDirective(const ADirectives: TArray<string>; const ADirective: string): Boolean;
var
  Directive: string;
begin
  for Directive in ADirectives do
    if SameText(Directive, ADirective) then
      Exit(True);
  Result := False;
end;

{ TInaccessibleMemberRule }

function TInaccessibleMemberRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(InaccessibleMemberRuleId, TRuleSeverity.Error,
    'Zugriff auf ein nicht sichtbares Mitglied');
end;

procedure TInaccessibleMemberRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Local: TUnitIndex;
  Tokens: TArray<TPascalToken>;
  Resolver: TNameResolver;
  FileName: string;
  // Name -> gibt es ein nicht öffentliches Mitglied dieses Namens (Datei oder Index)?
  Suspects: TDictionary<string, Boolean>;

  function Suspect(const AName: string): Boolean;
  var
    Symbol: TIndexSymbol;
    Location: TSymbolLocation;
  begin
    if Suspects.TryGetValue(LowerCase(AName), Result) then
      Exit;
    Result := False;
    for Symbol in Local.Symbols do
      if (Symbol.Container <> '') and (Symbol.Visibility in Restricted) and SameText(Symbol.Name, AName) then
        Result := True;
    if not Result and (AContext.Index <> nil) then
      for Location in AContext.Index.FindSymbols(AName) do
        if (Location.Symbol.Container <> '') and (Location.Symbol.Visibility in Restricted) then
        begin
          Result := True;
          Break;
        end;
    Suspects.Add(LowerCase(AName), Result);
  end;

  /// <summary>Methode, in der ANode steht (äußerste Routine mit Punkt im Namen); nil außerhalb.</summary>
  function EnclosingMethod(ANode: TSyntaxNode): TSyntaxNode;
  var
    Node: TSyntaxNode;
  begin
    Result := nil;
    Node := ANode.Parent;
    while Node <> nil do
    begin
      if (Node.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', Node.Name) > 0) then
        Result := Node;
      Node := Node.Parent;
    end;
  end;

  /// <summary>Darf die Methode AMethod mehr sehen als die Regel prüft? Methoden von Helfern (protected
  /// des erweiterten Typs) und verschachtelten Typen (Mitglieder des äußeren Typs).</summary>
  function WiderScope(AMethod: TSyntaxNode): Boolean;
  var
    TypeName: string;
    Symbol: TIndexSymbol;
  begin
    if AMethod = nil then
      Exit(False);
    TypeName := Copy(AMethod.Name, 1, LastDelimiter('.', AMethod.Name) - 1);
    if Pos('.', TypeName) > 0 then
      Exit(True);
    for Symbol in Local.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.HelperType) and SameText(Symbol.Name, TypeName) then
        Exit(True);
    Result := False;
  end;

  /// <summary>Beginnt die Routine ANode mit "class" (class function/procedure)?</summary>
  function IsClassMethod(ANode: TSyntaxNode): Boolean;
  var
    Low, High_, Middle: Integer;
  begin
    Low := 0;
    High_ := High(Tokens);
    while Low < High_ do
    begin
      Middle := (Low + High_) div 2;
      if Tokens[Middle].Offset < ANode.StartOffset then
        Low := Middle + 1
      else
        High_ := Middle;
    end;
    Result := (Low <= High(Tokens)) and (Tokens[Low].Offset = ANode.StartOffset) and Tokens[Low].IsKeyword('class') and
      (Low < High(Tokens)) and (Tokens[Low + 1].IsKeyword('function') or Tokens[Low + 1].IsKeyword('procedure'));
  end;

  /// <summary>Bereich des Mitgliedsnamens hinter dem Punkt in A.B.</summary>
  function MemberRange(ANode: TSyntaxNode): TTextRange;
  begin
    Result := TTextRange.Create(ANode.EndPos.Line, ANode.EndPos.Character - Length(ANode.Name), ANode.EndPos.Line,
      ANode.EndPos.Character);
  end;

  procedure CheckMemberAccess(ANode: TSyntaxNode);
  var
    Symbol, TypeInfo, Receiver, ReceiverType, Member: TResolvedSymbol;
    TypeFound: Boolean;
    Code: string;
  begin
    if (ANode.ChildCount <> 1) or (ANode.Name = '') or (ANode.EndPos.Line <> ANode[0].EndPos.Line) or
      not Suspect(ANode.Name) then
      Exit;
    if Resolver.NodeType(AContext.Tree, FileName, ANode, Symbol, TypeInfo, TypeFound) then
      Exit;
    if not Resolver.NodeType(AContext.Tree, FileName, ANode[0], Receiver, ReceiverType, TypeFound) or
      not TypeFound or (Receiver.Kind = TResolvedKind.UnitName) or ReceiverType.Builtin then
      Exit;
    // Sichtbar über Helfer oder Vorfahren: kein Fall für diese Regel.
    if Resolver.FindMember(ReceiverType, ANode.Name, Member) or
      not Resolver.DeclaredMember(ReceiverType, ANode.Name, Member) or not (Member.Visibility in Restricted) or
      (Member.Condition <> '') then
      Exit;
    if (Member.Visibility <> TIndexVisibility.Private) and WiderScope(EnclosingMethod(ANode)) then
      Exit;
    Code := 'E2361';
    if Member.Visibility in [TIndexVisibility.Protected, TIndexVisibility.StrictProtected] then
      Code := 'E2362';
    AReport.Add(MemberRange(ANode), Format('%s.%s ist %s und hier nicht sichtbar (wie %s).', [Member.Container,
      Member.Name, VisibilityText(Member.Visibility), Code]), TRuleConfidence.High);
  end;

  procedure CheckInstanceMember(ANode: TSyntaxNode; AMethod: TSyntaxNode);
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound, Unknown: Boolean;
    WithNode: TSyntaxNode;
    Element: Integer;
    What, MethodName: string;
  begin
    if not Resolver.NodeType(AContext.Tree, FileName, ANode, Symbol, TypeInfo, TypeFound) or
      (Symbol.Kind <> TResolvedKind.Symbol) or (Symbol.Container = '') or
      not (Symbol.SymbolKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Method]) or
      HasDirective(Symbol.Directives, 'class') or (Symbol.Condition <> '') then
      Exit;
    // Mitglied eines with-Ausdrucks (with Result do Pfad := …) ist erreichbar.
    if Resolver.WithMember(AContext.Tree, FileName, ANode.Name, ANode.StartOffset, WithNode, Element, Unknown) or
      Unknown then
      Exit;
    case Symbol.SymbolKind of
      TIndexSymbolKind.Field:
        What := 'ein Instanzfeld';
      TIndexSymbolKind.Property_:
        What := 'eine Instanz-Property';
    else
      What := 'eine Instanzmethode';
    end;
    MethodName := Copy(AMethod.Name, LastDelimiter('.', AMethod.Name) + 1, MaxInt);
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('%s ist %s und in der Klassenmethode %s ' +
      'nicht erreichbar (wie E2124).', [Symbol.Name, What, MethodName]), TRuleConfidence.High);
  end;

  procedure Visit(ANode: TSyntaxNode; AClassMethod: TSyntaxNode);
  var
    Index: Integer;
  begin
    case ANode.Kind of
      TSyntaxKind.InheritedExpr:
        Exit;
      TSyntaxKind.RoutineDecl:
        if (Pos('.', ANode.Name) > 0) and IsClassMethod(ANode) then
          AClassMethod := ANode;
      TSyntaxKind.MemberAccess:
        CheckMemberAccess(ANode);
      TSyntaxKind.Identifier:
        if (AClassMethod <> nil) and (ANode.Name <> '') then
          CheckInstanceMember(ANode, AClassMethod);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      // Kopf der Klassenmethode (Parameter, Ergebnistyp) ist kein Zugriff.
      if (ANode.Kind <> TSyntaxKind.RoutineDecl) or (AClassMethod = nil) or (ANode[Index].Kind = TSyntaxKind.Block) or
        (ANode[Index].Kind = TSyntaxKind.RoutineDecl) then
        Visit(ANode[Index], AClassMethod)
      else if ANode[Index].Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection] then
        Visit(ANode[Index], nil);
  end;

  /// <summary>Wörter hinter read und write einer Property-Signatur (bei read FPunkt.X nur FPunkt).</summary>
  function AccessorNames(const ASignature: string): TArray<string>;
  var
    Words: TArray<string>;
    Index: Integer;
    Name: string;
  begin
    Result := nil;
    Words := ASignature.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty);
    for Index := 0 to High(Words) - 1 do
      if SameText(Words[Index], 'read') or SameText(Words[Index], 'write') then
      begin
        Name := Words[Index + 1];
        if Pos('.', Name) > 0 then
          Name := Copy(Name, 1, Pos('.', Name) - 1);
        Result := Result + [Name];
      end;
  end;

  /// <summary>W1045: Property einer Klasse der Datei verweist auf ein private-Mitglied eines Vorfahren, der in
  /// derselben Unit steht.</summary>
  procedure CheckPropertyAccessors;
  var
    Ancestry: TAncestry;
    Symbol, Member: TIndexSymbol;
    Chain: TArray<TSymbolLocation>;
    Owner: TSymbolLocation;
    Complete, ObjectMissing, Own: Boolean;
    Name: string;
    Level: Integer;
    Reported: TArray<string>;
  begin
    Ancestry := TAncestry.Create(AContext.Index, Local);
    try
      for Symbol in Local.Symbols do
      begin
        if (Symbol.Kind <> TIndexSymbolKind.Property_) or (Symbol.Container = '') or Symbol.Unavailable or
          (Symbol.Condition <> '') or not Ancestry.FindClass(Symbol.Container, Owner) or (Owner.FileName <> '') then
          Continue;
        Reported := nil;
        for Name in AccessorNames(Symbol.Signature) do
        begin
          if IndexText(Name, Reported) >= 0 then
            Continue;
          // Im eigenen Typ deklariert: kein Fall für W1045.
          Own := False;
          for Member in Ancestry.Members(Owner) do
            if SameText(Member.Name, Name) then
              Own := True;
          if Own then
            Continue;
          Chain := Ancestry.Ancestors(Owner.Symbol.Name, Complete, ObjectMissing);
          for Level := 0 to High(Chain) do
          begin
            Own := False;
            for Member in Ancestry.Members(Chain[Level]) do
              if SameText(Member.Name, Name) then
              begin
                Own := True;
                if (Member.Visibility = TIndexVisibility.Private) and (Chain[Level].FileName = '') and
                  not Member.Unavailable and (Member.Condition = '') then
                begin
                  AReport.AddWithSeverity(Symbol.SelectionRange, Format('Die Property %s verweist auf %s.%s, ' +
                    'das im Vorfahren private ist (wie W1045).', [Symbol.Name, Chain[Level].Symbol.Name,
                    Member.Name]), TRuleSeverity.Warning, nil);
                  Reported := Reported + [Name];
                end;
                Break;
              end;
            if Own then
              Break;
          end;
        end;
      end;
    finally
      Ancestry.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Local := TRuleDerived.UnitIndex(Cache, AContext);
  Tokens := TRuleDerived.CodeTokens(Cache, AContext);
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  CheckPropertyAccessors;
  Suspects := TDictionary<string, Boolean>.Create;
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Visit(AContext.Tree.Root, nil);
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Suspects.Free;
  end;
end;

procedure RegisterVisibilityRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TInaccessibleMemberRule.Create);
end;

end.
