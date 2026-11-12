unit Atlas.Common.Lsp.CompletionCollector;

// Sammler der allgemeinen Vervollständigung: vorher 13
// verschachtelte Routinen in TCompletionLists.Collect mit 18 geteilten Variablen. Jeder Eintrag entsteht aus
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
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest;

const
  // CompletionItemKind
  cKindMethod = 2;
  cKindFunction = 3;
  cKindConstructor = 4;
  cKindField = 5;
  cKindVariable = 6;
  cKindClass = 7;
  cKindInterface = 8;
  cKindModule = 9;
  cKindProperty = 10;
  cKindEnum = 13;
  cKindEnumMember = 20;
  cKindConstant = 21;
  cKindStruct = 22;
  cKindKeyword = 14;
  cKindSnippet = 15;
  /// <summary>Abzüge vom Trefferwert, die die Gruppenreihenfolge festlegen: eingebunden vor
  /// Schlüsselwörtern vor Projekt-Import vor Bibliotheks-Import vor nicht verfügbaren Einträgen.</summary>
  cPenaltyKeyword = 50;
  cPenaltyProjectImport = 100;
  cPenaltyLibraryImport = 200;
  cPenaltyUnavailable = 500;
  /// <summary>Typen im Index (#31: Filter nach "class(", ":", "is", "as").</summary>
  cIndexTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];
  /// <summary>Höchstzahl der Einträge einer Antwort (TLspCompletion.cMaxItems).</summary>
  cCompletionMaxItems = 1000;
  /// <summary>Höchstzahl der Vorschläge aus nicht eingebundenen Units (TLspCompletion.cMaxImportItems).</summary>
  cCompletionMaxImportItems = 200;
  /// <summary>So viele Zeichen muss der Name haben, bevor nicht eingebundene Units mitsuchen.</summary>
  cCompletionMinImportPrefix = 2;

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
    function TakeStage(AStaged: Boolean): TArray<TCompletionItem>;
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
    /// <summary>Typen aus den Packages der IDE (TCompletionRequest.IdeTypes), die weder die Liste noch der Index
    /// bringt: aus eingebundenen Units ohne Quelltext direkt, sonst mit uses-Eintrag wie Bibliotheks-Importe.
    /// Ohne Vorfilter (SetAdmit), denn die Art des Typs ist unbekannt.</summary>
    procedure AddIdeTypes;
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
/// <summary>Punktzahl von AName; TFuzzyMatch.cNoMatch, wenn er nicht passt.</summary>
function MatchScore(const AName, APrefix: string; AMatching: TCompletionMatching): Integer;
/// <summary>Vorfilter des Resolvers (#616): nur Namen, die zu APrefix passen. GetEnumerator bleibt, weil die
/// Postfix-Vorlagen daran erkennen, ob der Typ aufzählbar ist; Add verwirft ihn ohne Treffer wieder.</summary>
function PrefixFilter(const APrefix: string; AMatching: TCompletionMatching): TCandidateNameFilter;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.IdeTypes,
  System.Math,
  System.StrUtils,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.NameIndex,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Lsp.CompletionSameNames,
  Atlas.Text.Fuzzy,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TCompletionCollectorText = (AddToUses);

const
  cTexts: array[TCompletionCollectorText] of TAtlasText = (
    (De: ' (uses ergänzen)'; En: ' (add to uses)'));

const
  // Kürzel über Wortanfänge (#882): zwischen Anfang (TFuzzyMatch, ab etwa 3000) und Teilwort (höchstens
  // 2499 mit Wortanfang-Zuschlag), wie im Plugin (TAtlasCompletionMatcher: Anfang vor Kürzel vor Teilwort).
  cWordStartsScore = 2600;

function CompletionKindOf(AKind: TIndexSymbolKind): Integer;
begin
  case AKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.HelperType, TIndexSymbolKind.TypeAlias:
      Result := cKindClass;
    TIndexSymbolKind.RecordType:
      Result := cKindStruct;
    TIndexSymbolKind.InterfaceType:
      Result := cKindInterface;
    TIndexSymbolKind.EnumType:
      Result := cKindEnum;
    TIndexSymbolKind.EnumMember:
      Result := cKindEnumMember;
    TIndexSymbolKind.Constant:
      Result := cKindConstant;
    TIndexSymbolKind.Field:
      Result := cKindField;
    TIndexSymbolKind.Property_:
      Result := cKindProperty;
    TIndexSymbolKind.Method:
      Result := cKindMethod;
    TIndexSymbolKind.Constructor_:
      Result := cKindConstructor;
    TIndexSymbolKind.Routine:
      Result := cKindFunction;
  else
    Result := cKindVariable;
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
  begin
    Result := Right.Score - Left.Score;
  end
  else
  begin
    Result := Left.Order - Right.Order;
  end;
end;

function PlainType(const AType: string): string;
begin
  Result := LowerCase(AType.Replace(' ', ''));
  if (Pos('<', Result) = 0) and (LastDelimiter('.', Result) > 0) then
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

function TypeFamily(const APlain: string): TTypeFamily;
begin
  if MatchText(APlain, ['integer', 'cardinal', 'int64', 'uint64', 'byte', 'word', 'shortint', 'smallint', 'longint',
    'longword', 'nativeint', 'nativeuint', 'int8', 'int16', 'int32', 'uint8', 'uint16', 'uint32', 'fixedint',
    'fixeduint']) then
  begin
    Result := TTypeFamily.Integer_;
  end
  else if MatchText(APlain, ['double', 'single', 'extended', 'real', 'currency', 'comp']) then
  begin
    Result := TTypeFamily.Float;
  end
  else if MatchText(APlain, ['string', 'unicodestring', 'ansistring', 'widestring', 'shortstring', 'rawbytestring',
    'utf8string']) then
  begin
    Result := TTypeFamily.String_;
  end
  else if MatchText(APlain, ['char', 'widechar', 'ansichar']) then
  begin
    Result := TTypeFamily.Char_;
  end
  else if MatchText(APlain, ['boolean', 'bytebool', 'wordbool', 'longbool']) then
  begin
    Result := TTypeFamily.Boolean_;
  end
  else
  begin
    Result := TTypeFamily.None;
  end;
end;

function TypeFits(const AActual, AExpected: string; out ACheckDescent: Boolean): Boolean;
var
  mActual, mExpected: TTypeFamily;
begin
  ACheckDescent := False;
  if (AActual = '') or (AExpected = '') then
  begin
    Exit(False);
  end;
  if PlainType(AActual) = PlainType(AExpected) then
  begin
    Exit(True);
  end;
  mActual := TypeFamily(PlainType(AActual));
  mExpected := TypeFamily(PlainType(AExpected));
  if mExpected <> TTypeFamily.None then
  begin
    Exit((mActual = mExpected) or (mExpected = TTypeFamily.Float) and (mActual = TTypeFamily.Integer_) or
      (mExpected = TTypeFamily.String_) and (mActual = TTypeFamily.Char_));
  end;
  ACheckDescent := mActual = TTypeFamily.None;
  Result := False;
end;

/// <summary>Umwandlung von AExpression (Typ APlain, Familie AActual) nach string; '' ohne. AHelperText: Helper-Stil,
/// '' ohne; AUnits nur, wenn nicht System.SysUtils.</summary>
function ToStringText(const APlain: string; AActual: TTypeFamily; const AEnumType, AExpression: string;
  out AHelperText: string; out AUnits: TArray<string>): string;
begin
  AHelperText := '';
  AUnits := nil;
  Result := '';
  if AEnumType <> '' then
  begin
    Result := 'GetEnumName(TypeInfo(' + AEnumType + '), Ord(' + AExpression + '))';
    AUnits := ['System.TypInfo'];
  end
  else if APlain = 'tdatetime' then
  begin
    Result := 'DateTimeToStr(' + AExpression + ')';
  end
  else if APlain = 'tdate' then
  begin
    Result := 'DateToStr(' + AExpression + ')';
  end
  else if APlain = 'ttime' then
  begin
    Result := 'TimeToStr(' + AExpression + ')';
  end
  else if AActual in [TTypeFamily.Integer_, TTypeFamily.Float] then
  begin
    Result := 'IntToStr(' + AExpression + ')';
    if AActual = TTypeFamily.Float then
    begin
      Result := 'FloatToStr(' + AExpression + ')';
    end;
    AHelperText := AExpression + '.ToString';
  end
  else if AActual = TTypeFamily.Boolean_ then
  begin
    // Ohne TUseBoolStrs.True liefert der Helper "-1" und "0".
    Result := 'BoolToStr(' + AExpression + ', True)';
    AHelperText := AExpression + '.ToString(TUseBoolStrs.True)';
  end;
end;

/// <summary>Umwandlung von AExpression (string) in die Zahlenfamilie AExpected (Typ APlainExpected); '' ohne.
/// </summary>
function FromStringText(const APlainExpected: string; AExpected: TTypeFamily; const AExpression: string;
  out AHelperText: string): string;
