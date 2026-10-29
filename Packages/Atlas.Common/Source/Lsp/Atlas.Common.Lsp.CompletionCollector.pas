unit Atlas.Common.Lsp.CompletionCollector;

// Sammler der allgemeinen Vervollständigung (Code-Review S-01, Konzept 4.2 Schritt 5): vorher 13
// verschachtelte Routinen in TLspCompletion.Collect mit 18 geteilten Variablen. Jeder Eintrag entsteht aus
// Name, Detail, Art, Strafpunkten und dem aufgelösten Symbol; Quelle und Merkmale kommen aus dem Symbol,
// nicht aus geteiltem Zustand. Bewertet wird nach Treffer (unscharf oder Anfang), Strafpunkten für die
// Gruppen (eingebunden, Schlüsselwörter, Projekt-Import, Bibliotheks-Import, nicht verfügbar), dann nach
// Reihenfolge der Gültigkeitsbereiche; passende Einträge zum erwarteten Typ (#417) kommen zuerst.
// Gestaffelt (#616) gibt SendStage den bisherigen Stand an den Aufrufer weiter.
//
// Root-Unit statt Internals: Der Sammler braucht TCompletionItem aus Atlas.Common.Lsp.CompletionRequest,
// und Internals dürfen das eigene Root nicht importieren (docs/Architektur.md, Importregeln).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest;

const
  // CompletionItemKind
  KindMethod = 2;
  KindFunction = 3;
  KindConstructor = 4;
  KindField = 5;
  KindVariable = 6;
  KindClass = 7;
  KindInterface = 8;
  KindModule = 9;
  KindProperty = 10;
  KindEnum = 13;
  KindEnumMember = 20;
  KindConstant = 21;
  KindStruct = 22;
  KindKeyword = 14;
  KindSnippet = 15;
  /// <summary>Abzüge vom Trefferwert, die die Gruppenreihenfolge festlegen (Code-Review S-07): eingebunden vor
  /// Schlüsselwörtern vor Projekt-Import vor Bibliotheks-Import vor nicht verfügbaren Einträgen.</summary>
  PenaltyKeyword = 50;
  PenaltyProjectImport = 100;
  PenaltyLibraryImport = 200;
  PenaltyUnavailable = 500;
  /// <summary>Typen im Index (#31: Filter nach "class(", ":", "is", "as").</summary>
  IndexTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];
  /// <summary>Höchstzahl der Einträge einer Antwort (TLspCompletion.MaxItems).</summary>
  CompletionMaxItems = 1000;
  /// <summary>Höchstzahl der Vorschläge aus nicht eingebundenen Units (TLspCompletion.MaxImportItems).</summary>
  CompletionMaxImportItems = 200;
  /// <summary>So viele Zeichen muss der Name haben, bevor nicht eingebundene Units mitsuchen.</summary>
  CompletionMinImportPrefix = 2;

type
  /// <summary>Vorfilter für Kandidaten und Symbole aus anderen Units (#465: nur Attributklassen).</summary>
  TCompletionAdmitFunc = reference to function(const ASymbol: TResolvedSymbol): Boolean;

  TScoredItem = record
    Item: TCompletionItem;
    Score: Integer;
    Order: Integer;
  end;

  TScoredItemComparer = class(TInterfacedObject, IComparer<TScoredItem>)
  public
    function Compare(const Left, Right: TScoredItem): Integer;
  end;

  TTypeFamily = (None, Integer_, Float, String_, Char_, Boolean_);

  /// <summary>Übliche Umwandlung eines Werts in den erwarteten Typ (#490): Text mit dem Ausdruck, benötigte
  /// Units; Lossy bei Gleitkomma nach Ganzzahl (dann ohne Text, nur der Hinweis auf Round und Trunc).</summary>
  TTypeConversion = record
    Text: string;
    Units: TArray<string>;
    Lossy: Boolean;
  end;

  TCompletionCollector = class
  private
    // Nicht besessen.
    FRequest: TCompletionRequest;
    FContext: TCompletionContext;
    FExpected: string;
    FOwnUnit: string;
    FOnPartial: TCompletionPartialProc;
    FList: TList<TScoredItem>;
    // Gestaffelt (#616): schon gesendete Einträge und ihre Namen.
    FSentNames: TDictionary<string, Boolean>;
    FSent: Integer;
    FDescends: TDictionary<string, Boolean>;
    FTruncated: Boolean;
    FImportsCapped: Boolean;
    FAnyFits: Boolean;
    // Typkonvertierung (#490): Grundtyp nach Aliasen und Aufzählungstypen je Typname.
    FBaseTypes: TDictionary<string, string>;
    FUsed: TArray<string>;
    FUsedReady: Boolean;
    FAdmit: TCompletionAdmitFunc;
    function MemberFits(const AMember: TResolvedSymbol): Boolean;
    /// <summary>Typ nach Aliasen bis zu einem eingebauten Typ oder TDateTime (TCaption → string); Aufzählungen
    /// mit dem Präfix "enum:". Unbekannte bleiben, wie sie sind.</summary>
    function BaseType(const AType: string): string;
    /// <summary>Umwandlungseintrag zu AOriginal (#490) bzw. Hinweis Lossy daran; False ohne Umwandlung.</summary>
    function Conversion(const AName: string; const ASymbol: TResolvedSymbol; var AOriginal: TScoredItem;
      out AConverted: TScoredItem): Boolean;
    /// <summary>Bereichsstufe (#488) für einen Eintrag aus AMember; 0 ohne Symbol oder nach einem Punkt.</summary>
    function ScopeOf(const AMember: TResolvedSymbol; out AUnitName: string): Integer;
    procedure MarkOwnConditions;
    function TakeStage(AStaged: Boolean): TArray<TCompletionItem>;
    function KnownNames: TDictionary<string, Boolean>;
    /// <summary>Wie AddFromOtherUnits; AWanted = nil heißt alle Namen, sonst nur diese (Großbuchstaben).</summary>
    procedure AddImports(AWanted: TDictionary<string, Boolean>);
  public
    /// <summary>ARequest liefert Baum, Resolver, Index, Datei und Matching; AExpected ist der erwartete Typ
    /// (#417), '' ohne. AOnPartial bekommt die Teilergebnisse von SendStage; nil = alles in Finish.</summary>
    constructor Create(ARequest: TCompletionRequest; const AContext: TCompletionContext; const AExpected: string;
      const AOnPartial: TCompletionPartialProc);
    destructor Destroy; override;
    /// <summary>Ein Eintrag AName; Quelle (FileName, SelectionRange) und Merkmale aus ASymbol, dessen Name ''
    /// „kein Symbol“ bedeutet (Schlüsselwörter, Units). False, wenn AName nicht zum Getippten passt.</summary>
    function Add(const AName, ADetail: string; AKind: Integer; const ASymbol: TResolvedSymbol): Boolean; overload;
    /// <summary>Wie oben, APenalty vom Trefferwert abgezogen.</summary>
    function Add(const AName, ADetail: string; AKind, APenalty: Integer;
      const ASymbol: TResolvedSymbol): Boolean; overload;
    /// <summary>Wie oben, mit weiteren Änderungen beim Annehmen (uses-Eintrag).</summary>
    function Add(const AName, ADetail: string; AKind, APenalty: Integer; const ASymbol: TResolvedSymbol;
      const AEdits: TArray<TRuleEdit>): Boolean; overload;
    /// <summary>Fertiger Eintrag mit eigener Punktzahl (uses-Abschnitt, #469); kein Abgleich mit dem Getippten.
    /// </summary>
    procedure AddItem(const AItem: TCompletionItem; AScore: Integer);
    /// <summary>Letzten Eintrag als nicht verfügbar markieren (#476).</summary>
    procedure MarkLastUnavailable;
    /// <summary>Kandidaten des Resolvers; an Typpositionen (#31) nur Typen.</summary>
    procedure AddCandidates(const ACandidates: TArray<TResolvedSymbol>);
    /// <summary>Mitglieder aus nicht geltenden Zweigen der Typen, deren Mitglieder AMembers schon zeigt (#476):
    /// abgeschwächt am Ende, wie die übrigen nicht verfügbaren Einträge.</summary>
    procedure AddUnavailableMembers(const AMembers: TArray<TResolvedSymbol>);
    /// <summary>Deklarationen der eigenen und eingebundener Units, die nur unter anderen Bedingungen existieren
    /// (#476): ans Ende, mit Bedingung und als nicht verfügbar markiert.</summary>
    procedure AddUnavailable;
    /// <summary>Symbole aus nicht eingebundenen Units (#180) mit uses-Eintrag; Projekt-Units vor Bibliotheken.
    /// </summary>
    procedure AddFromOtherUnits; overload;
    /// <summary>Nur die Symbole namens ANames aus nicht eingebundenen Units (#465: bekannte Attributklassen schon
    /// nach "[" ohne Eingabe); der Name muss zum getippten Anfang passen.</summary>
    procedure AddFromOtherUnits(const ANames: TArray<string>); overload;
    /// <summary>Gleichnamige Bezeichner aus anderen Units (#475): je Eintrag aus einer eingebundenen Unit, dessen
    /// Name weitere Units deklarieren, diese Varianten direkt dahinter; der Eintrag selbst trägt „aktiv“.
    /// Nach den Units aus uses aufrufen, vor dem Senden ihrer Stufe.</summary>
    procedure AddSameNameVariants;
    /// <summary>Mitglieder von Helpern für ATypes (Typ und Vorfahren, nächster zuerst) aus nicht eingebundenen
    /// Units (#456) mit uses-Eintrag, hinter den übrigen Mitgliedern.</summary>
    procedure AddHelpersFromOtherUnits(const ATypes: TArray<TResolvedSymbol>);
    /// <summary>Schlüsselwörter (#31) mit PenaltyKeyword.</summary>
    procedure AddKeywords(const AWords: TArray<string>);
    /// <summary>Namen des eigenen Bereichs, die gleichnamige Deklarationen aus uses verdecken (#488): vor dem
    /// Senden der ersten Stufe vermerken, die zweite bringt diese Namen nicht mehr.</summary>
    procedure MarkUsedShadows;
    /// <summary>Vorfilter des Resolvers nach dem Getippten an (#616) bzw. aus.</summary>
    procedure SetNameFilter(AOn: Boolean);
    /// <summary>Nur Kandidaten (AddCandidates) und Symbole anderer Units (AddFromOtherUnits), für die AAdmit
    /// True liefert; nil = alle. Vor dem Kürzen auf die Höchstzahl, damit passende nicht wegfallen.</summary>
    procedure SetAdmit(const AAdmit: TCompletionAdmitFunc);
    /// <summary>Teilergebnis senden (#616); ohne AOnPartial bleibt alles für Finish liegen.</summary>
    procedure SendStage;
    /// <summary>Rest der Liste, sortiert und gekürzt. AIncomplete nur, wenn beim Weitertippen etwas dazukommen
    /// kann (#616): gekürzt, Importe gekappt oder noch nicht gesucht (zu kurzer Name).</summary>
    function Finish(out AIncomplete: Boolean): TArray<TCompletionItem>;
  end;

