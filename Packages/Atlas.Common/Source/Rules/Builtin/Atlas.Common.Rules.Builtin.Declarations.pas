unit Atlas.Common.Rules.Builtin.Declarations;

// Deklaration und Rumpf passen nicht zusammen (#124):
//   declared-not-implemented   Methode im Typ ohne Rumpf (sonst erst E2065)
//   implemented-not-declared   Rumpf TFoo.Bar ohne Deklaration im Typ
//   signature-mismatch         Rumpf und Deklaration gleichen Namens mit
//                              abweichendem Kopf (#996, wie E2037): Parameter
//                              (Anzahl, Name, Typ, const/var/out), Ergebnistyp,
//                              procedure/function, Aufrufkonvention
//   interface-not-implemented  Klasse nennt ein Interface, dem Methoden fehlen
//   field-after-method         Feld nach Methode oder Property im selben
//                              Abschnitt (#986, wie E2169); Korrektur:
//                              Feld an den Anfang verschieben oder var davor
//                              (#1000, wie E2291), bzw. Zuordnung IFoo.Bar = Baz
//                              für ein nicht genanntes Interface (wie E2265).
//                              Geerbte Methoden, Zuordnungen und implements
//                              zählen; bricht die Kette der Vorfahrklassen ab,
//                              bleibt die Regel still (TNameResolver.
//                              MissingInterfaceMembers mit AComplete)
//
// Den Abgleich (auch über Überladungen) liefert TClassCompletion.Unmatched aus
// #42; Paare mit abweichendem Kopf ordnet TClassCompletion.Pairs zu. Sie meldet
// nur signature-mismatch, die beiden anderen Regeln finden fehlende Namen. Abstrakte, externe und forward-Methoden, Interfaces und generische
// Typen erzeugen keinen Treffer. Methoden innerhalb von {$IF…}-Blöcken werden
// übergangen, weil der Syntaxbaum auch inaktive Zweige enthält. Bindet die
// Datei Include-Dateien ein, können dort Rümpfe stehen: dann nur mittlere
// Konfidenz (höchstens Warnung).
//
// Korrekturen: "Rumpf erzeugen" (#42) bzw. "Deklaration ergänzen" im
// private-Abschnitt; bei signature-mismatch "Implementierung an die
// Deklaration angleichen" und als zweite Aktion umgekehrt (#100).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Editing.ClassCompletion;

type
  TDeclaredNotImplementedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TImplementedNotDeclaredRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInterfaceNotImplementedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Interfaces, die eine Property der Klasse mit implements übernimmt (Token im Bereich ARange).</summary>
    class function Delegated(const ATokens: TArray<TPascalToken>; const ARange: TTextRange): TArray<string>; static;
  end;

  TSignatureMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Abweichungen des Rumpfs ABody von der Deklaration ADeclaration, z. B. "Betrag ohne const",
    /// "Datum TDateTime statt TDate"; leer, wenn die Köpfe gleich sind.</summary>
    class function Differences(const ADeclaration, ABody: TSignatureShape): TArray<string>; static;
  end;

  TFieldAfterMethodRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  FieldAfterMethodRuleId = 'field-after-method';

procedure RegisterDeclarationRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Text.Lines;

/// <summary>Zeilen innerhalb von {$IF…}…{$ENDIF}: Element I gilt für Zeile I.</summary>
function ConditionalLines(const AContext: TRuleContext): TArray<Boolean>;
var
  Token: TPascalToken;
  Text: string;
  Depth, Line, LastLine, StartLine: Integer;
