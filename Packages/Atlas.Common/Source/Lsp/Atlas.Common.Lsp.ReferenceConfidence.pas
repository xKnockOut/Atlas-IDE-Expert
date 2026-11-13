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
    /// <summary>Gründe interface und virtual: Umsetzungen, die der Aufruf erreichen kann (#1122); sonst 0.</summary>
    Implementations: Integer;
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
    /// <summary>Kennzeichen eines Grundes wie ReasonName (auch für atlasDispatch, #1122).</summary>
    class function NameOfReason(AReason: TReferenceReason): string; static;
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
    /// <summary>Ist AResolved dasselbe Mitglied wie das Symbol, aber in einem anderen Typ?</summary>
    function SameMemberElsewhere(const AResolved: TResolvedSymbol): Boolean;
    /// <summary>Stammt die Klasse des Symbols von AContainer ab bzw. setzt sie ihn um? AClasses: Klassen unter den
    /// Nachfahren.</summary>
    function DescendsFrom(const AContainer: string; out AClasses: Integer): Boolean;
    function InterfaceConfidence(const AResolved: TResolvedSymbol; AClasses: Integer): TReferenceConfidence;
    function VirtualConfidence(const AResolved: TResolvedSymbol): TReferenceConfidence;
    function InheritedCall(const AResolved: TResolvedSymbol; out AConfidence: TReferenceConfidence): Boolean;
    procedure Init(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AWanted: TDefinitionTarget;
      const AName: string; const ASettings: TReferenceSettings);
    function Ambiguous(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
      AMatched: Boolean; out AConfidence: TReferenceConfidence): Boolean;
  public
    /// <summary>AName ohne &amp;; ASymbol ist die Deklaration hinter AWanted.</summary>
    constructor Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AWanted: TDefinitionTarget;
      const ASymbol: TIndexSymbol; const AName: string; const ASettings: TReferenceSettings); overload;
    /// <summary>Wie oben ohne Deklaration (fehlt im Index): dann keine Gründe interface und virtual.</summary>
    constructor Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AWanted: TDefinitionTarget;
      const AName: string; const ASettings: TReferenceSettings); overload;
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
    property Resolver: TNameResolver read FResolver;
  end;

implementation

uses
  Atlas.Common.Index.Files,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Lsp.Implementations,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Pascal.TokenCursor;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TReferenceConfidenceText = (InAnInactiveBranchOf, InAnInactiveBranchCondition, CallViaIsTheOnly, CallViaIsOneOf,
    CallOfOverridesIt, OverloadNotUniqueCandidatesThis, OverloadNotUniqueCandidatesAmong, SameNameTypeCannotBe,
    NameInTheStringLiteral);

const
  cTexts: array[TReferenceConfidenceText] of TAtlasText = (
    (De: 'In einem inaktiven Zweig der bedingten Übersetzung';
     En: 'In an inactive branch of conditional compilation'),
    (De: 'In einem inaktiven Zweig: Bedingung %s nicht erfüllt'; En: 'In an inactive branch: condition %s not met'),
    (De: 'Aufruf über %s.%s; %s ist die einzige Umsetzung'; En: 'Call via %s.%s; %s is the only implementation'),
    (De: 'Aufruf über %s.%s; %s ist eine von %d Umsetzungen'; En: 'Call via %s.%s; %s is one of %d implementations'),
    (De: 'Aufruf von %s.%s; %s.%s überschreibt sie'; En: 'Call of %s.%s; %s.%s overrides it'),
    (De: 'Überladung nicht eindeutig: %d Kandidaten, gewählt wurde dieses Symbol';
     En: 'Overload not unique: %d candidates, this symbol was chosen'),
    (De: 'Überladung nicht eindeutig: %d Kandidaten, darunter dieses Symbol';
     En: 'Overload not unique: %d candidates, among them this symbol'),
    (De: 'Gleicher Name, Typ nicht bestimmbar (with oder Ausdruck mit unbekanntem Typ)';
     En: 'Same name, type cannot be determined (with or expression of unknown type)'),
    (De: 'Name im String-Literal %s (etwa für RTTI oder MethodAddress)';
     En: 'Name in the string literal %s (e.g. for RTTI or MethodAddress)'));

{$SCOPEDENUMS OFF}

const
  /// <summary>Mitglieder, die über ein Interface oder eine überschriebene Methode erreicht werden.</summary>
  cMemberKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Property_];
  cClassKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType];
  cReasonNames: array[TReferenceReason] of string = ('', 'interface', 'virtual', 'ambiguous', 'unresolved',
    'inactiveBranch', 'text');

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
  begin
    Result := Copy(AText, 2, MaxInt);
  end
  else
  begin
    Result := AText;
  end;
