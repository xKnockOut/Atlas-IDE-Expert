unit Atlas.Common.Lsp.ReferenceConfidence;

// Treffersicherheit der Verwendungen (#1119). Eine Stelle, deren Name passt,
// ist
// - sicher, wenn der Namensauflöser sie eindeutig dem gesuchten Symbol
//   zuordnet (wie bisher),
// - erschlossen mit Grund, wenn sie das Symbol meinen kann:
//   - interface: Aufruf über ein Interface, das die Klasse des Symbols umsetzt,
//   - virtual: Aufruf der Methode eines Vorfahren, die das Symbol überschreibt,
//   - ambiguous: Überladung nicht eindeutig, das Symbol ist einer der gleich
//     guten Kandidaten (TNameResolver.ResolveAll, #263); wählt der Auflöser
//     es trotzdem, gilt die Stelle als Matched,
//   - unresolved: gleicher Name, aber nichts auflösbar (with, Ausdruck mit
//     unbekanntem Typ),
//   - inactiveBranch: Stelle in einem {$IFDEF}-Zweig, der unter den aktiven
//     Symbolen nicht gilt (#476); löst sie trotzdem auf das Symbol auf,
//     gilt sie als Matched,
//   - text: der Name als ganzes String-Literal (nur mit references.textMatches).
// Umbenennen ändert sichere und Matched-Stellen, also dieselben wie vor #1119.
// Ohne references.inferred bleibt alles wie vor #1119: nur sichere Treffer,
// auch aus inaktiven Zweigen (die Token-Liste jedes Baums enthält alle Zweige).
// Namen in Routinenköpfen (procedure TBasis.Speichern) deklarieren und rufen
// nicht auf; sie werden nie erschlossen.
// Erschlossene Treffer entstehen nur für das gesuchte Symbol; teure Schritte
// (ResolveAll, Nachfahren im Index) laufen nur für Stellen, die nicht sicher
// sind, die Nachfahren je Typ einmal.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Lsp.InactiveRegions;

