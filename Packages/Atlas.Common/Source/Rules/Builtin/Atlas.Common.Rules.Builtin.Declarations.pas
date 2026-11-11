unit Atlas.Common.Rules.Builtin.Declarations;

// Deklaration und Rumpf passen nicht zusammen (#124):
//   declared-not-implemented   Methode im Typ ohne Rumpf (sonst erst E2065)
//   implemented-not-declared   Rumpf TFoo.Bar ohne Deklaration im Typ
//   signature-mismatch         Rumpf und Deklaration gleichen Namens mit
//                              abweichendem Kopf (#996, wie E2037): Parameter
//                              (Anzahl, Name, Typ, const/var/out), Ergebnistyp,
//                              procedure/function, Aufrufkonvention; ebenso
//                              eine Routine im interface-Teil und ihr Rumpf
//                              (#1380, Cm.E2037), wenn der Name eindeutig ist,
//                              ohne overload und external, und der Rumpf nicht
//                              die Kurzform ohne Parameter und Ergebnis hat
//   interface-not-implemented  Klasse nennt ein Interface, dem Methoden fehlen
//   field-after-method         Feld nach Methode oder Property im selben
//                              Abschnitt (#986, wie E2169); Korrektur:
//                              Feld an den Anfang verschieben oder var davor
//   overload-directive-missing Gleichnamige Routinen bzw. Methoden eines
//                              Bereichs ohne overload (#987, wie E2254,
//                              E2267) oder mit gleichen Parametern (E2252,
//                              E2301); Korrektur: overload; anhängen
//   duplicate-declaration      Bezeichner im selben Bereich zweimal deklariert
//                              (#988, wie E2004): Parameter und lokale
//                              Deklarationen, Mitglieder eines Typs, die Unit
//                              über interface und implementation, uses
//                              (#1000, wie E2291), bzw. Zuordnung IFoo.Bar = Baz
//                              für ein nicht genanntes Interface (wie E2265).
//                              Geerbte Methoden, Zuordnungen und implements
//                              zählen; bricht die Kette der Vorfahrklassen ab,
//                              bleibt die Regel still (TNameResolver.Queries.
//                              MissingInterfaceMembers mit AComplete)
//   variant-record-managed-field
//                              Verwalteter Typ im varianten Teil eines Records
//                              (#1071): String, dynamisches Array, Interface,
//                              Variant oder Record mit solchen Feldern (wie
//                              E2154), verwalteter Record mit class operator
//                              Initialize/Finalize (wie E2418), Typparameter
//                              ohne Einschränkung (wie E2569); ebenso hinter
//                              file of (wie E2155, E2417). Typen über Datei und
//                              Index (Rules.ManagedTypes), unbekannte bleiben
//                              still. Korrekturen: Feld in den festen Teil vor
//                              case, ShortString, record-Einschränkung
//   type-too-large             Statisches Array oder Record ab 2 GB (#1083, wie
//                              E2100), Instanz eines generischen Typs der Datei
//                              ab 2 GB (wie E2543). Die Größe ist eine untere
//                              Grenze aus den Deklarationen (Grenzen über
//                              Semantics.OrdinalConstants, Konstanten und
//                              Aufzählungen der Datei, Records aus dem Index);
//                              Unbekanntes zählt 0. Gemeldet wird nur der
//                              innerste Typ, der die Grenze überschreitet.
//                              E2419 (1 MB) gilt nur für Delphi für .NET.
//   default-parameter          Parameter mit Vorgabewert (#976, Standard aus);
//                              Korrektur: je weggelassenem Standardparameter
//                              eine Überladung, die mit dem Vorgabewert
//                              weiterreicht
//
// Den Abgleich (auch über Überladungen) liefert TClassCompletion.Unmatched aus
// #42; Paare mit abweichendem Kopf ordnet TClassCompletion.Pairs zu. Sie meldet
// nur signature-mismatch, die beiden anderen Regeln finden fehlende Namen. Abstrakte, externe und forward-Methoden,
// Interfaces und generische
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
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Semantics.TypeIdentity,
  Atlas.Common.Rules.Builtin.Declarations.Overloads,
  Atlas.Common.Rules.Builtin.Declarations.Duplicates,
  Atlas.Common.Rules.Builtin.Declarations.TypeSizes,
  Atlas.Common.Rules.Builtin.Declarations.VariantRecords,
  Atlas.Common.Rules.Builtin.Declarations.Defaults;

type
  /// <summary>Vergleicht den Typ ADeclType der Deklaration mit dem Typ ABodyType des Rumpfs (#1324).</summary>
  TSignatureTypeMatch = reference to function(const ADeclType, ABodyType: string): TTypeMatch;

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
    /// "Datum TDateTime statt TDate"; leer, wenn die Köpfe gleich sind. Typen vergleicht TTypeIdentity.Same.
    /// </summary>
    class function Differences(const ADeclaration, ABody: TSignatureShape): TArray<string>; overload; static;
    /// <summary>Wie oben; Typen vergleicht AMatch (#1324). Nur sicher verschiedene Typen zählen als Abweichung.
    /// </summary>
    class function Differences(const ADeclaration, ABody: TSignatureShape;
      const AMatch: TSignatureTypeMatch): TArray<string>; overload; static;
  end;

  TFieldAfterMethodRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Declarations.Overloads.</summary>
  TOverloadDirectiveMissingRule = Atlas.Common.Rules.Builtin.Declarations.Overloads.TOverloadDirectiveMissingRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Declarations.Duplicates.</summary>
  TDuplicateDeclarationRule = Atlas.Common.Rules.Builtin.Declarations.Duplicates.TDuplicateDeclarationRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Declarations.TypeSizes.</summary>
  TTypeTooLargeRule = Atlas.Common.Rules.Builtin.Declarations.TypeSizes.TTypeTooLargeRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Declarations.VariantRecords.</summary>
  TVariantRecordManagedFieldRule =
    Atlas.Common.Rules.Builtin.Declarations.VariantRecords.TVariantRecordManagedFieldRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Declarations.Defaults.</summary>
  TDefaultParameterRule = Atlas.Common.Rules.Builtin.Declarations.Defaults.TDefaultParameterRule;

const
  cFieldAfterMethodRuleId = 'field-after-method';
  cDuplicateDeclarationRuleId = Atlas.Common.Rules.Builtin.Declarations.Duplicates.cDuplicateDeclarationRuleId;
  cOverloadDirectiveMissingRuleId = Atlas.Common.Rules.Builtin.Declarations.Overloads.cOverloadDirectiveMissingRuleId;

