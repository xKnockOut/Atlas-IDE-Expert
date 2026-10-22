unit Atlas.Common.Rules.Builtin.Properties;

// Regeln für Property-Deklarationen (#909, Gruppe Compiler vorab):
//   property-accessor-invalid  Hinter read/write steht nichts Passendes
//                              (#1001): Name fehlt in der Klasse und ihren
//                              Vorfahren (E2168) oder ist eine Property
//                              (E2168), Getter oder Setter mit falscher
//                              Signatur (E2234), Setter mit var-Parameter
//                              (E2282), überladene Zugriffsmethode (E2271),
//                              Klassen-Property mit Instanzmitglied bzw.
//                              nicht statischer Klassenmethode (E2355) und
//                              umgekehrt (E2356), Feld hinter einer Array-
//                              oder index-Property (E2174), Feldselektor über
//                              ein Feld, das kein Record ist (E2459), auf ein
//                              Mitglied, das kein Feld ist (E2461), oder auf
//                              ein fehlendes Feld (E2562).
//   default-property-invalid   default falsch (#1073): an einer Property ohne
//                              Index (E2132), zweite default-Property mit
//                              denselben Indextypen (E2131), Obj[I] auf einer
//                              Klasse ohne default-Property in ihrer ganzen
//                              Vorfahrenkette (E2149, Typ über TNameResolver).
//   property-redeclaration-invalid
//                              property Caption; ohne Property im Vorfahren
//                              (#1074, E2147, Korrektur: ähnlichster Name)
//                              oder dort nicht erreichbar (E2233).
//
// Die Regel liest read/write aus den Token der Property und sucht die Namen
// im Index der Datei und über TAncestry in den Vorfahren. Bricht die Kette der
// Vorfahren ab, steht der Name nur in einem inaktiven Zweig oder sieht die
// Klasse ihn nicht (private einer anderen Unit), bleibt sie still; ebenso in
// Klassen, die Include-Dateien einbinden. Typen vergleicht sie nur, wenn beide
// sicher für sich stehen (eingebaut oder als eigener Typ deklariert).
//
// Korrektur: Folgt der fehlende Name der Konvention F<Name>, Get<Name> oder
// Set<Name>, legt "FName anlegen" bzw. "GetName anlegen" das Mitglied an
// (Erzeuger der Vervollständigung #467, completion.accessorSection).

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  PropertyAccessorInvalidRuleId = 'property-accessor-invalid';
  DefaultPropertyInvalidRuleId = 'default-property-invalid';
  PropertyRedeclarationInvalidRuleId = 'property-redeclaration-invalid';

type
  TPropertyAccessorInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDefaultPropertyInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TPropertyRedeclarationInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterPropertyRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.AccessorCreation,
  Atlas.Text.Fuzzy;

type
  /// <summary>Ein Zugriff hinter read oder write: Name und Feldselektoren, Token von First bis Last.</summary>
  TPropertyAccessor = record
    IsWrite: Boolean;
    Name: string;
    Selectors: TArray<string>;
    First: Integer;
    Last: Integer;
  end;

  /// <summary>Gelesene Property: Indexparameter, Typtext, index-Angabe und Zugriffe.</summary>
  TPropertyShape = record
    Symbol: TIndexSymbol;
    /// <summary>Indexparameter ohne Klammern wie im Quelltext ("Index: Integer"); '' ohne.</summary>
    IndexText: string;
    /// <summary>Typ wie im Quelltext ("TList&lt;TKunde&gt;"); '' bei einer Property ohne Typ.</summary>
    TypeText: string;
    /// <summary>Die Property hat eine index-Angabe (index 3).</summary>
    HasIndex: Boolean;
    IsClass: Boolean;
    SingleLine: Boolean;
    Accessors: TArray<TPropertyAccessor>;
  end;

/// <summary>Bezeichner oder Schlüsselwort mit Text AWord (ohne Groß-/Kleinschreibung)?</summary>
function IsWord(const AToken: TPascalToken; const AWord: string): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and SameText(AToken.Text, AWord);
end;

/// <summary>Modifizierer der Parameter einer Signatur in Reihenfolge ('', const, var, out, constref).</summary>
function ParamModifiers(const ASignature: string): TArray<string>;
var
  Open, Close, Depth, Index, Count: Integer;
  Groups: TArray<string>;
  Group, Head, Modifier: string;
  Start: Integer;