begin
  AHelperText := '';
  Result := '';
  if AExpected = TTypeFamily.Float then
  begin
    Result := 'StrToFloat(' + AExpression + ')';
    AHelperText := AExpression + '.ToDouble';
  end
  else if (AExpected = TTypeFamily.Integer_) and MatchText(APlainExpected, ['int64', 'uint64']) then
  begin
    Result := 'StrToInt64(' + AExpression + ')';
    AHelperText := AExpression + '.ToInt64';
  end
  else if AExpected = TTypeFamily.Integer_ then
  begin
    Result := 'StrToInt(' + AExpression + ')';
    AHelperText := AExpression + '.ToInteger';
  end;
end;

function TypeConversion(const AActual, AExpected, AEnumType, AExpression: string; AHelper: Boolean;
  out AResult: TTypeConversion): Boolean;
var
  mActual, mExpected: TTypeFamily;
  mPlain, mText, mHelper: string;
begin
  AResult := Default(TTypeConversion);
  mPlain := PlainType(AActual);
  mActual := TypeFamily(mPlain);
  mExpected := TypeFamily(PlainType(AExpected));
  mText := '';
  mHelper := '';
  if mExpected = TTypeFamily.String_ then
  begin
    mText := ToStringText(mPlain, mActual, AEnumType, AExpression, mHelper, AResult.Units);
  end
  else if mActual = TTypeFamily.String_ then
  begin
    mText := FromStringText(PlainType(AExpected), mExpected, AExpression, mHelper);
  end
  else if (mActual = TTypeFamily.Float) and (mExpected = TTypeFamily.Integer_) then
  begin
    // Verlustbehaftet: kein Vorschlag, nur der Hinweis.
    AResult.Lossy := True;
    Exit(True);
  end;
  Result := mText <> '';
  if not Result then
  begin
    Exit;
  end;
  AResult.Text := mText;
  if AHelper and (mHelper <> '') then
  begin
    AResult.Text := mHelper;
  end;
  if AResult.Units = nil then
  begin
    AResult.Units := ['System.SysUtils'];
  end;
end;

function MatchScore(const AName, APrefix: string; AMatching: TCompletionMatching): Integer;
begin
  if APrefix = '' then
  begin
    Exit(0);
  end;
  if AMatching = TCompletionMatching.Prefix then
  begin
    if AName.StartsWith(APrefix, True) then
    begin
      Exit(0);
    end;
    Exit(TFuzzyMatch.cNoMatch);
  end;
  Result := TFuzzyMatch.CompletionScore(AName, APrefix);
  // Kürzel ("bs" → btnSave) vor Teilwort und Teilfolge (#882): Sonst fielen sie beim Kürzen auf MaxItems
  // hinter bloße Teilwörter zurück und erschienen erst mit passendem Anfang.
  if (Result <> TFuzzyMatch.cNoMatch) and not AName.StartsWith(APrefix, True) and
    TTextFuzzy.MatchesWordStarts(APrefix, AName) then
  begin
    Result := cWordStartsScore - Min(Length(AName) - Length(APrefix), 99);
  end;
end;

function PrefixFilter(const APrefix: string; AMatching: TCompletionMatching): TCandidateNameFilter;
begin
  Result :=
    function(const AName: string): Boolean
    begin
      Result := (MatchScore(AName, APrefix, AMatching) <> TFuzzyMatch.cNoMatch) or SameText(AName, 'GetEnumerator');
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
  begin
    FOwnUnit := TUsesClauses.OwnName(ARequest.Tree.Tokens);
  end;
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
  mTypeText: string;
  mCheckDescent: Boolean;
begin
  // Typ des Werts: Variablen, Felder, Eigenschaften, Funktionsergebnis; Aufzählungswerte über ihren Typ.
  if AMember.SymbolKind = TIndexSymbolKind.EnumMember then
  begin
    mTypeText := AMember.Container;
  end
  else if AMember.IsType then
  begin
    Exit(False);
  end
  else
  begin
    mTypeText := AMember.TypeName;
  end;
  Result := TypeFits(mTypeText, FExpected, mCheckDescent);
  if Result or not mCheckDescent then
  begin
    Exit;
  end;
  // Klassen: Nachfahr des erwarteten Typs; je Typname einmal auflösen.
  if not FDescends.TryGetValue(LowerCase(mTypeText), Result) then
  begin
    Result := FRequest.Resolver.Queries.TypeDescendsFrom(FRequest.Tree, FRequest.FileName, FContext.Offset, mTypeText,
      FExpected);
    FDescends.Add(LowerCase(mTypeText), Result);
  end;
end;

/// <summary>Eingebauter Typ oder TDateTime/TDate/TTime?</summary>
function KnownBaseType(const AText: string): Boolean;
begin
  Result := (TypeFamily(PlainType(AText)) <> TTypeFamily.None) or
    MatchText(PlainType(AText), ['tdatetime', 'tdate', 'ttime']);
end;

/// <summary>Zieltyp eines Alias ohne das Wort type ("TCaption = type string").</summary>
function AliasTarget(const ASymbol: TResolvedSymbol): string;
begin
  Result := Trim(ASymbol.TypeName);
  if Result.StartsWith('type ', True) then
  begin
    Result := Trim(Copy(Result, 6, MaxInt));
  end;
end;

/// <summary>Typ nach Aliasen bis zu einem eingebauten Typ oder TDateTime (TCaption → string); Aufzählungen mit dem
/// Präfix "enum:". Unbekannte bleiben, wie sie sind. Gemerkt in ACollector.FBaseTypes.</summary>
function BaseTypeOf(ACollector: TCompletionCollector; const AType: string): string;
var
  mCurrent: TResolvedSymbol;
  mDepth: Integer;
begin
  Result := AType;
  if (AType = '') or KnownBaseType(AType) then
  begin
    Exit;
  end;
  // Übliche Aliase der RTL und VCL auch ohne deren Quellen im Index.
  if MatchText(PlainType(AType), ['tcaption', 'tfilename']) then
  begin
    Exit('string');
  end;
  if ACollector.FBaseTypes.TryGetValue(LowerCase(AType), Result) then
  begin
    Exit;
  end;
  Result := AType;
  mCurrent := ACollector.FRequest.Resolver.ResolveChain(ACollector.FRequest.Tree, ACollector.FRequest.FileName,
    AType.Split(['.']), ACollector.FContext.Offset);
  mDepth := 0;
  while mCurrent.Found and mCurrent.IsType and (mDepth < 8) do
  begin
    if mCurrent.SymbolKind = TIndexSymbolKind.EnumType then
    begin
      Result := 'enum:' + AType;
      Break;
    end;
    if (mCurrent.SymbolKind <> TIndexSymbolKind.TypeAlias) or (mCurrent.TypeName = '') then
    begin
      Break;
    end;
    Result := AliasTarget(mCurrent);
    if KnownBaseType(Result) then
    begin
      Break;
    end;
    mCurrent := ACollector.FRequest.Resolver.ResolveChain(ACollector.FRequest.Tree, ACollector.FRequest.FileName,
      Result.Split(['.']), ACollector.FContext.Offset);
    Inc(mDepth);
  end;
  ACollector.FBaseTypes.AddOrSetValue(LowerCase(AType), Result);
end;

