unit Atlas.Common.Rules.Builtin.Deprecated;

// Verwendung veralteter oder gebundener Symbole und Units (#38, #1018, Gruppe
// Compiler vorab), wie die Compilerwarnungen W1000–W1007:
//   Symbol  deprecated W1000, library W1001, platform W1002, experimental W1003
//   Unit    library W1004, platform W1005, deprecated W1006, experimental W1007
// Dazu der veraltete Abschnitt automated einer Klasse (W1000, #1373).
// Ein Bezeichner, der sich sicher auf eine Deklaration mit einem dieser
// Hinweise auflöst, bekommt einen Treffer, bei Überladungen nur die vom
// Aufruf gewählte; eine Unit im uses, deren Kopf einen
// trägt, ebenso. Die LSP-Schicht streicht deprecated durch. Der Grund aus
// deprecated 'Grund' steht in der Meldung. Nicht gemeldet werden die
// Deklaration selbst und der Name im Kopf einer Implementierung.
//
// Ob eine Art gemeldet wird, entscheidet wie bei dcc der Stand der Warnung
// (Rules.WarnSwitches, #1378): ab Werk alle acht an, dann die Projektoption
// der .dproj (DCC_SYMBOL_PLATFORM = false …), dann die Schalter
// {$WARN SYMBOL_PLATFORM OFF|ON|ERROR|DEFAULT}, {$WARN UNIT_…} und
// {$WARNINGS OFF} in der Datei ab ihrer Stelle. Steht ein Schalter in einem
// {$IF}-Zweig, der nicht sicher mit der Stelle übersetzt wird, schweigt die
// Regel dort. Die Option kinds schränkt die Arten zusätzlich ein (Standard
// alle vier).
//
// Die .NET-Direktive {$UNSAFECODE ON|OFF} meldet dcc für Windows als
// plattformspezifisches Symbol (W1002, Fall CmE2406); die Regel meldet sie
// ebenso, solange SYMBOL_PLATFORM an ist.
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
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.WarnSwitches,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDeprecatedText = (IsKind, Better, Like, ReplaceWith, DotNetSwitch, RemoveSwitch, Title);

const
  cTexts: array[TDeprecatedText] of TAtlasText = (
    (De: '%s%s ist %s'; En: '%s%s is %s'),
    (De: '; besser '; En: '; better '),
    (De: ' (wie %s).'; En: ' (like %s).'),
    (De: 'Durch %s ersetzen'; En: 'Replace with %s'),
    (De: 'Den Schalter %s gibt es nur für .NET; er ist plattformspezifisch und wirkt hier nicht (wie W1002).';
     En: 'The switch %s exists only for .NET; it is platform-specific and has no effect here (like W1002).'),
    (De: 'Schalter %s entfernen'; En: 'Remove switch %s'),
    (De: 'Verwendung eines Symbols oder einer Unit mit deprecated, experimental, platform oder library (wie ' +
      'W1000–W1007).';
     En: 'Use of a symbol or unit with deprecated, experimental, platform or library (like W1000–W1007).'));

{$SCOPEDENUMS OFF}

const
  // Je Art: Direktive, Code bei Symbolen, Code bei Units, Schalter für Symbole und für Units.
  KindWords: array[0..3] of string = ('deprecated', 'experimental', 'platform', 'library');
  SymbolCodes: array[0..3] of string = ('W1000', 'W1003', 'W1002', 'W1001');
  UnitCodes: array[0..3] of string = ('W1006', 'W1007', 'W1005', 'W1004');
  SymbolSwitches: array[0..3] of string = ('SYMBOL_DEPRECATED', 'SYMBOL_EXPERIMENTAL', 'SYMBOL_PLATFORM',
    'SYMBOL_LIBRARY');
  UnitSwitches: array[0..3] of string = ('UNIT_DEPRECATED', 'UNIT_EXPERIMENTAL', 'UNIT_PLATFORM', 'UNIT_LIBRARY');
  // Index von platform in KindWords.
  cPlatformKind = 2;
  // Direktiven, die es nur für .NET gab; dcc für Windows meldet sie als plattformspezifisch (W1002).
  cNetDirectives: array[0..0] of string = ('UNSAFECODE');
  // platform-Routinen der RTL ohne Grund im Quelltext und ihr plattformunabhängiger Ersatz.
  KnownOld: array[0..1] of string = ('IncludeTrailingBackslash', 'ExcludeTrailingBackslash');
  KnownNew: array[0..1] of string = ('IncludeTrailingPathDelimiter', 'ExcludeTrailingPathDelimiter');
  KnownUnits: array[0..1] of string = ('System.SysUtils', 'SysUtils');

