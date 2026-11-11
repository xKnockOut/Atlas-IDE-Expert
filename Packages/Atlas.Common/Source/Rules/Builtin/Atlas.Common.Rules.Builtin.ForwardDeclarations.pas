unit Atlas.Common.Rules.Builtin.ForwardDeclarations;

// Forward-Deklarationen (#685):
//   type-used-before-declaration   Typ in einer Typdeklaration benutzt, bevor er
//                                  deklariert ist (sonst erst E2003)
//   unneeded-forward-declaration   Forward-Deklaration, die niemand braucht
//   unsatisfied-forward            Vorwärtsdeklaration nie aufgelöst (#1002, Gruppe
//                                  Compiler vorab): Routine im interface-Teil
//                                  oder mit forward ohne Rumpf (E2065),
//                                  TFoo = class; bzw. IFoo = interface; ohne
//                                  vollständige Deklaration im selben
//                                  type-Abschnitt (E2086, E2420); Typ, der
//                                  noch nicht vollständig ist (#1380, wie
//                                  E2086): vorwärts deklarierte Klasse oder
//                                  vorwärts deklariertes Interface als Vorfahr
//                                  oder in der Interface-Liste vor der
//                                  vollständigen Deklaration (Cm.E2420), ein
//                                  Record mit einem Feld seines eigenen Typs
//                                  (Cm.E2086)
//
// Erkennung und Korrekturen liefert TForwardDeclarations (Editing). Mit
// refactoring.forwardDeclaration aus schweigen die ersten beiden Regeln.
//
// unsatisfied-forward liest nur den Syntaxbaum; Methoden prüft
// declared-not-implemented. Ein Rumpf passt, wenn er gleich heißt; bei
// overload muss auch die Zahl der Parameter stimmen. Ein external im
// implementation-Teil zählt als Rumpf. Deklarationen in einem {$IFDEF}-Zweig
// bleiben unbeachtet, ein Rumpf im ausschließenden Zweig zählt nicht
// (TConditionalBranches). Bindet die Datei Include-Dateien ein, schweigt die
// Regel für Routinen. Korrektur: leeren Rumpf vor initialization bzw. dem
// abschließenden end. anlegen.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TTypeUsedBeforeDeclarationRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnneededForwardDeclarationRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnsatisfiedForwardRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  cUnsatisfiedForwardRuleId = 'unsatisfied-forward';

procedure RegisterForwardDeclarationRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Editing.ForwardDeclarations,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TForwardDeclarationsText = (UsedBeforeTitle, UsedBefore, NoFix, RedundantTitle, Redundant, UnresolvedTitle,
    CreateEmptyBody, ForwardNotImplemented, InterfaceNotImplemented, ContainsItself, OnlyForward, FullMissing);

const
  cTexts: array[TForwardDeclarationsText] of TAtlasText = (
    (De: 'Typ wird benutzt, bevor er deklariert ist'; En: 'Type is used before it is declared'),
    (De: '"%s" wird in %s benutzt, bevor es deklariert ist'; En: '"%s" is used in %s before it is declared'),
    (De: ' (keine Korrektur: %s)'; En: ' (no fix: %s)'),
    (De: 'Überflüssige Forward-Deklaration'; En: 'Redundant forward declaration'),
    (De: 'Die Forward-Deklaration von "%s" wird nicht gebraucht: %s wird vor seiner Deklaration nicht benutzt';
     En: 'The forward declaration of "%s" is not needed: %s is not used before its declaration'),
    (De: 'Vorwärtsdeklaration nie aufgelöst'; En: 'Forward declaration never resolved'),
    (De: 'Leeren Rumpf für %s anlegen'; En: 'Create empty body for %s'),
    (De: '%s ist forward deklariert, aber nicht implementiert (wie E2065).';
     En: '%s is declared forward but not implemented (like E2065).'),
    (De: '%s ist im interface deklariert, aber nicht implementiert (wie E2065).';
     En: '%s is declared in the interface but not implemented (like E2065).'),
    (De: 'Der Record %s enthält sich selbst als Feld %s; ein Typ ist erst nach seinem end vollständig (wie E2086).';
     En: 'The record %s contains itself as field %s; a type is complete only after its end (like E2086).'),
    (De: '%s ist hier nur vorwärts deklariert; als Vorfahr oder in der Interface-Liste von %s muss der Typ schon ' +
      'vollständig sein (wie E2086).';
     En: '%s is only declared forward here; as ancestor or in the interface list of %s the type must already be ' +
      'complete (like E2086).'),
    (De: '%s ist nur vorwärts deklariert; die vollständige Deklaration fehlt in diesem type-Abschnitt (wie %s).';
     En: '%s is only declared forward; the full declaration is missing in this type section (like %s).'));