begin
  Result := nil;
  Open := Pos('(', ASignature);
  if Open = 0 then
    Exit;
  Depth := 0;
  Close := 0;
  for Index := Open to Length(ASignature) do
  begin
    if ASignature[Index] = '(' then
      Inc(Depth)
    else if ASignature[Index] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Close := Index;
        Break;
      end;
    end;
  end;
  if Close = 0 then
    Exit;
  Groups := nil;
  Depth := 0;
  Start := Open + 1;
  for Index := Open + 1 to Close do
  begin
    if CharInSet(ASignature[Index], ['(', '[', '<']) then
      Inc(Depth)
    else if CharInSet(ASignature[Index], [']', '>']) or ((ASignature[Index] = ')') and (Index < Close)) then
      Dec(Depth)
    else if ((ASignature[Index] = ';') and (Depth = 0)) or (Index = Close) then
    begin
      Groups := Groups + [Trim(Copy(ASignature, Start, Index - Start))];
      Start := Index + 1;
    end;
  end;
  for Group in Groups do
  begin
    Head := Group;
    if Pos(':', Head) > 0 then
      Head := Copy(Head, 1, Pos(':', Head) - 1);
    Head := Trim(Head);
    Modifier := LowerCase(Copy(Head, 1, Pos(' ', Head + ' ') - 1));
    if MatchText(Modifier, ['const', 'var', 'out', 'constref']) then
      Head := Trim(Copy(Head, Length(Modifier) + 1, MaxInt))
    else
      Modifier := '';
    Count := Length(Head.Split([',']));
    for Index := 1 to Count do
      Result := Result + [Modifier];
  end;
end;

function TPropertyAccessorInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(PropertyAccessorInvalidRuleId, TRuleSeverity.Error,
    'Getter oder Setter einer Property ungültig');
end;

