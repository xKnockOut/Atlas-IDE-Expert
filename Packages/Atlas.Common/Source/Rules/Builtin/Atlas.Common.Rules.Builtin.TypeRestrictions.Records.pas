unit Atlas.Common.Rules.Builtin.TypeRestrictions.Records;

// Regel aus TypeRestrictions, registriert mit RegisterTypeRestrictionRules:
//   type-restriction-violated     feste Sprachregeln für Records, Helfer,
//                                 Klassenkonstruktoren, inline und threadvar
//                                 (#994): virtuelle und andere verbotene
//                                 Direktiven in Records (E2379, E2463) und
//                                 Record-Helfern (E2598, E2475),
//                                 parameterlose Konstruktoren (E2394, E2471)
//                                 und Destruktoren (E2465) in Records, class-
//                                 Methoden ohne static (E2398); Felder in
//                                 Helfern (E2599), Destruktor (E2295) im
//                                 Class-Helfer, Vorfahr-Helfer für
//                                 fremde Typen (E2294), Helfer als Typ
//                                 (E2527) oder in generischem Kontext
//                                 (E2589); mehrere oder parametrisierte bzw.
//                                 virtuelle Klassenkonstruktoren (E2359,
//                                 E2360, E2534); Methoden, Properties,
//                                 Klassenmitglieder, Typen und Konstanten in
//                                 lokalen oder anonymen Records (E2433 bis
//                                 E2437); inline an virtuellen Methoden
//                                 (E2425), mit asm (E2426), an Konstruktoren
//                                 (E2442), mit offenen Arrays (E2439), mit
//                                 Variablen oder typisierten Konstanten des
//                                 implementation-Teils (E2441; echte
//                                 Konstanten, Typen und Routinen übersetzt
//                                 dcc, #1328),
//                                 mit Zugriff auf die umgebende Routine
//                                 (E2449) oder Aufruf eigener lokaler
//                                 Routinen (E2501); lokale, absolute oder
//                                 initialisierte threadvar (E2189, E2190,
//                                 E2194). Option disabledChecks nimmt Codes
//                                 aus. Korrekturen: Direktive entfernen bzw.
//                                 static ergänzen.

interface

uses
  Atlas.Common.Rules.Contract;

const
  TypeRestrictionViolatedRuleId = 'type-restriction-violated';

type
  TTypeRestrictionViolatedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Heads,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Symbols;

{ TTypeRestrictionViolatedRule }

const
  // Direktiven, die Records und Record-Helfer nicht kennen (E2379, E2463, E2598, E2475).
  RecordForbiddenDirectives: array[0..6] of string = ('virtual', 'dynamic', 'override', 'abstract', 'reintroduce',
    'message', 'final');
  // Davon die, die eine Methode virtuell machen (E2379, E2598).
  RecordVirtualDirectives: array[0..1] of string = ('virtual', 'dynamic');
  // Direktiven, die ein Klassenkonstruktor nicht tragen darf (E2534).
  ClassConstructorDirectives: array[0..2] of string = ('virtual', 'dynamic', 'message');
  // Elterntypen eines Typverweises, die eine Deklaration mit diesem Typ sind (E2527).
  DeclarationParents = [TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.RoutineHeader,
    TSyntaxKind.PropertyDecl, TSyntaxKind.ConstDecl, TSyntaxKind.InlineVar, TSyntaxKind.ArrayType,
    TSyntaxKind.PointerType];

/// <summary>Steht vor ANode das Wort class (class var, class property)?</summary>
function PrecededByClass(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := TRoutineBody.PreviousToken(ATokens, TRoutineBody.TokenAt(ATokens, ANode.StartOffset));
  Result := (Index >= 0) and (Index < Length(ATokens)) and SameText(ATokens[Index].Text, 'class');
end;

/// <summary>Gibt es zwischen AFrom und ATo (Offsets) auf oberster Klammerebene das Token AText?</summary>
function HasTopLevelToken(const ATokens: TArray<TPascalToken>; AFrom, ATo: Integer; const AText: string): Boolean;
var
  Index, Depth: Integer;
begin
  Result := False;
  Depth := 0;
  Index := TRoutineBody.TokenAt(ATokens, AFrom);
  while (Index >= 0) and (Index < Length(ATokens)) and (ATokens[Index].Offset < ATo) do
  begin
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
    begin
      Inc(Depth);
    end
    else if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']') then
    begin
      Dec(Depth);
    end
    else if (Depth = 0) and not (ATokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) and
      SameText(ATokens[Index].Text, AText) then
    begin
      Exit(True);
    end;
    Inc(Index);
  end;