/// <summary>CompletionItemKind des LSP zur Symbolart.</summary>
function CompletionKindOf(AKind: TIndexSymbolKind): Integer;
/// <summary>Eintrag aus dem nächsten Gültigkeitsbereich: lokal, Parameter, eigenes Mitglied (nicht geerbt)
/// oder eigene Unit; solche Einträge fallen beim Kürzen auf MaxItems nie heraus.</summary>
function IsNearItem(const AItem: TCompletionItem): Boolean;
/// <summary>Typname für den Vergleich: ohne Leerzeichen und Unit-Präfix, klein.</summary>
function PlainType(const AType: string): string;
/// <summary>Familie eingebauter Typen für die Zuweisungsverträglichkeit (#417).</summary>
function TypeFamily(const APlain: string): TTypeFamily;
/// <summary>Ein Wert vom Typ AActual passt zu AExpected: gleich, gleiche Familie eingebauter Typen,
/// Integer zu Gleitkomma, Char zu String. ACheckDescent: Beides sind keine eingebauten Typen; ob AActual
/// von AExpected abstammt, muss die Namensauflösung klären.</summary>
function TypeFits(const AActual, AExpected: string; out ACheckDescent: Boolean): Boolean;
/// <summary>Umwandlung von AExpression (Typ AActual, nach Aliasen) in AExpected (#490): Zahl, Boolean,
/// TDateTime/TDate/TTime und Aufzählung (AEnumType, '' sonst) nach string; string nach Ganzzahl und
/// Gleitkomma. AHelper: Helper-Stil (X.ToString), wo es ihn gibt. False ohne Umwandlung und ohne Hinweis.</summary>
function TypeConversion(const AActual, AExpected, AEnumType, AExpression: string; AHelper: Boolean;
  out AResult: TTypeConversion): Boolean;
/// <summary>Punktzahl von AName; TFuzzyMatch.NoMatch, wenn er nicht passt.</summary>
function MatchScore(const AName, APrefix: string; AMatching: TCompletionMatching): Integer;
/// <summary>Vorfilter des Resolvers (#616): nur Namen, die zu APrefix passen. GetEnumerator bleibt, weil die
/// Postfix-Vorlagen daran erkennen, ob der Typ aufzählbar ist; Add verwirft ihn ohne Treffer wieder.</summary>
function PrefixFilter(const APrefix: string; AMatching: TCompletionMatching): TCandidateNameFilter;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.NameIndex,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Lsp.CompletionSameNames,
  Atlas.Text.Fuzzy;

const
  // Kürzel über Wortanfänge (#882): zwischen Anfang (TFuzzyMatch, ab etwa 3000) und Teilwort (höchstens
  // 2499 mit Wortanfang-Zuschlag), wie im Plugin (TAtlasCompletionMatcher: Anfang vor Kürzel vor Teilwort).
  WordStartsScore = 2600;

function CompletionKindOf(AKind: TIndexSymbolKind): Integer;
begin
  case AKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.HelperType, TIndexSymbolKind.TypeAlias:
      Result := KindClass;
    TIndexSymbolKind.RecordType:
      Result := KindStruct;
    TIndexSymbolKind.InterfaceType:
      Result := KindInterface;
    TIndexSymbolKind.EnumType:
      Result := KindEnum;
    TIndexSymbolKind.EnumMember:
      Result := KindEnumMember;
    TIndexSymbolKind.Constant:
      Result := KindConstant;
    TIndexSymbolKind.Field:
      Result := KindField;
    TIndexSymbolKind.Property_:
      Result := KindProperty;
    TIndexSymbolKind.Method:
      Result := KindMethod;
    TIndexSymbolKind.Constructor_:
      Result := KindConstructor;
    TIndexSymbolKind.Routine:
      Result := KindFunction;
  else
    Result := KindVariable;
  end;
end;

function IsNearItem(const AItem: TCompletionItem): Boolean;
begin
  Result := (AItem.Scope in [1, 2, 4]) or ((AItem.Scope = 3) and (AItem.Depth = 0));
end;

function TScoredItemComparer.Compare(const Left, Right: TScoredItem): Integer;
begin
  // Höhere Punktzahl zuerst, sonst Reihenfolge der Gültigkeitsbereiche.
  if Left.Score <> Right.Score then
    Result := Right.Score - Left.Score
  else
    Result := Left.Order - Right.Order;
end;

function PlainType(const AType: string): string;
begin
  Result := LowerCase(AType.Replace(' ', ''));
  if (Pos('<', Result) = 0) and (LastDelimiter('.', Result) > 0) then
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

