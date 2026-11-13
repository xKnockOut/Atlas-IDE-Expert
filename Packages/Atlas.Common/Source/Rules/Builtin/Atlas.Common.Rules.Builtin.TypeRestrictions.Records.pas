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
  cTypeRestrictionViolatedRuleId = 'type-restriction-violated';

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
  Atlas.Common.Rules.Builtin.TypeRestrictions.Heads,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Symbols,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Pascal.TokenCursor;

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
  cRecordForbiddenDirectives: array[0..6] of string = ('virtual', 'dynamic', 'override', 'abstract', 'reintroduce',
    'message', 'final');
  // Davon die, die eine Methode virtuell machen (E2379, E2598).
  cRecordVirtualDirectives: array[0..1] of string = ('virtual', 'dynamic');
  // Direktiven, die ein Klassenkonstruktor nicht tragen darf (E2534).
  cClassConstructorDirectives: array[0..2] of string = ('virtual', 'dynamic', 'message');
  // Elterntypen eines Typverweises, die eine Deklaration mit diesem Typ sind (E2527).
  cDeclarationParents = [TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.RoutineHeader,
    TSyntaxKind.PropertyDecl, TSyntaxKind.ConstDecl, TSyntaxKind.InlineVar, TSyntaxKind.ArrayType,
    TSyntaxKind.PointerType];

