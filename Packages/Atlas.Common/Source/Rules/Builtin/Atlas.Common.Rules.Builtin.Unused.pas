unit Atlas.Common.Rules.Builtin.Unused;

// Ungenutzte Variablen und Parameter ohne Compilerlauf (#91):
//   unused-local        lokale Variable wird nirgends verwendet (wie H2164)
//   unused-parameter    Parameter wird im Rumpf nicht verwendet
//   unused-assignment   zugewiesener Wert wird nie gelesen (wie H2077)
//   duplicate-assignment  Feld oder Property zweimal hintereinander gesetzt (#1051)
//
// Verwendung ist jedes Vorkommen des Namens in der Routine, auch in lokalen
// Routinen und anonymen Methoden, sowie "absolute Name" im var-Abschnitt.
// Enthält die Routine bedingte Kompilierung ({$IF…}), sieht der Syntaxbaum
// inaktive Zweige nicht: Kommt der Name dann im Text vor, gibt es keinen
// Treffer, sonst nur einen mit niedriger Konfidenz; unused-assignment
// schweigt in solchen Routinen ganz. Routinen mit asm-Rumpf werden übergangen.
// unused-assignment übergeht Variablen mit Interface-Typ (Referenzzähler: Bereichswächter, X := nil).
//
// unused-parameter nimmt aus:
// - Parameter namens Sender und Routinen mit einem solchen (Ereignis-Handler),
// - Methoden mit override, virtual, dynamic, abstract oder message,
//   published-Methoden (DFM-Ereignisse), Methoden von Klassen mit Interfaces
//   und Methoden, deren Typdeklaration nicht in der Datei steht,
// - Routinen, die als Wert verwendet werden (@P, X := P, X := Obj.P, Aufruf(P)).
//
// Option aller drei Regeln: {"ignore": ["Dummy*", "_*"]} nimmt Namen nach
// Muster aus (* und ? als Platzhalter).
//
// duplicate-assignment vergleicht Zuweisungen derselben Anweisungsfolge an
// Felder, Properties und Mitglieder (Panel.Left, Self.FWert, P^.X, Feld der
// eigenen Klasse ohne Self); lokale Variablen deckt unused-assignment ab.
// Dazwischen dürfen nur Zuweisungen an andere Objekte stehen, deren Werte
// nichts aufrufen und das Ziel nicht nennen; der zweite Wert darf das Ziel
// nicht lesen und nichts aufrufen. Ziele mit Index oder Aufruf zählen nicht.
// Still bleibt der Wechsel False/True (stößt bei Active, Open … etwas an),
// eine zweite Zuweisung, die nur unter einer weiteren Bedingung übersetzt
// wird ({$IFDEF DEBUG} Caption := …), und Properties aus allowProperties
// (Muster, Standard Visible, Enabled). Fehlt das Gegenstück (Left/Top,
// Width/Height …) in der Folge, nennt die Meldung es als Vermutung.
//
// empty-routine (#977): Rumpf ohne Anweisung und ohne Kommentar (auch keine
// Direktive). Ausgenommen sind virtuelle bzw. dynamische Methoden (Ersatz für
// abstract), Nachrichten-Handler und Ereignis-Handler aus der Formulardatei.
// Korrekturen: Kommentar zwischen begin und end; "Methode entfernen" nur für
// private Methoden bzw. Routinen ohne Deklaration im interface, die in der
// Datei nirgends vorkommen und keine Signatur von außen erfüllen.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TUnusedLocalRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnusedParameterRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnusedAssignmentRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDuplicateAssignmentRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ziel als Schlüssel ("Panel.Font.Size", "P^.X", Self. entfällt); '' bei Index, Aufruf und anderem.</summary>
    class function TargetKey(ANode: TSyntaxNode): string; static;
    /// <summary>Gegenstück für den Hinweis (Left zu Top, Height zu Width …); '' ohne.</summary>
    class function Counterpart(const AName: string): string; static;
  end;

  TEmptyRoutineRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Passt AName auf das Muster? * steht für beliebig viele, ? für genau ein Zeichen;
/// ohne Groß-/Kleinschreibung.</summary>
function MatchesWildcard(const AName, APattern: string): Boolean;

procedure RegisterUnusedRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  System.RegularExpressions,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Flow;

type
  TNameSet = TDictionary<string, Boolean>;

  /// <summary>Was die Prüfung einer Routine braucht.</summary>
  TRoutineInfo = record
    Routine: TSyntaxNode;
    Block: TSyntaxNode;
    Conditionals: Boolean;
  end;

function MatchesWildcard(const AName, APattern: string): Boolean;
var
  Name, Pattern: string;

  function Match(ANameIndex, APatternIndex: Integer): Boolean;
  begin
    while APatternIndex <= Length(Pattern) do
    begin
      if Pattern[APatternIndex] = '*' then
      begin
        while ANameIndex <= Length(Name) + 1 do
        begin
          if Match(ANameIndex, APatternIndex + 1) then
            Exit(True);
          Inc(ANameIndex);
        end;
        Exit(False);
      end;
      if (ANameIndex > Length(Name)) or ((Pattern[APatternIndex] <> '?') and
        (Pattern[APatternIndex] <> Name[ANameIndex])) then
        Exit(False);
      Inc(ANameIndex);
      Inc(APatternIndex);
    end;
    Result := ANameIndex > Length(Name);
  end;

begin
  Name := LowerCase(AName);
  Pattern := LowerCase(APattern);
  Result := Match(1, 1);
end;

/// <summary>Muster aus {"ignore": [...]}.</summary>
function IgnorePatterns(const AOptions: string): TArray<string>;
var
  Value, Items, Item: TJSONValue;
begin
  Result := nil;
  if AOptions = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
      Exit;
    Items := TJSONObject(Value).GetValue('ignore');
    if Items is TJSONArray then
      for Item in TJSONArray(Items) do
        if Item is TJSONString then
          Result := Result + [Item.Value];
  finally
    Value.Free;
  end;
end;

function IsIgnored(const AName: string; const APatterns: TArray<string>): Boolean;
var
  Pattern: string;
begin
  for Pattern in APatterns do
    if MatchesWildcard(AName, Pattern) then
      Exit(True);
  Result := False;
end;

function SplitNames(const ANames: string): TArray<string>;
var
  Name: string;
begin
  Result := nil;
  for Name in SplitString(ANames, ',') do
    if Trim(Name) <> '' then
      Result := Result + [Trim(Name)];
end;

function ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

function ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  Kind: TSyntaxKind;
begin
  Kind := AKind;
  // Iterativ (Bericht M1).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if AVisited.Kind = Kind then
        Exit(TSyntaxSearchStep.Found);
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

