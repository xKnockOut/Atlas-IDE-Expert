unit BDLsp.Common.Rules.Builtin.Declarations;

// Deklaration und Rumpf passen nicht zusammen (#124):
//   declared-not-implemented   Methode im Typ ohne Rumpf (sonst erst E2065)
//   implemented-not-declared   Rumpf TFoo.Bar ohne Deklaration im Typ
//
// Den Abgleich (auch über Überladungen) liefert TClassCompletion.Unmatched aus
// #42. Abstrakte, externe und forward-Methoden, Interfaces und generische
// Typen erzeugen keinen Treffer. Methoden innerhalb von {$IF…}-Blöcken werden
// übergangen, weil der Syntaxbaum auch inaktive Zweige enthält. Bindet die
// Datei Include-Dateien ein, können dort Rümpfe stehen: dann nur mittlere
// Konfidenz (höchstens Warnung).
//
// Korrekturen: "Rumpf erzeugen" (#42) bzw. "Deklaration ergänzen" im
// private-Abschnitt.

interface

uses
  System.SysUtils,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Registry;

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

procedure RegisterDeclarationRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Editing.CodeActions,
  BDLsp.Common.Editing.ClassCompletion;

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
  Method: TUnmatchedMethod;
  Action: TCodeAction;
  Message: string;
  Level: TRuleConfidence;
begin
  if AContext.Tree = nil then
    Exit;
  Lines := ConditionalLines(AContext);
  Level := Confidence(AContext);
  for Method in TClassCompletion.Unmatched(AContext.Tree, AContext.Text) do
  begin
    if not Method.Declared or IsConditional(Lines, Method) then
      Continue;
    Message := Format('"%s.%s" ist deklariert, aber nicht implementiert', [Method.TypeName, Method.Symbol.Name]);
    if TClassCompletion.MissingBodies(AContext.Tree, AContext.Text, Method.Symbol.SelectionRange.StartPos, Action) then
      AReport.Add(Method.Symbol.SelectionRange, Message, Level, [TRuleFix.Create(Action.Title, Action.Edits)])
    else
      AReport.Add(Method.Symbol.SelectionRange, Message, Level);
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
  Method: TUnmatchedMethod;
  Edit: TRuleEdit;
  Message: string;
  Level: TRuleConfidence;
begin
  if AContext.Tree = nil then
    Exit;
  Lines := ConditionalLines(AContext);
  Level := Confidence(AContext);
  for Method in TClassCompletion.Unmatched(AContext.Tree, AContext.Text) do
  begin
    if Method.Declared or IsConditional(Lines, Method) then
      Continue;
    Message := Format('"%s.%s" hat keine passende Deklaration in %s',
      [Method.TypeName, Method.Symbol.Name, Method.TypeName]);
    if TClassCompletion.AddDeclaration(AContext.Tree, AContext.Text, Method, Edit) then
      AReport.Add(Method.Symbol.SelectionRange, Message, Level,
        [TRuleFix.Create(Format('Deklaration von %s in %s ergänzen', [Method.Symbol.Name, Method.TypeName]), [Edit])])
    else
      AReport.Add(Method.Symbol.SelectionRange, Message, Level);
  end;
end;

procedure RegisterDeclarationRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDeclaredNotImplementedRule.Create);
  ARegistry.Register(TImplementedNotDeclaredRule.Create);
end;

end.
