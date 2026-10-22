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
//
// unused-parameter nimmt aus:
// - Parameter namens Sender und Routinen mit einem solchen (Ereignis-Handler),
// - Methoden mit override, virtual, dynamic, abstract oder message,
//   published-Methoden (DFM-Ereignisse), Methoden von Klassen mit Interfaces
//   und Methoden, deren Typdeklaration nicht in der Datei steht,
// - Routinen, die als Wert verwendet werden (@P, X := P, Aufruf(P)).
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

/// <summary>Passt AName auf das Muster? * steht für beliebig viele, ? für genau ein Zeichen;
/// ohne Groß-/Kleinschreibung.</summary>
function MatchesWildcard(const AName, APattern: string): Boolean;

procedure RegisterUnusedRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
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
  Index: Integer;
begin
  if ANode.Kind = AKind then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if ContainsKind(ANode[Index], AKind) then
      Exit(True);
  Result := False;
end;


/// <summary>Namen, die in ANode verwendet werden (klein geschrieben): Bezeichner und Schleifenvariablen.</summary>
procedure CollectUses(ANode: TSyntaxNode; ASet: TNameSet);
var
  Index: Integer;
begin
  if ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
    ASet.AddOrSetValue(LowerCase(ANode.Name), True);
  for Index := 0 to ANode.ChildCount - 1 do
    CollectUses(ANode[Index], ASet);
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
  Index: Integer;
begin
  if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
    Exit;
  if ANode.Kind = TSyntaxKind.InlineVar then
    AVars := AVars + [ANode];
  for Index := 0 to ANode.ChildCount - 1 do
    CollectInlineVars(ANode[Index], AVars);
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

/// <summary>Rumpf der Typdeklaration (Klasse, Record, Objekt, Helfer) mit diesem Namen in der Datei.</summary>
function FindTypeBody(ANode: TSyntaxNode; const ATypeName: string): TSyntaxNode;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, ATypeName) then
    for Index := 0 to ANode.ChildCount - 1 do
      if ANode[Index].Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
        TSyntaxKind.HelperType] then
        Exit(ANode[Index]);
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindTypeBody(ANode[Index], ATypeName);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
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
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName) and IsValueUse(ANode) then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if UsedAsValue(ANode[Index], AName) then
      Exit(True);
  Result := False;
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

/// <summary>Kommt AName in lokalen Routinen oder anonymen Methoden unter ANode vor?
/// AInside: ANode liegt bereits in einer solchen.</summary>
function UsedInNested(ANode: TSyntaxNode; const AName: string; AInside: Boolean): Boolean;
var
  Index: Integer;
begin
  if AInside and (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName) then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if UsedInNested(ANode[Index], AName, AInside or
      (ANode[Index].Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod])) then
      Exit(True);
  Result := False;
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

  procedure Collect(ANode: TSyntaxNode);
  var
    Child: Integer;
  begin
    if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      Exit;
    if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, Name) then
    begin
      if (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.AssignStatement) and (ANode.Parent[0] = ANode) then
        Writes.Add(ANode.Parent)
      else
        Reads.Add(ANode);
    end
    else if (ANode.Kind = TSyntaxKind.InlineVar) and (ANode.ChildCount > 0) and
      MatchText(Name, SplitNames(ANode.Name)) then
      Writes.Add(ANode);
    for Child := 0 to ANode.ChildCount - 1 do
      Collect(ANode[Child]);
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
    if IsIgnored(Name, Patterns) or HasOpaqueUse(Info.Block, Name) or UsedInNested(Routine, Name, False) or
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
            if Section[Inner].Kind = TSyntaxKind.VarDecl then
              Names := Names + SplitNames(Section[Inner].Name);
      end;
      Locals := nil;
      CollectInlineVars(Info.Block, Locals);
      for Decl in Locals do
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

class function TDuplicateAssignmentRule.TargetKey(ANode: TSyntaxNode): string;
var
  Base: string;
begin
  Result := '';
  if ANode.Kind = TSyntaxKind.Identifier then
    Result := ANode.Name
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) then
  begin
    Base := TargetKey(ANode[0]);
    if SameText(Base, 'Self') then
      Result := ANode.Name
    else if Base <> '' then
      Result := Base + '.' + ANode.Name;
  end
  else if (ANode.Kind = TSyntaxKind.Dereference) and (ANode.ChildCount = 1) then
  begin
    Base := TargetKey(ANode[0]);
    if Base <> '' then
      Result := Base + '^';
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
function MayRead(ANode: TSyntaxNode; const AParts: TArray<string>): Boolean;
var
  Index: Integer;
begin
  if ANode.Kind in [TSyntaxKind.Call, TSyntaxKind.InheritedExpr, TSyntaxKind.AnonymousMethod] then
    Exit(True);
  if (ANode.Kind = TSyntaxKind.Identifier) and MatchText(ANode.Name, AParts) then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if MayRead(ANode[Index], AParts) then
      Exit(True);
  Result := False;
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

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Child: TSyntaxNode;
    Key: string;
    Locals: TArray<string>;
    LocalsKnown: Boolean;
  begin
    LocalsKnown := False;
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Child := ANode[Index];
      // Nur Anweisungsfolgen; then- und else-Zweig eines if stehen auch nebeneinander.
      if (ANode.Kind in StatementLists) and (Child.Kind = TSyntaxKind.AssignStatement) and (Child.ChildCount >= 2) then
      begin
        Key := TargetKey(Child[0]);
        if (Key = '') or IsAllowed(Key) then
          Continue;
        // Lokale Variablen deckt unused-assignment ab.
        if Pos('.', Key) + Pos('^', Key) = 0 then
        begin
          if not LocalsKnown then
          begin
            Locals := LocalNames(ANode);
            LocalsKnown := True;
          end;
          if MatchText(Key, Locals) then
            Continue;
        end;
        CheckFrom(ANode, Index, Key);
      end;
      Visit(Child);
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

procedure RegisterUnusedRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUnusedLocalRule.Create);
  ARegistry.Register(TUnusedParameterRule.Create);
  ARegistry.Register(TUnusedAssignmentRule.Create);
  ARegistry.Register(TDuplicateAssignmentRule.Create);
end;

end.