end;

function SameTarget(const A, B: TDefinitionTarget): Boolean;
begin
  Result := SameText(A.FileName, B.FileName) and (A.SelectionRange.StartPos = B.SelectionRange.StartPos);
end;

/// <summary>Name im Kopf einer Routine: procedure Name, procedure TTyp.Name, constructor TA.TB.Create.</summary>
function InRoutineHeader(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := PreviousCode(ATokens, AIndex);
  while (mIndex > 0) and (ATokens[mIndex].Kind = TPascalTokenKind.Symbol) and (ATokens[mIndex].Text = '.') and
    (ATokens[PreviousCode(ATokens, mIndex)].Kind = TPascalTokenKind.Identifier) do
  begin
    mIndex := PreviousCode(ATokens, PreviousCode(ATokens, mIndex));
  end;
  Result := (mIndex >= 0) and (ATokens[mIndex].Kind = TPascalTokenKind.Keyword) and
    (SameText(ATokens[mIndex].Text, 'procedure') or SameText(ATokens[mIndex].Text, 'function') or
    SameText(ATokens[mIndex].Text, 'constructor') or SameText(ATokens[mIndex].Text, 'destructor') or
    SameText(ATokens[mIndex].Text, 'operator'));
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

/// <summary>Letzter Teil eines qualifizierten Namens: Kunden.TKunde → TKunde.</summary>
function ShortName(const AName: string): string;
var
  mDot: Integer;
begin
  mDot := LastDelimiter('.', AName);
  Result := Copy(AName, mDot + 1, MaxInt);
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
  Result := Default(TReferenceConfidence);
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
  begin
    Result := 'sure';
  end
  else
  begin
    Result := 'inferred';
  end;
end;

function TReferenceConfidence.ReasonName: string;
begin
  Result := cReasonNames[Reason];
end;

class function TReferenceConfidence.NameOfReason(AReason: TReferenceReason): string;
begin
  Result := cReasonNames[AReason];
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

procedure TReferenceClassifier.Init(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AWanted: TDefinitionTarget; const AName: string; const ASettings: TReferenceSettings);
begin
  FResolver := AResolver;
  FIndex := AIndex;
  FWanted := AWanted;
  FName := AName;
  FSettings := ASettings;
  FDescendants := TDictionary<string, TArray<TSymbolLocation>>.Create;
end;

constructor TReferenceClassifier.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AWanted: TDefinitionTarget; const ASymbol: TIndexSymbol; const AName: string;
  const ASettings: TReferenceSettings);
var
  mDirective: string;
begin
  inherited Create;
  Init(AResolver, AIndex, AWanted, AName, ASettings);
  FSymbol := ASymbol;
  FHasSymbol := True;
  FOverloaded := False;
  for mDirective in ASymbol.Directives do
  begin
    FOverloaded := FOverloaded or SameText(mDirective, 'overload');
  end;
end;

constructor TReferenceClassifier.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AWanted: TDefinitionTarget; const AName: string; const ASettings: TReferenceSettings);
begin
  inherited Create;
  Init(AResolver, AIndex, AWanted, AName, ASettings);
  FSymbol := Default(TIndexSymbol);
  FHasSymbol := False;
  FOverloaded := False;
end;

destructor TReferenceClassifier.Destroy;
begin
  FDescendants.Free;
  inherited Destroy;
end;

class function TReferenceClassifier.SymbolOf(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AFileName: string; const AWanted: TDefinitionTarget; out ASymbol: TIndexSymbol): Boolean;
var
  mOwnerUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  ASymbol := Default(TIndexSymbol);
  if SameText(AWanted.FileName, AFileName) then
  begin
    mOwnerUnit := AResolver.ExtractedUnit(ATree, AFileName);
  end
  else if not TIndexFiles.UnitOf(AIndex, AWanted.FileName, mOwnerUnit) then
  begin
    Exit(False);
  end;
  for mSymbol in mOwnerUnit.Symbols do
  begin
    if mSymbol.SelectionRange.StartPos = AWanted.SelectionRange.StartPos then
    begin
      ASymbol := mSymbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TReferenceClassifier.InactiveOf(const AText: string;
  const ADefines: TArray<string>): TArray<TLspInactiveRegion>;
var
  mIssues: TArray<TPreprocessorIssue>;
begin
  Result := nil;
  if not TPascalPreprocessor.HasConditionals(AText) then
  begin
    Exit;
  end;
  // Dieselben Optionen wie der Baum des Editors, damit „inaktiv“ hier dasselbe heißt wie beim Abblenden.
  Result := TLspInactiveRegions.Regions(TPascalPreprocessor.Process(AText,
    TPascalPreprocessor.EditorOptions(ADefines)), False, mIssues);