/// <summary>Kommt der Bezeichner AName in ANode oder darunter vor?</summary>
function MentionsName(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Name: string;
begin
  Name := AName;
  // Iterativ (Bericht M1).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if (AVisited.Kind = TSyntaxKind.Identifier) and SameText(AVisited.Name, Name) then
        Exit(TSyntaxSearchStep.Found);
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;


/// <summary>Namen, die in ANode verwendet werden (klein geschrieben): Bezeichner und Schleifenvariablen.</summary>
procedure CollectUses(ANode: TSyntaxNode; ASet: TNameSet);
var
  Names: TNameSet;
begin
  Names := ASet;
  // Iterativ (Bericht M1): Der Lauf geht auch durch lange Ausdrucksketten.
  ANode.Walk(
    function(AVisited: TSyntaxNode): Boolean
    begin
      if AVisited.Kind in [TSyntaxKind.Identifier, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
        Names.AddOrSetValue(LowerCase(AVisited.Name), True);
      Result := True;
    end);
end;


/// <summary>Erweitert [AStart, AEnd) auf ganze Zeilen; False, wenn davor oder dahinter noch etwas steht.</summary>
function WholeLines(const AText: string; AStart, AEnd: Integer; out ALineStart, ALineEnd: Integer): Boolean;
begin
  ALineStart := AStart;
  while (ALineStart > 0) and CharInSet(AText[ALineStart], [' ', #9]) do
    Dec(ALineStart);
  if (ALineStart > 0) and (AText[ALineStart] <> #10) then
    Exit(False);
  ALineEnd := AEnd;
  while (ALineEnd < Length(AText)) and CharInSet(AText[ALineEnd + 1], [' ', #9, #13]) do
    Inc(ALineEnd);
  if ALineEnd < Length(AText) then
  begin
    if AText[ALineEnd + 1] <> #10 then
      Exit(False);
    Inc(ALineEnd);
  end;
  Result := True;
end;

/// <summary>Bezeichner-Token im Bereich [AStart, AEnd) mit diesem Text.</summary>
function FindToken(const AContext: TRuleContext; AStart, AEnd: Integer; const AName: string;
  out AToken: TPascalToken): Boolean;
var
  Token: TPascalToken;
begin
  for Token in AContext.Tree.Tokens do
  begin
    if Token.Offset >= AEnd then
      Break;
    if (Token.Offset >= AStart) and (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, AName) then
    begin
      AToken := Token;
      Exit(True);
    end;
  end;
  Result := False;
end;

function NameRange(const AContext: TRuleContext; ANode: TSyntaxNode; const AName: string): TTextRange;
var
  Token: TPascalToken;
begin
  if FindToken(AContext, ANode.StartOffset, ANode.EndOffset, AName, Token) then
    Result := TTextRange.Create(Token.StartPos, Token.EndPos)
  else
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

/// <summary>Enthält die Routine Direktiven der bedingten Kompilierung?</summary>
function HasConditionals(const AContext: TRuleContext; ARoutine: TSyntaxNode): Boolean;
var
  Token: TPascalToken;
  Text: string;
begin
  for Token in AContext.Tree.Tokens do
  begin
    if Token.Offset >= ARoutine.EndOffset then
      Break;
    if (Token.Offset < ARoutine.StartOffset) or (Token.Kind <> TPascalTokenKind.Directive) then
      Continue;
    Text := UpperCase(Token.Text);
    if StartsStr('{$IF', Text) or StartsStr('(*$IF', Text) or StartsStr('{$ELSE', Text) or
      StartsStr('(*$ELSE', Text) then
      Exit(True);
  end;
  Result := False;
end;

/// <summary>Kommt AName als ganzes Wort im Text zwischen den Offsets vor (Kommentare eingeschlossen)?</summary>
function OccursInText(const AText, AName: string; AStart, AEnd: Integer): Boolean;
var
  Text, Name: string;
  Position: Integer;

  function IsWordChar(AIndex: Integer): Boolean;
  begin
    Result := (AIndex >= 1) and (AIndex <= Length(Text)) and
      (CharInSet(Text[AIndex], ['a'..'z', '0'..'9', '_']) or (Ord(Text[AIndex]) > 127));
  end;

begin
  Text := LowerCase(Copy(AText, 1, AEnd));
  Name := LowerCase(AName);
  Position := PosEx(Name, Text, AStart + 1);
  while Position > 0 do
  begin
    if not IsWordChar(Position - 1) and not IsWordChar(Position + Length(Name)) then
      Exit(True);
    Position := PosEx(Name, Text, Position + 1);
  end;
  Result := False;
end;

/// <summary>"absolute AName" in einem var-Abschnitt der Routine.</summary>
function UsedByAbsolute(const AContext: TRuleContext; ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  Index, Position: Integer;
  Section: TSyntaxNode;
  Text: string;
begin
  for Index := 0 to ARoutine.ChildCount - 1 do
  begin
    Section := ARoutine[Index];
    if Section.Kind <> TSyntaxKind.VarSection then
      Continue;
    Text := LowerCase(Copy(AContext.Text, Section.StartOffset + 1, Section.EndOffset - Section.StartOffset));
    Position := Pos('absolute', Text);
    while Position > 0 do
    begin
      if StartsStr(LowerCase(AName), TrimLeft(Copy(Text, Position + 8, MaxInt))) then
        Exit(True);
      Position := PosEx('absolute', Text, Position + 8);
    end;
  end;
  Result := False;
end;

/// <summary>Ist AName ungenutzt? AConfidence ist dann gesetzt.</summary>
function IsUnused(const AContext: TRuleContext; const AInfo: TRoutineInfo; AUses: TNameSet;
  const AName: string; AAfterOffset: Integer; out AConfidence: TRuleConfidence): Boolean;
begin
  Result := False;
  AConfidence := TRuleConfidence.High;
  if AUses.ContainsKey(LowerCase(AName)) or UsedByAbsolute(AContext, AInfo.Routine, AName) then
    Exit;
  if AInfo.Conditionals then
  begin
    // Vielleicht in einem inaktiven Zweig verwendet.
    if OccursInText(AContext.Text, AName, AAfterOffset, AInfo.Routine.EndOffset) then
      Exit;
    AConfidence := TRuleConfidence.Low;
  end;
  Result := True;
end;

function RoutineInfo(const AContext: TRuleContext; ARoutine: TSyntaxNode; out AInfo: TRoutineInfo): Boolean;
begin
  AInfo.Routine := ARoutine;
  AInfo.Block := ARoutine.FindChild(TSyntaxKind.Block);
  AInfo.Conditionals := False;
  Result := (AInfo.Block <> nil) and not ContainsKind(ARoutine, TSyntaxKind.AsmBlock);
  if Result then
    AInfo.Conditionals := HasConditionals(AContext, ARoutine);
end;

/// <summary>Inline-Variablen eines Rumpfs, ohne lokale Routinen und anonyme Methoden.</summary>
procedure CollectInlineVars(ANode: TSyntaxNode; var AVars: TArray<TSyntaxNode>);
var
  Vars: TArray<TSyntaxNode>;
begin
  // Iterativ (Bericht M1); var-Parameter lassen sich nicht in der anonymen Methode verwenden.
  Vars := AVars;
  ANode.Walk(
    function(AVisited: TSyntaxNode): Boolean
    begin
      Result := not (AVisited.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]);
      if Result and (AVisited.Kind = TSyntaxKind.InlineVar) then
        Vars := Vars + [AVisited];
    end);
  AVars := Vars;
end;

{ TUnusedLocalRule }

function TUnusedLocalRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unused-local', TRuleSeverity.Hint, 'Lokale Variable wird nicht verwendet');
end;

/// <summary>Korrektur, die AName aus ADecl entfernt (ASection = nil bei Inline-Variablen);
/// False, wenn keine sichere Korrektur möglich ist.</summary>
function RemoveVarFix(const ACache: IRuleDerivedCache; const AContext: TRuleContext; ASection, ADecl: TSyntaxNode;
  const AName: string; out AFix: TRuleFix): Boolean;
var
  Names: TArray<string>;
  Index, Position, LineStart, LineEnd, Start, Stop: Integer;
  Token, Neighbour: TPascalToken;
  Title: string;
begin
  Result := False;
  Title := Format('Variable "%s" entfernen', [AName]);
  Names := SplitNames(ADecl.Name);
  if ADecl.Kind = TSyntaxKind.InlineVar then
  begin
    // Nur ohne oder mit einfachem Startwert: ein Aufruf hätte Nebenwirkungen.
    if (ADecl.ChildCount > 1) or ((ADecl.ChildCount = 1) and (ADecl[0].Kind <> TSyntaxKind.Literal)) then
      Exit;
    Stop := ADecl.EndOffset;
    while (Stop < Length(AContext.Text)) and (AContext.Text[Stop + 1] = ' ') do
      Inc(Stop);
    if (Stop < Length(AContext.Text)) and (AContext.Text[Stop + 1] = ';') then
      Inc(Stop);
    if not WholeLines(AContext.Text, ADecl.StartOffset, Stop, LineStart, LineEnd) then
      Exit;
    AFix := TRuleFix.Create(Title, [TRuleEdit.Create(TRuleDerived.OffsetRange(ACache, AContext, LineStart, LineEnd),
      '')]);
    Exit(True);
  end;
  if Length(Names) > 1 then
  begin
    // Nur den Namen aus der Liste nehmen: "I, J: Integer" wird "J: Integer".
    Position := -1;
    for Index := 0 to High(Names) do
      if SameText(Names[Index], AName) then
        Position := Index;
    if (Position < 0) or not FindToken(AContext, ADecl.StartOffset, ADecl.EndOffset, AName, Token) then
      Exit;
    if Position < High(Names) then
    begin
      if not FindToken(AContext, Token.Offset + Length(Token.Text), ADecl.EndOffset, Names[Position + 1],
        Neighbour) then
        Exit;
      Start := Token.Offset;
      Stop := Neighbour.Offset;
    end
    else
    begin
      if not FindToken(AContext, ADecl.StartOffset, ADecl.EndOffset, Names[Position - 1], Neighbour) then
        Exit;
      Start := Neighbour.Offset + Length(Neighbour.Text);
      Stop := Token.Offset + Length(Token.Text);
    end;
    AFix := TRuleFix.Create(Title, [TRuleEdit.Create(TRuleDerived.OffsetRange(ACache, AContext, Start, Stop), '')]);
    Exit(True);
  end;
  // Letzte Deklaration: der leer gewordene var-Abschnitt entfällt mit.
  if ASection.ChildCount = 1 then
    Start := ASection.StartOffset
  else
    Start := ADecl.StartOffset;
  if not WholeLines(AContext.Text, Start, ADecl.EndOffset, LineStart, LineEnd) then
    Exit;
  AFix := TRuleFix.Create(Title, [TRuleEdit.Create(TRuleDerived.OffsetRange(ACache, AContext, LineStart, LineEnd),
    '')]);
  Result := True;
end;

procedure TUnusedLocalRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines, InlineVars: TArray<TSyntaxNode>;
  Routine, Section, Decl: TSyntaxNode;
  Info: TRoutineInfo;
  Uses_: TNameSet;
  Patterns: TArray<string>;
  Index, Inner: Integer;
  Cache: IRuleDerivedCache;

  procedure CheckDecl(ASection, ADecl: TSyntaxNode);
  var
    Name, Message: string;
    Confidence: TRuleConfidence;
    Fix: TRuleFix;
  begin
    for Name in SplitNames(ADecl.Name) do
    begin
      if IsIgnored(Name, Patterns) or not IsUnused(AContext, Info, Uses_, Name, ADecl.EndOffset, Confidence) then
        Continue;
      Message := Format('Variable "%s" wird nicht verwendet', [Name]);
      if RemoveVarFix(Cache, AContext, ASection, ADecl, Name, Fix) then
        AReport.Add(NameRange(AContext, ADecl, Name), Message, Confidence, [Fix])
      else
        AReport.Add(NameRange(AContext, ADecl, Name), Message, Confidence);
    end;
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Patterns := IgnorePatterns(AContext.Options);
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  Uses_ := TNameSet.Create;
  try
    for Routine in Routines do
    begin
      if not RoutineInfo(AContext, Routine, Info) then
        Continue;
      Uses_.Clear;
      // Lokale Routinen gehören dazu: sie dürfen Variablen der äußeren verwenden.
      for Index := 0 to Routine.ChildCount - 1 do
        if Routine[Index].Kind in [TSyntaxKind.Block, TSyntaxKind.RoutineDecl] then
          CollectUses(Routine[Index], Uses_);
      for Index := 0 to Routine.ChildCount - 1 do
      begin
        Section := Routine[Index];
        if Section.Kind = TSyntaxKind.VarSection then
          for Inner := 0 to Section.ChildCount - 1 do
            if Section[Inner].Kind = TSyntaxKind.VarDecl then
              CheckDecl(Section, Section[Inner]);
      end;
      InlineVars := nil;
      CollectInlineVars(Info.Block, InlineVars);
      for Decl in InlineVars do
        CheckDecl(nil, Decl);
    end;
  finally
    Uses_.Free;
  end;
end;

{ TUnusedParameterRule }

function TUnusedParameterRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unused-parameter', TRuleSeverity.Hint, 'Parameter wird nicht verwendet');
end;

/// <summary>Rumpf (Klasse, Record, Objekt, Helfer) einer Typdeklaration, sonst nil.</summary>
function TypeBodyOf(ADecl: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ADecl.ChildCount - 1 do
    if ADecl[Index].Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
      TSyntaxKind.HelperType] then
      Exit(ADecl[Index]);
  Result := nil;
end;

function FindTypeBody(ANode: TSyntaxNode; const ATypeName: string): TSyntaxNode;
var
  TypeName: string;
  Decl: TSyntaxNode;
begin
  TypeName := ATypeName;
  // Iterativ (Bericht M1).
  Decl := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if (AVisited.Kind = TSyntaxKind.TypeDecl) and SameText(AVisited.Name, TypeName) and
        (TypeBodyOf(AVisited) <> nil) then
        Exit(TSyntaxSearchStep.Found);
      Result := TSyntaxSearchStep.Descend;
    end);
  if Decl = nil then
    Result := nil
  else
    Result := TypeBodyOf(Decl);
end;

/// <summary>Ist die Signatur der Methode von außen vorgegeben (override, Interface, DFM …) oder unbekannt?</summary>
function MethodSignatureFixed(ARoot: TSyntaxNode; const AQualifiedName: string): Boolean;
var
  TypeName, Name, Visibility: string;
  Body, Member, Ancestor: TSyntaxNode;
  Index, Inner, Ancestors: Integer;
begin
  TypeName := Copy(AQualifiedName, 1, LastDelimiter('.', AQualifiedName) - 1);
  // TFoo<T>.Bar und verschachtelte Typen: nur der letzte Typname zählt.
  if Pos('<', TypeName) > 0 then
    TypeName := Copy(TypeName, 1, Pos('<', TypeName) - 1);
  TypeName := ShortName(TypeName);
  Name := ShortName(AQualifiedName);
  Body := FindTypeBody(ARoot, TypeName);
  if Body = nil then
    Exit(True);
  Ancestors := 0;
  Ancestor := nil;
  for Index := 0 to Body.ChildCount - 1 do
    if Body[Index].Kind = TSyntaxKind.TypeReference then
    begin
      Inc(Ancestors);
      Ancestor := Body[Index];
    end;
  // class(TBasis, IFoo) oder class(TInterfacedObject, IFoo): Methoden können ein Interface erfüllen.
  if (Ancestors > 1) or ((Ancestor <> nil) and StartsStr('I', Ancestor.Name) and (Length(Ancestor.Name) > 1) and
    CharInSet(Ancestor.Name[2], ['A'..'Z'])) then
    Exit(True);
  Visibility := '';
  for Index := 0 to Body.ChildCount - 1 do
  begin
    Member := Body[Index];
    if Member.Kind = TSyntaxKind.Visibility then
      Visibility := LowerCase(Member.Name)
    else if (Member.Kind = TSyntaxKind.RoutineHeader) and SameText(Member.Name, Name) then
    begin
      if Visibility = 'published' then
        Exit(True);
      for Inner := 0 to Member.ChildCount - 1 do
        if (Member[Inner].Kind = TSyntaxKind.Directive) and MatchText(Member[Inner].Name,
          ['override', 'virtual', 'dynamic', 'abstract', 'message']) then
          Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Wird ANode als Wert verwendet (Zuweisung, Argument, @) statt aufgerufen?</summary>
function IsValueUse(ANode: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  // Self.Handler: die ganze Kette zählt.
  while (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.MemberAccess) and
    (ANode.Parent[ANode.Parent.ChildCount - 1] = ANode) do
    ANode := ANode.Parent;
  Parent := ANode.Parent;
  if Parent = nil then
    Exit(False);
  case Parent.Kind of
    TSyntaxKind.AddressOf:
      Result := True;
    TSyntaxKind.AssignStatement:
      Result := Parent[0] <> ANode;
    TSyntaxKind.Call:
      Result := Parent[0] <> ANode;
  else
    Result := False;
  end;
end;

function UsedAsValue(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Name: string;
begin
  Name := AName;
  // Iterativ (Bericht M1).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      // Auch Objekt.Methode (Writer.OnFindMethodName := Namer.FindMethodName): Der Name steht am MemberAccess.
      if (AVisited.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and SameText(AVisited.Name, Name) and
        IsValueUse(AVisited) then
        Exit(TSyntaxSearchStep.Found);
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

procedure TUnusedParameterRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines: TArray<TSyntaxNode>;
  Routine, Header, Params, Param: TSyntaxNode;
  Info: TRoutineInfo;
  Uses_: TNameSet;
  Patterns: TArray<string>;
  Index: Integer;
  Name: string;
  Confidence: TRuleConfidence;
  Skip: Boolean;
  Cache: IRuleDerivedCache;
begin
  if AContext.Tree = nil then
    Exit;
  Patterns := IgnorePatterns(AContext.Options);
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  Uses_ := TNameSet.Create;
  try
    for Routine in Routines do
    begin
      if not RoutineInfo(AContext, Routine, Info) then
        Continue;
      Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
      if Header = nil then
        Continue;
      Params := Header.FindChild(TSyntaxKind.Parameters);
      if Params = nil then
        Continue;
      Skip := False;
      for Index := 0 to Params.ChildCount - 1 do
        for Name in SplitNames(Params[Index].Name) do
          Skip := Skip or SameText(Name, 'Sender');
      if Skip or ((Pos('.', Routine.Name) > 0) and MethodSignatureFixed(AContext.Tree.Root, Routine.Name)) or
        UsedAsValue(AContext.Tree.Root, ShortName(Routine.Name)) then
        Continue;
      Uses_.Clear;
      for Index := 0 to Routine.ChildCount - 1 do
        if Routine[Index].Kind in [TSyntaxKind.Block, TSyntaxKind.RoutineDecl, TSyntaxKind.VarSection] then
          CollectUses(Routine[Index], Uses_);
      for Index := 0 to Params.ChildCount - 1 do
      begin
        Param := Params[Index];
        if Param.Kind <> TSyntaxKind.Parameter then
          Continue;
        for Name in SplitNames(Param.Name) do
          if not IsIgnored(Name, Patterns) and IsUnused(AContext, Info, Uses_, Name, Header.EndOffset, Confidence) then
          begin
            // Parameter sind unsicherer als Variablen: die Signatur kann von außen vorgegeben sein.
            if Confidence = TRuleConfidence.High then
              Confidence := TRuleConfidence.Medium;
            AReport.Add(NameRange(AContext, Param, Name), Format('Parameter "%s" wird nicht verwendet', [Name]),
              Confidence);
          end;
      end;
    end;
  finally
    Uses_.Free;
  end;
end;

{ TUnusedAssignmentRule }

function TUnusedAssignmentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unused-assignment', TRuleSeverity.Hint, 'Zugewiesener Wert wird nie gelesen');
end;

/// <summary>Kommt AName in lokalen Routinen oder anonymen Methoden unter ANode vor (ANode selbst zählt nicht)?</summary>
function UsedInNested(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Root: TSyntaxNode;
  Name: string;
begin
  Root := ANode;
  Name := AName;
  // Iterativ (Bericht M1).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if (AVisited = Root) or not (AVisited.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
        Exit(TSyntaxSearchStep.Descend);
      if MentionsName(AVisited, Name) then
        Exit(TSyntaxSearchStep.Found);
      Result := TSyntaxSearchStep.Skip;
    end) <> nil;
end;

/// <summary>Hat die var-Deklaration ADecl einen Interface-Typ (IFoo nach Delphi-Brauch)? Zuweisungen an solche
/// Variablen wirken über den Referenzzähler: Activity := TAtlasActivity.Scope(…) hält einen Bereich bis zum Ende
/// der Routine, Writer := nil gibt den Schreiber vorzeitig frei. Wie Delphis H2077 schweigt die Regel dort (#1109).</summary>
function IsInterfaceTyped(ADecl: TSyntaxNode): Boolean;
var
  TypeNode: TSyntaxNode;
  TypeName: string;
begin
  TypeNode := ADecl.FindChild(TSyntaxKind.TypeReference);
  if TypeNode = nil then
    Exit(False);
  TypeName := TypeNode.Name;
  if LastDelimiter('.', TypeName) > 0 then
    TypeName := Copy(TypeName, LastDelimiter('.', TypeName) + 1, MaxInt);
  Result := (Length(TypeName) > 1) and (TypeName[1] = 'I') and CharInSet(TypeName[2], ['A'..'Z']);
end;

procedure TUnusedAssignmentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines, Locals: TArray<TSyntaxNode>;
  Routine, Section, Decl: TSyntaxNode;
  Info: TRoutineInfo;
  Graph: TControlFlowGraph;
  Patterns, Names: TArray<string>;
  Index, Inner: Integer;
  Name: string;
  Writes, Reads: TList<TSyntaxNode>;
  Cache: IRuleDerivedCache;

  procedure Collect(ARoot: TSyntaxNode);
  var
    Target: string;
    TargetWrites, TargetReads: TList<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1). Nur Locals dieser Routine gehen in die anonyme Methode: Name ist die Schleifenvariable
    // in Check und darf nicht eingefangen werden.
    Target := Name;
    TargetWrites := Writes;
    TargetReads := Reads;
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := not (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]);
        if not Result then
          Exit;
        if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, Target) then
        begin
          if (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.AssignStatement) and
            (ANode.Parent[0] = ANode) then
            TargetWrites.Add(ANode.Parent)
          else
            TargetReads.Add(ANode);
        end
        else if (ANode.Kind = TSyntaxKind.InlineVar) and (ANode.ChildCount > 0) and
          MatchText(Target, SplitNames(ANode.Name)) then
          TargetWrites.Add(ANode);
      end);
  end;

  /// <summary>Flussknoten der nächsten Anweisung um ANode (bei Schleifen mehrere).</summary>
  function FlowNodesOf(ANode: TSyntaxNode): TArray<TFlowNode>;
  var
    Node: TFlowNode;
  begin
    Result := nil;
    while (ANode <> nil) and (Result = nil) do
    begin
      for Node in Graph.Nodes do
        if Node.Syntax = ANode then
          Result := Result + [Node];
      ANode := ANode.Parent;
    end;
  end;

  function IsRead(ADefinition: TFlowNode): Boolean;
  var
    Read: TSyntaxNode;
    Node, Definition: TFlowNode;
  begin
    for Read in Reads do
      for Node in FlowNodesOf(Read) do
        for Definition in Graph.ReachingDefinitions(Node, Name).Definitions do
          if Definition = ADefinition then
            Exit(True);
    Result := False;
  end;

  procedure CheckName;
  var
    Write: TSyntaxNode;
    Definition: TFlowNode;
    Used, Defined: Boolean;
  begin
    if IsIgnored(Name, Patterns) or HasOpaqueUse(Info.Block, Name) or UsedInNested(Routine, Name) or
      UsedByAbsolute(AContext, Routine, Name) then
      Exit;
    Writes.Clear;
    Reads.Clear;
    Collect(Info.Block);
    if Writes.Count = 0 then
      Exit;
    if Graph = nil then
      Graph := TRuleDerived.Graph(Cache, AContext, Routine);
    if not Graph.Complete then
      Exit;
    for Write in Writes do
    begin
      // Zuweisungen im finally stehen je Ausgang einmal im Graphen; gemeldet
      // wird nur, wenn der Wert in keiner Kopie gelesen wird.
      Defined := False;
      Used := False;
      for Definition in Graph.Nodes do
        if (Definition.Syntax = Write) and SameText(Definition.Defines, Name) and
          (Graph.IsReachable(Definition) = TFlowAnswer.Yes) then
        begin
          Defined := True;
          if IsRead(Definition) then
            Used := True;
        end;
      if not Defined or Used then
        Continue;
      AReport.Add(NameRange(AContext, Write, Name), Format('Der an "%s" zugewiesene Wert wird nie gelesen', [Name]),
        TRuleConfidence.High);
    end;
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Patterns := IgnorePatterns(AContext.Options);
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  Writes := TList<TSyntaxNode>.Create;
  Reads := TList<TSyntaxNode>.Create;
  try
    for Routine in Routines do
    begin
      // Mit bedingter Kompilierung ist nicht eindeutig, welche Lesezugriffe es gibt.
      if not RoutineInfo(AContext, Routine, Info) or Info.Conditionals then
        Continue;
      Names := nil;
      for Index := 0 to Routine.ChildCount - 1 do
      begin
        Section := Routine[Index];
        if Section.Kind = TSyntaxKind.VarSection then
          for Inner := 0 to Section.ChildCount - 1 do
            if (Section[Inner].Kind = TSyntaxKind.VarDecl) and not IsInterfaceTyped(Section[Inner]) then
              Names := Names + SplitNames(Section[Inner].Name);
      end;
      Locals := nil;
      CollectInlineVars(Info.Block, Locals);
      for Decl in Locals do
        if not IsInterfaceTyped(Decl) then
          Names := Names + SplitNames(Decl.Name);
      Graph := nil;
      for Name in Names do
        CheckName;
    end;
  finally
    Reads.Free;
    Writes.Free;
  end;
end;

{ TDuplicateAssignmentRule }

const
  // Gegenstücke für den Hinweis "gemeint ist vermutlich …" (Left/Top vertauscht beim Kopieren).
  CounterpartPairs: array[0..9, 0..1] of string = (('Left', 'Top'), ('Width', 'Height'), ('Right', 'Bottom'),
    ('X', 'Y'), ('Min', 'Max'), ('MinValue', 'MaxValue'), ('ClientWidth', 'ClientHeight'), ('Row', 'Col'),
    ('MinWidth', 'MinHeight'), ('MaxWidth', 'MaxHeight'));
  // Knoten, deren Kinder nacheinander ausgeführte Anweisungen sind.
  StatementLists = [TSyntaxKind.Block, TSyntaxKind.RepeatStatement, TSyntaxKind.TryStatement, TSyntaxKind.ExceptBlock,
    TSyntaxKind.FinallyBlock, TSyntaxKind.CaseElse, TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection];

function TDuplicateAssignmentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('duplicate-assignment', TRuleSeverity.Warning,
    'Feld oder Property wird zweimal gesetzt');
end;

// Iterativ (Bericht M1): erst die Kette aus Punkten und ^ hinab, dann den Schlüssel von innen nach außen bauen.
class function TDuplicateAssignmentRule.TargetKey(ANode: TSyntaxNode): string;
var
  Chain: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Base: string;
begin
  Chain := TStack<TSyntaxNode>.Create;
  try
    Node := ANode;
    while (Node.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Dereference]) and (Node.ChildCount = 1) do
    begin
      Chain.Push(Node);
      Node := Node[0];
    end;
    Result := '';
    if Node.Kind = TSyntaxKind.Identifier then
      Result := Node.Name;
    while Chain.Count > 0 do
    begin
      Node := Chain.Pop;
      Base := Result;
      Result := '';
      if Node.Kind = TSyntaxKind.MemberAccess then
      begin
        if SameText(Base, 'Self') then
          Result := Node.Name
        else if Base <> '' then
          Result := Base + '.' + Node.Name;
      end
      else if Base <> '' then
        Result := Base + '^';
    end;
  finally
    Chain.Free;
  end;
end;

class function TDuplicateAssignmentRule.Counterpart(const AName: string): string;
var
  Index: Integer;
begin
  for Index := Low(CounterpartPairs) to High(CounterpartPairs) do
    if SameText(CounterpartPairs[Index, 0], AName) then
      Exit(CounterpartPairs[Index, 1])
    else if SameText(CounterpartPairs[Index, 1], AName) then
      Exit(CounterpartPairs[Index, 0]);
  Result := '';
end;

/// <summary>Teile des Schlüssels "Panel.Font.Size" bzw. "P^.X" ohne ^.</summary>
function KeyParts(const AKey: string): TArray<string>;
begin
  Result := StringReplace(AKey, '^', '', [rfReplaceAll]).Split(['.']);
end;

/// <summary>Kommt unter ANode ein Bezeichner aus AParts vor, ein Aufruf oder etwas, das Code ausführt?
/// Dann kann der Ausdruck den ersten Wert lesen.</summary>
// Iterativ (Bericht M1).
function MayRead(ANode: TSyntaxNode; const AParts: TArray<string>): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if Node.Kind in [TSyntaxKind.Call, TSyntaxKind.InheritedExpr, TSyntaxKind.AnonymousMethod] then
        Exit(True);
      if (Node.Kind = TSyntaxKind.Identifier) and MatchText(Node.Name, AParts) then
        Exit(True);
      for Index := Node.ChildCount - 1 downto 0 do
        Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Lokale Namen von ARoutine und umschließenden Routinen: Variablen, Parameter, Result, Routinenname.</summary>
function LocalNames(ANode: TSyntaxNode): TArray<string>;
var
  Section, Parameters: TSyntaxNode;
  InlineVars: TArray<TSyntaxNode>;
  Index, Inner: Integer;
begin
  Result := nil;
  while ANode <> nil do
  begin
    if ANode.Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := Result + ['Result', ShortName(ANode.Name)];
      for Index := 0 to ANode.ChildCount - 1 do
      begin
        Section := ANode[Index];
        if Section.Kind = TSyntaxKind.VarSection then
          for Inner := 0 to Section.ChildCount - 1 do
            Result := Result + SplitNames(Section[Inner].Name)
        else if Section.Kind = TSyntaxKind.RoutineHeader then
        begin
          Parameters := Section.FindChild(TSyntaxKind.Parameters);
          if Parameters <> nil then
            for Inner := 0 to Parameters.ChildCount - 1 do
              Result := Result + SplitNames(Parameters[Inner].Name);
        end
        else if Section.Kind = TSyntaxKind.Block then
        begin
          InlineVars := nil;
          CollectInlineVars(Section, InlineVars);
          for Inner := 0 to High(InlineVars) do
            Result := Result + SplitNames(InlineVars[Inner].Name);
        end;
      end;
    end;
    ANode := ANode.Parent;
  end;
end;

function IsBooleanLiteral(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and (SameText(ANode.Name, 'True') or SameText(ANode.Name, 'False'));
end;

procedure TDuplicateAssignmentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths, Allowed: TArray<string>;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, TRoutineBody.TokenAt(Tokens, ANode.StartOffset));
  end;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  // Wurzel des Schlüssels: einfache Bezeichner gehören zu Self (Feld oder Property der eigenen Klasse).
  function RootOf(const AKey: string): string;
  begin
    if Pos('.', AKey) = 0 then
      Result := 'Self'
    else
      Result := KeyParts(AKey)[0];
  end;

  // Sucht ab AFirst + 1 die nächste Zuweisung an dasselbe Ziel; dazwischen nur Zuweisungen an andere Objekte,
  // deren Werte nichts aufrufen und das Ziel nicht nennen.
  procedure CheckFrom(AParent: TSyntaxNode; AFirst: Integer; const AKey: string);
  var
    First, Second: TSyntaxNode;
    Parts: TArray<string>;
    Index, Other: Integer;
    Key, Hint, Name, Display, Swapped: string;
    Mentioned: Boolean;
  begin
    First := AParent[AFirst];
    Parts := KeyParts(AKey);
    for Index := AFirst + 1 to AParent.ChildCount - 1 do
    begin
      Second := AParent[Index];
      if (Second.Kind <> TSyntaxKind.AssignStatement) or (Second.ChildCount < 2) then
        Exit;
      Key := TargetKey(Second[0]);
      if Key = '' then
        Exit;
      if not SameText(Key, AKey) then
      begin
        if SameText(RootOf(Key), RootOf(AKey)) or MayRead(Second[1], Parts) then
          Exit;
        Continue;
      end;
      // Der zweite Wert darf den ersten nicht lesen; False/True im Wechsel stößt oft etwas an (Active, Open).
      if MayRead(Second[1], Parts) or
        (IsBooleanLiteral(First[1]) and IsBooleanLiteral(Second[1]) and not SameText(First[1].Name, Second[1].Name)) then
        Exit;
      // Bedingte Übersetzung: nur melden, wenn die zweite Zuweisung immer mit der ersten übersetzt wird.
      if not TConditionalBranches.Implies(PathOf(First), PathOf(Second)) then
        Exit;
      Name := Parts[High(Parts)];
      Display := NodeText(Second[0]);
      Hint := 'der erste Wert geht ungelesen verloren';
      if Counterpart(Name) <> '' then
      begin
        Swapped := Copy(AKey, 1, Length(AKey) - Length(Name)) + Counterpart(Name);
        Mentioned := False;
        for Other := 0 to AParent.ChildCount - 1 do
          if (AParent[Other].Kind = TSyntaxKind.AssignStatement) and (AParent[Other].ChildCount > 0) and
            SameText(TargetKey(AParent[Other][0]), Swapped) then
            Mentioned := True;
        if not Mentioned then
          Hint := 'gemeint ist vermutlich ' + Copy(Display, 1, Length(Display) - Length(Name)) + Counterpart(Name);
      end;
      AReport.Add(TTextRange.Create(Second[0].StartPos, Second[0].EndPos),
        Format('%s wird in Zeile %d schon gesetzt; %s.', [Display, First.StartPos.Line + 1, Hint]),
        TRuleConfidence.High, [TRuleFix.Jump('Zur ersten Zuweisung springen', First.StartPos)]);
      Exit;
    end;
  end;

  function IsAllowed(const AKey: string): Boolean;
  var
    Parts: TArray<string>;
    Pattern: string;
  begin
    Parts := KeyParts(AKey);
    for Pattern in Allowed do
      if MatchesWildcard(Parts[High(Parts)], Trim(Pattern)) then
        Exit(True);
    Result := False;
  end;

  // Iterativ (Bericht M1): der Stapel hält Elternknoten und Kindindex, damit jedes Kind wie bisher vor dem
  // Abstieg in seine Kinder geprüft wird.
  procedure Visit(ARoot: TSyntaxNode);
  var
    PendingParent: TStack<TSyntaxNode>;
    PendingIndex: TStack<Integer>;
    Parent, Child, LocalsOwner: TSyntaxNode;
    Index, ChildIndex: Integer;
    Key: string;
    Locals: TArray<string>;
  begin
    LocalsOwner := nil;
    PendingParent := TStack<TSyntaxNode>.Create;
    PendingIndex := TStack<Integer>.Create;
    try
      for ChildIndex := ARoot.ChildCount - 1 downto 0 do
      begin
        PendingParent.Push(ARoot);
        PendingIndex.Push(ChildIndex);
      end;
      while PendingParent.Count > 0 do
      begin
        Parent := PendingParent.Pop;
        Index := PendingIndex.Pop;
        Child := Parent[Index];
        // Nur Anweisungsfolgen; then- und else-Zweig eines if stehen auch nebeneinander.
        if (Parent.Kind in StatementLists) and (Child.Kind = TSyntaxKind.AssignStatement) and
          (Child.ChildCount >= 2) then
        begin
          Key := TargetKey(Child[0]);
          if (Key = '') or IsAllowed(Key) then
            Continue;
          // Lokale Variablen deckt unused-assignment ab.
          if Pos('.', Key) + Pos('^', Key) = 0 then
          begin
            if LocalsOwner <> Parent then
            begin
              Locals := LocalNames(Parent);
              LocalsOwner := Parent;
            end;
            if MatchText(Key, Locals) then
              Continue;
          end;
          CheckFrom(Parent, Index, Key);
        end;
        for ChildIndex := Child.ChildCount - 1 downto 0 do
        begin
          PendingParent.Push(Child);
          PendingIndex.Push(ChildIndex);
        end;
      end;
    finally
      PendingIndex.Free;
      PendingParent.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (Pos(':=', AContext.Text) = 0) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  Allowed := TRuleOptions.Strings(AContext.Options, 'allowProperties', ['Visible', 'Enabled']);
  Visit(AContext.Tree.Root);
end;

{ TEmptyRoutineRule }

function TEmptyRoutineRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('empty-routine', TRuleSeverity.Hint,
    'Methode oder Routine ohne Anweisung und ohne Kommentar');
end;

/// <summary>Kopf der Methode in ihrem Typ und der Sichtbarkeitsabschnitt davor ('' ohne Angabe).</summary>
function MemberHeader(ATypeBody: TSyntaxNode; const AName: string; out AVisibility: string): TSyntaxNode;
var
  Index: Integer;
  Visibility: string;
begin
  Result := nil;
  AVisibility := '';
  Visibility := '';
  for Index := 0 to ATypeBody.ChildCount - 1 do
    if ATypeBody[Index].Kind = TSyntaxKind.Visibility then
      Visibility := LowerCase(ATypeBody[Index].Name)
    else if (ATypeBody[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(ATypeBody[Index].Name, AName) then
    begin
      Result := ATypeBody[Index];
      AVisibility := Visibility;
      Exit;
    end;
end;

function NodesOfKind(ARoot: TSyntaxNode; AKind: TSyntaxKind): TArray<TSyntaxNode>;
var
  Found: TArray<TSyntaxNode>;
begin
  Found := nil;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = AKind then
        Found := Found + [ANode];
      Result := True;
    end);
  Result := Found;
end;

/// <summary>Nennt der Typ Interfaces (class(TBasis, IFoo) bzw. class(IFoo))? Unbekannter Typ zählt nicht.</summary>
function ListsInterfaces(ATypeBody: TSyntaxNode): Boolean;
var
  Index, Count: Integer;
  Name: string;
begin
  Result := False;
  if ATypeBody = nil then
    Exit;
  Count := 0;
  for Index := 0 to ATypeBody.ChildCount - 1 do
    if ATypeBody[Index].Kind = TSyntaxKind.TypeReference then
    begin
      Inc(Count);
      Name := ATypeBody[Index].Name;
      if (Count > 1) or ((Length(Name) > 1) and (Name[1] = 'I') and CharInSet(Name[2], ['A'..'Z'])) then
        Exit(True);
    end;
end;

function HasDirectiveIn(AHeader: TSyntaxNode; const ANames: array of string): Boolean;
var
  Index: Integer;
begin
  if AHeader <> nil then
    for Index := 0 to AHeader.ChildCount - 1 do
      if (AHeader[Index].Kind = TSyntaxKind.Directive) and MatchText(AHeader[Index].Name, ANames) then
        Exit(True);
  Result := False;
end;

procedure TEmptyRoutineRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Tokens: TArray<TPascalToken>;
  Root: TSyntaxNode;
  References: TArray<TSyntaxNode>;
  LineBreak: string;

  function Range(AStart, AEnd: Integer): TTextRange;
  begin
    Result := TRuleDerived.OffsetRange(Cache, AContext, AStart, AEnd);
  end;

  // Kommentare oder Direktiven zwischen Kopf und Ende der Routine?
  function HasCommentOrDirective(AHeader, ARoutine: TSyntaxNode): Boolean;
  var
    Token: TPascalToken;
  begin
    for Token in Tokens do
    begin
      if Token.Offset >= ARoutine.EndOffset then
        Break;
      if (Token.Offset >= AHeader.EndOffset) and (Token.Kind in [TPascalTokenKind.Comment,
        TPascalTokenKind.Directive]) then
        Exit(True);
    end;
    Result := False;
  end;

  function IsEmpty(ABlock: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    for Index := 0 to ABlock.ChildCount - 1 do
      if ABlock[Index].Kind <> TSyntaxKind.EmptyStatement then
        Exit(False);
    Result := True;
  end;

  function Referenced(const AName: string): Boolean;
  var
    Node: TSyntaxNode;
  begin
    for Node in References do
      if SameText(Node.Name, AName) then
        Exit(True);
    Result := ((AContext.FormText <> '') and TRegEx.IsMatch(AContext.FormText, '\b' + AName + '\b',
      [roIgnoreCase]));
  end;

  // Erstes Token ab AOffset.
  function TokenAt(AOffset: Integer): Integer;
  begin
    Result := 0;
    while (Result <= High(Tokens)) and (Tokens[Result].Offset < AOffset) do
      Inc(Result);
  end;

  // Ganze Zeilen von ANode samt ";" dahinter und ///-Kommentaren direkt darüber; False, wenn auf den Zeilen
  // noch anderes steht.
  function RemovalOf(ANode: TSyntaxNode; out AEdit: TRuleEdit): Boolean;
  var
    First, Last, Index, LineStart, LineEnd: Integer;
  begin
    Result := False;
    First := ANode.StartOffset;
    Index := TokenAt(ANode.StartOffset) - 1;
    while (Index >= 0) and (Tokens[Index].Kind = TPascalTokenKind.Comment) and StartsStr('///', Tokens[Index].Text) do
    begin
      First := Tokens[Index].Offset;
      Dec(Index);
    end;
    Last := ANode.EndOffset;
    Index := TokenAt(ANode.EndOffset);
    if (Index <= High(Tokens)) and Tokens[Index].IsSymbol(';') then
      Last := Tokens[Index].Offset + 1;
    if not WholeLines(AContext.Text, First, Last, LineStart, LineEnd) then
      Exit;
    // Eine Leerzeile davor fällt mit weg, damit keine doppelten Leerzeilen bleiben.
    if (LineStart >= 2) and (AContext.Text[LineStart] = #10) and
      ((AContext.Text[LineStart - 1] = #10) or ((AContext.Text[LineStart - 1] = #13) and (LineStart >= 3) and
      (AContext.Text[LineStart - 2] = #10))) then
    begin
      Dec(LineStart);
      if AContext.Text[LineStart] = #13 then
        Dec(LineStart);
    end;
    AEdit := TRuleEdit.Create(Range(LineStart, LineEnd), '');
    Result := True;
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    Header, Block, TypeBody, Member, Forward_, Node: TSyntaxNode;
    Name, Short, TypeName, Visibility, Kind, Indent: string;
    CanRemove, IsMethod: Boolean;
    Fixes: TArray<TRuleFix>;
    Edits: TArray<TRuleEdit>;
    Edit: TRuleEdit;
    BeginToken, EndToken: Integer;
    Lines: TArray<string>;
  begin
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    Block := ARoutine.FindChild(TSyntaxKind.Block);
    if (Header = nil) or (Block = nil) or not IsEmpty(Block) or HasCommentOrDirective(Header, ARoutine) then
      Exit;
    Name := Header.Name;
    Short := ShortName(Name);
    IsMethod := Pos('.', Name) > 0;
    // Nachrichten-Handler ohne Inhalt schlucken die Nachricht absichtlich.
    if HasDirectiveIn(Header, ['message']) then
      Exit;
    Member := nil;
    Visibility := '';
    if IsMethod then
    begin
      TypeName := Copy(Name, 1, LastDelimiter('.', Name) - 1);
      if Pos('<', TypeName) > 0 then
        TypeName := Copy(TypeName, 1, Pos('<', TypeName) - 1);
      TypeBody := FindTypeBody(Root, ShortName(TypeName));
      if TypeBody <> nil then
        Member := MemberHeader(TypeBody, Short, Visibility);
      // Leere virtuelle Methode als Ersatz für abstract; leerer Nachrichten-Handler; Klasse mit Interfaces:
      // der Compiler verlangt jede Interface-Methode, auch wenn sie nichts zu tun hat (Notifier der Open Tools API).
      if HasDirectiveIn(Member, ['virtual', 'dynamic', 'message']) or ListsInterfaces(TypeBody) then
        Exit;
    end;
    // Ereignis-Handler aus der Formulardatei: die IDE entfernt sie beim Speichern selbst.
    if (AContext.FormText <> '') and TRegEx.IsMatch(AContext.FormText, '=\s*' + Short + '\b', [roIgnoreCase]) then
      Exit;
    Kind := 'Routine';
    if IsMethod then
      Kind := 'Methode';
    Fixes := nil;
    // Kommentar zwischen begin und end.
    BeginToken := TokenAt(Block.StartOffset);
    EndToken := TokenAt(Block.EndOffset) - 1;
    if (BeginToken <= High(Tokens)) and Tokens[BeginToken].IsKeyword('begin') and (EndToken > BeginToken) and
      Tokens[EndToken].IsKeyword('end') then
    begin
      Lines := TTextLines.SplitLines(AContext.Text);
      Indent := '';
      if Tokens[BeginToken].StartPos.Line <= High(Lines) then
        Indent := TTextLines.IndentOf(Lines[Tokens[BeginToken].StartPos.Line]);
      Fixes := [TRuleFix.Create('Kommentar einfügen', [TRuleEdit.Create(TTextRange.Create(
        Tokens[BeginToken].EndPos, Tokens[EndToken].StartPos), LineBreak + Indent + '  // Absichtlich leer.' +
        LineBreak + Indent)])];
    end;
    // Entfernen nur, wo niemand außerhalb der Datei die Routine sehen kann und sie hier nicht vorkommt.
    Forward_ := nil;
    if IsMethod then
      CanRemove := (Member <> nil) and ((Visibility = 'private') or (Visibility = 'strict private')) and
        not MethodSignatureFixed(Root, Name) and not HasDirectiveIn(Member, ['override', 'overload'])
    else
    begin
      CanRemove := True;
      for Node in NodesOfKind(Root, TSyntaxKind.RoutineHeader) do
        if (Node <> Header) and SameText(Node.Name, Name) then
          if (Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.RoutineDecl) and
            (Node.Parent.FindChild(TSyntaxKind.Block) = nil) and (Node.Parent.Parent <> nil) and
            (Node.Parent.Parent.Kind = TSyntaxKind.ImplementationSection) and (Forward_ = nil) then
            Forward_ := Node.Parent
          else
            CanRemove := False;
    end;
    CanRemove := CanRemove and not Referenced(Short);
    if CanRemove and RemovalOf(ARoutine, Edit) then
    begin
      Edits := [Edit];
      if (Member <> nil) and RemovalOf(Member, Edit) then
        Edits := Edits + [Edit]
      else if Member <> nil then
        Edits := nil;
      if (Forward_ <> nil) and (Edits <> nil) and RemovalOf(Forward_, Edit) then
        Edits := Edits + [Edit]
      else if Forward_ <> nil then
        Edits := nil;
      if Edits <> nil then
        Fixes := Fixes + [TRuleFix.Create(Kind + ' entfernen', Edits)];
    end;
    AReport.Add(NameRange(AContext, Header, Short), Format('%s ist leer; entweder fehlt der Inhalt oder die %s ' +
      'kann weg.', [Short, Kind]), Fixes);
  end;

var
  Routine: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Root := AContext.Tree.Root;
  Tokens := AContext.Tree.Tokens;
  Cache := TRuleDerived.Open(AContext);
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  References := nil;
  for Routine in NodesOfKind(Root, TSyntaxKind.Identifier) + NodesOfKind(Root, TSyntaxKind.MemberAccess) do
    References := References + [Routine];
  for Routine in TRuleDerived.Routines(Cache, AContext) do
    CheckRoutine(Routine);
end;

procedure RegisterUnusedRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUnusedLocalRule.Create);
  ARegistry.Register(TUnusedParameterRule.Create);
  ARegistry.Register(TUnusedAssignmentRule.Create);
  ARegistry.Register(TDuplicateAssignmentRule.Create);
  ARegistry.Register(TEmptyRoutineRule.Create);
end;

end.