type
{$SCOPEDENUMS ON}
  TReferenceLevel = (Sure, Inferred);
  TReferenceReason = (None, Interface_, Virtual, Ambiguous, Unresolved, InactiveBranch, Text);
{$SCOPEDENUMS OFF}

  TReferenceConfidence = record
    Level: TReferenceLevel;
    Reason: TReferenceReason;
    /// <summary>Erklärung für Hover und MCP, etwa „Aufruf über ISpeicherbar.Speichern; TKunde ist eine von 2
    /// Umsetzungen“.</summary>
    Detail: string;
    /// <summary>Der Auflöser wählt das Symbol (sicher, in einem inaktiven Zweig oder als beste von mehreren
    /// Überladungen).</summary>
    Matched: Boolean;
    class function Sure: TReferenceConfidence; static;
    class function Inferred(AReason: TReferenceReason; const ADetail: string;
      AMatched: Boolean): TReferenceConfidence; static;
    function IsSure: Boolean;
    /// <summary>Umbenennen ändert die Stelle: sicher oder Matched (so viel wie vor #1119).</summary>
    function Renameable: Boolean;
    /// <summary>"sure" bzw. "inferred".</summary>
    function LevelName: string;
    /// <summary>Kennzeichen wie im LSP: '', "interface", "virtual", "ambiguous", "unresolved",
    /// "inactiveBranch", "text".</summary>
    function ReasonName: string;
    /// <summary>{"level", "reason", "detail"} für atlasConfidence; der Aufrufer übernimmt das Objekt.</summary>
    function ToJson: TJSONObject;
  end;

  TReferenceHit = record
    Range: TTextRange;
    Confidence: TReferenceConfidence;
  end;

  TReferenceClassifier = class
  private
    FResolver: TNameResolver;
    FIndex: ISymbolIndex;
    FWanted: TDefinitionTarget;
    FSymbol: TIndexSymbol;
    FHasSymbol: Boolean;
    /// <summary>Das Symbol trägt overload: Auch sichere Stellen können mehrdeutig sein.</summary>
    FOverloaded: Boolean;
    FName: string;
    FSettings: TReferenceSettings;
    FDescendants: TDictionary<string, TArray<TSymbolLocation>>;
    function Descendants(const ATypeName: string): TArray<TSymbolLocation>;
    function ContainerIsInterface(const AContainer: string): Boolean;
    function InheritedCall(const AResolved: TResolvedSymbol; out AConfidence: TReferenceConfidence): Boolean;
    function Ambiguous(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
      AMatched: Boolean; out AConfidence: TReferenceConfidence): Boolean;
  public
    /// <summary>AName ohne &amp;; ASymbol ist die Deklaration hinter AWanted (AHasSymbol False, wenn sie im Index
    /// fehlt: dann keine Gründe interface und virtual).</summary>
    constructor Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AWanted: TDefinitionTarget;
      const ASymbol: TIndexSymbol; AHasSymbol: Boolean; const AName: string; const ASettings: TReferenceSettings);
    destructor Destroy; override;
    /// <summary>Einstufung des Bezeichners ATokenIndex, dessen Name schon passt (auch als Attributname). False:
    /// kein Treffer. AInactive: inaktive Bereiche der Datei (leer ohne references.inferred).</summary>
    function Classify(ATree: TSyntaxTree; const AFileName: string; ATokenIndex: Integer;
      const AInactive: TArray<TLspInactiveRegion>; out AConfidence: TReferenceConfidence): Boolean;
    /// <summary>String-Literal, das genau den Namen enthält (nur mit references.inferred und textMatches).</summary>
    function TextMatch(const AToken: TPascalToken; out AConfidence: TReferenceConfidence): Boolean;
    /// <summary>Deklaration hinter AWanted aus der eigenen Datei (ATree) oder dem Index.</summary>
    class function SymbolOf(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const AWanted: TDefinitionTarget; out ASymbol: TIndexSymbol): Boolean; static;
    /// <summary>Inaktive Bereiche von AText mit den Symbolen ADefines wie im Editor-Baum (#845); leer ohne
    /// bedingte Zweige.</summary>
    class function InactiveOf(const AText: string; const ADefines: TArray<string>): TArray<TLspInactiveRegion>;
      static;
    /// <summary>Liegt APosition in einem der Bereiche? ACondition: Bedingung des Zweigs.</summary>
    class function RegionAt(const AInactive: TArray<TLspInactiveRegion>; const APosition: TTextPosition;
      out ACondition: string): Boolean; static;
    property Settings: TReferenceSettings read FSettings;
  end;

implementation

uses
  Atlas.Common.Index.Files,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Lsp.Implementations;

const
  /// <summary>Mitglieder, die über ein Interface oder eine überschriebene Methode erreicht werden.</summary>
  MemberKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Property_];
  ClassKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType];
  ReasonNames: array[TReferenceReason] of string = ('', 'interface', 'virtual', 'ambiguous', 'unresolved',
    'inactiveBranch', 'text');

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
    Result := Copy(AText, 2, MaxInt)
  else
    Result := AText;
end;

function SameTarget(const A, B: TDefinitionTarget): Boolean;
begin
  Result := SameText(A.FileName, B.FileName) and (A.SelectionRange.StartPos = B.SelectionRange.StartPos);
end;