procedure RegisterDeclarationRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Rules.Builtin.Declarations.Shared,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDeclarationsText = (NotImplementedTitle, NotImplemented, NoDeclTitle, AddDeclaration, NoDecl, InterfaceTitle,
    Differs, MissingOne, MissingMany, NotInList, MismatchTitle, WithoutModifier, WithModifier, InsteadOf,
    NoTypeInstead, InsteadOfNoType, Instead, ParamCount, ResultInstead, DiffersFrom, FieldTitle, MoveField, InsertVar,
    FieldAfter);

const
  cTexts: array[TDeclarationsText] of TAtlasText = (
    (De: 'Methode ist deklariert, aber nicht implementiert'; En: 'Method is declared but not implemented'),
    (De: '"%s.%s" ist deklariert, aber nicht implementiert'; En: '"%s.%s" is declared but not implemented'),
    (De: 'Methodenrumpf ohne Deklaration im Typ'; En: 'Method body without declaration in the type'),
    (De: 'Deklaration von %s in %s ergänzen'; En: 'Add declaration of %s to %s'),
    (De: '"%s.%s" hat keine passende Deklaration in %s'; En: '"%s.%s" has no matching declaration in %s'),
    (De: 'Interface-Methode fehlt in der Klasse (wie E2291)'; En: 'Interface method missing in the class (like E2291)'),
    (De: '%s weicht von der Deklaration in %s ab (wie E2211).';
     En: '%s differs from the declaration in %s (like E2211).'),
    (De: '%s fehlt in %s (wie E2291).'; En: '%s is missing in %s (like E2291).'),
    (De: '%s fehlen in %s (wie E2291).'; En: '%s are missing in %s (like E2291).'),
    (De: '%s steht nicht in der Interface-Liste von %s (wie E2265).';
     En: '%s is not in the interface list of %s (like E2265).'),
    (De: 'Implementierung weicht von der Deklaration ab (wie E2037)';
     En: 'Implementation differs from the declaration (like E2037)'),
    (De: '%s ohne %s'; En: '%s without %s'),
    (De: '%s mit %s'; En: '%s with %s'),
    (De: '%s %s statt %s'; En: '%s %s instead of %s'),
    (De: '%s ohne Typ statt %s'; En: '%s without type instead of %s'),
    (De: '%s %s statt ohne Typ'; En: '%s %s instead of without type'),
    (De: '%s statt %s'; En: '%s instead of %s'),
    (De: '%d statt %d Parameter'; En: '%d instead of %d parameters'),
    (De: 'Ergebnis %s statt %s'; En: 'result %s instead of %s'),
    (De: '%s weicht von der Deklaration ab: %s (wie E2037).'; En: '%s differs from the declaration: %s (like E2037).'),
    (De: 'Feld nach Methoden im selben Abschnitt'; En: 'Field after methods in the same section'),
    (De: 'Feld an den Anfang des Abschnitts verschieben'; En: 'Move field to the start of the section'),
    (De: 'var davor setzen'; En: 'Put var before it'),
    (De: 'Feld nach Methoden im selben Abschnitt (wie E2169).';
     En: 'Field after methods in the same section (like E2169).'));

{$SCOPEDENUMS OFF}

/// <summary>Beginnt die Direktive AText (groß geschrieben) einen {$IF…}-Block?</summary>
function IsIfStart(const AText: string): Boolean;
begin
  Result := StartsStr('{$IF', AText) or StartsStr('(*$IF', AText);
end;

/// <summary>Beendet die Direktive AText (groß geschrieben) einen {$IF…}-Block?</summary>
function IsIfEnd(const AText: string): Boolean;
begin
  Result := StartsStr('{$ENDIF', AText) or StartsStr('{$IFEND', AText) or StartsStr('(*$ENDIF', AText) or
    StartsStr('(*$IFEND', AText);
end;

/// <summary>Markiert die Zeilen AFrom bis ATo.</summary>
procedure MarkLines(var ALines: TArray<Boolean>; AFrom, ATo: Integer);
var
  mLine: Integer;
begin
  for mLine := AFrom to ATo do
  begin
    ALines[mLine] := True;
  end;
end;

/// <summary>Zeilen innerhalb von {$IF…}…{$ENDIF}: Element I gilt für Zeile I.</summary>
function ConditionalLines(const AContext: TRuleContext): TArray<Boolean>;
var
  mToken: TPascalToken;
  mText: string;
  mDepth, mLastLine, mStartLine: Integer;
begin
  mLastLine := 0;
  for mToken in AContext.Tree.Tokens do
  begin
    mLastLine := mToken.EndPos.Line;
  end;
  SetLength(Result, mLastLine + 1);
  mDepth := 0;
  mStartLine := 0;
  for mToken in AContext.Tree.Tokens do
  begin
    if mToken.Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    mText := UpperCase(mToken.Text);
    if IsIfStart(mText) then
    begin
      if mDepth = 0 then
      begin
        mStartLine := mToken.StartPos.Line;
      end;
      Inc(mDepth);
    end
    else if (mDepth > 0) and IsIfEnd(mText) then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        MarkLines(Result, mStartLine, mToken.EndPos.Line);
      end;
    end;
  end;
  // Nicht geschlossener Block: bis zum Dateiende.
  if mDepth > 0 then
  begin
    MarkLines(Result, mStartLine, mLastLine);
  end;
end;

/// <summary>Bindet die Datei Include-Dateien ein ({$I datei} oder {$INCLUDE datei})?</summary>
function HasIncludes(const AContext: TRuleContext): Boolean;
var
  mToken: TPascalToken;
  mText: string;
begin
  for mToken in AContext.Tree.Tokens do
  begin
    if mToken.Kind = TPascalTokenKind.Directive then
    begin
      mText := UpperCase(mToken.Text);
      // {$I+} und {$I-} schalten die E/A-Prüfung um und sind keine Includes.
      if StartsStr('{$INCLUDE ', mText) or StartsStr('{$I ', mText) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function IsConditional(const ALines: TArray<Boolean>; const AMethod: TUnmatchedMethod): Boolean;
var
  mLine: Integer;
begin
  mLine := AMethod.Symbol.Range.StartPos.Line;
  Result := (mLine >= 0) and (mLine <= High(ALines)) and ALines[mLine];
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
  mPair: TSignaturePair;