/// <summary>Ein Wert ohne Pflichtargumente; keine Typen und Aufzählungswerte.</summary>
function SymbolConvertible(const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := (ASymbol.Name <> '') and not ASymbol.IsType and (ASymbol.SymbolKind <> TIndexSymbolKind.EnumMember) and
    (ASymbol.MinArgs = 0) and (ASymbol.TypeName <> '');
end;

/// <summary>Umwandlungen eingeschaltet, erwarteter Typ bekannt, gewöhnliche Liste mit Baum.</summary>
function ContextConvertible(ACollector: TCompletionCollector): Boolean;
begin
  Result := (ACollector.FRequest.Settings.TypeConversion <> TCompletionTypeConversion.Off) and
    (ACollector.FExpected <> '') and (ACollector.FContext.Filter = TCompletionFilter.Any) and
    (ACollector.FRequest.Tree <> nil);
end;

/// <summary>Eingesetzt wird die ganze Kette: "Lines.Cou" → "IntToStr(Lines.Count)"; AStart ist ihr Anfang.
/// </summary>
function ConversionExpression(ACollector: TCompletionCollector; const AName: string;
  out AStart: TTextPosition): string;
var
  mRequest: TCompletionRequest;
begin
  mRequest := ACollector.FRequest;
  if ACollector.FContext.Kind = TCompletionContextKind.Member then
  begin
    AStart := ACollector.FContext.ChainStart;
    Result := Copy(mRequest.Text, mRequest.OffsetAt(AStart) + 1, mRequest.OffsetAt(ACollector.FContext.DotPos) -
      mRequest.OffsetAt(AStart)) + '.' + AName;
  end
  else
  begin
    AStart := TTextPosition.Create(mRequest.Position.Line, mRequest.Position.Character -
      Length(ACollector.FContext.Prefix));
    Result := AName;
  end;
end;

/// <summary>uses-Einträge für AUnits an AItem, wie bei #180.</summary>
procedure AddConversionUnits(ACollector: TCompletionCollector; const AUnits: TArray<string>;
  var AItem: TCompletionItem);
var
  mUnitName: string;
  mEdit: TRuleEdit;
begin
  if not ACollector.FUsedReady then
  begin
    ACollector.FUsed := TUsesClauses.UsedUnits(ACollector.FRequest.Tree.Tokens);
    ACollector.FUsedReady := True;
  end;
  for mUnitName in AUnits do
  begin
    if not TUsesClauses.IsUsed(ACollector.FUsed, mUnitName, ACollector.FRequest.Resolver.Namespaces) and
      not TUsesClauses.IsUsed(ACollector.FUsed, mUnitName, ['System']) and
      TUsesClauses.AddUnit(ACollector.FRequest.Tree.Tokens, ACollector.FContext.Offset, mUnitName, #13#10, mEdit) then
    begin
      AItem.AdditionalEdits := AItem.AdditionalEdits + [mEdit];
    end;
  end;
end;

/// <summary>Umwandlungseintrag zu AOriginal (#490) bzw. Hinweis Lossy daran; False ohne Umwandlung.</summary>
function ConversionOf(ACollector: TCompletionCollector; const AName: string; const ASymbol: TResolvedSymbol;
  var AOriginal: TScoredItem; out AConverted: TScoredItem): Boolean;
var
  mActual, mExpected, mEnumType, mExpression: string;
  mConverted, mDisplay: TTypeConversion;
  mHelper: Boolean;
  mStart: TTextPosition;
begin
  AConverted := Default(TScoredItem);
  // Nur Werte ohne Pflichtargumente; Typen, Aufzählungswerte und Importe mit eigenem uses-Eintrag nicht.
  Result := ContextConvertible(ACollector) and SymbolConvertible(ASymbol) and
    (AOriginal.Item.AdditionalEdits = nil) and not AOriginal.Item.Unavailable;
  mActual := '';
  mExpected := '';
  if Result then
  begin
    mActual := BaseTypeOf(ACollector, ASymbol.TypeName);
    mExpected := BaseTypeOf(ACollector, ACollector.FExpected);
  end;
  if not Result or mExpected.StartsWith('enum:') then
  begin
    Exit(False);
  end;
  mEnumType := '';
  if mActual.StartsWith('enum:') then
  begin
    mEnumType := ACollector.FRequest.Resolver.Queries.UnqualifyType(Copy(mActual, 6, MaxInt), ACollector.FOwnUnit);
    mActual := '';
  end;
  mHelper := ACollector.FRequest.Settings.TypeConversion = TCompletionTypeConversion.Helper;
  mExpression := ConversionExpression(ACollector, AName, mStart);
  if (mStart.Character < 0) or not TypeConversion(mActual, mExpected, mEnumType, mExpression, mHelper,
    mConverted) then
  begin
    Exit(False);
  end;
  if mConverted.Lossy then
  begin
    AOriginal.Item.Lossy := ASymbol.TypeName;
    Exit(False);
  end;
  // Gezeigt wird nur der Name.
  TypeConversion(mActual, mExpected, mEnumType, AName, mHelper, mDisplay);
  AConverted := AOriginal;
  AConverted.Item.Name := mDisplay.Text;
  AConverted.Item.FilterText := AName;
  AConverted.Item.Conversion := ACollector.FExpected;
  AConverted.Item.ConvertFrom := AName;
  AConverted.Item.Overloads := nil;
  AConverted.Item.HasParameters := False;
  AConverted.Item.HasTextEdit := True;
  AConverted.Item.TextEdit := TRuleEdit.Create(TTextRange.Create(mStart, ACollector.FRequest.Position),
    mConverted.Text);
  AddConversionUnits(ACollector, mConverted.Units, AConverted.Item);
end;

/// <summary>Bereichsstufe (#488) für einen Eintrag aus AMember; 0 ohne Symbol oder nach einem Punkt.</summary>
function ScopeOf(ACollector: TCompletionCollector; const AMember: TResolvedSymbol; out AUnitName: string): Integer;
begin
  AUnitName := '';
  // Bereichsstufe nur im Gültigkeitsbereich, nicht nach einem Punkt (#488).
  Result := 0;
  if (ACollector.FContext.Kind <> TCompletionContextKind.Scope) or (AMember.Name = '') then
  begin
    Exit;
  end;
  if AMember.WithOrigin <> '' then
  begin
    // Mitglied eines with-Objekts (#481), auch wenn es zur eigenen Klasse gehört (with Self do); abgeschaltet
    // ohne Angabe statt einer falschen.
    if ACollector.FRequest.Settings.WithOrigin then
    begin
      Result := 6;
    end;
  end
  else if AMember.Kind = TResolvedKind.Local then
  begin
    if AMember.IsParameter then
    begin
      Result := 2;
    end
    else
    begin
      Result := 1;
    end;
  end
  else if AMember.Container <> '' then
  begin
    Result := 3;
  end
  else if (ACollector.FOwnUnit <> '') and SameText(AMember.UnitName, ACollector.FOwnUnit) then
  begin
    Result := 4;
  end
  else
  begin
    Result := 5;
    AUnitName := AMember.UnitName;
  end;
end;

/// <summary>Merkmale und Quelle des Eintrags aus ASymbol: gebundene Typparameter, Bereich, Überladungen.</summary>
procedure FillFromSymbol(ACollector: TCompletionCollector; const ASymbol: TResolvedSymbol;
  var AItem: TCompletionItem);
var
  mBinding, mParams, mUnitName: string;
  mRange: TTextRange;
begin
  // Gebundene Typparameter (#450): FItems: TObjectList<TKunde> zeigt Add(const Value: TKunde), ohne Unit davor.
  for mBinding in ASymbol.Bindings do
  begin
    AItem.Bindings := AItem.Bindings + [Copy(mBinding, 1, Pos('=', mBinding)) +
      ACollector.FRequest.Resolver.Queries.UnqualifyType(Copy(mBinding, Pos('=', mBinding) + 1, MaxInt),
      ACollector.FOwnUnit)];
  end;
  // Wo die Deklaration steht, für completionItem/resolve.
  AItem.SourceFile := ASymbol.FileName;
  AItem.SourcePosition := ASymbol.SelectionRange.StartPos;
  AItem.Container := ASymbol.Container;
  AItem.Depth := ASymbol.Depth;
  AItem.IsHelper := ASymbol.IsHelper;
  AItem.HasParameters := ASymbol.MaxArgs > 0;
  AItem.Condition := ASymbol.Condition;
  AItem.VariantBranch := ASymbol.VariantBranch;
  AItem.Scope := ScopeOf(ACollector, ASymbol, mUnitName);
  AItem.UnitName := mUnitName;
  AItem.Hides := ASymbol.Hides;
  if AItem.Scope = 6 then
  begin
    AItem.WithOrigin := ASymbol.WithOrigin;
    AItem.WithShadows := ASymbol.WithShadows;
  end;
  for mParams in ASymbol.VariantParams do
  begin
    if mParams <> '' then
    begin
      AItem.HasParameters := True;
    end;
  end;
  for mRange in ASymbol.Overloads do
  begin
    AItem.Overloads := AItem.Overloads + [mRange.StartPos];
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
  mScored, mConverted: TScoredItem;
begin
  // Jeder Eintrag frisch: Nichts bleibt vom vorigen stehen, z. B. HasTextEdit und TextEdit
  // (im Plugin löschte das alles bis zum Wort).
  mScored := Default(TScoredItem);
  mScored.Score := MatchScore(AName, FContext.Prefix, FRequest.Matching);
  if mScored.Score = TFuzzyMatch.cNoMatch then
  begin
    Exit(False);
  end;
  Dec(mScored.Score, APenalty);
  mScored.Item.Name := AName;
  // Der Index führt Namen ohne Escape-&; reservierte Wörter und &-Namen brauchen es im Quelltext (#1137).
  if (ASymbol.Name <> '') and (TPascalLexer.SourceName(AName) <> AName) then
  begin
    mScored.Item.InsertText := TPascalLexer.SourceName(AName);
  end;
  mScored.Item.AdditionalEdits := AEdits;
  FillFromSymbol(Self, ASymbol, mScored.Item);
  mScored.Item.Detail := TInterfaceStubs.SubstituteWords(ADetail, mScored.Item.Bindings);
  mScored.Item.Kind := AKind;
  // Der Editor filtert selbst nach dem getippten Wort; unscharfe Treffer bekommen es
  // als filterText, damit er sie nicht verwirft.
  if (FRequest.Matching = TCompletionMatching.Fuzzy) and not AName.StartsWith(FContext.Prefix, True) then
  begin
    mScored.Item.FilterText := FContext.Prefix;
  end;
  // Erwarteter Typ (#417): Atlas gruppiert nach Fits.
  mScored.Item.Expected := FExpected;
  mScored.Item.Fits := (FExpected <> '') and (ASymbol.Name <> '') and MemberFits(ASymbol);
  if mScored.Item.Fits then
  begin
    FAnyFits := True;
  end;
  // Typkonvertierung (#490): Umwandlung direkt vor dem Original, das mit seinem Typ wählbar bleibt.
  if not mScored.Item.Fits and ConversionOf(Self, AName, ASymbol, mScored, mConverted) then
  begin
    mConverted.Order := FList.Count;
    FList.Add(mConverted);
  end;
  mScored.Order := FList.Count;
  FList.Add(mScored);
  Result := True;
end;

procedure TCompletionCollector.AddItem(const AItem: TCompletionItem; AScore: Integer);
var
  mScored: TScoredItem;
begin
  mScored := Default(TScoredItem);
  mScored.Item := AItem;
  mScored.Score := AScore;
  mScored.Order := FList.Count;
  FList.Add(mScored);
end;

procedure TCompletionCollector.MarkLastUnavailable;
var
  mScored: TScoredItem;
begin
  if FList.Count = 0 then
  begin
    Exit;
  end;
  mScored := FList[FList.Count - 1];
  mScored.Item.Unavailable := True;
  FList[FList.Count - 1] := mScored;
end;

/// <summary>Bedingungen (AConditions) und nicht geltende Deklarationen (AMissing) der obersten Ebene von AOwn,
/// je Name groß geschrieben.</summary>
procedure CollectOwnConditions(const AOwn: TUnitIndex; AConditions, AMissing: TDictionary<string, string>);
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AOwn.Symbols do
  begin
    if (mSymbol.Container = '') and (mSymbol.Condition <> '') then
    begin
      AConditions.AddOrSetValue(UpperCase(mSymbol.Name), mSymbol.Condition);
    end;
  end;
  for mSymbol in AOwn.Unavailable do
  begin
    if mSymbol.Container = '' then
    begin
      AMissing.AddOrSetValue(UpperCase(mSymbol.Name), mSymbol.Condition);
    end;
  end;
end;

/// <summary>Bedingung für AScored aus AMissing (dann nicht verfügbar) bzw. AConditions; False ohne Treffer.
/// </summary>
function ApplyOwnCondition(var AScored: TScoredItem; AConditions, AMissing: TDictionary<string, string>): Boolean;
var
  mCondition: string;
begin
  Result := True;
  if AMissing.TryGetValue(UpperCase(AScored.Item.Name), mCondition) then
  begin
    AScored.Item.Condition := mCondition;
    AScored.Item.Unavailable := True;
    // Wie die übrigen nicht verfügbaren Einträge ans Ende.
    Dec(AScored.Score, cPenaltyUnavailable);
  end
  else if AConditions.TryGetValue(UpperCase(AScored.Item.Name), mCondition) then
  begin
    AScored.Item.Condition := mCondition;
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Eintrag aus der Datei der Anfrage ohne Bedingung? Gleichnamige aus anderen Units bleiben unberührt.
/// </summary>
function IsOwnPlainEntry(ACollector: TCompletionCollector; const AItem: TCompletionItem): Boolean;
begin
  Result := (AItem.Condition = '') and ((AItem.SourceFile = '') or
    SameText(AItem.SourceFile, ACollector.FRequest.FileName));
end;

/// <summary>Einträge aus der eigenen Datei: Der Baum des Editors kennt keine {$IFDEF}-Zweige.
/// Bedingung und Verfügbarkeit kommen aus dem Index dieser Unit, der mit Präprozessor gelesen ist (#476).</summary>
procedure MarkOwnConditions(ACollector: TCompletionCollector);
var
  mOwn: TUnitIndex;
  mConditions, mMissing: TDictionary<string, string>;
  mIndex: Integer;
  mScored: TScoredItem;
begin
  if (ACollector.FRequest.Index = nil) or
    not ACollector.FRequest.Index.FindFile(ACollector.FRequest.FileName, mOwn) then
  begin
    Exit;
  end;
  mConditions := TDictionary<string, string>.Create;
  mMissing := TDictionary<string, string>.Create;
  try
    CollectOwnConditions(mOwn, mConditions, mMissing);
    if (mConditions.Count = 0) and (mMissing.Count = 0) then
    begin
      Exit;
    end;
    for mIndex := 0 to ACollector.FList.Count - 1 do
    begin
      mScored := ACollector.FList[mIndex];
      if IsOwnPlainEntry(ACollector, mScored.Item) and ApplyOwnCondition(mScored, mConditions, mMissing) then
      begin
        ACollector.FList[mIndex] := mScored;
      end;
    end;
  finally
    mMissing.Free;
    mConditions.Free;
  end;
end;

/// <summary>Namen der Liste und der schon gesendeten Einträge, groß geschrieben. Der Aufrufer gibt frei.
/// </summary>
function KnownNames(ACollector: TCompletionCollector): TDictionary<string, Boolean>;
var
  mExisting: TScoredItem;
  mName: string;
begin
  Result := TDictionary<string, Boolean>.Create;
  for mExisting in ACollector.FList do
  begin
    Result.AddOrSetValue(UpperCase(mExisting.Item.Name), True);
  end;
  for mName in ACollector.FSentNames.Keys do
  begin
    Result.AddOrSetValue(mName, True);
  end;
end;

/// <summary>Passt die Symbolart AKind zum Filter der Anfrage (an Typpositionen nur Typen)?</summary>
function KindAllowed(ACollector: TCompletionCollector; AKind: TIndexSymbolKind): Boolean;
begin
  Result := (ACollector.FContext.Filter <> TCompletionFilter.Types) or (AKind in cIndexTypeKinds);
end;

/// <summary>Gehört ASymbol nicht zu AddUnavailable? Mitglieder nicht geltender Zweige zeigt AddUnavailableMembers
/// hinter "Objekt.", aus fremden Units nur das Interface.</summary>
function SkipsUnavailable(ACollector: TCompletionCollector; const ASymbol: TIndexSymbol; AOwnUnit: Boolean;
  AKnown: TDictionary<string, Boolean>): Boolean;
begin
  Result := (ASymbol.Container <> '') or not (ASymbol.InInterface or AOwnUnit) or
    AKnown.ContainsKey(UpperCase(ASymbol.Name)) or not KindAllowed(ACollector, ASymbol.Kind);
end;

/// <summary>Die nicht geltenden Deklarationen von AUnitInfo als nicht verfügbare Einträge.</summary>
procedure AddUnavailableOf(ACollector: TCompletionCollector; const AUnitInfo: TUnitIndex; AOwnUnit: Boolean;
  AKnown: TDictionary<string, Boolean>);
var
  mSymbol: TIndexSymbol;
  mMember: TResolvedSymbol;
begin
  for mSymbol in AUnitInfo.Unavailable do
  begin
    if SkipsUnavailable(ACollector, mSymbol, AOwnUnit, AKnown) then
    begin
      Continue;
    end;
    mMember := Default(TResolvedSymbol);
    mMember.Name := mSymbol.Name;
    mMember.Condition := mSymbol.Condition;
    mMember.FileName := AUnitInfo.FileName;
    mMember.SelectionRange.StartPos := mSymbol.SelectionRange.StartPos;
    if ACollector.Add(mSymbol.Name, AUnitInfo.UnitName, CompletionKindOf(mSymbol.Kind), cPenaltyUnavailable,
      mMember) then
    begin
      ACollector.MarkLastUnavailable;
      AKnown.AddOrSetValue(UpperCase(mSymbol.Name), True);
    end;
  end;
end;

procedure TCompletionCollector.AddUnavailable;
var
  mKnown: TDictionary<string, Boolean>;
  mUsed: TArray<string>;
  mOwn: string;
  mUnitInfo: TUnitIndex;
  mOwnUnit: Boolean;
begin
  mKnown := KnownNames(Self);
  try
    mUsed := TUsesClauses.UsedUnits(FRequest.Tree.Tokens);
    mOwn := TUsesClauses.OwnName(FRequest.Tree.Tokens);
    for mUnitInfo in FRequest.Index.UnavailableUnits do
    begin
      mOwnUnit := SameText(mUnitInfo.UnitName, mOwn);
      if (Length(mUnitInfo.Unavailable) > 0) and (mOwnUnit or
        TUsesClauses.IsUsed(mUsed, mUnitInfo.UnitName, FRequest.Resolver.Namespaces)) then
      begin
        AddUnavailableOf(Self, mUnitInfo, mOwnUnit, mKnown);
      end;
    end;
  finally
    mKnown.Free;
  end;
end;

type
  /// <summary>Suche nach Symbolen nicht eingebundener Units (#180) über den Namensindex (#617).</summary>
  TImportScan = record
    Collector: TCompletionCollector;
    Names: TImportNameIndex;
    QueryMask: UInt64;
    Used: TArray<string>;
    Own: string;
    // Je Unit: 0 = noch nicht geprüft, 1 = überspringen (eigene oder schon eingebunden), 2 = vorschlagen.
    UnitState: TArray<Byte>;
    Known: TDictionary<string, Boolean>;
    // nil = alle Namen, sonst nur diese (Großbuchstaben).
    Wanted: TDictionary<string, Boolean>;
    /// <summary>Kann AEntry passen (Zeichenmaske) und gehört er zu einer Unit, die nicht eingebunden ist?
    /// </summary>
    function Candidate(const AEntry: TImportNameEntry): Boolean;
    /// <summary>Soll ASymbol aus AUnitInfo erscheinen (gewünscht, neu, Art, Treffer, zugelassen)?</summary>
    function Wants(const AUnitInfo: TUnitIndex; const ASymbol: TIndexSymbol): Boolean;
  end;

/// <summary>Passt ASymbol aus AUnitInfo zum Getippten, und lässt der Filter von SetAdmit es zu?</summary>
function SymbolAdmitted(ACollector: TCompletionCollector; const AUnitInfo: TUnitIndex;
  const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (MatchScore(ASymbol.Name, ACollector.FContext.Prefix, ACollector.FRequest.Matching) <>
    TFuzzyMatch.cNoMatch) and (not Assigned(ACollector.FAdmit) or
    ACollector.FAdmit(TResolvedSymbol.FromIndex(AUnitInfo, ASymbol)));
end;

function TImportScan.Candidate(const AEntry: TImportNameEntry): Boolean;
var
  mUnitName: string;
begin
  if not TImportNameIndex.MayMatch(AEntry.Mask, QueryMask) then
  begin
    Exit(False);
  end;
  if UnitState[AEntry.UnitPos] = 0 then
  begin
    mUnitName := Names.Units[AEntry.UnitPos].UnitName;
    UnitState[AEntry.UnitPos] := 2;
    if SameText(mUnitName, Own) or TUsesClauses.IsUsed(Used, mUnitName, Collector.FRequest.Resolver.Namespaces) then
    begin
      UnitState[AEntry.UnitPos] := 1;
    end;
  end;
  Result := UnitState[AEntry.UnitPos] = 2;
end;

function TImportScan.Wants(const AUnitInfo: TUnitIndex; const ASymbol: TIndexSymbol): Boolean;
var
  mName: string;
begin
  mName := UpperCase(ASymbol.Name);
  Result := ((Wanted = nil) or Wanted.ContainsKey(mName)) and not Known.ContainsKey(mName) and
    KindAllowed(Collector, ASymbol.Kind) and SymbolAdmitted(Collector, AUnitInfo, ASymbol);
end;

/// <summary>Abzug für Symbole aus AUnitInfo: eingebundenes zuerst, dann Projekt-Units, dann RTL/VCL und andere
/// Bibliotheken.</summary>
function ImportPenalty(const AUnitInfo: TUnitIndex): Integer;
begin
  Result := cPenaltyProjectImport;
  if AUnitInfo.Library_ then
  begin
    Result := cPenaltyLibraryImport;
  end;
end;

/// <summary>Eintrag für ASymbol aus AUnitInfo mit dem uses-Eintrag AEdit; False, wenn er nicht passt.</summary>
function AddImport(ACollector: TCompletionCollector; const AUnitInfo: TUnitIndex; const ASymbol: TIndexSymbol;
  const AEdit: TRuleEdit): Boolean;
var
  mMember: TResolvedSymbol;
begin
  // Merkmale und Quelle aus dem Indexsymbol (sonst fehlten z. B. die Klammern bei ShowMessage aus
  // Vcl.Dialogs).
  mMember := Default(TResolvedSymbol);
  mMember.Name := ASymbol.Name;
  mMember.MinArgs := ASymbol.MinArgs;
  mMember.MaxArgs := ASymbol.MaxArgs;
  mMember.FileName := AUnitInfo.FileName;
  mMember.SelectionRange.StartPos := ASymbol.SelectionRange.StartPos;
  // Gleichnamige Symbole verschiedener Units bleiben alle wählbar.
  Result := ACollector.Add(ASymbol.Name, AUnitInfo.UnitName + cTexts[TCompletionCollectorText.AddToUses].Text,
    CompletionKindOf(ASymbol.Kind),
    ImportPenalty(AUnitInfo), mMember, [AEdit]);
end;

/// <summary>Wie AddFromOtherUnits; AWanted = nil heißt alle Namen, sonst nur diese (Großbuchstaben).</summary>
procedure AddImports(ACollector: TCompletionCollector; AWanted: TDictionary<string, Boolean>);
var
  mScan: TImportScan;
  mEntry: TImportNameEntry;
  mUnitInfo: TUnitIndex;
  mSymbol: TIndexSymbol;
  mEdit: TRuleEdit;
  mAdded: Integer;
begin
  mScan := Default(TImportScan);
  mScan.Collector := ACollector;
  mScan.Wanted := AWanted;
  mScan.Known := KnownNames(ACollector);
  try
    mScan.Used := TUsesClauses.UsedUnits(ACollector.FRequest.Tree.Tokens);
    mScan.Own := TUsesClauses.OwnName(ACollector.FRequest.Tree.Tokens);
    // Projekt-Units vor der Bibliothek: Sonst füllen RTL/VCL die Höchstzahl, bevor eine
    // gerade getippte Klasse aus dem eigenen Projekt drankommt (#492). Der Namensindex (#617)
    // ist schon so sortiert und enthält nur importierbare Symbole; die Zeichenmaske spart den
    // unscharfen Vergleich für fast alle Namen.
    mScan.Names := TImportNames.Current(ACollector.FRequest.Index);
    mScan.QueryMask := TImportNameIndex.MaskOf(ACollector.FContext.Prefix);
    SetLength(mScan.UnitState, Length(mScan.Names.Units));
    mAdded := 0;
    for mEntry in mScan.Names.Entries do
    begin
      if not mScan.Candidate(mEntry) then
      begin
        Continue;
      end;
      mUnitInfo := mScan.Names.Units[mEntry.UnitPos];
      mSymbol := mUnitInfo.Symbols[mEntry.SymbolPos];
      if not mScan.Wants(mUnitInfo, mSymbol) then
      begin
        Continue;
      end;
      // Fest #13#10 wie bisher (eigener Befund: uses-Eintrag in LF-Dateien, siehe CHANGELOG).
      if not TUsesClauses.AddUnit(ACollector.FRequest.Tree.Tokens, ACollector.FContext.Offset, mUnitInfo.UnitName,
        #13#10, mEdit) then
      begin
        Exit;
      end;
      if AddImport(ACollector, mUnitInfo, mSymbol, mEdit) then
      begin
        Inc(mAdded);
        if mAdded >= cCompletionMaxImportItems then
        begin
          ACollector.FImportsCapped := True;
          Exit;
        end;
      end;
    end;
  finally
    mScan.Known.Free;
  end;
end;

procedure TCompletionCollector.AddFromOtherUnits;
begin
  AddImports(Self, nil);
end;

procedure TCompletionCollector.AddFromOtherUnits(const ANames: TArray<string>);
var
  mWanted: TDictionary<string, Boolean>;
  mName: string;
begin
  mWanted := TDictionary<string, Boolean>.Create;
  try
    for mName in ANames do
    begin
      mWanted.AddOrSetValue(UpperCase(mName), True);
    end;
    AddImports(Self, mWanted);
  finally
    mWanted.Free;
  end;
end;

/// <summary>Eintrag für den IDE-Typ AType; AUsed: seine Unit steht schon im uses. False, wenn er nicht passt.
/// </summary>
function AddIdeType(ACollector: TCompletionCollector; const AType: TIdeTypeEntry; AUsed: Boolean): Boolean;
var
  mEdit: TRuleEdit;
begin
  if AUsed then
  begin
    Exit(ACollector.Add(AType.Name, AType.UnitName, cKindClass, Default(TResolvedSymbol)));
  end;
  // Fest #13#10 wie bei AddImports.
  Result := TUsesClauses.AddUnit(ACollector.FRequest.Tree.Tokens, ACollector.FContext.Offset, AType.UnitName,
    #13#10, mEdit) and ACollector.Add(AType.Name, AType.UnitName + cTexts[TCompletionCollectorText.AddToUses].Text,
    cKindClass, cPenaltyLibraryImport, Default(TResolvedSymbol), [mEdit]);
end;

procedure TCompletionCollector.AddIdeTypes;
var
  mKnown: TDictionary<string, Boolean>;
  mType: TIdeTypeEntry;
  mUsed: TArray<string>;
  mOwn: string;
  mAdded: Integer;
begin
  if (Length(FRequest.IdeTypes) = 0) or Assigned(FAdmit) or not KindAllowed(Self, TIndexSymbolKind.ClassType) then
  begin
    Exit;
  end;
  mKnown := KnownNames(Self);
  try
    mUsed := TUsesClauses.UsedUnits(FRequest.Tree.Tokens);
    mOwn := TUsesClauses.OwnName(FRequest.Tree.Tokens);
    mAdded := 0;
    for mType in FRequest.IdeTypes do
    begin
      if mKnown.ContainsKey(UpperCase(mType.Name)) or SameText(mType.UnitName, mOwn) or
        not AddIdeType(Self, mType, TUsesClauses.IsUsed(mUsed, mType.UnitName, FRequest.Resolver.Namespaces)) then
      begin
        Continue;
      end;
      mKnown.AddOrSetValue(UpperCase(mType.Name), True);
      Inc(mAdded);
      if mAdded >= cCompletionMaxImportItems then
      begin
        FImportsCapped := True;
        Exit;
      end;
    end;
  finally
    mKnown.Free;
  end;
end;

const
  /// <summary>Platz für Varianten in der Reihenfolge hinter jedem Eintrag.</summary>
  cVariantSlots = 1000;

type
  TSameNameVariant = record
    Active: Integer;
    UnitInfo: TUnitIndex;
    Symbol: TIndexSymbol;
  end;

  /// <summary>Gleichnamige Bezeichner aus anderen Units (#475) für AddSameNameVariants.</summary>
  TSameNameScan = record
    Collector: TCompletionCollector;
    // Je Name groß geschrieben die Position der aktiven Variante in der Liste.
    Active: TDictionary<string, Integer>;
    Variants: TList<TSameNameVariant>;
    // Je Position der aktiven Variante: Units weiterer Varianten und ausgeblendete (FMX).
    Units, Hidden: TArray<TArray<string>>;
    Own: string;
    // Hinzugefügte Varianten, für ihre Reihenfolge.
    Count: Integer;
    /// <summary>Aktiv ist, was die Namensauflösung aus den uses brachte (letzte Unit gewinnt).</summary>
    procedure FindActive;
    /// <summary>Varianten der aktiven Namen aus dem Namensindex.</summary>
    procedure Collect;
    function Skips(const AVariant: TSameNameVariant): Boolean;
    procedure Take(const AVariant: TSameNameVariant);
    /// <summary>Die aktive Variante nennt alle Units, die den Namen deklarieren.</summary>
    procedure MarkActive;
    /// <summary>AVariant direkt hinter ihrer aktiven Variante.</summary>
    procedure AddVariant(const AVariant: TSameNameVariant; const AUsed: TArray<string>; const ARange: TTextRange);
    /// <summary>Die übrigen behalten ihre Reihenfolge, mit Platz für die Varianten dahinter.</summary>
    procedure Spread;
  end;

procedure TSameNameScan.FindActive;
var
  mIndex: Integer;
  mItem: TCompletionItem;
begin
  for mIndex := 0 to Collector.FList.Count - 1 do
  begin
    mItem := Collector.FList[mIndex].Item;
    if (mItem.Scope = 5) and (mItem.UnitName <> '') and (mItem.Action = '') and not mItem.Unavailable and
      (mItem.Conversion = '') then
    begin
      Active.AddOrSetValue(UpperCase(mItem.Name), mIndex);
    end;
  end;
end;

procedure TSameNameScan.Collect;
var
  mNames: TImportNameIndex;
  mEntry: TImportNameEntry;
  mQueryMask: UInt64;
  mVariant: TSameNameVariant;
begin
  mNames := TImportNames.Current(Collector.FRequest.Index);
  mQueryMask := TImportNameIndex.MaskOf(Collector.FContext.Prefix);
  for mEntry in mNames.Entries do
  begin
    if not TImportNameIndex.MayMatch(mEntry.Mask, mQueryMask) then
    begin
      Continue;
    end;
    mVariant.Symbol := mNames.Units[mEntry.UnitPos].Symbols[mEntry.SymbolPos];
    if Active.TryGetValue(UpperCase(mVariant.Symbol.Name), mVariant.Active) then
    begin
      mVariant.UnitInfo := mNames.Units[mEntry.UnitPos];
      Take(mVariant);
    end;
  end;
end;

function TSameNameScan.Skips(const AVariant: TSameNameVariant): Boolean;
begin
  Result := AVariant.Symbol.Unavailable or SameText(AVariant.UnitInfo.UnitName, Own) or
    SameText(AVariant.UnitInfo.UnitName, Collector.FList[AVariant.Active].Item.UnitName) or
    MatchText(AVariant.UnitInfo.UnitName, Units[AVariant.Active]) or
    not KindAllowed(Collector, AVariant.Symbol.Kind);
end;

procedure TSameNameScan.Take(const AVariant: TSameNameVariant);
var
  mText: string;
begin
  if Skips(AVariant) then
  begin
    Exit;
  end;
  if TCompletionSameNames.IsFmx(AVariant.UnitInfo.UnitName) and not Collector.FRequest.Settings.ShowFmxUnits then
  begin
    mText := AVariant.UnitInfo.UnitName + '.' + AVariant.Symbol.Name;
    if not MatchText(mText, Hidden[AVariant.Active]) then
    begin
      Hidden[AVariant.Active] := Hidden[AVariant.Active] + [mText];
    end;
    Exit;
  end;
  Units[AVariant.Active] := Units[AVariant.Active] + [AVariant.UnitInfo.UnitName];
  Variants.Add(AVariant);
end;

procedure TSameNameScan.MarkActive;
var
  mIndex: Integer;
  mScored: TScoredItem;
begin
  for mIndex := 0 to Collector.FList.Count - 1 do
  begin
    if (Length(Units[mIndex]) > 0) or (Length(Hidden[mIndex]) > 0) then
    begin
      mScored := Collector.FList[mIndex];
      mScored.Item.SameNameActive := True;
      mScored.Item.SameNameUnits := [mScored.Item.UnitName] + Units[mIndex];
      mScored.Item.SameNameHidden := Hidden[mIndex];
      Collector.FList[mIndex] := mScored;
    end;
  end;
end;

/// <summary>Einfügeart für AVariant (aktiv aus Unit AKey) und die Änderungen dazu: uses umstellen oder ergänzen.
/// False, wenn der uses-Eintrag nicht geht.</summary>
function VariantEdits(ACollector: TCompletionCollector; const AVariant: TSameNameVariant; const AKey: string;
  const AUsed: TArray<string>; out AMode: string; out AEdits: TArray<TRuleEdit>): Boolean;
var
  mIsUsed, mMovable: Boolean;
  mMoved: TArray<TRuleEdit>;
  mEdit: TRuleEdit;
begin
  mIsUsed := TUsesClauses.IsUsed(AUsed, AVariant.UnitInfo.UnitName, ACollector.FRequest.Resolver.Namespaces);
  mMovable := mIsUsed and TCompletionSameNames.MoveToEnd(ACollector.FRequest.Tree.Tokens,
    AVariant.UnitInfo.UnitName, AKey, ACollector.FRequest.Resolver.Namespaces, mMoved);
  AMode := TCompletionSameNames.InsertMode(ACollector.FRequest.Settings.SameNameInsert, mIsUsed, mMovable);
  AEdits := nil;
  Result := True;
  if AMode = TCompletionSameNames.cInsertMove then
  begin
    AEdits := mMoved;
  end
  else if (AMode = TCompletionSameNames.cInsertAdd) or (AMode = TCompletionSameNames.cInsertPrefixAdd) then
  begin
    Result := TUsesClauses.AddUnit(ACollector.FRequest.Tree.Tokens, ACollector.FContext.Offset,
      AVariant.UnitInfo.UnitName, ACollector.FRequest.LineBreak, mEdit);
    if Result then
    begin
      AEdits := [mEdit];
    end;
  end;
end;

/// <summary>Symbol zum Eintrag von AVariant: Merkmale und Quelle aus dem Index.</summary>
function VariantSymbol(const AVariant: TSameNameVariant): TResolvedSymbol;
begin
  Result := Default(TResolvedSymbol);
  Result.Kind := TResolvedKind.Symbol;
  Result.Name := AVariant.Symbol.Name;
  Result.UnitName := AVariant.UnitInfo.UnitName;
  Result.MinArgs := AVariant.Symbol.MinArgs;
  Result.MaxArgs := AVariant.Symbol.MaxArgs;
  Result.FileName := AVariant.UnitInfo.FileName;
  Result.SelectionRange.StartPos := AVariant.Symbol.SelectionRange.StartPos;
end;

procedure TSameNameScan.AddVariant(const AVariant: TSameNameVariant; const AUsed: TArray<string>;
  const ARange: TTextRange);
var
  mActive, mScored: TScoredItem;
  mMode: string;
  mEdits: TArray<TRuleEdit>;
  mPosition: Integer;
begin
  mActive := Collector.FList[AVariant.Active];
  if not VariantEdits(Collector, AVariant, mActive.Item.UnitName, AUsed, mMode, mEdits) or
    not Collector.Add(AVariant.Symbol.Name, AVariant.UnitInfo.UnitName, CompletionKindOf(AVariant.Symbol.Kind), 0,
    VariantSymbol(AVariant), mEdits) then
  begin
    Exit;
  end;
  // Direkt hinter der aktiven Variante: gleiche Punktzahl, Reihenfolge gleich dahinter (siehe Spread).
  mPosition := Collector.FList.Count - 1;
  mScored := Collector.FList[mPosition];
  mScored.Score := mActive.Score;
  Inc(Count);
  mScored.Order := mActive.Order * cVariantSlots + Count;
  mScored.Item.SameNameOf := mActive.Item.UnitName;
  mScored.Item.SameNameInsert := mMode;
  mScored.Item.SameNameUnits := mActive.Item.SameNameUnits;
  mScored.Item.SameNameHidden := mActive.Item.SameNameHidden;
  if mScored.Item.FilterText = '' then
  begin
    mScored.Item.FilterText := AVariant.Symbol.Name;
  end;
  if (mMode = TCompletionSameNames.cInsertPrefix) or (mMode = TCompletionSameNames.cInsertPrefixAdd) then
  begin
    mScored.Item.HasTextEdit := True;
    mScored.Item.TextEdit := TRuleEdit.Create(ARange, AVariant.UnitInfo.UnitName + '.' + AVariant.Symbol.Name);
  end;
  // Kein uses-Eintrag im Sinne von #180: Atlas soll die Edits nicht als „+ Unit“ zeigen.
  mScored.Item.Action := 'sameName';
  Collector.FList[mPosition] := mScored;
end;

procedure TSameNameScan.Spread;
var
  mIndex: Integer;
  mScored: TScoredItem;
begin
  if Count = 0 then
  begin
    Exit;
  end;
  for mIndex := 0 to Collector.FList.Count - 1 do
  begin
    if Collector.FList[mIndex].Item.SameNameOf = '' then
    begin
      mScored := Collector.FList[mIndex];
      mScored.Order := mScored.Order * cVariantSlots;
      Collector.FList[mIndex] := mScored;
    end;
  end;
end;

procedure TCompletionCollector.AddSameNameVariants;
var
  mScan: TSameNameScan;
  mUsed: TArray<string>;
  mRange: TTextRange;
  mVariant: TSameNameVariant;
begin
  if not FRequest.Settings.SameNameVariants or (FContext.Kind <> TCompletionContextKind.Scope) or
    (FRequest.Tree = nil) or (FRequest.Index = nil) then
  begin
    Exit;
  end;
  mScan := Default(TSameNameScan);
  mScan.Collector := Self;
  mScan.Active := TDictionary<string, Integer>.Create;
  mScan.Variants := TList<TSameNameVariant>.Create;
  try
    mScan.FindActive;
    if mScan.Active.Count = 0 then
    begin
      Exit;
    end;
    mScan.Own := TUsesClauses.OwnName(FRequest.Tree.Tokens);
    SetLength(mScan.Units, FList.Count);
    SetLength(mScan.Hidden, FList.Count);
    mScan.Collect;
    mScan.MarkActive;
    mUsed := TUsesClauses.UsedUnits(FRequest.Tree.Tokens);
    mRange := TTextRange.Create(FRequest.Position.Line, FRequest.Position.Character - Length(FContext.Prefix),
      FRequest.Position.Line, FRequest.Position.Character);
    for mVariant in mScan.Variants do
    begin
      mScan.AddVariant(mVariant, mUsed, mRange);
    end;
  finally
    mScan.Spread;
    mScan.Variants.Free;
    mScan.Active.Free;
  end;
end;

/// <summary>Stufe des ersten Typs aus ATypes, den AHelper erweitert; -1 ohne.</summary>
function HelperDepth(const AHelper: TIndexSymbol; const ATypes: TArray<TResolvedSymbol>): Integer;
var
  mPosition: Integer;
begin
  Result := -1;
  for mPosition := 0 to High(ATypes) do
  begin
    if TResolverText.HelperTargets(AHelper.Ancestors[High(AHelper.Ancestors)], ATypes[mPosition]) then
    begin
      Exit(mPosition);
    end;
  end;
end;

/// <summary>Ist AUnitName die eigene oder schon eingebunden (System immer)?</summary>
function HelperUnitSkipped(ACollector: TCompletionCollector; const AUnitName, AOwn: string;
  const AUsed: TArray<string>): Boolean;
begin
  Result := SameText(AUnitName, AOwn) or TUsesClauses.IsUsed(AUsed, AUnitName,
    ACollector.FRequest.Resolver.Namespaces) or TUsesClauses.IsUsed(AUsed, AUnitName, ['System']);
end;

/// <summary>Kommt AMember als öffentliches, neues und passendes Mitglied des Helpers AHelperName in Frage?
/// </summary>
function HelperMemberWanted(ACollector: TCompletionCollector; const AMember: TIndexSymbol;
  const AHelperName: string; AKnown: TDictionary<string, Boolean>): Boolean;
begin
  Result := SameText(AMember.Container, AHelperName) and
    (AMember.Visibility in [TIndexVisibility.Public, TIndexVisibility.Published]) and
    not AKnown.ContainsKey(UpperCase(AMember.Name)) and ((ACollector.FContext.Prefix = '') or
    (MatchScore(AMember.Name, ACollector.FContext.Prefix, ACollector.FRequest.Matching) <> TFuzzyMatch.cNoMatch));
end;

/// <summary>Mitglieder des Helpers AHelperName aus AUnitInfo mit dem uses-Eintrag AEdit, Stufe ADepth.</summary>
procedure AddHelperMembers(ACollector: TCompletionCollector; const AUnitInfo: TUnitIndex; const AHelperName: string;
  ADepth: Integer; const AEdit: TRuleEdit; AKnown: TDictionary<string, Boolean>);
var
  mSymbol: TIndexSymbol;
  mMember: TResolvedSymbol;
begin
  for mSymbol in AUnitInfo.Symbols do
  begin
    if not HelperMemberWanted(ACollector, mSymbol, AHelperName, AKnown) then
    begin
      Continue;
    end;
    mMember := TResolvedSymbol.FromIndex(AUnitInfo, mSymbol);
    mMember.IsHelper := True;
    mMember.Depth := ADepth;
    if ACollector.Add(mSymbol.Name, AUnitInfo.UnitName + cTexts[TCompletionCollectorText.AddToUses].Text,
      CompletionKindOf(mSymbol.Kind),
      ImportPenalty(AUnitInfo), mMember, [AEdit]) then
    begin
      AKnown.AddOrSetValue(UpperCase(mSymbol.Name), True);
    end;
  end;
end;

procedure TCompletionCollector.AddHelpersFromOtherUnits(const ATypes: TArray<TResolvedSymbol>);
var
  mKnown: TDictionary<string, Boolean>;
  mUsed: TArray<string>;
  mOwn: string;
  mNames: TImportNameIndex;
  mEntry: TImportNameEntry;
  mUnitInfo: TUnitIndex;
  mHelper: TIndexSymbol;
  mEdit: TRuleEdit;
  mDepth: Integer;
begin
  if Length(ATypes) = 0 then
  begin
    Exit;
  end;
  mKnown := KnownNames(Self);
  try
    mUsed := TUsesClauses.UsedUnits(FRequest.Tree.Tokens);
    mOwn := TUsesClauses.OwnName(FRequest.Tree.Tokens);
    mNames := TImportNames.Current(FRequest.Index);
    for mEntry in mNames.Helpers do
    begin
      mUnitInfo := mNames.Units[mEntry.UnitPos];
      if HelperUnitSkipped(Self, mUnitInfo.UnitName, mOwn, mUsed) then
      begin
        Continue;
      end;
      mHelper := mUnitInfo.Symbols[mEntry.SymbolPos];
      mDepth := HelperDepth(mHelper, ATypes);
      if mDepth < 0 then
      begin
        Continue;
      end;
      if not TUsesClauses.AddUnit(FRequest.Tree.Tokens, FContext.Offset, mUnitInfo.UnitName, #13#10, mEdit) then
      begin
        Exit;
      end;
      AddHelperMembers(Self, mUnitInfo, mHelper.Name, mDepth, mEdit, mKnown);
    end;
  finally
    mKnown.Free;
  end;
end;

/// <summary>Passende zuerst (#417): nach Fits gruppiert, sonst in der sortierten Reihenfolge.</summary>
procedure OrderFitting(AList: TList<TScoredItem>);
var
  mIndex: Integer;
  mScored: TScoredItem;
begin
  for mIndex := 0 to AList.Count - 1 do
  begin
    mScored := AList[mIndex];
    mScored.Order := mIndex + IfThen(mScored.Item.Fits, 0, AList.Count);
    AList[mIndex] := mScored;
  end;
  AList.Sort(TComparer<TScoredItem>.Construct(
    function(const ALeft, ARight: TScoredItem): Integer
    begin
      Result := ALeft.Order - ARight.Order;
    end));
end;

/// <summary>Passt nichts, entfällt die Gruppierung nach dem erwarteten Typ.</summary>
procedure ClearExpected(AList: TList<TScoredItem>);
var
  mIndex: Integer;
  mScored: TScoredItem;
begin
  for mIndex := 0 to AList.Count - 1 do
  begin
    mScored := AList[mIndex];
    mScored.Item.Expected := '';
    AList[mIndex] := mScored;
  end;
end;

/// <summary>Kürzt AList auf ARoom Einträge. Nahe Einträge (lokal, Parameter, eigene Mitglieder ohne geerbte,
/// eigene Unit) nie abschneiden: Bei Formularen mit Hunderten geerbten Mitgliedern verdrängten kurze geerbte
/// Namen sonst die eigenen Methoden mit längerem Namen (Rückmeldung 15.10.2026). Die Reihenfolge bleibt.
/// </summary>
procedure KeepRoom(AList: TList<TScoredItem>; ARoom: Integer);
var
  mNear, mOthersLeft, mKept, mIndex: Integer;
  mScored: TScoredItem;
begin
  mNear := 0;
  for mIndex := 0 to AList.Count - 1 do
  begin
    if IsNearItem(AList[mIndex].Item) then
    begin
      Inc(mNear);
    end;
  end;
  mOthersLeft := Max(0, ARoom - mNear);
  mKept := 0;
  for mIndex := 0 to AList.Count - 1 do
  begin
    mScored := AList[mIndex];
    if IsNearItem(mScored.Item) then
    begin
      if mKept >= ARoom then
      begin
        Continue;
      end;
    end
    else if mOthersLeft > 0 then
    begin
      Dec(mOthersLeft);
    end
    else
    begin
      Continue;
    end;
    AList[mKept] := mScored;
    Inc(mKept);
  end;
  AList.Count := mKept;
end;

/// <summary>Sortiert die gesammelten Einträge, kürzt auf den Rest von MaxItems und leert die Liste.
/// AStaged: Teilergebnis; dann bleibt Expected stehen, weil spätere Stufen noch passende Einträge bringen
/// können (Atlas gruppiert erst, wenn einer passt).</summary>
function TCompletionCollector.TakeStage(AStaged: Boolean): TArray<TCompletionItem>;
var
  mRoom, mIndex: Integer;
begin
  MarkOwnConditions(Self);
  FList.Sort;
  if FAnyFits then
  begin
    OrderFitting(FList);
  end
  else if not AStaged then
  begin
    ClearExpected(FList);
  end;
  mRoom := Max(0, cCompletionMaxItems - FSent);
  if FList.Count > mRoom then
  begin
    FTruncated := True;
    KeepRoom(FList, mRoom);
  end;
  Result := nil;
  SetLength(Result, FList.Count);
  for mIndex := 0 to FList.Count - 1 do
  begin
    Result[mIndex] := FList[mIndex].Item;
    FSentNames.AddOrSetValue(UpperCase(FList[mIndex].Item.Name), True);
  end;
  Inc(FSent, FList.Count);
  FList.Clear;
end;

procedure TCompletionCollector.SendStage;
var
  mItems: TArray<TCompletionItem>;
begin
  if not Assigned(FOnPartial) or (FList.Count = 0) then
  begin
    Exit;
  end;
  mItems := TakeStage(True);
  if Length(mItems) > 0 then
  begin
    FOnPartial(mItems);
  end;
end;

procedure TCompletionCollector.SetNameFilter(AOn: Boolean);
begin
  if AOn and (FContext.Prefix <> '') then
  begin
    FRequest.Resolver.Candidates.NameFilter := PrefixFilter(FContext.Prefix, FRequest.Matching);
  end
  else
  begin
    FRequest.Resolver.Candidates.NameFilter := nil;
  end;
end;

procedure TCompletionCollector.MarkUsedShadows;
var
  mNames: TDictionary<string, Integer>;
  mShadows: TArray<TResolvedSymbol>;
  mShadow: TResolvedSymbol;
  mIndex: Integer;
  mText: string;
  mScored: TScoredItem;
begin
  mNames := TDictionary<string, Integer>.Create;
  try
    for mIndex := 0 to FList.Count - 1 do
    begin
      if ((FList[mIndex].Item.Scope >= 1) and (FList[mIndex].Item.Scope <= 4)) or (FList[mIndex].Item.Scope = 6) then
      begin
        mNames.AddOrSetValue(UpperCase(FList[mIndex].Item.Name), mIndex);
      end;
    end;
    if mNames.Count = 0 then
    begin
      Exit;
    end;
    FRequest.Resolver.Candidates.NameFilter :=
      function(const AName: string): Boolean
      begin
        Result := mNames.ContainsKey(UpperCase(AName));
      end;
    try
      mShadows := FRequest.Resolver.Candidates.UsedScopeShadows;
    finally
      FRequest.Resolver.Candidates.NameFilter := nil;
    end;
    for mShadow in mShadows do
    begin
      if mNames.TryGetValue(UpperCase(mShadow.Name), mIndex) then
      begin
        mScored := FList[mIndex];
        mText := mShadow.ShadowText;
        if not MatchText(mText, mScored.Item.Hides) then
        begin
          mScored.Item.Hides := mScored.Item.Hides + [mText];
          FList[mIndex] := mScored;
        end;
      end;
    end;
  finally
    mNames.Free;
  end;
end;

procedure TCompletionCollector.AddKeywords(const AWords: TArray<string>);
var
  mWord: string;
begin
  for mWord in AWords do
  begin
    Add(mWord, '', cKindKeyword, cPenaltyKeyword, Default(TResolvedSymbol));
  end;
end;

procedure TCompletionCollector.AddUnavailableMembers(const AMembers: TArray<TResolvedSymbol>);
var
  mContainers, mKnown: TDictionary<string, Boolean>;
  mCandidate, mMember: TResolvedSymbol;
  mUnitInfo: TUnitIndex;
  mSymbol: TIndexSymbol;
  mExisting: TScoredItem;
begin
  mContainers := TDictionary<string, Boolean>.Create;
  mKnown := TDictionary<string, Boolean>.Create;
  try
    for mCandidate in AMembers do
    begin
      if mCandidate.Container <> '' then
      begin
        mContainers.AddOrSetValue(UpperCase(mCandidate.Container), True);
      end;
    end;
    if mContainers.Count = 0 then
    begin
      Exit;
    end;
    for mExisting in FList do
    begin
      mKnown.AddOrSetValue(UpperCase(mExisting.Item.Name), True);
    end;
    for mUnitInfo in FRequest.Index.UnavailableUnits do
    begin
      for mSymbol in mUnitInfo.Unavailable do
      begin
        if (mSymbol.Container = '') or not mContainers.ContainsKey(UpperCase(mSymbol.Container)) or
          mKnown.ContainsKey(UpperCase(mSymbol.Name)) then
        begin
          Continue;
        end;
        mMember := Default(TResolvedSymbol);
        mMember.Name := mSymbol.Name;
        mMember.Container := mSymbol.Container;
        mMember.Condition := mSymbol.Condition;
        mMember.FileName := mUnitInfo.FileName;
        mMember.SelectionRange.StartPos := mSymbol.SelectionRange.StartPos;
        if Add(mSymbol.Name, mSymbol.Container, CompletionKindOf(mSymbol.Kind), cPenaltyUnavailable, mMember) then
        begin
          MarkLastUnavailable;
          mKnown.AddOrSetValue(UpperCase(mSymbol.Name), True);
        end;
      end;
    end;
  finally
    mKnown.Free;
    mContainers.Free;
  end;
end;

procedure TCompletionCollector.SetAdmit(const AAdmit: TCompletionAdmitFunc);
begin
  FAdmit := AAdmit;
end;

procedure TCompletionCollector.AddCandidates(const ACandidates: TArray<TResolvedSymbol>);
var
  mCandidate: TResolvedSymbol;
begin
  for mCandidate in ACandidates do
  begin
    // Typposition (#31): nur Typen.
    if (FContext.Filter = TCompletionFilter.Types) and not mCandidate.IsType then
    begin
      Continue;
    end;
    if Assigned(FAdmit) and not FAdmit(mCandidate) then
    begin
      Continue;
    end;
    if mCandidate.TypeName <> '' then
    begin
      Add(mCandidate.Name, mCandidate.TypeName, CompletionKindOf(mCandidate.SymbolKind), mCandidate);
    end
    else if mCandidate.Container <> '' then
    begin
      Add(mCandidate.Name, mCandidate.Container, CompletionKindOf(mCandidate.SymbolKind), mCandidate);
    end
    else
    begin
      Add(mCandidate.Name, mCandidate.UnitName, CompletionKindOf(mCandidate.SymbolKind), mCandidate);
    end;
  end;
end;

function TCompletionCollector.Finish(out AIncomplete: Boolean): TArray<TCompletionItem>;
begin
  Result := TakeStage(FSent > 0);
  AIncomplete := FTruncated or FImportsCapped or
    ((FContext.Kind = TCompletionContextKind.Scope) and (Length(FContext.Prefix) < cCompletionMinImportPrefix));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.CompletionCollector', cTexts);

end.
