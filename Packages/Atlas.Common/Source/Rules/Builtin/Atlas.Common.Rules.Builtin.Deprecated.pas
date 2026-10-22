unit Atlas.Common.Rules.Builtin.Deprecated;

// Verwendung veralteter oder gebundener Symbole und Units (#38, #1018, Gruppe
// Compiler vorab), wie die Compilerwarnungen W1000–W1007:
//   Symbol  deprecated W1000, library W1001, platform W1002, experimental W1003
//   Unit    library W1004, platform W1005, deprecated W1006, experimental W1007
// Ein Bezeichner, der sich sicher auf eine Deklaration mit einem dieser
// Hinweise auflöst, bekommt einen Treffer; eine Unit im uses, deren Kopf einen
// trägt, ebenso. Die LSP-Schicht streicht deprecated durch. Der Grund aus
// deprecated 'Grund' steht in der Meldung. Nicht gemeldet werden die
// Deklaration selbst und der Name im Kopf einer Implementierung.
//
// Welche Arten gemeldet werden, legt die Option kinds fest (Standard
// deprecated und experimental, wie meist in Projekten); die Schalter
// {$WARN SYMBOL_PLATFORM OFF|ON|ERROR|DEFAULT}, {$WARN UNIT_…} und
// {$WARNINGS OFF} in der Datei gelten ab ihrer Stelle wie beim Compiler.
// Steht ein Schalter in einem {$IF}-Zweig, der nicht sicher mit der Stelle
// übersetzt wird, schweigt die Regel dort.
//
// Korrektur: Ersatz aus dem deprecated-Text (deprecated 'Use Neu'), bzw. für
// platform-Routinen der RTL ohne Text aus einer kleinen Tabelle, wenn genau
// ein Name passt, an der Stelle sichtbar ist und dieselbe Art hat (Routine
// für Routine, Typ für Typ). Ohne Projektindex prüft die Regel nur die
// Symbole der Datei selbst.

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
    /// <summary>Meldung der Regel zu deprecated (W1000, W1006)? Nur solche streicht der Editor durch.</summary>
    class function IsDeprecation(const AMessage: string): Boolean; static;
  end;