type
  /// <summary>Hinweis an einem verwendeten Symbol bzw. einer Unit: Direktiven, Grund aus deprecated '…' und
  /// eindeutiger Ersatz ('' ohne).</summary>
  TDeprecatedHint = record
    Directives: TArray<string>;
    Reason: string;
    Replacement: string;
    class function Create(const ADirectives: TArray<string>; const AReason, AReplacement: string): TDeprecatedHint;
      static;
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
    FSwitches: TRuleWarnSwitches;
    FTokenIndex: TDictionary<Integer, Integer>;
    procedure IndexTokens;
    /// <summary>Wie die Warnung AKind (Symbol bzw. Unit) am Token ATokenIndex steht.</summary>
    function StateAt(AKind: Integer; AUnitLevel: Boolean; ATokenIndex: Integer): TRuleWarnState;
    function FindIndexedUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
    function SymbolOf(const AResolved: TResolvedSymbol; out AOwner: TUnitIndex; out ASymbol: TIndexSymbol): Boolean;
    /// <summary>Eindeutiger Ersatz für ASymbol, an der Stelle sichtbar und von derselben Art; '' ohne.</summary>
    function ReplacementOf(const ASymbol: TIndexSymbol; const AOwner: TUnitIndex; AQualified: Boolean): string;
    function Fits(const ASymbol: TIndexSymbol; const AOwner: TUnitIndex; const ACandidate: string;
      AQualified: Boolean): Boolean;
    /// <summary>Meldung der Art AKind für AName mit dem Hinweis AHint.</summary>
    function MessageOf(AKind: Integer; const AName: string; const AHint: TDeprecatedHint;
      AUnitLevel: Boolean): string;
    procedure ReportKinds(const ARange: TTextRange; ATokenIndex: Integer; const AName: string;
      const AHint: TDeprecatedHint; AUnitLevel: Boolean);
    procedure CheckUses;
    /// <summary>Vorfilter: Gibt es in der Datei oder im Index ein Symbol AName mit Hinweis?</summary>
    function NameHinted(const AName: string): Boolean;
    /// <summary>Das Symbol, das der Bezeichner ATokenIndex verwendet, wenn es sicher einen Hinweis trägt.
    /// </summary>
    function HintedSymbolAt(ATokenIndex: Integer; out AOwner: TUnitIndex; out ASymbol: TIndexSymbol): Boolean;
    /// <summary>Steht vor dem Token ATokenIndex (ohne Kommentare und Direktiven) ein Punkt?</summary>
    function IsQualified(ATokenIndex: Integer): Boolean;
    procedure CheckSymbols;
    /// <summary>Abschnitte automated in Klassen (W1000 „Symbol 'AUTOMATED' ist veraltet“, #1373).</summary>
    procedure CheckAutomated;
    procedure CheckNetDirectives;
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
  begin
    if IndexText(Word, ADirectives) >= 0 then
    begin
      Exit(True);
    end;
  end;
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