begin
  for mPair in APairs do
  begin
    if (mPair.Declaration.Symbol.SelectionRange.StartPos = AMethod.Symbol.SelectionRange.StartPos) or
      (mPair.Body.Symbol.SelectionRange.StartPos = AMethod.Symbol.SelectionRange.StartPos) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function Confidence(const AContext: TRuleContext): TRuleConfidence;
begin
  if HasIncludes(AContext) then
  begin
    Result := TRuleConfidence.Medium;
  end
  else
  begin
    Result := TRuleConfidence.High;
  end;
end;

{ TDeclaredNotImplementedRule }

function TDeclaredNotImplementedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('declared-not-implemented', TRuleSeverity.Error,
    cTexts[TDeclarationsText.NotImplementedTitle].Text);
end;

procedure TDeclaredNotImplementedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mLines: TArray<Boolean>;
  mPairs: TArray<TSignaturePair>;
  mMethod: TUnmatchedMethod;
  mAction: TCodeAction;
  mFixes: TArray<TRuleFix>;
  mLevel: TRuleConfidence;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mLines := ConditionalLines(AContext);
  mLevel := Confidence(AContext);
  mPairs := TClassCompletion.Pairs(AContext.Tree, AContext.Text);
  for mMethod in TClassCompletion.Unmatched(AContext.Tree, AContext.Text) do
  begin
    if not mMethod.Declared or IsConditional(mLines, mMethod) or InPair(mPairs, mMethod) then
    begin
      Continue;
    end;
    mFixes := nil;
    if TClassCompletion.MissingBodies(AContext.Tree, AContext.Text, mMethod.Symbol.SelectionRange.StartPos,
      AContext.ClassCompletion, AContext.Formatting, mAction) then
    begin
      mFixes := [TRuleFix.Create(mAction.Title, mAction.Edits)];
    end;
    AReport.Add(mMethod.Symbol.SelectionRange, cTexts[TDeclarationsText.NotImplemented].Fmt(
      [mMethod.TypeName, mMethod.Symbol.Name]), mLevel, mFixes);
  end;
end;

{ TImplementedNotDeclaredRule }

function TImplementedNotDeclaredRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('implemented-not-declared', TRuleSeverity.Error,
    cTexts[TDeclarationsText.NoDeclTitle].Text);
end;

procedure TImplementedNotDeclaredRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mLines: TArray<Boolean>;
  mPairs: TArray<TSignaturePair>;
  mMethod: TUnmatchedMethod;
  mEdit: TRuleEdit;
  mFixes: TArray<TRuleFix>;
  mLevel: TRuleConfidence;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mLines := ConditionalLines(AContext);
  mLevel := Confidence(AContext);
  mPairs := TClassCompletion.Pairs(AContext.Tree, AContext.Text);
  for mMethod in TClassCompletion.Unmatched(AContext.Tree, AContext.Text) do
  begin
    if mMethod.Declared or IsConditional(mLines, mMethod) or InPair(mPairs, mMethod) then
    begin
      Continue;
    end;
    mFixes := nil;
    if TClassCompletion.AddDeclaration(AContext.Tree, AContext.Text, mMethod, mEdit) then
    begin
      mFixes := [TRuleFix.Create(cTexts[TDeclarationsText.AddDeclaration].Fmt([mMethod.Symbol.Name,
        mMethod.TypeName]), [mEdit])];
    end;
    AReport.Add(mMethod.Symbol.SelectionRange, cTexts[TDeclarationsText.NoDecl].Fmt(
      [mMethod.TypeName, mMethod.Symbol.Name, mMethod.TypeName]), mLevel, mFixes);
  end;
end;

{ TInterfaceNotImplementedRule }

function TInterfaceNotImplementedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('interface-not-implemented', TRuleSeverity.Error,
    cTexts[TDeclarationsText.InterfaceTitle].Text);
end;

/// <summary>Steht im Token AIndex ein implements innerhalb der Zeilen von ARange?</summary>
function ImplementsAt(const ATokens: TArray<TPascalToken>; AIndex: Integer; const ARange: TTextRange): Boolean;
begin
  Result := (ATokens[AIndex].StartPos.Line >= ARange.StartPos.Line) and
    (ATokens[AIndex].EndPos.Line <= ARange.EndPos.Line) and SameText(ATokens[AIndex].Text, 'implements') and
    (ATokens[AIndex].Kind = TPascalTokenKind.Identifier);
end;

/// <summary>Interfaces hinter implements im Token AIndex (implements IFoo, Units.IBar;); AIndex steht danach auf
/// dem Semikolon.</summary>
function DelegatedNames(const ATokens: TArray<TPascalToken>; var AIndex: Integer): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  Inc(AIndex);
  mName := '';
  while (AIndex <= High(ATokens)) and not ATokens[AIndex].IsSymbol(';') do
  begin
    if ATokens[AIndex].IsSymbol(',') then
    begin
      Result := Result + [mName];
      mName := '';
    end
    else if ATokens[AIndex].Kind <> TPascalTokenKind.Comment then
    begin
      mName := mName + ATokens[AIndex].Text;
    end;
    Inc(AIndex);
  end;
  if mName <> '' then
  begin
    Result := Result + [mName];
  end;
end;

class function TInterfaceNotImplementedRule.Delegated(const ATokens: TArray<TPascalToken>;
  const ARange: TTextRange): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := 0;
  while mIndex <= High(ATokens) do
  begin
    if ImplementsAt(ATokens, mIndex, ARange) then
    begin
      Result := Result + DelegatedNames(ATokens, mIndex);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Methode AName der Klasse ATypeName (ohne Zuordnungen); Name leer, wenn es keine gibt.</summary>
function OwnMethod(const AUnit: TUnitIndex; const ATypeName, AName: string): TIndexSymbol;
var
  mSymbol: TIndexSymbol;
begin
  Result := Default(TIndexSymbol);
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.Container, ATypeName) and SameText(mSymbol.Name, AName) and
      (mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) then
    begin
      Exit(mSymbol);
    end;
  end;
end;

/// <summary>Köpfe aller Methodenzuordnungen (procedure IFoo.Bar = Baz) in Typrümpfen der Datei; Anweisungen
/// werden nicht durchlaufen.</summary>
function ResolutionHeaders(ATree: TSyntaxTree): TArray<TSyntaxNode>;
var
  mFound: TList<TSyntaxNode>;
begin
  mFound := TList<TSyntaxNode>.Create;
  try
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode.Kind = TSyntaxKind.RoutineHeader) and ANode.IsMethodResolution then
        begin
          mFound.Add(ANode);
        end;
        Result := not (ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock]);
      end);
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

