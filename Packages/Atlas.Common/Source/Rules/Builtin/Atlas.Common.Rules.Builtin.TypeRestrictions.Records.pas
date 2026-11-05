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
  Atlas.Common.Rules.Builtin.TypeRestrictions.Symbols,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTypeRestrictionsRecordsText = (Title, LocalMethods, LocalProperties, LocalClassMembers, LocalTypes, LocalConstants,
    ParameterlessCtor, DefaultCtor, Destructor_, StaticClassMethods, AddStatic, VirtualMethods, Directive,
    HelperVirtual, HelperDirective, HelperDestructor, HelperFields, HelperDescendants, HelperGeneric, ClassCtorParams,
    ClassCtorVirtual, ClassCtorMany, InlineVirtual, RemoveInline, InlineCtor, InlineOpenArray, InlineLocalCall,
    InlineLocalAccess, InlineAsm, InlineImplementation, ThreadvarLocal, ThreadvarAbsolute, ThreadvarInit,
    HelperAsType, RemoveDirective);

const
  cTexts: array[TTypeRestrictionsRecordsText] of TAtlasText = (
    (De: 'Sprachregel für Records, inline und Helfer verletzt';
     En: 'Language rule for records, inline and helpers violated'),
    (De: 'Lokale und anonyme Records dürfen keine Methoden deklarieren (wie E2433).';
     En: 'Local and anonymous records must not declare methods (like E2433).'),
    (De: 'Lokale und anonyme Records dürfen keine Properties deklarieren (wie E2434).';
     En: 'Local and anonymous records must not declare properties (like E2434).'),
    (De: 'Lokale und anonyme Records dürfen keine Klassenmitglieder deklarieren (wie E2435).';
     En: 'Local and anonymous records must not declare class members (like E2435).'),
    (De: 'Lokale und anonyme Records dürfen keine Typen deklarieren (wie E2436).';
     En: 'Local and anonymous records must not declare types (like E2436).'),
    (De: 'Lokale und anonyme Records dürfen keine Konstanten deklarieren (wie E2437).';
     En: 'Local and anonymous records must not declare constants (like E2437).'),
    (De: 'Records erlauben keine parameterlosen Konstruktoren (wie E2394).';
     En: 'Records do not allow parameterless constructors (like E2394).'),
    (De: 'Records erlauben keine Konstruktoren, die ohne Argumente aufrufbar sind; alle Parameter haben Vorgabewerte ' +
      '(wie E2471).';
     En: 'Records do not allow constructors that can be called without arguments; all parameters have default values ' +
      '(like E2471).'),
    (De: 'Records dürfen keinen Destruktor einführen (wie E2465).';
     En: 'Records must not introduce a destructor (like E2465).'),
    (De: 'Klassenmethoden in Records müssen static sein (wie E2398).';
     En: 'Class methods in records must be static (like E2398).'),
    (De: 'static ergänzen'; En: 'Add static'),
    (De: 'Records erlauben keine virtuellen Methoden (wie E2379).';
     En: 'Records do not allow virtual methods (like E2379).'),
    (De: 'Die Direktive %s ist in Records nicht erlaubt (wie E2463).';
     En: 'The directive %s is not allowed in records (like E2463).'),
    (De: 'Record-Helfer erlauben keine virtuellen Methoden (wie E2598).';
     En: 'Record helpers do not allow virtual methods (like E2598).'),
    (De: 'Die Direktive %s ist in Record-Helfern nicht erlaubt (wie E2475).';
     En: 'The directive %s is not allowed in record helpers (like E2475).'),
    (De: 'Class-Helfer dürfen keinen Destruktor einführen (wie E2295).';
     En: 'Class helpers must not introduce a destructor (like E2295).'),
    (De: 'Helfer dürfen keine Felder deklarieren (wie E2599).'; En: 'Helpers must not declare fields (like E2599).'),
    (De: 'Ein Class-Helfer, der von %s abstammt, kann nur Nachfahren von %s helfen (wie E2294).';
     En: 'A class helper descending from %s can only help descendants of %s (like E2294).'),
    (De: 'Helfer dürfen nicht im Kontext eines parametrisierten Typs deklariert werden (wie E2589).';
     En: 'Helpers must not be declared in the context of a parameterized type (like E2589).'),
    (De: 'Klassenkonstruktoren dürfen keine Parameter haben (wie E2360).';
     En: 'Class constructors must not have parameters (like E2360).'),
    (De: 'Klassenkonstruktoren dürfen nicht virtual, dynamic oder message sein (wie E2534).';
     En: 'Class constructors must not be virtual, dynamic or message (like E2534).'),
    (De: 'Mehrere Klassenkonstruktoren in %s: %s und %s (wie E2359).';
     En: 'Several class constructors in %s: %s and %s (like E2359).'),
    (De: 'Inline-Methoden dürfen nicht virtual oder dynamic sein (wie E2425).';
     En: 'Inline methods must not be virtual or dynamic (like E2425).'),
    (De: 'inline entfernen'; En: 'Remove inline'),
    (De: 'inline ist an Konstruktoren und Destruktoren nicht erlaubt (wie E2442).';
     En: 'inline is not allowed on constructors and destructors (like E2442).'),
    (De: 'Inline-Routinen dürfen keine offenen Array-Parameter haben (wie E2439).';
     En: 'Inline routines must not have open array parameters (like E2439).'),
    (De: 'Die Inline-Routine %s darf die lokale Routine %s nicht aufrufen (wie E2501).';
     En: 'The inline routine %s must not call the local routine %s (like E2501).'),
    (De: 'Die eingebettete lokale Routine %s darf nicht auf %s der umgebenden Routine zugreifen (wie E2449).';
     En: 'The inlined local routine %s must not access %s of the enclosing routine (like E2449).'),
    (De: 'Inline-Routinen dürfen keinen asm-Block haben (wie E2426).';
     En: 'Inline routines must not have an asm block (like E2426).'),
    (De: 'Die Inline-Routine %s aus dem interface-Teil darf %s aus dem implementation-Teil nicht verwenden (wie ' +
      'E2441).';
     En: 'The inline routine %s from the interface section must not use %s from the implementation section (like ' +
      'E2441).'),
    (De: 'threadvar ist nur auf Unit-Ebene erlaubt, nicht lokal in einer Routine (wie E2189).';
     En: 'threadvar is only allowed at unit level, not locally in a routine (like E2189).'),
    (De: 'threadvar-Variablen dürfen nicht absolute sein (wie E2190).';
     En: 'threadvar variables must not be absolute (like E2190).'),
    (De: 'threadvar-Variablen lassen sich nicht initialisieren (wie E2194).';
     En: 'threadvar variables cannot be initialized (like E2194).'),
    (De: 'Der Helfer %s kann nicht als Typ in Deklarationen stehen (wie E2527).';
     En: 'The helper %s cannot be used as a type in declarations (like E2527).'),
    (De: '%s entfernen'; En: 'Remove %s'));