begin
  LastLine := 0;
  for Token in AContext.Tree.Tokens do
    LastLine := Token.EndPos.Line;
  SetLength(Result, LastLine + 1);
  Depth := 0;
  StartLine := 0;
  for Token in AContext.Tree.Tokens do
  begin
    if Token.Kind <> TPascalTokenKind.Directive then
      Continue;
    Text := UpperCase(Token.Text);
    if StartsStr('{$IF', Text) or StartsStr('(*$IF', Text) then
    begin
      if Depth = 0 then
        StartLine := Token.StartPos.Line;
      Inc(Depth);
    end
    else if (Depth > 0) and (StartsStr('{$ENDIF', Text) or StartsStr('{$IFEND', Text) or
      StartsStr('(*$ENDIF', Text) or StartsStr('(*$IFEND', Text)) then
    begin
      Dec(Depth);
      if Depth = 0 then
        for Line := StartLine to Token.EndPos.Line do
          Result[Line] := True;
    end;
  end;
  // Nicht geschlossener Block: bis zum Dateiende.
  if Depth > 0 then
    for Line := StartLine to LastLine do
      Result[Line] := True;
end;

/// <summary>Bindet die Datei Include-Dateien ein ({$I datei} oder {$INCLUDE datei})?</summary>
function HasIncludes(const AContext: TRuleContext): Boolean;
var
  Token: TPascalToken;
  Text: string;
begin
  for Token in AContext.Tree.Tokens do
    if Token.Kind = TPascalTokenKind.Directive then
    begin
      Text := UpperCase(Token.Text);
      // {$I+} und {$I-} schalten die E/A-Prüfung um und sind keine Includes.
      if StartsStr('{$INCLUDE ', Text) or StartsStr('{$I ', Text) then
        Exit(True);
    end;
  Result := False;
end;

function IsConditional(const ALines: TArray<Boolean>; const AMethod: TUnmatchedMethod): Boolean;
var
  Line: Integer;
begin
  Line := AMethod.Symbol.Range.StartPos.Line;
  Result := (Line >= 0) and (Line <= High(ALines)) and ALines[Line];
end;

/// <summary>AFix als gleichrangige Alternative markieren, wenn schon andere Korrekturen vorliegen.</summary>
function Alternative(const AFix: TRuleFix; AIsAlternative: Boolean): TRuleFix;
begin
  Result := AFix;
  Result.Alternative := AIsAlternative;
end;

/// <summary>Gehört AMethod zu einem Paar mit abweichendem Kopf? Das meldet signature-mismatch.</summary>
function InPair(const APairs: TArray<TSignaturePair>; const AMethod: TUnmatchedMethod): Boolean;
var
  Pair: TSignaturePair;
begin
  for Pair in APairs do
    if (Pair.Declaration.Symbol.SelectionRange.StartPos = AMethod.Symbol.SelectionRange.StartPos) or
      (Pair.Body.Symbol.SelectionRange.StartPos = AMethod.Symbol.SelectionRange.StartPos) then
      Exit(True);
  Result := False;
end;

function Confidence(const AContext: TRuleContext): TRuleConfidence;
begin
  if HasIncludes(AContext) then
    Result := TRuleConfidence.Medium
  else
    Result := TRuleConfidence.High;
end;

{ TDeclaredNotImplementedRule }

function TDeclaredNotImplementedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('declared-not-implemented', TRuleSeverity.Error,
    'Methode ist deklariert, aber nicht implementiert');
end;

procedure TDeclaredNotImplementedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<Boolean>;
  Pairs: TArray<TSignaturePair>;
  Method: TUnmatchedMethod;
  Action: TCodeAction;
  Fixes: TArray<TRuleFix>;
  Level: TRuleConfidence;
begin
  if AContext.Tree = nil then
    Exit;
  Lines := ConditionalLines(AContext);
  Level := Confidence(AContext);
  Pairs := TClassCompletion.Pairs(AContext.Tree, AContext.Text);
  for Method in TClassCompletion.Unmatched(AContext.Tree, AContext.Text) do
  begin
    if not Method.Declared or IsConditional(Lines, Method) or InPair(Pairs, Method) then
      Continue;
    Fixes := nil;
    if TClassCompletion.MissingBodies(AContext.Tree, AContext.Text, Method.Symbol.SelectionRange.StartPos, Action) then
      Fixes := [TRuleFix.Create(Action.Title, Action.Edits)];
    AReport.Add(Method.Symbol.SelectionRange, Format('"%s.%s" ist deklariert, aber nicht implementiert',
      [Method.TypeName, Method.Symbol.Name]), Level, Fixes);
  end;