procedure TPropertyAccessorInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Ancestry: TAncestry;
  Tokens: TArray<TPascalToken>;
  Actions: TClassActionContext;

  function Source(AFrom, ATo: Integer): string;
  begin
    Result := Trim(Copy(AContext.Text, Tokens[AFrom].Offset + 1, Tokens[ATo].Offset + Length(Tokens[ATo].Text) -
      Tokens[AFrom].Offset));
  end;

  /// <summary>Property ab dem Token "property" an AStart lesen; False ohne Namen.</summary>
  function Parse(AStart: Integer; out AShape: TPropertyShape): Boolean;
  var
    Index, Depth, Bracket, TypeStart: Integer;
    Accessor: TPropertyAccessor;
  begin
    AShape := Default(TPropertyShape);
    Result := (AStart + 1 <= High(Tokens)) and (Tokens[AStart + 1].Kind = TPascalTokenKind.Identifier);
    if not Result then
      Exit;
    Index := AStart + 2;
    Depth := 0;
    Bracket := -1;
    TypeStart := -1;
    while Index <= High(Tokens) do
    begin
      if Tokens[Index].IsSymbol('[') or Tokens[Index].IsSymbol('(') then
      begin
        if (Depth = 0) and Tokens[Index].IsSymbol('[') and (TypeStart < 0) then
          Bracket := Index;
        Inc(Depth);
      end
      else if Tokens[Index].IsSymbol(']') or Tokens[Index].IsSymbol(')') then
      begin
        Dec(Depth);
        if (Depth = 0) and (Bracket >= 0) and (AShape.IndexText = '') and (Index > Bracket + 1) then
          AShape.IndexText := Source(Bracket + 1, Index - 1);
      end
      else if Depth = 0 then
      begin
        if Tokens[Index].IsSymbol(';') then
          Break;
        if Tokens[Index].IsSymbol(':') and (TypeStart < 0) then
          TypeStart := Index + 1
        else if IsWord(Tokens[Index], 'read') or IsWord(Tokens[Index], 'write') or IsWord(Tokens[Index], 'index') or
          IsWord(Tokens[Index], 'stored') or IsWord(Tokens[Index], 'default') or
          IsWord(Tokens[Index], 'nodefault') or IsWord(Tokens[Index], 'implements') then
        begin
          if (TypeStart > 0) and (AShape.TypeText = '') and (Index > TypeStart) then
            AShape.TypeText := Source(TypeStart, Index - 1);
          if IsWord(Tokens[Index], 'index') then
            AShape.HasIndex := True
          else if (IsWord(Tokens[Index], 'read') or IsWord(Tokens[Index], 'write')) and (Index < High(Tokens)) and
            (Tokens[Index + 1].Kind = TPascalTokenKind.Identifier) then
          begin
            Accessor := Default(TPropertyAccessor);
            Accessor.IsWrite := IsWord(Tokens[Index], 'write');
            Inc(Index);
            Accessor.Name := Tokens[Index].Text;
            Accessor.First := Index;
            while (Index + 2 <= High(Tokens)) and Tokens[Index + 1].IsSymbol('.') and
              (Tokens[Index + 2].Kind = TPascalTokenKind.Identifier) do
            begin
              Inc(Index, 2);
              Accessor.Selectors := Accessor.Selectors + [Tokens[Index].Text];
            end;
            Accessor.Last := Index;
            AShape.Accessors := AShape.Accessors + [Accessor];
          end;
        end;
      end;
      Inc(Index);
    end;
    if (TypeStart > 0) and (AShape.TypeText = '') and (Index > TypeStart) and (Index <= High(Tokens)) then
      AShape.TypeText := Source(TypeStart, Index - 1);
    AShape.SingleLine := (Index <= High(Tokens)) and (Tokens[Index].StartPos.Line = Tokens[AStart].StartPos.Line);
  end;

  /// <summary>Bindet die Klasse AType Include-Dateien ein? Dann kennt die Datei nicht alle Mitglieder.</summary>
  function HasInclude(const AType: TIndexSymbol): Boolean;
  var
    Token: TPascalToken;
    Name: string;
  begin
    for Token in AContext.Tree.Tokens do
      if (Token.Kind = TPascalTokenKind.Directive) and (Token.StartPos.Line >= AType.Range.StartPos.Line) and
        (Token.StartPos.Line <= AType.Range.EndPos.Line) then
      begin
        Name := TDirectiveNames.LeadingName(TDirectiveNames.Body(Token.Text));
        if SameText(Name, 'I') or SameText(Name, 'INCLUDE') then
          Exit(True);
      end;
    Result := False;
  end;

  /// <summary>Typparameter der Klasse und ihrer Vorfahren: Sie passen zu jedem Typ.</summary>
  function Wildcards(const AChain: TArray<TSymbolLocation>): TArray<string>;
  var
    Location: TSymbolLocation;
    Name: string;
  begin
    Result := nil;
    for Location in AChain do
      for Name in Location.Symbol.TypeParams.Split([',']) do
        if Trim(Name) <> '' then
          Result := Result + [Trim(Name)];
  end;

  /// <summary>Mitglieder namens AName auf der nächsten Stufe der Kette, die es dort gibt. False, wenn keine
  /// Aussage möglich ist (Kette bricht ab, nur in inaktivem Zweig, für die Klasse unsichtbar).</summary>
  function Lookup(const AChain: TArray<TSymbolLocation>; AComplete: Boolean; const AName: string;
    out AFound: TArray<TIndexSymbol>): Boolean;
  var
    Level: Integer;
    Symbol: TIndexSymbol;
    Any: Boolean;
  begin
    AFound := nil;
    for Level := 0 to High(AChain) do
    begin
      Any := False;
      for Symbol in Ancestry.Members(AChain[Level]) do
      begin
        if not SameText(Symbol.Name, AName) then
          Continue;
        Any := True;
        if Symbol.Unavailable then
          Exit(False);
        // strict private sieht kein Nachfahre, private nur einer in derselben Unit.
        if (Level > 0) and ((Symbol.Visibility = TIndexVisibility.StrictPrivate) or
          ((AChain[Level].FileName <> '') and (Symbol.Visibility = TIndexVisibility.Private))) then
          Continue;
        AFound := AFound + [Symbol];
      end;
      if Any then
        Exit(AFound <> nil);
    end;
    Result := AComplete;
  end;

  function Range(const AAccessor: TPropertyAccessor): TTextRange;
  begin
    Result := TTextRange.Create(Tokens[AAccessor.First].StartPos, Tokens[AAccessor.Last].EndPos);
  end;

  /// <summary>Korrektur "F/Get/SetName anlegen", wenn der fehlende Name der Konvention folgt.</summary>
  function CreateFixes(const AShape: TPropertyShape; const AAccessor: TPropertyAccessor): TArray<TRuleFix>;
  var
    Plan: TAccessorPlan;
    Action: TCodeAction;
  begin
    Result := nil;
    if (AAccessor.Selectors <> nil) or AShape.IsClass or not AShape.SingleLine or (AShape.TypeText = '') then
      Exit;
    Plan := Default(TAccessorPlan);
    Plan.PropertyName := AShape.Symbol.Name;
    Plan.PropertyType := AShape.TypeText;
    Plan.IndexParameters := AShape.IndexText;
    if AShape.HasIndex then
    begin
      if Plan.IndexParameters <> '' then
        Plan.IndexParameters := Plan.IndexParameters + '; ';
      Plan.IndexParameters := Plan.IndexParameters + 'AIndex: Integer';
    end;
    Plan.MethodSection := 'private';
    if AContext.AccessorsProtected then
      Plan.MethodSection := 'protected';
    if SameText(AAccessor.Name, Plan.FieldName) and (Plan.IndexParameters = '') then
      Plan.Kind := TAccessorKind.Field
    else if not AAccessor.IsWrite and SameText(AAccessor.Name, 'Get' + Plan.PropertyName) then
      Plan.Kind := TAccessorKind.Getter
    else if AAccessor.IsWrite and SameText(AAccessor.Name, 'Set' + Plan.PropertyName) then
      Plan.Kind := TAccessorKind.Setter
    else
      Exit;
    if TClassActions.CreateAccessor(AContext.Text, Tokens[AAccessor.First].StartPos.Line, Plan, Actions, Action) then
      Result := [TRuleFix.Create(Action.Title, Action.Edits)];
  end;

  /// <summary>Erwarteter Kopf der Zugriffsmethode, z. B. "function GetName(Index: Integer): string".</summary>
  function Expected(const AShape: TPropertyShape; const AAccessor: TPropertyAccessor): string;
  var
    Params: string;
  begin
    Params := AShape.IndexText;
    if AShape.HasIndex then
    begin
      if Params <> '' then
        Params := Params + '; ';
      Params := Params + 'AIndex: Integer';
    end;
    if AAccessor.IsWrite then
    begin
      if Params <> '' then
        Params := Params + '; ';
      Result := Format('procedure %s(%sconst Value: %s)', [AAccessor.Name, Params, AShape.TypeText]);
    end
    else if Params <> '' then
      Result := Format('function %s(%s): %s', [AAccessor.Name, Params, AShape.TypeText])
    else
      Result := Format('function %s: %s', [AAccessor.Name, AShape.TypeText]);
    if AShape.IsClass then
      Result := 'class ' + Result + '; static';
  end;

  /// <summary>Passt die Methode AMethod als Getter bzw. Setter? Typen zählen nur, wenn beide sicher sind.</summary>
  function Fits(const AShape: TPropertyShape; const AAccessor: TPropertyAccessor; const AMethod: TIndexSymbol;
    const AWildcards: TArray<string>): Boolean;
  var
    Wanted: TArray<string>;
    Index: Integer;
    Keyword: string;

    function Same(const A, B: string): Boolean;
    begin
      Result := Ancestry.SameType(A, B, AWildcards) or (A = '') or (B = '') or not Ancestry.KnownType(A) or
        not Ancestry.KnownType(B);
    end;

  begin
    Wanted := Copy(AShape.Symbol.ParamTypes);
    if AShape.HasIndex then
      Wanted := Wanted + ['Integer'];
    if AAccessor.IsWrite then
      Wanted := Wanted + [AShape.Symbol.TypeName];
    Keyword := LowerCase(AMethod.Signature);
    if StartsStr('class ', Keyword) then
      Keyword := Trim(Copy(Keyword, 7, MaxInt));
    if AAccessor.IsWrite then
      Result := StartsStr('procedure', Keyword)
    else
      Result := StartsStr('function', Keyword);
    Result := Result and (AMethod.MaxArgs = Length(Wanted)) and (Length(AMethod.ParamTypes) = Length(Wanted));
    if not Result then
      Exit;
    for Index := 0 to High(Wanted) do
      if not Same(Wanted[Index], AMethod.ParamTypes[Index]) then
        Exit(False);
    if not AAccessor.IsWrite then
      Result := Same(AShape.Symbol.TypeName, AMethod.TypeName);
  end;

  /// <summary>Feldselektoren ab dem Feld AField prüfen; True mit Meldung bei einem Fehler.</summary>
  function CheckSelectors(const AAccessor: TPropertyAccessor; const AField: TIndexSymbol): Boolean;
  var
    Current: TIndexSymbol;
    Path, Selector: string;
    Location: TSymbolLocation;
    Member, Hit: TIndexSymbol;
    Found: Boolean;
    Index: Integer;
  begin
    Result := False;
    Current := AField;
    Path := AAccessor.Name;
    for Index := 0 to High(AAccessor.Selectors) do
    begin
      Selector := AAccessor.Selectors[Index];
      if (Current.TypeName = '') or (Current.TypeArgs <> '') or
        not Ancestry.FindAnyType(Copy(Current.TypeName, LastDelimiter('.', Current.TypeName) + 1, MaxInt),
        Location) or (Location.Symbol.Kind = TIndexSymbolKind.TypeAlias) then
        Exit;
      if Location.Symbol.Kind <> TIndexSymbolKind.RecordType then
      begin
        AReport.Add(Range(AAccessor), Format('%s ist vom Typ %s, keinem Record; ein Feldselektor wie %s.%s geht ' +
          'nur über ein Record-Feld (wie E2459).', [Path, Current.TypeName, Path, Selector]), TRuleConfidence.High);
        Exit(True);
      end;
      Found := False;
      Hit := Default(TIndexSymbol);
      for Member in Ancestry.Members(Location) do
        if SameText(Member.Name, Selector) then
        begin
          if Member.Unavailable then
            Exit;
          Found := True;
          Hit := Member;
          Break;
        end;
      if not Found then
      begin
        AReport.Add(Range(AAccessor), Format('%s hat kein Feld %s (wie E2562).', [Location.Symbol.Name, Selector]),
          TRuleConfidence.High);
        Exit(True);
      end;
      if (Hit.Kind <> TIndexSymbolKind.Field) or Hit.HasDirective('class') then
      begin
        AReport.Add(Range(AAccessor), Format('%s.%s ist kein Instanzfeld; hinter dem Punkt muss ein Feld des ' +
          'Records stehen (wie E2461).', [Location.Symbol.Name, Hit.Name]), TRuleConfidence.High);
        Exit(True);
      end;
      Current := Hit;
      Path := Path + '.' + Selector;
    end;
  end;

  procedure CheckAccessor(const AShape: TPropertyShape; const AAccessor: TPropertyAccessor;
    const AChain: TArray<TSymbolLocation>; AComplete: Boolean; const AWildcards: TArray<string>);
  var
    Found: TArray<TIndexSymbol>;
    Symbol: TIndexSymbol;
    Clause, Modifier: string;
    Modifiers: TArray<string>;
  begin
    if not Lookup(AChain, AComplete, AAccessor.Name, Found) then
      Exit;
    Clause := 'read';
    if AAccessor.IsWrite then
      Clause := 'write';
    if Found = nil then
    begin
      AReport.Add(Range(AAccessor), Format('%s ist in %s nicht deklariert (wie E2168).', [AAccessor.Name,
        AChain[0].Symbol.Name]), TRuleConfidence.High, CreateFixes(AShape, AAccessor));
      Exit;
    end;
    Symbol := Found[0];
    if Symbol.Kind = TIndexSymbolKind.Property_ then
    begin
      AReport.Add(Range(AAccessor), Format('%s ist eine Property; hinter %s gehört ein Feld oder eine Methode ' +
        '(wie E2168).', [Symbol.Name, Clause]), TRuleConfidence.High);
      Exit;
    end;
    if Symbol.Kind = TIndexSymbolKind.Field then
    begin
      if (AShape.Symbol.MaxArgs > 0) or AShape.HasIndex then
      begin
        if AShape.HasIndex then
          AReport.Add(Range(AAccessor), Format('Die Property %s hat eine index-Angabe und braucht hinter %s eine ' +
            'Methode; %s ist ein Feld (wie E2174).', [AShape.Symbol.Name, Clause, Symbol.Name]), TRuleConfidence.High)
        else
          AReport.Add(Range(AAccessor), Format('Die Array-Property %s braucht hinter %s eine Methode; %s ist ein ' +
            'Feld (wie E2174).', [AShape.Symbol.Name, Clause, Symbol.Name]), TRuleConfidence.High);
        Exit;
      end;
      if AShape.IsClass and not Symbol.HasDirective('class') then
      begin
        AReport.Add(Range(AAccessor), Format('Die Klassen-Property %s braucht hinter %s eine class var oder eine ' +
          'class-Methode mit static; %s ist ein Instanzfeld (wie E2355).', [AShape.Symbol.Name, Clause,
          Symbol.Name]), TRuleConfidence.High);
        Exit;
      end;
      if not AShape.IsClass and Symbol.HasDirective('class') then
      begin
        AReport.Add(Range(AAccessor), Format('%s ist eine class var; die Property %s braucht ein Instanzfeld oder ' +
          'eine Instanzmethode (wie E2356).', [Symbol.Name, AShape.Symbol.Name]), TRuleConfidence.High);
        Exit;
      end;
      CheckSelectors(AAccessor, Symbol);
      Exit;
    end;
    // Methode (ein Konstruktor ist nie ein passender Getter oder Setter).
    if AAccessor.Selectors <> nil then
      Exit;
    if Length(Found) > 1 then
    begin
      AReport.Add(Range(AAccessor), Format('%s ist überladen; Getter und Setter einer Property dürfen nicht ' +
        'überladen sein (wie E2271).', [Symbol.Name]), TRuleConfidence.High);
      Exit;
    end;
    if AShape.IsClass and not (Symbol.HasDirective('class') and Symbol.HasDirective('static')) then
    begin
      if Symbol.HasDirective('class') then
        AReport.Add(Range(AAccessor), Format('Die Klassen-Property %s braucht eine class-Methode mit static; %s ' +
          'ist nicht static (wie E2355).', [AShape.Symbol.Name, Symbol.Name]), TRuleConfidence.High)
      else
        AReport.Add(Range(AAccessor), Format('Die Klassen-Property %s braucht hinter %s eine class var oder eine ' +
          'class-Methode mit static; %s ist eine Instanzmethode (wie E2355).', [AShape.Symbol.Name, Clause,
          Symbol.Name]), TRuleConfidence.High);
      Exit;
    end;
    if not AShape.IsClass and Symbol.HasDirective('class') then
    begin
      AReport.Add(Range(AAccessor), Format('%s ist eine Klassenmethode; die Property %s braucht ein Instanzfeld ' +
        'oder eine Instanzmethode (wie E2356).', [Symbol.Name, AShape.Symbol.Name]), TRuleConfidence.High);
      Exit;
    end;
    if AAccessor.IsWrite then
    begin
      Modifiers := ParamModifiers(Symbol.Signature);
      if Modifiers <> nil then
      begin
        Modifier := Modifiers[High(Modifiers)];
        if MatchText(Modifier, ['var', 'out']) then
        begin
          AReport.Add(Range(AAccessor), Format('Der Setter %s nimmt den Wert als %s-Parameter; ein Setter ' +
            'braucht einen Wert- oder const-Parameter (wie E2282).', [Symbol.Name, Modifier]), TRuleConfidence.High);
          Exit;
        end;
      end;
    end;
    // Ohne Typ übernimmt die Property Typ und Indexparameter vom Vorfahren.
    if (AShape.TypeText = '') or Fits(AShape, AAccessor, Symbol, AWildcards) then
      Exit;
    if AAccessor.IsWrite then
      AReport.Add(Range(AAccessor), Format('%s passt nicht als Setter von %s; erwartet wird %s (wie E2234).',
        [Symbol.Name, AShape.Symbol.Name, Expected(AShape, AAccessor)]), TRuleConfidence.High)
    else
      AReport.Add(Range(AAccessor), Format('%s passt nicht als Getter von %s; erwartet wird %s (wie E2234).',
        [Symbol.Name, AShape.Symbol.Name, Expected(AShape, AAccessor)]), TRuleConfidence.High);
  end;

  procedure CheckProperty(AStart: Integer);
  var
    Shape: TPropertyShape;
    Symbol: TIndexSymbol;
    Found: Boolean;
    Owner: TSymbolLocation;
    Chain: TArray<TSymbolLocation>;
    Complete, ObjectMissing: Boolean;
    Accessor: TPropertyAccessor;
  begin
    if not Parse(AStart, Shape) or (Shape.Accessors = nil) then
      Exit;
    Found := False;
    for Symbol in Ancestry.Local.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.Property_) and (Symbol.Container <> '') and
        (Symbol.Range.StartPos.Line = Tokens[AStart].StartPos.Line) and
        (Symbol.Range.StartPos.Character = Tokens[AStart].StartPos.Character) then
      begin
        Shape.Symbol := Symbol;
        Found := True;
        Break;
      end;
    if not Found or Shape.Symbol.Unavailable then
      Exit;
    Shape.IsClass := Shape.Symbol.HasDirective('class');
    if not Ancestry.FindAnyType(Shape.Symbol.Container, Owner) or (Owner.FileName <> '') or
      not (Owner.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.ObjectType]) or HasInclude(Owner.Symbol) then
      Exit;
    Chain := [Owner];
    Complete := True;
    if Owner.Symbol.Kind = TIndexSymbolKind.ClassType then
      Chain := Chain + Ancestry.Ancestors(Owner.Symbol.Name, Complete, ObjectMissing);
    for Accessor in Shape.Accessors do
      CheckAccessor(Shape, Accessor, Chain, Complete, Wildcards(Chain));
  end;

