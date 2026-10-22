unit Atlas.Common.Rules.Builtin.Declarations;

// Deklaration und Rumpf passen nicht zusammen (#124):
//   declared-not-implemented   Methode im Typ ohne Rumpf (sonst erst E2065)
//   implemented-not-declared   Rumpf TFoo.Bar ohne Deklaration im Typ
//   signature-mismatch         Rumpf und Deklaration gleichen Namens mit
//                              abweichendem Kopf (#996, wie E2037): Parameter
//                              (Anzahl, Name, Typ, const/var/out), Ergebnistyp,
//                              procedure/function, Aufrufkonvention
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

  TSignatureMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Abweichungen des Rumpfs ABody von der Deklaration ADeclaration, z. B. "Betrag ohne const",
    /// "Datum TDateTime statt TDate"; leer, wenn die Köpfe gleich sind.</summary>
    class function Differences(const ADeclaration, ABody: TSignatureShape): TArray<string>; static;
  end;

procedure RegisterDeclarationRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.CodeActions;

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

procedure RegisterDeclarationRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDeclaredNotImplementedRule.Create);
  ARegistry.Register(TImplementedNotDeclaredRule.Create);
  ARegistry.Register(TSignatureMismatchRule.Create);
end;

end.