end;

{ TImplementedNotDeclaredRule }

function TImplementedNotDeclaredRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('implemented-not-declared', TRuleSeverity.Error,
    'Methodenrumpf ohne Deklaration im Typ');
end;

procedure TImplementedNotDeclaredRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<Boolean>;
  Pairs: TArray<TSignaturePair>;
  Method: TUnmatchedMethod;
  Edit: TRuleEdit;
  Fixes: TArray<TRuleFix>;
  Level: TRuleConfidence;
begin
  if AContext.Tree = nil then
    Exit;
  Lines := ConditionalLines(AContext);
  Level := Confidence(AContext);
  Pairs := TClassCompletion.Pairs(AContext.Tree, AContext.Text);
  for Method in TClassCompletion.Unmatched(AContext.Tree, AContext.Text) do
  begin
    if Method.Declared or IsConditional(Lines, Method) or InPair(Pairs, Method) then
      Continue;
    Fixes := nil;
    if TClassCompletion.AddDeclaration(AContext.Tree, AContext.Text, Method, Edit) then
      Fixes := [TRuleFix.Create(Format('Deklaration von %s in %s ergänzen', [Method.Symbol.Name,
        Method.TypeName]), [Edit])];
    AReport.Add(Method.Symbol.SelectionRange, Format('"%s.%s" hat keine passende Deklaration in %s',
      [Method.TypeName, Method.Symbol.Name, Method.TypeName]), Level, Fixes);
  end;
end;

{ TInterfaceNotImplementedRule }

function TInterfaceNotImplementedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('interface-not-implemented', TRuleSeverity.Error,
    'Interface-Methode fehlt in der Klasse (wie E2291)');
end;

class function TInterfaceNotImplementedRule.Delegated(const ATokens: TArray<TPascalToken>;
  const ARange: TTextRange): TArray<string>;
var
  Index: Integer;
  Name: string;
begin
  Result := nil;
  Index := 0;
  while Index <= High(ATokens) do
  begin
    if (ATokens[Index].StartPos.Line >= ARange.StartPos.Line) and (ATokens[Index].EndPos.Line <= ARange.EndPos.Line) and
      SameText(ATokens[Index].Text, 'implements') and (ATokens[Index].Kind = TPascalTokenKind.Identifier) then
    begin
      // implements IFoo, Units.IBar;
      Inc(Index);
      Name := '';
      while (Index <= High(ATokens)) and not ATokens[Index].IsSymbol(';') do
      begin
        if ATokens[Index].IsSymbol(',') then
        begin
          Result := Result + [Name];
          Name := '';
        end
        else if ATokens[Index].Kind <> TPascalTokenKind.Comment then
          Name := Name + ATokens[Index].Text;
        Inc(Index);
      end;
      if Name <> '' then
        Result := Result + [Name];
    end;
    Inc(Index);
  end;
end;

/// <summary>"A", "A und B", "A, B und C".</summary>
function JoinedList(const AItems: TArray<string>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AItems) do
  begin
    if Index = 0 then
      Result := AItems[Index]
    else if Index = High(AItems) then
      Result := Result + ' und ' + AItems[Index]
    else
      Result := Result + ', ' + AItems[Index];
  end;
end;

function BareName(const AText: string): string;
begin
  Result := Trim(AText);
  if Pos('<', Result) > 0 then
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

/// <summary>Methode AName der Klasse ATypeName (ohne Zuordnungen); Name leer, wenn es keine gibt.</summary>
function OwnMethod(const AUnit: TUnitIndex; const ATypeName, AName: string): TIndexSymbol;
var
  Symbol: TIndexSymbol;
begin
  Result := Default(TIndexSymbol);
  for Symbol in AUnit.Symbols do
    if SameText(Symbol.Container, ATypeName) and SameText(Symbol.Name, AName) and
      (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) then
      Exit(Symbol);
end;