/// <summary>Erstes Token ab AOffset (Tokens sind nach Offset sortiert).</summary>
function FirstTokenAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  mHigh, mMiddle: Integer;
begin
  Result := 0;
  mHigh := Length(ATokens);
  while Result < mHigh do
  begin
    mMiddle := (Result + mHigh) div 2;
    if ATokens[mMiddle].Offset < AOffset then
    begin
      Result := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
end;

/// <summary>(Use, Alloc, Release = 4): die Namen direkt nach "(" bzw. ","; der Wert hinter "=" ist eine
/// Verwendung.</summary>
procedure AddEnumNames(const ATokens: TArray<TPascalToken>; AFirst: Integer; ANode: TSyntaxNode;
  AOffsets: TDictionary<Integer, Boolean>);
var
  mIndex: Integer;
begin
  mIndex := AFirst + 1;
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ANode.EndOffset) do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      (ATokens[mIndex - 1].IsSymbol('(') or ATokens[mIndex - 1].IsSymbol(',')) then
    begin
      AOffsets.AddOrSetValue(ATokens[mIndex].Offset, True);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Endet am Token AToken der Name einer Deklaration (Parameter, Typ, Wert, Typparameter)?</summary>
function EndsDeclaredName(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Symbol) and MatchStr(AToken.Text, ['(', ':', ';', '=', '[', '(.', '<']);
end;

/// <summary>Bezeichner ab AFirst bis zum Ende des deklarierten Namens.</summary>
procedure AddDeclaredNames(const ATokens: TArray<TPascalToken>; AFirst: Integer; ANode: TSyntaxNode;
  AOffsets: TDictionary<Integer, Boolean>);
var
  mIndex: Integer;
begin
  mIndex := AFirst;
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ANode.EndOffset) and
    not EndsDeclaredName(ATokens[mIndex]) do
  begin
    if ATokens[mIndex].Kind = TPascalTokenKind.Identifier then
    begin
      AOffsets.AddOrSetValue(ATokens[mIndex].Offset, True);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Offsets der Namen, die hier deklariert werden, nicht verwendet: Routinenköpfe (procedure TFoo.Bar),
/// Variablen, Felder, Konstanten, Typen, Parameter, Properties und Aufzählungswerte. Ein Feld Release ist keine
/// Verwendung eines veralteten Release anderswo; die Auflösung an der Deklaration kann aber dort landen.</summary>
function DeclarationNameOffsets(ATree: TSyntaxTree): TDictionary<Integer, Boolean>;
const
  NamedKinds = [TSyntaxKind.RoutineHeader, TSyntaxKind.VarDecl, TSyntaxKind.Field, TSyntaxKind.ConstDecl,
    TSyntaxKind.TypeDecl, TSyntaxKind.Parameter, TSyntaxKind.PropertyDecl, TSyntaxKind.InlineVar,
    TSyntaxKind.InlineConst];
var
  mOffsets: TDictionary<Integer, Boolean>;
  mTokens: TArray<TPascalToken>;
begin
  mOffsets := TDictionary<Integer, Boolean>.Create;
  mTokens := ATree.Tokens;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      if ANode.Kind = TSyntaxKind.EnumType then
      begin
        AddEnumNames(mTokens, FirstTokenAt(mTokens, ANode.StartOffset), ANode, mOffsets);
      end
      else if ANode.Kind in NamedKinds then
      begin
        AddDeclaredNames(mTokens, FirstTokenAt(mTokens, ANode.StartOffset), ANode, mOffsets);
      end;
    end);
  Result := mOffsets;
end;

{ TDeprecatedHint }

class function TDeprecatedHint.Create(const ADirectives: TArray<string>; const AReason,
  AReplacement: string): TDeprecatedHint;
begin
  Result.Directives := ADirectives;
  Result.Reason := AReason;
  Result.Replacement := AReplacement;
end;

{ TDeprecatedCheck }