type
  /// <summary>interface-not-implemented für eine Datei: fehlende Interface-Methoden je Klasse und Zuordnungen
  /// (procedure IFoo.Bar = Baz) für Interfaces, die die Klasse nicht nennt.</summary>
  TInterfaceCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FLines: TArray<Boolean>;
    FLevel: TRuleConfidence;
    FResolver: TNameResolver;
    FOwnUnit: TUnitIndex;
    FHeaders: TArray<TSyntaxNode>;
    FActions: TClassActionContext;
    function IsCandidate(const AType: TIndexSymbol): Boolean;
    function MissingNames(const AMissing: TArray<TResolvedSymbol>; const ATypeName: string;
      out ADiffers: Boolean): TArray<string>;
    function InterfaceFixes(const AType: TIndexSymbol): TArray<TRuleFix>;
    procedure CheckMissing(const AType: TIndexSymbol; const ATypeName: string);
    function Listed(const AType: TIndexSymbol; const APrefix: string): Boolean;
    procedure CheckResolutions(const AType: TIndexSymbol; const ATypeName: string);
    procedure CheckType(const AType: TIndexSymbol);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport; AResolver: TNameResolver;
      const AIndex: ISymbolIndex);
    /// <summary>Prüft alle Klassen der Datei.</summary>
    procedure Run;
  end;

constructor TInterfaceCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport;
  AResolver: TNameResolver; const AIndex: ISymbolIndex);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FResolver := AResolver;
  FLines := ConditionalLines(AContext);
  FLevel := Confidence(AContext);
  FOwnUnit := AResolver.ExtractedUnit(AContext.Tree, AContext.RelativePath);
  FHeaders := ResolutionHeaders(AContext.Tree);
  FActions := TClassActionContext.Default;
  FActions.Index := AIndex;
  FActions.Namespaces := AContext.Namespaces;
  FActions.DelphiVersion := AContext.DelphiVersion;
  FActions.Style := AContext.Formatting;
end;

// Klasse mit Vorfahren außerhalb von {$IF…}-Blöcken?
function TInterfaceCheck.IsCandidate(const AType: TIndexSymbol): Boolean;
var
  mLine: Integer;
begin
  mLine := AType.SelectionRange.StartPos.Line;
  Result := (AType.Kind = TIndexSymbolKind.ClassType) and (Length(AType.Ancestors) > 0);
  Result := Result and not ((mLine <= High(FLines)) and FLines[mLine]);
end;

// Namen der fehlenden Methoden (Interface.Methode, sortiert). Gleichnamige Methode der Klasse mit anderer
// Signatur: E2211 an der Methode statt "fehlt", ADiffers.
function TInterfaceCheck.MissingNames(const AMissing: TArray<TResolvedSymbol>; const ATypeName: string;
  out ADiffers: Boolean): TArray<string>;
var
  mMember: TResolvedSymbol;
  mOwn: TIndexSymbol;
  mNames: TList<string>;
  mName: string;
begin
  ADiffers := False;
  mNames := TList<string>.Create;
  try
    for mMember in AMissing do
    begin
      mOwn := OwnMethod(FOwnUnit, ATypeName, mMember.Name);
      mName := BareName(mMember.Container) + '.' + mMember.Name;
      if mOwn.Name <> '' then
      begin
        ADiffers := True;
        FReport.Add(mOwn.SelectionRange, cTexts[TDeclarationsText.Differs].Fmt(
          [mOwn.Name, BareName(mMember.Container)]), FLevel);
      end
      else if not mNames.Contains(mName) then
      begin
        mNames.Add(mName);
      end;
    end;
    mNames.Sort;
    Result := mNames.ToArray;
  finally
    mNames.Free;
  end;
end;

// "Interface implementieren" je Vorfahr, ab dem zweiten als Alternative.
function TInterfaceCheck.InterfaceFixes(const AType: TIndexSymbol): TArray<TRuleFix>;
var
  mAncestor: string;
  mAction: TCodeAction;
begin
  Result := nil;
  for mAncestor in AType.Ancestors do
  begin
    if TClassActions.ImplementInterface(FContext.Text, AType.Range.StartPos.Line, mAncestor, FActions, mAction) then
    begin
      Result := Result + [Alternative(TRuleFix.Create(mAction.Title, mAction.Edits), Length(Result) > 0)];
    end;
  end;
end;

procedure TInterfaceCheck.CheckMissing(const AType: TIndexSymbol; const ATypeName: string);
var
  mMissing: TArray<TResolvedSymbol>;
  mNames: TArray<string>;
  mComplete, mDiffers: Boolean;
  mFixes: TArray<TRuleFix>;
begin
  mMissing := FResolver.Queries.MissingInterfaceMembers(FOwnUnit, ATypeName, nil,
    TInterfaceNotImplementedRule.Delegated(FContext.Tree.Tokens, AType.Range), mComplete);
  if not mComplete or (Length(mMissing) = 0) then
  begin
    Exit;
  end;
  mNames := MissingNames(mMissing, ATypeName, mDiffers);
  // Bei abweichenden Köpfen fügte die Korrektur eine zweite gleichnamige Methode ein; dann keine.
  mFixes := nil;
  if not mDiffers then
  begin
    mFixes := InterfaceFixes(AType);
  end;
  if Length(mNames) = 1 then
  begin
    FReport.Add(AType.SelectionRange, cTexts[TDeclarationsText.MissingOne].Fmt([mNames[0], AType.Name]), FLevel,
      mFixes);
  end
  else if Length(mNames) > 1 then
  begin
    FReport.Add(AType.SelectionRange, cTexts[TDeclarationsText.MissingMany].Fmt([JoinedList(mNames), AType.Name]),
      FLevel, mFixes);
  end;
end;

// Nennt die Klasse AType das Interface APrefix?
function TInterfaceCheck.Listed(const AType: TIndexSymbol; const APrefix: string): Boolean;
var
  mAncestor: string;
begin
  Result := False;
  for mAncestor in AType.Ancestors do
  begin
    Result := Result or SameText(BareName(mAncestor), APrefix);
  end;
end;

// Zuordnung "procedure IFoo.Bar = Baz" für ein Interface, das die Klasse nicht nennt; die Zuordnungen sind keine
// Mitglieder (#849), ihre Stelle steht nur im Baum.
procedure TInterfaceCheck.CheckResolutions(const AType: TIndexSymbol; const ATypeName: string);
var
  mHeader: TSyntaxNode;
  mPrefix: string;