procedure TInterfaceNotImplementedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<Boolean>;
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  OwnUnit: TUnitIndex;
  TypeSymbol, Symbol: TIndexSymbol;
  TypeName, Ancestor, Prefix: string;
  Missing: TArray<TResolvedSymbol>;
  Member: TResolvedSymbol;
  Names: TList<string>;
  Complete, Listed, Differs: Boolean;
  Own: TIndexSymbol;
  Actions: TClassActionContext;
  Action: TCodeAction;
  Fixes: TArray<TRuleFix>;
  Level: TRuleConfidence;
begin
  if AContext.Tree = nil then
    Exit;
  Lines := ConditionalLines(AContext);
  Level := Confidence(AContext);
  // Ohne Projektindex prüft die Regel nur, was die Datei selbst kennt; unbekannte Vorfahren halten sie still.
  Index := AContext.Index;
  if Index = nil then
    Index := TSymbolIndex.Create;
  Resolver := TNameResolver.Create(Index, AContext.EnsureUnit);
  Names := TList<string>.Create;
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, AContext.RelativePath);
    try
      OwnUnit := Resolver.ExtractedUnit(AContext.Tree, AContext.RelativePath);
      Actions := TClassActionContext.Default;
      Actions.Index := Index;
      Actions.Namespaces := AContext.Namespaces;
      Actions.DelphiVersion := AContext.DelphiVersion;
      Actions.Style := AContext.Formatting;
      for TypeSymbol in OwnUnit.Symbols do
      begin
        if (TypeSymbol.Kind <> TIndexSymbolKind.ClassType) or (Length(TypeSymbol.Ancestors) = 0) or
          ((TypeSymbol.SelectionRange.StartPos.Line <= High(Lines)) and Lines[TypeSymbol.SelectionRange.StartPos.Line]) then
          Continue;
        TypeName := TypeSymbol.Name;
        if TypeSymbol.Container <> '' then
          TypeName := TypeSymbol.Container + '.' + TypeName;
        Missing := Resolver.MissingInterfaceMembers(OwnUnit, TypeName, nil,
          Delegated(AContext.Tree.Tokens, TypeSymbol.Range), Complete);
        if Complete and (Length(Missing) > 0) then
        begin
          Names.Clear;
          Differs := False;
          for Member in Missing do
          begin
            // Gleichnamige Methode der Klasse mit anderer Signatur: E2211 an der Methode statt "fehlt".
            Own := OwnMethod(OwnUnit, TypeName, Member.Name);
            if Own.Name <> '' then
            begin
              Differs := True;
              AReport.Add(Own.SelectionRange, Format('%s weicht von der Deklaration in %s ab (wie E2211).',
                [Own.Name, BareName(Member.Container)]), Level);
            end
            else if not Names.Contains(BareName(Member.Container) + '.' + Member.Name) then
              Names.Add(BareName(Member.Container) + '.' + Member.Name);
          end;
          Names.Sort;
          // Bei abweichenden Köpfen fügte die Korrektur eine zweite gleichnamige Methode ein; dann keine.
          Fixes := nil;
          if not Differs then
            for Ancestor in TypeSymbol.Ancestors do
              if TClassActions.ImplementInterface(AContext.Text, TypeSymbol.Range.StartPos.Line, Ancestor, Actions,
                Action) then
                Fixes := Fixes + [Alternative(TRuleFix.Create(Action.Title, Action.Edits), Length(Fixes) > 0)];
          if Names.Count = 1 then
            AReport.Add(TypeSymbol.SelectionRange, Format('%s fehlt in %s (wie E2291).', [Names[0], TypeSymbol.Name]),
              Level, Fixes)
          else if Names.Count > 1 then
            AReport.Add(TypeSymbol.SelectionRange, Format('%s fehlen in %s (wie E2291).',
              [JoinedList(Names.ToArray), TypeSymbol.Name]), Level, Fixes);
        end;
        // Zuordnung "procedure IFoo.Bar = Baz" für ein Interface, das die Klasse nicht nennt.
        for Symbol in OwnUnit.Symbols do
        begin
          if not SameText(Symbol.Container, TypeName) or (Pos('.', Symbol.Name) = 0) or
            not (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) then
            Continue;
          Prefix := BareName(Copy(Symbol.Name, 1, LastDelimiter('.', Symbol.Name) - 1));
          Listed := False;
          for Ancestor in TypeSymbol.Ancestors do
            if SameText(BareName(Ancestor), Prefix) then
              Listed := True;
          if not Listed then
            AReport.Add(Symbol.SelectionRange, Format('%s steht nicht in der Interface-Liste von %s (wie E2265).',
              [Prefix, TypeSymbol.Name]), Level);
        end;
      end;
    finally
      Resolver.UnpinTree;
    end;
  finally
    Names.Free;
    Resolver.Free;
  end;
