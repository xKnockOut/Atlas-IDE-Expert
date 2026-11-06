unit Atlas.Common.Rules.Builtin.Declarations.Duplicates;

// Regel duplicate-declaration aus Atlas.Common.Rules.Builtin.Declarations (#988, wie E2004): Bezeichner im
// selben Bereich zweimal deklariert (Parameter und lokale Deklarationen, Mitglieder eines Typs, die Unit über
// interface und implementation, uses (#1000, wie E2291), Zuordnung IFoo.Bar = Baz für ein nicht genanntes
// Interface (wie E2265)).

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
  DuplicateDeclarationRuleId = 'duplicate-declaration';

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Rules.Builtin.Declarations.Shared,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDeclarationsDuplicatesText = (Title, RemoveSecond, AlreadyDeclared, RemoveDuplicate, UnitTwice, UnitInInterface,
    KindType, KindVariable, KindConstant, KindRoutine, KindField, KindMethod, KindProperty, KindParameter, KindLabel);

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
    (De: 'Label'; En: 'label'));

{$SCOPEDENUMS OFF}

/// <summary>Art AKind (deutscher Schlüssel aus AddName, z. B. "Feld") in der Sprache der Meldung.</summary>
function KindText(const AKind: string): string;
const
  cKeys: array[0..8] of string = ('Typ', 'Variable', 'Konstante', 'Routine', 'Feld', 'Methode', 'Property',
    'Parameter', 'Label');
  cKinds: array[0..8] of TDeclarationsDuplicatesText = (TDeclarationsDuplicatesText.KindType,
    TDeclarationsDuplicatesText.KindVariable, TDeclarationsDuplicatesText.KindConstant,
    TDeclarationsDuplicatesText.KindRoutine, TDeclarationsDuplicatesText.KindField,
    TDeclarationsDuplicatesText.KindMethod, TDeclarationsDuplicatesText.KindProperty,
    TDeclarationsDuplicatesText.KindParameter, TDeclarationsDuplicatesText.KindLabel);
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
  Result := TRuleDescriptor.Create(DuplicateDeclarationRuleId, TRuleSeverity.Error,
    cTexts[TDeclarationsDuplicatesText.Title].Text);
end;