{$SCOPEDENUMS OFF}

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

/// <summary>Steht AName in der Vorfahrenkette AChain?</summary>
function ChainContains(const AChain: TArray<TSymbolLocation>; const AName: string): Boolean;
var
  Location: TSymbolLocation;
begin
  for Location in AChain do
  begin
    if SameText(Location.Symbol.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TTypeRestrictionViolatedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(TypeRestrictionViolatedRuleId, TRuleSeverity.Error,
    cTexts[TTypeRestrictionsRecordsText.Title].Text);
end;

procedure TTypeRestrictionViolatedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Types: TFileTypes;
  Root: TSyntaxNode;
  Disabled, Paths: TArray<string>;
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
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

  /// <summary>Wo die Deklaration zum Rumpf ARoutine steht: Typ der Methode bzw. interface-Teil; nil ohne.
  /// </summary>
  function DeclarationHolder(ARoutine: TSyntaxNode): TSyntaxNode;
  var
    Decl: TSyntaxNode;
  begin
    Result := nil;
    if Pos('.', ARoutine.Name) > 0 then
    begin
      Decl := FindStructDecl(Root, LastPart(Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1)));
      if Decl <> nil then
      begin
        Result := TypeOfDecl(Decl);
      end;
    end
    else if (ARoutine.Parent <> nil) and (ARoutine.Parent.Kind = TSyntaxKind.ImplementationSection) then
    begin
      Result := Root.FindChild(TSyntaxKind.InterfaceSection);
    end;
  end;

  /// <summary>Kopf der Routine AName aus dem Kind ANode eines Halters (Kopf oder Routine), nil sonst.</summary>
  function HeaderCandidate(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
  begin
    Result := ANode;
    if Result.Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := Result.FindChild(TSyntaxKind.RoutineHeader);
    end;
    if (Result <> nil) and ((Result.Kind <> TSyntaxKind.RoutineHeader) or not SameText(Result.Name, AName)) then
    begin
      Result := nil;
    end;
  end;

  /// <summary>Kopf AName unter AHolder mit der Parameterliste AParams; ohne Parameter der einzige Kopf dieses
  /// Namens. nil ohne bzw. bei mehrdeutigen.</summary>
  function MatchingHeader(AHolder: TSyntaxNode; const AName, AParams: string): TSyntaxNode;
  var
    Candidate: TSyntaxNode;
    Child, Found: Integer;
  begin
    Result := nil;
    Found := 0;
    for Child := 0 to AHolder.ChildCount - 1 do
    begin
      Candidate := HeaderCandidate(AHolder[Child], AName);
      if Candidate = nil then
      begin
        Continue;
      end;
      Inc(Found);
      if Squeezed(AContext.Text, Candidate.FindChild(TSyntaxKind.Parameters)) = AParams then
      begin
        Exit(Candidate);
      end;
      if (AParams = '') and (Found = 1) then
      begin
        Result := Candidate;
      end;
    end;
    if Found > 1 then
    begin
      Result := nil;
    end;
  end;

  /// <summary>Deklaration (Kopf in Typ bzw. interface-Teil) zum Rumpf ARoutine, nil ohne.</summary>
  function DeclarationOf(ARoutine: TSyntaxNode): TSyntaxNode;
  var
    Header, Holder: TSyntaxNode;
  begin
    Result := nil;
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    Holder := nil;
    if Header <> nil then
    begin
      Holder := DeclarationHolder(ARoutine);
    end;
    if Holder <> nil then
    begin
      Result := MatchingHeader(Holder, LastPart(ARoutine.Name), Squeezed(AContext.Text,
        Header.FindChild(TSyntaxKind.Parameters)));
    end;
  end;

  /// <summary>Meldet die erste virtuelle (AVirtualCode) bzw. sonst verbotene Direktive (AOtherCode, AOtherFormat
  /// mit dem Namen der Direktive) am Kopf, mit Korrektur.</summary>
  procedure CheckForbiddenDirectives(const AHead: TRoutineHead; const AVirtualCode, AVirtualMessage, AOtherCode,
    AOtherFormat: string);
  var
    Directive: TSyntaxNode;
  begin
    Directive := FirstDirective(AHead, RecordVirtualDirectives);
    if Directive <> nil then
    begin
      Report(AVirtualCode, NodeRange(Directive), AVirtualMessage, RemoveFix(AHead, RecordForbiddenDirectives,
        cTexts[TTypeRestrictionsRecordsText.RemoveDirective].Fmt([Directive.Name])));
      Exit;
    end;
    Directive := FirstDirective(AHead, RecordForbiddenDirectives);
    if Directive <> nil then
    begin
      Report(AOtherCode, NodeRange(Directive), Format(AOtherFormat, [Directive.Name]), RemoveFix(AHead,
        RecordForbiddenDirectives, cTexts[TTypeRestrictionsRecordsText.RemoveDirective].Fmt([Directive.Name])));
    end;
  end;

  // Lokale und anonyme Records: E2433–E2437.
  procedure CheckLocalRecord(ARecord: TSyntaxNode);
  var
    Child: Integer;
    Member: TSyntaxNode;
  begin
    for Child := 0 to ARecord.ChildCount - 1 do
    begin
      Member := ARecord[Child];
      case Member.Kind of
        TSyntaxKind.RoutineHeader:
          Report('E2433', NameRange(Member), cTexts[TTypeRestrictionsRecordsText.LocalMethods].Text, nil);
        TSyntaxKind.PropertyDecl:
          Report('E2434', KeywordRange(Member), cTexts[TTypeRestrictionsRecordsText.LocalProperties].Text, nil);
        TSyntaxKind.VarSection:
          if PrecededByClass(Tokens, Member) then
          begin
            Report('E2435', KeywordRange(Member), cTexts[TTypeRestrictionsRecordsText.LocalClassMembers].Text, nil);
          end;
        TSyntaxKind.TypeSection:
          Report('E2436', KeywordRange(Member), cTexts[TTypeRestrictionsRecordsText.LocalTypes].Text, nil);
        TSyntaxKind.ConstSection:
          Report('E2437', KeywordRange(Member), cTexts[TTypeRestrictionsRecordsText.LocalConstants].Text, nil);
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
  end;

  // Konstruktoren, Destruktoren und Klassenmethoden in Records: E2394, E2471, E2465, E2398.
  procedure CheckRecordMethodKind(const AHead: TRoutineHead; AMember: TSyntaxNode);
  begin
    if AHead.Keyword = 'constructor' then
    begin
      if AHead.ParameterCount = 0 then
      begin
        Report('E2394', NameRange(AMember), cTexts[TTypeRestrictionsRecordsText.ParameterlessCtor].Text, nil);
      end
      else if AllParametersDefaulted(Tokens, AHead) then
      begin
        Report('E2471', NameRange(AMember), cTexts[TTypeRestrictionsRecordsText.DefaultCtor].Text, nil);
      end;
    end
    else if AHead.Keyword = 'destructor' then
    begin
      Report('E2465', NameRange(AMember), cTexts[TTypeRestrictionsRecordsText.Destructor_].Text, nil);
    end
    else if AHead.IsClass and MatchText(AHead.Keyword, ['procedure', 'function']) and
      not AHead.HasDirective('static') then
    begin
      Report('E2398', NameRange(AMember), cTexts[TTypeRestrictionsRecordsText.StaticClassMethods].Text,
        [TRuleFix.Create(cTexts[TTypeRestrictionsRecordsText.AddStatic].Text,
          [TRuleEdit.Create(TTextRange.Create(AMember.EndPos, AMember.EndPos),
        ' static;')])]);
    end;
  end;

  // Methoden in Records: E2379, E2463 und CheckRecordMethodKind.
  procedure CheckRecordMethod(AMember: TSyntaxNode);
  var
    Head: TRoutineHead;
  begin
    Head := TRoutineHead.Read(Tokens, AMember);
    if (Head.Keyword = 'operator') or (Head.IsClass and MatchText(Head.Keyword, ['constructor', 'destructor'])) then
    begin
      Exit;
    end;
    CheckForbiddenDirectives(Head, 'E2379', cTexts[TTypeRestrictionsRecordsText.VirtualMethods].Text, 'E2463',
      cTexts[TTypeRestrictionsRecordsText.Directive].Text);
    CheckRecordMethodKind(Head, AMember);
  end;

  procedure CheckRecord(ARecord: TSyntaxNode);
  var
    Child: Integer;
  begin
    if IsLocalOrAnonymousRecord(ARecord) then
    begin
      CheckLocalRecord(ARecord);
      Exit;
    end;
    for Child := 0 to ARecord.ChildCount - 1 do
    begin
      if ARecord[Child].Kind = TSyntaxKind.RoutineHeader then
      begin
        CheckRecordMethod(ARecord[Child]);
      end;
    end;
  end;

  /// <summary>Stammt der Typ AName sicher nicht von AAncestor ab? False, wenn die Kette nicht bekannt ist.</summary>
  function CertainlyNotDescendant(const AName, AAncestor: string): Boolean;
  var
    Chain: TArray<TSymbolLocation>;
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
    Result := Complete and not ChainContains(Chain, AAncestor);
    Result := Result and not (ObjectMissing and SameText(AAncestor, 'TObject'));
  end;

  // Methoden in Helfern: E2598, E2475, E2295.
  procedure CheckHelperMethod(AMember: TSyntaxNode; AIsRecordHelper: Boolean);
  var
    Head: TRoutineHead;
  begin
    Head := TRoutineHead.Read(Tokens, AMember);
    if AIsRecordHelper then
    begin
      CheckForbiddenDirectives(Head, 'E2598', cTexts[TTypeRestrictionsRecordsText.HelperVirtual].Text,
        'E2475', cTexts[TTypeRestrictionsRecordsText.HelperDirective].Text);
    end
    else if (Head.Keyword = 'destructor') and not Head.IsClass then
    begin
      Report('E2295', NameRange(AMember), cTexts[TTypeRestrictionsRecordsText.HelperDestructor].Text, nil);
    end;
  end;

  // Mitglieder von Helfern: Felder (E2599) und Methoden.
  procedure CheckHelperMember(AMember: TSyntaxNode; AIsRecordHelper: Boolean);
  var
    Inner: Integer;
  begin
    case AMember.Kind of
      TSyntaxKind.Field:
        Report('E2599', KeywordRange(AMember), cTexts[TTypeRestrictionsRecordsText.HelperFields].Text, nil);
      TSyntaxKind.VarSection:
        if not PrecededByClass(Tokens, AMember) then
        begin
          for Inner := 0 to AMember.ChildCount - 1 do
          begin
            Report('E2599', KeywordRange(AMember[Inner]), cTexts[TTypeRestrictionsRecordsText.HelperFields].Text,
              nil);
          end;
        end;
      TSyntaxKind.RoutineHeader:
        CheckHelperMethod(AMember, AIsRecordHelper);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  // Vorfahr-Helfer: nur Nachfahren seines Typs (E2294).
  procedure CheckAncestorHelper(ATarget, AAncestorRef: TSyntaxNode);
  var
    AncestorName, Wanted: string;
    TypeIndex: Integer;
    AncestorTarget, Dummy: TSyntaxNode;
  begin
    AncestorName := BareTypeName(AAncestorRef.Name);
    TypeIndex := Types.IndexOf(AncestorName);
    if (TypeIndex < 0) or (Types.DeclaredKind(AncestorName) <> TSyntaxKind.HelperType) then
    begin
      Exit;
    end;
    AncestorTarget := HelperTarget(Types.Types[TypeIndex], Dummy);
    if AncestorTarget = nil then
    begin
      Exit;
    end;
    Wanted := BareTypeName(AncestorTarget.Name);
    if CertainlyNotDescendant(BareTypeName(ATarget.Name), Wanted) then
    begin
      Report('E2294', NodeRange(ATarget), cTexts[TTypeRestrictionsRecordsText.HelperDescendants].Fmt([AncestorName,
        Wanted]), nil);
    end;
  end;

  // Helfer im Kontext eines parametrisierten Typs (E2589).
  procedure CheckHelperContext(AHelper: TSyntaxNode);
  var
    Outer: TSyntaxNode;
  begin
    Outer := AHelper.Parent;
    if Outer <> nil then
    begin
      Outer := Outer.Parent;
    end;
    while Outer <> nil do
    begin
      if (Outer.Kind = TSyntaxKind.TypeDecl) and (Outer.FindChild(TSyntaxKind.GenericParams) <> nil) then
      begin
        Report('E2589', KeywordRange(AHelper.Parent), cTexts[TTypeRestrictionsRecordsText.HelperGeneric].Text, nil);
        Break;
      end;
      Outer := Outer.Parent;
    end;
  end;

  // Helfer: E2599, E2598, E2475, E2295, E2294, E2589. Klassenkonstruktoren im Class-Helfer (E2358) und
  // Helfer-Konstruktoren ohne Konstruktoraufruf zuerst (E2296) übersetzt dcc (Skia4Delphi MobileBars,
  // TSkPixmapHelper.Create, FMX.Skia TSkBitmapHelper; TR6, TR7, #1328); die Prüfungen sind entfallen.
  procedure CheckHelper(AHelper: TSyntaxNode);
  var
    Child: Integer;
    Target, AncestorRef: TSyntaxNode;
    IsRecordHelper: Boolean;
  begin
    IsRecordHelper := SameText(AHelper.Name, 'record');
    Target := HelperTarget(AHelper, AncestorRef);
    for Child := 0 to AHelper.ChildCount - 1 do
    begin
      CheckHelperMember(AHelper[Child], IsRecordHelper);
    end;
    if not IsRecordHelper and (AncestorRef <> nil) and (Target <> nil) and (BareTypeName(Target.Name) <> '') then
    begin
      CheckAncestorHelper(Target, AncestorRef);
    end;
    CheckHelperContext(AHelper);
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
        Report('E2360', NameRange(Head.Header), cTexts[TTypeRestrictionsRecordsText.ClassCtorParams].Text, nil);
      end;
      Directive := FirstDirective(Head, ClassConstructorDirectives);
      if Directive <> nil then
      begin
        Report('E2534', NodeRange(Directive), cTexts[TTypeRestrictionsRecordsText.ClassCtorVirtual].Text,
          RemoveFix(Head, ClassConstructorDirectives,
            cTexts[TTypeRestrictionsRecordsText.RemoveDirective].Fmt([Directive.Name])));
      end;
      if First = nil then
      begin
        First := Head.Header;
      end
      else if not TConditionalBranches.Exclusive(
        TConditionalBranches.PathAt(Paths, TRoutineBody.TokenAt(Tokens, First.StartOffset)),
        TConditionalBranches.PathAt(Paths, TRoutineBody.TokenAt(Tokens, Head.Header.StartOffset))) then
      begin
        Report('E2359', NameRange(Head.Header), cTexts[TTypeRestrictionsRecordsText.ClassCtorMany].Fmt(
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
      Report('E2425', NodeRange(InlineHead), cTexts[TTypeRestrictionsRecordsText.InlineVirtual].Text,
        RemoveFix(Head, ['inline'], cTexts[TTypeRestrictionsRecordsText.RemoveInline].Text));
    end
    else if MatchText(Head.Keyword, ['constructor', 'destructor']) then
    begin
      Report('E2442', NodeRange(InlineHead), cTexts[TTypeRestrictionsRecordsText.InlineCtor].Text,
        RemoveFix(Head, ['inline'], cTexts[TTypeRestrictionsRecordsText.RemoveInline].Text));
    end;
    if HasOpenArrayParameter(Head) then
    begin
      Report('E2439', NodeRange(InlineHead), cTexts[TTypeRestrictionsRecordsText.InlineOpenArray].Text,
        RemoveFix(Head, ['inline'], cTexts[TTypeRestrictionsRecordsText.RemoveInline].Text));
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

  // Aufruf eigener lokaler Routinen aus einer inline-Routine: E2501.
  procedure CheckNestedCalls(ARoutine, ABody: TSyntaxNode; const AFix: TArray<TRuleFix>);
  var
    Nested, Used: TArray<string>;
    Child: Integer;
    Ident: TSyntaxNode;
  begin
    Nested := nil;
    for Child := 0 to ARoutine.ChildCount - 1 do
    begin
      if ARoutine[Child].Kind = TSyntaxKind.RoutineDecl then
      begin
        Nested := Nested + [ARoutine[Child].Name];
      end;
    end;
    if Nested = nil then
    begin
      Exit;
    end;
    Used := nil;
    for Ident in IdentifiersIn(ABody, True) do
    begin
      if MatchText(Ident.Name, Nested) and not MatchText(Ident.Name, Used) then
      begin
        Used := Used + [Ident.Name];
        Report('E2501', NodeRange(Ident), cTexts[TTypeRestrictionsRecordsText.InlineLocalCall].Fmt([ARoutine.Name,
          Ident.Name]), AFix);
      end;
    end;
  end;

  /// <summary>Ist ARoutine eine lokale Routine mit eigenem inline-Kopf?</summary>
  function IsLocalInline(ARoutine: TSyntaxNode): Boolean;
  var
    Head: TSyntaxNode;
  begin
    Head := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    Result := (ARoutine.Parent <> nil) and (ARoutine.Parent.Kind = TSyntaxKind.RoutineDecl) and (Head <> nil);
    Result := Result and TRoutineHead.Read(Tokens, Head).HasDirective('inline');
  end;

  // Lokale inline-Routine mit Zugriff auf Variablen der umgebenden Routine: E2449.
  procedure CheckOuterAccess(ARoutine, ABody: TSyntaxNode; const AFix: TArray<TRuleFix>);
  var
    Outside, Own, Used: TArray<string>;
    Ident: TSyntaxNode;
  begin
    Outside := OwnVariables(ARoutine.Parent);
    Own := NamesBelow(ARoutine);
    Used := nil;
    for Ident in IdentifiersIn(ABody, False) do
    begin
      if MatchText(Ident.Name, Outside) and not MatchText(Ident.Name, Own) and not MatchText(Ident.Name, Used) then
      begin
        Used := Used + [Ident.Name];
        Report('E2449', NodeRange(Ident), cTexts[TTypeRestrictionsRecordsText.InlineLocalAccess].Fmt([ARoutine.Name,
          Ident.Name]), AFix);
      end;
    end;
  end;

  // Rümpfe von inline-Routinen: E2426, E2501, E2449.
  procedure CheckInlineBody(ARoutine: TSyntaxNode);
  var
    InlineHead, Body: TSyntaxNode;
    Head: TRoutineHead;
    Fix: TArray<TRuleFix>;
  begin
    InlineHead := InlineHeader(ARoutine);
    if InlineHead = nil then
    begin
      Exit;
    end;
    Head := TRoutineHead.Read(Tokens, InlineHead);
    Fix := RemoveFix(Head, ['inline'], cTexts[TTypeRestrictionsRecordsText.RemoveInline].Text);
    if ARoutine.FindChild(TSyntaxKind.AsmBlock) <> nil then
    begin
      Report('E2426', NodeRange(Head.Directive('inline')), cTexts[TTypeRestrictionsRecordsText.InlineAsm].Text, Fix);
    end;
    Body := ARoutine.FindChild(TSyntaxKind.Block);
    if Body = nil then
    begin
      Exit;
    end;
    CheckNestedCalls(ARoutine, Body, Fix);
    if IsLocalInline(ARoutine) then
    begin
      CheckOuterAccess(ARoutine, Body, Fix);
    end;
  end;

  /// <summary>Ist ARoutine an ihrer Deklaration im interface-Teil inline? Nur das zählt: steht es allein am Rumpf,
  /// können andere Units die Routine ohnehin nicht einbetten (HtmlViewer, TR5).</summary>
  function InterfaceInline(ASymbols: TImplementationSymbols; ARoutine: TSyntaxNode): Boolean;
  var
    mDeclaration: TSyntaxNode;
  begin
    mDeclaration := DeclarationOf(ARoutine);
    Result := (mDeclaration <> nil) and TRoutineHead.Read(Tokens, mDeclaration).HasDirective('inline');
    if not Result then
    begin
      Exit;
    end;
    if Pos('.', ARoutine.Name) > 0 then
    begin
      Result := ASymbols.OwnerType(ARoutine) <> nil;
    end
    else
    begin
      Result := (mDeclaration.Parent <> nil) and (mDeclaration.Parent.Parent = ASymbols.InterfacePart);
    end;
  end;

  // inline-Routinen aus dem interface-Teil mit Symbolen des implementation-Teils: E2441.
  procedure CheckInlineLocalSymbols;
  var
    Symbols: TImplementationSymbols;
    Routine, Use: TSyntaxNode;
    mUsable: TArray<string>;
  begin
    Symbols := TImplementationSymbols.Create(AContext);
    try
      mUsable := InlineUsableNames(Root.FindChild(TSyntaxKind.ImplementationSection));
      for Routine in Symbols.Routines do
      begin
        if not InterfaceInline(Symbols, Routine) then
        begin
          Continue;
        end;
        for Use in Symbols.UsesIn(Routine, Symbols.OwnerType(Routine)) do
        begin
          if not MatchText(Use.Name, mUsable) then
          begin
            Report('E2441', NodeRange(Use), cTexts[TTypeRestrictionsRecordsText.InlineImplementation].Fmt([Routine.Name,
              Use.Name]), nil);
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
        Report('E2189', KeywordRange(ASection), cTexts[TTypeRestrictionsRecordsText.ThreadvarLocal].Text, nil);
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
        Report('E2190', KeywordRange(Decl), cTexts[TTypeRestrictionsRecordsText.ThreadvarAbsolute].Text, nil);
      end
      else if HasTopLevelToken(Tokens, Decl.StartOffset, Decl.EndOffset, '=') then
      begin
        Report('E2194', KeywordRange(Decl), cTexts[TTypeRestrictionsRecordsText.ThreadvarInit].Text, nil);
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
      Report('E2527', NodeRange(AReference), cTexts[TTypeRestrictionsRecordsText.HelperAsType].Fmt([Name]), nil);
    end;
  end;

  procedure CheckNode(ANode: TSyntaxNode);
  begin
    case ANode.Kind of
      TSyntaxKind.RecordType:
        begin
          CheckRecord(ANode);
          if not IsLocalOrAnonymousRecord(ANode) then
          begin
            CheckClassConstructors(ANode);
          end;
        end;
      TSyntaxKind.ClassType, TSyntaxKind.ObjectType:
        CheckClassConstructors(ANode);
      TSyntaxKind.HelperType:
        CheckHelper(ANode);
      TSyntaxKind.RoutineHeader:
        CheckInlineHeader(ANode);
      TSyntaxKind.RoutineDecl:
        CheckInlineBody(ANode);
      TSyntaxKind.VarSection:
        if SameText(ANode.Name, 'threadvar') then
        begin
          CheckThreadVars(ANode);
        end;
      TSyntaxKind.TypeReference:
        CheckHelperReference(ANode);
    else
      // Übrige Werte bewusst ohne Wirkung.
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
    for Node in Nodes do
    begin
      CheckNode(Node);
    end;
    CheckInlineLocalSymbols;
  finally
    Nodes.Free;
    Ancestry.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TypeRestrictions.Records', cTexts);

end.