/// <summary>Bedeutsamer Token vor AIndex (ohne Kommentare und Direktiven); -1 am Anfang.</summary>
function PreviousToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and (ATokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Dec(Result);
end;

/// <summary>Name im Kopf einer Routine: procedure Name, procedure TTyp.Name, constructor TA.TB.Create.</summary>
function InRoutineHeader(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  Index: Integer;
begin
  Index := PreviousToken(ATokens, AIndex);
  while (Index > 0) and (ATokens[Index].Kind = TPascalTokenKind.Symbol) and (ATokens[Index].Text = '.') and
    (ATokens[PreviousToken(ATokens, Index)].Kind = TPascalTokenKind.Identifier) do
    Index := PreviousToken(ATokens, PreviousToken(ATokens, Index));
  Result := (Index >= 0) and (ATokens[Index].Kind = TPascalTokenKind.Keyword) and
    (SameText(ATokens[Index].Text, 'procedure') or SameText(ATokens[Index].Text, 'function') or
    SameText(ATokens[Index].Text, 'constructor') or SameText(ATokens[Index].Text, 'destructor') or
    SameText(ATokens[Index].Text, 'operator'));
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

/// <summary>Letzter Teil eines qualifizierten Namens: Kunden.TKunde → TKunde.</summary>
function ShortName(const AName: string): string;
var
  Dot: Integer;
begin
  Dot := LastDelimiter('.', AName);
  Result := Copy(AName, Dot + 1, MaxInt);
end;

{ TReferenceConfidence }

class function TReferenceConfidence.Sure: TReferenceConfidence;
begin
  Result := Default(TReferenceConfidence);
  Result.Level := TReferenceLevel.Sure;
  Result.Reason := TReferenceReason.None;
  Result.Matched := True;
end;

class function TReferenceConfidence.Inferred(AReason: TReferenceReason; const ADetail: string;
  AMatched: Boolean): TReferenceConfidence;
begin
  Result.Level := TReferenceLevel.Inferred;
  Result.Reason := AReason;
  Result.Detail := ADetail;
  Result.Matched := AMatched;
end;

function TReferenceConfidence.IsSure: Boolean;
begin
  Result := Level = TReferenceLevel.Sure;
end;

function TReferenceConfidence.Renameable: Boolean;
begin
  Result := IsSure or Matched;
end;

function TReferenceConfidence.LevelName: string;
begin
  if IsSure then
    Result := 'sure'
  else
    Result := 'inferred';
end;

function TReferenceConfidence.ReasonName: string;
begin
  Result := ReasonNames[Reason];
end;

function TReferenceConfidence.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('level', LevelName);
  if not IsSure then
  begin
    Result.AddPair('reason', ReasonName);
    Result.AddPair('detail', Detail);
  end;
end;

{ TReferenceClassifier }

constructor TReferenceClassifier.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AWanted: TDefinitionTarget; const ASymbol: TIndexSymbol; AHasSymbol: Boolean; const AName: string;
  const ASettings: TReferenceSettings);
var
  Directive: string;
begin
  inherited Create;
  FResolver := AResolver;
  FIndex := AIndex;
  FWanted := AWanted;
  FSymbol := ASymbol;
  FHasSymbol := AHasSymbol;
  FOverloaded := False;
  if AHasSymbol then
    for Directive in ASymbol.Directives do
      FOverloaded := FOverloaded or SameText(Directive, 'overload');
  FName := AName;
  FSettings := ASettings;
  FDescendants := TDictionary<string, TArray<TSymbolLocation>>.Create;
end;

destructor TReferenceClassifier.Destroy;
begin
  FDescendants.Free;
  inherited Destroy;
end;

class function TReferenceClassifier.SymbolOf(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AFileName: string; const AWanted: TDefinitionTarget; out ASymbol: TIndexSymbol): Boolean;
var
  OwnerUnit: TUnitIndex;
  Symbol: TIndexSymbol;
begin
  ASymbol := Default(TIndexSymbol);
  if SameText(AWanted.FileName, AFileName) then
    OwnerUnit := AResolver.ExtractedUnit(ATree, AFileName)
  else if not TIndexFiles.UnitOf(AIndex, AWanted.FileName, OwnerUnit) then
    Exit(False);
  for Symbol in OwnerUnit.Symbols do
    if Symbol.SelectionRange.StartPos = AWanted.SelectionRange.StartPos then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
  Result := False;
end;

class function TReferenceClassifier.InactiveOf(const AText: string;
  const ADefines: TArray<string>): TArray<TLspInactiveRegion>;
var
  Issues: TArray<TPreprocessorIssue>;
begin
  Result := nil;
  if not TPascalPreprocessor.HasConditionals(AText) then
    Exit;
  // Dieselben Optionen wie der Baum des Editors, damit „inaktiv“ hier dasselbe heißt wie beim Abblenden.
  Result := TLspInactiveRegions.Regions(TPascalPreprocessor.Process(AText,
    TPascalPreprocessor.EditorOptions(ADefines)), False, Issues);
end;

class function TReferenceClassifier.RegionAt(const AInactive: TArray<TLspInactiveRegion>;
  const APosition: TTextPosition; out ACondition: string): Boolean;
var
  Region: TLspInactiveRegion;
begin
  ACondition := '';
  for Region in AInactive do
    if not Before(APosition, Region.Range.StartPos) and Before(APosition, Region.Range.EndPos) then
    begin
      ACondition := Region.Condition;
      Exit(True);
    end;
  Result := False;
end;

function InactiveDetail(const ACondition: string): string;
begin
  if ACondition = '' then
    Result := 'In einem inaktiven Zweig der bedingten Übersetzung'
  else
    Result := Format('In einem inaktiven Zweig: Bedingung %s nicht erfüllt', [ACondition]);
end;

function TReferenceClassifier.Descendants(const ATypeName: string): TArray<TSymbolLocation>;
begin
  if FDescendants.TryGetValue(UpperCase(ATypeName), Result) then
    Exit;
  Result := TLspImplementations.AllDescendantsOf(FIndex, ATypeName);
  FDescendants.Add(UpperCase(ATypeName), Result);
end;

function TReferenceClassifier.ContainerIsInterface(const AContainer: string): Boolean;
var
  Location: TSymbolLocation;
begin
  for Location in FIndex.FindSymbols(ShortName(AContainer)) do
    if (Location.Symbol.Kind = TIndexSymbolKind.InterfaceType) and
      (SameText(Location.Symbol.QualifiedName, AContainer) or SameText(Location.Symbol.Name, AContainer)) then
      Exit(True);
  Result := False;
end;

function TReferenceClassifier.InheritedCall(const AResolved: TResolvedSymbol;
  out AConfidence: TReferenceConfidence): Boolean;
var
  Location: TSymbolLocation;
  Found: Boolean;
  Classes: Integer;
begin
  Result := False;
  if not FHasSymbol or not (FSymbol.Kind in MemberKinds) or (FSymbol.Container = '') then
    Exit;
  if (AResolved.Kind <> TResolvedKind.Symbol) or (AResolved.SymbolKind <> FSymbol.Kind) or
    not SameText(AResolved.Name, FSymbol.Name) or (AResolved.Container = '') or
    SameText(AResolved.Container, FSymbol.Container) then
    Exit;
  // Die Klasse des Symbols muss vom Typ des aufgerufenen Mitglieds abstammen bzw. ihn umsetzen.
  Found := False;
  Classes := 0;
  for Location in Descendants(AResolved.Container) do
  begin
    if Location.Symbol.Kind in ClassKinds then
      Inc(Classes);
    if SameText(Location.Symbol.QualifiedName, FSymbol.Container) or
      SameText(Location.Symbol.Name, ShortName(FSymbol.Container)) then
      Found := True;
  end;
  if not Found then
    Exit;
  if ContainerIsInterface(AResolved.Container) then
  begin
    if Classes <= 1 then
      AConfidence := TReferenceConfidence.Inferred(TReferenceReason.Interface_,
        Format('Aufruf über %s.%s; %s ist die einzige Umsetzung', [AResolved.Container, AResolved.Name,
        FSymbol.Container]), False)
    else
      AConfidence := TReferenceConfidence.Inferred(TReferenceReason.Interface_,
        Format('Aufruf über %s.%s; %s ist eine von %d Umsetzungen', [AResolved.Container, AResolved.Name,
        FSymbol.Container, Classes]), False);
    Exit(True);
  end;
  // Statische Methoden gleichen Namens verdecken nur; erreicht wird das Symbol nur über virtual.
  if not AResolved.IsVirtual then
    Exit;
  AConfidence := TReferenceConfidence.Inferred(TReferenceReason.Virtual,
    Format('Aufruf von %s.%s; %s.%s überschreibt sie', [AResolved.Container, AResolved.Name, FSymbol.Container,
    FSymbol.Name]), False);
  Result := True;
end;

function TReferenceClassifier.Ambiguous(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; AMatched: Boolean; out AConfidence: TReferenceConfidence): Boolean;
var
  All: TArray<TResolvedSymbol>;
  Candidate: TResolvedSymbol;
  Targets: TArray<TDefinitionTarget>;
begin
  Result := False;
  All := FResolver.ResolveAll(ATree, AFileName, APosition);
  if Length(All) < 2 then
    Exit;
  if AMatched then
  begin
    AConfidence := TReferenceConfidence.Inferred(TReferenceReason.Ambiguous,
      Format('Überladung nicht eindeutig: %d Kandidaten, gewählt wurde dieses Symbol', [Length(All)]), True);
    Exit(True);
  end;
  for Candidate in All do
  begin
    Targets := TLspDefinition.TargetsOf(FResolver, FIndex, ATree, AFileName, APosition, Candidate, True);
    if (Length(Targets) > 0) and SameTarget(Targets[0], FWanted) then
    begin
      AConfidence := TReferenceConfidence.Inferred(TReferenceReason.Ambiguous,
        Format('Überladung nicht eindeutig: %d Kandidaten, darunter dieses Symbol', [Length(All)]), False);
      Exit(True);
    end;
  end;
end;

function TReferenceClassifier.Classify(ATree: TSyntaxTree; const AFileName: string; ATokenIndex: Integer;
  const AInactive: TArray<TLspInactiveRegion>; out AConfidence: TReferenceConfidence): Boolean;
var
  Position: TTextPosition;
  Resolved: TResolvedSymbol;
  Targets: TArray<TDefinitionTarget>;
  Inactive: Boolean;
  Condition: string;
begin
  Position := ATree.Tokens[ATokenIndex].StartPos;
  Inactive := FSettings.Inferred and RegionAt(AInactive, Position, Condition);
  Resolved := FResolver.Resolve(ATree, AFileName, Position);
  Targets := TLspDefinition.TargetsOf(FResolver, FIndex, ATree, AFileName, Position, Resolved, True);
  if (Length(Targets) > 0) and SameTarget(Targets[0], FWanted) then
  begin
    if Inactive then
      AConfidence := TReferenceConfidence.Inferred(TReferenceReason.InactiveBranch, InactiveDetail(Condition), True)
    // ResolveAll nur bei Aufrufen von Überladungen: Sonst gibt es keinen zweiten Kandidaten.
    else if not (FSettings.Inferred and FOverloaded and not InRoutineHeader(ATree.Tokens, ATokenIndex) and
      Ambiguous(ATree, AFileName, Position, True, AConfidence)) then
      AConfidence := TReferenceConfidence.Sure;
    Exit(True);
  end;
  // Erschlossen nur bei genau dem Namen, nicht bei der anderen Schreibweise eines Attributs; Köpfe anderer
  // Routinen gleichen Namens deklarieren nur.
  if not FSettings.Inferred or not SameText(CleanName(ATree.Tokens[ATokenIndex].Text), FName) or
    InRoutineHeader(ATree.Tokens, ATokenIndex) then
    Exit(False);
  if Inactive then
  begin
    AConfidence := TReferenceConfidence.Inferred(TReferenceReason.InactiveBranch, InactiveDetail(Condition), False);
    Exit(True);
  end;
  if Length(Targets) = 0 then
  begin
    AConfidence := TReferenceConfidence.Inferred(TReferenceReason.Unresolved,
      'Gleicher Name, Typ nicht bestimmbar (with oder Ausdruck mit unbekanntem Typ)', False);
    Exit(True);
  end;
  Result := Ambiguous(ATree, AFileName, Position, False, AConfidence) or InheritedCall(Resolved, AConfidence);
end;

function TReferenceClassifier.TextMatch(const AToken: TPascalToken; out AConfidence: TReferenceConfidence): Boolean;
begin
  Result := FSettings.Inferred and FSettings.TextMatches and (AToken.Kind = TPascalTokenKind.StringLiteral) and
    SameText(AToken.Text, '''' + FName + '''');
  if Result then
    AConfidence := TReferenceConfidence.Inferred(TReferenceReason.Text,
      Format('Name im String-Literal %s (etwa für RTTI oder MethodAddress)', [AToken.Text]), False);
end;

end.
