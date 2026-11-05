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
  UnsatisfiedForwardRuleId = 'unsatisfied-forward';

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
  Safe: Boolean;
begin
  Result := nil;
  if AFinding.Fix = TForwardFix.NoFix then
  begin
    Exit;
  end;
  // Ergänzen und Entfernen ändern nur eine Zeile und sind immer richtig.
  Safe := AFinding.Fix in [TForwardFix.AddForward, TForwardFix.RemoveForward];
  Result := [TRuleFix.Create(TForwardDeclarations.FixTitle(AFinding.Fix), AFinding.Edits, Safe)];
end;

{ TTypeUsedBeforeDeclarationRule }

function TTypeUsedBeforeDeclarationRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('type-used-before-declaration', TRuleSeverity.Error,
    cTexts[TForwardDeclarationsText.UsedBeforeTitle].Text);
end;

procedure TTypeUsedBeforeDeclarationRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Finding: TForwardFinding;
  Message: string;
begin
  if (AContext.Tree = nil) or AContext.NoForwardDeclaration then
  begin
    Exit;
  end;
  for Finding in TForwardDeclarations.Analyze(AContext.Tree, AContext.Text) do
  begin
    if Finding.Issue <> TForwardIssue.UsedBeforeDeclaration then
    begin
      Continue;
    end;
    Message := cTexts[TForwardDeclarationsText.UsedBefore].Fmt([Finding.TypeName, Finding.UserName]);
    if Finding.Reason <> '' then
    begin
      Message := Message + cTexts[TForwardDeclarationsText.NoFix].Fmt([Finding.Reason]);
    end;
    AReport.Add(Finding.Range, Message, FixesOf(Finding));
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
  Finding: TForwardFinding;
begin
  if (AContext.Tree = nil) or AContext.NoForwardDeclaration then
  begin
    Exit;
  end;
  for Finding in TForwardDeclarations.Analyze(AContext.Tree, AContext.Text) do
  begin
    if Finding.Issue = TForwardIssue.UnneededForward then
    begin
      AReport.Add(Finding.Range, cTexts[TForwardDeclarationsText.Redundant].Fmt([Finding.TypeName, Finding.TypeName]),
        FixesOf(Finding));
    end;
  end;
end;

{ TUnsatisfiedForwardRule }

function TUnsatisfiedForwardRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UnsatisfiedForwardRuleId, TRuleSeverity.Error,
    cTexts[TForwardDeclarationsText.UnresolvedTitle].Text);
end;

procedure TUnsatisfiedForwardRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;
  HasIncludes: Boolean;
  Implementation_: TSyntaxNode;

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

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, TokenAt(ANode.StartOffset));
  end;

  /// <summary>Bereich des ersten Bezeichners AName ab dem Anfang von ANode; der ganze Knoten ohne.</summary>
  function NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
  var
    Index: Integer;
  begin
    Index := TokenAt(ANode.StartOffset);
    while (Index < Length(Tokens)) and (Tokens[Index].Offset < ANode.EndOffset) do
    begin
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AName) then
      begin
        Exit(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos));
      end;
      Inc(Index);
    end;
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;

  function HasDirective(AHeader: TSyntaxNode; const ADirective: string): Boolean;
  var
    Index: Integer;
  begin
    for Index := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[Index].Kind = TSyntaxKind.Directive) and SameText(AHeader[Index].Name, ADirective) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  function ParamCount(AHeader: TSyntaxNode): Integer;
  var
    Params: TSyntaxNode;
    Index: Integer;
  begin
    Result := 0;
    Params := AHeader.FindChild(TSyntaxKind.Parameters);
    if Params <> nil then
    begin
      for Index := 0 to Params.ChildCount - 1 do
      begin
        if Params[Index].Kind = TSyntaxKind.Parameter then
        begin
          Inc(Result, Length(Params[Index].Name.Split([','])));
        end;
      end;
    end;
  end;

  /// <summary>Rumpf (oder external) im Sinn des Compilers: Block, asm-Block oder external.</summary>
  function IsBody(ARoutine: TSyntaxNode): Boolean;
  var
    Header: TSyntaxNode;
  begin
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    Result := (ARoutine.FindChild(TSyntaxKind.Block) <> nil) or (ARoutine.FindChild(TSyntaxKind.AsmBlock) <> nil) or
      ((Header <> nil) and HasDirective(Header, 'external'));
  end;

  /// <summary>Gibt es unter AContainer ab dem Kind AFrom einen Rumpf zur Deklaration ADecl, der mit ihr übersetzt
  /// wird?</summary>
  function Satisfied(AContainer: TSyntaxNode; AFrom: Integer; ADecl: TSyntaxNode): Boolean;
  var
    Index: Integer;
    Header, Other: TSyntaxNode;
    Overloaded: Boolean;
  begin
    Header := ADecl.FindChild(TSyntaxKind.RoutineHeader);
    Overloaded := HasDirective(Header, 'overload');
    for Index := AFrom to AContainer.ChildCount - 1 do
    begin
      Other := AContainer[Index];
      if (Other = ADecl) or (Other.Kind <> TSyntaxKind.RoutineDecl) or not SameText(Other.Name, ADecl.Name) or
        not IsBody(Other) or TConditionalBranches.Exclusive(PathOf(ADecl), PathOf(Other)) then
      begin
        Continue;
      end;
      if not Overloaded or (Other.FindChild(TSyntaxKind.RoutineHeader) = nil) or
        (ParamCount(Other.FindChild(TSyntaxKind.RoutineHeader)) = ParamCount(Header)) then
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
    for mIndex := AFirst to High(Tokens) do
    begin
      if Tokens[mIndex].IsSymbol('(') or Tokens[mIndex].IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if Tokens[mIndex].IsSymbol(')') or Tokens[mIndex].IsSymbol(']') then
      begin
        Dec(mDepth);
      end
      else if (mDepth = 0) and Tokens[mIndex].IsSymbol(';') then
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
    mFirst := TokenAt(AHeader.StartOffset);
    mStop := HeadStop(mFirst);
    if mStop < 0 then
    begin
      Exit('');
    end;
    Result := CompactHead(Copy(AContext.Text, Tokens[mFirst].Offset + 1,
      Tokens[mStop].Offset + 1 - Tokens[mFirst].Offset));
  end;

  /// <summary>Korrektur: leeren Rumpf vor initialization bzw. dem abschließenden "end." einfügen.</summary>
  function CreateBody(ADecl: TSyntaxNode): TArray<TRuleFix>;
  var
    Header, Section: TSyntaxNode;
    Head, Break_: string;
    Index: Integer;
    At: TTextPosition;
    Found: Boolean;
  begin
    Result := nil;
    Header := ADecl.FindChild(TSyntaxKind.RoutineHeader);
    if (Header = nil) or (Implementation_ = nil) then
    begin
      Exit;
    end;
    Head := HeadText(Header);
    if Head = '' then
    begin
      Exit;
    end;
    if HasDirective(Header, 'overload') then
    begin
      Head := Head + ' overload;';
    end;
    Found := False;
    At := Default(TTextPosition);
    Section := AContext.Tree.Root.FindChild(TSyntaxKind.InitializationSection);
    if Section <> nil then
    begin
      At := Section.StartPos;
      Found := True;
    end
    else
    begin
      for Index := High(Tokens) downto 1 do
      begin
        if Tokens[Index].IsSymbol('.') and Tokens[Index - 1].IsKeyword('end') then
        begin
          At := Tokens[Index - 1].StartPos;
          Found := True;
          Break;
        end;
      end;
    end;
    if not Found or (At.Character <> 0) then
    begin
      Exit;
    end;
    Break_ := TTextLines.LineBreakOf(AContext.Text);
    Result := [TRuleFix.Create(cTexts[TForwardDeclarationsText.CreateEmptyBody].Fmt([ADecl.Name]),
      [TRuleEdit.Create(TTextRange.Create(At, At), Head + Break_ + 'begin' + Break_ + 'end;' + Break_ + Break_)])];
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
    if AContainer = Implementation_ then
    begin
      AReport.Add(NameRange(mHeader, mChild.Name), mMessage, TRuleConfidence.High, CreateBody(mChild));
    end
    else
    begin
      AReport.Add(NameRange(mHeader, mChild.Name), mMessage, TRuleConfidence.High);
    end;
  end;

  // Iterativ (Bericht M1): der Stapel hält Container und Index der Routinen, in derselben Reihenfolge wie
  // zuvor die Rekursion in lokale Routinen.
  procedure CheckRoutines(ARoot: TSyntaxNode);
  var
    PendingContainer: TStack<TSyntaxNode>;
    PendingIndex: TStack<Integer>;
    Container, Child: TSyntaxNode;
    Index, ChildIndex: Integer;
  begin
    PendingContainer := TStack<TSyntaxNode>.Create;
    PendingIndex := TStack<Integer>.Create;
    try
      for ChildIndex := ARoot.ChildCount - 1 downto 0 do
      begin
        if ARoot[ChildIndex].Kind = TSyntaxKind.RoutineDecl then
        begin
          PendingContainer.Push(ARoot);
          PendingIndex.Push(ChildIndex);
        end;
      end;
      while PendingContainer.Count > 0 do
      begin
        Container := PendingContainer.Pop;
        Index := PendingIndex.Pop;
        Child := Container[Index];
        CheckForward(Container, Index);
        // Lokale Routinen mit forward.
        for ChildIndex := Child.ChildCount - 1 downto 0 do
        begin
          if Child[ChildIndex].Kind = TSyntaxKind.RoutineDecl then
          begin
            PendingContainer.Push(Child);
            PendingIndex.Push(ChildIndex);
          end;
        end;
      end;
    finally
      PendingIndex.Free;
      PendingContainer.Free;
    end;
  end;

  procedure CheckInterface(ASection: TSyntaxNode);
  var
    Index: Integer;
    Child, Header: TSyntaxNode;
  begin
    for Index := 0 to ASection.ChildCount - 1 do
    begin
      Child := ASection[Index];
      if Child.Kind <> TSyntaxKind.RoutineDecl then
      begin
        Continue;
      end;
      Header := Child.FindChild(TSyntaxKind.RoutineHeader);
      if (Header = nil) or HasDirective(Header, 'external') or HasDirective(Header, 'forward') or
        (Pos('.', Child.Name) > 0) or (PathOf(Child) <> '') then
      begin
        Continue;
      end;
      if not Satisfied(Implementation_, 0, Child) then
      begin
        AReport.Add(NameRange(Header, Child.Name),
          cTexts[TForwardDeclarationsText.InterfaceNotImplemented].Fmt([Child.Name]), TRuleConfidence.High,
          CreateBody(Child));
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
    Index: Integer;
    Decl, Forward_: TSyntaxNode;
    Code: string;
  begin
    for Index := 0 to ASection.ChildCount - 1 do
    begin
      Decl := ASection[Index];
      if Decl.Kind <> TSyntaxKind.TypeDecl then
      begin
        Continue;
      end;
      CheckSelfContained(Decl);
      Forward_ := Decl.FindChild(TSyntaxKind.ForwardType);
      if (Forward_ = nil) or (PathOf(Decl) <> '') or Completed(ASection, Index) then
      begin
        Continue;
      end;
      if SameText(Forward_.Name, 'class') then
      begin
        Code := 'E2086';
      end
      else
      begin
        Code := 'E2420';
      end;
      AReport.Add(NameRange(Decl, Decl.Name), cTexts[TForwardDeclarationsText.FullMissing].Fmt([Decl.Name, Code]),
        TRuleConfidence.High);
    end;
  end;

  // Iterativ (Bericht M1).
  procedure VisitTypes(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.TypeSection then
        begin
          CheckTypes(Node);
        end;
        // Nur Deklarationscontainer (#1094).
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          if Node[Index].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
            TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl, TSyntaxKind.ClassType, TSyntaxKind.ObjectType,
            TSyntaxKind.RecordType, TSyntaxKind.RoutineDecl] then
          begin
            Pending.Push(Node[Index]);
          end;
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Token: TPascalToken;
  Interface_: TSyntaxNode;
  Text: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  HasIncludes := False;
  for Token in Tokens do
  begin
    if Token.Kind = TPascalTokenKind.Directive then
    begin
      Text := UpperCase(Token.Text);
      // {$I+} und {$I-} schalten die E/A-Prüfung um und sind keine Includes.
      if StartsStr('{$INCLUDE ', Text) or StartsStr('{$I ', Text) then
      begin
        HasIncludes := True;
      end;
    end;
  end;
  VisitTypes(AContext.Tree.Root);
  if HasIncludes then
  begin
    Exit;
  end;
  Implementation_ := AContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  Interface_ := AContext.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  if (Interface_ <> nil) and (Implementation_ <> nil) then
  begin
    CheckInterface(Interface_);
  end;
  if Implementation_ <> nil then
  begin
    CheckRoutines(Implementation_);
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