begin
  for mHeader in FHeaders do
  begin
    if not SameText(mHeader.EnclosingTypeName, ATypeName) then
    begin
      Continue;
    end;
    mPrefix := BareName(Copy(mHeader.Name, 1, LastDelimiter('.', mHeader.Name) - 1));
    if not Listed(AType, mPrefix) then
    begin
      FReport.Add(TTextRange.Create(mHeader.StartPos, mHeader.EndPos),
        cTexts[TDeclarationsText.NotInList].Fmt([mPrefix, AType.Name]), FLevel);
    end;
  end;
end;

procedure TInterfaceCheck.CheckType(const AType: TIndexSymbol);
var
  mTypeName: string;
begin
  if not IsCandidate(AType) then
  begin
    Exit;
  end;
  mTypeName := AType.Name;
  if AType.Container <> '' then
  begin
    mTypeName := AType.Container + '.' + mTypeName;
  end;
  CheckMissing(AType, mTypeName);
  CheckResolutions(AType, mTypeName);
end;

procedure TInterfaceCheck.Run;
var
  mTypeSymbol: TIndexSymbol;
begin
  for mTypeSymbol in FOwnUnit.Symbols do
  begin
    CheckType(mTypeSymbol);
  end;
end;

procedure TInterfaceNotImplementedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mChecker: TInterfaceCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  // Ohne Projektindex prüft die Regel nur, was die Datei selbst kennt; unbekannte Vorfahren halten sie still.
  mIndex := AContext.Index;
  if mIndex = nil then
  begin
    mIndex := TSymbolIndex.Create;
  end;
  mResolver := TNameResolver.Create(mIndex, AContext.EnsureUnit, AContext.TreeUnits);
  try
    mResolver.Namespaces := AContext.Namespaces;
    mResolver.PinTree(AContext.Tree, AContext.RelativePath);
    try
      mChecker := TInterfaceCheck.Create(AContext, AReport, mResolver, mIndex);
      try
        mChecker.Run;
      finally
        mChecker.Free;
      end;
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
end;

type
  /// <summary>Typvergleich für signature-mismatch (#1324): löst die Typen eines Paars dort auf, wo sie stehen, die
  /// der Deklaration im Typ, die des Rumpfs im implementation-Teil. Ohne Projektindex zählt der Text.</summary>
  TSignatureTypes = class
  private
    FContext: TRuleContext;
    FResolver: TNameResolver;
    FPinned: Boolean;
    function Resolver: TNameResolver;
    function OffsetOf(const APosition: TTextPosition): Integer;
    function ChainAt(AOffset: Integer): TTypeChainResolver;
  public
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    /// <summary>Vergleich für die Typen von APair.</summary>
    function Matcher(const APair: TSignaturePair): TSignatureTypeMatch;
  end;

/// <summary>Vergleich ohne Namensauflösung: verschiedene Namen sind verschiedene Typen.</summary>
function TextTypeMatch(const ADeclType, ABodyType: string): TTypeMatch;
begin
  if TTypeIdentity.Same(ADeclType, ABodyType) then
  begin
    Result := TTypeMatch.Same;
  end
  else
  begin
    Result := TTypeMatch.Different;
  end;
end;

{ TSignatureTypes }

constructor TSignatureTypes.Create(const AContext: TRuleContext);
begin
  inherited Create;
  FContext := AContext;
end;

destructor TSignatureTypes.Destroy;
begin
  if FPinned then
  begin
    FResolver.UnpinTree;
  end;
  FResolver.Free;
  inherited Destroy;
end;

function TSignatureTypes.Resolver: TNameResolver;
begin
  // Erst beim ersten abweichenden Typ: Die meisten Paare unterscheiden sich nicht im Typtext.
  if FResolver = nil then
  begin
    FResolver := TNameResolver.Create(FContext.Index, FContext.EnsureUnit, FContext.TreeUnits);
    FResolver.Namespaces := FContext.Namespaces;
    FResolver.PinTree(FContext.Tree, FContext.RelativePath);
    FPinned := True;
  end;
  Result := FResolver;
end;

function TSignatureTypes.OffsetOf(const APosition: TTextPosition): Integer;
var
  mToken: TPascalToken;
begin
  Result := -1;
  for mToken in FContext.Tree.Tokens do
  begin
    if mToken.StartPos = APosition then
    begin
      Exit(mToken.Offset);
    end;
  end;
end;

function TSignatureTypes.ChainAt(AOffset: Integer): TTypeChainResolver;
var
  mSelf: TSignatureTypes;
begin
  mSelf := Self;
  Result :=
    function(const ANames: TArray<string>; out AType: TResolvedSymbol): Boolean
    begin
      AType := mSelf.Resolver.ResolveChain(mSelf.FContext.Tree, mSelf.FContext.RelativePath, ANames, AOffset);
      Result := AType.Found;
    end;
end;

function TSignatureTypes.Matcher(const APair: TSignaturePair): TSignatureTypeMatch;
var
  mSelf: TSignatureTypes;
  mDeclaration, mBody: TTypeChainResolver;
begin
  if FContext.Index = nil then
  begin
    Result := TextTypeMatch;
    Exit;
  end;
  mSelf := Self;
  mDeclaration := ChainAt(OffsetOf(APair.Declaration.Symbol.SelectionRange.StartPos));
  mBody := ChainAt(OffsetOf(APair.Body.Symbol.SelectionRange.StartPos));
  Result :=
    function(const ADeclType, ABodyType: string): TTypeMatch
    begin
      Result := TTypeIdentity.Compare(ADeclType, ABodyType, mDeclaration, mBody, mSelf.Resolver);
    end;
end;

{ TSignatureMismatchRule }

function TSignatureMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('signature-mismatch', TRuleSeverity.Error,
    cTexts[TDeclarationsText.MismatchTitle].Text);
end;

class function TSignatureMismatchRule.Differences(const ADeclaration, ABody: TSignatureShape): TArray<string>;
var
  mMatch: TSignatureTypeMatch;
begin
  // Typisierte Variable: Delphi wählt die Überladung sonst nicht sicher.
  mMatch := TextTypeMatch;
  Result := Differences(ADeclaration, ABody, mMatch);
end;