var
  Index: Integer;
begin
  if AContext.Tree = nil then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Tokens := TRuleDerived.CodeTokens(Cache, AContext);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  try
    Actions := TClassActionContext.Default;
    Actions.Index := AContext.Index;
    Actions.Namespaces := AContext.Namespaces;
    Actions.DelphiVersion := AContext.DelphiVersion;
    Actions.Style := AContext.Formatting;
    for Index := 0 to High(Tokens) do
      if IsWord(Tokens[Index], 'property') then
        CheckProperty(Index);
  finally
    Ancestry.Free;
  end;
end;

{ TDefaultPropertyInvalidRule }

function TDefaultPropertyInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DefaultPropertyInvalidRuleId, TRuleSeverity.Error,
    'default-Property falsch deklariert oder fehlt');
end;

procedure TDefaultPropertyInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Ancestry: TAncestry;
  Tokens: TArray<TPascalToken>;
  Resolver: TNameResolver;
  FileName: string;

  /// <summary>Token "default" hinter dem Semikolon der Property ASymbol; -1 ohne.</summary>
  function DefaultToken(const ASymbol: TIndexSymbol): Integer;
  var
    Index: Integer;
  begin
    for Index := 0 to High(Tokens) - 1 do
    begin
      if (Tokens[Index].StartPos.Line < ASymbol.Range.StartPos.Line) or
        (Tokens[Index].StartPos.Line > ASymbol.Range.EndPos.Line) then
        Continue;
      if Tokens[Index].IsSymbol(';') and IsWord(Tokens[Index + 1], 'default') then
        Exit(Index + 1);
    end;
    Result := -1;
  end;

  function SameIndexTypes(const A, B: TIndexSymbol): Boolean;
  var
    Index: Integer;
  begin
    Result := Length(A.ParamTypes) = Length(B.ParamTypes);
    if Result then
      for Index := 0 to High(A.ParamTypes) do
        if not Ancestry.SameType(A.ParamTypes[Index], B.ParamTypes[Index], nil) then
          Exit(False);
  end;

  /// <summary>E2132 (default an einer Property ohne Index) und E2131 (zweite default-Property mit gleichen
  /// Indextypen) aus dem Index der Datei.</summary>
  procedure CheckDeclarations;
  var
    Symbol, Earlier: TIndexSymbol;
    Seen: TArray<TIndexSymbol>;
    Token: Integer;
    Range: TTextRange;
  begin
    Seen := nil;
    for Symbol in Ancestry.Local.Symbols do
    begin
      if (Symbol.Kind <> TIndexSymbolKind.Property_) or not Symbol.IsDefault or (Symbol.Container = '') or
        Symbol.Unavailable then
        Continue;
      Token := DefaultToken(Symbol);
      if Token < 0 then
        Continue;
      Range := TTextRange.Create(Tokens[Token].StartPos, Tokens[Token].EndPos);
      // Ohne Typ übernimmt eine Neudeklaration (property Items; default;) die Indexparameter des Vorfahren.
      if (Symbol.MaxArgs = 0) and (Symbol.TypeName <> '') then
      begin
        AReport.Add(Range, 'default ist nur an Array-Properties erlaubt (wie E2132).', TRuleConfidence.High);
        Continue;
      end;
      for Earlier in Seen do
        if SameText(Earlier.Container, Symbol.Container) and (Symbol.TypeName <> '') and
          (Earlier.TypeName <> '') and SameIndexTypes(Earlier, Symbol) then
        begin
          AReport.Add(Range, Format('%s hat schon die default-Property %s mit denselben Indextypen (wie E2131).',
            [Symbol.Container, Earlier.Name]), TRuleConfidence.High);
          Break;
        end;
      Seen := Seen + [Symbol];
    end;
  end;

  /// <summary>Hat die Klasse ATypeName (oder ein Vorfahr) eine default-Property? False ohne sichere Aussage.</summary>
  function LacksDefault(const ATypeName: string): Boolean;
  var
    Own: TSymbolLocation;
    Chain: TArray<TSymbolLocation>;
    Location: TSymbolLocation;
    Member, Symbol: TIndexSymbol;
    Complete, ObjectMissing: Boolean;
  begin
    Result := False;
    if not Ancestry.FindClass(ATypeName, Own) or (Own.Symbol.Kind <> TIndexSymbolKind.ClassType) then
      Exit;
    Chain := [Own] + Ancestry.Ancestors(Own.Symbol.Name, Complete, ObjectMissing);
    if not Complete then
      Exit;
    for Location in Chain do
      for Member in Ancestry.Members(Location) do
        if (Member.Kind = TIndexSymbolKind.Property_) and Member.IsDefault then
          Exit;
    // Ein Class-Helper der Datei könnte die default-Property liefern.
    for Symbol in Ancestry.Local.Symbols do
      if Symbol.Kind = TIndexSymbolKind.HelperType then
        for Location in Chain do
          if ContainsText(' ' + Symbol.Signature + ' ', ' ' + Location.Symbol.Name + ' ') or
            ContainsText(Symbol.Signature, ' ' + Location.Symbol.Name + ')') then
            Exit;
    Result := True;
  end;

  /// <summary>E2149: Obj[I] auf einer Klasse ohne default-Property.</summary>
  procedure CheckAccess(ANode: TSyntaxNode);
  var
    Base: TSyntaxNode;
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    Base := ANode[0];
    if not (Base.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
      TSyntaxKind.Call]) then
      Exit;
    if not Resolver.NodeType(AContext.Tree, FileName, Base, Symbol, TypeInfo, TypeFound) or not TypeFound or
      Symbol.IsType or (TypeInfo.SymbolKind <> TIndexSymbolKind.ClassType) or TypeInfo.Builtin then
      Exit;
    // Bei einer Array-Property (Items[I]) ist Base selbst schon der indizierte Zugriff.
    if (Symbol.SymbolKind = TIndexSymbolKind.Property_) and (Symbol.MaxArgs > 0) and
      (Base.Kind <> TSyntaxKind.IndexAccess) then
      Exit;
    if not LacksDefault(TypeInfo.Name) then
      Exit;
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('%s hat keine default-Property; ' +
      '%s[…] braucht eine (wie E2149).', [TypeInfo.Name, Symbol.Name]), TRuleConfidence.High);
  end;

  procedure VisitBodies;
  var
    Stack: TArray<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Stack := [AContext.Tree.Root];
    while Stack <> nil do
    begin
      Node := Stack[High(Stack)];
      SetLength(Stack, Length(Stack) - 1);
      if (Node.Kind = TSyntaxKind.IndexAccess) and (Node.ChildCount > 1) then
        CheckAccess(Node);
      for Index := Node.ChildCount - 1 downto 0 do
        Stack := Stack + [Node[Index]];
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Tokens := TRuleDerived.CodeTokens(Cache, AContext);
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  try
    CheckDeclarations;
    Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
    try
      Resolver.Namespaces := AContext.Namespaces;
      Resolver.PinTree(AContext.Tree, FileName);
      try
        VisitBodies;
      finally
        Resolver.UnpinTree;
      end;
    finally
      Resolver.Free;
    end;
  finally
    Ancestry.Free;
  end;
