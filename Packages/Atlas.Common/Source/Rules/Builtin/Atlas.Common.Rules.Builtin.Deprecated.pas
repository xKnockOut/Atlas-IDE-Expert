unit Atlas.Common.Rules.Builtin.Deprecated;

// Verwendung veralteter Symbole (#38), wie die Compilerwarnungen W1000, W1002
// und W1003: Ein Bezeichner, der sich auf eine Deklaration mit deprecated,
// platform oder experimental auflöst, bekommt einen Treffer. Die LSP-Schicht
// hängt das Diagnose-Tag Deprecated an (durchgestrichen). Der Grund aus
// deprecated 'Grund' steht in der Meldung. Nicht gemeldet werden die
// Deklaration selbst und der Name im Kopf einer Implementierung. Ohne Index
// (Linter) schweigt die Regel.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  DeprecatedSymbolRuleId = 'deprecated-symbol';

type
  TDeprecatedSymbolRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterDeprecatedRules(ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver;

const
  HintWords: array[0..2] of string = ('deprecated', 'platform', 'experimental');

function HasHint(const ASymbol: TIndexSymbol): Boolean;
var
  Word: string;
begin
  for Word in HintWords do
    if ASymbol.HasDirective(Word) then
      Exit(True);
  Result := False;
end;

/// <summary>Meldung zu einem Symbol mit Hinweis-Direktive; '' ohne.</summary>
function MessageOf(const AName: string; const ASymbol: TIndexSymbol): string;
begin
  Result := '';
  if ASymbol.HasDirective('deprecated') then
  begin
    Result := Format('"%s" ist veraltet', [AName]);
    if ASymbol.DeprecatedText <> '' then
      Result := Result + ': ' + ASymbol.DeprecatedText;
  end
  else if ASymbol.HasDirective('experimental') then
    Result := Format('"%s" ist experimentell', [AName])
  else if ASymbol.HasDirective('platform') then
    Result := Format('"%s" ist plattformspezifisch', [AName]);
end;

/// <summary>Offsets der Namen in Routinenköpfen (procedure TFoo.Bar): Deklaration bzw. Implementierung,
/// keine Verwendung.</summary>
function HeaderNameOffsets(ATree: TSyntaxTree): TDictionary<Integer, Boolean>;
var
  Offsets: TDictionary<Integer, Boolean>;
  Tokens: TArray<TPascalToken>;
begin
  Offsets := TDictionary<Integer, Boolean>.Create;
  Tokens := ATree.Tokens;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Low_, High_, Middle, Index: Integer;
    begin
      Result := True;
      if ANode.Kind <> TSyntaxKind.RoutineHeader then
        Exit;
      // Erstes Token des Kopfs (Tokens sind nach Offset sortiert).
      Low_ := 0;
      High_ := Length(Tokens);
      while Low_ < High_ do
      begin
        Middle := (Low_ + High_) div 2;
        if Tokens[Middle].Offset < ANode.StartOffset then
          Low_ := Middle + 1
        else
          High_ := Middle;
      end;
      for Index := Low_ to High(Tokens) do
      begin
        if (Tokens[Index].Offset >= ANode.EndOffset) or Tokens[Index].IsSymbol('(') or
          Tokens[Index].IsSymbol(':') or Tokens[Index].IsSymbol(';') then
          Break;
        if Tokens[Index].Kind = TPascalTokenKind.Identifier then
          Offsets.AddOrSetValue(Tokens[Index].Offset, True);
      end;
    end);
  Result := Offsets;
end;

function TDeprecatedSymbolRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DeprecatedSymbolRuleId, TRuleSeverity.Hint,
    'Verwendung eines Symbols mit deprecated, platform oder experimental (wie Compilerwarnung W1000).');
end;

procedure TDeprecatedSymbolRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  Candidates: TDictionary<string, Boolean>;
  Headers: TDictionary<Integer, Boolean>;
  Token: TPascalToken;
  Resolved: TResolvedSymbol;
  OwnerUnit, OwnUnit: TUnitIndex;
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
  Known, Hinted: Boolean;
  Message: string;
begin
  if (AContext.Tree = nil) or (AContext.Index = nil) then
    Exit;
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  Candidates := TDictionary<string, Boolean>.Create;
  Headers := HeaderNameOffsets(AContext.Tree);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, AContext.RelativePath);
    try
      OwnUnit := Resolver.ExtractedUnit(AContext.Tree, AContext.RelativePath);
      for Token in AContext.Tree.Tokens do
      begin
        if (Token.Kind <> TPascalTokenKind.Identifier) or Headers.ContainsKey(Token.Offset) then
          Continue;
        // Vorfilter: Gibt es irgendwo ein gleichnamiges Symbol mit Hinweis?
        if not Candidates.TryGetValue(LowerCase(Token.Text), Hinted) then
        begin
          Hinted := False;
          for Symbol in OwnUnit.Symbols do
            if SameText(Symbol.Name, Token.Text) and HasHint(Symbol) then
              Hinted := True;
          if not Hinted then
            for Location in AContext.Index.FindSymbols(Token.Text) do
              if HasHint(Location.Symbol) then
                Hinted := True;
          Candidates.Add(LowerCase(Token.Text), Hinted);
        end;
        if not Hinted then
          Continue;
        Resolved := Resolver.Resolve(AContext.Tree, AContext.RelativePath, Token.StartPos);
        if not Resolved.Found or (Resolved.SelectionRange.StartPos = Token.StartPos) and
          SameText(Resolved.FileName, AContext.RelativePath) then
          Continue;
        if not Resolver.DeclaringUnit(Resolved, OwnerUnit) then
          Continue;
        Known := False;
        for Symbol in OwnerUnit.Symbols do
          if (Symbol.SelectionRange.StartPos = Resolved.SelectionRange.StartPos) and
            SameText(Symbol.Name, Resolved.Name) then
          begin
            Known := True;
            Break;
          end;
        if not Known then
          Continue;
        Message := MessageOf(Token.Text, Symbol);
        if Message <> '' then
          AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos), Message, TRuleConfidence.Medium);
      end;
    finally
      Resolver.UnpinTree;
    end;
  finally
    Headers.Free;
    Candidates.Free;
    Resolver.Free;
  end;
end;

procedure RegisterDeprecatedRules(ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDeprecatedSymbolRule.Create);
end;

end.