function TypeFamily(const APlain: string): TTypeFamily;
begin
  if MatchText(APlain, ['integer', 'cardinal', 'int64', 'uint64', 'byte', 'word', 'shortint', 'smallint', 'longint',
    'longword', 'nativeint', 'nativeuint', 'int8', 'int16', 'int32', 'uint8', 'uint16', 'uint32', 'fixedint',
    'fixeduint']) then
    Result := TTypeFamily.Integer_
  else if MatchText(APlain, ['double', 'single', 'extended', 'real', 'currency', 'comp']) then
    Result := TTypeFamily.Float
  else if MatchText(APlain, ['string', 'unicodestring', 'ansistring', 'widestring', 'shortstring', 'rawbytestring',
    'utf8string']) then
    Result := TTypeFamily.String_
  else if MatchText(APlain, ['char', 'widechar', 'ansichar']) then
    Result := TTypeFamily.Char_
  else if MatchText(APlain, ['boolean', 'bytebool', 'wordbool', 'longbool']) then
    Result := TTypeFamily.Boolean_
  else
    Result := TTypeFamily.None;
end;

function TypeFits(const AActual, AExpected: string; out ACheckDescent: Boolean): Boolean;
var
  Actual, Expected: TTypeFamily;
begin
  ACheckDescent := False;
  if (AActual = '') or (AExpected = '') then
    Exit(False);
  if PlainType(AActual) = PlainType(AExpected) then
    Exit(True);
  Actual := TypeFamily(PlainType(AActual));
  Expected := TypeFamily(PlainType(AExpected));
  if Expected <> TTypeFamily.None then
    Exit((Actual = Expected) or (Expected = TTypeFamily.Float) and (Actual = TTypeFamily.Integer_) or
      (Expected = TTypeFamily.String_) and (Actual = TTypeFamily.Char_));
  ACheckDescent := Actual = TTypeFamily.None;
  Result := False;
end;

function TypeConversion(const AActual, AExpected, AEnumType, AExpression: string; AHelper: Boolean;
  out AResult: TTypeConversion): Boolean;
var
  Actual, Expected: TTypeFamily;
  Plain, Text, Helper: string;
begin
  AResult := Default(TTypeConversion);
  Plain := PlainType(AActual);
  Actual := TypeFamily(Plain);
  Expected := TypeFamily(PlainType(AExpected));
  Text := '';
  Helper := '';
  if Expected = TTypeFamily.String_ then
  begin
    if AEnumType <> '' then
    begin
      Text := 'GetEnumName(TypeInfo(' + AEnumType + '), Ord(' + AExpression + '))';
      AResult.Units := ['System.TypInfo'];
    end
    else if Plain = 'tdatetime' then
      Text := 'DateTimeToStr(' + AExpression + ')'
    else if Plain = 'tdate' then
      Text := 'DateToStr(' + AExpression + ')'
    else if Plain = 'ttime' then
      Text := 'TimeToStr(' + AExpression + ')'
    else if Actual = TTypeFamily.Integer_ then
    begin
      Text := 'IntToStr(' + AExpression + ')';
      Helper := AExpression + '.ToString';
    end
    else if Actual = TTypeFamily.Float then
    begin
      Text := 'FloatToStr(' + AExpression + ')';
      Helper := AExpression + '.ToString';
    end
    else if Actual = TTypeFamily.Boolean_ then
    begin
      // Ohne TUseBoolStrs.True liefert der Helper "-1" und "0".
      Text := 'BoolToStr(' + AExpression + ', True)';
      Helper := AExpression + '.ToString(TUseBoolStrs.True)';
    end;
  end
  else if (Actual = TTypeFamily.String_) and (Expected = TTypeFamily.Integer_) then
  begin
    if MatchText(PlainType(AExpected), ['int64', 'uint64']) then
    begin
      Text := 'StrToInt64(' + AExpression + ')';
      Helper := AExpression + '.ToInt64';
    end
    else
    begin
      Text := 'StrToInt(' + AExpression + ')';
      Helper := AExpression + '.ToInteger';
    end;
  end
  else if (Actual = TTypeFamily.String_) and (Expected = TTypeFamily.Float) then
  begin
    Text := 'StrToFloat(' + AExpression + ')';
    Helper := AExpression + '.ToDouble';
  end
  else if (Actual = TTypeFamily.Float) and (Expected = TTypeFamily.Integer_) then
  begin
    // Verlustbehaftet: kein Vorschlag, nur der Hinweis.
    AResult.Lossy := True;
    Exit(True);
  end;
  if Text = '' then
    Exit(False);
  if AHelper and (Helper <> '') then
    Text := Helper;
  AResult.Text := Text;
  if AResult.Units = nil then
    AResult.Units := ['System.SysUtils'];
  Result := True;
end;

function MatchScore(const AName, APrefix: string; AMatching: TCompletionMatching): Integer;
begin
  if APrefix = '' then
    Exit(0);
  if AMatching = TCompletionMatching.Prefix then
  begin
    if AName.StartsWith(APrefix, True) then
      Exit(0);
    Exit(TFuzzyMatch.NoMatch);
  end;
  Result := TFuzzyMatch.CompletionScore(AName, APrefix);
  // Kürzel ("bs" → btnSave) vor Teilwort und Teilfolge (#882): Sonst fielen sie beim Kürzen auf MaxItems
  // hinter bloße Teilwörter zurück und erschienen erst mit passendem Anfang.
  if (Result <> TFuzzyMatch.NoMatch) and not AName.StartsWith(APrefix, True) and
    TTextFuzzy.MatchesWordStarts(APrefix, AName) then
    Result := WordStartsScore - Min(Length(AName) - Length(APrefix), 99);
end;

function PrefixFilter(const APrefix: string; AMatching: TCompletionMatching): TCandidateNameFilter;
begin
  Result :=
    function(const AName: string): Boolean
    begin
      Result := (MatchScore(AName, APrefix, AMatching) <> TFuzzyMatch.NoMatch) or SameText(AName, 'GetEnumerator');
    end;
end;

{ TCompletionCollector }

constructor TCompletionCollector.Create(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  const AExpected: string; const AOnPartial: TCompletionPartialProc);
begin
  inherited Create;
  FRequest := ARequest;
  FContext := AContext;
  FExpected := AExpected;
  FOnPartial := AOnPartial;
  // Name der eigenen Unit für die Bereichsstufe (#488).
  FOwnUnit := '';
  if ARequest.Tree <> nil then
    FOwnUnit := TUsesClauses.OwnName(ARequest.Tree.Tokens);
  FDescends := TDictionary<string, Boolean>.Create;
  FBaseTypes := TDictionary<string, string>.Create;
  FSentNames := TDictionary<string, Boolean>.Create;
  FList := TList<TScoredItem>.Create(TScoredItemComparer.Create);
end;

destructor TCompletionCollector.Destroy;
begin
  FList.Free;
  FSentNames.Free;
  FBaseTypes.Free;
  FDescends.Free;
  inherited;
end;

function TCompletionCollector.MemberFits(const AMember: TResolvedSymbol): Boolean;
var
  TypeText: string;
  CheckDescent: Boolean;
begin
  // Typ des Werts: Variablen, Felder, Eigenschaften, Funktionsergebnis; Aufzählungswerte über ihren Typ.
  if AMember.SymbolKind = TIndexSymbolKind.EnumMember then
    TypeText := AMember.Container
  else if AMember.IsType then
    Exit(False)
  else
    TypeText := AMember.TypeName;
  Result := TypeFits(TypeText, FExpected, CheckDescent);
  if Result or not CheckDescent then
    Exit;
  // Klassen: Nachfahr des erwarteten Typs; je Typname einmal auflösen.
  if not FDescends.TryGetValue(LowerCase(TypeText), Result) then
  begin
    Result := FRequest.Resolver.TypeDescendsFrom(FRequest.Tree, FRequest.FileName, FContext.Offset, TypeText,
      FExpected);
    FDescends.Add(LowerCase(TypeText), Result);
  end;
end;

function TCompletionCollector.BaseType(const AType: string): string;
var
  Current: TResolvedSymbol;
  Depth: Integer;

  function Known(const AText: string): Boolean;
  begin
    Result := (TypeFamily(PlainType(AText)) <> TTypeFamily.None) or
      MatchText(PlainType(AText), ['tdatetime', 'tdate', 'ttime']);
  end;