type
  /// <summary>Ein deklarierter Name für duplicate-declaration (#988).</summary>
  TDeclaredName = record
    Name: string;
    /// <summary>Vergleichsschlüssel: Name in Kleinbuchstaben, bei generischen Typen mit Zahl der Typparameter.</summary>
    Key: string;
    /// <summary>Art für die Meldung: Parameter, Variable, Konstante, Typ, Label, Routine, Feld, Methode, Property.</summary>
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
  Tokens: TArray<TPascalToken>;
  Lines: TArray<string>;
  LineBreak: string;
  Paths: TArray<string>;
  Names: TArray<TDeclaredName>;

  // Erstes Token AName im Knoten ANode; -1 ohne.
  function NameToken(ANode: TSyntaxNode; const AName: string): Integer;
  var
    Index: Integer;
  begin
    for Index := TokenAtOffset(Tokens, ANode.StartOffset) to High(Tokens) do
    begin
      if Tokens[Index].Offset >= ANode.EndOffset then
      begin
        Break;
      end;
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AName) then
      begin
        Exit(Index);
      end;
    end;
    Result := -1;
  end;

  // Vergleichsschlüssel: TList und TList<T> dürfen nebeneinander stehen.
  function NameKey(ANode: TSyntaxNode; const AName: string): string;
  var
    Generic: TSyntaxNode;
  begin
    Result := LowerCase(AName);
    Generic := nil;
    if ANode.Kind = TSyntaxKind.TypeDecl then
    begin
      Generic := ANode.FindChild(TSyntaxKind.GenericParams);
    end;
    if Generic <> nil then
    begin
      Result := Result + '<' + IntToStr(Generic.ChildCount) + '>';
    end;
  end;

  // Nimmt AName als einzigen Namen seiner Deklaration auf; False ohne Namen, mit Punkt oder ohne Token.
  function AddName(ANode, ASection: TSyntaxNode; const AName, AKind: string; AToken: Integer;
    AIsRoutine: Boolean): Boolean;
  var
    Entry: TDeclaredName;
  begin
    Result := (AName <> '') and (Pos('.', AName) = 0) and (AToken >= 0);
    if not Result then
    begin
      Exit;
    end;
    Entry := Default(TDeclaredName);
    Entry.Name := AName;
    Entry.Key := NameKey(ANode, AName);
    Entry.Kind := AKind;
    Entry.Node := ANode;
    Entry.Section := ASection;
    Entry.NameIndex := 0;
    Entry.NameCount := 1;
    Entry.Token := AToken;
    Entry.Path := TConditionalBranches.PathAt(Paths, AToken);
    Entry.IsRoutine := AIsRoutine;
    Names := Names + [Entry];
  end;

  // Der zuletzt aufgenommene Name ist der AIndex-te von ACount Namen einer Liste A, B, C.
  procedure SetListPlace(AIndex, ACount: Integer);
  begin
    Names[High(Names)].NameIndex := AIndex;
    Names[High(Names)].NameCount := ACount;
  end;

  // A, B: Integer: je Name ein Eintrag; die Token stehen in der Reihenfolge der Namen.
  procedure AddNames(ANode, ASection: TSyntaxNode; const AKind: string);
  var
    Parts: TArray<string>;
    Index, Token, From: Integer;
  begin
    Parts := ANode.Name.Split([',']);
    From := TokenAtOffset(Tokens, ANode.StartOffset);
    for Index := 0 to High(Parts) do
    begin
      Token := From;
      while (Token <= High(Tokens)) and (Tokens[Token].Offset < ANode.EndOffset) and
        not ((Tokens[Token].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Token].Text, Trim(Parts[Index]))) do
      begin
        Inc(Token);
      end;
      if (Token > High(Tokens)) or (Tokens[Token].Offset >= ANode.EndOffset) then
      begin
        Exit;
      end;
      if AddName(ANode, ASection, Trim(Parts[Index]), AKind, Token, False) then
      begin
        SetListPlace(Index, Length(Parts));
      end;
      From := Token + 1;
    end;
  end;

  // Ist das Token AIndex ein Label des Abschnitts (Bezeichner oder Zahl)?
  function IsLabel(AIndex: Integer): Boolean;
  begin
    Result := Tokens[AIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number];
  end;

  // label L1, L2; über die Token.
  procedure AddLabels(ASection: TSyntaxNode);
  var
    Index, Count, Position: Integer;
  begin
    Count := 0;
    for Index := TokenAtOffset(Tokens, ASection.StartOffset) to High(Tokens) do
    begin
      if Tokens[Index].Offset >= ASection.EndOffset then
      begin
        Break;
      end;
      if IsLabel(Index) then
      begin
        Inc(Count);
      end;
    end;
    Position := 0;
    for Index := TokenAtOffset(Tokens, ASection.StartOffset) to High(Tokens) do
    begin
      if Tokens[Index].Offset >= ASection.EndOffset then
      begin
        Break;
      end;
      if IsLabel(Index) then
      begin
        if AddName(ASection, ASection, Tokens[Index].Text, 'Label', Index, False) then
        begin
          SetListPlace(Position, Count);
        end;
        Inc(Position);
      end;
    end;
  end;

  // Deklarationen der Art AKind im Abschnitt ASection als AName (Variable, Konstante, Feld).
  procedure AddDecls(ASection: TSyntaxNode; AKind: TSyntaxKind; const AName: string);
  var
    Inner: Integer;
  begin
    for Inner := 0 to ASection.ChildCount - 1 do
    begin
      if ASection[Inner].Kind = AKind then
      begin
        AddNames(ASection[Inner], ASection, AName);
      end;
    end;
  end;

  // Typen eines type-Abschnitts. Die Vorwärtsdeklaration TFoo = class; und ihre volle Deklaration sind ein Typ.
  procedure AddTypes(ASection: TSyntaxNode);
  var
    Inner: Integer;
    Decl: TSyntaxNode;
  begin
    for Inner := 0 to ASection.ChildCount - 1 do
    begin
      Decl := ASection[Inner];
      if (Decl.Kind = TSyntaxKind.TypeDecl) and (Decl.FindChild(TSyntaxKind.ForwardType) = nil) then
      begin
        AddName(Decl, ASection, Decl.Name, 'Typ', NameToken(Decl, Decl.Name), False);
      end;
    end;
  end;

  // Ein Deklarationsabschnitt, eine Routine oder Labels.
  procedure AddSection(AChild: TSyntaxNode);
  var
    Header: TSyntaxNode;
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
          Header := AChild.FindChild(TSyntaxKind.RoutineHeader);
          if Header <> nil then
          begin
            AddName(AChild, nil, Header.Name, 'Routine', NameToken(Header, Header.Name), True);
          end;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  procedure AddSections(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      AddSection(ANode[Index]);
    end;
  end;

  // property Items[I: Integer]: T read Get; default;  "default" folgt auf ein Semikolon.
  function DefaultArrayProperty(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    Result := False;
    if ANode.FindChild(TSyntaxKind.Parameters) = nil then
    begin
      Exit;
    end;
    for Index := TokenAtOffset(Tokens, ANode.StartOffset) to High(Tokens) - 1 do
    begin
      if Tokens[Index].Offset >= ANode.EndOffset then
      begin
        Break;
      end;
      if Tokens[Index].IsSymbol(';') and SameText(Tokens[Index + 1].Text, 'default') then
      begin
        Exit(True);
      end;
    end;
  end;

  // Ein Mitglied eines Typs; Teile mit eigenen Mitgliedern (varianter Teil, Sichtbarkeit) kommen auf APending.
  procedure AddMember(AChild: TSyntaxNode; APending: TStack<TSyntaxNode>);
  var
    Inner: Integer;
  begin
    case AChild.Kind of
      TSyntaxKind.Field:
        AddNames(AChild, nil, 'Feld');
      TSyntaxKind.RoutineHeader:
        AddName(AChild, nil, AChild.Name, 'Methode', NameToken(AChild, AChild.Name), True);
      TSyntaxKind.PropertyDecl:
        if AddName(AChild, nil, AChild.Name, 'Property', NameToken(AChild, AChild.Name), False) then
        begin
          Names[High(Names)].IsDefaultArray := DefaultArrayProperty(AChild);
        end;
      TSyntaxKind.VarSection:
        AddDecls(AChild, TSyntaxKind.VarDecl, 'Feld');
      TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
        AddSection(AChild);
      // Varianter Teil: Selektorfeld und die Felder der Zweige gehören zum Record.
      TSyntaxKind.VariantPart, TSyntaxKind.CaseItem, TSyntaxKind.Visibility:
        for Inner := AChild.ChildCount - 1 downto 0 do
        begin
          APending.Push(AChild[Inner]);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  procedure AddMembers(ABody: TSyntaxNode);
  var
    Index: Integer;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1): Vorordnung, die Namen kommen in derselben Reihenfolge dazu.
    Pending := TStack<TSyntaxNode>.Create;
    try
      for Index := ABody.ChildCount - 1 downto 0 do
      begin
        Pending.Push(ABody[Index]);
      end;
      while Pending.Count > 0 do
      begin
        AddMember(Pending.Pop, Pending);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Löscht die Zeilen von ANode, wenn er allein auf ihnen steht.
  function LinesEdit(ANode: TSyntaxNode; out AEdit: TRuleEdit): Boolean;
  begin
    Result := BlankBefore(Lines, ANode.StartPos) and BlankAfter(Lines, ANode.EndPos) and
      (ANode.EndPos.Line + 1 < Length(Lines));
    if Result then
    begin
      AEdit := TRuleEdit.Create(TTextRange.Create(ANode.StartPos.Line, 0, ANode.EndPos.Line + 1, 0), '');
    end;
  end;

  // Erster Name hinter dem Komma nach AToken (Kommentare übersprungen); hinter dem Ende, wenn keiner.
  function NextName(AToken: Integer): Integer;
  begin
    Result := AToken + 1;
    while (Result <= High(Tokens)) and not Tokens[Result].IsSymbol(',') do
    begin
      Inc(Result);
    end;
    Inc(Result);
    while (Result <= High(Tokens)) and (Tokens[Result].Kind = TPascalTokenKind.Comment) do
    begin
      Inc(Result);
    end;
  end;

  // Letzter Name vor dem Komma vor AToken (Kommentare übersprungen); negativ, wenn keiner.
  function PreviousName(AToken: Integer): Integer;
  begin
    Result := AToken - 1;
    while (Result >= 0) and not Tokens[Result].IsSymbol(',') do
    begin
      Dec(Result);
    end;
    Dec(Result);
    while (Result >= 0) and (Tokens[Result].Kind = TPascalTokenKind.Comment) do
    begin
      Dec(Result);
    end;
  end;

  // Name aus einer Liste A, B, C: "B, " bis zum nächsten Namen bzw. ", C" ab dem Ende des Namens davor.
  function ListEdit(const AEntry: TDeclaredName; out AEdit: TRuleEdit): Boolean;
  var
    Other: Integer;
  begin
    AEdit := Default(TRuleEdit);
    if AEntry.NameIndex < AEntry.NameCount - 1 then
    begin
      Other := NextName(AEntry.Token);
      Result := Other <= High(Tokens);
      if Result then
      begin
        AEdit := TRuleEdit.Create(TTextRange.Create(Tokens[AEntry.Token].StartPos, Tokens[Other].StartPos), '');
      end;
    end
    else
    begin
      Other := PreviousName(AEntry.Token);
      Result := Other >= 0;
      if Result then
      begin
        AEdit := TRuleEdit.Create(TTextRange.Create(Tokens[Other].EndPos, Tokens[AEntry.Token].EndPos), '');
      end;
    end;
  end;

  // Name aus einer Liste A, B, C bzw. ganze Deklaration (samt Abschnitt, wenn sie dessen einzige ist).
  function RemovalFix(const AEntry: TDeclaredName; out AFix: TRuleFix): Boolean;
  var
    Edit: TRuleEdit;
  begin
    if AEntry.NameCount > 1 then
    begin
      Result := ListEdit(AEntry, Edit);
    end
    else if (AEntry.Section <> nil) and (AEntry.Section.ChildCount = 1) then
    begin
      // Einzige Deklaration: der Abschnitt (var, const, type, label) geht mit.
      Result := LinesEdit(AEntry.Section, Edit);
    end
    else
    begin
      Result := LinesEdit(AEntry.Node, Edit);
    end;
    AFix := Default(TRuleFix);
    if Result then
    begin
      AFix := TRuleFix.Create(cTexts[TDeclarationsDuplicatesText.RemoveSecond].Text, [Edit]);
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
    Result := (AEntry.Kind <> 'Parameter') and not AEntry.IsRoutine and (AEntry.Kind <> 'Property');
  end;

  procedure CheckNames;
  var
    Later, Earlier: Integer;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    for Later := 1 to High(Names) do
    begin
      for Earlier := 0 to Later - 1 do
      begin
        if Clashes(Names[Later], Names[Earlier]) then
        begin
          Fixes := nil;
          if Removable(Names[Later]) and RemovalFix(Names[Later], Fix) then
          begin
            Fixes := [Fix];
          end;
          AReport.Add(TTextRange.Create(Tokens[Names[Later].Token].StartPos, Tokens[Names[Later].Token].EndPos),
            cTexts[TDeclarationsDuplicatesText.AlreadyDeclared].Fmt([Names[Later].Name, KindText(Names[Earlier].Kind)]),
            TRuleConfidence.High, Fixes);
          Break;
        end;
      end;
    end;
  end;

  procedure CheckRoutine(ADecl: TSyntaxNode);
  var
    Header, Parameters: TSyntaxNode;
    Index: Integer;
  begin
    // Nur Rümpfe: Parameter und lokale Deklarationen teilen einen Bereich.
    if ADecl.FindChild(TSyntaxKind.Block) = nil then
    begin
      Exit;
    end;
    Names := nil;
    Header := ADecl.FindChild(TSyntaxKind.RoutineHeader);
    if Header <> nil then
    begin
      Parameters := Header.FindChild(TSyntaxKind.Parameters);
      if Parameters <> nil then
      begin
        for Index := 0 to Parameters.ChildCount - 1 do
        begin
          if Parameters[Index].Kind = TSyntaxKind.Parameter then
          begin
            AddNames(Parameters[Index], nil, 'Parameter');
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
    Inner: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    Result := nil;
    // Iterativ (Bericht M1); Vorordnung, die Klauseln bleiben in Textreihenfolge.
    Pending := TStack<TSyntaxNode>.Create;
    try
      for Inner := ARoot.ChildCount - 1 downto 0 do
      begin
        Pending.Push(ARoot[Inner]);
      end;
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.UsesClause then
        begin
          Result := Result + [Node];
        end
        else if Node.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
        begin
          for Inner := Node.ChildCount - 1 downto 0 do
          begin
            Pending.Push(Node[Inner]);
          end;
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Alle uses-Einträge der Datei.
  function UsedUnits: TArray<TSyntaxNode>;
  var
    Clause: TSyntaxNode;
    Index: Integer;
  begin
    Result := nil;
    for Clause in UsesClauses(AContext.Tree.Root) do
    begin
      for Index := 0 to Clause.ChildCount - 1 do
      begin
        if Clause[Index].Kind = TSyntaxKind.UsedUnit then
        begin
          Result := Result + [Clause[Index]];
        end;
      end;
    end;
  end;

  // Nennt ALater dieselbe Unit wie AEarlier, und wird AEarlier immer mit übersetzt?
  function SameUnit(ALater, AEarlier: TSyntaxNode): Boolean;
  begin
    Result := SameText(AEarlier.Name, ALater.Name) and TConditionalBranches.Implies(TConditionalBranches.PathAt(
      Paths, TokenAtOffset(Tokens, ALater.StartOffset)), TConditionalBranches.PathAt(Paths, TokenAtOffset(Tokens,
      AEarlier.StartOffset)));
  end;

  // uses-Einträge direkt vor und hinter AEntry in seiner Klausel; nil, wo keiner steht.
  procedure Neighbours(AEntry: TSyntaxNode; out APrevious, ANext: TSyntaxNode);
  var
    Clause: TSyntaxNode;
    Index: Integer;
  begin
    APrevious := nil;
    ANext := nil;
    Clause := AEntry.Parent;
    Index := Clause.ChildCount - 1;
    while (Index >= 0) and (Clause[Index] <> AEntry) do
    begin
      Dec(Index);
    end;
    if (Index > 0) and (Clause[Index - 1].Kind = TSyntaxKind.UsedUnit) then
    begin
      APrevious := Clause[Index - 1];
    end;
    if (Index >= 0) and (Index < Clause.ChildCount - 1) and (Clause[Index + 1].Kind = TSyntaxKind.UsedUnit) then
    begin
      ANext := Clause[Index + 1];
    end;
  end;

  // ", X" bzw. "X, " entfernen; der einzige Eintrag nimmt die ganze uses-Klausel mit.
  function UsesFixes(AEntry: TSyntaxNode): TArray<TRuleFix>;
  var
    Previous, Next: TSyntaxNode;
    Edit: TRuleEdit;
  begin
    Result := nil;
    Neighbours(AEntry, Previous, Next);
    if Previous <> nil then
    begin
      Result := [TRuleFix.Create(cTexts[TDeclarationsDuplicatesText.RemoveDuplicate].Text,
        [TRuleEdit.Create(TTextRange.Create(
        Previous.EndPos, AEntry.EndPos), '')], True)];
    end
    else if Next <> nil then
    begin
      Result := [TRuleFix.Create(cTexts[TDeclarationsDuplicatesText.RemoveDuplicate].Text,
        [TRuleEdit.Create(TTextRange.Create(
        AEntry.StartPos, Next.StartPos), '')], True)];
    end
    else if LinesEdit(AEntry.Parent, Edit) then
    begin
      Result := [TRuleFix.Create(cTexts[TDeclarationsDuplicatesText.RemoveDuplicate].Text, [Edit], True)];
    end;
  end;

  procedure ReportUses(ALater, AEarlier: TSyntaxNode);
  var
    Range: TTextRange;
  begin
    Range := TTextRange.Create(ALater.StartPos, ALater.EndPos);
    if AEarlier.Parent = ALater.Parent then
    begin
      AReport.Add(Range, cTexts[TDeclarationsDuplicatesText.UnitTwice].Fmt([ALater.Name]), TRuleConfidence.High,
        UsesFixes(ALater));
    end
    else
    begin
      AReport.Add(Range, cTexts[TDeclarationsDuplicatesText.UnitInInterface].Fmt([ALater.Name]),
        TRuleConfidence.High, UsesFixes(ALater));
    end;
  end;

  // uses-Einträge der Datei: interface und implementation zusammen.
  procedure CheckUses;
  var
    Later, Earlier: Integer;
    Entries: TArray<TSyntaxNode>;
  begin
    Entries := UsedUnits;
    for Later := 1 to High(Entries) do
    begin
      for Earlier := 0 to Later - 1 do
      begin
        if SameUnit(Entries[Later], Entries[Earlier]) then
        begin
          ReportUses(Entries[Later], Entries[Earlier]);
          Break;
        end;
      end;
    end;
  end;

  // Abschnitte von interface und implementation einer Unit.
  procedure AddUnitSections(AUnit: TSyntaxNode);
  var
    Index: Integer;
  begin
    for Index := 0 to AUnit.ChildCount - 1 do
    begin
      if AUnit[Index].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
      begin
        AddSections(AUnit[Index]);
      end;
    end;
  end;

  // Prüft den Bereich ANode, wenn er einer ist (Routine, Typ, Unit, Programm, Bibliothek).
  procedure CheckNode(ANode: TSyntaxNode);
  begin
    case ANode.Kind of
      TSyntaxKind.RoutineDecl:
        CheckRoutine(ANode);
      TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.InterfaceType,
      TSyntaxKind.HelperType:
        begin
          Names := nil;
          AddMembers(ANode);
          CheckNames;
        end;
      TSyntaxKind.UnitFile:
        begin
          Names := nil;
          AddUnitSections(ANode);
          CheckNames;
        end;
      TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile:
        begin
          Names := nil;
          AddSections(ANode);
          CheckNames;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
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
        CheckNode(Node);
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Paths := TConditionalBranches.Paths(Tokens);
  Visit(AContext.Tree.Root);
  if TRuleOptions.Bool(AContext.Options, 'checkUses', True) then
  begin
    CheckUses;
  end;
  Names := nil;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Declarations.Duplicates', cTexts);

end.