/// <summary>Abweichung der Modifizierer (const, var …) eines Parameters, z. B. "Betrag ohne const".</summary>
function ModifierDifference(const ADecl, ABody: TShapeParameter): string;
begin
  if ABody.Modifier = '' then
  begin
    Result := cTexts[TDeclarationsText.WithoutModifier].Fmt([ABody.Name, ADecl.Modifier]);
  end
  else if ADecl.Modifier = '' then
  begin
    Result := cTexts[TDeclarationsText.WithModifier].Fmt([ABody.Name, ABody.Modifier]);
  end
  else
  begin
    Result := cTexts[TDeclarationsText.InsteadOf].Fmt([ABody.Name, ABody.Modifier, ADecl.Modifier]);
  end;
end;

/// <summary>Abweichung des Typs eines Parameters, z. B. "Datum TDateTime statt TDate".</summary>
function TypeDifference(const ADecl, ABody: TShapeParameter): string;
begin
  if ABody.TypeName = '' then
  begin
    Result := cTexts[TDeclarationsText.NoTypeInstead].Fmt([ABody.Name, ADecl.TypeName]);
  end
  else if ADecl.TypeName = '' then
  begin
    Result := cTexts[TDeclarationsText.InsteadOfNoType].Fmt([ABody.Name, ABody.TypeName]);
  end
  else
  begin
    Result := cTexts[TDeclarationsText.InsteadOf].Fmt([ABody.Name, ABody.TypeName, ADecl.TypeName]);
  end;
end;

/// <summary>Aufrufkonvention von AShape, register ohne Angabe.</summary>
function ConventionOf(const AShape: TSignatureShape): string;
begin
  Result := AShape.Convention;
  if Result = '' then
  begin
    Result := 'register';
  end;
end;

class function TSignatureMismatchRule.Differences(const ADeclaration, ABody: TSignatureShape;
  const AMatch: TSignatureTypeMatch): TArray<string>;

  function Differs(const ADeclType, ABodyType: string): Boolean;
  begin
    if (ADeclType = '') or (ABodyType = '') then
    begin
      Result := (ADeclType <> '') or (ABodyType <> '');
    end
    else
    begin
      Result := AMatch(ADeclType, ABodyType) = TTypeMatch.Different;
    end;
  end;

  // Abweichungen gleich vieler Parameter: Name, Modifizierer, Typ.
  function ParameterDifferences: TArray<string>;
  var
    mIndex: Integer;
    mDecl, mBody: TShapeParameter;
  begin
    Result := nil;
    for mIndex := 0 to High(ABody.Parameters) do
    begin
      mDecl := ADeclaration.Parameters[mIndex];
      mBody := ABody.Parameters[mIndex];
      if not SameText(mDecl.Name, mBody.Name) then
      begin
        Result := Result + [cTexts[TDeclarationsText.Instead].Fmt([mBody.Name, mDecl.Name])];
      end;
      if mDecl.Modifier <> mBody.Modifier then
      begin
        Result := Result + [ModifierDifference(mDecl, mBody)];
      end;
      if Differs(mDecl.TypeName, mBody.TypeName) then
      begin
        Result := Result + [TypeDifference(mDecl, mBody)];
      end;
    end;
  end;

begin
  Result := nil;
  if (ADeclaration.Kind <> '') and (ABody.Kind <> '') and (ADeclaration.Kind <> ABody.Kind) then
  begin
    Result := Result + [cTexts[TDeclarationsText.Instead].Fmt([ABody.Kind, ADeclaration.Kind])];
  end;
  if Length(ADeclaration.Parameters) <> Length(ABody.Parameters) then
  begin
    Result := Result + [cTexts[TDeclarationsText.ParamCount].Fmt([Length(ABody.Parameters),
      Length(ADeclaration.Parameters)])];
  end
  else
  begin
    Result := Result + ParameterDifferences;
  end;
  if (ADeclaration.Kind = ABody.Kind) and Differs(ADeclaration.ResultType, ABody.ResultType) then
  begin
    Result := Result + [cTexts[TDeclarationsText.ResultInstead].Fmt([ABody.ResultType, ADeclaration.ResultType])];
  end;
  // Der Rumpf darf die Konvention weglassen; nur eine abweichende Angabe ist ein Fehler.
  if (ABody.Convention <> '') and (ConventionOf(ABody) <> ConventionOf(ADeclaration)) then
  begin
    Result := Result + [cTexts[TDeclarationsText.Instead].Fmt([ABody.Convention, ConventionOf(ADeclaration)])];
  end;
end;