constructor TDeprecatedCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FIndex := AContext.Index;
  if FIndex = nil then
  begin
    FIndex := TSymbolIndex.Create;
  end;
  FResolver := TNameResolver.Create(FIndex, AContext.EnsureUnit, AContext.TreeUnits);
  FResolver.Namespaces := AContext.Namespaces;
  FScope := TNameResolver.Create(FIndex, AContext.EnsureUnit, AContext.TreeUnits);
  FScope.Namespaces := AContext.Namespaces;
  FTokenIndex := TDictionary<Integer, Integer>.Create;
  FSwitches := TRuleWarnSwitches.Create(AContext);
  // Standard wie dcc: alle Arten; ob die Warnung an ist, sagt FSwitches.
  FKinds := TRuleOptions.Strings(AContext.Options, 'kinds', ['deprecated', 'experimental', 'platform', 'library']);
end;

destructor TDeprecatedCheck.Destroy;
begin
  FSwitches.Free;
  FTokenIndex.Free;
  FScope.Free;
  FResolver.Free;
  inherited;
end;

procedure TDeprecatedCheck.IndexTokens;
var
  mIndex: Integer;
  mTokens: TArray<TPascalToken>;
begin
  mTokens := FContext.Tree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    FTokenIndex.AddOrSetValue(mTokens[mIndex].Offset, mIndex);
  end;
end;

function TDeprecatedCheck.StateAt(AKind: Integer; AUnitLevel: Boolean; ATokenIndex: Integer): TRuleWarnState;
var
  mKey: string;
begin
  if IndexText(KindWords[AKind], FKinds) < 0 then
  begin
    Exit(TRuleWarnState.Disabled);
  end;
  if AUnitLevel then
  begin
    mKey := UnitSwitches[AKind];
  end
  else
  begin
    mKey := SymbolSwitches[AKind];
  end;
  // dcc meldet alle acht Warnungen ab Werk.
  Result := FSwitches.StateAt(mKey, True, ATokenIndex);
end;

function TDeprecatedCheck.FindIndexedUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
var
  Namespace: string;