end;

{ TSignatureMismatchRule }

function TSignatureMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('signature-mismatch', TRuleSeverity.Error,
    'Implementierung weicht von der Deklaration ab (wie E2037)');
end;

class function TSignatureMismatchRule.Differences(const ADeclaration, ABody: TSignatureShape): TArray<string>;

  function Normalized(const AText: string): string;
  begin
    Result := LowerCase(StringReplace(AText, ' ', '', [rfReplaceAll]));
  end;

  function ConventionOf(const AShape: TSignatureShape): string;
  begin
    Result := AShape.Convention;
    if Result = '' then
      Result := 'register';
  end;

var
  Index: Integer;
  Decl, Body: TSignatureParameter;
begin
  Result := nil;
  if (ADeclaration.Kind <> '') and (ABody.Kind <> '') and (ADeclaration.Kind <> ABody.Kind) then
    Result := Result + [Format('%s statt %s', [ABody.Kind, ADeclaration.Kind])];
  if Length(ADeclaration.Parameters) <> Length(ABody.Parameters) then
    Result := Result + [Format('%d statt %d Parameter', [Length(ABody.Parameters), Length(ADeclaration.Parameters)])]
  else
    for Index := 0 to High(ABody.Parameters) do
    begin
      Decl := ADeclaration.Parameters[Index];
      Body := ABody.Parameters[Index];
      if not SameText(Decl.Name, Body.Name) then
        Result := Result + [Format('%s statt %s', [Body.Name, Decl.Name])];
      if Decl.Modifier <> Body.Modifier then
      begin
        if Body.Modifier = '' then
          Result := Result + [Format('%s ohne %s', [Body.Name, Decl.Modifier])]
        else if Decl.Modifier = '' then
          Result := Result + [Format('%s mit %s', [Body.Name, Body.Modifier])]
        else
          Result := Result + [Format('%s %s statt %s', [Body.Name, Body.Modifier, Decl.Modifier])];
      end;
      if Normalized(Decl.TypeName) <> Normalized(Body.TypeName) then
      begin
        if Body.TypeName = '' then
          Result := Result + [Format('%s ohne Typ statt %s', [Body.Name, Decl.TypeName])]
        else if Decl.TypeName = '' then
          Result := Result + [Format('%s %s statt ohne Typ', [Body.Name, Body.TypeName])]
        else
          Result := Result + [Format('%s %s statt %s', [Body.Name, Body.TypeName, Decl.TypeName])];
      end;
    end;
  if (ADeclaration.Kind = ABody.Kind) and (Normalized(ADeclaration.ResultType) <> Normalized(ABody.ResultType)) then
    Result := Result + [Format('Ergebnis %s statt %s', [ABody.ResultType, ADeclaration.ResultType])];
  // Der Rumpf darf die Konvention weglassen; nur eine abweichende Angabe ist ein Fehler.
  if (ABody.Convention <> '') and (ConventionOf(ABody) <> ConventionOf(ADeclaration)) then
    Result := Result + [Format('%s statt %s', [ABody.Convention, ConventionOf(ADeclaration)])];
end;

procedure TSignatureMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<Boolean>;
  Pair: TSignaturePair;
  Changes: TArray<string>;
  Actions: TArray<TCodeAction>;
  Fixes: TArray<TRuleFix>;
  Index: Integer;
  Level: TRuleConfidence;