begin
  Result := AType;
  if (AType = '') or Known(AType) then
    Exit;
  // Übliche Aliase der RTL und VCL auch ohne deren Quellen im Index.
  if MatchText(PlainType(AType), ['tcaption', 'tfilename']) then
    Exit('string');
  if FBaseTypes.TryGetValue(LowerCase(AType), Result) then
    Exit;
  Result := AType;
  Current := FRequest.Resolver.ResolveChain(FRequest.Tree, FRequest.FileName, AType.Split(['.']), FContext.Offset);
  Depth := 0;
  while Current.Found and Current.IsType and (Depth < 8) do
  begin
    if Current.SymbolKind = TIndexSymbolKind.EnumType then
    begin
      Result := 'enum:' + AType;
      Break;
    end;
    if (Current.SymbolKind <> TIndexSymbolKind.TypeAlias) or (Current.TypeName = '') then
      Break;
    // "TCaption = type string": das Wort type gehört nicht zum Namen.
    Result := Trim(Current.TypeName);
    if Result.StartsWith('type ', True) then
      Result := Trim(Copy(Result, 6, MaxInt));
    if Known(Result) then
      Break;
    Current := FRequest.Resolver.ResolveChain(FRequest.Tree, FRequest.FileName, Result.Split(['.']),
      FContext.Offset);
    Inc(Depth);
  end;
  FBaseTypes.AddOrSetValue(LowerCase(AType), Result);
end;

function TCompletionCollector.Conversion(const AName: string; const ASymbol: TResolvedSymbol;
  var AOriginal: TScoredItem; out AConverted: TScoredItem): Boolean;
var
  Actual, Expected, EnumType, Expression, Shown: string;
  Converted, Display: TTypeConversion;
  Helper: Boolean;
  Start: TTextPosition;
  UnitName: string;
  Edit: TRuleEdit;