end;

class function TReferenceClassifier.RegionAt(const AInactive: TArray<TLspInactiveRegion>;
  const APosition: TTextPosition; out ACondition: string): Boolean;
var
  mRegion: TLspInactiveRegion;
begin
  ACondition := '';
  for mRegion in AInactive do
  begin
    if not Before(APosition, mRegion.Range.StartPos) and Before(APosition, mRegion.Range.EndPos) then
    begin
      ACondition := mRegion.Condition;
      Exit(True);
    end;
  end;
  Result := False;
end;

function InactiveDetail(const ACondition: string): string;
begin
  if ACondition = '' then
  begin
    Result := cTexts[TReferenceConfidenceText.InAnInactiveBranchOf].Text;
  end
  else
  begin
    Result := cTexts[TReferenceConfidenceText.InAnInactiveBranchCondition].Fmt([ACondition]);
  end;
end;

function TReferenceClassifier.Descendants(const ATypeName: string): TArray<TSymbolLocation>;
begin
  if FDescendants.TryGetValue(UpperCase(ATypeName), Result) then
  begin
    Exit;
  end;
  Result := TLspImplementations.AllDescendantsOf(FIndex, ATypeName);
  FDescendants.Add(UpperCase(ATypeName), Result);
end;

function TReferenceClassifier.ContainerIsInterface(const AContainer: string): Boolean;
begin
  Result := TLspImplementations.IsInterfaceType(FIndex, AContainer);
end;

function TReferenceClassifier.SameMemberElsewhere(const AResolved: TResolvedSymbol): Boolean;
begin
  Result := FHasSymbol and (FSymbol.Kind in cMemberKinds) and (FSymbol.Container <> '');
  if Result then
  begin
    Result := (AResolved.Kind = TResolvedKind.Symbol) and (AResolved.SymbolKind = FSymbol.Kind) and
      SameText(AResolved.Name, FSymbol.Name) and (AResolved.Container <> '') and
      not SameText(AResolved.Container, FSymbol.Container);
  end;
end;

function TReferenceClassifier.DescendsFrom(const AContainer: string; out AClasses: Integer): Boolean;
var
  mLocation: TSymbolLocation;
begin
  Result := False;
  AClasses := 0;
  for mLocation in Descendants(AContainer) do
  begin
    if mLocation.Symbol.Kind in cClassKinds then
    begin
      Inc(AClasses);
    end;
    if SameText(mLocation.Symbol.QualifiedName, FSymbol.Container) or
      SameText(mLocation.Symbol.Name, ShortName(FSymbol.Container)) then
    begin
      Result := True;
    end;
  end;
end;

function TReferenceClassifier.InterfaceConfidence(const AResolved: TResolvedSymbol;
  AClasses: Integer): TReferenceConfidence;
begin
  if AClasses <= 1 then
  begin
    Result := TReferenceConfidence.Inferred(TReferenceReason.Interface_,
      cTexts[TReferenceConfidenceText.CallViaIsTheOnly].Fmt([AResolved.Container, AResolved.Name,
      FSymbol.Container]), False);
  end
  else
  begin
    Result := TReferenceConfidence.Inferred(TReferenceReason.Interface_,
      cTexts[TReferenceConfidenceText.CallViaIsOneOf].Fmt([AResolved.Container, AResolved.Name,
      FSymbol.Container, AClasses]), False);
  end;
  Result.Implementations := AClasses;
end;

function TReferenceClassifier.VirtualConfidence(const AResolved: TResolvedSymbol): TReferenceConfidence;
begin
  Result := TReferenceConfidence.Inferred(TReferenceReason.Virtual,
    cTexts[TReferenceConfidenceText.CallOfOverridesIt].Fmt([AResolved.Container, AResolved.Name, FSymbol.Container,
    FSymbol.Name]), False);
  Result.Implementations := TLspImplementations.ImplementationCount(FIndex, AResolved.Container, AResolved.Name,
    False);
end;

function TReferenceClassifier.InheritedCall(const AResolved: TResolvedSymbol;
  out AConfidence: TReferenceConfidence): Boolean;
var
  mClasses: Integer;
begin
  // Die Klasse des Symbols muss vom Typ des aufgerufenen Mitglieds abstammen bzw. ihn umsetzen.
  Result := SameMemberElsewhere(AResolved) and DescendsFrom(AResolved.Container, mClasses);
  if not Result then
  begin
    Exit;
  end;
  if ContainerIsInterface(AResolved.Container) then
  begin
    AConfidence := InterfaceConfidence(AResolved, mClasses);
  end
  else if AResolved.IsVirtual then
  begin
    AConfidence := VirtualConfidence(AResolved);
  end
  else
  begin
    // Statische Methoden gleichen Namens verdecken nur; erreicht wird das Symbol nur über virtual.
    Result := False;
  end;