begin
  if AContext.Tree = nil then
    Exit;
  Lines := ConditionalLines(AContext);
  Level := Confidence(AContext);
  for Pair in TClassCompletion.Pairs(AContext.Tree, AContext.Text) do
  begin
    if IsConditional(Lines, Pair.Declaration) or IsConditional(Lines, Pair.Body) then
      Continue;
    Changes := Differences(Pair.DeclarationShape, Pair.BodyShape);
    if Changes = nil then
      Continue;
    Fixes := nil;
    // refactoring.syncSignatures aus (#100): die Meldung bleibt, die Angleich-Aktionen entfallen.
    if not AContext.NoSignatureSync and TClassCompletion.PairFixes(AContext.Tree, AContext.Text, Pair, Actions) then
      for Index := 0 to High(Actions) do
        Fixes := Fixes + [Alternative(TRuleFix.Create(Actions[Index].Title, Actions[Index].Edits), Index > 0)];
    AReport.Add(Pair.Body.Symbol.SelectionRange, Format('%s weicht von der Deklaration ab: %s (wie E2037).',
      [Pair.Body.Symbol.Name, string.Join(', ', Changes)]), Level, Fixes);
  end;
end;

{ TFieldAfterMethodRule }

function TFieldAfterMethodRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FieldAfterMethodRuleId, TRuleSeverity.Error,
    'Feld nach Methoden im selben Abschnitt');
end;

