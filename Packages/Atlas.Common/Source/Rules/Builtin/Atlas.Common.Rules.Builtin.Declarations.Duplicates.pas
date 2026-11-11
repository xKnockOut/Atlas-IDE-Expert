unit Atlas.Common.Rules.Builtin.Declarations.Duplicates;

// Regel duplicate-declaration aus Atlas.Common.Rules.Builtin.Declarations (#988, wie E2004): Bezeichner im
// selben Bereich zweimal deklariert (Parameter und lokale Deklarationen, Mitglieder eines Typs, die Unit über
// interface und implementation, uses (#1000, wie E2291), Zuordnung IFoo.Bar = Baz für ein nicht genanntes
// Interface (wie E2265)), Werte eines Aufzählungstyps (#1345, wie E2004).

interface

uses
  Atlas.Common.Rules.Contract;

type
  TDuplicateDeclarationRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  cDuplicateDeclarationRuleId = 'duplicate-declaration';

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Rules.Builtin.Declarations.Shared,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDeclarationsDuplicatesText = (Title, RemoveSecond, AlreadyDeclared, RemoveDuplicate, UnitTwice, UnitInInterface,
    KindType, KindVariable, KindConstant, KindRoutine, KindField, KindMethod, KindProperty, KindParameter, KindLabel,
    KindEnumValue);

const
  cTexts: array[TDeclarationsDuplicatesText] of TAtlasText = (
    (De: 'Bezeichner doppelt deklariert'; En: 'Identifier declared twice'),
    (De: 'Zweite Deklaration entfernen'; En: 'Remove second declaration'),
    (De: '%s ist schon als %s deklariert (wie E2004).'; En: '%s is already declared as %s (like E2004).'),
    (De: 'Doppelten Eintrag entfernen'; En: 'Remove duplicate entry'),
    (De: 'Unit %s steht schon in uses (wie E2004).'; En: 'Unit %s is already in uses (like E2004).'),
    (De: 'Unit %s steht schon im uses des interface (wie E2004).';
     En: 'Unit %s is already in the uses of the interface (like E2004).'),
    (De: 'Typ'; En: 'type'),
    (De: 'Variable'; En: 'variable'),
    (De: 'Konstante'; En: 'constant'),
    (De: 'Routine'; En: 'routine'),
    (De: 'Feld'; En: 'field'),
    (De: 'Methode'; En: 'method'),
    (De: 'Property'; En: 'property'),
    (De: 'Parameter'; En: 'parameter'),
    (De: 'Label'; En: 'label'),
    (De: 'Wert der Aufzählung'; En: 'value of the enumeration'));

{$SCOPEDENUMS OFF}

/// <summary>Art AKind (deutscher Schlüssel aus AddName, z. B. "Feld") in der Sprache der Meldung.</summary>
function KindText(const AKind: string): string;
const
  cKeys: array[0..9] of string = ('Typ', 'Variable', 'Konstante', 'Routine', 'Feld', 'Methode', 'Property',
    'Parameter', 'Label', 'EnumValue');
  cKinds: array[0..9] of TDeclarationsDuplicatesText = (TDeclarationsDuplicatesText.KindType,
    TDeclarationsDuplicatesText.KindVariable, TDeclarationsDuplicatesText.KindConstant,
    TDeclarationsDuplicatesText.KindRoutine, TDeclarationsDuplicatesText.KindField,
    TDeclarationsDuplicatesText.KindMethod, TDeclarationsDuplicatesText.KindProperty,
    TDeclarationsDuplicatesText.KindParameter, TDeclarationsDuplicatesText.KindLabel,
    TDeclarationsDuplicatesText.KindEnumValue);
var
  mIndex: Integer;
begin
  Result := AKind;
  mIndex := IndexStr(AKind, cKeys);
  if mIndex >= 0 then
  begin
    Result := cTexts[cKinds[mIndex]].Text;
  end;
end;

{ TDuplicateDeclarationRule }

function TDuplicateDeclarationRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDuplicateDeclarationRuleId, TRuleSeverity.Error,
    cTexts[TDeclarationsDuplicatesText.Title].Text);
end;