/// <summary>Steht vor ANode das Wort class (class var, class property)?</summary>
function PrecededByClass(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := PreviousCode(ATokens, TRoutineBody.TokenAt(ATokens, ANode.StartOffset));
  Result := (mIndex >= 0) and (mIndex < Length(ATokens)) and SameText(ATokens[mIndex].Text, 'class');
end;

/// <summary>Gibt es zwischen AFrom und ATo (Offsets) auf oberster Klammerebene das Token AText?</summary>
function HasTopLevelToken(const ATokens: TArray<TPascalToken>; AFrom, ATo: Integer; const AText: string): Boolean;
var
  mIndex, mDepth: Integer;
begin
  Result := False;
  mDepth := 0;
  mIndex := TRoutineBody.TokenAt(ATokens, AFrom);
  while (mIndex >= 0) and (mIndex < Length(ATokens)) and (ATokens[mIndex].Offset < ATo) do
  begin
    if ATokens[mIndex].IsSymbol('(') or ATokens[mIndex].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if ATokens[mIndex].IsSymbol(')') or ATokens[mIndex].IsSymbol(']') then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and not (ATokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) and
      SameText(ATokens[mIndex].Text, AText) then
    begin
      Exit(True);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Edit, das die Direktive ADirective samt Semikolon und dem Abstand davor entfernt.</summary>
function DirectiveRemoval(const ATokens: TArray<TPascalToken>; ADirective: TSyntaxNode; out AEdit: TRuleEdit):
  Boolean;
var
  mIndex, mBefore, mAfter: Integer;
begin
  Result := False;
  mIndex := TRoutineBody.TokenAt(ATokens, ADirective.StartOffset);
  mBefore := PreviousCode(ATokens, mIndex);
  if (mIndex < 0) or (mIndex >= Length(ATokens)) or (mBefore < 0) then
  begin
    Exit;
  end;
  mAfter := mIndex;
  while (mAfter >= 0) and (mAfter < Length(ATokens)) and not ATokens[mAfter].IsSymbol(';') do
  begin
    mAfter := TRoutineBody.NextToken(ATokens, mAfter);
  end;
  if (mAfter < 0) or (mAfter >= Length(ATokens)) then
  begin
    Exit;
  end;
  AEdit := TRuleEdit.Create(TTextRange.Create(ATokens[mBefore].EndPos, ATokens[mAfter].EndPos), '');
  Result := True;
end;

/// <summary>Zielt der Helfer AHelper (HelperType) auf diesen Typverweis; bei class helper (TBasis) for T ist es
/// der zweite.</summary>
function HelperTarget(AHelper: TSyntaxNode; out AAncestor: TSyntaxNode): TSyntaxNode;
var
  mCount: Integer;
begin
  mCount := 0;
  while (mCount < AHelper.ChildCount) and (AHelper[mCount].Kind = TSyntaxKind.TypeReference) do
  begin
    Inc(mCount);
  end;
  AAncestor := nil;
  Result := nil;
  if mCount >= 2 then
  begin
    AAncestor := AHelper[0];
    Result := AHelper[1];
  end
  else if mCount = 1 then
  begin
    Result := AHelper[0];
  end;
end;

/// <summary>Hat jeder Parameter des Kopfs einen Vorgabewert (und gibt es mindestens einen)?</summary>
function AllParametersDefaulted(const ATokens: TArray<TPascalToken>; const AHead: TRoutineHead): Boolean;
var
  mParameter: TSyntaxNode;
begin
  Result := AHead.Parameters <> nil;
  for mParameter in AHead.Parameters do
  begin
    if not HasTopLevelToken(ATokens, mParameter.StartOffset, mParameter.EndOffset, '=') then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Hat der Kopf einen offenen Array-Parameter (array of T, array of const)?</summary>
function HasOpenArrayParameter(const AHead: TRoutineHead): Boolean;
var
  mParameter: TSyntaxNode;
begin
  for mParameter in AHead.Parameters do
  begin
    if mParameter.FindChild(TSyntaxKind.ArrayType) <> nil then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Ist der Record ARecord lokal (in einer Routine) oder anonym (ohne eigene Typdeklaration)?</summary>
function IsLocalOrAnonymousRecord(ARecord: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  if (ARecord.Parent = nil) or (ARecord.Parent.Kind <> TSyntaxKind.TypeDecl) then
  begin
    Exit(True);
  end;
  mNode := ARecord.Parent.Parent;
  while mNode <> nil do
  begin
    if mNode.Kind = TSyntaxKind.RoutineDecl then
    begin
      Exit(True);
    end;
    mNode := mNode.Parent;
  end;
  Result := False;
end;

/// <summary>Steht AName in der Vorfahrenkette AChain?</summary>
function ChainContains(const AChain: TArray<TSymbolLocation>; const AName: string): Boolean;
var
  mLocation: TSymbolLocation;
begin
  for mLocation in AChain do
  begin
    if SameText(mLocation.Symbol.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TTypeRestrictionViolatedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cTypeRestrictionViolatedRuleId, TRuleSeverity.Error,
    cTexts[TTypeRestrictionsRecordsText.Title].Text);
end;

procedure TTypeRestrictionViolatedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mTypes: TFileTypes;
  mRoot: TSyntaxNode;
  mDisabled, mPaths: TArray<string>;
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mAncestry: TAncestry;

  procedure Report(const ACode: string; const ARange: TTextRange; const AMessage: string;
    const AFixes: TArray<TRuleFix>);
  begin
    if not MatchText(ACode, mDisabled) then
    begin
      AReport.Add(ARange, AMessage, TRuleConfidence.High, AFixes);
    end;
  end;

  function NameRange(AHeader: TSyntaxNode): TTextRange;
  var
    mAt: Integer;
  begin
    mAt := NameToken(mTokens, AHeader);
    if mAt >= 0 then
    begin
      Result := TokenRange(mTokens[mAt]);
    end
    else
    begin
      Result := NodeRange(AHeader);
    end;
  end;

  function KeywordRange(ANode: TSyntaxNode): TTextRange;
  var
    mAt: Integer;
  begin
    mAt := TRoutineBody.TokenAt(mTokens, ANode.StartOffset);
    if (mAt >= 0) and (mAt < Length(mTokens)) then
    begin
      Result := TokenRange(mTokens[mAt]);
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
    mEdits: TArray<TRuleEdit>;
    mEdit: TRuleEdit;
    mChild: Integer;
  begin
    mEdits := nil;
    for mChild := 0 to AHead.Header.ChildCount - 1 do
    begin
      if (AHead.Header[mChild].Kind = TSyntaxKind.Directive) and MatchText(AHead.Header[mChild].Name, ANames) and
        DirectiveRemoval(mTokens, AHead.Header[mChild], mEdit) then
      begin
        mEdits := mEdits + [mEdit];
      end;
    end;
    Result := nil;
    if mEdits <> nil then
    begin
      Result := [TRuleFix.Create(ATitle, mEdits)];
    end;
  end;

  /// <summary>Erste Direktive des Kopfs aus ANames oder nil.</summary>
  function FirstDirective(const AHead: TRoutineHead; const ANames: array of string): TSyntaxNode;
  var
    mChild: Integer;
  begin
    for mChild := 0 to AHead.Header.ChildCount - 1 do
    begin
      if (AHead.Header[mChild].Kind = TSyntaxKind.Directive) and MatchText(AHead.Header[mChild].Name, ANames) then
      begin
        Exit(AHead.Header[mChild]);
      end;
    end;
    Result := nil;
  end;

  /// <summary>Wo die Deklaration zum Rumpf ARoutine steht: Typ der Methode bzw. interface-Teil; nil ohne.
  /// </summary>
  function DeclarationHolder(ARoutine: TSyntaxNode): TSyntaxNode;
  var
    mDecl: TSyntaxNode;
  begin
    Result := nil;
    if Pos('.', ARoutine.Name) > 0 then
    begin
      mDecl := FindStructDecl(mRoot, LastPart(Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1)));
      if mDecl <> nil then
      begin
        Result := TypeOfDecl(mDecl);
      end;
    end
    else if (ARoutine.Parent <> nil) and (ARoutine.Parent.Kind = TSyntaxKind.ImplementationSection) then
    begin
      Result := mRoot.FindChild(TSyntaxKind.InterfaceSection);
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
    mCandidate: TSyntaxNode;
    mChild, mFound: Integer;
  begin
    Result := nil;
    mFound := 0;
    for mChild := 0 to AHolder.ChildCount - 1 do
    begin
      mCandidate := HeaderCandidate(AHolder[mChild], AName);
      if mCandidate = nil then
      begin
        Continue;
      end;
      Inc(mFound);
      if Squeezed(AContext.Text, mCandidate.FindChild(TSyntaxKind.Parameters)) = AParams then
      begin
        Exit(mCandidate);
      end;
      if (AParams = '') and (mFound = 1) then
      begin
        Result := mCandidate;
      end;
    end;
    if mFound > 1 then
    begin
      Result := nil;
    end;
  end;

  /// <summary>Deklaration (Kopf in Typ bzw. interface-Teil) zum Rumpf ARoutine, nil ohne.</summary>
  function DeclarationOf(ARoutine: TSyntaxNode): TSyntaxNode;
  var
    mHeader, mHolder: TSyntaxNode;
  begin
    Result := nil;
    mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    mHolder := nil;
    if mHeader <> nil then
    begin
      mHolder := DeclarationHolder(ARoutine);
    end;
    if mHolder <> nil then
    begin
      Result := MatchingHeader(mHolder, LastPart(ARoutine.Name), Squeezed(AContext.Text,
        mHeader.FindChild(TSyntaxKind.Parameters)));
    end;
  end;

  /// <summary>Meldet die erste virtuelle (AVirtualCode) bzw. sonst verbotene Direktive (AOtherCode, AOtherFormat
  /// mit dem Namen der Direktive) am Kopf, mit Korrektur.</summary>
  procedure CheckForbiddenDirectives(const AHead: TRoutineHead; const AVirtualCode, AVirtualMessage, AOtherCode,
    AOtherFormat: string);
  var
    mDirective: TSyntaxNode;
  begin
    mDirective := FirstDirective(AHead, cRecordVirtualDirectives);
    if mDirective <> nil then
    begin
      Report(AVirtualCode, NodeRange(mDirective), AVirtualMessage, RemoveFix(AHead, cRecordForbiddenDirectives,
        cTexts[TTypeRestrictionsRecordsText.RemoveDirective].Fmt([mDirective.Name])));
      Exit;
    end;
    mDirective := FirstDirective(AHead, cRecordForbiddenDirectives);
    if mDirective <> nil then
    begin
      Report(AOtherCode, NodeRange(mDirective), Format(AOtherFormat, [mDirective.Name]), RemoveFix(AHead,
        cRecordForbiddenDirectives, cTexts[TTypeRestrictionsRecordsText.RemoveDirective].Fmt([mDirective.Name])));
    end;
  end;

  // Lokale und anonyme Records: E2433–E2437.
  procedure CheckLocalRecord(ARecord: TSyntaxNode);
  var
    mChild: Integer;
    mMember: TSyntaxNode;
  begin
    for mChild := 0 to ARecord.ChildCount - 1 do
    begin
      mMember := ARecord[mChild];
      case mMember.Kind of
        TSyntaxKind.RoutineHeader:
          Report('E2433', NameRange(mMember), cTexts[TTypeRestrictionsRecordsText.LocalMethods].Text, nil);
        TSyntaxKind.PropertyDecl:
          Report('E2434', KeywordRange(mMember), cTexts[TTypeRestrictionsRecordsText.LocalProperties].Text, nil);
        TSyntaxKind.VarSection:
          if PrecededByClass(mTokens, mMember) then
          begin
            Report('E2435', KeywordRange(mMember), cTexts[TTypeRestrictionsRecordsText.LocalClassMembers].Text, nil);
          end;
        TSyntaxKind.TypeSection:
          Report('E2436', KeywordRange(mMember), cTexts[TTypeRestrictionsRecordsText.LocalTypes].Text, nil);
        TSyntaxKind.ConstSection:
          Report('E2437', KeywordRange(mMember), cTexts[TTypeRestrictionsRecordsText.LocalConstants].Text, nil);
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
      else if AllParametersDefaulted(mTokens, AHead) then
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
    mHead: TRoutineHead;
  begin
    mHead := TRoutineHead.Read(mTokens, AMember);
    if (mHead.Keyword = 'operator') or (mHead.IsClass and MatchText(mHead.Keyword, ['constructor', 'destructor'])) then
    begin
      Exit;
    end;
    CheckForbiddenDirectives(mHead, 'E2379', cTexts[TTypeRestrictionsRecordsText.VirtualMethods].Text, 'E2463',
      cTexts[TTypeRestrictionsRecordsText.Directive].Text);
    CheckRecordMethodKind(mHead, AMember);
  end;

  procedure CheckRecord(ARecord: TSyntaxNode);
  var
    mChild: Integer;
  begin
    if IsLocalOrAnonymousRecord(ARecord) then
    begin
      CheckLocalRecord(ARecord);
      Exit;
    end;
    for mChild := 0 to ARecord.ChildCount - 1 do
    begin
      if ARecord[mChild].Kind = TSyntaxKind.RoutineHeader then
      begin
        CheckRecordMethod(ARecord[mChild]);
      end;
    end;
  end;

  /// <summary>Stammt der Typ AName sicher nicht von AAncestor ab? False, wenn die Kette nicht bekannt ist.</summary>
  function CertainlyNotDescendant(const AName, AAncestor: string): Boolean;
  var
    mChain: TArray<TSymbolLocation>;
    mComplete, mObjectMissing: Boolean;
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
    if mAncestry = nil then
    begin
      mAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
    end;
    mChain := mAncestry.Ancestors(AName, mComplete, mObjectMissing);
    Result := mComplete and not ChainContains(mChain, AAncestor);
    Result := Result and not (mObjectMissing and SameText(AAncestor, 'TObject'));
  end;

  // Methoden in Helfern: E2598, E2475, E2295.
  procedure CheckHelperMethod(AMember: TSyntaxNode; AIsRecordHelper: Boolean);
  var
    mHead: TRoutineHead;
  begin
    mHead := TRoutineHead.Read(mTokens, AMember);
    if AIsRecordHelper then
    begin
      CheckForbiddenDirectives(mHead, 'E2598', cTexts[TTypeRestrictionsRecordsText.HelperVirtual].Text,
        'E2475', cTexts[TTypeRestrictionsRecordsText.HelperDirective].Text);
    end
    else if (mHead.Keyword = 'destructor') and not mHead.IsClass then
    begin
      Report('E2295', NameRange(AMember), cTexts[TTypeRestrictionsRecordsText.HelperDestructor].Text, nil);
    end;
  end;

  // Mitglieder von Helfern: Felder (E2599) und Methoden.
  procedure CheckHelperMember(AMember: TSyntaxNode; AIsRecordHelper: Boolean);
  var
    mInner: Integer;
  begin
    case AMember.Kind of
      TSyntaxKind.Field:
        Report('E2599', KeywordRange(AMember), cTexts[TTypeRestrictionsRecordsText.HelperFields].Text, nil);
      TSyntaxKind.VarSection:
        if not PrecededByClass(mTokens, AMember) then
        begin
          for mInner := 0 to AMember.ChildCount - 1 do
          begin
            Report('E2599', KeywordRange(AMember[mInner]), cTexts[TTypeRestrictionsRecordsText.HelperFields].Text,
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
    mAncestorName, mWanted: string;
    mTypeIndex: Integer;
    mAncestorTarget, mDummy: TSyntaxNode;
  begin
    mAncestorName := BareTypeName(AAncestorRef.Name);
    mTypeIndex := mTypes.IndexOf(mAncestorName);
    if (mTypeIndex < 0) or (mTypes.DeclaredKind(mAncestorName) <> TSyntaxKind.HelperType) then
    begin
      Exit;
    end;
    mAncestorTarget := HelperTarget(mTypes.Types[mTypeIndex], mDummy);
    if mAncestorTarget = nil then
    begin
      Exit;
    end;
    mWanted := BareTypeName(mAncestorTarget.Name);
    if CertainlyNotDescendant(BareTypeName(ATarget.Name), mWanted) then
    begin
      Report('E2294', NodeRange(ATarget), cTexts[TTypeRestrictionsRecordsText.HelperDescendants].Fmt([mAncestorName,
        mWanted]), nil);
    end;
  end;

  // Helfer im Kontext eines parametrisierten Typs (E2589).
  procedure CheckHelperContext(AHelper: TSyntaxNode);
  var
    mOuter: TSyntaxNode;
  begin
    mOuter := AHelper.Parent;
    if mOuter <> nil then
    begin
      mOuter := mOuter.Parent;
    end;
    while mOuter <> nil do
    begin
      if (mOuter.Kind = TSyntaxKind.TypeDecl) and (mOuter.FindChild(TSyntaxKind.GenericParams) <> nil) then
      begin
        Report('E2589', KeywordRange(AHelper.Parent), cTexts[TTypeRestrictionsRecordsText.HelperGeneric].Text, nil);
        Break;
      end;
      mOuter := mOuter.Parent;
    end;
  end;

  // Helfer: E2599, E2598, E2475, E2295, E2294, E2589. Klassenkonstruktoren im Class-Helfer (E2358) und
  // Helfer-Konstruktoren ohne Konstruktoraufruf zuerst (E2296) übersetzt dcc (Skia4Delphi MobileBars,
  // TSkPixmapHelper.Create, FMX.Skia TSkBitmapHelper; TR6, TR7, #1328); die Prüfungen sind entfallen.
  procedure CheckHelper(AHelper: TSyntaxNode);
  var
    mChild: Integer;
    mTarget, mAncestorRef: TSyntaxNode;
    mIsRecordHelper: Boolean;
  begin
    mIsRecordHelper := SameText(AHelper.Name, 'record');
    mTarget := HelperTarget(AHelper, mAncestorRef);
    for mChild := 0 to AHelper.ChildCount - 1 do
    begin
      CheckHelperMember(AHelper[mChild], mIsRecordHelper);
    end;
    if not mIsRecordHelper and (mAncestorRef <> nil) and (mTarget <> nil) and (BareTypeName(mTarget.Name) <> '') then
    begin
      CheckAncestorHelper(mTarget, mAncestorRef);
    end;
    CheckHelperContext(AHelper);
  end;

  // Klassenkonstruktoren: E2360, E2534, E2359.
  procedure CheckClassConstructors(AType: TSyntaxNode);
  var
    mChild: Integer;
    mHead: TRoutineHead;
    mDirective, mFirst: TSyntaxNode;
  begin
    mFirst := nil;
    for mChild := 0 to AType.ChildCount - 1 do
    begin
      if AType[mChild].Kind <> TSyntaxKind.RoutineHeader then
      begin
        Continue;
      end;
      mHead := TRoutineHead.Read(mTokens, AType[mChild]);
      if not mHead.IsClass or (mHead.Keyword <> 'constructor') then
      begin
        Continue;
      end;
      if mHead.ParameterCount > 0 then
      begin
        Report('E2360', NameRange(mHead.Header), cTexts[TTypeRestrictionsRecordsText.ClassCtorParams].Text, nil);
      end;
      mDirective := FirstDirective(mHead, cClassConstructorDirectives);
      if mDirective <> nil then
      begin
        Report('E2534', NodeRange(mDirective), cTexts[TTypeRestrictionsRecordsText.ClassCtorVirtual].Text,
          RemoveFix(mHead, cClassConstructorDirectives,
            cTexts[TTypeRestrictionsRecordsText.RemoveDirective].Fmt([mDirective.Name])));
      end;
      if mFirst = nil then
      begin
        mFirst := mHead.Header;
      end
      else if not TConditionalBranches.Exclusive(
        TConditionalBranches.PathAt(mPaths, TRoutineBody.TokenAt(mTokens, mFirst.StartOffset)),
        TConditionalBranches.PathAt(mPaths, TRoutineBody.TokenAt(mTokens, mHead.Header.StartOffset))) then
      begin
        Report('E2359', NameRange(mHead.Header), cTexts[TTypeRestrictionsRecordsText.ClassCtorMany].Fmt(
          [AType.Parent.Name, mFirst.Name, mHead.Header.Name]), nil);
      end;
    end;
  end;

  // inline an Köpfen: E2425, E2442, E2439.
  procedure CheckInlineHeader(AHeader: TSyntaxNode);
  var
    mHead: TRoutineHead;
    mInlineHead, mDecl: TSyntaxNode;
  begin
    mHead := TRoutineHead.Read(mTokens, AHeader);
    mInlineHead := mHead.Directive('inline');
    if mInlineHead = nil then
    begin
      Exit;
    end;
    if (AHeader.Parent <> nil) and (AHeader.Parent.Kind = TSyntaxKind.RoutineDecl) then
    begin
      mDecl := DeclarationOf(AHeader.Parent);
      if (mDecl <> nil) and (mDecl <> AHeader) and TRoutineHead.Read(mTokens, mDecl).HasDirective('inline') then
      begin
        Exit;
      end;
    end;
    if FirstDirective(mHead, cRecordVirtualDirectives) <> nil then
    begin
      Report('E2425', NodeRange(mInlineHead), cTexts[TTypeRestrictionsRecordsText.InlineVirtual].Text,
        RemoveFix(mHead, ['inline'], cTexts[TTypeRestrictionsRecordsText.RemoveInline].Text));
    end
    else if MatchText(mHead.Keyword, ['constructor', 'destructor']) then
    begin
      Report('E2442', NodeRange(mInlineHead), cTexts[TTypeRestrictionsRecordsText.InlineCtor].Text,
        RemoveFix(mHead, ['inline'], cTexts[TTypeRestrictionsRecordsText.RemoveInline].Text));
    end;
    if HasOpenArrayParameter(mHead) then
    begin
      Report('E2439', NodeRange(mInlineHead), cTexts[TTypeRestrictionsRecordsText.InlineOpenArray].Text,
        RemoveFix(mHead, ['inline'], cTexts[TTypeRestrictionsRecordsText.RemoveInline].Text));
    end;
  end;

  /// <summary>Kopf mit inline zum Rumpf ARoutine (eigener Kopf oder Deklaration), nil ohne.</summary>
  function InlineHeader(ARoutine: TSyntaxNode): TSyntaxNode;
  var
    mHeader: TSyntaxNode;
  begin
    mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if (mHeader <> nil) and TRoutineHead.Read(mTokens, mHeader).HasDirective('inline') then
    begin
      Exit(mHeader);
    end;
    Result := DeclarationOf(ARoutine);
    if (Result <> nil) and not TRoutineHead.Read(mTokens, Result).HasDirective('inline') then
    begin
      Result := nil;
    end;
  end;

  /// <summary>Namen, die ARoutine selbst als Parameter und Variablen deklariert (ohne verschachtelte
  /// Routinen).</summary>
  function OwnVariables(ARoutine: TSyntaxNode): TArray<string>;
  var
    mChild, mInner: Integer;
    mHeader: TSyntaxNode;
  begin
    Result := nil;
    mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if (mHeader <> nil) and (mHeader.FindChild(TSyntaxKind.Parameters) <> nil) then
    begin
      Result := NamesBelow(mHeader.FindChild(TSyntaxKind.Parameters));
    end;
    for mChild := 0 to ARoutine.ChildCount - 1 do
    begin
      if ARoutine[mChild].Kind = TSyntaxKind.VarSection then
      begin
        for mInner := 0 to ARoutine[mChild].ChildCount - 1 do
        begin
          Result := Result + DeclaredNames(ARoutine[mChild][mInner]);
        end;
      end;
    end;
  end;

  /// <summary>Bezeichner im Rumpf ABody, die nicht in with stehen.</summary>
  function IdentifiersIn(ABody: TSyntaxNode; ASkipNested: Boolean): TArray<TSyntaxNode>;
  var
    mFound: TArray<TSyntaxNode>;
  begin
    mFound := nil;
    ABody.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := (ANode.Kind <> TSyntaxKind.WithStatement) and
          not (ASkipNested and (ANode <> ABody) and (ANode.Kind = TSyntaxKind.RoutineDecl));
        if Result and (ANode.Kind = TSyntaxKind.Identifier) then
        begin
          mFound := mFound + [ANode];
        end;
      end);
    Result := mFound;
  end;

  // Aufruf eigener lokaler Routinen aus einer inline-Routine: E2501.
  procedure CheckNestedCalls(ARoutine, ABody: TSyntaxNode; const AFix: TArray<TRuleFix>);
  var
    mNested, mUsed: TArray<string>;
    mChild: Integer;
    mIdent: TSyntaxNode;
  begin
    mNested := nil;
    for mChild := 0 to ARoutine.ChildCount - 1 do
    begin
      if ARoutine[mChild].Kind = TSyntaxKind.RoutineDecl then
      begin
        mNested := mNested + [ARoutine[mChild].Name];
      end;
    end;
    if mNested = nil then
    begin
      Exit;
    end;
    mUsed := nil;
    for mIdent in IdentifiersIn(ABody, True) do
    begin
      if MatchText(mIdent.Name, mNested) and not MatchText(mIdent.Name, mUsed) then
      begin
        mUsed := mUsed + [mIdent.Name];
        Report('E2501', NodeRange(mIdent), cTexts[TTypeRestrictionsRecordsText.InlineLocalCall].Fmt([ARoutine.Name,
          mIdent.Name]), AFix);
      end;
    end;
  end;

  /// <summary>Ist ARoutine eine lokale Routine mit eigenem inline-Kopf?</summary>
  function IsLocalInline(ARoutine: TSyntaxNode): Boolean;
  var
    mHead: TSyntaxNode;
  begin
    mHead := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    Result := (ARoutine.Parent <> nil) and (ARoutine.Parent.Kind = TSyntaxKind.RoutineDecl) and (mHead <> nil);
    Result := Result and TRoutineHead.Read(mTokens, mHead).HasDirective('inline');
  end;

  // Lokale inline-Routine mit Zugriff auf Variablen der umgebenden Routine: E2449.
  procedure CheckOuterAccess(ARoutine, ABody: TSyntaxNode; const AFix: TArray<TRuleFix>);
  var
    mOutside, mOwn, mUsed: TArray<string>;
    mIdent: TSyntaxNode;
  begin
    mOutside := OwnVariables(ARoutine.Parent);
    mOwn := NamesBelow(ARoutine);
    mUsed := nil;
    for mIdent in IdentifiersIn(ABody, False) do
    begin
      if MatchText(mIdent.Name, mOutside) and not MatchText(mIdent.Name, mOwn) and
        not MatchText(mIdent.Name, mUsed) then
      begin
        mUsed := mUsed + [mIdent.Name];
        Report('E2449', NodeRange(mIdent), cTexts[TTypeRestrictionsRecordsText.InlineLocalAccess].Fmt([ARoutine.Name,
          mIdent.Name]), AFix);
      end;
    end;
  end;

  // Rümpfe von inline-Routinen: E2426, E2501, E2449.
  procedure CheckInlineBody(ARoutine: TSyntaxNode);
  var
    mInlineHead, mBody: TSyntaxNode;
    mHead: TRoutineHead;
    mFix: TArray<TRuleFix>;
  begin
    mInlineHead := InlineHeader(ARoutine);
    if mInlineHead = nil then
    begin
      Exit;
    end;
    mHead := TRoutineHead.Read(mTokens, mInlineHead);
    mFix := RemoveFix(mHead, ['inline'], cTexts[TTypeRestrictionsRecordsText.RemoveInline].Text);
    if ARoutine.FindChild(TSyntaxKind.AsmBlock) <> nil then
    begin
      Report('E2426', NodeRange(mHead.Directive('inline')), cTexts[TTypeRestrictionsRecordsText.InlineAsm].Text, mFix);
    end;
    mBody := ARoutine.FindChild(TSyntaxKind.Block);
    if mBody = nil then
    begin
      Exit;
    end;
    CheckNestedCalls(ARoutine, mBody, mFix);
    if IsLocalInline(ARoutine) then
    begin
      CheckOuterAccess(ARoutine, mBody, mFix);
    end;
  end;

  /// <summary>Ist ARoutine an ihrer Deklaration im interface-Teil inline? Nur das zählt: steht es allein am Rumpf,
  /// können andere Units die Routine ohnehin nicht einbetten (HtmlViewer, TR5).</summary>
  function InterfaceInline(ASymbols: TImplementationSymbols; ARoutine: TSyntaxNode): Boolean;
  var
    mDeclaration: TSyntaxNode;
  begin
    mDeclaration := DeclarationOf(ARoutine);
    Result := (mDeclaration <> nil) and TRoutineHead.Read(mTokens, mDeclaration).HasDirective('inline');
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
    mSymbols: TImplementationSymbols;
    mRoutine, mUse: TSyntaxNode;
    mUsable: TArray<string>;
  begin
    mSymbols := TImplementationSymbols.Create(AContext);
    try
      mUsable := InlineUsableNames(mRoot.FindChild(TSyntaxKind.ImplementationSection));
      for mRoutine in mSymbols.Routines do
      begin
        if not InterfaceInline(mSymbols, mRoutine) then
        begin
          Continue;
        end;
        for mUse in mSymbols.UsesIn(mRoutine, mSymbols.OwnerType(mRoutine)) do
        begin
          if not MatchText(mUse.Name, mUsable) then
          begin
            Report('E2441', NodeRange(mUse), cTexts[TTypeRestrictionsRecordsText.InlineImplementation].Fmt([mRoutine.Name,
              mUse.Name]), nil);
          end;
        end;
      end;
    finally
      mSymbols.Free;
    end;
  end;

  // threadvar: E2189, E2190, E2194.
  procedure CheckThreadVars(ASection: TSyntaxNode);
  var
    mOuter: TSyntaxNode;
    mChild: Integer;
    mDecl: TSyntaxNode;
  begin
    mOuter := ASection.Parent;
    while mOuter <> nil do
    begin
      if mOuter.Kind = TSyntaxKind.RoutineDecl then
      begin
        Report('E2189', KeywordRange(ASection), cTexts[TTypeRestrictionsRecordsText.ThreadvarLocal].Text, nil);
        Break;
      end;
      mOuter := mOuter.Parent;
    end;
    for mChild := 0 to ASection.ChildCount - 1 do
    begin
      mDecl := ASection[mChild];
      if mDecl.Kind <> TSyntaxKind.VarDecl then
      begin
        Continue;
      end;
      if HasTopLevelToken(mTokens, mDecl.StartOffset, mDecl.EndOffset, 'absolute') then
      begin
        Report('E2190', KeywordRange(mDecl), cTexts[TTypeRestrictionsRecordsText.ThreadvarAbsolute].Text, nil);
      end
      else if HasTopLevelToken(mTokens, mDecl.StartOffset, mDecl.EndOffset, '=') then
      begin
        Report('E2194', KeywordRange(mDecl), cTexts[TTypeRestrictionsRecordsText.ThreadvarInit].Text, nil);
      end;
    end;
  end;

  // Helfer als Typ einer Deklaration: E2527.
  procedure CheckHelperReference(AReference: TSyntaxNode);
  var
    mName: string;
  begin
    if (AReference.Parent = nil) or not (AReference.Parent.Kind in cDeclarationParents) or
      (Pos('.', AReference.Name) > 0) or (AReference.FindChild(TSyntaxKind.GenericArgs) <> nil) then
    begin
      Exit;
    end;
    mName := AReference.Name;
    if mTypes.DeclaredKind(mName) = TSyntaxKind.HelperType then
    begin
      Report('E2527', NodeRange(AReference), cTexts[TTypeRestrictionsRecordsText.HelperAsType].Fmt([mName]), nil);
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
  mTokens := AContext.Tree.Tokens;
  mRoot := AContext.Tree.Root;
  mTypes := TFileTypes.Collect(mRoot);
  mDisabled := TRuleOptions.Strings(AContext.Options, 'disabledChecks', nil);
  mPaths := TConditionalBranches.Paths(mTokens);
  mAncestry := nil;
  mNodes := TList<TSyntaxNode>.Create;
  try
    mRoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if ANode.Kind in [TSyntaxKind.RecordType, TSyntaxKind.ClassType, TSyntaxKind.ObjectType,
          TSyntaxKind.HelperType, TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl, TSyntaxKind.VarSection,
          TSyntaxKind.TypeReference] then
        begin
          mNodes.Add(ANode);
        end;
      end);
    for mNode in mNodes do
    begin
      CheckNode(mNode);
    end;
    CheckInlineLocalSymbols;
  finally
    mNodes.Free;
    mAncestry.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TypeRestrictions.Records', cTexts);

end.