begin
  if FIndex.FindUnit(AName, AUnit) then
  begin
    Exit(True);
  end;
  for Namespace in FContext.Namespaces do
  begin
    if FIndex.FindUnit(Namespace + '.' + AName, AUnit) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDeprecatedCheck.SymbolOf(const AResolved: TResolvedSymbol; out AOwner: TUnitIndex;
  out ASymbol: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
begin
  Result := False;
  if not AResolved.Found or (AResolved.Kind <> TResolvedKind.Symbol) then
  begin
    Exit;
  end;
  // Symbole der eigenen Datei stehen in ihrem Index, nicht im (womöglich älteren) Projektindex.
  if SameText(AResolved.FileName, FContext.RelativePath) or SameText(AResolved.UnitName, FOwn.UnitName) then
  begin
    AOwner := FOwn;
  end
  else if not FResolver.DeclaringUnit(AResolved, AOwner) then
  begin
    Exit;
  end;
  for Symbol in AOwner.Symbols do
  begin
    if (Symbol.SelectionRange.StartPos = AResolved.SelectionRange.StartPos) and SameText(Symbol.Name, AResolved.Name)
      and SameText(Symbol.Container, AResolved.Container) then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
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
  begin
    Exit;
  end;
  Dot := Pos('.', ACandidate);
  if ASymbol.Container <> '' then
  begin
    // Mitglied: Ersatz im selben Typ (oder seinen Vorfahren).
    if (Dot > 0) or not FScope.ResolveTypeFrom(AOwner, ASymbol.Container, OwnerType) or
      not FScope.DeclaredMember(OwnerType, ACandidate, Found) then
    begin
      Exit;
    end;
  end
  else if Dot > 0 then
  begin
    // TPath.Combine: nur ohne Qualifizierung an der Stelle, Typ aus Sicht der Datei, Mitglied darin.
    if AQualified or (Pos('.', Copy(ACandidate, Dot + 1, MaxInt)) > 0) or
      not FScope.ResolveNameFrom(FOwn, Copy(ACandidate, 1, Dot - 1), TypeSymbol) or
      (KindGroup(TypeSymbol.SymbolKind) <> 2) or
      not FScope.DeclaredMember(TypeSymbol, Copy(ACandidate, Dot + 1, MaxInt), Found) then
    begin
      Exit;
    end;
  end
  else if AQualified or not FScope.ResolveNameFrom(FOwn, ACandidate, Found) then
  begin
    Exit;
  end;
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
      begin
        if (Candidates.IndexOf(Match.Value) < 0) and Fits(ASymbol, AOwner, Match.Value, AQualified) then
        begin
          Candidates.Add(Match.Value);
        end;
      end;
    end
    else if IndexText(AOwner.UnitName, KnownUnits) >= 0 then
    begin
      Index := IndexText(ASymbol.Name, KnownOld);
      if Index >= 0 then
      begin
        Name := KnownNew[Index];
        if Fits(ASymbol, AOwner, Name, AQualified) then
        begin
          Candidates.Add(Name);
        end;
      end;
    end;
    // Eindeutig heißt: genau ein Name aus dem Text passt.
    if Candidates.Count = 1 then
    begin
      Result := Candidates[0];
    end;
  finally
    Candidates.Free;
  end;
end;

function TDeprecatedCheck.MessageOf(AKind: Integer; const AName: string; const AHint: TDeprecatedHint;
  AUnitLevel: Boolean): string;
var
  mPrefix, mCode: string;
begin
  mPrefix := '';
  mCode := SymbolCodes[AKind];
  if AUnitLevel then
  begin
    mPrefix := 'Unit ';
    mCode := UnitCodes[AKind];
  end;
  Result := cTexts[TDeprecatedText.IsKind].Fmt([mPrefix, AName, KindWords[AKind]]);
  if (AKind = 0) and (AHint.Reason <> '') then
  begin
    Result := Result + ': ' + AHint.Reason;
  end
  else if AHint.Replacement <> '' then
  begin
    Result := Result + cTexts[TDeprecatedText.Better].Text + AHint.Replacement;
  end;
  Result := Result + cTexts[TDeprecatedText.Like].Fmt([mCode]);
end;

procedure TDeprecatedCheck.ReportKinds(const ARange: TTextRange; ATokenIndex: Integer; const AName: string;
  const AHint: TDeprecatedHint; AUnitLevel: Boolean);
var
  mKind: Integer;
  mState: TRuleWarnState;
  mFixes: TArray<TRuleFix>;
  mSeverity: TRuleSeverity;
begin
  mFixes := nil;
  if AHint.Replacement <> '' then
  begin
    mFixes := [TRuleFix.Create(cTexts[TDeprecatedText.ReplaceWith].Fmt([AHint.Replacement]),
      [TTextEdit.Create(ARange, AHint.Replacement)])];
  end;
  for mKind := Low(KindWords) to High(KindWords) do
  begin
    if IndexText(KindWords[mKind], AHint.Directives) < 0 then
    begin
      Continue;
    end;
    mState := StateAt(mKind, AUnitLevel, ATokenIndex);
    if not TRuleWarnSwitches.Reported(mState) then
    begin
      Continue;
    end;
    // {$WARN … ERROR} macht die Warnung zum Fehler.
    mSeverity := TRuleSeverity.Default;
    if mState = TRuleWarnState.AsError then
    begin
      mSeverity := TRuleSeverity.Error;
    end;
    FReport.AddWithSeverity(ARange, MessageOf(mKind, AName, AHint, AUnitLevel), mSeverity, mFixes);
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
        begin
          Items.Add(ANode);
        end;
      end);
    for Item in Items do
    begin
      if (Item.Name = '') or SameText(Item.Name, FOwn.UnitName) or not FTokenIndex.TryGetValue(Item.StartOffset, First)
        or not FindIndexedUnit(Item.Name, UnitIndex) or not HasHint(UnitIndex.Directives) then
      begin
        Continue;
      end;
      // Name samt Punkten, ohne "in '…'".
      Last := First;
      while (Last + 2 <= High(Tokens)) and Tokens[Last + 1].IsSymbol('.') and
        (Tokens[Last + 2].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) do
      begin
        Inc(Last, 2);
      end;
      ReportKinds(TTextRange.Create(Tokens[First].StartPos, Tokens[Last].EndPos), First, Item.Name,
        TDeprecatedHint.Create(UnitIndex.Directives, UnitIndex.DeprecatedText, ''), True);
    end;
  finally
    Items.Free;
  end;