type
  /// <summary>Ein deklarierter Name für duplicate-declaration (#988).</summary>
  TDeclaredName = record
    Name: string;
    /// <summary>Vergleichsschlüssel: Name in Kleinbuchstaben, bei generischen Typen mit Zahl der
    /// Typparameter.</summary>
    Key: string;
    /// <summary>Art für die Meldung: Parameter, Variable, Konstante, Typ, Label, Routine, Feld, Methode,
    /// Property.</summary>
    Kind: string;
    /// <summary>Deklarationsknoten (VarDecl, Field, TypeDecl …) bzw. LabelSection oder UsedUnit.</summary>
    Node: TSyntaxNode;
    /// <summary>Umgebender Abschnitt (VarSection …) oder nil.</summary>
    Section: TSyntaxNode;
    /// <summary>Position unter den Namen des Knotens (A, B: Integer) und deren Zahl.</summary>
    NameIndex: Integer;
    NameCount: Integer;
    Token: Integer;
    Path: string;
    IsRoutine: Boolean;
    /// <summary>Array-Property mit default: Sie darf unter demselben Namen überladen werden (#1380).</summary>
    IsDefaultArray: Boolean;
  end;

procedure TDuplicateDeclarationRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mLines: TArray<string>;
  mLineBreak: string;
  mPaths: TArray<string>;
  mNames: TArray<TDeclaredName>;

  // Erstes Token AName im Knoten ANode; -1 ohne.
  function NameToken(ANode: TSyntaxNode; const AName: string): Integer;
  var
    mIndex: Integer;
  begin
    for mIndex := TokenFrom(mTokens, ANode.StartOffset) to High(mTokens) do
    begin
      if mTokens[mIndex].Offset >= ANode.EndOffset then
      begin
        Break;
      end;
      if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mIndex].Text, AName) then
      begin
        Exit(mIndex);
      end;
    end;
    Result := -1;
  end;

  // Vergleichsschlüssel: TList und TList<T> dürfen nebeneinander stehen.
  function NameKey(ANode: TSyntaxNode; const AName: string): string;
  var
    mGeneric: TSyntaxNode;
  begin
    Result := LowerCase(AName);
    mGeneric := nil;
    if ANode.Kind = TSyntaxKind.TypeDecl then
    begin
      mGeneric := ANode.FindChild(TSyntaxKind.GenericParams);
    end;
    if mGeneric <> nil then
    begin
      Result := Result + '<' + IntToStr(mGeneric.ChildCount) + '>';
    end;
  end;

  // Nimmt AName als einzigen Namen seiner Deklaration auf; False ohne Namen, mit Punkt oder ohne Token.
  function AddName(ANode, ASection: TSyntaxNode; const AName, AKind: string; AToken: Integer;
    AIsRoutine: Boolean): Boolean;
  var
    mEntry: TDeclaredName;
  begin
    Result := (AName <> '') and (Pos('.', AName) = 0) and (AToken >= 0);
    if not Result then
    begin
      Exit;
    end;
    mEntry := Default(TDeclaredName);
    mEntry.Name := AName;
    mEntry.Key := NameKey(ANode, AName);
    mEntry.Kind := AKind;
    mEntry.Node := ANode;
    mEntry.Section := ASection;
    mEntry.NameIndex := 0;
    mEntry.NameCount := 1;
    mEntry.Token := AToken;
    mEntry.Path := TConditionalBranches.PathAt(mPaths, AToken);
    mEntry.IsRoutine := AIsRoutine;
    mNames := mNames + [mEntry];
  end;

  // Der zuletzt aufgenommene Name ist der AIndex-te von ACount Namen einer Liste A, B, C.
  procedure SetListPlace(AIndex, ACount: Integer);
  begin
    mNames[High(mNames)].NameIndex := AIndex;
    mNames[High(mNames)].NameCount := ACount;
  end;

  // A, B: Integer: je Name ein Eintrag; die Token stehen in der Reihenfolge der Namen.
  procedure AddNames(ANode, ASection: TSyntaxNode; const AKind: string);
  var
    mParts: TArray<string>;
    mIndex, mToken, mFrom: Integer;
    mPart: string;
  begin
    mParts := ANode.Name.Split([',']);
    mFrom := TokenFrom(mTokens, ANode.StartOffset);
    for mIndex := 0 to High(mParts) do
    begin
      mToken := mFrom;
      mPart := Trim(mParts[mIndex]);
      while (mToken <= High(mTokens)) and (mTokens[mToken].Offset < ANode.EndOffset) and
        not ((mTokens[mToken].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mToken].Text, mPart)) do
      begin
        Inc(mToken);
      end;
      if (mToken > High(mTokens)) or (mTokens[mToken].Offset >= ANode.EndOffset) then
      begin
        Exit;
      end;
      if AddName(ANode, ASection, mPart, AKind, mToken, False) then
      begin
        SetListPlace(mIndex, Length(mParts));
      end;
      mFrom := mToken + 1;
    end;
  end;

  // Ist das Token AIndex ein Label des Abschnitts (Bezeichner oder Zahl)?
  function IsLabel(AIndex: Integer): Boolean;
  begin
    Result := mTokens[AIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number];
  end;

  // label L1, L2; über die Token.
  procedure AddLabels(ASection: TSyntaxNode);
  var
    mIndex, mCount, mPosition: Integer;
  begin
    mCount := 0;
    for mIndex := TokenFrom(mTokens, ASection.StartOffset) to High(mTokens) do
    begin
      if mTokens[mIndex].Offset >= ASection.EndOffset then
      begin
        Break;
      end;
      if IsLabel(mIndex) then
      begin
        Inc(mCount);
      end;
    end;
    mPosition := 0;
    for mIndex := TokenFrom(mTokens, ASection.StartOffset) to High(mTokens) do
    begin
      if mTokens[mIndex].Offset >= ASection.EndOffset then
      begin
        Break;
      end;
      if IsLabel(mIndex) then
      begin
        if AddName(ASection, ASection, mTokens[mIndex].Text, 'Label', mIndex, False) then
        begin
          SetListPlace(mPosition, mCount);
        end;
        Inc(mPosition);
      end;
    end;
  end;

  // Deklarationen der Art AKind im Abschnitt ASection als AName (Variable, Konstante, Feld).
  procedure AddDecls(ASection: TSyntaxNode; AKind: TSyntaxKind; const AName: string);
  var
    mInner: Integer;
  begin
    for mInner := 0 to ASection.ChildCount - 1 do
    begin
      if ASection[mInner].Kind = AKind then
      begin
        AddNames(ASection[mInner], ASection, AName);
      end;
    end;
  end;

  // Typen eines type-Abschnitts. Die Vorwärtsdeklaration TFoo = class; und ihre volle Deklaration sind ein Typ.
  procedure AddTypes(ASection: TSyntaxNode);
  var
    mInner: Integer;
    mDecl: TSyntaxNode;
  begin
    for mInner := 0 to ASection.ChildCount - 1 do
    begin
      mDecl := ASection[mInner];
      if (mDecl.Kind = TSyntaxKind.TypeDecl) and (mDecl.FindChild(TSyntaxKind.ForwardType) = nil) then
      begin
        AddName(mDecl, ASection, mDecl.Name, 'Typ', NameToken(mDecl, mDecl.Name), False);
      end;
    end;
  end;

  // Ein Deklarationsabschnitt, eine Routine oder Labels.
  procedure AddSection(AChild: TSyntaxNode);
  var
    mHeader: TSyntaxNode;
  begin
    case AChild.Kind of
      TSyntaxKind.VarSection:
        AddDecls(AChild, TSyntaxKind.VarDecl, 'Variable');
      TSyntaxKind.ConstSection:
        AddDecls(AChild, TSyntaxKind.ConstDecl, 'Konstante');
      TSyntaxKind.TypeSection:
        AddTypes(AChild);
      TSyntaxKind.LabelSection:
        AddLabels(AChild);
      TSyntaxKind.RoutineDecl:
        begin
          mHeader := AChild.FindChild(TSyntaxKind.RoutineHeader);
          if mHeader <> nil then
          begin
            AddName(AChild, nil, mHeader.Name, 'Routine', NameToken(mHeader, mHeader.Name), True);
          end;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  procedure AddSections(ANode: TSyntaxNode);
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      AddSection(ANode[mIndex]);
    end;
  end;

  // property Items[I: Integer]: T read Get; default;  "default" folgt auf ein Semikolon.
  function DefaultArrayProperty(ANode: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
  begin
    Result := False;
    if ANode.FindChild(TSyntaxKind.Parameters) = nil then
    begin
      Exit;
    end;
    for mIndex := TokenFrom(mTokens, ANode.StartOffset) to High(mTokens) - 1 do
    begin
      if mTokens[mIndex].Offset >= ANode.EndOffset then
      begin
        Break;
      end;
      if mTokens[mIndex].IsSymbol(';') and SameText(mTokens[mIndex + 1].Text, 'default') then
      begin
        Exit(True);
      end;
    end;
  end;

  // Ein Mitglied eines Typs; Teile mit eigenen Mitgliedern (varianter Teil, Sichtbarkeit) kommen auf APending.
  procedure AddMember(AChild: TSyntaxNode; APending: TStack<TSyntaxNode>);
  var
    mInner: Integer;
  begin
    case AChild.Kind of
      TSyntaxKind.Field:
        AddNames(AChild, nil, 'Feld');
      TSyntaxKind.RoutineHeader:
        AddName(AChild, nil, AChild.Name, 'Methode', NameToken(AChild, AChild.Name), True);
      TSyntaxKind.PropertyDecl:
        if AddName(AChild, nil, AChild.Name, 'Property', NameToken(AChild, AChild.Name), False) then
        begin
          mNames[High(mNames)].IsDefaultArray := DefaultArrayProperty(AChild);
        end;
      TSyntaxKind.VarSection:
        AddDecls(AChild, TSyntaxKind.VarDecl, 'Feld');
      TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
        AddSection(AChild);
      // Varianter Teil: Selektorfeld und die Felder der Zweige gehören zum Record.
      TSyntaxKind.VariantPart, TSyntaxKind.CaseItem, TSyntaxKind.Visibility:
        for mInner := AChild.ChildCount - 1 downto 0 do
        begin
          APending.Push(AChild[mInner]);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  procedure AddMembers(ABody: TSyntaxNode);
  var
    mIndex: Integer;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht): Vorordnung, die Namen kommen in derselben Reihenfolge dazu.
    mPending := TStack<TSyntaxNode>.Create;
    try
      for mIndex := ABody.ChildCount - 1 downto 0 do
      begin
        mPending.Push(ABody[mIndex]);
      end;
      while mPending.Count > 0 do
      begin
        AddMember(mPending.Pop, mPending);
      end;
    finally
      mPending.Free;
    end;
  end;

  // Löscht die Zeilen von ANode, wenn er allein auf ihnen steht.
  function LinesEdit(ANode: TSyntaxNode; out AEdit: TRuleEdit): Boolean;
  begin
    Result := BlankBefore(mLines, ANode.StartPos) and BlankAfter(mLines, ANode.EndPos) and
      (ANode.EndPos.Line + 1 < Length(mLines));
    if Result then
    begin
      AEdit := TRuleEdit.Create(TTextRange.Create(ANode.StartPos.Line, 0, ANode.EndPos.Line + 1, 0), '');
    end;
  end;

  // Erster Name hinter dem Komma nach AToken (Kommentare übersprungen); hinter dem Ende, wenn keiner.
  function NextName(AToken: Integer): Integer;
  begin
    Result := AToken + 1;
    while (Result <= High(mTokens)) and not mTokens[Result].IsSymbol(',') do
    begin
      Inc(Result);
    end;
    Inc(Result);
    while (Result <= High(mTokens)) and (mTokens[Result].Kind = TPascalTokenKind.Comment) do
    begin
      Inc(Result);
    end;
  end;

  // Letzter Name vor dem Komma vor AToken (Kommentare übersprungen); negativ, wenn keiner.
  function PreviousName(AToken: Integer): Integer;
  begin
    Result := AToken - 1;
    while (Result >= 0) and not mTokens[Result].IsSymbol(',') do
    begin
      Dec(Result);
    end;
    Dec(Result);
    while (Result >= 0) and (mTokens[Result].Kind = TPascalTokenKind.Comment) do
    begin
      Dec(Result);
    end;
  end;

  // Name aus einer Liste A, B, C: "B, " bis zum nächsten Namen bzw. ", C" ab dem Ende des Namens davor.
  function ListEdit(const AEntry: TDeclaredName; out AEdit: TRuleEdit): Boolean;
  var
    mOther: Integer;
  begin
    AEdit := Default(TRuleEdit);
    if AEntry.NameIndex < AEntry.NameCount - 1 then
    begin
      mOther := NextName(AEntry.Token);
      Result := mOther <= High(mTokens);
      if Result then
      begin
        AEdit := TRuleEdit.Create(TTextRange.Create(mTokens[AEntry.Token].StartPos, mTokens[mOther].StartPos), '');
      end;
    end
    else
    begin
      mOther := PreviousName(AEntry.Token);
      Result := mOther >= 0;
      if Result then
      begin
        AEdit := TRuleEdit.Create(TTextRange.Create(mTokens[mOther].EndPos, mTokens[AEntry.Token].EndPos), '');
      end;
    end;
  end;

  // Name aus einer Liste A, B, C bzw. ganze Deklaration (samt Abschnitt, wenn sie dessen einzige ist).
  function RemovalFix(const AEntry: TDeclaredName; out AFix: TRuleFix): Boolean;
  var
    mEdit: TRuleEdit;
  begin
    if AEntry.NameCount > 1 then
    begin
      Result := ListEdit(AEntry, mEdit);
    end
    else if (AEntry.Section <> nil) and (AEntry.Section.ChildCount = 1) then
    begin
      // Einzige Deklaration: der Abschnitt (var, const, type, label) geht mit.
      Result := LinesEdit(AEntry.Section, mEdit);
    end
    else
    begin
      Result := LinesEdit(AEntry.Node, mEdit);
    end;
    AFix := Default(TRuleFix);
    if Result then
    begin
      AFix := TRuleFix.Create(cTexts[TDeclarationsDuplicatesText.RemoveSecond].Text, [mEdit]);
    end;
  end;

  // Deklariert ALater denselben Namen wie AEarlier im selben Bereich? Überladene Routinen zählen nicht,
  // überladene default-Properties prüft default-property-invalid (wie E2131).
  function Clashes(const ALater, AEarlier: TDeclaredName): Boolean;
  begin
    Result := (AEarlier.Key = ALater.Key) and not (AEarlier.IsRoutine and ALater.IsRoutine);
    Result := Result and not (AEarlier.IsDefaultArray and ALater.IsDefaultArray) and
      TConditionalBranches.Implies(ALater.Path, AEarlier.Path);
  end;

  // Lässt sich die Deklaration AEntry entfernen (kein Parameter, keine Routine, keine Property)?
  function Removable(const AEntry: TDeclaredName): Boolean;
  begin
    Result := (AEntry.Kind <> 'Parameter') and not AEntry.IsRoutine and (AEntry.Kind <> 'Property') and
      (AEntry.Kind <> 'EnumValue');
  end;

  procedure CheckNames;
  var
    mLater, mEarlier: Integer;
    mFix: TRuleFix;
    mFixes: TArray<TRuleFix>;
  begin
    for mLater := 1 to High(mNames) do
    begin
      for mEarlier := 0 to mLater - 1 do
      begin
        if Clashes(mNames[mLater], mNames[mEarlier]) then
        begin
          mFixes := nil;
          if Removable(mNames[mLater]) and RemovalFix(mNames[mLater], mFix) then
          begin
            mFixes := [mFix];
          end;
          AReport.Add(TTextRange.Create(mTokens[mNames[mLater].Token].StartPos, mTokens[mNames[mLater].Token].EndPos),
            cTexts[TDeclarationsDuplicatesText.AlreadyDeclared].Fmt([mNames[mLater].Name,
              KindText(mNames[mEarlier].Kind)]),
            TRuleConfidence.High, mFixes);
          Break;
        end;
      end;
    end;
  end;

  procedure CheckRoutine(ADecl: TSyntaxNode);
  var
    mHeader, mParameters: TSyntaxNode;
    mIndex: Integer;
  begin
    // Nur Rümpfe: Parameter und lokale Deklarationen teilen einen Bereich.
    if ADecl.FindChild(TSyntaxKind.Block) = nil then
    begin
      Exit;
    end;
    mNames := nil;
    mHeader := ADecl.FindChild(TSyntaxKind.RoutineHeader);
    if mHeader <> nil then
    begin
      mParameters := mHeader.FindChild(TSyntaxKind.Parameters);
      if mParameters <> nil then
      begin
        for mIndex := 0 to mParameters.ChildCount - 1 do
        begin
          if mParameters[mIndex].Kind = TSyntaxKind.Parameter then
          begin
            AddNames(mParameters[mIndex], nil, 'Parameter');
          end;
        end;
      end;
    end;
    AddSections(ADecl);
    CheckNames;
  end;

  // uses-Klauseln der Datei in Textreihenfolge: interface und implementation zusammen.
  function UsesClauses(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
  var
    mInner: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    Result := nil;
    // Iterativ (tiefe Bäume sprengen den Stapel nicht); Vorordnung, die Klauseln bleiben in Textreihenfolge.
    mPending := TStack<TSyntaxNode>.Create;
    try
      for mInner := ARoot.ChildCount - 1 downto 0 do
      begin
        mPending.Push(ARoot[mInner]);
      end;
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.UsesClause then
        begin
          Result := Result + [mNode];
        end
        else if mNode.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
        begin
          for mInner := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode[mInner]);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  // Alle uses-Einträge der Datei.
  function UsedUnits: TArray<TSyntaxNode>;
  var
    mClause: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := nil;
    for mClause in UsesClauses(AContext.Tree.Root) do
    begin
      for mIndex := 0 to mClause.ChildCount - 1 do
      begin
        if mClause[mIndex].Kind = TSyntaxKind.UsedUnit then
        begin
          Result := Result + [mClause[mIndex]];
        end;
      end;
    end;
  end;

  // Nennt ALater dieselbe Unit wie AEarlier, und wird AEarlier immer mit übersetzt?
  function SameUnit(ALater, AEarlier: TSyntaxNode): Boolean;
  begin
    Result := SameText(AEarlier.Name, ALater.Name) and TConditionalBranches.Implies(TConditionalBranches.PathAt(
      mPaths, TokenFrom(mTokens, ALater.StartOffset)), TConditionalBranches.PathAt(mPaths, TokenFrom(mTokens,
      AEarlier.StartOffset)));
  end;

  // uses-Einträge direkt vor und hinter AEntry in seiner Klausel; nil, wo keiner steht.
  procedure Neighbours(AEntry: TSyntaxNode; out APrevious, ANext: TSyntaxNode);
  var
    mClause: TSyntaxNode;
    mIndex: Integer;
  begin
    APrevious := nil;
    ANext := nil;
    mClause := AEntry.Parent;
    mIndex := mClause.ChildCount - 1;
    while (mIndex >= 0) and (mClause[mIndex] <> AEntry) do
    begin
      Dec(mIndex);
    end;
    if (mIndex > 0) and (mClause[mIndex - 1].Kind = TSyntaxKind.UsedUnit) then
    begin
      APrevious := mClause[mIndex - 1];
    end;
    if (mIndex >= 0) and (mIndex < mClause.ChildCount - 1) and (mClause[mIndex + 1].Kind = TSyntaxKind.UsedUnit) then
    begin
      ANext := mClause[mIndex + 1];
    end;
  end;

  // ", X" bzw. "X, " entfernen; der einzige Eintrag nimmt die ganze uses-Klausel mit.
  function UsesFixes(AEntry: TSyntaxNode): TArray<TRuleFix>;
  var
    mPrevious, mNext: TSyntaxNode;
    mEdit: TRuleEdit;
  begin
    Result := nil;
    Neighbours(AEntry, mPrevious, mNext);
    if mPrevious <> nil then
    begin
      Result := [TRuleFix.Create(cTexts[TDeclarationsDuplicatesText.RemoveDuplicate].Text,
        [TRuleEdit.Create(TTextRange.Create(
        mPrevious.EndPos, AEntry.EndPos), '')], True)];
    end
    else if mNext <> nil then
    begin
      Result := [TRuleFix.Create(cTexts[TDeclarationsDuplicatesText.RemoveDuplicate].Text,
        [TRuleEdit.Create(TTextRange.Create(
        AEntry.StartPos, mNext.StartPos), '')], True)];
    end
    else if LinesEdit(AEntry.Parent, mEdit) then
    begin
      Result := [TRuleFix.Create(cTexts[TDeclarationsDuplicatesText.RemoveDuplicate].Text, [mEdit], True)];
    end;
  end;

  procedure ReportUses(ALater, AEarlier: TSyntaxNode);
  var
    mRange: TTextRange;
  begin
    mRange := TTextRange.Create(ALater.StartPos, ALater.EndPos);
    if AEarlier.Parent = ALater.Parent then
    begin
      AReport.Add(mRange, cTexts[TDeclarationsDuplicatesText.UnitTwice].Fmt([ALater.Name]), TRuleConfidence.High,
        UsesFixes(ALater));
    end
    else
    begin
      AReport.Add(mRange, cTexts[TDeclarationsDuplicatesText.UnitInInterface].Fmt([ALater.Name]),
        TRuleConfidence.High, UsesFixes(ALater));
    end;
  end;

  // uses-Einträge der Datei: interface und implementation zusammen.
  procedure CheckUses;
  var
    mLater, mEarlier: Integer;
    mEntries: TArray<TSyntaxNode>;
  begin
    mEntries := UsedUnits;
    for mLater := 1 to High(mEntries) do
    begin
      for mEarlier := 0 to mLater - 1 do
      begin
        if SameUnit(mEntries[mLater], mEntries[mEarlier]) then
        begin
          ReportUses(mEntries[mLater], mEntries[mEarlier]);
          Break;
        end;
      end;
    end;
  end;

  // Abschnitte von interface und implementation einer Unit.
  procedure AddUnitSections(AUnit: TSyntaxNode);
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to AUnit.ChildCount - 1 do
    begin
      if AUnit[mIndex].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
      begin
        AddSections(AUnit[mIndex]);
      end;
    end;
  end;

  // (rot, gruen = rot, blau): Bezeichner direkt nach "(" oder "," sind Werte, die übrigen gehören zu Ausdrücken.
  procedure AddEnumValues(AEnum: TSyntaxNode);
  var
    mIndex, mToken, mBefore: Integer;
  begin
    for mIndex := 0 to AEnum.ChildCount - 1 do
    begin
      if AEnum[mIndex].Kind <> TSyntaxKind.Identifier then
      begin
        Continue;
      end;
      mToken := TokenFrom(mTokens, AEnum[mIndex].StartOffset);
      mBefore := mToken - 1;
      while (mBefore >= 0) and (mTokens[mBefore].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
      begin
        Dec(mBefore);
      end;
      if (mBefore >= 0) and (mToken <= High(mTokens)) and (mTokens[mToken].Kind = TPascalTokenKind.Identifier) and
        (mTokens[mBefore].IsSymbol('(') or mTokens[mBefore].IsSymbol(',')) then
      begin
        AddName(AEnum, nil, mTokens[mToken].Text, 'EnumValue', mToken, False);
      end;
    end;
  end;

  // Prüft den Bereich ANode, wenn er einer ist (Routine, Typ, Aufzählung, Unit, Programm, Bibliothek).
  procedure CheckNode(ANode: TSyntaxNode);
  begin
    case ANode.Kind of
      TSyntaxKind.RoutineDecl:
        CheckRoutine(ANode);
      TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.InterfaceType,
      TSyntaxKind.HelperType:
        begin
          mNames := nil;
          AddMembers(ANode);
          CheckNames;
        end;
      TSyntaxKind.EnumType:
        begin
          mNames := nil;
          AddEnumValues(ANode);
          CheckNames;
        end;
      TSyntaxKind.UnitFile:
        begin
          mNames := nil;
          AddUnitSections(ANode);
          CheckNames;
        end;
      TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile:
        begin
          mNames := nil;
          AddSections(ANode);
          CheckNames;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        CheckNode(mNode);
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
  mPaths := TConditionalBranches.Paths(mTokens);
  Visit(AContext.Tree.Root);
  if TRuleOptions.Bool(AContext.Options, 'checkUses', True) then
  begin
    CheckUses;
  end;
  mNames := nil;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Declarations.Duplicates', cTexts);

end.