procedure TSignatureMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mLines: TArray<Boolean>;
  mPair: TSignaturePair;
  mChanges: TArray<string>;
  mActions: TArray<TCodeAction>;
  mFixes: TArray<TRuleFix>;
  mIndex: Integer;
  mLevel: TRuleConfidence;
  mTypes: TSignatureTypes;
  mCache: IRuleDerivedCache;

  /// <summary>Routinen auf oberster Ebene von ASection namens AName.</summary>
  function Routines(ASection: TSyntaxNode; const AName: string): TArray<TSyntaxNode>;
  var
    mIndex: Integer;
  begin
    Result := nil;
    if ASection <> nil then
    begin
      for mIndex := 0 to ASection.ChildCount - 1 do
      begin
        if (ASection[mIndex].Kind = TSyntaxKind.RoutineDecl) and SameText(ASection[mIndex].Name, AName) then
        begin
          Result := Result + [ASection[mIndex]];
        end;
      end;
    end;
  end;

  function HasDirective(ARoutine: TSyntaxNode; const ADirective: string): Boolean;
  var
    mHeader: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := False;
    mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if mHeader <> nil then
    begin
      for mIndex := 0 to mHeader.ChildCount - 1 do
      begin
        if (mHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(mHeader[mIndex].Name, ADirective) then
        begin
          Exit(True);
        end;
      end;
    end;
  end;

  /// <summary>Symbol der Routine ARoutine im Index der Datei.</summary>
  function SymbolOf(const AUnit: TUnitIndex; ARoutine: TSyntaxNode; out ASymbol: TIndexSymbol): Boolean;
  var
    mSymbol: TIndexSymbol;
  begin
    for mSymbol in AUnit.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.Routine) and (mSymbol.Container = '') and
        SameText(mSymbol.Name, ARoutine.Name) and (mSymbol.Range.StartPos.Line = ARoutine.StartPos.Line) then
      begin
        ASymbol := mSymbol;
        Exit(True);
      end;
    end;
    Result := False;
  end;

  /// <summary>Kommt die Routine ADecl des interface-Teils AInterface für ein Paar in Frage: eindeutiger Name
  /// ohne Punkt, ohne overload, external und forward?</summary>
  function IsPairCandidate(AInterface, ADecl: TSyntaxNode): Boolean;
  begin
    Result := (ADecl.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', ADecl.Name) = 0) and
      (Length(Routines(AInterface, ADecl.Name)) = 1);
    Result := Result and not HasDirective(ADecl, 'overload') and not HasDirective(ADecl, 'external') and
      not HasDirective(ADecl, 'forward');
  end;

  /// <summary>Paar aus Deklaration ADecl und Rumpf ABody mit Symbolen und Köpfen; False, wenn eines fehlt oder
  /// der Rumpf die Kurzform ohne Parameter und Ergebnis hat.</summary>
  function PairOf(const AUnit: TUnitIndex; ADecl, ABody: TSyntaxNode; out APair: TSignaturePair): Boolean;
  begin
    APair := Default(TSignaturePair);
    Result := SymbolOf(AUnit, ADecl, APair.Declaration.Symbol) and SymbolOf(AUnit, ABody, APair.Body.Symbol);
    Result := Result and TClassCompletion.Shape(AContext.Tree, AContext.Text, APair.Declaration.Symbol,
      APair.DeclarationShape) and TClassCompletion.Shape(AContext.Tree, AContext.Text, APair.Body.Symbol,
      APair.BodyShape);
    Result := Result and ((APair.BodyShape.Parameters <> nil) or (APair.BodyShape.ResultType <> ''));
    APair.Declaration.Declared := True;
  end;

  /// <summary>Routine im interface-Teil mit ihrem Rumpf (#1380): dcc meldet E2037, wenn der Rumpf anders
  /// aussieht und die Deklaration kein overload hat (Cm.E2037). Nur eindeutige Namen; Rümpfe in der Kurzform
  /// ohne Parameter und Ergebnis übernehmen den Kopf. Mit Include-Dateien kann dort ein weiterer Rumpf stehen.
  /// </summary>
  function RoutinePairs: TArray<TSignaturePair>;
  var
    mInterface, mImplementation, mDecl: TSyntaxNode;
    mBodies: TArray<TSyntaxNode>;
    mIndex: Integer;
    mUnit: TUnitIndex;
    mPair: TSignaturePair;
  begin
    Result := nil;
    if (AContext.Tree.Root = nil) or HasIncludes(AContext) then
    begin
      Exit;
    end;
    mInterface := AContext.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
    mImplementation := AContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
    if (mInterface = nil) or (mImplementation = nil) then
    begin
      Exit;
    end;
    mUnit := TRuleDerived.UnitIndex(mCache, AContext);
    for mIndex := 0 to mInterface.ChildCount - 1 do
    begin
      mDecl := mInterface[mIndex];
      if not IsPairCandidate(mInterface, mDecl) then
      begin
        Continue;
      end;
      mBodies := Routines(mImplementation, mDecl.Name);
      if (Length(mBodies) = 1) and (mBodies[0].FindChild(TSyntaxKind.Block) <> nil) and
        PairOf(mUnit, mDecl, mBodies[0], mPair) then
      begin
        Result := Result + [mPair];
      end;
    end;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mLines := ConditionalLines(AContext);
  mLevel := Confidence(AContext);
  mCache := TRuleDerived.Open(AContext);
  mTypes := TSignatureTypes.Create(AContext);
  try
    for mPair in TClassCompletion.Pairs(AContext.Tree, AContext.Text) + RoutinePairs do
    begin
      // Bedingte Übersetzung im Kopf ({$IFDEF} in der Parameterliste): Welche Parameter gelten, ist offen (#1324).
      if IsConditional(mLines, mPair.Declaration) or IsConditional(mLines, mPair.Body) or
        mPair.DeclarationShape.Conditional or mPair.BodyShape.Conditional then
      begin
        Continue;
      end;
      mChanges := Differences(mPair.DeclarationShape, mPair.BodyShape, mTypes.Matcher(mPair));
      if mChanges = nil then
      begin
        Continue;
      end;
      mFixes := nil;
      // refactoring.syncSignatures aus (#100): die Meldung bleibt, die Angleich-Aktionen entfallen.
      if not AContext.NoSignatureSync and TClassCompletion.PairFixes(AContext.Tree, AContext.Text, mPair, mActions) then
      begin
        for mIndex := 0 to High(mActions) do
        begin
          mFixes := mFixes + [Alternative(TRuleFix.Create(mActions[mIndex].Title, mActions[mIndex].Edits), mIndex > 0)];
        end;
      end;
      AReport.Add(mPair.Body.Symbol.SelectionRange, cTexts[TDeclarationsText.DiffersFrom].Fmt(
        [mPair.Body.Symbol.Name, string.Join(', ', mChanges)]), mLevel, mFixes);
    end;
  finally
    mTypes.Free;
  end;
end;

{ TFieldAfterMethodRule }

function TFieldAfterMethodRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cFieldAfterMethodRuleId, TRuleSeverity.Error,
    cTexts[TDeclarationsText.FieldTitle].Text);
end;