procedure TFieldAfterMethodRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Lines: TArray<string>;
  LineBreak: string;
  Paths: TArray<string>;

  function FirstToken(ANode: TSyntaxNode): Integer;
  var
    Low, High, Middle: Integer;
  begin
    Low := 0;
    High := Length(Tokens);
    while Low < High do
    begin
      Middle := (Low + High) div 2;
      if Tokens[Middle].Offset < ANode.StartOffset then
        Low := Middle + 1
      else
        High := Middle;
    end;
    Result := Low;
  end;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, FirstToken(ANode));
  end;

  function OnlySpaceBefore(const APosition: TTextPosition): Boolean;
  begin
    Result := (APosition.Line < Length(Lines)) and (Trim(Copy(Lines[APosition.Line], 1, APosition.Character)) = '');
  end;

  function OnlyCommentAfter(const APosition: TTextPosition): Boolean;
  var
    Rest: string;
  begin
    Result := False;
    if APosition.Line >= Length(Lines) then
      Exit;
    Rest := Trim(Copy(Lines[APosition.Line], APosition.Character + 1, MaxInt));
    Result := (Rest = '') or Rest.StartsWith('//');
  end;

  // Erstes Kind des Blocks um ABody[AIndex]: davorstehende Attribute gehören dazu.
  function BlockFirst(ABody: TSyntaxNode; AIndex: Integer): TSyntaxNode;
  begin
    while (AIndex > 0) and (ABody[AIndex - 1].Kind = TSyntaxKind.Attribute) do
      Dec(AIndex);
    Result := ABody[AIndex];
  end;

  // Erste Zeile des Blocks ab ANode samt Kommentarzeilen direkt darüber (XMLDoc).
  function StartLine(ANode: TSyntaxNode): Integer;
  var
    Index: Integer;
  begin
    Result := ANode.StartPos.Line;
    Index := FirstToken(ANode) - 1;
    while (Index >= 0) and (Tokens[Index].Kind = TPascalTokenKind.Comment) and
      (Tokens[Index].EndPos.Line = Result - 1) and OnlySpaceBefore(Tokens[Index].StartPos) do
    begin
      Result := Tokens[Index].StartPos.Line;
      Dec(Index);
    end;
  end;

  // Feld samt Attributen und Kommentaren vor das erste Mitglied des Abschnitts; nil, wenn Zeilen nicht passen.
  function MoveFix(ABody: TSyntaxNode; AField, AMember: Integer): TArray<TRuleFix>;
  var
    Field, Target: TSyntaxNode;
    FieldStart, FieldEnd, TargetLine, Line: Integer;
    Moved: string;
  begin
    Result := nil;
    Field := BlockFirst(ABody, AField);
    Target := BlockFirst(ABody, AMember);
    if not OnlySpaceBefore(Field.StartPos) or not OnlySpaceBefore(Target.StartPos) or
      not OnlyCommentAfter(ABody[AField].EndPos) then
      Exit;
    FieldStart := StartLine(Field);
    FieldEnd := ABody[AField].EndPos.Line;
    TargetLine := StartLine(Target);
    if (TargetLine >= FieldStart) or (FieldEnd + 1 >= Length(Lines)) then
      Exit;
    Moved := '';
    for Line := FieldStart to FieldEnd do
      Moved := Moved + Lines[Line] + LineBreak;
    Result := [TRuleFix.Create('Feld an den Anfang des Abschnitts verschieben', [
      TRuleEdit.Create(TTextRange.Create(TargetLine, 0, TargetLine, 0), Moved),
      TRuleEdit.Create(TTextRange.Create(FieldStart, 0, FieldEnd + 1, 0), '')], True)];
  end;

  function VarFix(ABody: TSyntaxNode; AField: Integer): TRuleFix;
  var
    First: TSyntaxNode;
  begin
    First := BlockFirst(ABody, AField);
    Result := TRuleFix.Create('var davor setzen', [TRuleEdit.Create(TTextRange.Create(First.StartPos,
      First.StartPos), 'var ')], True);
  end;

  procedure CheckBody(ABody: TSyntaxNode);
  var
    Index, Member, First: Integer;
    Fixes: TArray<TRuleFix>;
    SamePaths: Boolean;
  begin
    First := -1;
    SamePaths := True;
    for Index := 0 to ABody.ChildCount - 1 do
      case ABody[Index].Kind of
        // Ein neuer Abschnitt bzw. var erlaubt wieder Felder.
        TSyntaxKind.Visibility, TSyntaxKind.VarSection, TSyntaxKind.TypeSection, TSyntaxKind.ConstSection:
          begin
            First := -1;
            SamePaths := True;
          end;
        TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl:
          begin
            if First < 0 then
              First := Index
            else if PathOf(ABody[Index]) <> PathOf(ABody[First]) then
              SamePaths := False;
          end;
        TSyntaxKind.Field:
          if First >= 0 then
          begin
            // Nur, wenn eine Methode davor immer mit übersetzt wird, wenn das Feld übersetzt wird.
            Member := First;
            while (Member < Index) and not ((ABody[Member].Kind in [TSyntaxKind.RoutineHeader,
              TSyntaxKind.PropertyDecl]) and TConditionalBranches.Implies(PathOf(ABody[Index]),
              PathOf(ABody[Member]))) do
              Inc(Member);
            if Member >= Index then
              Continue;
            Fixes := nil;
            // Verschieben nur ohne Bedingungen dazwischen, sonst landet das Feld in einem anderen Zweig.
            if SamePaths and (PathOf(ABody[Index]) = PathOf(ABody[First])) then
              Fixes := MoveFix(ABody, Index, First);
            if ABody.Kind = TSyntaxKind.RecordType then
              // In Records verschiebt das Verschieben das Speicherlayout; var zuerst.
              Fixes := [VarFix(ABody, Index)] + Fixes
            else
              Fixes := Fixes + [VarFix(ABody, Index)];
            AReport.Add(TTextRange.Create(ABody[Index].StartPos, ABody[Index].EndPos),
              'Feld nach Methoden im selben Abschnitt (wie E2169).', TRuleConfidence.High, Fixes);
          end;
      end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType] then
      CheckBody(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Paths := TConditionalBranches.Paths(Tokens);
  Visit(AContext.Tree.Root);
end;

procedure RegisterDeclarationRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDeclaredNotImplementedRule.Create);
  ARegistry.Register(TImplementedNotDeclaredRule.Create);
  ARegistry.Register(TSignatureMismatchRule.Create);
  ARegistry.Register(TInterfaceNotImplementedRule.Create);
  ARegistry.Register(TFieldAfterMethodRule.Create);
end;

end.