end;

{ TPropertyRedeclarationInvalidRule }

function TPropertyRedeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(PropertyRedeclarationInvalidRuleId, TRuleSeverity.Error,
    'Neu deklarierte Property fehlt im Vorfahren');
end;

procedure TPropertyRedeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Ancestry: TAncestry;

  /// <summary>Bindet die Klasse AType Include-Dateien ein? Dann kennt die Datei nicht alle Mitglieder.</summary>
  function HasInclude(const AType: TIndexSymbol): Boolean;
  var
    Token: TPascalToken;
    Name: string;
  begin
    for Token in AContext.Tree.Tokens do
      if (Token.Kind = TPascalTokenKind.Directive) and (Token.StartPos.Line >= AType.Range.StartPos.Line) and
        (Token.StartPos.Line <= AType.Range.EndPos.Line) then
      begin
        Name := TDirectiveNames.LeadingName(TDirectiveNames.Body(Token.Text));
        if SameText(Name, 'I') or SameText(Name, 'INCLUDE') then
          Exit(True);
      end;
    Result := False;
  end;

  /// <summary>Sieht der Nachfahre den Member ASymbol des Vorfahren auf AType?</summary>
  function Visible(const AType: TSymbolLocation; const ASymbol: TIndexSymbol): Boolean;
  begin
    Result := (ASymbol.Visibility <> TIndexVisibility.StrictPrivate) and
      ((ASymbol.Visibility <> TIndexVisibility.Private) or (AType.FileName = ''));
  end;

  procedure CheckProperty(const AOwner: TIndexSymbol; const AProperty: TIndexSymbol);
  var
    Chain: TArray<TSymbolLocation>;
    Location: TSymbolLocation;
    Member: TIndexSymbol;
    Complete, ObjectMissing: Boolean;
    Names: TArray<string>;
    Closest, Ancestor, Hidden: string;
  begin
    Chain := Ancestry.Ancestors(AOwner.Name, Complete, ObjectMissing);
    if not Complete then
      Exit;
    Hidden := '';
    Names := nil;
    for Location in Chain do
      for Member in Ancestry.Members(Location) do
      begin
        if SameText(Member.Name, AProperty.Name) then
        begin
          // Nur in einem inaktiven Zweig oder kein Property (Feld, Methode): keine sichere Aussage.
          if Member.Unavailable or (Member.Kind <> TIndexSymbolKind.Property_) then
            Exit;
          if Visible(Location, Member) then
            Exit;
          if Hidden = '' then
            Hidden := Location.Symbol.Name;
        end
        else if (Member.Kind = TIndexSymbolKind.Property_) and Visible(Location, Member) and
          not MatchText(Member.Name, Names) then
          Names := Names + [Member.Name];
      end;
    if Hidden <> '' then
    begin
      AReport.Add(AProperty.SelectionRange, Format('Die Property %s von %s ist hier nicht erreichbar (wie E2233).',
        [AProperty.Name, Hidden]), TRuleConfidence.High);
      Exit;
    end;
    Ancestor := 'TObject';
    if Chain <> nil then
      Ancestor := Chain[0].Symbol.Name;
    Closest := TTextFuzzy.Closest(AProperty.Name, Names);
    if Closest <> '' then
      AReport.Add(AProperty.SelectionRange, Format('%s hat keine Property %s; gemeint ist %s (wie E2147).',
        [Ancestor, AProperty.Name, Closest]), TRuleConfidence.High,
        [TRuleFix.Create(Format('%s verwenden', [Closest]), [TRuleEdit.Create(AProperty.SelectionRange, Closest)])])
    else
      AReport.Add(AProperty.SelectionRange, Format('%s hat keine Property %s (wie E2147).', [Ancestor,
        AProperty.Name]), TRuleConfidence.High);
  end;

var
  Symbol, Member: TIndexSymbol;
  Location: TSymbolLocation;
begin
  if AContext.Tree = nil then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  try
    for Symbol in Ancestry.Local.Symbols do
    begin
      if (Symbol.Kind <> TIndexSymbolKind.ClassType) or (Symbol.Container <> '') or Symbol.Unavailable or
        HasInclude(Symbol) then
        Continue;
      Location := Default(TSymbolLocation);
      Location.Symbol := Symbol;
      // Neudeklaration: property Caption; bzw. property Align default alClient; (ohne Typ und Index).
      for Member in Ancestry.Members(Location) do
        if (Member.Kind = TIndexSymbolKind.Property_) and (Member.TypeName = '') and (Member.MaxArgs = 0) and
          not Member.Unavailable and not Member.HasDirective('class') then
          CheckProperty(Symbol, Member);
    end;
  finally
    Ancestry.Free;
  end;
end;

procedure RegisterPropertyRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TPropertyAccessorInvalidRule.Create);
  ARegistry.Register(TDefaultPropertyInvalidRule.Create);
  ARegistry.Register(TPropertyRedeclarationInvalidRule.Create);
end;

end.