end;

function TDeprecatedCheck.NameHinted(const AName: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FOwn.Symbols do
  begin
    if SameText(mSymbol.Name, AName) and HasHint(mSymbol.Directives) then
    begin
      Exit(True);
    end;
  end;
  Result := FIndex.HasSymbol(AName,
    function(const ACandidate: TIndexSymbol): Boolean
    begin
      Result := HasHint(ACandidate.Directives);
    end);
end;

function TDeprecatedCheck.HintedSymbolAt(ATokenIndex: Integer; out AOwner: TUnitIndex;
  out ASymbol: TIndexSymbol): Boolean;
var
  mToken: TPascalToken;
  mResolved, mCandidate: TResolvedSymbol;
  mCandidateUnit: TUnitIndex;
  mCandidateSymbol: TIndexSymbol;
begin
  mToken := FContext.Tree.Tokens[ATokenIndex];
  // Bei Überladungen zählt die Überladung, die der Aufruf wählt (FileAge(Name, Alter) nicht die veraltete
  // FileAge(Name)). Bleibt die Wahl offen, meldet die Regel nur, wenn alle Kandidaten den Hinweis tragen.
  mResolved := Default(TResolvedSymbol);
  for mCandidate in FResolver.ResolveAll(FContext.Tree, FContext.RelativePath, mToken.StartPos) do
  begin
    if not SymbolOf(mCandidate, mCandidateUnit, mCandidateSymbol) or not HasHint(mCandidateSymbol.Directives) then
    begin
      Exit(False);
    end;
    if not mResolved.Found then
    begin
      mResolved := mCandidate;
      AOwner := mCandidateUnit;
      ASymbol := mCandidateSymbol;
    end;
  end;
  // Die Deklaration selbst ist keine Verwendung.
  Result := mResolved.Found and not ((mResolved.SelectionRange.StartPos = mToken.StartPos) and
    SameText(mResolved.FileName, FContext.RelativePath));
end;

function TDeprecatedCheck.IsQualified(ATokenIndex: Integer): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mPrevious: Integer;
begin
  mTokens := FContext.Tree.Tokens;
  mPrevious := ATokenIndex - 1;
  while (mPrevious >= 0) and (mTokens[mPrevious].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(mPrevious);
  end;
  Result := (mPrevious >= 0) and mTokens[mPrevious].IsSymbol('.');
end;

procedure TDeprecatedCheck.CheckSymbols;
var
  mCandidates: TDictionary<string, Boolean>;
  mHeaders: TDictionary<Integer, Boolean>;
  mTokens: TArray<TPascalToken>;
  mToken: TPascalToken;
  mIndex: Integer;
  mOwner: TUnitIndex;
  mSymbol: TIndexSymbol;
  mHinted: Boolean;
begin
  mTokens := FContext.Tree.Tokens;
  mCandidates := TDictionary<string, Boolean>.Create;
  mHeaders := DeclarationNameOffsets(FContext.Tree);
  try
    for mIndex := 0 to High(mTokens) do
    begin
      mToken := mTokens[mIndex];
      if (mToken.Kind <> TPascalTokenKind.Identifier) or mHeaders.ContainsKey(mToken.Offset) then
      begin
        Continue;
      end;
      if not mCandidates.TryGetValue(LowerCase(mToken.Text), mHinted) then
      begin
        mHinted := NameHinted(mToken.Text);
        mCandidates.Add(LowerCase(mToken.Text), mHinted);
      end;
      if mHinted and HintedSymbolAt(mIndex, mOwner, mSymbol) then
      begin
        ReportKinds(TTextRange.Create(mToken.StartPos, mToken.EndPos), mIndex, mToken.Text,
          TDeprecatedHint.Create(mSymbol.Directives, mSymbol.DeprecatedText,
          ReplacementOf(mSymbol, mOwner, IsQualified(mIndex))), False);
      end;
    end;
  finally
    mHeaders.Free;
    mCandidates.Free;
  end;
end;

procedure TDeprecatedCheck.CheckAutomated;
var
  mSections: TList<TSyntaxNode>;
  mSection: TSyntaxNode;
  mToken: Integer;
begin
  mSections := TList<TSyntaxNode>.Create;
  try
    FContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if (ANode.Kind = TSyntaxKind.Visibility) and (ANode.Name = 'automated') and (ANode.Parent <> nil) and
          (ANode.Parent.Kind = TSyntaxKind.ClassType) then
        begin
          mSections.Add(ANode);
        end;
      end);
    for mSection in mSections do
    begin
      if FTokenIndex.TryGetValue(mSection.StartOffset, mToken) then
      begin
        ReportKinds(TTextRange.Create(mSection.StartPos, mSection.EndPos), mToken, 'automated',
          TDeprecatedHint.Create(TArray<string>.Create('deprecated'), '', ''), False);
      end;
    end;
  finally
    mSections.Free;
  end;
end;

procedure TDeprecatedCheck.CheckNetDirectives;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mName: string;
  mState: TRuleWarnState;
  mSeverity: TRuleSeverity;
  mRange: TTextRange;
begin
  mTokens := FContext.Tree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if mTokens[mIndex].Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    mName := TPascalLexer.DirectiveName(mTokens[mIndex].Text);
    if IndexText(mName, cNetDirectives) < 0 then
    begin
      Continue;
    end;
    mState := StateAt(cPlatformKind, False, mIndex);
    if not TRuleWarnSwitches.Reported(mState) then
    begin
      Continue;
    end;
    mSeverity := TRuleSeverity.Default;
    if mState = TRuleWarnState.AsError then
    begin
      mSeverity := TRuleSeverity.Error;
    end;
    mRange := TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].EndPos);
    FReport.AddWithSeverity(mRange, cTexts[TDeprecatedText.DotNetSwitch].Fmt([mName]), mSeverity,
      [TRuleFix.Create(cTexts[TDeprecatedText.RemoveSwitch].Fmt([mName]), [TTextEdit.Create(mRange, '')])]);
  end;
end;

procedure TDeprecatedCheck.Run;
begin
  IndexTokens;
  CheckNetDirectives;
  FResolver.PinTree(FContext.Tree, FContext.RelativePath);
  try
    FOwn := FResolver.ExtractedUnit(FContext.Tree, FContext.RelativePath);
    CheckUses;
    CheckSymbols;
    CheckAutomated;
  finally
    FResolver.UnpinTree;
  end;
end;

{ TDeprecatedSymbolRule }

function TDeprecatedSymbolRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DeprecatedSymbolRuleId, TRuleSeverity.Warning,
    cTexts[TDeprecatedText.Title].Text);
end;

class function TDeprecatedSymbolRule.IsDeprecation(const AMessage: string): Boolean;
begin
  // Über die Compilernummer am Ende, nicht über den Text: die Meldung gibt es deutsch und englisch (#1458).
  Result := EndsStr('W1000).', AMessage) or EndsStr('W1006).', AMessage);
end;

procedure TDeprecatedSymbolRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TDeprecatedCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Deprecated', cTexts);

end.