{$SCOPEDENUMS OFF}

function FixesOf(const AFinding: TForwardFinding): TArray<TRuleFix>;
var
  mSafe: Boolean;
begin
  Result := nil;
  if AFinding.Fix = TForwardFix.NoFix then
  begin
    Exit;
  end;
  // Ergänzen und Entfernen ändern nur eine Zeile und sind immer richtig.
  mSafe := AFinding.Fix in [TForwardFix.AddForward, TForwardFix.RemoveForward];
  Result := [TRuleFix.Create(TForwardDeclarations.FixTitle(AFinding.Fix), AFinding.Edits, mSafe)];
end;

{ TTypeUsedBeforeDeclarationRule }

function TTypeUsedBeforeDeclarationRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('type-used-before-declaration', TRuleSeverity.Error,
    cTexts[TForwardDeclarationsText.UsedBeforeTitle].Text);
end;

procedure TTypeUsedBeforeDeclarationRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mFinding: TForwardFinding;
  mMessage: string;
begin
  if (AContext.Tree = nil) or AContext.NoForwardDeclaration then
  begin
    Exit;
  end;
  for mFinding in TForwardDeclarations.Analyze(AContext.Tree, AContext.Text) do
  begin
    if mFinding.Issue <> TForwardIssue.UsedBeforeDeclaration then
    begin
      Continue;
    end;
    mMessage := cTexts[TForwardDeclarationsText.UsedBefore].Fmt([mFinding.TypeName, mFinding.UserName]);
    if mFinding.Reason <> '' then
    begin
      mMessage := mMessage + cTexts[TForwardDeclarationsText.NoFix].Fmt([mFinding.Reason]);
    end;
    AReport.Add(mFinding.Range, mMessage, FixesOf(mFinding));
  end;
end;

{ TUnneededForwardDeclarationRule }

function TUnneededForwardDeclarationRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unneeded-forward-declaration', TRuleSeverity.Hint,
    cTexts[TForwardDeclarationsText.RedundantTitle].Text);
end;

procedure TUnneededForwardDeclarationRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mFinding: TForwardFinding;
begin
  if (AContext.Tree = nil) or AContext.NoForwardDeclaration then
  begin
    Exit;
  end;
  for mFinding in TForwardDeclarations.Analyze(AContext.Tree, AContext.Text) do
  begin
    if mFinding.Issue = TForwardIssue.UnneededForward then
    begin
      AReport.Add(mFinding.Range, cTexts[TForwardDeclarationsText.Redundant].Fmt([mFinding.TypeName,
        mFinding.TypeName]),
        FixesOf(mFinding));
    end;
  end;
end;

{ TUnsatisfiedForwardRule }

function TUnsatisfiedForwardRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cUnsatisfiedForwardRuleId, TRuleSeverity.Error,
    cTexts[TForwardDeclarationsText.UnresolvedTitle].Text);
end;

procedure TUnsatisfiedForwardRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mPaths: TArray<string>;
  mHasIncludes: Boolean;
  mImplementation_: TSyntaxNode;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(mPaths, TokenFrom(mTokens, ANode.StartOffset));
  end;

  /// <summary>Bereich des ersten Bezeichners AName ab dem Anfang von ANode; der ganze Knoten ohne.</summary>
  function NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
  var
    mIndex: Integer;
  begin
    mIndex := TokenFrom(mTokens, ANode.StartOffset);
    while (mIndex < Length(mTokens)) and (mTokens[mIndex].Offset < ANode.EndOffset) do
    begin
      if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mIndex].Text, AName) then
      begin
        Exit(TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].EndPos));
      end;
      Inc(mIndex);
    end;
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;

  function HasDirective(AHeader: TSyntaxNode; const ADirective: string): Boolean;
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(AHeader[mIndex].Name, ADirective) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  function ParamCount(AHeader: TSyntaxNode): Integer;
  var
    mParams: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := 0;
    mParams := AHeader.FindChild(TSyntaxKind.Parameters);
    if mParams <> nil then
    begin
      for mIndex := 0 to mParams.ChildCount - 1 do
      begin
        if mParams[mIndex].Kind = TSyntaxKind.Parameter then
        begin
          Inc(Result, Length(mParams[mIndex].Name.Split([','])));
        end;
      end;
    end;
  end;

  /// <summary>Rumpf (oder external) im Sinn des Compilers: Block, asm-Block oder external.</summary>
  function IsBody(ARoutine: TSyntaxNode): Boolean;
  var
    mHeader: TSyntaxNode;
  begin
    mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    Result := (ARoutine.FindChild(TSyntaxKind.Block) <> nil) or (ARoutine.FindChild(TSyntaxKind.AsmBlock) <> nil) or
      ((mHeader <> nil) and HasDirective(mHeader, 'external'));
  end;

  /// <summary>Gibt es unter AContainer ab dem Kind AFrom einen Rumpf zur Deklaration ADecl, der mit ihr übersetzt
  /// wird?</summary>
  function Satisfied(AContainer: TSyntaxNode; AFrom: Integer; ADecl: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
    mHeader, mOther: TSyntaxNode;
    mOverloaded: Boolean;
  begin
    mHeader := ADecl.FindChild(TSyntaxKind.RoutineHeader);
    mOverloaded := HasDirective(mHeader, 'overload');
    for mIndex := AFrom to AContainer.ChildCount - 1 do
    begin
      mOther := AContainer[mIndex];
      if (mOther = ADecl) or (mOther.Kind <> TSyntaxKind.RoutineDecl) or not SameText(mOther.Name, ADecl.Name) or
        not IsBody(mOther) or TConditionalBranches.Exclusive(PathOf(ADecl), PathOf(mOther)) then
      begin
        Continue;
      end;
      if not mOverloaded or (mOther.FindChild(TSyntaxKind.RoutineHeader) = nil) or
        (ParamCount(mOther.FindChild(TSyntaxKind.RoutineHeader)) = ParamCount(mHeader)) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  /// <summary>Token des ersten ";" ab AFirst außerhalb von Klammern; -1 ohne.</summary>
  function HeadStop(AFirst: Integer): Integer;
  var
    mIndex, mDepth: Integer;
  begin
    mDepth := 0;
    for mIndex := AFirst to High(mTokens) do
    begin
      if mTokens[mIndex].IsSymbol('(') or mTokens[mIndex].IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if mTokens[mIndex].IsSymbol(')') or mTokens[mIndex].IsSymbol(']') then
      begin
        Dec(mDepth);
      end
      else if (mDepth = 0) and mTokens[mIndex].IsSymbol(';') then
      begin
        Exit(mIndex);
      end;
    end;
    Result := -1;
  end;

  /// <summary>Klammertiefe ADepth zum Zeichen AChar nachführen; ASkipping: innerhalb eines Standardwerts
  /// (ab "=" in der Parameterliste bis ";" oder zur schließenden Klammer).</summary>
  procedure TrackDefault(AChar: Char; var ADepth: Integer; var ASkipping: Boolean);
  begin
    case AChar of
      '(', '[':
        Inc(ADepth);
      ')', ']':
        begin
          Dec(ADepth);
          ASkipping := ASkipping and (ADepth <> 0);
        end;
      ';':
        ASkipping := ASkipping and (ADepth <> 1);
      '=':
        ASkipping := ASkipping or (ADepth = 1);
    end;
  end;

  /// <summary>AText ohne Standardwerte, Leerraum zu einem Leerzeichen zusammengefasst.</summary>
  function CompactHead(const AText: string): string;
  var
    mIndex, mDepth: Integer;
    mQuoted, mSkipping, mSpace: Boolean;
  begin
    Result := '';
    mDepth := 0;
    mQuoted := False;
    mSkipping := False;
    mSpace := False;
    for mIndex := 1 to Length(AText) do
    begin
      if AText[mIndex] = '''' then
      begin
        mQuoted := not mQuoted;
      end;
      if not mQuoted then
      begin
        TrackDefault(AText[mIndex], mDepth, mSkipping);
      end;
      if mSkipping then
      begin
        Continue;
      end;
      if not mQuoted and CharInSet(AText[mIndex], [' ', #9, #10, #13]) then
      begin
        mSpace := Result <> '';
        Continue;
      end;
      if mSpace and not CharInSet(AText[mIndex], [';', ')', ']', ',']) then
      begin
        Result := Result + ' ';
      end;
      mSpace := False;
      Result := Result + AText[mIndex];
    end;
  end;

  /// <summary>Kopf bis zum ersten ";" ohne Standardwerte und Zeilenumbrüche, z. B.
  /// "function Pruefsumme(const Daten: TBytes): Cardinal;"; '' ohne ";".</summary>
  function HeadText(AHeader: TSyntaxNode): string;
  var
    mFirst, mStop: Integer;
  begin
    mFirst := TokenFrom(mTokens, AHeader.StartOffset);
    mStop := HeadStop(mFirst);
    if mStop < 0 then
    begin
      Exit('');
    end;
    Result := CompactHead(Copy(AContext.Text, mTokens[mFirst].Offset + 1,
      mTokens[mStop].Offset + 1 - mTokens[mFirst].Offset));
  end;

  /// <summary>Korrektur: leeren Rumpf vor initialization bzw. dem abschließenden "end." einfügen.</summary>
  function CreateBody(ADecl: TSyntaxNode): TArray<TRuleFix>;
  var
    mHeader, mSection: TSyntaxNode;
    mHead, mBreak_: string;
    mIndex: Integer;
    mAt: TTextPosition;
    mFound: Boolean;
  begin
    Result := nil;
    mHeader := ADecl.FindChild(TSyntaxKind.RoutineHeader);
    if (mHeader = nil) or (mImplementation_ = nil) then
    begin
      Exit;
    end;
    mHead := HeadText(mHeader);
    if mHead = '' then
    begin
      Exit;
    end;
    if HasDirective(mHeader, 'overload') then
    begin
      mHead := mHead + ' overload;';
    end;
    mFound := False;
    mAt := Default(TTextPosition);
    mSection := AContext.Tree.Root.FindChild(TSyntaxKind.InitializationSection);
    if mSection <> nil then
    begin
      mAt := mSection.StartPos;
      mFound := True;
    end
    else
    begin
      for mIndex := High(mTokens) downto 1 do
      begin
        if mTokens[mIndex].IsSymbol('.') and mTokens[mIndex - 1].IsKeyword('end') then
        begin
          mAt := mTokens[mIndex - 1].StartPos;
          mFound := True;
          Break;
        end;
      end;
    end;
    if not mFound or (mAt.Character <> 0) then
    begin
      Exit;
    end;
    mBreak_ := TTextLines.LineBreakOf(AContext.Text);
    Result := [TRuleFix.Create(cTexts[TForwardDeclarationsText.CreateEmptyBody].Fmt([ADecl.Name]),
      [TRuleEdit.Create(TTextRange.Create(mAt, mAt), mHead + mBreak_ + 'begin' + mBreak_ + 'end;' + mBreak_ + mBreak_)])];
  end;

  /// <summary>E2065: Die Routine AContainer[AIndex] ist forward deklariert, aber nicht implementiert.</summary>
  procedure CheckForward(AContainer: TSyntaxNode; AIndex: Integer);
  var
    mChild, mHeader: TSyntaxNode;
    mMessage: string;
  begin
    mChild := AContainer[AIndex];
    mHeader := mChild.FindChild(TSyntaxKind.RoutineHeader);
    if (mHeader = nil) or not HasDirective(mHeader, 'forward') or (Pos('.', mChild.Name) > 0) or
      (PathOf(mChild) <> '') or Satisfied(AContainer, AIndex + 1, mChild) then
    begin
      Exit;
    end;
    mMessage := cTexts[TForwardDeclarationsText.ForwardNotImplemented].Fmt([mChild.Name]);
    if AContainer = mImplementation_ then
    begin
      AReport.Add(NameRange(mHeader, mChild.Name), mMessage, TRuleConfidence.High, CreateBody(mChild));
    end
    else
    begin
      AReport.Add(NameRange(mHeader, mChild.Name), mMessage, TRuleConfidence.High);
    end;
  end;

  // Iterativ (tiefe Bäume sprengen den Stapel nicht): der Stapel hält Container und Index der Routinen, in derselben Reihenfolge wie
  // zuvor die Rekursion in lokale Routinen.
  procedure CheckRoutines(ARoot: TSyntaxNode);
  var
    mPendingContainer: TStack<TSyntaxNode>;
    mPendingIndex: TStack<Integer>;
    mContainer, mChild: TSyntaxNode;
    mIndex, mChildIndex: Integer;
  begin
    mPendingContainer := TStack<TSyntaxNode>.Create;
    mPendingIndex := TStack<Integer>.Create;
    try
      for mChildIndex := ARoot.ChildCount - 1 downto 0 do
      begin
        if ARoot[mChildIndex].Kind = TSyntaxKind.RoutineDecl then
        begin
          mPendingContainer.Push(ARoot);
          mPendingIndex.Push(mChildIndex);
        end;
      end;
      while mPendingContainer.Count > 0 do
      begin
        mContainer := mPendingContainer.Pop;
        mIndex := mPendingIndex.Pop;
        mChild := mContainer[mIndex];
        CheckForward(mContainer, mIndex);
        // Lokale Routinen mit forward.
        for mChildIndex := mChild.ChildCount - 1 downto 0 do
        begin
          if mChild[mChildIndex].Kind = TSyntaxKind.RoutineDecl then
          begin
            mPendingContainer.Push(mChild);
            mPendingIndex.Push(mChildIndex);
          end;
        end;
      end;
    finally
      mPendingIndex.Free;
      mPendingContainer.Free;
    end;
  end;

  procedure CheckInterface(ASection: TSyntaxNode);
  var
    mIndex: Integer;
    mChild, mHeader: TSyntaxNode;
  begin
    for mIndex := 0 to ASection.ChildCount - 1 do
    begin
      mChild := ASection[mIndex];
      if mChild.Kind <> TSyntaxKind.RoutineDecl then
      begin
        Continue;
      end;
      mHeader := mChild.FindChild(TSyntaxKind.RoutineHeader);
      if (mHeader = nil) or HasDirective(mHeader, 'external') or HasDirective(mHeader, 'forward') or
        (Pos('.', mChild.Name) > 0) or (PathOf(mChild) <> '') then
      begin
        Continue;
      end;
      if not Satisfied(mImplementation_, 0, mChild) then
      begin
        AReport.Add(NameRange(mHeader, mChild.Name),
          cTexts[TForwardDeclarationsText.InterfaceNotImplemented].Fmt([mChild.Name]), TRuleConfidence.High,
          CreateBody(mChild));
      end;
    end;
  end;

  /// <summary>E2086 (#1380): Ein Record enthält ein Feld seines eigenen Typs (TKreis = record Innen: TKreis).
  /// </summary>
  procedure CheckSelfContained(ADecl: TSyntaxNode);
  var
    mRecord, mField, mType: TSyntaxNode;
    mIndex: Integer;
  begin
    mRecord := ADecl.FindChild(TSyntaxKind.RecordType);
    if (mRecord = nil) or (Pos('<', ADecl.Name) > 0) or (PathOf(ADecl) <> '') then
    begin
      Exit;
    end;
    for mIndex := 0 to mRecord.ChildCount - 1 do
    begin
      mField := mRecord[mIndex];
      if (mField.Kind <> TSyntaxKind.Field) or (mField.ChildCount = 0) then
      begin
        Continue;
      end;
      mType := mField[0];
      if (mType.Kind = TSyntaxKind.TypeReference) and (mType.ChildCount = 0) and SameText(mType.Name, ADecl.Name) then
      begin
        AReport.Add(TTextRange.Create(mType.StartPos, mType.EndPos),
          cTexts[TForwardDeclarationsText.ContainsItself].Fmt([ADecl.Name, mField.Name]),
          TRuleConfidence.High);
      end;
    end;
  end;

  /// <summary>E2086 (#1380): Klassen und Interfaces zwischen der Vorwärtsdeklaration ADecl und ihrer
  /// Vervollständigung an AComplete, die den Typ als Vorfahr oder in der Interface-Liste nennen (Cm.E2420).
  /// </summary>
  procedure CheckIncompleteUse(ASection, ADecl: TSyntaxNode; AFirst, AComplete: Integer);
  var
    mIndex, mChild: Integer;
    mUser, mBody, mType: TSyntaxNode;
  begin
    for mIndex := AFirst to AComplete - 1 do
    begin
      mUser := ASection[mIndex];
      if (mUser.Kind <> TSyntaxKind.TypeDecl) or (PathOf(mUser) <> '') then
      begin
        Continue;
      end;
      mBody := mUser.FindChild(TSyntaxKind.ClassType);
      if mBody = nil then
      begin
        mBody := mUser.FindChild(TSyntaxKind.InterfaceType);
      end;
      if mBody = nil then
      begin
        Continue;
      end;
      for mChild := 0 to mBody.ChildCount - 1 do
      begin
        mType := mBody[mChild];
        if (mType.Kind = TSyntaxKind.TypeReference) and (mType.ChildCount = 0) and SameText(mType.Name, ADecl.Name)
        then
        begin
          AReport.Add(TTextRange.Create(mType.StartPos, mType.EndPos), cTexts[TForwardDeclarationsText.OnlyForward].Fmt(
            [ADecl.Name, mUser.Name]), TRuleConfidence.High);
        end;
      end;
    end;
  end;

  /// <summary>Vervollständigt eine spätere Deklaration in ASection die Vorwärtsdeklaration ASection[AIndex]?
  /// Prüft dabei die Verwendungen dazwischen (CheckIncompleteUse).</summary>
  function Completed(ASection: TSyntaxNode; AIndex: Integer): Boolean;
  var
    mLater: Integer;
    mDecl, mOther: TSyntaxNode;
  begin
    mDecl := ASection[AIndex];
    for mLater := AIndex + 1 to ASection.ChildCount - 1 do
    begin
      mOther := ASection[mLater];
      if (mOther.Kind = TSyntaxKind.TypeDecl) and SameText(mOther.Name, mDecl.Name) and
        (mOther.FindChild(TSyntaxKind.ForwardType) = nil) and
        not TConditionalBranches.Exclusive(PathOf(mDecl), PathOf(mOther)) then
      begin
        if PathOf(mOther) = '' then
        begin
          CheckIncompleteUse(ASection, mDecl, AIndex + 1, mLater);
        end;
        Exit(True);
      end;
    end;
    Result := False;
  end;

  procedure CheckTypes(ASection: TSyntaxNode);
  var
    mIndex: Integer;
    mDecl, mForward_: TSyntaxNode;
    mCode: string;
  begin
    for mIndex := 0 to ASection.ChildCount - 1 do
    begin
      mDecl := ASection[mIndex];
      if mDecl.Kind <> TSyntaxKind.TypeDecl then
      begin
        Continue;
      end;
      CheckSelfContained(mDecl);
      mForward_ := mDecl.FindChild(TSyntaxKind.ForwardType);
      if (mForward_ = nil) or (PathOf(mDecl) <> '') or Completed(ASection, mIndex) then
      begin
        Continue;
      end;
      if SameText(mForward_.Name, 'class') then
      begin
        mCode := 'E2086';
      end
      else
      begin
        mCode := 'E2420';
      end;
      AReport.Add(NameRange(mDecl, mDecl.Name), cTexts[TForwardDeclarationsText.FullMissing].Fmt([mDecl.Name, mCode]),
        TRuleConfidence.High);
    end;
  end;

  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  procedure VisitTypes(ARoot: TSyntaxNode);
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
        if mNode.Kind = TSyntaxKind.TypeSection then
        begin
          CheckTypes(mNode);
        end;
        // Nur Deklarationscontainer (#1094).
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          if mNode[mIndex].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
            TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl, TSyntaxKind.ClassType, TSyntaxKind.ObjectType,
            TSyntaxKind.RecordType, TSyntaxKind.RoutineDecl] then
          begin
            mPending.Push(mNode[mIndex]);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

var
  mToken: TPascalToken;
  mInterface_: TSyntaxNode;
  mText: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mPaths := TConditionalBranches.Paths(mTokens);
  mHasIncludes := False;
  for mToken in mTokens do
  begin
    if mToken.Kind = TPascalTokenKind.Directive then
    begin
      mText := UpperCase(mToken.Text);
      // {$I+} und {$I-} schalten die E/A-Prüfung um und sind keine Includes.
      if StartsStr('{$INCLUDE ', mText) or StartsStr('{$I ', mText) then
      begin
        mHasIncludes := True;
      end;
    end;
  end;
  VisitTypes(AContext.Tree.Root);
  if mHasIncludes then
  begin
    Exit;
  end;
  mImplementation_ := AContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  mInterface_ := AContext.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  if (mInterface_ <> nil) and (mImplementation_ <> nil) then
  begin
    CheckInterface(mInterface_);
  end;
  if mImplementation_ <> nil then
  begin
    CheckRoutines(mImplementation_);
  end
  else if AContext.Tree.Root.Kind in [TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile] then
  begin
    CheckRoutines(AContext.Tree.Root);
  end;
end;

procedure RegisterForwardDeclarationRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TTypeUsedBeforeDeclarationRule.Create);
  ARegistry.Register(TUnneededForwardDeclarationRule.Create);
  ARegistry.Register(TUnsatisfiedForwardRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.ForwardDeclarations', cTexts);

end.