end;

/// <summary>Edit, das die Direktive ADirective samt Semikolon und dem Abstand davor entfernt.</summary>
function DirectiveRemoval(const ATokens: TArray<TPascalToken>; ADirective: TSyntaxNode; out AEdit: TRuleEdit):
  Boolean;
var
  Index, Before, After: Integer;
begin
  Result := False;
  Index := TRoutineBody.TokenAt(ATokens, ADirective.StartOffset);
  Before := TRoutineBody.PreviousToken(ATokens, Index);
  if (Index < 0) or (Index >= Length(ATokens)) or (Before < 0) then
  begin
    Exit;
  end;
  After := Index;
  while (After >= 0) and (After < Length(ATokens)) and not ATokens[After].IsSymbol(';') do
  begin
    After := TRoutineBody.NextToken(ATokens, After);
  end;
  if (After < 0) or (After >= Length(ATokens)) then
  begin
    Exit;
  end;
  AEdit := TRuleEdit.Create(TTextRange.Create(ATokens[Before].EndPos, ATokens[After].EndPos), '');
  Result := True;
end;

/// <summary>Zielt der Helfer AHelper (HelperType) auf diesen Typverweis; bei class helper (TBasis) for T ist es
/// der zweite.</summary>
function HelperTarget(AHelper: TSyntaxNode; out AAncestor: TSyntaxNode): TSyntaxNode;
var
  Count: Integer;
begin
  Count := 0;
  while (Count < AHelper.ChildCount) and (AHelper[Count].Kind = TSyntaxKind.TypeReference) do
  begin
    Inc(Count);
  end;
  AAncestor := nil;
  Result := nil;
  if Count >= 2 then
  begin
    AAncestor := AHelper[0];
    Result := AHelper[1];
  end
  else if Count = 1 then
  begin
    Result := AHelper[0];
  end;
end;

/// <summary>Hat jeder Parameter des Kopfs einen Vorgabewert (und gibt es mindestens einen)?</summary>
function AllParametersDefaulted(const ATokens: TArray<TPascalToken>; const AHead: TRoutineHead): Boolean;
var
  Parameter: TSyntaxNode;
begin
  Result := AHead.Parameters <> nil;
  for Parameter in AHead.Parameters do
  begin
    if not HasTopLevelToken(ATokens, Parameter.StartOffset, Parameter.EndOffset, '=') then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Hat der Kopf einen offenen Array-Parameter (array of T, array of const)?</summary>
function HasOpenArrayParameter(const AHead: TRoutineHead): Boolean;
var
  Parameter: TSyntaxNode;
begin
  for Parameter in AHead.Parameters do
  begin
    if Parameter.FindChild(TSyntaxKind.ArrayType) <> nil then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Ist der Record ARecord lokal (in einer Routine) oder anonym (ohne eigene Typdeklaration)?</summary>