begin
  Result := False;
  AConverted := Default(TScoredItem);
  // Nur Werte ohne Pflichtargumente; Typen, Aufzählungswerte und Importe mit eigenem uses-Eintrag nicht.
  if (FRequest.Settings.TypeConversion = TCompletionTypeConversion.Off) or (FExpected = '') or
    (ASymbol.Name = '') or ASymbol.IsType or (ASymbol.SymbolKind = TIndexSymbolKind.EnumMember) or
    (ASymbol.MinArgs > 0) or (ASymbol.TypeName = '') or (AOriginal.Item.AdditionalEdits <> nil) or
    AOriginal.Item.Unavailable or (FContext.Filter <> TCompletionFilter.Any) or (FRequest.Tree = nil) then
    Exit;
  Actual := BaseType(ASymbol.TypeName);
  Expected := BaseType(FExpected);
  EnumType := '';
  if Actual.StartsWith('enum:') then
  begin
    EnumType := FRequest.Resolver.UnqualifyType(Copy(Actual, 6, MaxInt), FOwnUnit);
    Actual := '';
  end;
  if Expected.StartsWith('enum:') then
    Exit;
  Helper := FRequest.Settings.TypeConversion = TCompletionTypeConversion.Helper;
  // Eingesetzt wird die ganze Kette: "Lines.Cou" → "IntToStr(Lines.Count)"; gezeigt nur der Name.
  if FContext.Kind = TCompletionContextKind.Member then
  begin
    Start := FContext.ChainStart;
    Expression := Copy(FRequest.Text, FRequest.OffsetAt(Start) + 1,
      FRequest.OffsetAt(FContext.DotPos) - FRequest.OffsetAt(Start)) + '.' + AName;
  end
  else
  begin
    Start := TTextPosition.Create(FRequest.Position.Line, FRequest.Position.Character - Length(FContext.Prefix));
    Expression := AName;
  end;
  if (Start.Character < 0) or not TypeConversion(Actual, Expected, EnumType, Expression, Helper, Converted) then
    Exit;
  if Converted.Lossy then
  begin
    AOriginal.Item.Lossy := ASymbol.TypeName;
    Exit;
  end;
  TypeConversion(Actual, Expected, EnumType, AName, Helper, Display);
  Shown := Display.Text;
  AConverted := AOriginal;
  AConverted.Item.Name := Shown;
  AConverted.Item.FilterText := AName;
  AConverted.Item.Conversion := FExpected;
  AConverted.Item.ConvertFrom := AName;
  AConverted.Item.Overloads := nil;
  AConverted.Item.HasParameters := False;
  AConverted.Item.HasTextEdit := True;
  AConverted.Item.TextEdit := TRuleEdit.Create(TTextRange.Create(Start, FRequest.Position), Converted.Text);
  // Benötigte Units wie bei #180.
  if not FUsedReady then
  begin
    FUsed := TUsesClauses.UsedUnits(FRequest.Tree.Tokens);
    FUsedReady := True;
  end;
  for UnitName in Converted.Units do
    if not TUsesClauses.IsUsed(FUsed, UnitName, FRequest.Resolver.Namespaces) and
      not TUsesClauses.IsUsed(FUsed, UnitName, ['System']) and
      TUsesClauses.AddUnit(FRequest.Tree.Tokens, FContext.Offset, UnitName, #13#10, Edit) then
      AConverted.Item.AdditionalEdits := AConverted.Item.AdditionalEdits + [Edit];
  Result := True;
end;

function TCompletionCollector.ScopeOf(const AMember: TResolvedSymbol; out AUnitName: string): Integer;
begin
  AUnitName := '';
  // Bereichsstufe nur im Gültigkeitsbereich, nicht nach einem Punkt (#488).
  Result := 0;
  if (FContext.Kind <> TCompletionContextKind.Scope) or (AMember.Name = '') then
    Exit;
  if AMember.WithOrigin <> '' then
  begin
    // Mitglied eines with-Objekts (#481), auch wenn es zur eigenen Klasse gehört (with Self do); abgeschaltet
    // ohne Angabe statt einer falschen.
    if FRequest.Settings.WithOrigin then
      Result := 6;
  end
  else if AMember.Kind = TResolvedKind.Local then
  begin
    if AMember.IsParameter then
      Result := 2
    else
      Result := 1;
  end
  else if AMember.Container <> '' then
    Result := 3
  else if (FOwnUnit <> '') and SameText(AMember.UnitName, FOwnUnit) then
    Result := 4
  else
  begin
    Result := 5;
    AUnitName := AMember.UnitName;
  end;
end;

function TCompletionCollector.Add(const AName, ADetail: string; AKind: Integer;
  const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := Add(AName, ADetail, AKind, 0, ASymbol, nil);
end;

function TCompletionCollector.Add(const AName, ADetail: string; AKind, APenalty: Integer;
  const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := Add(AName, ADetail, AKind, APenalty, ASymbol, nil);
end;

function TCompletionCollector.Add(const AName, ADetail: string; AKind, APenalty: Integer;
  const ASymbol: TResolvedSymbol; const AEdits: TArray<TRuleEdit>): Boolean;
var
  Scored, Converted: TScoredItem;
  Range: TTextRange;
  Params, UnitName, Binding: string;
begin
  // Jeder Eintrag frisch (Code-Review S-01): Nichts bleibt vom vorigen stehen, z. B. HasTextEdit und TextEdit
  // (im Plugin löschte das alles bis zum Wort).
  Scored := Default(TScoredItem);
  Scored.Score := MatchScore(AName, FContext.Prefix, FRequest.Matching);
  if Scored.Score = TFuzzyMatch.NoMatch then
    Exit(False);
  Dec(Scored.Score, APenalty);
  Scored.Item.Name := AName;
  // Der Index führt Namen ohne Escape-&; reservierte Wörter und &-Namen brauchen es im Quelltext (#1137).
  if (ASymbol.Name <> '') and (TPascalLexer.SourceName(AName) <> AName) then
    Scored.Item.InsertText := TPascalLexer.SourceName(AName);
  Scored.Item.AdditionalEdits := AEdits;
  // Gebundene Typparameter (#450): FItems: TObjectList<TKunde> zeigt Add(const Value: TKunde), ohne Unit davor.
  for Binding in ASymbol.Bindings do
    Scored.Item.Bindings := Scored.Item.Bindings + [Copy(Binding, 1, Pos('=', Binding)) +
      FRequest.Resolver.UnqualifyType(Copy(Binding, Pos('=', Binding) + 1, MaxInt), FOwnUnit)];
  Scored.Item.Detail := TInterfaceStubs.SubstituteWords(ADetail, Scored.Item.Bindings);
  Scored.Item.Kind := AKind;
  // Wo die Deklaration steht, für completionItem/resolve.
  Scored.Item.SourceFile := ASymbol.FileName;
  Scored.Item.SourcePosition := ASymbol.SelectionRange.StartPos;
  Scored.Item.Container := ASymbol.Container;
  Scored.Item.Depth := ASymbol.Depth;
  Scored.Item.IsHelper := ASymbol.IsHelper;
  Scored.Item.HasParameters := ASymbol.MaxArgs > 0;
  Scored.Item.Condition := ASymbol.Condition;
  Scored.Item.VariantBranch := ASymbol.VariantBranch;
  Scored.Item.Scope := ScopeOf(ASymbol, UnitName);
  Scored.Item.UnitName := UnitName;
  Scored.Item.Hides := ASymbol.Hides;
  if Scored.Item.Scope = 6 then
  begin
    Scored.Item.WithOrigin := ASymbol.WithOrigin;
    Scored.Item.WithShadows := ASymbol.WithShadows;
  end;
  for Params in ASymbol.VariantParams do
    if Params <> '' then
      Scored.Item.HasParameters := True;
  for Range in ASymbol.Overloads do
    Scored.Item.Overloads := Scored.Item.Overloads + [Range.StartPos];
  // Der Editor filtert selbst nach dem getippten Wort; unscharfe Treffer bekommen es
  // als filterText, damit er sie nicht verwirft.
  if (FRequest.Matching = TCompletionMatching.Fuzzy) and not AName.StartsWith(FContext.Prefix, True) then
    Scored.Item.FilterText := FContext.Prefix;
  // Erwarteter Typ (#417): Atlas gruppiert nach Fits.
  Scored.Item.Expected := FExpected;
  Scored.Item.Fits := (FExpected <> '') and (ASymbol.Name <> '') and MemberFits(ASymbol);
  if Scored.Item.Fits then
    FAnyFits := True;
  // Typkonvertierung (#490): Umwandlung direkt vor dem Original, das mit seinem Typ wählbar bleibt.
  if not Scored.Item.Fits and Conversion(AName, ASymbol, Scored, Converted) then
  begin
    Converted.Order := FList.Count;
    FList.Add(Converted);
  end;
  Scored.Order := FList.Count;
  FList.Add(Scored);
  Result := True;
end;

procedure TCompletionCollector.AddItem(const AItem: TCompletionItem; AScore: Integer);
var
  Scored: TScoredItem;
begin
  Scored := Default(TScoredItem);
  Scored.Item := AItem;
  Scored.Score := AScore;
  Scored.Order := FList.Count;
  FList.Add(Scored);
end;

procedure TCompletionCollector.MarkLastUnavailable;
var
  Scored: TScoredItem;
begin
  if FList.Count = 0 then
    Exit;
  Scored := FList[FList.Count - 1];
  Scored.Item.Unavailable := True;
  FList[FList.Count - 1] := Scored;
end;

/// <summary>Einträge aus der eigenen Datei: Der Baum des Editors kennt keine {$IFDEF}-Zweige.
/// Bedingung und Verfügbarkeit kommen aus dem Index dieser Unit, der mit Präprozessor gelesen ist (#476).</summary>
procedure TCompletionCollector.MarkOwnConditions;
var
  Own: TUnitIndex;
  Conditions: TDictionary<string, string>;
  Missing: TDictionary<string, string>;
  Symbol: TIndexSymbol;
  Index: Integer;
  Condition: string;
  Scored: TScoredItem;
begin
  if (FRequest.Index = nil) or not FRequest.Index.FindFile(FRequest.FileName, Own) then
    Exit;
  Conditions := TDictionary<string, string>.Create;
  Missing := TDictionary<string, string>.Create;
  try
    for Symbol in Own.Symbols do
      if (Symbol.Container = '') and (Symbol.Condition <> '') then
        Conditions.AddOrSetValue(UpperCase(Symbol.Name), Symbol.Condition);
    for Symbol in Own.Unavailable do
      if Symbol.Container = '' then
        Missing.AddOrSetValue(UpperCase(Symbol.Name), Symbol.Condition);
    if (Conditions.Count = 0) and (Missing.Count = 0) then
      Exit;
    for Index := 0 to FList.Count - 1 do
    begin
      Scored := FList[Index];
      // Nur Einträge aus dieser Datei; gleichnamige aus anderen Units bleiben unberührt.
      if (Scored.Item.Condition <> '') or ((Scored.Item.SourceFile <> '') and
        not SameText(Scored.Item.SourceFile, FRequest.FileName)) then
        Continue;
      if Missing.TryGetValue(UpperCase(Scored.Item.Name), Condition) then
      begin
        Scored.Item.Condition := Condition;
        Scored.Item.Unavailable := True;
        // Wie die übrigen nicht verfügbaren Einträge ans Ende.
        Dec(Scored.Score, PenaltyUnavailable);
      end
      else if Conditions.TryGetValue(UpperCase(Scored.Item.Name), Condition) then
        Scored.Item.Condition := Condition
      else
        Continue;
      FList[Index] := Scored;
    end;
  finally
    Missing.Free;
    Conditions.Free;
  end;
end;

/// <summary>Namen der Liste und der schon gesendeten Einträge, groß geschrieben. Der Aufrufer gibt frei.
/// </summary>
function TCompletionCollector.KnownNames: TDictionary<string, Boolean>;
var
  Existing: TScoredItem;
  Name: string;
begin
  Result := TDictionary<string, Boolean>.Create;
  for Existing in FList do
    Result.AddOrSetValue(UpperCase(Existing.Item.Name), True);
  for Name in FSentNames.Keys do
    Result.AddOrSetValue(Name, True);
end;

procedure TCompletionCollector.AddUnavailable;
var
  Known: TDictionary<string, Boolean>;
  Used: TArray<string>;
  Own: string;
  UnitInfo: TUnitIndex;
  Symbol: TIndexSymbol;
  Member: TResolvedSymbol;
begin
  Known := KnownNames;
  try
    Used := TUsesClauses.UsedUnits(FRequest.Tree.Tokens);
    Own := TUsesClauses.OwnName(FRequest.Tree.Tokens);
    for UnitInfo in FRequest.Index.UnavailableUnits do
    begin
      if Length(UnitInfo.Unavailable) = 0 then
        Continue;
      if not SameText(UnitInfo.UnitName, Own) and
        not TUsesClauses.IsUsed(Used, UnitInfo.UnitName, FRequest.Resolver.Namespaces) then
        Continue;
      for Symbol in UnitInfo.Unavailable do
      begin
        // Mitglieder nicht geltender Zweige zeigt AddUnavailableMembers hinter "Objekt.".
        if (Symbol.Container <> '') or (not Symbol.InInterface and not SameText(UnitInfo.UnitName, Own)) or
          Known.ContainsKey(UpperCase(Symbol.Name)) or
          ((FContext.Filter = TCompletionFilter.Types) and not (Symbol.Kind in IndexTypeKinds)) then
          Continue;
        Member := Default(TResolvedSymbol);
        Member.Name := Symbol.Name;
        Member.Condition := Symbol.Condition;
        Member.FileName := UnitInfo.FileName;
        Member.SelectionRange.StartPos := Symbol.SelectionRange.StartPos;
        if Add(Symbol.Name, UnitInfo.UnitName, CompletionKindOf(Symbol.Kind), PenaltyUnavailable, Member) then
        begin
          MarkLastUnavailable;
          Known.AddOrSetValue(UpperCase(Symbol.Name), True);
        end;
      end;
    end;
  finally
    Known.Free;
  end;
end;

procedure TCompletionCollector.AddFromOtherUnits;
begin
  AddImports(nil);
end;

procedure TCompletionCollector.AddFromOtherUnits(const ANames: TArray<string>);
var
  Wanted: TDictionary<string, Boolean>;
  Name: string;
begin
  Wanted := TDictionary<string, Boolean>.Create;
  try
    for Name in ANames do
      Wanted.AddOrSetValue(UpperCase(Name), True);
    AddImports(Wanted);
  finally
    Wanted.Free;
  end;
end;

procedure TCompletionCollector.AddImports(AWanted: TDictionary<string, Boolean>);
var
  Known: TDictionary<string, Boolean>;
  Used: TArray<string>;
  Own: string;
  UnitInfo: TUnitIndex;
  Symbol: TIndexSymbol;
  Edit: TRuleEdit;
  Added: Integer;
  Names: TImportNameIndex;
  Entry: TImportNameEntry;
  QueryMask: UInt64;
  // Je Unit: 0 = noch nicht geprüft, 1 = überspringen (eigene oder schon eingebunden), 2 = vorschlagen.
  UnitState: TArray<Byte>;
  Member: TResolvedSymbol;
  Penalty: Integer;
begin
  Known := KnownNames;
  try
    Used := TUsesClauses.UsedUnits(FRequest.Tree.Tokens);
    Own := TUsesClauses.OwnName(FRequest.Tree.Tokens);
    Added := 0;
    // Projekt-Units vor der Bibliothek: Sonst füllen RTL/VCL die Höchstzahl, bevor eine
    // gerade getippte Klasse aus dem eigenen Projekt drankommt (#492). Der Namensindex (#617)
    // ist schon so sortiert und enthält nur importierbare Symbole; die Zeichenmaske spart den
    // unscharfen Vergleich für fast alle Namen.
    Names := TImportNames.Current(FRequest.Index);
    QueryMask := TImportNameIndex.MaskOf(FContext.Prefix);
    UnitState := nil;
    SetLength(UnitState, Length(Names.Units));
    for Entry in Names.Entries do
    begin
      if not TImportNameIndex.MayMatch(Entry.Mask, QueryMask) then
        Continue;
      if UnitState[Entry.UnitPos] = 0 then
      begin
        UnitInfo := Names.Units[Entry.UnitPos];
        if SameText(UnitInfo.UnitName, Own) or
          TUsesClauses.IsUsed(Used, UnitInfo.UnitName, FRequest.Resolver.Namespaces) then
          UnitState[Entry.UnitPos] := 1
        else
          UnitState[Entry.UnitPos] := 2;
      end;
      if UnitState[Entry.UnitPos] = 1 then
        Continue;
      UnitInfo := Names.Units[Entry.UnitPos];
      Symbol := UnitInfo.Symbols[Entry.SymbolPos];
      if ((AWanted <> nil) and not AWanted.ContainsKey(UpperCase(Symbol.Name))) or
        Known.ContainsKey(UpperCase(Symbol.Name)) or
        ((FContext.Filter = TCompletionFilter.Types) and not (Symbol.Kind in IndexTypeKinds)) then
        Continue;
      if MatchScore(Symbol.Name, FContext.Prefix, FRequest.Matching) = TFuzzyMatch.NoMatch then
        Continue;
      if Assigned(FAdmit) and not FAdmit(FRequest.Resolver.SymbolFrom(UnitInfo, Symbol)) then
        Continue;
      // Fest #13#10 wie bisher (eigener Befund: uses-Eintrag in LF-Dateien, siehe CHANGELOG).
      if not TUsesClauses.AddUnit(FRequest.Tree.Tokens, FContext.Offset, UnitInfo.UnitName, #13#10, Edit) then
        Exit;
      // Merkmale und Quelle aus dem Indexsymbol (sonst fehlten z. B. die Klammern bei ShowMessage aus
      // Vcl.Dialogs).
      Member := Default(TResolvedSymbol);
      Member.Name := Symbol.Name;
      Member.MinArgs := Symbol.MinArgs;
      Member.MaxArgs := Symbol.MaxArgs;
      Member.FileName := UnitInfo.FileName;
      Member.SelectionRange.StartPos := Symbol.SelectionRange.StartPos;
      // Eingebundenes zuerst, dann Projekt-Units, dann RTL/VCL und andere Bibliotheken.
      if UnitInfo.Library_ then
        Penalty := PenaltyLibraryImport
      else
        Penalty := PenaltyProjectImport;
      // Gleichnamige Symbole verschiedener Units bleiben alle wählbar.
      if Add(Symbol.Name, UnitInfo.UnitName + ' (uses ergänzen)', CompletionKindOf(Symbol.Kind), Penalty, Member,
        [Edit]) then
      begin
        Inc(Added);
        if Added >= CompletionMaxImportItems then
        begin
          FImportsCapped := True;
          Exit;
        end;
      end;
    end;
  finally
    Known.Free;
  end;
end;

procedure TCompletionCollector.AddSameNameVariants;
type
  TVariant = record
    Active: Integer;
    UnitInfo: TUnitIndex;
    Symbol: TIndexSymbol;
  end;
const
  /// <summary>Platz für Varianten in der Reihenfolge hinter jedem Eintrag.</summary>
  VariantSlots = 1000;
var
  Count: Integer;
  Active: TDictionary<string, Integer>;
  Variants: TList<TVariant>;
  Variant: TVariant;
  Units, Hidden: TArray<TArray<string>>;
  Names: TImportNameIndex;
  Entry: TImportNameEntry;
  Used: TArray<string>;
  Own, Key, Mode, Text: string;
  QueryMask: UInt64;
  Index, Position: Integer;
  Scored: TScoredItem;
  Member: TResolvedSymbol;
  Edits, Moved: TArray<TRuleEdit>;
  Edit: TRuleEdit;
  IsUsed_, Movable: Boolean;
  Range: TTextRange;
begin
  Count := 0;
  if not FRequest.Settings.SameNameVariants or (FContext.Kind <> TCompletionContextKind.Scope) or
    (FRequest.Tree = nil) or (FRequest.Index = nil) then
    Exit;
  Active := TDictionary<string, Integer>.Create;
  Variants := TList<TVariant>.Create;
  try
    // Aktiv ist, was die Namensauflösung aus den uses brachte (letzte Unit gewinnt).
    for Index := 0 to FList.Count - 1 do
      if (FList[Index].Item.Scope = 5) and (FList[Index].Item.UnitName <> '') and (FList[Index].Item.Action = '') and
        not FList[Index].Item.Unavailable and (FList[Index].Item.Conversion = '') then
        Active.AddOrSetValue(UpperCase(FList[Index].Item.Name), Index);
    if Active.Count = 0 then
      Exit;
    Own := TUsesClauses.OwnName(FRequest.Tree.Tokens);
    Names := TImportNames.Current(FRequest.Index);
    QueryMask := TImportNameIndex.MaskOf(FContext.Prefix);
    SetLength(Units, FList.Count);
    SetLength(Hidden, FList.Count);
    for Entry in Names.Entries do
    begin
      if not TImportNameIndex.MayMatch(Entry.Mask, QueryMask) then
        Continue;
      Variant.Symbol := Names.Units[Entry.UnitPos].Symbols[Entry.SymbolPos];
      if not Active.TryGetValue(UpperCase(Variant.Symbol.Name), Variant.Active) then
        Continue;
      Variant.UnitInfo := Names.Units[Entry.UnitPos];
      if Variant.Symbol.Unavailable or SameText(Variant.UnitInfo.UnitName, Own) or
        SameText(Variant.UnitInfo.UnitName, FList[Variant.Active].Item.UnitName) or
        MatchText(Variant.UnitInfo.UnitName, Units[Variant.Active]) or
        ((FContext.Filter = TCompletionFilter.Types) and not (Variant.Symbol.Kind in IndexTypeKinds)) then
        Continue;
      if TCompletionSameNames.IsFmx(Variant.UnitInfo.UnitName) and not FRequest.Settings.ShowFmxUnits then
      begin
        Text := Variant.UnitInfo.UnitName + '.' + Variant.Symbol.Name;
        if not MatchText(Text, Hidden[Variant.Active]) then
          Hidden[Variant.Active] := Hidden[Variant.Active] + [Text];
        Continue;
      end;
      Units[Variant.Active] := Units[Variant.Active] + [Variant.UnitInfo.UnitName];
      Variants.Add(Variant);
    end;
    // Die aktive Variante nennt alle Units, die den Namen deklarieren.
    for Index := 0 to FList.Count - 1 do
      if (Length(Units[Index]) > 0) or (Length(Hidden[Index]) > 0) then
      begin
        Scored := FList[Index];
        Scored.Item.SameNameActive := True;
        Scored.Item.SameNameUnits := [Scored.Item.UnitName] + Units[Index];
        Scored.Item.SameNameHidden := Hidden[Index];
        FList[Index] := Scored;
      end;
    Used := TUsesClauses.UsedUnits(FRequest.Tree.Tokens);
    Range := TTextRange.Create(FRequest.Position.Line, FRequest.Position.Character - Length(FContext.Prefix),
      FRequest.Position.Line, FRequest.Position.Character);
    for Variant in Variants do
    begin
      Key := FList[Variant.Active].Item.UnitName;
      IsUsed_ := TUsesClauses.IsUsed(Used, Variant.UnitInfo.UnitName, FRequest.Resolver.Namespaces);
      Movable := IsUsed_ and TCompletionSameNames.MoveToEnd(FRequest.Tree.Tokens, Variant.UnitInfo.UnitName, Key,
        FRequest.Resolver.Namespaces, Moved);
      Mode := TCompletionSameNames.InsertMode(FRequest.Settings.SameNameInsert, IsUsed_, Movable);
      Edits := nil;
      if Mode = TCompletionSameNames.InsertMove then
        Edits := Moved
      else if (Mode = TCompletionSameNames.InsertAdd) or (Mode = TCompletionSameNames.InsertPrefixAdd) then
      begin
        if not TUsesClauses.AddUnit(FRequest.Tree.Tokens, FContext.Offset, Variant.UnitInfo.UnitName,
          FRequest.LineBreak, Edit) then
          Continue;
        Edits := [Edit];
      end;
      Member := Default(TResolvedSymbol);
      Member.Kind := TResolvedKind.Symbol;
      Member.Name := Variant.Symbol.Name;
      Member.UnitName := Variant.UnitInfo.UnitName;
      Member.MinArgs := Variant.Symbol.MinArgs;
      Member.MaxArgs := Variant.Symbol.MaxArgs;
      Member.FileName := Variant.UnitInfo.FileName;
      Member.SelectionRange.StartPos := Variant.Symbol.SelectionRange.StartPos;
      if not Add(Variant.Symbol.Name, Variant.UnitInfo.UnitName, CompletionKindOf(Variant.Symbol.Kind), 0, Member,
        Edits) then
        Continue;
      // Direkt hinter der aktiven Variante: gleiche Punktzahl, Reihenfolge gleich dahinter (siehe unten).
      Position := FList.Count - 1;
      Scored := FList[Position];
      Scored.Score := FList[Variant.Active].Score;
      Inc(Count);
      Scored.Order := FList[Variant.Active].Order * VariantSlots + Count;
      Scored.Item.SameNameOf := Key;
      Scored.Item.SameNameInsert := Mode;
      Scored.Item.SameNameUnits := FList[Variant.Active].Item.SameNameUnits;
      Scored.Item.SameNameHidden := FList[Variant.Active].Item.SameNameHidden;
      if Scored.Item.FilterText = '' then
        Scored.Item.FilterText := Variant.Symbol.Name;
      if (Mode = TCompletionSameNames.InsertPrefix) or (Mode = TCompletionSameNames.InsertPrefixAdd) then
      begin
        Scored.Item.HasTextEdit := True;
        Scored.Item.TextEdit := TRuleEdit.Create(Range, Variant.UnitInfo.UnitName + '.' + Variant.Symbol.Name);
      end;
      // Kein uses-Eintrag im Sinne von #180: Atlas soll die Edits nicht als „+ Unit“ zeigen.
      Scored.Item.Action := 'sameName';
      FList[Position] := Scored;
    end;
  finally
    // Die übrigen behalten ihre Reihenfolge, mit Platz für die Varianten dahinter.
    if Count > 0 then
      for Index := 0 to FList.Count - 1 do
        if FList[Index].Item.SameNameOf = '' then
        begin
          Scored := FList[Index];
          Scored.Order := Scored.Order * VariantSlots;
          FList[Index] := Scored;
        end;
    Variants.Free;
    Active.Free;
  end;
end;

procedure TCompletionCollector.AddHelpersFromOtherUnits(const ATypes: TArray<TResolvedSymbol>);
var
  Known: TDictionary<string, Boolean>;
  Used: TArray<string>;
  Own: string;
  Names: TImportNameIndex;
  Entry: TImportNameEntry;
  UnitInfo: TUnitIndex;
  Helper: TIndexSymbol;
  Edit: TRuleEdit;
  Member: TResolvedSymbol;
  Depth, Position, Penalty: Integer;
begin
  if Length(ATypes) = 0 then
    Exit;
  Known := KnownNames;
  try
    Used := TUsesClauses.UsedUnits(FRequest.Tree.Tokens);
    Own := TUsesClauses.OwnName(FRequest.Tree.Tokens);
    Names := TImportNames.Current(FRequest.Index);
    for Entry in Names.Helpers do
    begin
      UnitInfo := Names.Units[Entry.UnitPos];
      if SameText(UnitInfo.UnitName, Own) or TUsesClauses.IsUsed(Used, UnitInfo.UnitName,
        FRequest.Resolver.Namespaces) or TUsesClauses.IsUsed(Used, UnitInfo.UnitName, ['System']) then
        Continue;
      Helper := UnitInfo.Symbols[Entry.SymbolPos];
      Depth := -1;
      for Position := 0 to High(ATypes) do
        if TNameResolver.HelperTargets(Helper.Ancestors[High(Helper.Ancestors)], ATypes[Position]) then
        begin
          Depth := Position;
          Break;
        end;
      if Depth < 0 then
        Continue;
      if not TUsesClauses.AddUnit(FRequest.Tree.Tokens, FContext.Offset, UnitInfo.UnitName, #13#10, Edit) then
        Exit;
      if UnitInfo.Library_ then
        Penalty := PenaltyLibraryImport
      else
        Penalty := PenaltyProjectImport;
      for Position := 0 to High(UnitInfo.Symbols) do
      begin
        if not SameText(UnitInfo.Symbols[Position].Container, Helper.Name) or
          not (UnitInfo.Symbols[Position].Visibility in [TIndexVisibility.Public, TIndexVisibility.Published]) or
          Known.ContainsKey(UpperCase(UnitInfo.Symbols[Position].Name)) then
          Continue;
        if (FContext.Prefix <> '') and (MatchScore(UnitInfo.Symbols[Position].Name, FContext.Prefix,
          FRequest.Matching) = TFuzzyMatch.NoMatch) then
          Continue;
        Member := FRequest.Resolver.SymbolFrom(UnitInfo, UnitInfo.Symbols[Position]);
        Member.IsHelper := True;
        Member.Depth := Depth;
        if Add(UnitInfo.Symbols[Position].Name, UnitInfo.UnitName + ' (uses ergänzen)',
          CompletionKindOf(UnitInfo.Symbols[Position].Kind), Penalty, Member, [Edit]) then
          Known.AddOrSetValue(UpperCase(UnitInfo.Symbols[Position].Name), True);
      end;
    end;
  finally
    Known.Free;
  end;
end;

/// <summary>Sortiert die gesammelten Einträge, kürzt auf den Rest von MaxItems und leert die Liste.
/// AStaged: Teilergebnis; dann bleibt Expected stehen, weil spätere Stufen noch passende Einträge bringen
/// können (Atlas gruppiert erst, wenn einer passt).</summary>
function TCompletionCollector.TakeStage(AStaged: Boolean): TArray<TCompletionItem>;
var
  Room, Near, OthersLeft, Kept: Integer;
  Index: Integer;
  Scored: TScoredItem;
begin
  MarkOwnConditions;
  FList.Sort;
  // Passende zuerst (#417); passt nichts, entfällt die Gruppierung.
  if FAnyFits then
  begin
    for Index := 0 to FList.Count - 1 do
    begin
      Scored := FList[Index];
      Scored.Order := Index + IfThen(Scored.Item.Fits, 0, FList.Count);
      FList[Index] := Scored;
    end;
    FList.Sort(TComparer<TScoredItem>.Construct(
      function(const Left, Right: TScoredItem): Integer
      begin
        Result := Left.Order - Right.Order;
      end));
  end
  else if not AStaged then
    for Index := 0 to FList.Count - 1 do
    begin
      Scored := FList[Index];
      Scored.Item.Expected := '';
      FList[Index] := Scored;
    end;
  Room := Max(0, CompletionMaxItems - FSent);
  if FList.Count > Room then
  begin
    FTruncated := True;
    // Nahe Einträge (lokal, Parameter, eigene Mitglieder ohne geerbte, eigene Unit) nie abschneiden: Bei
    // Formularen mit Hunderten geerbten Mitgliedern verdrängten kurze geerbte Namen sonst die eigenen
    // Methoden mit längerem Namen (Rückmeldung 15.10.2026). Die Reihenfolge bleibt.
    Near := 0;
    for Index := 0 to FList.Count - 1 do
      if IsNearItem(FList[Index].Item) then
        Inc(Near);
    OthersLeft := Max(0, Room - Near);
    Kept := 0;
    for Index := 0 to FList.Count - 1 do
    begin
      Scored := FList[Index];
      if IsNearItem(Scored.Item) then
      begin
        if Kept >= Room then
          Continue;
      end
      else if OthersLeft > 0 then
        Dec(OthersLeft)
      else
        Continue;
      FList[Kept] := Scored;
      Inc(Kept);
    end;
    FList.Count := Kept;
  end;
  Result := nil;
  SetLength(Result, FList.Count);
  for Index := 0 to FList.Count - 1 do
  begin
    Result[Index] := FList[Index].Item;
    FSentNames.AddOrSetValue(UpperCase(FList[Index].Item.Name), True);
  end;
  Inc(FSent, FList.Count);
  FList.Clear;
end;

procedure TCompletionCollector.SendStage;
var
  Items: TArray<TCompletionItem>;
begin
  if not Assigned(FOnPartial) or (FList.Count = 0) then
    Exit;
  Items := TakeStage(True);
  if Length(Items) > 0 then
    FOnPartial(Items);
end;

procedure TCompletionCollector.SetNameFilter(AOn: Boolean);
begin
  if AOn and (FContext.Prefix <> '') then
    FRequest.Resolver.NameFilter := PrefixFilter(FContext.Prefix, FRequest.Matching)
  else
    FRequest.Resolver.NameFilter := nil;
end;

procedure TCompletionCollector.MarkUsedShadows;
var
  Names: TDictionary<string, Integer>;
  Shadows: TArray<TResolvedSymbol>;
  Shadow: TResolvedSymbol;
  Index: Integer;
  Text: string;
  Scored: TScoredItem;
begin
  Names := TDictionary<string, Integer>.Create;
  try
    for Index := 0 to FList.Count - 1 do
      if ((FList[Index].Item.Scope >= 1) and (FList[Index].Item.Scope <= 4)) or (FList[Index].Item.Scope = 6) then
        Names.AddOrSetValue(UpperCase(FList[Index].Item.Name), Index);
    if Names.Count = 0 then
      Exit;
    FRequest.Resolver.NameFilter :=
      function(const AName: string): Boolean
      begin
        Result := Names.ContainsKey(UpperCase(AName));
      end;
    try
      Shadows := FRequest.Resolver.UsedScopeShadows;
    finally
      FRequest.Resolver.NameFilter := nil;
    end;
    for Shadow in Shadows do
      if Names.TryGetValue(UpperCase(Shadow.Name), Index) then
      begin
        Scored := FList[Index];
        Text := TNameResolver.ShadowText(Shadow);
        if not MatchText(Text, Scored.Item.Hides) then
        begin
          Scored.Item.Hides := Scored.Item.Hides + [Text];
          FList[Index] := Scored;
        end;
      end;
  finally
    Names.Free;
  end;
end;

procedure TCompletionCollector.AddKeywords(const AWords: TArray<string>);
var
  Word: string;
begin
  for Word in AWords do
    Add(Word, '', KindKeyword, PenaltyKeyword, Default(TResolvedSymbol));
end;

procedure TCompletionCollector.AddUnavailableMembers(const AMembers: TArray<TResolvedSymbol>);
var
  Containers, Known: TDictionary<string, Boolean>;
  Candidate, Member: TResolvedSymbol;
  UnitInfo: TUnitIndex;
  Symbol: TIndexSymbol;
  Existing: TScoredItem;
begin
  Containers := TDictionary<string, Boolean>.Create;
  Known := TDictionary<string, Boolean>.Create;
  try
    for Candidate in AMembers do
      if Candidate.Container <> '' then
        Containers.AddOrSetValue(UpperCase(Candidate.Container), True);
    if Containers.Count = 0 then
      Exit;
    for Existing in FList do
      Known.AddOrSetValue(UpperCase(Existing.Item.Name), True);
    for UnitInfo in FRequest.Index.UnavailableUnits do
      for Symbol in UnitInfo.Unavailable do
      begin
        if (Symbol.Container = '') or not Containers.ContainsKey(UpperCase(Symbol.Container)) or
          Known.ContainsKey(UpperCase(Symbol.Name)) then
          Continue;
        Member := Default(TResolvedSymbol);
        Member.Name := Symbol.Name;
        Member.Container := Symbol.Container;
        Member.Condition := Symbol.Condition;
        Member.FileName := UnitInfo.FileName;
        Member.SelectionRange.StartPos := Symbol.SelectionRange.StartPos;
        if Add(Symbol.Name, Symbol.Container, CompletionKindOf(Symbol.Kind), PenaltyUnavailable, Member) then
        begin
          MarkLastUnavailable;
          Known.AddOrSetValue(UpperCase(Symbol.Name), True);
        end;
      end;
  finally
    Known.Free;
    Containers.Free;
  end;
end;

procedure TCompletionCollector.SetAdmit(const AAdmit: TCompletionAdmitFunc);
begin
  FAdmit := AAdmit;
end;

procedure TCompletionCollector.AddCandidates(const ACandidates: TArray<TResolvedSymbol>);
var
  Candidate: TResolvedSymbol;
begin
  for Candidate in ACandidates do
  begin
    // Typposition (#31): nur Typen.
    if (FContext.Filter = TCompletionFilter.Types) and not Candidate.IsType then
      Continue;
    if Assigned(FAdmit) and not FAdmit(Candidate) then
      Continue;
    if Candidate.TypeName <> '' then
      Add(Candidate.Name, Candidate.TypeName, CompletionKindOf(Candidate.SymbolKind), Candidate)
    else if Candidate.Container <> '' then
      Add(Candidate.Name, Candidate.Container, CompletionKindOf(Candidate.SymbolKind), Candidate)
    else
      Add(Candidate.Name, Candidate.UnitName, CompletionKindOf(Candidate.SymbolKind), Candidate);
  end;
end;

function TCompletionCollector.Finish(out AIncomplete: Boolean): TArray<TCompletionItem>;
begin
  Result := TakeStage(FSent > 0);
  AIncomplete := FTruncated or FImportsCapped or
    ((FContext.Kind = TCompletionContextKind.Scope) and (Length(FContext.Prefix) < CompletionMinImportPrefix));
end;

end.