procedure TFieldAfterMethodRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mLines: TArray<string>;
  mLineBreak: string;
  mPaths: TArray<string>;

  function FirstToken(ANode: TSyntaxNode): Integer;
  begin
    Result := TokenFrom(mTokens, ANode.StartOffset);
  end;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(mPaths, FirstToken(ANode));
  end;

  function OnlySpaceBefore(const APosition: TTextPosition): Boolean;
  begin
    Result := BlankBefore(mLines, APosition);
  end;

  function OnlyCommentAfter(const APosition: TTextPosition): Boolean;
  begin
    Result := BlankAfter(mLines, APosition);
  end;

  // Erstes Kind des Blocks um ABody[AIndex]: davorstehende Attribute gehören dazu.
  function BlockFirst(ABody: TSyntaxNode; AIndex: Integer): TSyntaxNode;
  begin
    while (AIndex > 0) and (ABody[AIndex - 1].Kind = TSyntaxKind.Attribute) do
    begin
      Dec(AIndex);
    end;
    Result := ABody[AIndex];
  end;

  // Erste Zeile des Blocks ab ANode samt Kommentarzeilen direkt darüber (XMLDoc).
  function StartLine(ANode: TSyntaxNode): Integer;
  var
    mIndex: Integer;
  begin
    Result := ANode.StartPos.Line;
    mIndex := FirstToken(ANode) - 1;
    while (mIndex >= 0) and (mTokens[mIndex].Kind = TPascalTokenKind.Comment) and
      (mTokens[mIndex].EndPos.Line = Result - 1) and OnlySpaceBefore(mTokens[mIndex].StartPos) do
    begin
      Result := mTokens[mIndex].StartPos.Line;
      Dec(mIndex);
    end;
  end;

  // Feld samt Attributen und Kommentaren vor das erste Mitglied des Abschnitts; nil, wenn Zeilen nicht passen.
  function MoveFix(ABody: TSyntaxNode; AField, AMember: Integer): TArray<TRuleFix>;
  var
    mField, mTarget: TSyntaxNode;
    mFieldStart, mFieldEnd, mTargetLine, mLine: Integer;
    mMoved: string;
  begin
    Result := nil;
    mField := BlockFirst(ABody, AField);
    mTarget := BlockFirst(ABody, AMember);
    if not OnlySpaceBefore(mField.StartPos) or not OnlySpaceBefore(mTarget.StartPos) or
      not OnlyCommentAfter(ABody[AField].EndPos) then
    begin
      Exit;
    end;
    mFieldStart := StartLine(mField);
    mFieldEnd := ABody[AField].EndPos.Line;
    mTargetLine := StartLine(mTarget);
    if (mTargetLine >= mFieldStart) or (mFieldEnd + 1 >= Length(mLines)) then
    begin
      Exit;
    end;
    mMoved := '';
    for mLine := mFieldStart to mFieldEnd do
    begin
      mMoved := mMoved + mLines[mLine] + mLineBreak;
    end;
    Result := [TRuleFix.Create(cTexts[TDeclarationsText.MoveField].Text, [
      TRuleEdit.Create(TTextRange.Create(mTargetLine, 0, mTargetLine, 0), mMoved),
      TRuleEdit.Create(TTextRange.Create(mFieldStart, 0, mFieldEnd + 1, 0), '')], True)];
  end;

  function VarFix(ABody: TSyntaxNode; AField: Integer): TRuleFix;
  var
    mFirst: TSyntaxNode;
  begin
    mFirst := BlockFirst(ABody, AField);
    Result := TRuleFix.Create(cTexts[TDeclarationsText.InsertVar].Text,
      [TRuleEdit.Create(TTextRange.Create(mFirst.StartPos,
      mFirst.StartPos), 'var ')], True);
  end;

  // Ist ABody[AMember] eine Methode oder Property, die immer mit übersetzt wird, wenn das Feld ABody[AField]
  // übersetzt wird?
  function Guards(ABody: TSyntaxNode; AMember, AField: Integer): Boolean;
  begin
    Result := (ABody[AMember].Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl]) and
      TConditionalBranches.Implies(PathOf(ABody[AField]), PathOf(ABody[AMember]));
  end;

  // Gibt es zwischen ABody[AFirst] und dem Feld ABody[AField] eine Methode, die es sicher vor dem Feld gibt?
  function HasGuard(ABody: TSyntaxNode; AFirst, AField: Integer): Boolean;
  var
    mMember: Integer;
  begin
    mMember := AFirst;
    while (mMember < AField) and not Guards(ABody, mMember, AField) do
    begin
      Inc(mMember);
    end;
    Result := mMember < AField;
  end;

  // Meldet das Feld ABody[AField] hinter dem ersten Mitglied ABody[AFirst]; ASamePaths: keine Bedingungen
  // zwischen den Mitgliedern.
  procedure CheckField(ABody: TSyntaxNode; AField, AFirst: Integer; ASamePaths: Boolean);
  var
    mFixes: TArray<TRuleFix>;
  begin
    if not HasGuard(ABody, AFirst, AField) then
    begin
      Exit;
    end;
    mFixes := nil;
    // Verschieben nur ohne Bedingungen dazwischen, sonst landet das Feld in einem anderen Zweig.
    if ASamePaths and (PathOf(ABody[AField]) = PathOf(ABody[AFirst])) then
    begin
      mFixes := MoveFix(ABody, AField, AFirst);
    end;
    if ABody.Kind = TSyntaxKind.RecordType then
    begin
      // In Records verschiebt das Verschieben das Speicherlayout; var zuerst.
      mFixes := [VarFix(ABody, AField)] + mFixes;
    end
    else
    begin
      mFixes := mFixes + [VarFix(ABody, AField)];
    end;
    AReport.Add(TTextRange.Create(ABody[AField].StartPos, ABody[AField].EndPos),
      cTexts[TDeclarationsText.FieldAfter].Text, TRuleConfidence.High, mFixes);
  end;

  procedure CheckBody(ABody: TSyntaxNode);
  var
    mIndex, mFirst: Integer;
    mSamePaths: Boolean;
  begin
    mFirst := -1;
    mSamePaths := True;
    for mIndex := 0 to ABody.ChildCount - 1 do
    begin
      case ABody[mIndex].Kind of
        // Ein neuer Abschnitt bzw. var erlaubt wieder Felder.
        TSyntaxKind.Visibility, TSyntaxKind.VarSection, TSyntaxKind.TypeSection, TSyntaxKind.ConstSection:
          begin
            mFirst := -1;
            mSamePaths := True;
          end;
        TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl:
          if mFirst < 0 then
          begin
            mFirst := mIndex;
          end
          else if PathOf(ABody[mIndex]) <> PathOf(ABody[mFirst]) then
          begin
            mSamePaths := False;
          end;
        TSyntaxKind.Field:
          if mFirst >= 0 then
          begin
            CheckField(ABody, mIndex, mFirst, mSamePaths);
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType] then
        begin
          CheckBody(mNode);
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

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
  mPaths := TConditionalBranches.Paths(mTokens);
  Visit(AContext.Tree.Root);
end;

procedure RegisterDeclarationRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDeclaredNotImplementedRule.Create);
  ARegistry.Register(TImplementedNotDeclaredRule.Create);
  ARegistry.Register(TSignatureMismatchRule.Create);
  ARegistry.Register(TInterfaceNotImplementedRule.Create);
  ARegistry.Register(TFieldAfterMethodRule.Create);
  ARegistry.Register(TOverloadDirectiveMissingRule.Create);
  ARegistry.Register(TDuplicateDeclarationRule.Create);
  ARegistry.Register(TVariantRecordManagedFieldRule.Create);
  ARegistry.Register(TTypeTooLargeRule.Create);
  ARegistry.Register(TDefaultParameterRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Declarations', cTexts);

end.