function IsLocalOrAnonymousRecord(ARecord: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  if (ARecord.Parent = nil) or (ARecord.Parent.Kind <> TSyntaxKind.TypeDecl) then
  begin
    Exit(True);
  end;
  Node := ARecord.Parent.Parent;
  while Node <> nil do
  begin
    if Node.Kind = TSyntaxKind.RoutineDecl then
    begin
      Exit(True);
    end;
    Node := Node.Parent;
  end;
  Result := False;
end;

function TTypeRestrictionViolatedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(TypeRestrictionViolatedRuleId, TRuleSeverity.Error,
    'Sprachregel für Records, inline und Helfer verletzt');
end;

procedure TTypeRestrictionViolatedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Types: TFileTypes;
  Root: TSyntaxNode;
  Disabled, Paths: TArray<string>;
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
  Ancestry: TAncestry;

  procedure Report(const ACode: string; const ARange: TTextRange; const AMessage: string;
    const AFixes: TArray<TRuleFix>);
  begin
    if not MatchText(ACode, Disabled) then
    begin
      AReport.Add(ARange, AMessage, TRuleConfidence.High, AFixes);
    end;
  end;

  function NameRange(AHeader: TSyntaxNode): TTextRange;
  var
    At: Integer;
  begin
    At := NameToken(Tokens, AHeader);
    if At >= 0 then
    begin
      Result := TokenRange(Tokens[At]);
    end
    else
    begin
      Result := NodeRange(AHeader);
    end;
  end;

  function KeywordRange(ANode: TSyntaxNode): TTextRange;
  var
    At: Integer;
  begin
    At := TRoutineBody.TokenAt(Tokens, ANode.StartOffset);
    if (At >= 0) and (At < Length(Tokens)) then
    begin
      Result := TokenRange(Tokens[At]);
    end
    else
    begin
      Result := NodeRange(ANode);
    end;
  end;

  /// <summary>Korrektur, die alle Direktiven aus ANames am Kopf entfernt.</summary>
  function RemoveFix(const AHead: TRoutineHead; const ANames: array of string; const ATitle: string):
    TArray<TRuleFix>;
  var
    Edits: TArray<TRuleEdit>;
    Edit: TRuleEdit;
    Child: Integer;
  begin
    Edits := nil;
    for Child := 0 to AHead.Header.ChildCount - 1 do
    begin
      if (AHead.Header[Child].Kind = TSyntaxKind.Directive) and MatchText(AHead.Header[Child].Name, ANames) and
        DirectiveRemoval(Tokens, AHead.Header[Child], Edit) then
      begin
        Edits := Edits + [Edit];
      end;
    end;
    Result := nil;
    if Edits <> nil then
    begin
      Result := [TRuleFix.Create(ATitle, Edits)];
    end;
  end;

  /// <summary>Erste Direktive des Kopfs aus ANames oder nil.</summary>
  function FirstDirective(const AHead: TRoutineHead; const ANames: array of string): TSyntaxNode;
  var
    Child: Integer;
  begin
    for Child := 0 to AHead.Header.ChildCount - 1 do
    begin
      if (AHead.Header[Child].Kind = TSyntaxKind.Directive) and MatchText(AHead.Header[Child].Name, ANames) then
      begin
        Exit(AHead.Header[Child]);
      end;
    end;
    Result := nil;
  end;

  /// <summary>Deklaration (Kopf in Typ bzw. interface-Teil) zum Rumpf ARoutine, nil ohne.</summary>
  function DeclarationOf(ARoutine: TSyntaxNode): TSyntaxNode;
  var
    Header, Decl, Holder, Candidate: TSyntaxNode;
    Params: string;
    Child, Found: Integer;
  begin
    Result := nil;
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if Header = nil then
    begin
      Exit;
    end;
    Params := Squeezed(AContext.Text, Header.FindChild(TSyntaxKind.Parameters));
    if Pos('.', ARoutine.Name) > 0 then
    begin
      Decl := FindStructDecl(Root, LastPart(Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1)));
      if Decl = nil then
      begin
        Exit;
      end;
      Holder := TypeOfDecl(Decl);
    end
    else if (ARoutine.Parent <> nil) and (ARoutine.Parent.Kind = TSyntaxKind.ImplementationSection) then
    begin
      Holder := Root.FindChild(TSyntaxKind.InterfaceSection);
    end
    else
    begin
      Exit;
    end;
    if Holder = nil then
    begin
      Exit;
    end;
    Found := 0;
    for Child := 0 to Holder.ChildCount - 1 do
    begin
      Candidate := Holder[Child];
      if Candidate.Kind = TSyntaxKind.RoutineDecl then
      begin
        Candidate := Candidate.FindChild(TSyntaxKind.RoutineHeader);
      end;
      if (Candidate = nil) or (Candidate.Kind <> TSyntaxKind.RoutineHeader) or
        not SameText(Candidate.Name, LastPart(ARoutine.Name)) then
      begin
        Continue;
      end;
      Inc(Found);
      if Squeezed(AContext.Text, Candidate.FindChild(TSyntaxKind.Parameters)) = Params then
      begin
        Exit(Candidate);
      end;
      if (Params = '') and (Found = 1) then
      begin
        Result := Candidate;
      end;
    end;
    if Found > 1 then
    begin
      Result := nil;
    end;
  end;

  // Records: E2379, E2463, E2394, E2471, E2465, E2398; lokale und anonyme Records: E2433–E2437.
  procedure CheckRecord(ARecord: TSyntaxNode);
  var
    Child: Integer;
    Member, Directive: TSyntaxNode;
    Head: TRoutineHead;
  begin
    if IsLocalOrAnonymousRecord(ARecord) then
    begin
      for Child := 0 to ARecord.ChildCount - 1 do
      begin
        Member := ARecord[Child];
        case Member.Kind of
          TSyntaxKind.RoutineHeader:
            Report('E2433', NameRange(Member), 'Lokale und anonyme Records dürfen keine Methoden deklarieren ' +
              '(wie E2433).', nil);
          TSyntaxKind.PropertyDecl:
            Report('E2434', KeywordRange(Member), 'Lokale und anonyme Records dürfen keine Properties ' +
              'deklarieren (wie E2434).', nil);
          TSyntaxKind.VarSection:
            if PrecededByClass(Tokens, Member) then
            begin
              Report('E2435', KeywordRange(Member), 'Lokale und anonyme Records dürfen keine Klassenmitglieder ' +
                'deklarieren (wie E2435).', nil);
            end;
          TSyntaxKind.TypeSection:
            Report('E2436', KeywordRange(Member), 'Lokale und anonyme Records dürfen keine Typen deklarieren ' +
              '(wie E2436).', nil);
          TSyntaxKind.ConstSection:
            Report('E2437', KeywordRange(Member), 'Lokale und anonyme Records dürfen keine Konstanten ' +
              'deklarieren (wie E2437).', nil);
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
      end;
      Exit;
    end;
    for Child := 0 to ARecord.ChildCount - 1 do
    begin
      Member := ARecord[Child];
      if Member.Kind <> TSyntaxKind.RoutineHeader then
      begin
        Continue;
      end;
      Head := TRoutineHead.Read(Tokens, Member);
      if (Head.Keyword = 'operator') or (Head.IsClass and MatchText(Head.Keyword, ['constructor', 'destructor'])) then
      begin
        Continue;
      end;
      Directive := FirstDirective(Head, RecordVirtualDirectives);
      if Directive <> nil then
      begin
        Report('E2379', NodeRange(Directive), 'Records erlauben keine virtuellen Methoden (wie E2379).',
          RemoveFix(Head, RecordForbiddenDirectives, Directive.Name + ' entfernen'));
      end
      else
      begin
        Directive := FirstDirective(Head, RecordForbiddenDirectives);
        if Directive <> nil then
        begin
          Report('E2463', NodeRange(Directive), Format('Die Direktive %s ist in Records nicht erlaubt (wie E2463).',
            [Directive.Name]), RemoveFix(Head, RecordForbiddenDirectives, Directive.Name + ' entfernen'));
        end;
      end;
      if Head.Keyword = 'constructor' then
      begin
        if Head.ParameterCount = 0 then
        begin
          Report('E2394', NameRange(Member), 'Records erlauben keine parameterlosen Konstruktoren (wie E2394).', nil);
        end
        else if AllParametersDefaulted(Tokens, Head) then
        begin
          Report('E2471', NameRange(Member), 'Records erlauben keine Konstruktoren, die ohne Argumente aufrufbar ' +
            'sind; alle Parameter haben Vorgabewerte (wie E2471).', nil);
        end;
      end
      else if Head.Keyword = 'destructor' then
      begin
        Report('E2465', NameRange(Member), 'Records dürfen keinen Destruktor einführen (wie E2465).', nil);
      end
      else if Head.IsClass and MatchText(Head.Keyword, ['procedure', 'function']) and
        not Head.HasDirective('static') then
      begin
        Report('E2398', NameRange(Member), 'Klassenmethoden in Records müssen static sein (wie E2398).',
          [TRuleFix.Create('static ergänzen', [TRuleEdit.Create(TTextRange.Create(Member.EndPos, Member.EndPos),
          ' static;')])]);
      end;
    end;
  end;

  /// <summary>Stammt der Typ AName sicher nicht von AAncestor ab? False, wenn die Kette nicht bekannt ist.</summary>
  function CertainlyNotDescendant(const AName, AAncestor: string): Boolean;
  var
    Chain: TArray<TSymbolLocation>;
    Location: TSymbolLocation;
    Complete, ObjectMissing: Boolean;
  begin
    Result := False;
    if SameText(AName, AAncestor) then
    begin
      Exit;
    end;
    if SameText(AName, 'TObject') then
    begin
      Exit(True);
    end;
    if Ancestry = nil then
    begin
      Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
    end;
    Chain := Ancestry.Ancestors(AName, Complete, ObjectMissing);
    if not Complete then
    begin
      Exit;
    end;
    for Location in Chain do
    begin
      if SameText(Location.Symbol.Name, AAncestor) then
      begin
        Exit;
      end;
    end;
    if ObjectMissing and SameText(AAncestor, 'TObject') then
    begin
      Exit;
    end;
    Result := True;
  end;

  // Helfer: E2599, E2598, E2475, E2295, E2294, E2589. Klassenkonstruktoren im Class-Helfer (E2358) und
  // Helfer-Konstruktoren ohne Konstruktoraufruf zuerst (E2296) übersetzt dcc (Skia4Delphi MobileBars,
  // TSkPixmapHelper.Create, FMX.Skia TSkBitmapHelper; TR6, TR7, #1328); die Prüfungen sind entfallen.
  procedure CheckHelper(AHelper: TSyntaxNode);
  var
    Child, Inner: Integer;
    Member, Directive, Target, AncestorRef, AncestorDecl, AncestorTarget, Dummy, Outer: TSyntaxNode;
    Head: TRoutineHead;
    IsRecordHelper: Boolean;
    Helped, Wanted: string;
    TypeIndex: Integer;
  begin
    IsRecordHelper := SameText(AHelper.Name, 'record');
    Target := HelperTarget(AHelper, AncestorRef);
    Helped := '';
    if Target <> nil then
    begin
      Helped := BareTypeName(Target.Name);
    end;
    for Child := 0 to AHelper.ChildCount - 1 do
    begin
      Member := AHelper[Child];
      case Member.Kind of
        TSyntaxKind.Field:
          Report('E2599', KeywordRange(Member), 'Helfer dürfen keine Felder deklarieren (wie E2599).', nil);
        TSyntaxKind.VarSection:
          if not PrecededByClass(Tokens, Member) then
          begin
            for Inner := 0 to Member.ChildCount - 1 do
            begin
              Report('E2599', KeywordRange(Member[Inner]), 'Helfer dürfen keine Felder deklarieren (wie E2599).',
                nil);
            end;
          end;
        TSyntaxKind.RoutineHeader:
          begin
            Head := TRoutineHead.Read(Tokens, Member);
            if IsRecordHelper then
            begin
              Directive := FirstDirective(Head, RecordVirtualDirectives);
              if Directive <> nil then
              begin
                Report('E2598', NodeRange(Directive), 'Record-Helfer erlauben keine virtuellen Methoden ' +
                  '(wie E2598).', RemoveFix(Head, RecordForbiddenDirectives, Directive.Name + ' entfernen'));
              end
              else
              begin
                Directive := FirstDirective(Head, RecordForbiddenDirectives);
                if Directive <> nil then
                begin
                  Report('E2475', NodeRange(Directive), Format('Die Direktive %s ist in Record-Helfern nicht ' +
                    'erlaubt (wie E2475).', [Directive.Name]), RemoveFix(Head, RecordForbiddenDirectives,
                    Directive.Name + ' entfernen'));
                end;
              end;
            end
            else if (Head.Keyword = 'destructor') and not Head.IsClass then
            begin
              Report('E2295', NameRange(Member), 'Class-Helfer dürfen keinen Destruktor einführen (wie E2295).', nil);
            end;
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
    // Vorfahr-Helfer: nur Nachfahren seines Typs (E2294).
    if not IsRecordHelper and (AncestorRef <> nil) and (Helped <> '') then
    begin
      TypeIndex := Types.IndexOf(BareTypeName(AncestorRef.Name));
      if (TypeIndex >= 0) and (Types.DeclaredKind(BareTypeName(AncestorRef.Name)) = TSyntaxKind.HelperType) then
      begin
        AncestorDecl := Types.Types[TypeIndex];
        AncestorTarget := HelperTarget(AncestorDecl, Dummy);
        if AncestorTarget <> nil then
        begin
          Wanted := BareTypeName(AncestorTarget.Name);
          if CertainlyNotDescendant(Helped, Wanted) then
          begin
            Report('E2294', NodeRange(Target), Format('Ein Class-Helfer, der von %s abstammt, kann nur Nachfahren ' +
              'von %s helfen (wie E2294).', [BareTypeName(AncestorRef.Name), Wanted]), nil);
          end;
        end;
      end;
    end;
    // Helfer im Kontext eines parametrisierten Typs (E2589).
    Outer := AHelper.Parent;
    if Outer <> nil then
    begin
      Outer := Outer.Parent;
    end;
    while Outer <> nil do
    begin
      if (Outer.Kind = TSyntaxKind.TypeDecl) and (Outer.FindChild(TSyntaxKind.GenericParams) <> nil) then
      begin
        Report('E2589', KeywordRange(AHelper.Parent), 'Helfer dürfen nicht im Kontext eines parametrisierten Typs ' +
          'deklariert werden (wie E2589).', nil);
        Break;
      end;
      Outer := Outer.Parent;
    end;
  end;

  // Klassenkonstruktoren: E2360, E2534, E2359.
  procedure CheckClassConstructors(AType: TSyntaxNode);
  var
    Child: Integer;
    Head: TRoutineHead;
    Directive, First: TSyntaxNode;
  begin
    First := nil;
    for Child := 0 to AType.ChildCount - 1 do
    begin
      if AType[Child].Kind <> TSyntaxKind.RoutineHeader then
      begin
        Continue;
      end;
      Head := TRoutineHead.Read(Tokens, AType[Child]);
      if not Head.IsClass or (Head.Keyword <> 'constructor') then
      begin
        Continue;
      end;
      if Head.ParameterCount > 0 then
      begin
        Report('E2360', NameRange(Head.Header), 'Klassenkonstruktoren dürfen keine Parameter haben (wie E2360).', nil);
      end;
      Directive := FirstDirective(Head, ClassConstructorDirectives);
      if Directive <> nil then
      begin
        Report('E2534', NodeRange(Directive), 'Klassenkonstruktoren dürfen nicht virtual, dynamic oder message sein ' +
          '(wie E2534).', RemoveFix(Head, ClassConstructorDirectives, Directive.Name + ' entfernen'));
      end;
      if First = nil then
      begin
        First := Head.Header;
      end
      else if not TConditionalBranches.Exclusive(
        TConditionalBranches.PathAt(Paths, TRoutineBody.TokenAt(Tokens, First.StartOffset)),
        TConditionalBranches.PathAt(Paths, TRoutineBody.TokenAt(Tokens, Head.Header.StartOffset))) then
      begin
        Report('E2359', NameRange(Head.Header), Format('Mehrere Klassenkonstruktoren in %s: %s und %s (wie E2359).',
          [AType.Parent.Name, First.Name, Head.Header.Name]), nil);
      end;
    end;
  end;

  // inline an Köpfen: E2425, E2442, E2439.
  procedure CheckInlineHeader(AHeader: TSyntaxNode);
  var
    Head: TRoutineHead;
    InlineHead, Decl: TSyntaxNode;
  begin
    Head := TRoutineHead.Read(Tokens, AHeader);
    InlineHead := Head.Directive('inline');
    if InlineHead = nil then
    begin
      Exit;
    end;
    if (AHeader.Parent <> nil) and (AHeader.Parent.Kind = TSyntaxKind.RoutineDecl) then
    begin
      Decl := DeclarationOf(AHeader.Parent);
      if (Decl <> nil) and (Decl <> AHeader) and TRoutineHead.Read(Tokens, Decl).HasDirective('inline') then
      begin
        Exit;
      end;
    end;
    if FirstDirective(Head, RecordVirtualDirectives) <> nil then
    begin
      Report('E2425', NodeRange(InlineHead), 'Inline-Methoden dürfen nicht virtual oder dynamic sein (wie E2425).',
        RemoveFix(Head, ['inline'], 'inline entfernen'));
    end
    else if MatchText(Head.Keyword, ['constructor', 'destructor']) then
    begin
      Report('E2442', NodeRange(InlineHead), 'inline ist an Konstruktoren und Destruktoren nicht erlaubt (wie E2442).',
        RemoveFix(Head, ['inline'], 'inline entfernen'));
    end;
    if HasOpenArrayParameter(Head) then
    begin
      Report('E2439', NodeRange(InlineHead), 'Inline-Routinen dürfen keine offenen Array-Parameter haben (wie E2439).',
        RemoveFix(Head, ['inline'], 'inline entfernen'));
    end;
  end;

  /// <summary>Kopf mit inline zum Rumpf ARoutine (eigener Kopf oder Deklaration), nil ohne.</summary>
  function InlineHeader(ARoutine: TSyntaxNode): TSyntaxNode;
  var
    Header: TSyntaxNode;
  begin
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if (Header <> nil) and TRoutineHead.Read(Tokens, Header).HasDirective('inline') then
    begin
      Exit(Header);
    end;
    Result := DeclarationOf(ARoutine);
    if (Result <> nil) and not TRoutineHead.Read(Tokens, Result).HasDirective('inline') then
    begin
      Result := nil;
    end;
  end;

  /// <summary>Namen, die ARoutine selbst als Parameter und Variablen deklariert (ohne verschachtelte Routinen).</summary>
  function OwnVariables(ARoutine: TSyntaxNode): TArray<string>;
  var
    Child, Inner: Integer;
    Header: TSyntaxNode;
  begin
    Result := nil;
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if (Header <> nil) and (Header.FindChild(TSyntaxKind.Parameters) <> nil) then
    begin
      Result := NamesBelow(Header.FindChild(TSyntaxKind.Parameters));
    end;
    for Child := 0 to ARoutine.ChildCount - 1 do
    begin
      if ARoutine[Child].Kind = TSyntaxKind.VarSection then
      begin
        for Inner := 0 to ARoutine[Child].ChildCount - 1 do
        begin
          Result := Result + DeclaredNames(ARoutine[Child][Inner]);
        end;
      end;
    end;
  end;

  /// <summary>Bezeichner im Rumpf ABody, die nicht in with stehen.</summary>
  function IdentifiersIn(ABody: TSyntaxNode; ASkipNested: Boolean): TArray<TSyntaxNode>;
  var
    Found: TArray<TSyntaxNode>;
  begin
    Found := nil;
    ABody.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := (ANode.Kind <> TSyntaxKind.WithStatement) and
          not (ASkipNested and (ANode <> ABody) and (ANode.Kind = TSyntaxKind.RoutineDecl));
        if Result and (ANode.Kind = TSyntaxKind.Identifier) then
        begin
          Found := Found + [ANode];
        end;
      end);
    Result := Found;
  end;

  // Rümpfe von inline-Routinen: E2426, E2501, E2449.
  procedure CheckInlineBody(ARoutine: TSyntaxNode);
  var
    InlineHead, Head, Body, Outer: TSyntaxNode;
    Directive: TSyntaxNode;
    Nested, Outside, Own, Used: TArray<string>;
    Child: Integer;
    Ident: TSyntaxNode;
    Fix: TArray<TRuleFix>;
  begin
    InlineHead := InlineHeader(ARoutine);
    if InlineHead = nil then
    begin
      Exit;
    end;
    Directive := TRoutineHead.Read(Tokens, InlineHead).Directive('inline');
    Fix := RemoveFix(TRoutineHead.Read(Tokens, InlineHead), ['inline'], 'inline entfernen');
    if ARoutine.FindChild(TSyntaxKind.AsmBlock) <> nil then
    begin
      Report('E2426', NodeRange(Directive), 'Inline-Routinen dürfen keinen asm-Block haben (wie E2426).', Fix);
    end;
    Body := ARoutine.FindChild(TSyntaxKind.Block);
    if Body = nil then
    begin
      Exit;
    end;
    // Aufruf eigener lokaler Routinen.
    Nested := nil;
    for Child := 0 to ARoutine.ChildCount - 1 do
    begin
      if ARoutine[Child].Kind = TSyntaxKind.RoutineDecl then
      begin
        Nested := Nested + [ARoutine[Child].Name];
      end;
    end;
    Used := nil;
    if Nested <> nil then
    begin
      for Ident in IdentifiersIn(Body, True) do
      begin
        if MatchText(Ident.Name, Nested) and not MatchText(Ident.Name, Used) then
        begin
          Used := Used + [Ident.Name];
          Report('E2501', NodeRange(Ident), Format('Die Inline-Routine %s darf die lokale Routine %s nicht ' +
            'aufrufen (wie E2501).', [ARoutine.Name, Ident.Name]), Fix);
        end;
      end;
    end;
    // Lokale inline-Routine mit Zugriff auf Variablen der umgebenden Routine.
    Outer := ARoutine.Parent;
    Head := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if (Outer = nil) or (Outer.Kind <> TSyntaxKind.RoutineDecl) or (Head = nil) or
      not TRoutineHead.Read(Tokens, Head).HasDirective('inline') then
    begin
      Exit;
    end;
    Outside := OwnVariables(Outer);
    Own := NamesBelow(ARoutine);
    Used := nil;
    for Ident in IdentifiersIn(Body, False) do
    begin
      if MatchText(Ident.Name, Outside) and not MatchText(Ident.Name, Own) and not MatchText(Ident.Name, Used) then
      begin
        Used := Used + [Ident.Name];
        Report('E2449', NodeRange(Ident), Format('Die eingebettete lokale Routine %s darf nicht auf %s der ' +
          'umgebenden Routine zugreifen (wie E2449).', [ARoutine.Name, Ident.Name]), Fix);
      end;
    end;
  end;

  // inline-Routinen aus dem interface-Teil mit Symbolen des implementation-Teils: E2441.
  procedure CheckInlineLocalSymbols;
  var
    Symbols: TImplementationSymbols;
    Routine, Use, mDeclaration: TSyntaxNode;
    mUsable: TArray<string>;
  begin
    Symbols := TImplementationSymbols.Create(AContext);
    try
      mUsable := InlineUsableNames(Root.FindChild(TSyntaxKind.ImplementationSection));
      for Routine in Symbols.Routines do
      begin
        // Nur inline an der Deklaration im interface-Teil zählt: steht es allein am Rumpf, können andere Units
        // die Routine ohnehin nicht einbetten (HtmlViewer, TR5).
        mDeclaration := DeclarationOf(Routine);
        if (mDeclaration = nil) or not TRoutineHead.Read(Tokens, mDeclaration).HasDirective('inline') then
        begin
          Continue;
        end;
        if Pos('.', Routine.Name) > 0 then
        begin
          if Symbols.OwnerType(Routine) = nil then
          begin
            Continue;
          end;
        end
        else if (DeclarationOf(Routine) = nil) or (DeclarationOf(Routine).Parent = nil) or
          (DeclarationOf(Routine).Parent.Parent <> Symbols.InterfacePart) then
        begin
          Continue;
        end;
        for Use in Symbols.UsesIn(Routine, Symbols.OwnerType(Routine)) do
        begin
          if not MatchText(Use.Name, mUsable) then
          begin
            Report('E2441', NodeRange(Use), Format('Die Inline-Routine %s aus dem interface-Teil darf %s aus dem ' +
              'implementation-Teil nicht verwenden (wie E2441).', [Routine.Name, Use.Name]), nil);
          end;
        end;
      end;
    finally
      Symbols.Free;
    end;
  end;

  // threadvar: E2189, E2190, E2194.
  procedure CheckThreadVars(ASection: TSyntaxNode);
  var
    Outer: TSyntaxNode;
    Child: Integer;
    Decl: TSyntaxNode;
  begin
    Outer := ASection.Parent;
    while Outer <> nil do
    begin
      if Outer.Kind = TSyntaxKind.RoutineDecl then
      begin
        Report('E2189', KeywordRange(ASection), 'threadvar ist nur auf Unit-Ebene erlaubt, nicht lokal in einer ' +
          'Routine (wie E2189).', nil);
        Break;
      end;
      Outer := Outer.Parent;
    end;
    for Child := 0 to ASection.ChildCount - 1 do
    begin
      Decl := ASection[Child];
      if Decl.Kind <> TSyntaxKind.VarDecl then
      begin
        Continue;
      end;
      if HasTopLevelToken(Tokens, Decl.StartOffset, Decl.EndOffset, 'absolute') then
      begin
        Report('E2190', KeywordRange(Decl), 'threadvar-Variablen dürfen nicht absolute sein (wie E2190).', nil);
      end
      else if HasTopLevelToken(Tokens, Decl.StartOffset, Decl.EndOffset, '=') then
      begin
        Report('E2194', KeywordRange(Decl), 'threadvar-Variablen lassen sich nicht initialisieren (wie E2194).', nil);
      end;
    end;
  end;

  // Helfer als Typ einer Deklaration: E2527.
  procedure CheckHelperReference(AReference: TSyntaxNode);
  var
    Name: string;
  begin
    if (AReference.Parent = nil) or not (AReference.Parent.Kind in DeclarationParents) or
      (Pos('.', AReference.Name) > 0) or (AReference.FindChild(TSyntaxKind.GenericArgs) <> nil) then
    begin
      Exit;
    end;
    Name := AReference.Name;
    if Types.DeclaredKind(Name) = TSyntaxKind.HelperType then
    begin
      Report('E2527', NodeRange(AReference), Format('Der Helfer %s kann nicht als Typ in Deklarationen stehen ' +
        '(wie E2527).', [Name]), nil);
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Root := AContext.Tree.Root;
  Types := TFileTypes.Collect(Root);
  Disabled := TRuleOptions.Strings(AContext.Options, 'disabledChecks', nil);
  Paths := TConditionalBranches.Paths(Tokens);
  Ancestry := nil;
  Nodes := TList<TSyntaxNode>.Create;
  try
    Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if ANode.Kind in [TSyntaxKind.RecordType, TSyntaxKind.ClassType, TSyntaxKind.ObjectType,
          TSyntaxKind.HelperType, TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl, TSyntaxKind.VarSection,
          TSyntaxKind.TypeReference] then
        begin
          Nodes.Add(ANode);
        end;
      end);
    for Index := 0 to Nodes.Count - 1 do
    begin
      Node := Nodes[Index];
      case Node.Kind of
        TSyntaxKind.RecordType:
          begin
            CheckRecord(Node);
            if not IsLocalOrAnonymousRecord(Node) then
            begin
              CheckClassConstructors(Node);
            end;
          end;
        TSyntaxKind.ClassType, TSyntaxKind.ObjectType:
          CheckClassConstructors(Node);
        TSyntaxKind.HelperType:
          CheckHelper(Node);
        TSyntaxKind.RoutineHeader:
          CheckInlineHeader(Node);
        TSyntaxKind.RoutineDecl:
          CheckInlineBody(Node);
        TSyntaxKind.VarSection:
          if SameText(Node.Name, 'threadvar') then
          begin
            CheckThreadVars(Node);
          end;
        TSyntaxKind.TypeReference:
          CheckHelperReference(Node);
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
    CheckInlineLocalSymbols;
  finally
    Nodes.Free;
    Ancestry.Free;
  end;
end;

end.