procedure RegisterDeprecatedRules(ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Options,
  Atlas.Common.Semantics.NameResolver;

const
  // Je Art: Direktive, Code bei Symbolen, Code bei Units, Schalter für Symbole und für Units.
  KindWords: array[0..3] of string = ('deprecated', 'experimental', 'platform', 'library');
  SymbolCodes: array[0..3] of string = ('W1000', 'W1003', 'W1002', 'W1001');
  UnitCodes: array[0..3] of string = ('W1006', 'W1007', 'W1005', 'W1004');
  SymbolSwitches: array[0..3] of string = ('SYMBOL_DEPRECATED', 'SYMBOL_EXPERIMENTAL', 'SYMBOL_PLATFORM',
    'SYMBOL_LIBRARY');
  UnitSwitches: array[0..3] of string = ('UNIT_DEPRECATED', 'UNIT_EXPERIMENTAL', 'UNIT_PLATFORM', 'UNIT_LIBRARY');
  // platform-Routinen der RTL ohne Grund im Quelltext und ihr plattformunabhängiger Ersatz.
  KnownOld: array[0..1] of string = ('IncludeTrailingBackslash', 'ExcludeTrailingBackslash');
  KnownNew: array[0..1] of string = ('IncludeTrailingPathDelimiter', 'ExcludeTrailingPathDelimiter');
  KnownUnits: array[0..1] of string = ('System.SysUtils', 'SysUtils');

type
{$SCOPEDENUMS ON}
  /// <summary>Zustand einer Warnung an einer Stelle: an, als Fehler, aus oder nicht sicher bekannt.</summary>
  TWarnState = (Enabled, AsError, Disabled, Unknown);
  TWarnValue = (SetOn, SetError, SetOff, SetDefault);
{$SCOPEDENUMS OFF}

  /// <summary>Schalter {$WARN Name Wert} bzw. {$WARNINGS Wert} (Name '') an Offset und Zweig Path.</summary>
  TWarnSwitch = record
    Offset: Integer;
    Path: string;
    Name: string;
    Value: TWarnValue;
  end;

  TDeprecatedCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    // Eigener Resolver für Namen aus Sicht der Datei bzw. einer Unit: ResolveNameFrom setzt den Zustand zurück.
    FScope: TNameResolver;
    FOwn: TUnitIndex;
    FKinds: TArray<string>;
    FSwitches: TArray<TWarnSwitch>;
    FPaths: TArray<string>;
    FTokenIndex: TDictionary<Integer, Integer>;
    procedure ReadSwitches;
    /// <summary>Wie die Warnung AKind (Symbol bzw. Unit) am Token ATokenIndex steht.</summary>
    function StateAt(AKind: Integer; AUnitLevel: Boolean; ATokenIndex: Integer): TWarnState;
    function FindIndexedUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
    function SymbolOf(const AResolved: TResolvedSymbol; out AOwner: TUnitIndex; out ASymbol: TIndexSymbol): Boolean;
    /// <summary>Eindeutiger Ersatz für ASymbol, an der Stelle sichtbar und von derselben Art; '' ohne.</summary>
    function ReplacementOf(const ASymbol: TIndexSymbol; const AOwner: TUnitIndex; AQualified: Boolean): string;
    function Fits(const ASymbol: TIndexSymbol; const AOwner: TUnitIndex; const ACandidate: string;
      AQualified: Boolean): Boolean;
    procedure ReportKinds(const ARange: TTextRange; ATokenIndex: Integer; const AName: string;
      const ADirectives: TArray<string>; const AReason, AReplacement: string; AUnitLevel: Boolean);
    procedure CheckUses;
    procedure CheckSymbols;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

function HasHint(const ADirectives: TArray<string>): Boolean;
var
  Word: string;
begin
  for Word in KindWords do
    if IndexText(Word, ADirectives) >= 0 then
      Exit(True);
  Result := False;
end;

/// <summary>Grobe Art für den Ersatz: 1 Routine, 2 Typ, 3 Konstante, 4 Variable oder Feld, 5 Property.</summary>
function KindGroup(AKind: TIndexSymbolKind): Integer;
begin
  case AKind of
    TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_:
      Result := 1;
    TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias:
      Result := 2;
    TIndexSymbolKind.Constant, TIndexSymbolKind.EnumMember:
      Result := 3;
    TIndexSymbolKind.Variable, TIndexSymbolKind.Field:
      Result := 4;
    TIndexSymbolKind.Property_:
      Result := 5;
  else
    Result := 0;
  end;
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

{ TDeprecatedCheck }

constructor TDeprecatedCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FIndex := AContext.Index;
  if FIndex = nil then
    FIndex := TSymbolIndex.Create;
  FResolver := TNameResolver.Create(FIndex, AContext.EnsureUnit);
  FResolver.Namespaces := AContext.Namespaces;
  FScope := TNameResolver.Create(FIndex, AContext.EnsureUnit);
  FScope.Namespaces := AContext.Namespaces;
  FTokenIndex := TDictionary<Integer, Integer>.Create;
  // Standard wie meist in Projekten: platform und library aus.
  FKinds := TRuleOptions.Strings(AContext.Options, 'kinds', ['deprecated', 'experimental']);
end;

destructor TDeprecatedCheck.Destroy;
begin
  FTokenIndex.Free;
  FScope.Free;
  FResolver.Free;
  inherited;
end;

procedure TDeprecatedCheck.ReadSwitches;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
  Name, Body: string;
  Words: TArray<string>;
  Switch: TWarnSwitch;
  Value: string;
begin
  Tokens := FContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(Tokens);
  FSwitches := nil;
  for Index := 0 to High(Tokens) do
  begin
    FTokenIndex.AddOrSetValue(Tokens[Index].Offset, Index);
    if Tokens[Index].Kind <> TPascalTokenKind.Directive then
      Continue;
    Name := TPascalLexer.DirectiveName(Tokens[Index].Text);
    if (Name <> 'WARN') and (Name <> 'WARNINGS') then
      Continue;
    // {$WARN SYMBOL_PLATFORM OFF} bzw. (*$WARNINGS OFF*)
    Body := Tokens[Index].Text;
    if StartsStr('(*', Body) then
      Body := Copy(Body, 4, Length(Body) - 5)
    else
      Body := Copy(Body, 3, Length(Body) - 3);
    Words := Body.Split([' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty);
    Switch := Default(TWarnSwitch);
    Switch.Offset := Tokens[Index].Offset;
    Switch.Path := TConditionalBranches.PathAt(FPaths, Index);
    if Name = 'WARN' then
    begin
      if Length(Words) < 3 then
        Continue;
      Switch.Name := UpperCase(Words[1]);
      Value := UpperCase(Words[2]);
    end
    else
    begin
      if Length(Words) < 2 then
        Continue;
      Value := UpperCase(Words[1]);
    end;
    if Value = 'ON' then
      Switch.Value := TWarnValue.SetOn
    else if Value = 'ERROR' then
      Switch.Value := TWarnValue.SetError
    else if Value = 'OFF' then
      Switch.Value := TWarnValue.SetOff
    else if (Value = 'DEFAULT') and (Name = 'WARN') then
      Switch.Value := TWarnValue.SetDefault
    else
      Continue;
    FSwitches := FSwitches + [Switch];
  end;
end;

function TDeprecatedCheck.StateAt(AKind: Integer; AUnitLevel: Boolean; ATokenIndex: Integer): TWarnState;
var
  Base, State, Warnings: TWarnState;
  Switch: TWarnSwitch;
  Path, Key: string;
  Offset: Integer;
begin
  if IndexText(KindWords[AKind], FKinds) >= 0 then
    Base := TWarnState.Enabled
  else
    Base := TWarnState.Disabled;
  if AUnitLevel then
    Key := UnitSwitches[AKind]
  else
    Key := SymbolSwitches[AKind];
  State := Base;
  Warnings := TWarnState.Enabled;
  Path := TConditionalBranches.PathAt(FPaths, ATokenIndex);
  Offset := FContext.Tree.Tokens[ATokenIndex].Offset;
  for Switch in FSwitches do
  begin
    if Switch.Offset >= Offset then
      Break;
    if (Switch.Name <> '') and (Switch.Name <> Key) then
      Continue;
    // Ein Schalter im anderen Zweig desselben {$IF} gilt hier nie; einer, der nicht sicher mit übersetzt
    // wird, macht den Zustand unbekannt.
    if TConditionalBranches.Exclusive(Path, Switch.Path) then
      Continue;
    if Switch.Name = '' then
    begin
      if not TConditionalBranches.Implies(Path, Switch.Path) then
        Warnings := TWarnState.Unknown
      else if Switch.Value = TWarnValue.SetOff then
        Warnings := TWarnState.Disabled
      else
        Warnings := TWarnState.Enabled;
      Continue;
    end;
    if not TConditionalBranches.Implies(Path, Switch.Path) then
      State := TWarnState.Unknown
    else
      case Switch.Value of
        TWarnValue.SetOn:
          State := TWarnState.Enabled;
        TWarnValue.SetError:
          State := TWarnState.AsError;
        TWarnValue.SetOff:
          State := TWarnState.Disabled;
        TWarnValue.SetDefault:
          State := Base;
      end;
  end;
  if (State = TWarnState.Disabled) or (Warnings = TWarnState.Disabled) then
    Exit(TWarnState.Disabled);
  if (State = TWarnState.Unknown) or (Warnings = TWarnState.Unknown) then
    Exit(TWarnState.Unknown);
  Result := State;
end;

function TDeprecatedCheck.FindIndexedUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
var
  Namespace: string;
begin
  if FIndex.FindUnit(AName, AUnit) then
    Exit(True);
  for Namespace in FContext.Namespaces do
    if FIndex.FindUnit(Namespace + '.' + AName, AUnit) then
      Exit(True);
  Result := False;
end;

function TDeprecatedCheck.SymbolOf(const AResolved: TResolvedSymbol; out AOwner: TUnitIndex;
  out ASymbol: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
begin
  Result := False;
  if not AResolved.Found or (AResolved.Kind <> TResolvedKind.Symbol) then
    Exit;
  // Symbole der eigenen Datei stehen in ihrem Index, nicht im (womöglich älteren) Projektindex.
  if SameText(AResolved.FileName, FContext.RelativePath) or SameText(AResolved.UnitName, FOwn.UnitName) then
    AOwner := FOwn
  else if not FResolver.DeclaringUnit(AResolved, AOwner) then
    Exit;
  for Symbol in AOwner.Symbols do
    if (Symbol.SelectionRange.StartPos = AResolved.SelectionRange.StartPos) and SameText(Symbol.Name, AResolved.Name)
      and SameText(Symbol.Container, AResolved.Container) then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
end;

function TDeprecatedCheck.Fits(const ASymbol: TIndexSymbol; const AOwner: TUnitIndex; const ACandidate: string;
  AQualified: Boolean): Boolean;
var
  Group, Dot: Integer;
  OwnerType, TypeSymbol, Found: TResolvedSymbol;
begin
  Result := False;
  Group := KindGroup(ASymbol.Kind);
  if (Group = 0) or SameText(ACandidate, ASymbol.Name) then
    Exit;
  Dot := Pos('.', ACandidate);
  if ASymbol.Container <> '' then
  begin
    // Mitglied: Ersatz im selben Typ (oder seinen Vorfahren).
    if (Dot > 0) or not FScope.ResolveTypeFrom(AOwner, ASymbol.Container, OwnerType) or
      not FScope.DeclaredMember(OwnerType, ACandidate, Found) then
      Exit;
  end
  else if Dot > 0 then
  begin
    // TPath.Combine: nur ohne Qualifizierung an der Stelle, Typ aus Sicht der Datei, Mitglied darin.
    if AQualified or (Pos('.', Copy(ACandidate, Dot + 1, MaxInt)) > 0) or
      not FScope.ResolveNameFrom(FOwn, Copy(ACandidate, 1, Dot - 1), TypeSymbol) or
      (KindGroup(TypeSymbol.SymbolKind) <> 2) or
      not FScope.DeclaredMember(TypeSymbol, Copy(ACandidate, Dot + 1, MaxInt), Found) then
      Exit;
  end
  else if AQualified or not FScope.ResolveNameFrom(FOwn, ACandidate, Found) then
    Exit;
  Result := Found.Found and (Found.Kind = TResolvedKind.Symbol) and (KindGroup(Found.SymbolKind) = Group);
end;

function TDeprecatedCheck.ReplacementOf(const ASymbol: TIndexSymbol; const AOwner: TUnitIndex;
  AQualified: Boolean): string;
var
  Candidates: TList<string>;
  Match: TMatch;
  Index: Integer;
  Name: string;
begin
  Result := '';
  Candidates := TList<string>.Create;
  try
    if ASymbol.DeprecatedText <> '' then
    begin
      for Match in TRegEx.Matches(ASymbol.DeprecatedText, '[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*') do
        if (Candidates.IndexOf(Match.Value) < 0) and Fits(ASymbol, AOwner, Match.Value, AQualified) then
          Candidates.Add(Match.Value);
    end
    else if IndexText(AOwner.UnitName, KnownUnits) >= 0 then
    begin
      Index := IndexText(ASymbol.Name, KnownOld);
      if Index >= 0 then
      begin
        Name := KnownNew[Index];
        if Fits(ASymbol, AOwner, Name, AQualified) then
          Candidates.Add(Name);
      end;
    end;
    // Eindeutig heißt: genau ein Name aus dem Text passt.
    if Candidates.Count = 1 then
      Result := Candidates[0];
  finally
    Candidates.Free;
  end;
end;

procedure TDeprecatedCheck.ReportKinds(const ARange: TTextRange; ATokenIndex: Integer; const AName: string;
  const ADirectives: TArray<string>; const AReason, AReplacement: string; AUnitLevel: Boolean);
var
  Kind: Integer;
  State: TWarnState;
  Message, Prefix, Code: string;
  Fixes: TArray<TRuleFix>;
  Severity: TRuleSeverity;
begin
  for Kind := Low(KindWords) to High(KindWords) do
  begin
    if IndexText(KindWords[Kind], ADirectives) < 0 then
      Continue;
    State := StateAt(Kind, AUnitLevel, ATokenIndex);
    if (State = TWarnState.Disabled) or (State = TWarnState.Unknown) then
      Continue;
    if AUnitLevel then
    begin
      Prefix := 'Unit ';
      Code := UnitCodes[Kind];
    end
    else
    begin
      Prefix := '';
      Code := SymbolCodes[Kind];
    end;
    Message := Format('%s%s ist %s', [Prefix, AName, KindWords[Kind]]);
    if (Kind = 0) and (AReason <> '') then
      Message := Message + ': ' + AReason
    else if AReplacement <> '' then
      Message := Message + '; besser ' + AReplacement;
    Message := Message + Format(' (wie %s).', [Code]);
    Fixes := nil;
    if AReplacement <> '' then
      Fixes := [TRuleFix.Create(Format('Durch %s ersetzen', [AReplacement]),
        [TTextEdit.Create(ARange, AReplacement)])];
    // {$WARN … ERROR} macht die Warnung zum Fehler.
    Severity := TRuleSeverity.Default;
    if State = TWarnState.AsError then
      Severity := TRuleSeverity.Error;
    FReport.AddWithSeverity(ARange, Message, Severity, Fixes);
  end;
end;

procedure TDeprecatedCheck.CheckUses;
var
  Items: TList<TSyntaxNode>;
  Item: TSyntaxNode;
  Tokens: TArray<TPascalToken>;
  First, Last: Integer;
  UnitIndex: TUnitIndex;
begin
  Tokens := FContext.Tree.Tokens;
  Items := TList<TSyntaxNode>.Create;
  try
    FContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if ANode.Kind = TSyntaxKind.UsedUnit then
          Items.Add(ANode);
      end);
    for Item in Items do
    begin
      if (Item.Name = '') or SameText(Item.Name, FOwn.UnitName) or not FTokenIndex.TryGetValue(Item.StartOffset, First)
        or not FindIndexedUnit(Item.Name, UnitIndex) or not HasHint(UnitIndex.Directives) then
        Continue;
      // Name samt Punkten, ohne "in '…'".
      Last := First;
      while (Last + 2 <= High(Tokens)) and Tokens[Last + 1].IsSymbol('.') and
        (Tokens[Last + 2].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) do
        Inc(Last, 2);
      ReportKinds(TTextRange.Create(Tokens[First].StartPos, Tokens[Last].EndPos), First, Item.Name,
        UnitIndex.Directives, UnitIndex.DeprecatedText, '', True);
    end;
  finally
    Items.Free;
  end;
end;

procedure TDeprecatedCheck.CheckSymbols;
var
  Candidates: TDictionary<string, Boolean>;
  Headers: TDictionary<Integer, Boolean>;
  Tokens: TArray<TPascalToken>;
  Token: TPascalToken;
  Index, Previous: Integer;
  Resolved: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
  Hinted, Qualified: Boolean;
begin
  Tokens := FContext.Tree.Tokens;
  Candidates := TDictionary<string, Boolean>.Create;
  Headers := HeaderNameOffsets(FContext.Tree);
  try
    for Index := 0 to High(Tokens) do
    begin
      Token := Tokens[Index];
      if (Token.Kind <> TPascalTokenKind.Identifier) or Headers.ContainsKey(Token.Offset) then
        Continue;
      // Vorfilter: Gibt es in der Datei oder im Index ein gleichnamiges Symbol mit Hinweis?
      if not Candidates.TryGetValue(LowerCase(Token.Text), Hinted) then
      begin
        Hinted := False;
        for Symbol in FOwn.Symbols do
          if SameText(Symbol.Name, Token.Text) and HasHint(Symbol.Directives) then
            Hinted := True;
        if not Hinted then
          for Location in FIndex.FindSymbols(Token.Text) do
            if HasHint(Location.Symbol.Directives) then
              Hinted := True;
        Candidates.Add(LowerCase(Token.Text), Hinted);
      end;
      if not Hinted then
        Continue;
      Resolved := FResolver.Resolve(FContext.Tree, FContext.RelativePath, Token.StartPos);
      if not Resolved.Found or (Resolved.SelectionRange.StartPos = Token.StartPos) and
        SameText(Resolved.FileName, FContext.RelativePath) then
        Continue;
      if not SymbolOf(Resolved, OwnerUnit, Symbol) or not HasHint(Symbol.Directives) then
        Continue;
      Previous := Index - 1;
      while (Previous >= 0) and (Tokens[Previous].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
        Dec(Previous);
      Qualified := (Previous >= 0) and Tokens[Previous].IsSymbol('.');
      ReportKinds(TTextRange.Create(Token.StartPos, Token.EndPos), Index, Token.Text, Symbol.Directives,
        Symbol.DeprecatedText, ReplacementOf(Symbol, OwnerUnit, Qualified), False);
    end;
  finally
    Headers.Free;
    Candidates.Free;
  end;
end;

procedure TDeprecatedCheck.Run;
begin
  ReadSwitches;
  FResolver.PinTree(FContext.Tree, FContext.RelativePath);
  try
    FOwn := FResolver.ExtractedUnit(FContext.Tree, FContext.RelativePath);
    CheckUses;
    CheckSymbols;
  finally
    FResolver.UnpinTree;
  end;
end;

{ TDeprecatedSymbolRule }

function TDeprecatedSymbolRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DeprecatedSymbolRuleId, TRuleSeverity.Warning,
    'Verwendung eines Symbols oder einer Unit mit deprecated, experimental, platform oder library ' +
    '(wie W1000–W1007).');
end;

class function TDeprecatedSymbolRule.IsDeprecation(const AMessage: string): Boolean;
begin
  Result := ContainsStr(AMessage, '(wie W1000).') or ContainsStr(AMessage, '(wie W1006).');
end;

procedure TDeprecatedSymbolRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TDeprecatedCheck;
begin
  if AContext.Tree = nil then
    Exit;
  Check := TDeprecatedCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
  end;
end;

procedure RegisterDeprecatedRules(ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDeprecatedSymbolRule.Create);
end;

end.