end;

function TReferenceClassifier.Ambiguous(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; AMatched: Boolean; out AConfidence: TReferenceConfidence): Boolean;
var
  mAll: TArray<TResolvedSymbol>;
  mCandidate: TResolvedSymbol;
  mTargets: TArray<TDefinitionTarget>;
begin
  Result := False;
  mAll := FResolver.ResolveAll(ATree, AFileName, APosition);
  if Length(mAll) < 2 then
  begin
    Exit;
  end;
  if AMatched then
  begin
    AConfidence := TReferenceConfidence.Inferred(TReferenceReason.Ambiguous,
      cTexts[TReferenceConfidenceText.OverloadNotUniqueCandidatesThis].Fmt([Length(mAll)]), True);
    Exit(True);
  end;
  for mCandidate in mAll do
  begin
    mTargets := TLspDefinition.TargetsOf(FResolver, FIndex, TDefinitionQuery.Create(ATree, AFileName, APosition, True),
      mCandidate);
    if (Length(mTargets) > 0) and SameTarget(mTargets[0], FWanted) then
    begin
      AConfidence := TReferenceConfidence.Inferred(TReferenceReason.Ambiguous,
        cTexts[TReferenceConfidenceText.OverloadNotUniqueCandidatesAmong].Fmt([Length(mAll)]), False);
      Exit(True);
    end;
  end;
end;

function TReferenceClassifier.Classify(ATree: TSyntaxTree; const AFileName: string; ATokenIndex: Integer;
  const AInactive: TArray<TLspInactiveRegion>; out AConfidence: TReferenceConfidence): Boolean;
var
  mPosition: TTextPosition;
  mResolved: TResolvedSymbol;
  mTargets: TArray<TDefinitionTarget>;
  mInactive: Boolean;
  mCondition: string;
begin
  mPosition := ATree.Tokens[ATokenIndex].StartPos;
  mInactive := FSettings.Inferred and RegionAt(AInactive, mPosition, mCondition);
  mResolved := FResolver.Resolve(ATree, AFileName, mPosition);
  mTargets := TLspDefinition.TargetsOf(FResolver, FIndex, TDefinitionQuery.Create(ATree, AFileName, mPosition, True),
    mResolved);
  if (Length(mTargets) > 0) and SameTarget(mTargets[0], FWanted) then
  begin
    if mInactive then
    begin
      AConfidence := TReferenceConfidence.Inferred(TReferenceReason.InactiveBranch, InactiveDetail(mCondition), True);
    end
    // ResolveAll nur bei Aufrufen von Überladungen: Sonst gibt es keinen zweiten Kandidaten.
    else if not (FSettings.Inferred and FOverloaded and not InRoutineHeader(ATree.Tokens, ATokenIndex) and
      Ambiguous(ATree, AFileName, mPosition, True, AConfidence)) then
    begin
      AConfidence := TReferenceConfidence.Sure;
    end;
    Exit(True);
  end;
  // Erschlossen nur bei genau dem Namen, nicht bei der anderen Schreibweise eines Attributs; Köpfe anderer
  // Routinen gleichen Namens deklarieren nur.
  if not FSettings.Inferred or not SameText(CleanName(ATree.Tokens[ATokenIndex].Text), FName) or
    InRoutineHeader(ATree.Tokens, ATokenIndex) then
  begin
    Exit(False);
  end;
  if mInactive then
  begin
    AConfidence := TReferenceConfidence.Inferred(TReferenceReason.InactiveBranch, InactiveDetail(mCondition), False);
    Exit(True);
  end;
  if Length(mTargets) = 0 then
  begin
    AConfidence := TReferenceConfidence.Inferred(TReferenceReason.Unresolved,
      cTexts[TReferenceConfidenceText.SameNameTypeCannotBe].Text, False);
    Exit(True);
  end;
  Result := Ambiguous(ATree, AFileName, mPosition, False, AConfidence) or InheritedCall(mResolved, AConfidence);
end;

function TReferenceClassifier.TextMatch(const AToken: TPascalToken; out AConfidence: TReferenceConfidence): Boolean;
begin
  Result := FSettings.Inferred and FSettings.TextMatches and (AToken.Kind = TPascalTokenKind.StringLiteral) and
    SameText(AToken.Text, '''' + FName + '''');
  if Result then
  begin
    AConfidence := TReferenceConfidence.Inferred(TReferenceReason.Text,
      cTexts[TReferenceConfidenceText.NameInTheStringLiteral].Fmt([AToken.Text]), False);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.ReferenceConfidence', cTexts);

end.
