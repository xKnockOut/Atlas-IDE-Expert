unit Atlas.Common.Rules.Builtin.Unresolved;

// Nicht auflösbare Bezeichner beim Tippen (#178), wie Compilerfehler E2003,
// aber ohne Compiler (Community Edition, Prüfung in der IDE aus). Nutzt die
// vorsichtige Prüfung aus TUnresolvedNames: nur der erste Name einer Kette in
// Anweisungen, with/asm/anonyme Methoden übersprungen, ohne Unit System im
// Index keine Aussage. Ohne Index (Linter) schweigt die Regel. Alte
// object-Syntax: fehlender Konstruktor in New(P, Init) wie E2601, fehlender
// Destruktor in Dispose(P, Done) wie E2602, Fail außerhalb eines Konstruktors
// wie E2078 (#1382).
//
// uses-unit-not-found (#1016, wie F2613, F1026, F1027, E2202, F2092): Units in
// uses und contains, die der Compiler nicht findet (TRuleContext.Units, die
// Suche steht in Atlas.Common.Projects.UnitLookup), Dateien aus "in '…'",
// Packages aus requires und Units, die sich selbst einbinden. Fehlt die Datei
// aus "in '…'", meldet die Regel das auch ohne Projekt (#1379). Findet die
// Suche nicht einmal System, fehlt der Bibliothekspfad: eine Meldung F1027
// statt einer je Unit. Einträge in {$IF…}-Blöcken bleiben still, ebenso alles, worüber
// die Suche keine sichere Aussage trifft (Installation unbekannt, Makro im
// Pfad). Korrekturen: Namen mit Namespace bzw. ähnlich geschriebene Units
// einsetzen, Ordner außerhalb der Suchpfade in DCC_UnitSearchPath der .dproj
// aufnehmen.
//
// unresolved-attribute (#1019, wie W1074, E2289): Ein Attribut [Name] lässt
// sich weder als Klasse NameAttribute noch als Name auflösen; Delphi warnt nur
// und übergeht es (DUnitX-Tests laufen dann nicht). Nach {$WARN
// UNKNOWN_CUSTOM_ATTRIBUTE ERROR} meldet Delphi 13 E1074 (#1379). Vorgeschlagen wird die Unit,
// die den Typ im Index deklariert; Fassaden-Units, die ihn aus einer anderen
// Kandidaten-Unit weiterreichen (DUnitX.TestFramework), gehen vor. Ohne System
// im Index, wenn eine Unit aus uses nicht im Index steht (sie könnte das
// Attribut deklarieren), in {$IF…}-Blöcken und bei unbekannten Vorfahren bleibt
// die Regel still; Attribute des Compilers (Weak, Unsafe, Ref …) zählen immer.
//
// unresolved-type (#1031, wie E2003, E2564, E2005): Ein Typname in einer
// Deklaration (Feld, Parameter, Ergebnis, Vorfahr, Interface-Liste, Variable,
// Typargument) lässt sich nicht auflösen bzw. bezeichnet keinen Typ. Der Code
// folgt Delphi 13 (#1382): Mitglied hinter einem Punkt (TObject.Create) und
// Variable wie E2005, Routine wie E2007, Konstante wie E2029 (dcc liest sie als
// Anfang eines Teilbereichs und erwartet '..'). Dieselben
// Vorbedingungen wie bei unresolved-attribute (System im Index, alle Units aus
// uses bekannt, nicht in {$IF…}); außerdem still bei Typparametern, Namen, die
// die Datei irgendwo als Typ deklariert (auch verschachtelt), und Namen, die der
// Index als verschachtelten Typ kennt (geerbte innere Typen). Korrektur: die
// Unit, die den Typ im Index deklariert, in uses aufnehmen.
//
// Typen der IDE (atlas/ideTypes, TRuleContext.IdeTypes): Kennt die laufende
// IDE einen Typ aus ihren Packages (auch ohne oder mit abweichendem
// Quelltext) in einer Unit, die im uses steht (bzw. vor dem Punkt), schweigen
// unresolved-type und unresolved-identifier für ihn. Steht keine solche Unit im
// uses, schlägt unresolved-type ihre Units zusätzlich zu denen des Index vor.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
{$SCOPEDENUMS ON}
  TUsesListKind = (UsedUnit, ContainedUnit, RequiredPackage);
{$SCOPEDENUMS OFF}

  /// <summary>Eintrag einer uses-, contains- oder requires-Liste (#1016).</summary>
  TUsesListEntry = record
    Kind: TUsesListKind;
    Name: string;
    /// <summary>Pfad aus "in '…'" ohne Hochkommas; '' ohne.</summary>
    InPath: string;
    /// <summary>Alle Namensteile.</summary>
    Range: TTextRange;
  end;

  TUnresolvedAttributeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Units, die AName bzw. ANameAttribute als Typ deklarieren, ohne die, die eine andere Kandidaten-Unit
    /// im interface einbindet und weiterreicht; sortiert.</summary>
    class function DeclaringUnits(const AIndex: ISymbolIndex; const AName: string): TArray<string>; static;
  end;

  TUsesUnitNotFoundRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Alle Einträge aus uses, contains und requires in Quelltextreihenfolge.</summary>
    class function Entries(const ATokens: TArray<TPascalToken>): TArray<TUsesListEntry>; static;
    /// <summary>Bekannte Units, die AName meinen könnten: zuerst mit Namespace davor (Forms → Vcl.Forms),
    /// dann ähnlich geschriebene (Editierabstand höchstens 2), höchstens drei.</summary>
    class function Suggestions(const AName: string; const AKnown: TArray<string>): TArray<string>; static;
    /// <summary>Kleinste Ersetzung, die AOld in ANew verwandelt (gemeinsamer Anfang und Schluss bleiben).</summary>
    class function DiffEdit(const AOld, ANew: string): TTextEdit; static;
  end;

  TUnresolvedTypeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Units, die den Typ AName auf oberster Ebene deklarieren (bei AArity &gt; 0 mit so vielen
    /// Typparametern), ohne AOwnUnit und ohne Units, die eine andere Kandidatin im interface weiterreichen;
    /// sortiert.</summary>
    class function DeclaringUnits(const AIndex: ISymbolIndex; const AName, AOwnUnit: string;
      AArity: Integer): TArray<string>; static;
  end;

procedure RegisterUnresolvedRules(ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Text.Fuzzy,
  Atlas.Common.Rules.Options,
  Atlas.Common.Projects.DprojEditor,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.Attributes,
  Atlas.Common.Semantics.SystemIntrinsics,
  Atlas.Common.Semantics.UnresolvedNames,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TUnresolvedText = (Title, UndeclaredMeant, Undeclared, UsesTitle, OrSep, AddUses, UsesItself, FileNotFound,
    SystemNotFound, AddSearchPath, UseName, OutsidePaths, Similar, UnitNotFound, PackageNotFound, AttributeTitle,
    AttributeIgnored, TestsDontRun, LikeCode, UnitMissing, Candidates, NotType, RoutineNotType, ConstantNotType,
    TypeTitle, TypeUndeclared, MissingInUses, TypeCandidates, LikeE2564, LikeE2003);

const
  cTexts: array[TUnresolvedText] of TAtlasText = (
    (De: 'Bezeichner ist im Projekt und seinen Units nicht deklariert (wie Compilerfehler E2003).';
     En: 'Identifier is not declared in the project and its units (like compiler error E2003).'),
    (De: '"%s" ist nicht deklariert; gemeint ist %s? ({$SCOPEDENUMS ON})';
     En: '"%s" is not declared; is %s meant? ({$SCOPEDENUMS ON})'),
    (De: '"%s" ist nicht deklariert'; En: '"%s" is not declared'),
    (De: 'Unit in uses nicht gefunden (wie F2613)'; En: 'Unit in uses not found (like F2613)'),
    (De: ' oder '; En: ' or '),
    (De: 'uses %s ergänzen'; En: 'Add uses %s'),
    (De: '%s verwendet sich selbst (wie F2092).'; En: '%s uses itself (like F2092).'),
    (De: 'Datei %s für %s nicht gefunden (wie F1026).'; En: 'File %s for %s not found (like F1026).'),
    (De: 'Unit System nicht gefunden; der Bibliothekspfad der Installation fehlt (wie F1027).';
     En: 'Unit System not found; the library path of the installation is missing (like F1027).'),
    (De: 'Ordner %s in den Suchpfad aufnehmen'; En: 'Add folder %s to the search path'),
    (De: '%s verwenden'; En: 'Use %s'),
    (De: 'Unit %s nicht gefunden; sie liegt in %s außerhalb der Suchpfade (wie F2613).';
     En: 'Unit %s not found; it is in %s outside the search paths (like F2613).'),
    (De: 'Unit %s nicht gefunden; ähnlich: %s (wie F2613).'; En: 'Unit %s not found; similar: %s (like F2613).'),
    (De: 'Unit %s nicht gefunden (wie F2613).'; En: 'Unit %s not found (like F2613).'),
    (De: 'Package %s nicht gefunden (wie E2202).'; En: 'Package %s not found (like E2202).'),
    (De: 'Attribut nicht gefunden und vom Compiler still ignoriert (wie W1074)';
     En: 'Attribute not found and silently ignored by the compiler (like W1074)'),
    (De: 'Attribut %s nicht gefunden und wird ignoriert'; En: 'Attribute %s not found and is ignored'),
    (De: '; die Tests laufen nicht'; En: '; the tests do not run'),
    (De: ' (wie %s).'; En: ' (like %s).'),
    (De: ' Unit %s fehlt.'; En: ' Unit %s is missing.'),
    (De: ' In Frage kommen %s.'; En: ' Candidates are %s.'),
    (De: '%s ist kein Typ (wie E2005).'; En: '%s is not a type (like E2005).'),
    (De: '%s ist eine Routine, kein Typ (wie E2007).'; En: '%s is a routine, not a type (like E2007).'),
    (De: '%s ist eine Konstante, kein Typ; der Compiler liest sie als Anfang eines Teilbereichs %s..Ende (wie E2029).';
     En: '%s is a constant, not a type; the compiler reads it as the start of a subrange %s..end (like E2029).'),
    (De: 'Typ in einer Deklaration nicht gefunden'; En: 'Type not found in a declaration'),
    (De: 'Typ %s ist nicht deklariert'; En: 'Type %s is not declared'),
    (De: '; %s fehlt in uses'; En: '; %s is missing in uses'),
    (De: '; in Frage kommen %s'; En: '; candidates are %s'),
    (De: ' (wie E2564).'; En: ' (like E2564).'),
    (De: ' (wie E2003).'; En: ' (like E2003).'));

{$SCOPEDENUMS OFF}

type
  TUnresolvedIdentifierRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

function TUnresolvedIdentifierRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unresolved-identifier', TRuleSeverity.Warning,
    cTexts[TUnresolvedText.Title].Text);
end;

/// <summary>Meint der uses-Eintrag AUsed die Unit AUnit, auch über einen Namespace des Projekts?</summary>
function UsesNames(const AUsed, AUnit: string; const ANamespaces: TArray<string>): Boolean;
var
  mNamespace: string;
begin
  Result := SameText(AUsed, AUnit);
  for mNamespace in ANamespaces do
  begin
    Result := Result or SameText(mNamespace + '.' + AUsed, AUnit);
  end;
end;

/// <summary>Steht AUnit in AUsed (auch über ANamespaces)?</summary>
function UnitUsed(const AUnit: string; const AUsed, ANamespaces: TArray<string>): Boolean;
var
  mUsed: string;
begin
  for mUsed in AUsed do
  begin
    if UsesNames(mUsed, AUnit, ANamespaces) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Kennt die IDE den Typ ANames (Name, ggf. mit Unit davor) in einer Unit, die sichtbar ist: die vor dem
/// Punkt bzw. eine aus AUsed?</summary>
function IdeDeclares(const AIdeTypes: IRuleIdeTypes; const ANames, AUsed, ANamespaces: TArray<string>): Boolean;
var
  mUnit, mQualifier: string;
  mVisible: TArray<string>;
begin
  Result := False;
  if (AIdeTypes = nil) or (Length(ANames) = 0) then
  begin
    Exit;
  end;
  mVisible := AUsed;
  if Length(ANames) > 1 then
  begin
    mQualifier := string.Join('.', Copy(ANames, 0, High(ANames)));
    mVisible := TArray<string>.Create(mQualifier);
  end;
  for mUnit in AIdeTypes.UnitsOf(ANames[High(ANames)]) do
  begin
    Result := Result or UnitUsed(mUnit, mVisible, ANamespaces);
  end;
end;

/// <summary>AUnits und dahinter die Units, in denen die IDE den Typ ABare kennt, ohne Doppelte und ohne AOwnUnit.
/// </summary>
function WithIdeUnits(const AIdeTypes: IRuleIdeTypes; const ABare, AOwnUnit: string;
  const AUnits: TArray<string>): TArray<string>;
var
  mUnit: string;
begin
  Result := AUnits;
  if AIdeTypes = nil then
  begin
    Exit;
  end;
  for mUnit in AIdeTypes.UnitsOf(ABare) do
  begin
    if not SameText(mUnit, AOwnUnit) and (IndexText(mUnit, Result) < 0) then
    begin
      Result := Result + [mUnit];
    end;
  end;
end;

procedure TUnresolvedIdentifierRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  Name: TUnresolvedName;
  mUsed: TArray<string>;
begin
  if (AContext.Tree = nil) or not TUnresolvedNames.Available(AContext.Index) then
  begin
    Exit;
  end;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  mUsed := TUsesClauses.UsedUnits(AContext.Tree.Tokens);
  for Name in TUnresolvedNames.Find(Resolver, AContext.Tree, AContext.RelativePath) do
  begin
    // Typ aus einem Package der IDE, dessen Unit im uses steht (TFoo.Create).
    if (Name.Code = '') and IdeDeclares(AContext.IdeTypes, TArray<string>.Create(Name.Name), mUsed,
      AContext.Namespaces) then
    begin
      Continue;
    end;
    if Name.Code <> '' then
    begin
      AReport.Add(Name.Range, TUnresolvedNames.Describe(Name), TRuleConfidence.Medium);
    end
    else if Name.Suggestion <> '' then
    begin
      AReport.Add(Name.Range, cTexts[TUnresolvedText.UndeclaredMeant].Fmt(
        [Name.Name, Name.Suggestion]), TRuleConfidence.Medium);
    end
    else
    begin
      AReport.Add(Name.Range, cTexts[TUnresolvedText.Undeclared].Fmt([Name.Name]), TRuleConfidence.Medium);
    end;
  end;
end;

{ TUsesUnitNotFoundRule }

function TUsesUnitNotFoundRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('uses-unit-not-found', TRuleSeverity.Error,
    cTexts[TUnresolvedText.UsesTitle].Text);
end;

function IsCode(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

/// <summary>Text eines String-Literals ohne Hochkommas ('' → ').</summary>
function Unquoted(const AText: string): string;
begin
  Result := AText;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end;
  Result := StringReplace(Result, '''''', '''', [rfReplaceAll]);
end;

/// <summary>Beginnt der Quelltext mit "package"? contains und requires gibt es nur dort. In einer Unit sind es
/// Bezeichner, etwa Felder eines Records ("Requires: TArray&lt;TPackageEntry&gt;;" nach einem Semikolon).
/// </summary>
function IsPackageSource(const ATokens: TArray<TPascalToken>): Boolean;
var
  mToken: TPascalToken;
begin
  for mToken in ATokens do
  begin
    if IsCode(mToken) then
    begin
      Exit(SameText(mToken.Text, 'package'));
    end;
  end;
  Result := False;
end;

type
  /// <summary>Eintrag einer Liste, der gerade gelesen wird.</summary>
  TUsesEntryDraft = record
    Name: string;
    InPath: string;
    First: Integer;
    Last: Integer;
    AfterIn: Boolean;
    procedure Reset;
  end;

  /// <summary>Liest die Einträge aus uses, contains und requires.</summary>
  TUsesListScanner = class
  private
    FTokens: TArray<TPascalToken>;
    FIndex: Integer;
    FPrevious: Integer;
    FIsPackage: Boolean;
    FDraft: TUsesEntryDraft;
    FEntries: TArray<TUsesListEntry>;
    function StartsStatement(const AWord: string): Boolean;
    function ListKind(out AKind: TUsesListKind): Boolean;
    procedure Flush(AKind: TUsesListKind);
    procedure ReadToken(AIndex: Integer);
    procedure ReadList(AKind: TUsesListKind);
  public
    constructor Create(const ATokens: TArray<TPascalToken>);
    function Scan: TArray<TUsesListEntry>;
  end;

procedure TUsesEntryDraft.Reset;
begin
  Name := '';
  InPath := '';
  First := -1;
  Last := -1;
  AfterIn := False;
end;

constructor TUsesListScanner.Create(const ATokens: TArray<TPascalToken>);
begin
  inherited Create;
  FTokens := ATokens;
end;

/// <summary>Steht AWord in einem Package am Anfang einer Anweisung (sonst ein Bezeichner)?</summary>
function TUsesListScanner.StartsStatement(const AWord: string): Boolean;
begin
  Result := FIsPackage and (FTokens[FIndex].Kind = TPascalTokenKind.Identifier) and (FPrevious >= 0);
  Result := Result and FTokens[FPrevious].IsSymbol(';') and SameText(FTokens[FIndex].Text, AWord);
end;

function TUsesListScanner.ListKind(out AKind: TUsesListKind): Boolean;
begin
  Result := True;
  // uses überall; contains und requires nur in Packages am Anfang einer Anweisung.
  if FTokens[FIndex].IsKeyword('uses') then
  begin
    AKind := TUsesListKind.UsedUnit;
  end
  else if StartsStatement('contains') then
  begin
    AKind := TUsesListKind.ContainedUnit;
  end
  else if StartsStatement('requires') then
  begin
    AKind := TUsesListKind.RequiredPackage;
  end
  else
  begin
    Result := False;
  end;
end;

procedure TUsesListScanner.Flush(AKind: TUsesListKind);
var
  mEntry: TUsesListEntry;
begin
  if FDraft.Name <> '' then
  begin
    mEntry.Kind := AKind;
    mEntry.Name := FDraft.Name;
    mEntry.InPath := FDraft.InPath;
    mEntry.Range := TTextRange.Create(FTokens[FDraft.First].StartPos, FTokens[FDraft.Last].EndPos);
    FEntries := FEntries + [mEntry];
  end;
  FDraft.Reset;
end;

procedure TUsesListScanner.ReadToken(AIndex: Integer);
var
  mToken: TPascalToken;
begin
  mToken := FTokens[AIndex];
  if mToken.IsKeyword('in') then
  begin
    FDraft.AfterIn := True;
  end
  else if FDraft.AfterIn and (mToken.Kind = TPascalTokenKind.StringLiteral) then
  begin
    FDraft.InPath := Unquoted(mToken.Text);
  end
  else if not FDraft.AfterIn and ((mToken.Kind = TPascalTokenKind.Identifier) or mToken.IsSymbol('.')) then
  begin
    if FDraft.First < 0 then
    begin
      FDraft.First := AIndex;
    end;
    FDraft.Last := AIndex;
    FDraft.Name := FDraft.Name + mToken.Text;
  end;
end;

/// <summary>Liest die Liste hinter dem Schlüsselwort bei FIndex bis zum Semikolon (FIndex steht danach dort).
/// </summary>
procedure TUsesListScanner.ReadList(AKind: TUsesListKind);
begin
  FDraft.Reset;
  Inc(FIndex);
  while FIndex <= High(FTokens) do
  begin
    if FTokens[FIndex].IsSymbol(';') or FTokens[FIndex].IsSymbol(',') then
    begin
      Flush(AKind);
      if FTokens[FIndex].IsSymbol(';') then
      begin
        Break;
      end;
    end
    else
    begin
      ReadToken(FIndex);
    end;
    Inc(FIndex);
  end;
end;

function TUsesListScanner.Scan: TArray<TUsesListEntry>;
var
  mKind: TUsesListKind;
begin
  FEntries := nil;
  FIsPackage := IsPackageSource(FTokens);
  FIndex := 0;
  FPrevious := -1;
  while FIndex <= High(FTokens) do
  begin
    if IsCode(FTokens[FIndex]) then
    begin
      if ListKind(mKind) then
      begin
        ReadList(mKind);
      end;
      FPrevious := FIndex;
    end;
    Inc(FIndex);
  end;
  Result := FEntries;
end;

class function TUsesUnitNotFoundRule.Entries(const ATokens: TArray<TPascalToken>): TArray<TUsesListEntry>;
var
  mScanner: TUsesListScanner;
begin
  mScanner := TUsesListScanner.Create(ATokens);
  try
    Result := mScanner.Scan;
  finally
    mScanner.Free;
  end;
end;

type
  TScoredName = record
    Score: Integer;
    Name: string;
  end;

const
  cMaxSuggestions = 3;
  cMaxDistance = 2;

function Scored(AScore: Integer; const AName: string): TScoredName;
begin
  Result.Score := AScore;
  Result.Name := AName;
end;

/// <summary>Teilt die bekannten Units in solche mit Namespace vor AName und ähnlich geschriebene.</summary>
procedure CollectSuggestions(const AName: string; const AKnown: TArray<string>; AQualified: TList<string>;
  ASimilar: TList<TScoredName>);
var
  mKnown: string;
  mScore: Integer;
begin
  for mKnown in AKnown do
  begin
    if SameText(mKnown, AName) then
    begin
      Continue;
    end;
    if EndsText('.' + AName, mKnown) then
    begin
      AQualified.Add(mKnown);
    end
    else
    begin
      mScore := TTextFuzzy.EditDistance(AName, mKnown, cMaxDistance);
      if mScore <= cMaxDistance then
      begin
        ASimilar.Add(Scored(mScore, mKnown));
      end;
    end;
  end;
end;

/// <summary>Nach Abstand, bei Gleichstand nach Namen.</summary>
function ScoredOrder: IComparer<TScoredName>;
begin
  Result := TComparer<TScoredName>.Construct(
    function(const ALeft, ARight: TScoredName): Integer
    begin
      Result := ALeft.Score - ARight.Score;
      if Result = 0 then
      begin
        Result := CompareText(ALeft.Name, ARight.Name);
      end;
    end);
end;

procedure AppendSuggestion(var AResult: TArray<string>; const AName: string);
begin
  if Length(AResult) < cMaxSuggestions then
  begin
    AResult := AResult + [AName];
  end;
end;

class function TUsesUnitNotFoundRule.Suggestions(const AName: string; const AKnown: TArray<string>): TArray<string>;
var
  mQualified: TList<string>;
  mSimilar: TList<TScoredName>;
  mKnown: string;
  mItem: TScoredName;
begin
  Result := nil;
  mQualified := TList<string>.Create;
  mSimilar := TList<TScoredName>.Create;
  try
    CollectSuggestions(AName, AKnown, mQualified, mSimilar);
    mQualified.Sort;
    mSimilar.Sort(ScoredOrder);
    for mKnown in mQualified do
    begin
      AppendSuggestion(Result, mKnown);
    end;
    for mItem in mSimilar do
    begin
      AppendSuggestion(Result, mItem.Name);
    end;
  finally
    mSimilar.Free;
    mQualified.Free;
  end;
end;

/// <summary>Position des Zeichens AOffset (ab 0) in AText.</summary>
function PositionOf(const AText: string; AOffset: Integer): TTextPosition;
var
  Index: Integer;
begin
  Result := TTextPosition.Create(0, 0);
  for Index := 1 to AOffset do
  begin
    if AText[Index] = #10 then
    begin
      Result := TTextPosition.Create(Result.Line + 1, 0);
    end
    else
    begin
      Result := TTextPosition.Create(Result.Line, Result.Character + 1);
    end;
  end;
end;

class function TUsesUnitNotFoundRule.DiffEdit(const AOld, ANew: string): TTextEdit;
var
  Prefix, Suffix: Integer;
begin
  Prefix := 0;
  while (Prefix < Length(AOld)) and (Prefix < Length(ANew)) and (AOld[Prefix + 1] = ANew[Prefix + 1]) do
  begin
    Inc(Prefix);
  end;
  Suffix := 0;
  while (Suffix < Length(AOld) - Prefix) and (Suffix < Length(ANew) - Prefix) and
    (AOld[Length(AOld) - Suffix] = ANew[Length(ANew) - Suffix]) do
  begin
    Inc(Suffix);
  end;
  Result := TTextEdit.Create(TTextRange.Create(PositionOf(AOld, Prefix), PositionOf(AOld, Length(AOld) - Suffix)),
    Copy(ANew, Prefix + 1, Length(ANew) - Prefix - Suffix));
end;

/// <summary>"A", "A, B", "A, B oder C".</summary>
function Alternatives(const AItems: TArray<string>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AItems) do
  begin
    if Index = 0 then
    begin
      Result := AItems[Index];
    end
    else if Index = High(AItems) then
    begin
      Result := Result + cTexts[TUnresolvedText.OrSep].Text + AItems[Index];
    end
    else
    begin
      Result := Result + ', ' + AItems[Index];
    end;
  end;
end;

/// <summary>Mehrere gleichwertige Vorschläge: keiner bevorzugt.</summary>
procedure MarkAlternatives(var AFixes: TArray<TRuleFix>);
var
  mIndex: Integer;
begin
  if Length(AFixes) > 1 then
  begin
    for mIndex := 0 to High(AFixes) do
    begin
      AFixes[mIndex].Alternative := True;
    end;
  end;
end;

/// <summary>Je Unit in AUnits die Korrektur "uses Unit ergänzen" an der Stelle AOffset.</summary>
function UsesFixes(const ATokens: TArray<TPascalToken>; AOffset: Integer; const AUnits: TArray<string>;
  const ALineBreak: string): TArray<TRuleFix>;
var
  mUnitName: string;
  mEdit: TTextEdit;
begin
  Result := nil;
  for mUnitName in AUnits do
  begin
    if TUsesClauses.AddUnit(ATokens, AOffset, mUnitName, ALineBreak, mEdit) then
    begin
      Result := Result + [TRuleFix.Create(cTexts[TUnresolvedText.AddUses].Fmt([mUnitName]), [mEdit])];
    end;
  end;
  MarkAlternatives(Result);
end;

/// <summary>Beginnt die Anweisung AText ({$IF…} in Großbuchstaben) einen bedingten Block?</summary>
function OpensCondition(const AText: string): Boolean;
begin
  Result := StartsStr('{$IF', AText) or StartsStr('(*$IF', AText);
end;

/// <summary>Schließt die Anweisung AText einen bedingten Block?</summary>
function ClosesCondition(const AText: string): Boolean;
begin
  Result := StartsStr('{$ENDIF', AText) or StartsStr('{$IFEND', AText) or StartsStr('(*$ENDIF', AText) or
    StartsStr('(*$IFEND', AText);
end;

procedure MarkLines(var ALines: TArray<Boolean>; AFirst, ALast: Integer);
var
  mLine: Integer;
begin
  for mLine := AFirst to ALast do
  begin
    ALines[mLine] := True;
  end;
end;

/// <summary>Zeilen innerhalb von {$IF…}…{$ENDIF}: Element I gilt für Zeile I.</summary>
function ConditionalLines(const ATokens: TArray<TPascalToken>): TArray<Boolean>;
var
  mToken: TPascalToken;
  mText: string;
  mDepth, mLastLine, mStartLine: Integer;
begin
  mLastLine := 0;
  if ATokens <> nil then
  begin
    mLastLine := ATokens[High(ATokens)].EndPos.Line;
  end;
  SetLength(Result, mLastLine + 1);
  mDepth := 0;
  mStartLine := 0;
  for mToken in ATokens do
  begin
    if mToken.Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    mText := UpperCase(mToken.Text);
    if OpensCondition(mText) then
    begin
      if mDepth = 0 then
      begin
        mStartLine := mToken.StartPos.Line;
      end;
      Inc(mDepth);
    end
    else if (mDepth > 0) and ClosesCondition(mText) then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        MarkLines(Result, mStartLine, mToken.EndPos.Line);
      end;
    end;
  end;
  if mDepth > 0 then
  begin
    MarkLines(Result, mStartLine, mLastLine);
  end;
end;

/// <summary>Liegt die Zeile ALine in einem bedingten Block (ConditionalLines)?</summary>
function InCondition(const ALines: TArray<Boolean>; ALine: Integer): Boolean;
begin
  Result := (ALine <= High(ALines)) and ALines[ALine];
end;

/// <summary>Mit Include-Dateien kann ein Name dort deklariert sein: dann nur mittlere Sicherheit.</summary>
function IncludeConfidence(const ATokens: TArray<TPascalToken>): TRuleConfidence;
var
  mToken: TPascalToken;
begin
  Result := TRuleConfidence.High;
  for mToken in ATokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Directive) and (StartsText('{$I ', mToken.Text) or
      StartsText('{$INCLUDE ', mToken.Text)) then
    begin
      Result := TRuleConfidence.Medium;
    end;
  end;
end;

/// <summary>Sind Index und alle verwendeten Units bekannt, sodass ein fehlender Name sicher fehlt?</summary>
function NamesCheckable(const AContext: TRuleContext): Boolean;
begin
  Result := (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) and TUnresolvedNames.Available(AContext.Index);
  Result := Result and TUnresolvedNames.UsesKnown(AContext.Index, TUsesClauses.UsedUnits(AContext.Tree.Tokens),
    AContext.Namespaces, AContext.EnsureUnit);
end;

/// <summary>Kandidaten ohne die, die eine andere Kandidatin im interface einbinden und den Typ weiterreichen
/// (Fassade vor Quelle); sortiert.</summary>
function WithoutForwarders(const AIndex: ISymbolIndex; ACandidates: TList<string>): TArray<string>;
var
  mName, mOther: string;
  mFound: TUnitIndex;
  mUsed: Boolean;
begin
  Result := nil;
  for mName in ACandidates do
  begin
    mUsed := False;
    for mOther in ACandidates do
    begin
      if not SameText(mOther, mName) and AIndex.FindUnit(mOther, mFound) and
        (IndexText(mName, mFound.InterfaceUses) >= 0) then
      begin
        mUsed := True;
      end;
    end;
    if not mUsed then
    begin
      Result := Result + [mName];
    end;
  end;
  TArray.Sort<string>(Result);
end;

/// <summary>Quelle der Suche aus der Option searchPaths: project (Vorgabe), atlas oder both.</summary>
function SourcesOf(const AOptions: string): TRuleUnitSources;
var
  Value: string;
begin
  Value := TRuleOptions.Text(AOptions, 'searchPaths', 'project');
  if SameText(Value, 'atlas') then
  begin
    Result := [TRuleUnitSource.Atlas];
  end
  else if SameText(Value, 'both') then
  begin
    Result := [TRuleUnitSource.Project, TRuleUnitSource.Atlas];
  end
  else
  begin
    Result := [TRuleUnitSource.Project];
  end;
end;

type
  /// <summary>Ein Lauf von uses-unit-not-found über eine Datei.</summary>
  TUsesUnitCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FEntries: TArray<TUsesListEntry>;
    FLines: TArray<Boolean>;
    FOwn: string;
    FSources: TRuleUnitSources;
    FKnown: TArray<string>;
    FHasKnown: Boolean;
    function Known: TArray<string>;
    procedure ReportSelfUse;
    procedure ReportMissingFiles;
    function LibraryMissing: Boolean;
    procedure AddSearchPathFix(const AFolder: string; var AFixes: TArray<TRuleFix>);
    procedure ReportMissingUnit(const AEntry: TUsesListEntry);
    procedure CheckEntry(const AEntry: TUsesListEntry);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

constructor TUsesUnitCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

/// <summary>Bekannte Units, erst bei Bedarf gelesen.</summary>
function TUsesUnitCheck.Known: TArray<string>;
begin
  if not FHasKnown then
  begin
    FKnown := FContext.Units.KnownUnits(FSources);
    FHasKnown := True;
  end;
  Result := FKnown;
end;

/// <summary>F2092: eine Unit, die sich selbst einbindet; braucht keine Pfade.</summary>
procedure TUsesUnitCheck.ReportSelfUse;
var
  mEntry: TUsesListEntry;
begin
  for mEntry in FEntries do
  begin
    if (mEntry.Kind <> TUsesListKind.RequiredPackage) and (FOwn <> '') and SameText(mEntry.Name, FOwn) then
    begin
      FReport.Add(mEntry.Range, cTexts[TUnresolvedText.UsesItself].Fmt([mEntry.Name]));
    end;
  end;
end;

/// <summary>F1026 auch ohne Projekt (#1379, Fall CmF1026): "in '…'" gilt nur relativ zur verwendenden Datei,
/// dafür braucht es keine Suchpfade.</summary>
procedure TUsesUnitCheck.ReportMissingFiles;
var
  mEntry: TUsesListEntry;
begin
  if not Assigned(FContext.FileExists) then
  begin
    Exit;
  end;
  for mEntry in FEntries do
  begin
    if (mEntry.Kind <> TUsesListKind.RequiredPackage) and (mEntry.InPath <> '') and
      not InCondition(FLines, mEntry.Range.StartPos.Line) and not FContext.FileExists(mEntry.InPath) then
    begin
      FReport.Add(mEntry.Range, cTexts[TUnresolvedText.FileNotFound].Fmt([mEntry.InPath,
        mEntry.Name]));
    end;
  end;
end;

/// <summary>F1027: Ohne System fehlt der Bibliothekspfad; dann eine Meldung statt einer je Unit.</summary>
function TUsesUnitCheck.LibraryMissing: Boolean;
begin
  Result := FContext.Units.Find('System', '', FContext.FileName, [TRuleUnitSource.Project]) =
    TRuleUnitAnswer.Missing;
  if Result and (Length(FEntries) > 0) then
  begin
    FReport.Add(FEntries[0].Range, cTexts[TUnresolvedText.SystemNotFound].Text);
  end;
end;

/// <summary>Ordner unter dem Projekt, der in keinem Suchpfad steht: in DCC_UnitSearchPath der Basis aufnehmen.
/// </summary>
procedure TUsesUnitCheck.AddSearchPathFix(const AFolder: string; var AFixes: TArray<TRuleFix>);
var
  mProjectFile, mProjectText, mNewText, mKey: string;
  mFix: TRuleFix;
begin
  if (AFolder = '') or not FContext.Units.ReadProject(mProjectFile, mProjectText) then
  begin
    Exit;
  end;
  mKey := TDprojEditor.ConfigKey(mProjectText, 'Base');
  if (mKey <> '') and (TDprojEditor.AddToList(mProjectText, mKey, 'DCC_UnitSearchPath', AFolder, mNewText) =
    TDprojEditResult.Added) then
  begin
    mFix := TRuleFix.Create(cTexts[TUnresolvedText.AddSearchPath].Fmt([AFolder]),
      [TUsesUnitNotFoundRule.DiffEdit(mProjectText, mNewText)]);
    mFix.FileName := mProjectFile;
    AFixes := [mFix] + AFixes;
  end;
end;

procedure TUsesUnitCheck.ReportMissingUnit(const AEntry: TUsesListEntry);
var
  mSuggested: TArray<string>;
  mSuggestion, mFolder: string;
  mFixes: TArray<TRuleFix>;
begin
  mSuggested := TUsesUnitNotFoundRule.Suggestions(AEntry.Name, Known);
  mFixes := nil;
  for mSuggestion in mSuggested do
  begin
    mFixes := mFixes + [TRuleFix.Create(cTexts[TUnresolvedText.UseName].Fmt([mSuggestion]),
      [TTextEdit.Create(AEntry.Range, mSuggestion)])];
  end;
  mFolder := FContext.Units.FolderOutsidePaths(AEntry.Name);
  AddSearchPathFix(mFolder, mFixes);
  MarkAlternatives(mFixes);
  if mFolder <> '' then
  begin
    FReport.Add(AEntry.Range, cTexts[TUnresolvedText.OutsidePaths].Fmt([AEntry.Name, mFolder]), TRuleConfidence.High,
      mFixes);
  end
  else if Length(mSuggested) > 0 then
  begin
    FReport.Add(AEntry.Range, cTexts[TUnresolvedText.Similar].Fmt(
      [AEntry.Name, Alternatives(mSuggested)]), TRuleConfidence.High, mFixes);
  end
  else
  begin
    FReport.Add(AEntry.Range, cTexts[TUnresolvedText.UnitNotFound].Fmt([AEntry.Name]));
  end;
end;

procedure TUsesUnitCheck.CheckEntry(const AEntry: TUsesListEntry);
begin
  if InCondition(FLines, AEntry.Range.StartPos.Line) or ((FOwn <> '') and SameText(AEntry.Name, FOwn)) then
  begin
    Exit;
  end;
  if AEntry.Kind = TUsesListKind.RequiredPackage then
  begin
    if FContext.Units.FindPackage(AEntry.Name) = TRuleUnitAnswer.Missing then
    begin
      FReport.Add(AEntry.Range, cTexts[TUnresolvedText.PackageNotFound].Fmt([AEntry.Name]));
    end;
    Exit;
  end;
  if FContext.Units.Find(AEntry.Name, AEntry.InPath, FContext.FileName, FSources) <> TRuleUnitAnswer.Missing then
  begin
    Exit;
  end;
  if AEntry.InPath <> '' then
  begin
    FReport.Add(AEntry.Range, cTexts[TUnresolvedText.FileNotFound].Fmt([AEntry.InPath, AEntry.Name]));
  end
  else
  begin
    ReportMissingUnit(AEntry);
  end;
end;

procedure TUsesUnitCheck.Run;
var
  mEntry: TUsesListEntry;
begin
  FEntries := TUsesUnitNotFoundRule.Entries(FContext.Tree.Tokens);
  FLines := ConditionalLines(FContext.Tree.Tokens);
  FOwn := TUsesClauses.OwnName(FContext.Tree.Tokens);
  ReportSelfUse;
  if FContext.Units = nil then
  begin
    ReportMissingFiles;
    Exit;
  end;
  FSources := SourcesOf(FContext.Options);
  if LibraryMissing then
  begin
    Exit;
  end;
  for mEntry in FEntries do
  begin
    CheckEntry(mEntry);
  end;
end;

procedure TUsesUnitNotFoundRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TUsesUnitCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mCheck := TUsesUnitCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

{ TUnresolvedAttributeRule }

const
  // Attribute, die der Compiler selbst kennt (System); sie fehlen in einem unvollständigen Index.
  CompilerAttributes: array[0..8] of string = ('Weak', 'Unsafe', 'Ref', 'Volatile', 'Align', 'HPPGEN', 'HFA',
    'Stored', 'Result');
  // DUnitX-Attribute: ohne sie laufen die Tests nicht. Unit, falls DUnitX nicht im Index steht.
  DUnitXAttributes: array[0..16] of string = ('TestFixture', 'Test', 'TestCase', 'Setup', 'TearDown',
    'SetupFixture', 'TearDownFixture', 'Ignore', 'Category', 'WillRaise', 'WillRaiseAny', 'RepeatTest', 'MaxTime',
    'TestCaseProvider', 'TestInOwnThread', 'IgnoreMemoryLeaks', 'AutoNameTestCase');
  DUnitXUnit = 'DUnitX.TestFramework';

function TUnresolvedAttributeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unresolved-attribute', TRuleSeverity.Error,
    cTexts[TUnresolvedText.AttributeTitle].Text);
end;

/// <summary>Ist ALocation ein Typ auf oberster Ebene, der eine Attributklasse sein kann?</summary>
function IsAttributeType(const ALocation: TSymbolLocation): Boolean;
begin
  Result := (ALocation.Symbol.Container = '') and (ALocation.Symbol.Kind in [TIndexSymbolKind.ClassType,
    TIndexSymbolKind.TypeAlias]);
end;

class function TUnresolvedAttributeRule.DeclaringUnits(const AIndex: ISymbolIndex; const AName: string): TArray<string>;
var
  mCandidates: TList<string>;
  mLocation: TSymbolLocation;
  mName: string;
begin
  Result := nil;
  if AIndex = nil then
  begin
    Exit;
  end;
  mCandidates := TList<string>.Create;
  try
    for mName in TAttributes.ClassNames(AName) do
    begin
      for mLocation in AIndex.FindSymbols(mName) do
      begin
        if IsAttributeType(mLocation) and not mCandidates.Contains(mLocation.UnitName) then
        begin
          mCandidates.Add(mLocation.UnitName);
        end;
      end;
    end;
    Result := WithoutForwarders(AIndex, mCandidates);
  finally
    mCandidates.Free;
  end;
end;

/// <summary>Offset ab 0 des ersten Tokens an APosition; 0 ohne.</summary>
function OffsetAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  Token: TPascalToken;
begin
  for Token in ATokens do
  begin
    if (Token.StartPos.Line = APosition.Line) and (Token.StartPos.Character = APosition.Character) then
    begin
      Exit(Token.Offset);
    end;
  end;
  Result := 0;
end;

/// <summary>Kennt der Compiler das Attribut ABare (oder ABareAttribute) selbst?</summary>
function CompilerAttribute(const ABare: string): Boolean;
begin
  Result := MatchText(ABare, CompilerAttributes) or MatchText(ABare + 'Attribute', CompilerAttributes);
end;

/// <summary>Knoten mit dem Namen eines Attributs (bei Test(1) der Name vor der Klammer).</summary>
function AttributeNameNode(AItem: TSyntaxNode): TSyntaxNode;
begin
  Result := AItem;
  if (AItem.Kind = TSyntaxKind.Call) and (AItem.ChildCount > 0) then
  begin
    Result := AItem[0];
  end;
end;

/// <summary>Units, die das Attribut ABare deklarieren; für DUnitX-Attribute ohne Index DUnitX.TestFramework.
/// </summary>
function AttributeUnits(const AIndex: ISymbolIndex; const ABare: string): TArray<string>;
begin
  Result := TUnresolvedAttributeRule.DeclaringUnits(AIndex, ABare);
  if (Length(Result) = 0) and MatchText(ABare, DUnitXAttributes) then
  begin
    Result := [DUnitXUnit];
  end;
end;

/// <summary>Meldung für das fehlende Attribut AName mit dem Code ACode und den Kandidaten AUnits.</summary>
function AttributeMessage(const AName, ABare, ACode: string; const AUnits: TArray<string>): string;
begin
  Result := cTexts[TUnresolvedText.AttributeIgnored].Fmt([AName]);
  if MatchText(ABare, DUnitXAttributes) or ((Length(AUnits) > 0) and StartsText('DUnitX', AUnits[0])) then
  begin
    Result := Result + cTexts[TUnresolvedText.TestsDontRun].Text;
  end;
  Result := Result + cTexts[TUnresolvedText.LikeCode].Fmt([ACode]);
  if Length(AUnits) = 1 then
  begin
    Result := Result + cTexts[TUnresolvedText.UnitMissing].Fmt([AUnits[0]]);
  end
  else if Length(AUnits) > 1 then
  begin
    Result := Result + cTexts[TUnresolvedText.Candidates].Fmt([Alternatives(AUnits)]);
  end;
end;

type
  /// <summary>Ein Lauf von unresolved-attribute über eine Datei.</summary>
  TUnresolvedAttributeCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FResolver: TNameResolver;
    FLines: TArray<Boolean>;
    FLineBreak: string;
    FLevel: TRuleConfidence;
    // {$WARN UNKNOWN_CUSTOM_ATTRIBUTE …} außerhalb bedingter Blöcke: Offset und ob ERROR (#1379).
    FSwitchOffsets: TArray<Integer>;
    FSwitchErrors: TArray<Boolean>;
    procedure ReadSwitches;
    function CodeAt(AOffset: Integer): string;
    function Resolves(ANameNode: TSyntaxNode; const AUse: TAttributeUse): Boolean;
    procedure CheckItem(AItem: TSyntaxNode);
    procedure CheckAttribute(ANode: TSyntaxNode);
    procedure Visit(ARoot: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

constructor TUnresolvedAttributeCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

procedure TUnresolvedAttributeCheck.ReadSwitches;
var
  mToken: TPascalToken;
  mWords: TArray<string>;
begin
  FSwitchOffsets := nil;
  FSwitchErrors := nil;
  for mToken in FContext.Tree.Tokens do
  begin
    if (mToken.Kind <> TPascalTokenKind.Directive) or InCondition(FLines, mToken.StartPos.Line) then
    begin
      Continue;
    end;
    mWords := TDirectiveNames.Body(mToken.Text).Split([' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty);
    if (Length(mWords) >= 3) and SameText(mWords[0], 'WARN') and
      SameText(mWords[1], 'UNKNOWN_CUSTOM_ATTRIBUTE') then
    begin
      FSwitchOffsets := FSwitchOffsets + [mToken.Offset];
      FSwitchErrors := FSwitchErrors + [SameText(mWords[2], 'ERROR')];
    end;
  end;
end;

/// <summary>Mit {$WARN UNKNOWN_CUSTOM_ATTRIBUTE ERROR} davor meldet dcc E1074 statt W1074 (#1379).</summary>
function TUnresolvedAttributeCheck.CodeAt(AOffset: Integer): string;
var
  mIndex: Integer;
begin
  Result := 'W1074';
  for mIndex := 0 to High(FSwitchOffsets) do
  begin
    if (FSwitchOffsets[mIndex] < AOffset) and FSwitchErrors[mIndex] then
    begin
      Result := 'E1074';
    end
    else if FSwitchOffsets[mIndex] < AOffset then
    begin
      Result := 'W1074';
    end;
  end;
end;

/// <summary>Findet die Auflösung das Attribut (zuerst NameAttribute, dann Name, wie der Compiler) oder kann es
/// nicht sicher beurteilen?</summary>
function TUnresolvedAttributeCheck.Resolves(ANameNode: TSyntaxNode; const AUse: TAttributeUse): Boolean;
var
  mNames: TArray<string>;
  mResolved: TResolvedSymbol;
begin
  mNames := AUse.Name.Split(['.']);
  mNames[High(mNames)] := mNames[High(mNames)] + 'Attribute';
  mResolved := FResolver.ResolveChain(FContext.Tree, FContext.RelativePath, mNames, ANameNode.StartOffset);
  Result := mResolved.Found or FResolver.HasUnknownAncestor;
  if Result then
  begin
    Exit;
  end;
  mResolved := FResolver.ResolveChain(FContext.Tree, FContext.RelativePath, AUse.Name.Split(['.']),
    ANameNode.StartOffset);
  Result := mResolved.Found or FResolver.HasUnknownAncestor or FResolver.IsUnitPrefix(AUse.Name);
end;

procedure TUnresolvedAttributeCheck.CheckItem(AItem: TSyntaxNode);
var
  mNameNode: TSyntaxNode;
  mUse: TAttributeUse;
  mUnits: TArray<string>;
  mBare: string;
begin
  mNameNode := AttributeNameNode(AItem);
  if not (mNameNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
    not TAttributes.At(FContext.Tree, mNameNode.StartPos, mUse) then
  begin
    Exit;
  end;
  mBare := Copy(mUse.Name, LastDelimiter('.', mUse.Name) + 1, MaxInt);
  if CompilerAttribute(mBare) or Resolves(mNameNode, mUse) then
  begin
    Exit;
  end;
  mUnits := AttributeUnits(FContext.Index, mBare);
  FReport.Add(mUse.NameRange, AttributeMessage(mUse.Name, mBare, CodeAt(mNameNode.StartOffset), mUnits), FLevel,
    UsesFixes(FContext.Tree.Tokens, OffsetAt(FContext.Tree.Tokens, mNameNode.StartPos), mUnits, FLineBreak));
end;

procedure TUnresolvedAttributeCheck.CheckAttribute(ANode: TSyntaxNode);
var
  mIndex: Integer;
begin
  if not InCondition(FLines, ANode.StartPos.Line) then
  begin
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      CheckItem(ANode[mIndex]);
    end;
  end;
end;

// Iterativ (Bericht M1).
procedure TUnresolvedAttributeCheck.Visit(ARoot: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.Attribute then
      begin
        CheckAttribute(mNode);
      end
      // In Anweisungen gibt es keine Attribute.
      else if not (mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock]) then
      begin
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TUnresolvedAttributeCheck.Run;
begin
  FLines := ConditionalLines(FContext.Tree.Tokens);
  ReadSwitches;
  FLineBreak := TTextLines.LineBreakOf(FContext.Text);
  // Mit Include-Dateien kann das Attribut dort deklariert sein.
  FLevel := IncludeConfidence(FContext.Tree.Tokens);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  FCache := TRuleDerived.Open(FContext);
  FResolver := TRuleDerived.Resolver(FCache, FContext);
  FResolver.PinTree(FContext.Tree, FContext.RelativePath);
  try
    Visit(FContext.Tree.Root);
  finally
    FResolver.UnpinTree;
  end;
end;

procedure TUnresolvedAttributeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TUnresolvedAttributeCheck;
begin
  if not NamesCheckable(AContext) then
  begin
    Exit;
  end;
  mCheck := TUnresolvedAttributeCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

{ TUnresolvedTypeRule }

const
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];

/// <summary>Meldung für einen Namen, der keinen Typ bezeichnet, mit dem Code von Delphi 13 (#1382).</summary>
function NotATypeMessage(const AName: string; AQualified: Boolean; AKind: TIndexSymbolKind): string;
begin
  if AQualified then
  begin
    Result := cTexts[TUnresolvedText.NotType].Fmt([AName]);
  end
  else if AKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine] then
  begin
    Result := cTexts[TUnresolvedText.RoutineNotType].Fmt([AName]);
  end
  else if AKind in [TIndexSymbolKind.EnumMember, TIndexSymbolKind.Constant] then
  begin
    Result := cTexts[TUnresolvedText.ConstantNotType].Fmt([AName, AName]);
  end
  else
  begin
    Result := cTexts[TUnresolvedText.NotType].Fmt([AName]);
  end;
end;

function TUnresolvedTypeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unresolved-type', TRuleSeverity.Error, cTexts[TUnresolvedText.TypeTitle].Text);
end;

/// <summary>Zahl der Typparameter von ASymbol.</summary>
function TypeArity(const ASymbol: TIndexSymbol): Integer;
begin
  Result := 0;
  if ASymbol.TypeParams <> '' then
  begin
    Result := Length(ASymbol.TypeParams.Split([',']));
  end;
end;

/// <summary>Ist ALocation ein Typ im interface einer anderen Unit als AOwnUnit mit AArity Typparametern?</summary>
function IsForeignType(const ALocation: TSymbolLocation; const AOwnUnit: string; AArity: Integer): Boolean;
begin
  Result := (ALocation.Symbol.Container = '') and (ALocation.Symbol.Kind in TypeKinds) and
    ALocation.Symbol.InInterface;
  Result := Result and not SameText(ALocation.UnitName, AOwnUnit) and (TypeArity(ALocation.Symbol) = AArity);
end;

class function TUnresolvedTypeRule.DeclaringUnits(const AIndex: ISymbolIndex; const AName, AOwnUnit: string;
  AArity: Integer): TArray<string>;
var
  mCandidates: TList<string>;
  mLocation: TSymbolLocation;
begin
  Result := nil;
  if AIndex = nil then
  begin
    Exit;
  end;
  mCandidates := TList<string>.Create;
  try
    for mLocation in AIndex.FindSymbols(AName) do
    begin
      if IsForeignType(mLocation, AOwnUnit, AArity) and not mCandidates.Contains(mLocation.UnitName) then
      begin
        mCandidates.Add(mLocation.UnitName);
      end;
    end;
    // Fassade vor Quelle wie bei unresolved-attribute.
    Result := WithoutForwarders(AIndex, mCandidates);
  finally
    mCandidates.Free;
  end;
end;

/// <summary>Zahl der Typargumente der Typreferenz ANode.</summary>
function GenericArity(ANode: TSyntaxNode): Integer;
var
  mArgs: TSyntaxNode;
begin
  Result := 0;
  mArgs := ANode.FindChild(TSyntaxKind.GenericArgs);
  if mArgs <> nil then
  begin
    Result := mArgs.ChildCount;
  end;
end;

/// <summary>Ist ANode keine Typreferenz im Sinn der Regel? Der Anfang eines Teilbereichs (MinWert..MaxWert) ist
/// ein Ausdruck, kein Typ.</summary>
function IgnoredReference(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Name = '') or MatchText(ANode.Name, ['string', 'file', 'const']) or
    ((ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.SubrangeType));
end;

/// <summary>Bereich des Namens selbst, ohne Typargumente.</summary>
function ReferenceNameRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, TTextPosition.Create(ANode.StartPos.Line,
    ANode.StartPos.Character + Length(ANode.Name)));
end;

/// <summary>Meldung für den nicht deklarierten Typ ANode mit den Kandidaten AUnits.</summary>
function MissingTypeMessage(ANode: TSyntaxNode; const AUnits: TArray<string>): string;
begin
  Result := cTexts[TUnresolvedText.TypeUndeclared].Fmt([ANode.Name]);
  if Length(AUnits) = 1 then
  begin
    Result := Result + cTexts[TUnresolvedText.MissingInUses].Fmt([AUnits[0]]);
  end
  else if Length(AUnits) > 1 then
  begin
    Result := Result + cTexts[TUnresolvedText.TypeCandidates].Fmt([Alternatives(AUnits)]);
  end;
  // Ziel eines Zeigertyps (PFoo = ^TFoo) meldet der Compiler als undefinierten Typ.
  if (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.PointerType) then
  begin
    Result := Result + cTexts[TUnresolvedText.LikeE2564].Text;
  end
  else
  begin
    Result := Result + cTexts[TUnresolvedText.LikeE2003].Text;
  end;
end;

/// <summary>Ist der gefundene Name AResolved ein Wert statt eines Typs (Variable, Konstante, Routine)? Lokale
/// Namen zählen nicht: In hWnd: HWND meint HWND den Typ, der Parametername gilt dort noch nicht (Watchdog,
/// KeyHook).</summary>
function IsValueSymbol(const AResolved: TResolvedSymbol): Boolean;
begin
  Result := (AResolved.Kind = TResolvedKind.Symbol) and not AResolved.IsType;
  Result := Result and (AResolved.SymbolKind in [TIndexSymbolKind.EnumMember, TIndexSymbolKind.Constant,
    TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Method,
    TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine]);
end;

type
  /// <summary>Ein Lauf von unresolved-type über eine Datei.</summary>
  TUnresolvedTypeCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FResolver: TNameResolver;
    FLines: TArray<Boolean>;
    FLineBreak: string;
    FOwnUnit: string;
    // Units aus den uses-Listen der Datei, für die Typen der IDE.
    FUsed: TArray<string>;
    FLevel: TRuleConfidence;
    // Typnamen und Typparameter der Datei: gelten als bekannt.
    FDeclared: TDictionary<string, Boolean>;
    procedure CollectNode(ANode: TSyntaxNode);
    procedure Collect(ARoot: TSyntaxNode);
    function NestedSomewhere(const AName: string): Boolean;
    function KnownName(const ABare: string): Boolean;
    function Unclear(ANode: TSyntaxNode; const ABare: string): Boolean;
    procedure CheckReference(ANode: TSyntaxNode);
    procedure Visit(ARoot: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

constructor TUnresolvedTypeCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FDeclared := TDictionary<string, Boolean>.Create;
  FResolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
end;

destructor TUnresolvedTypeCheck.Destroy;
begin
  FResolver.Free;
  FDeclared.Free;
  inherited Destroy;
end;

procedure TUnresolvedTypeCheck.CollectNode(ANode: TSyntaxNode);
var
  mIndex: Integer;
begin
  if (ANode.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ForwardType]) and (ANode.Name <> '') then
  begin
    FDeclared.AddOrSetValue(LowerCase(ANode.Name), True);
  end
  else if ANode.Kind = TSyntaxKind.GenericParams then
  begin
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      FDeclared.AddOrSetValue(LowerCase(ANode[mIndex].Name), True);
    end;
  end;
end;

// Iterativ (Bericht M1).
procedure TUnresolvedTypeCheck.Collect(ARoot: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      CollectNode(mNode);
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Kennt der Index AName als verschachtelten Typ (geerbte innere Typen sind ohne Präfix sichtbar)?
/// </summary>
function TUnresolvedTypeCheck.NestedSomewhere(const AName: string): Boolean;
var
  mLocation: TSymbolLocation;
begin
  for mLocation in FContext.Index.FindSymbols(AName) do
  begin
    if (mLocation.Symbol.Container <> '') and (mLocation.Symbol.Kind in TypeKinds) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Typen, die der Compiler kennt, ohne dass System.pas sie deklariert (TextFile, Real48 …, #1382), und
/// Typen der Datei.</summary>
function TUnresolvedTypeCheck.KnownName(const ABare: string): Boolean;
begin
  Result := TResolverText.IsBuiltinTypeName(ABare) or TSystemIntrinsics.IsType(ABare) or
    FDeclared.ContainsKey(LowerCase(ABare));
end;

/// <summary>Kann die Regel nicht sicher sagen, dass der Typ fehlt?</summary>
function TUnresolvedTypeCheck.Unclear(ANode: TSyntaxNode; const ABare: string): Boolean;
begin
  Result := FResolver.HasUnknownAncestor or FResolver.IsUnitPrefix(ANode.Name) or NestedSomewhere(ABare);
end;

procedure TUnresolvedTypeCheck.CheckReference(ANode: TSyntaxNode);
var
  mNames, mUnits: TArray<string>;
  mBare: string;
  mResolved: TResolvedSymbol;
  mRange: TTextRange;
begin
  if IgnoredReference(ANode) then
  begin
    Exit;
  end;
  mNames := ANode.Name.Split(['.']);
  mBare := mNames[High(mNames)];
  if KnownName(mBare) then
  begin
    Exit;
  end;
  mResolved := FResolver.ResolveChain(FContext.Tree, FContext.RelativePath, mNames, ANode.StartOffset);
  mRange := ReferenceNameRange(ANode);
  // Gefunden, aber kein Typ: Variable, Konstante, Routine.
  if mResolved.Found and IsValueSymbol(mResolved) then
  begin
    FReport.Add(mRange, NotATypeMessage(ANode.Name, Length(mNames) > 1, mResolved.SymbolKind), FLevel);
  end;
  if mResolved.Found or Unclear(ANode, mBare) or
    IdeDeclares(FContext.IdeTypes, mNames, FUsed, FContext.Namespaces) then
  begin
    Exit;
  end;
  mUnits := nil;
  if Length(mNames) = 1 then
  begin
    mUnits := WithIdeUnits(FContext.IdeTypes, mBare, FOwnUnit,
      TUnresolvedTypeRule.DeclaringUnits(FContext.Index, mBare, FOwnUnit, GenericArity(ANode)));
  end;
  FReport.Add(mRange, MissingTypeMessage(ANode, mUnits), FLevel, UsesFixes(FContext.Tree.Tokens, ANode.StartOffset,
    mUnits, FLineBreak));
end;

// Iterativ (Bericht M1).
procedure TUnresolvedTypeCheck.Visit(ARoot: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind in [TSyntaxKind.AsmBlock, TSyntaxKind.WithStatement, TSyntaxKind.Error] then
      begin
        Continue;
      end;
      if (mNode.Kind = TSyntaxKind.TypeReference) and not InCondition(FLines, mNode.StartPos.Line) then
      begin
        CheckReference(mNode);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TUnresolvedTypeCheck.Run;
begin
  FLines := ConditionalLines(FContext.Tree.Tokens);
  FLineBreak := TTextLines.LineBreakOf(FContext.Text);
  FOwnUnit := TUsesClauses.OwnName(FContext.Tree.Tokens);
  FUsed := TUsesClauses.UsedUnits(FContext.Tree.Tokens);
  // Mit Include-Dateien kann der Typ dort deklariert sein.
  FLevel := IncludeConfidence(FContext.Tree.Tokens);
  Collect(FContext.Tree.Root);
  FResolver.Namespaces := FContext.Namespaces;
  FResolver.PinTree(FContext.Tree, FContext.RelativePath);
  try
    Visit(FContext.Tree.Root);
  finally
    FResolver.UnpinTree;
  end;
end;

procedure TUnresolvedTypeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TUnresolvedTypeCheck;
begin
  if not NamesCheckable(AContext) then
  begin
    Exit;
  end;
  mCheck := TUnresolvedTypeCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

procedure RegisterUnresolvedRules(ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUnresolvedIdentifierRule.Create);
  ARegistry.Register(TUsesUnitNotFoundRule.Create);
  ARegistry.Register(TUnresolvedAttributeRule.Create);
  ARegistry.Register(TUnresolvedTypeRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Unresolved', cTexts);

end.
