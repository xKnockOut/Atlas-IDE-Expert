unit Atlas.Common.Query.Engine;

// Auswertung der Code-Abfragen (#1351) über vorhandene Dienste:
//
// - Elemente und einfache Felder aus dem Symbolindex (Units im Umfang ohne
//   Bibliothek und ohne Packages; Vorwärtsdeklarationen zählen einmal).
// - Metriken je Routine aus TMetricsCollector (dieselben Zahlen wie
//   get_metrics); Überladungen ordnet die Parameterzahl zu.
// - uses und usedBy aus dem Uses-Graphen (#268) über die Units im Umfang.
// - inherits über TAncestry wie die Prüfregeln, implements über die
//   Interfaces der Vorfahrenkette samt abgeleiteter Interfaces.
// - callers, callees und calls über die Aufrufhierarchie (TQuerySource.Calls,
//   #1119/#1122); erschlossene Aufrufe zählen mit, die Zeile ist dann als
//   erschlossen markiert.
//
// Felder werden erst berechnet, wenn eine Bedingung sie braucht; in einer
// and-Kette laufen billige Glieder zuerst (das Ergebnis bleibt gleich).
// Sortiert wird nach dem Feld aus order by, bei Gleichstand eindeutig nach
// Unit, Zeile, Name und Pfad; ohne order by nach Unit und Zeile.

interface

uses
  System.SysUtils,
  Atlas.Common.Metrics.Collector,
  Atlas.Common.Query.Contract;

type
  TCodeQueryEngine = class
  public
    /// <summary>Wertet ARequest über ASource aus; Fehler (Syntax, Abbruch) stehen im Ergebnis. ACollector hält die
    /// Metriken unveränderter Dateien zwischen Abfragen; nil = eigener für diese Abfrage.</summary>
    class function Run(const ASource: TQuerySource; const ARequest: TQueryRequest;
      ACollector: TMetricsCollector): TQueryResult; static;
    /// <summary>Text ohne Typargumente und ohne Unit: Vcl.Forms.TForm → TForm, TList&lt;T&gt; → TList.</summary>
    class function ShortName(const AName: string): string; static;
    /// <summary>Nennt eine uses-Liste AUses die Unit AUnit (auch mit bzw. ohne Namensraum aus ANamespaces)?
    /// </summary>
    class function UsesUnit(const AUses: TArray<string>; const AUnit: string;
      const ANamespaces: TArray<string>): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Diagnostics,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Calculator,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Dfm.FormFiles,
  Atlas.Common.Dfm.BinaryForm,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Rules.ConsideredUsed,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Query.Catalog,
  Atlas.Common.Query.Language,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TQueryEngineText = (QueryCancelled, Inferred);

const
  cTexts: array[TQueryEngineText] of TAtlasText = (
    (De: 'Abfrage abgebrochen'; En: 'Query cancelled'),
    (De: 'erschlossen: %s (%s)'; En: 'inferred: %s (%s)'));

{$SCOPEDENUMS OFF}

type
  EQueryCancelled = class(Exception);

  TIndexSymbolKinds = set of TIndexSymbolKind;

  /// <summary>Mitglieder je Typ einer Unit.</summary>
  TTypeCounts = record
    Methods: Integer;
    Fields: Integer;
    Properties: Integer;
    Overrides: Integer;
  end;

  /// <summary>Eine Unit im Umfang mit ihren bei Bedarf ermittelten Daten.</summary>
  TQueryUnit = class
  public
    Data: TUnitIndex;
    Path: string;
    HasCounts: Boolean;
    Counts: TDictionary<string, TTypeCounts>;
    /// <summary>Qualifizierter Typname (groß) → Stelle in Data.Symbols.</summary>
    Types: TDictionary<string, Integer>;
    ClassCount: Integer;
    /// <summary>Methoden der Typen und Routinen der Unit, jede einmal.</summary>
    RoutineCount: Integer;
    /// <summary>Je Symbol: eine Deklaration und kein Rumpf im implementation-Teil (TFoo.Bar).</summary>
    Declared: TArray<Boolean>;
    HasMetrics: Boolean;
    Metrics: TArray<TRoutineMetrics>;
    /// <summary>Stelle in Data.Symbols → Stelle in Metrics.</summary>
    MetricOf: TDictionary<Integer, Integer>;
    HasLength: Boolean;
    UnitLength: Integer;
    HasTokens: Boolean;
    Tokens: TArray<TPascalToken>;
    Ancestry: TAncestry;
    HasForm: Boolean;
    FormClass: string;
    FormComponents: Integer;
    constructor Create(const AData: TUnitIndex; const APath: string);
    destructor Destroy; override;
  end;

  /// <summary>Ein Element der abgefragten Menge.</summary>
  TQueryElement = class
  public
    Owner: TQueryUnit;
    /// <summary>-1 = die Unit selbst.</summary>
    SymbolIndex: Integer;
    HasCallers: Boolean;
    Callers: TArray<TQueryCall>;
    HasCallees: Boolean;
    Callees: TArray<TQueryCall>;
    Inferred: Boolean;
    InferredDetail: string;
    Values: TArray<TQueryValue>;
    function Symbol: TIndexSymbol;
    function IsUnit: Boolean;
    function Name: string;
    function Location: TSymbolLocation;
  end;

  TQueryFacts = class
  private
    FSource: TQuerySource;
    FCollector: TMetricsCollector;
    FUnits: TObjectList<TQueryUnit>;
    FGraph: TUsesGraph;
    FInterfaceNames: TDictionary<string, TArray<string>>;
    procedure LoadCounts(AUnit: TQueryUnit);
    procedure LoadMetrics(AUnit: TQueryUnit);
    procedure LoadLength(AUnit: TQueryUnit);
    procedure LoadTokens(AUnit: TQueryUnit);
    procedure LoadForm(AUnit: TQueryUnit);
    function Ancestry(AUnit: TQueryUnit): TAncestry;
    function Graph: TUsesGraph;
    function CountsOf(AElement: TQueryElement): TTypeCounts;
    function MetricValue(AElement: TQueryElement; AKind: TMetricKind): TQueryValue;
    function CallsOf(AElement: TQueryElement; AIncoming: Boolean): TArray<TQueryCall>;
    /// <summary>Typ, um den es geht: das Element selbst oder der Typ, der das Mitglied deklariert.</summary>
    function TypeOf(AElement: TQueryElement; out ALocation: TSymbolLocation): Boolean;
    /// <summary>Kurznamen der Typ-Kette ab ALocation: der Typ selbst, die Vorfahren aus dem Index und die
    /// Vorfahren, wie sie geschrieben sind (auch wenn sie nicht im Index stehen).</summary>
    function Chain(AUnit: TQueryUnit; const ALocation: TSymbolLocation): TArray<TSymbolLocation>;
    function InterfaceClosure(const AName: string): TArray<string>;
    function Inherits(AElement: TQueryElement; const AName: string): Boolean;
    function Implements(AElement: TQueryElement; const AName: string): Boolean;
    function UsesTarget(AElement: TQueryElement; const AName: string): Boolean;
    function CallsTarget(AElement: TQueryElement; const AName: string): Boolean;
    function HasAttribute(AElement: TQueryElement; const AName: string): Boolean;
    procedure CheckCancelled;
    procedure AddUnitElements(AUnit: TQueryUnit; AEntity: TQueryEntity; AList: TObjectList<TQueryElement>;
      ASeen: TDictionary<string, Integer>);
    function TryPlainValue(AElement: TQueryElement; const AField: string; out AValue: TQueryValue): Boolean;
    function TryCountValue(AElement: TQueryElement; const AField: string; out AValue: TQueryValue): Boolean;
    function LinesValue(AElement: TQueryElement): TQueryValue;
    function TryMetricValue(AElement: TQueryElement; const AField: string; out AValue: TQueryValue): Boolean;
    function UsedByValue(AElement: TQueryElement): TQueryValue;
    function TryRelationValue(AElement: TQueryElement; const AField: string; out AValue: TQueryValue): Boolean;
    function LogicHolds(AElement: TQueryElement; ANode: TQueryLogicNode): Boolean;
    function PredicateHolds(AElement: TQueryElement; ANode: TQueryPredicateNode): Boolean;
  public
    constructor Create(const ASource: TQuerySource; ACollector: TMetricsCollector);
    destructor Destroy; override;
    /// <summary>Elemente der Menge; der Aufrufer gibt sie frei.</summary>
    function Elements(AEntity: TQueryEntity): TObjectList<TQueryElement>;
    function Value(AElement: TQueryElement; const AField: string): TQueryValue;
    function Holds(AElement: TQueryElement; ANode: TQueryNode): Boolean;
  end;

const
  cTypeKinds: TIndexSymbolKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
    TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType];
  cMethodKinds: TIndexSymbolKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_];
  cRoutineKinds: TIndexSymbolKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_,
    TIndexSymbolKind.Routine];
  /// <summary>Elemente zwischen zwei Blicken auf den Abbruch.</summary>
  cCancelStride = 256;

function VisibilityName(AVisibility: TIndexVisibility): string;
begin
  case AVisibility of
    TIndexVisibility.Published:
      Result := 'published';
    TIndexVisibility.Protected:
      Result := 'protected';
    TIndexVisibility.StrictProtected:
      Result := 'strict protected';
    TIndexVisibility.Private:
      Result := 'private';
    TIndexVisibility.StrictPrivate:
      Result := 'strict private';
  else
    Result := 'public';
  end;
end;

/// <summary>Name ohne Typargumente: TFoo&lt;T&gt;.Bar → TFoo.Bar.</summary>
function WithoutTypeArgs(const AName: string): string;
var
  mDepth, mIndex: Integer;
begin
  Result := '';
  mDepth := 0;
  for mIndex := 1 to Length(AName) do
  begin
    if AName[mIndex] = '<' then
    begin
      Inc(mDepth);
    end
    else if AName[mIndex] = '>' then
    begin
      if mDepth > 0 then
      begin
        Dec(mDepth);
      end;
    end
    else if mDepth = 0 then
    begin
      Result := Result + AName[mIndex];
    end;
  end;
end;

function RelativePath(const ARoot, AFileName: string): string;
var
  mRoot, mPath: string;
begin
  mPath := StringReplace(AFileName, '\', '/', [rfReplaceAll]);
  mRoot := StringReplace(ARoot, '\', '/', [rfReplaceAll]);
  if (mRoot <> '') and (mRoot[Length(mRoot)] <> '/') then
  begin
    mRoot := mRoot + '/';
  end;
  if (mRoot <> '') and (mRoot <> '/') and SameText(Copy(mPath, 1, Length(mRoot)), mRoot) then
  begin
    Result := Copy(mPath, Length(mRoot) + 1, MaxInt);
  end
  else
  begin
    // Außerhalb der Wurzel (RTL, andere Laufwerke): der Pfad, wie er ist; "c:/Programme/…" las sich schlecht.
    Result := AFileName;
  end;
end;

{ TCodeQueryEngine }

class function TCodeQueryEngine.ShortName(const AName: string): string;
var
  mDot: Integer;
begin
  Result := Trim(WithoutTypeArgs(AName));
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
  if StartsStr('&', Result) then
  begin
    Delete(Result, 1, 1);
  end;
end;

class function TCodeQueryEngine.UsesUnit(const AUses: TArray<string>; const AUnit: string;
  const ANamespaces: TArray<string>): Boolean;
var
  mName, mNamespace: string;
begin
  for mName in AUses do
  begin
    if SameText(mName, AUnit) then
    begin
      Exit(True);
    end;
    for mNamespace in ANamespaces do
    begin
      if SameText(mNamespace + '.' + mName, AUnit) or SameText(mName, mNamespace + '.' + AUnit) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

{ TQueryUnit }

constructor TQueryUnit.Create(const AData: TUnitIndex; const APath: string);
begin
  inherited Create;
  Data := AData;
  Path := APath;
  Counts := TDictionary<string, TTypeCounts>.Create;
  Types := TDictionary<string, Integer>.Create;
  MetricOf := TDictionary<Integer, Integer>.Create;
end;

destructor TQueryUnit.Destroy;
begin
  Ancestry.Free;
  MetricOf.Free;
  Types.Free;
  Counts.Free;
  inherited;
end;

{ TQueryElement }

function TQueryElement.Symbol: TIndexSymbol;
begin
  if SymbolIndex < 0 then
  begin
    Result := Default(TIndexSymbol);
  end
  else
  begin
    Result := Owner.Data.Symbols[SymbolIndex];
  end;
end;

function TQueryElement.IsUnit: Boolean;
begin
  Result := SymbolIndex < 0;
end;

function TQueryElement.Name: string;
begin
  if SymbolIndex < 0 then
  begin
    Result := Owner.Data.UnitName;
  end
  else
  begin
    Result := Owner.Data.Symbols[SymbolIndex].Name;
  end;
end;

function TQueryElement.Location: TSymbolLocation;
begin
  Result.UnitName := Owner.Data.UnitName;
  Result.FileName := Owner.Data.FileName;
  Result.Symbol := Symbol;
  if SymbolIndex >= 0 then
  begin
    Result.FileName := Owner.Data.SymbolFile(Result.Symbol);
  end;
end;

{ TQueryFacts }

constructor TQueryFacts.Create(const ASource: TQuerySource; ACollector: TMetricsCollector);
var
  mInScope: TDictionary<string, Boolean>;
  mFileName: string;
  mData: TUnitIndex;
begin
  inherited Create;
  FSource := ASource;
  FCollector := ACollector;
  FUnits := TObjectList<TQueryUnit>.Create(True);
  FInterfaceNames := TDictionary<string, TArray<string>>.Create;
  if FSource.Index = nil then
  begin
    Exit;
  end;
  mInScope := TDictionary<string, Boolean>.Create;
  try
    for mFileName in FSource.Files do
    begin
      mInScope.AddOrSetValue(LowerCase(mFileName), True);
    end;
    for mData in FSource.Index.Units do
    begin
      // Packages kennen nur requires und contains; Bibliotheks-Units gehören nicht zum Projekt.
      if mData.Library_ or SameText(ExtractFileExt(mData.FileName), '.dpk') then
      begin
        Continue;
      end;
      if (mInScope.Count > 0) and not mInScope.ContainsKey(LowerCase(mData.FileName)) then
      begin
        Continue;
      end;
      FUnits.Add(TQueryUnit.Create(mData, RelativePath(FSource.Root, mData.FileName)));
    end;
  finally
    mInScope.Free;
  end;
end;

destructor TQueryFacts.Destroy;
begin
  FGraph.Free;
  FInterfaceNames.Free;
  FUnits.Free;
  inherited;
end;

procedure TQueryFacts.CheckCancelled;
begin
  if Assigned(FSource.Cancelled) and FSource.Cancelled() then
  begin
    raise EQueryCancelled.Create(cTexts[TQueryEngineText.QueryCancelled].Text);
  end;
end;

function RangeHas(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := ((ARange.StartPos.Line < APosition.Line) or ((ARange.StartPos.Line = APosition.Line) and
    (ARange.StartPos.Character <= APosition.Character))) and ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

/// <summary>Trägt die Typen der Unit in Types ein und zählt die Klassen.</summary>
procedure CollectTypes(AUnit: TQueryUnit);
var
  mIndex: Integer;
  mSymbol: TIndexSymbol;
  mClasses: TDictionary<string, Boolean>;
begin
  mClasses := TDictionary<string, Boolean>.Create;
  try
    for mIndex := 0 to High(AUnit.Data.Symbols) do
    begin
      mSymbol := AUnit.Data.Symbols[mIndex];
      if not (mSymbol.Kind in cTypeKinds) then
      begin
        Continue;
      end;
      // Vorwärtsdeklaration und Deklaration: die spätere zählt.
      AUnit.Types.AddOrSetValue(UpperCase(mSymbol.QualifiedName), mIndex);
      if mSymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType] then
      begin
        mClasses.AddOrSetValue(UpperCase(mSymbol.QualifiedName), True);
      end;
    end;
    AUnit.ClassCount := mClasses.Count;
  finally
    mClasses.Free;
  end;
end;

/// <summary>Steht das Symbol AIndex (kein Typ) als Mitglied im Rumpf seines Typs oder ohne Typ in der Unit?
/// </summary>
function IsDeclaredMember(AUnit: TQueryUnit; AIndex: Integer): Boolean;
var
  mSymbol: TIndexSymbol;
  mType: Integer;
begin
  mSymbol := AUnit.Data.Symbols[AIndex];
  // Der Index führt auch die Rümpfe im implementation-Teil (procedure TFoo.Bar) als Methode von TFoo; Mitglied
  // ist nur, was im Rumpf des Typs steht.
  Result := (mSymbol.Container = '') or (mSymbol.FileName <> '') or
    (AUnit.Types.TryGetValue(UpperCase(mSymbol.Container), mType) and
    RangeHas(AUnit.Data.Symbols[mType].Range, mSymbol.Range.StartPos));
end;

/// <summary>Zählt das deklarierte Mitglied ASymbol bei seinem Typ.</summary>
procedure CountMember(AUnit: TQueryUnit; const ASymbol: TIndexSymbol);
var
  mKey: string;
  mCounts: TTypeCounts;
begin
  mKey := UpperCase(ASymbol.Container);
  if not AUnit.Counts.TryGetValue(mKey, mCounts) then
  begin
    mCounts := Default(TTypeCounts);
  end;
  if ASymbol.Kind in cMethodKinds then
  begin
    Inc(mCounts.Methods);
    Inc(AUnit.RoutineCount);
    if ASymbol.HasDirective('override') then
    begin
      Inc(mCounts.Overrides);
    end;
  end
  else if ASymbol.Kind = TIndexSymbolKind.Field then
  begin
    Inc(mCounts.Fields);
  end
  else
  begin
    Inc(mCounts.Properties);
  end;
  AUnit.Counts.AddOrSetValue(mKey, mCounts);
end;

procedure TQueryFacts.LoadCounts(AUnit: TQueryUnit);
var
  mIndex: Integer;
  mSymbol: TIndexSymbol;
begin
  if AUnit.HasCounts then
  begin
    Exit;
  end;
  AUnit.HasCounts := True;
  CollectTypes(AUnit);
  SetLength(AUnit.Declared, Length(AUnit.Data.Symbols));
  for mIndex := 0 to High(AUnit.Data.Symbols) do
  begin
    mSymbol := AUnit.Data.Symbols[mIndex];
    if mSymbol.Kind in cTypeKinds then
    begin
      Continue;
    end;
    AUnit.Declared[mIndex] := IsDeclaredMember(AUnit, mIndex);
    if AUnit.Declared[mIndex] and (mSymbol.Container <> '') and
      (mSymbol.Kind in cMethodKinds + [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) then
    begin
      CountMember(AUnit, mSymbol);
    end;
  end;
end;

/// <summary>Stellen in AMetrics je Name (groß, ohne Typargumente).</summary>
function MetricsByName(const AMetrics: TArray<TRoutineMetrics>): TObjectDictionary<string, TList<Integer>>;
var
  mIndex: Integer;
  mKey: string;
  mList: TList<Integer>;
begin
  Result := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  for mIndex := 0 to High(AMetrics) do
  begin
    mKey := UpperCase(WithoutTypeArgs(AMetrics[mIndex].Name));
    if not Result.TryGetValue(mKey, mList) then
    begin
      mList := TList<Integer>.Create;
      Result.Add(mKey, mList);
    end;
    mList.Add(mIndex);
  end;
end;

/// <summary>Erste freie Stelle aus ACandidates, zuerst mit AParameters Parametern; -1 = keine.</summary>
function ChooseMetric(AUnit: TQueryUnit; ACandidates: TList<Integer>; AUsed: TDictionary<Integer, Boolean>;
  AParameters: Integer): Integer;
var
  mCandidate: Integer;
begin
  Result := -1;
  for mCandidate in ACandidates do
  begin
    if AUsed.ContainsKey(mCandidate) then
    begin
      Continue;
    end;
    if AUnit.Metrics[mCandidate].Values[TMetricKind.ParameterCount] = AParameters then
    begin
      Exit(mCandidate);
    end;
    if Result < 0 then
    begin
      Result := mCandidate;
    end;
  end;
end;

procedure TQueryFacts.LoadMetrics(AUnit: TQueryUnit);
var
  mText: string;
  mByName: TObjectDictionary<string, TList<Integer>>;
  mList: TList<Integer>;
  mIndex, mChosen: Integer;
  mUsed: TDictionary<Integer, Boolean>;
  mSymbol: TIndexSymbol;
begin
  if AUnit.HasMetrics then
  begin
    Exit;
  end;
  AUnit.HasMetrics := True;
  if not (Assigned(FSource.ReadText) and FSource.ReadText(AUnit.Data.FileName, mText)) then
  begin
    Exit;
  end;
  AUnit.Metrics := FCollector.FileRoutines(AUnit.Data.FileName, mText);
  mByName := MetricsByName(AUnit.Metrics);
  mUsed := TDictionary<Integer, Boolean>.Create;
  try
    // Alle Routinen der Unit auf einmal zuordnen, damit Überladungen unabhängig von der Reihenfolge der Abfrage
    // dieselbe Implementierung bekommen: zuerst die mit gleicher Parameterzahl, sonst die erste freie.
    for mIndex := 0 to High(AUnit.Data.Symbols) do
    begin
      mSymbol := AUnit.Data.Symbols[mIndex];
      if not (mSymbol.Kind in cRoutineKinds) or (mSymbol.FileName <> '') or
        not mByName.TryGetValue(UpperCase(WithoutTypeArgs(mSymbol.QualifiedName)), mList) then
      begin
        Continue;
      end;
      mChosen := ChooseMetric(AUnit, mList, mUsed, mSymbol.MaxArgs);
      if mChosen >= 0 then
      begin
        mUsed.Add(mChosen, True);
        AUnit.MetricOf.AddOrSetValue(mIndex, mChosen);
      end;
    end;
  finally
    mUsed.Free;
    mByName.Free;
  end;
end;

procedure TQueryFacts.LoadLength(AUnit: TQueryUnit);
var
  mText: string;
  mItem: TStructureMetrics;
begin
  if AUnit.HasLength then
  begin
    Exit;
  end;
  AUnit.HasLength := True;
  AUnit.UnitLength := -1;
  if not (Assigned(FSource.ReadText) and FSource.ReadText(AUnit.Data.FileName, mText)) then
  begin
    Exit;
  end;
  for mItem in TMetricsCalculator.StructureForText(mText) do
  begin
    if mItem.Kind = TStructureKind.UnitLength then
    begin
      AUnit.UnitLength := mItem.Value;
    end;
  end;
end;

procedure TQueryFacts.LoadTokens(AUnit: TQueryUnit);
var
  mText: string;
  mToken: TPascalToken;
  mCount: Integer;
begin
  if AUnit.HasTokens then
  begin
    Exit;
  end;
  AUnit.HasTokens := True;
  if not (Assigned(FSource.ReadText) and FSource.ReadText(AUnit.Data.FileName, mText)) then
  begin
    Exit;
  end;
  AUnit.Tokens := TPascalLexer.Tokenize(mText);
  mCount := 0;
  for mToken in AUnit.Tokens do
  begin
    if not (mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      AUnit.Tokens[mCount] := mToken;
      Inc(mCount);
    end;
  end;
  SetLength(AUnit.Tokens, mCount);
end;

function CountComponents(AObject: TDfmObject): Integer;
var
  mChild: TDfmObject;
begin
  Result := 0;
  for mChild in AObject.Children do
  begin
    // Collection-Einträge (item) haben keinen Namen und sind keine Komponenten.
    if mChild.Name <> '' then
    begin
      Inc(Result);
    end;
    Inc(Result, CountComponents(mChild));
  end;
end;

procedure TQueryFacts.LoadForm(AUnit: TQueryUnit);
var
  mText, mFormText, mDecoded, mFile: string;
  mDocument: TDfmDocument;
begin
  if AUnit.HasForm then
  begin
    Exit;
  end;
  AUnit.HasForm := True;
  if not Assigned(FSource.ReadText) or not FSource.ReadText(AUnit.Data.FileName, mText) then
  begin
    Exit;
  end;
  for mFile in TFormFiles.FormFiles(AUnit.Data.FileName, mText) do
  begin
    if not FSource.ReadText(mFile, mFormText) then
    begin
      Continue;
    end;
    // Binäre Formulardateien erst in Text umwandeln.
    if TDfmBinary.FromDecodedText(mFormText, mDecoded) then
    begin
      mFormText := mDecoded;
    end;
    mDocument := TDfmParser.Parse(mFormText);
    try
      if mDocument.Root = nil then
      begin
        Continue;
      end;
      AUnit.FormClass := mDocument.Root.TypeName;
      AUnit.FormComponents := CountComponents(mDocument.Root);
      Exit;
    finally
      mDocument.Free;
    end;
  end;
end;

function TQueryFacts.Ancestry(AUnit: TQueryUnit): TAncestry;
begin
  if AUnit.Ancestry = nil then
  begin
    AUnit.Ancestry := TAncestry.Create(FSource.Index, AUnit.Data);
  end;
  Result := AUnit.Ancestry;
end;

function TQueryFacts.Graph: TUsesGraph;
var
  mUnits: TArray<TUnitIndex>;
  mUnit: TQueryUnit;
  mOptions: TUsesGraphOptions;
begin
  if FGraph = nil then
  begin
    mUnits := nil;
    for mUnit in FUnits do
    begin
      mUnits := mUnits + [mUnit.Data];
    end;
    mOptions := TUsesGraphOptions.Default;
    mOptions.Root := FSource.Root;
    mOptions.Namespaces := FSource.Namespaces;
    FGraph := TUsesGraph.Create(mUnits, mOptions);
  end;
  Result := FGraph;
end;

function TQueryFacts.CountsOf(AElement: TQueryElement): TTypeCounts;
begin
  LoadCounts(AElement.Owner);
  if not AElement.Owner.Counts.TryGetValue(UpperCase(AElement.Symbol.QualifiedName), Result) then
  begin
    Result := Default(TTypeCounts);
  end;
end;

function TQueryFacts.MetricValue(AElement: TQueryElement; AKind: TMetricKind): TQueryValue;
var
  mPosition: Integer;
begin
  LoadMetrics(AElement.Owner);
  if AElement.Owner.MetricOf.TryGetValue(AElement.SymbolIndex, mPosition) then
  begin
    Result := TQueryValue.OfNumber(AElement.Owner.Metrics[mPosition].Values[AKind]);
  end
  else
  begin
    // Ohne Rumpf (abstract, external, Interface-Methode) gibt es keine Kennzahl.
    Result := TQueryValue.Empty;
  end;
end;

function TQueryFacts.CallsOf(AElement: TQueryElement; AIncoming: Boolean): TArray<TQueryCall>;
var
  mCall: TQueryCall;
begin
  if not Assigned(FSource.Calls) or AElement.IsUnit then
  begin
    Exit(nil);
  end;
  if AIncoming and not AElement.HasCallers then
  begin
    CheckCancelled;
    AElement.Callers := FSource.Calls(AElement.Location, True);
    AElement.HasCallers := True;
  end
  else if not AIncoming and not AElement.HasCallees then
  begin
    CheckCancelled;
    AElement.Callees := FSource.Calls(AElement.Location, False);
    AElement.HasCallees := True;
  end;
  if AIncoming then
  begin
    Result := AElement.Callers;
  end
  else
  begin
    Result := AElement.Callees;
  end;
  for mCall in Result do
  begin
    if mCall.Inferred and not AElement.Inferred then
    begin
      AElement.Inferred := True;
      AElement.InferredDetail := cTexts[TQueryEngineText.Inferred].Fmt([mCall.Name, mCall.Reason]);
    end;
  end;
end;

function TQueryFacts.TypeOf(AElement: TQueryElement; out ALocation: TSymbolLocation): Boolean;
var
  mSymbol: TIndexSymbol;
  mPosition: Integer;
begin
  ALocation := Default(TSymbolLocation);
  if AElement.IsUnit then
  begin
    Exit(False);
  end;
  mSymbol := AElement.Symbol;
  if mSymbol.Kind in cTypeKinds then
  begin
    ALocation := AElement.Location;
    Exit(True);
  end;
  if mSymbol.Container = '' then
  begin
    Exit(False);
  end;
  LoadCounts(AElement.Owner);
  Result := AElement.Owner.Types.TryGetValue(UpperCase(mSymbol.Container), mPosition);
  if Result then
  begin
    ALocation.UnitName := AElement.Owner.Data.UnitName;
    ALocation.FileName := AElement.Owner.Data.FileName;
    ALocation.Symbol := AElement.Owner.Data.Symbols[mPosition];
  end;
end;

function TQueryFacts.Chain(AUnit: TQueryUnit; const ALocation: TSymbolLocation): TArray<TSymbolLocation>;
var
  mComplete, mObjectMissing: Boolean;
begin
  Result := [ALocation];
  if ALocation.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType] then
  begin
    Result := Result + Ancestry(AUnit).Ancestors(ALocation, mComplete, mObjectMissing);
  end;
end;

/// <summary>Vorfahren aller Interfaces namens AName im Index, als Kurznamen.</summary>
function InterfaceAncestors(const AIndex: ISymbolIndex; const AName: string): TArray<string>;
var
  mLocation: TSymbolLocation;
  mAncestor: string;
begin
  Result := nil;
  for mLocation in AIndex.FindSymbols(AName) do
  begin
    if mLocation.Symbol.Kind <> TIndexSymbolKind.InterfaceType then
    begin
      Continue;
    end;
    for mAncestor in mLocation.Symbol.Ancestors do
    begin
      Result := Result + [TCodeQueryEngine.ShortName(mAncestor)];
    end;
  end;
end;

function TQueryFacts.InterfaceClosure(const AName: string): TArray<string>;
var
  mKey, mName, mAncestor: string;
  mQueue: TQueue<string>;
  mSeen: TDictionary<string, Boolean>;
begin
  mKey := UpperCase(TCodeQueryEngine.ShortName(AName));
  if FInterfaceNames.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result := nil;
  mQueue := TQueue<string>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mQueue.Enqueue(TCodeQueryEngine.ShortName(AName));
    while mQueue.Count > 0 do
    begin
      mName := mQueue.Dequeue;
      if (mName = '') or mSeen.ContainsKey(UpperCase(mName)) then
      begin
        Continue;
      end;
      mSeen.Add(UpperCase(mName), True);
      Result := Result + [mName];
      for mAncestor in InterfaceAncestors(FSource.Index, mName) do
      begin
        mQueue.Enqueue(mAncestor);
      end;
    end;
  finally
    mSeen.Free;
    mQueue.Free;
  end;
  FInterfaceNames.Add(mKey, Result);
end;

function ContainsName(const ANames: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in ANames do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Nennt die Typ-Kette AChain den Vorfahren ATarget (Kurzname)? Der erste Eintrag ist der Typ selbst.
/// </summary>
function ChainNames(const AChain: TArray<TSymbolLocation>; const ATarget: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to High(AChain) do
  begin
    // Der erste Eintrag ist der Typ selbst; er erbt nicht von sich. Der Vorfahr, wie er geschrieben ist, zählt
    // auch, wenn er selbst nicht im Index steht (VCL nicht indiziert).
    if ((mIndex > 0) and SameText(TCodeQueryEngine.ShortName(AChain[mIndex].Symbol.Name), ATarget)) or
      ((Length(AChain[mIndex].Symbol.Ancestors) > 0) and
      SameText(TCodeQueryEngine.ShortName(AChain[mIndex].Symbol.Ancestors[0]), ATarget)) then
    begin
      Exit(True);
    end;
  end;
end;

function TQueryFacts.Inherits(AElement: TQueryElement; const AName: string): Boolean;
var
  mType: TSymbolLocation;
  mTarget, mAncestor: string;
begin
  Result := False;
  if not TypeOf(AElement, mType) then
  begin
    Exit;
  end;
  mTarget := TCodeQueryEngine.ShortName(AName);
  if mType.Symbol.Kind <> TIndexSymbolKind.InterfaceType then
  begin
    Exit(ChainNames(Chain(AElement.Owner, mType), mTarget));
  end;
  for mAncestor in mType.Symbol.Ancestors do
  begin
    if ContainsName(InterfaceClosure(mAncestor), mTarget) then
    begin
      Exit(True);
    end;
  end;
end;

function TQueryFacts.Implements(AElement: TQueryElement; const AName: string): Boolean;
var
  mType, mLink: TSymbolLocation;
  mTarget, mName: string;
  mIndex, mFirst: Integer;
begin
  if not TypeOf(AElement, mType) then
  begin
    Exit(False);
  end;
  mTarget := TCodeQueryEngine.ShortName(AName);
  // Ein Interface „setzt um“, wovon es abgeleitet ist.
  if mType.Symbol.Kind = TIndexSymbolKind.InterfaceType then
  begin
    Exit(Inherits(AElement, AName));
  end;
  for mLink in Chain(AElement.Owner, mType) do
  begin
    // Bei Klassen ist der erste Eintrag der Vorfahr, die übrigen sind Interfaces.
    mFirst := 0;
    if mLink.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType] then
    begin
      mFirst := 1;
    end;
    for mIndex := mFirst to High(mLink.Symbol.Ancestors) do
    begin
      for mName in InterfaceClosure(mLink.Symbol.Ancestors[mIndex]) do
      begin
        if SameText(mName, mTarget) then
        begin
          Exit(True);
        end;
      end;
    end;
  end;
  Result := False;
end;

function TQueryFacts.UsesTarget(AElement: TQueryElement; const AName: string): Boolean;
begin
  Result := TCodeQueryEngine.UsesUnit(AElement.Owner.Data.InterfaceUses, AName, FSource.Namespaces) or
    TCodeQueryEngine.UsesUnit(AElement.Owner.Data.ImplementationUses, AName, FSource.Namespaces);
end;

function TQueryFacts.CallsTarget(AElement: TQueryElement; const AName: string): Boolean;
var
  mCall: TQueryCall;
  mTarget: string;
begin
  mTarget := WithoutTypeArgs(Trim(AName));
  for mCall in CallsOf(AElement, False) do
  begin
    if SameText(WithoutTypeArgs(mCall.Name), mTarget) or
      ((Pos('.', mTarget) = 0) and SameText(TCodeQueryEngine.ShortName(mCall.Name), mTarget)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TQueryFacts.HasAttribute(AElement: TQueryElement; const AName: string): Boolean;
var
  mTarget, mName: string;
  mSymbol: TIndexSymbol;
begin
  if AElement.IsUnit then
  begin
    Exit(False);
  end;
  mSymbol := AElement.Symbol;
  // Deklarationen aus $I-Dateien: Attribute stehen in einer anderen Datei.
  if mSymbol.FileName <> '' then
  begin
    Exit(False);
  end;
  LoadTokens(AElement.Owner);
  mTarget := TCodeQueryEngine.ShortName(AName);
  if EndsText('Attribute', mTarget) and (Length(mTarget) > Length('Attribute')) then
  begin
    mTarget := Copy(mTarget, 1, Length(mTarget) - Length('Attribute'));
  end;
  for mName in TConsideredUsed.AttributesAt(AElement.Owner.Tokens, mSymbol.Range.StartPos) do
  begin
    if SameText(mName, mTarget) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Gehört ASymbol aus AUnit zur Menge AEntity (ohne Prüfung, ob es ein deklariertes Mitglied ist)?
/// </summary>
function TakesSymbol(AEntity: TQueryEntity; AUnit: TQueryUnit; const ASymbol: TIndexSymbol): Boolean;
begin
  case AEntity of
    TQueryEntity.Classes:
      Result := ASymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType];
    TQueryEntity.Records:
      Result := ASymbol.Kind = TIndexSymbolKind.RecordType;
    TQueryEntity.Interfaces:
      Result := ASymbol.Kind = TIndexSymbolKind.InterfaceType;
    TQueryEntity.Forms:
      Result := (ASymbol.Kind = TIndexSymbolKind.ClassType) and (AUnit.FormClass <> '') and
        SameText(ASymbol.QualifiedName, AUnit.FormClass);
    TQueryEntity.Methods:
      Result := (ASymbol.Kind in cMethodKinds) and (ASymbol.Container <> '');
    TQueryEntity.Routines:
      Result := (ASymbol.Kind = TIndexSymbolKind.Routine) and (ASymbol.Container = '');
    TQueryEntity.Fields:
      Result := (ASymbol.Kind = TIndexSymbolKind.Field) and (ASymbol.Container <> '');
    TQueryEntity.Properties:
      Result := (ASymbol.Kind = TIndexSymbolKind.Property_) and (ASymbol.Container <> '');
  else
    Result := False;
  end;
end;

/// <summary>Schlüssel, unter dem ein Element nur einmal zählt: Typen mit Vorwärtsdeklaration und Deklaration,
/// Routinen mit Deklaration im interface und Rumpf im implementation; '' = jedes Symbol zählt.</summary>
function ElementKey(AEntity: TQueryEntity; const ASymbol: TIndexSymbol): string;
begin
  if AEntity in TQueryCatalog.cTypeEntities then
  begin
    Result := UpperCase(ASymbol.QualifiedName);
  end
  else if AEntity = TQueryEntity.Routines then
  begin
    Result := UpperCase(ASymbol.Name) + '(' + UpperCase(string.Join(',', ASymbol.ParamTypes)) + ')';
  end
  else
  begin
    Result := '';
  end;
end;

function NewElement(AUnit: TQueryUnit; ASymbolIndex: Integer): TQueryElement;
begin
  Result := TQueryElement.Create;
  Result.Owner := AUnit;
  Result.SymbolIndex := ASymbolIndex;
end;

/// <summary>Steht unter AKey schon ein Element in AList? Bei Typen gilt dann die spätere Deklaration AIndex,
/// bei Routinen bleibt die erste. Sonst wird AKey für das nächste Element vorgemerkt.</summary>
function IsSeenElement(AEntity: TQueryEntity; const AKey: string; AIndex: Integer; AList: TObjectList<TQueryElement>;
  ASeen: TDictionary<string, Integer>): Boolean;
var
  mSlot: Integer;
begin
  Result := (AKey <> '') and ASeen.TryGetValue(AKey, mSlot);
  if Result and (AEntity in TQueryCatalog.cTypeEntities) then
  begin
    AList[mSlot].SymbolIndex := AIndex;
  end
  else if not Result and (AKey <> '') then
  begin
    ASeen.Add(AKey, AList.Count);
  end;
end;

procedure TQueryFacts.AddUnitElements(AUnit: TQueryUnit; AEntity: TQueryEntity; AList: TObjectList<TQueryElement>;
  ASeen: TDictionary<string, Integer>);
var
  mIndex: Integer;
  mSymbol: TIndexSymbol;
begin
  if AEntity in TQueryCatalog.cMemberEntities then
  begin
    LoadCounts(AUnit);
  end;
  for mIndex := 0 to High(AUnit.Data.Symbols) do
  begin
    mSymbol := AUnit.Data.Symbols[mIndex];
    if TakesSymbol(AEntity, AUnit, mSymbol) and
      (not (AEntity in TQueryCatalog.cMemberEntities) or AUnit.Declared[mIndex]) and
      not IsSeenElement(AEntity, ElementKey(AEntity, mSymbol), mIndex, AList, ASeen) then
    begin
      AList.Add(NewElement(AUnit, mIndex));
    end;
  end;
end;

function TQueryFacts.Elements(AEntity: TQueryEntity): TObjectList<TQueryElement>;
var
  mUnit: TQueryUnit;
  mSeen: TDictionary<string, Integer>;
begin
  Result := TObjectList<TQueryElement>.Create(True);
  mSeen := TDictionary<string, Integer>.Create;
  try
    try
      for mUnit in FUnits do
      begin
        CheckCancelled;
        if AEntity = TQueryEntity.Units then
        begin
          Result.Add(NewElement(mUnit, -1));
          Continue;
        end;
        if AEntity = TQueryEntity.Forms then
        begin
          LoadForm(mUnit);
        end;
        mSeen.Clear;
        AddUnitElements(mUnit, AEntity, Result, mSeen);
      end;
    except
      // Abbruch (EQueryCancelled) mitten im Sammeln: die Liste gehört noch niemandem.
      Result.Free;
      raise;
    end;
  finally
    mSeen.Free;
  end;
end;

function LineValue(AElement: TQueryElement): TQueryValue;
begin
  if AElement.IsUnit then
  begin
    Result := TQueryValue.OfNumber(1);
  end
  else
  begin
    Result := TQueryValue.OfNumber(AElement.Symbol.SelectionRange.StartPos.Line + 1);
  end;
end;

function TypeValue(const ASymbol: TIndexSymbol): TQueryValue;
var
  mText: string;
begin
  mText := ASymbol.TypeName;
  if ASymbol.TypeArgs <> '' then
  begin
    mText := mText + '<' + ASymbol.TypeArgs + '>';
  end;
  Result := TQueryValue.OfText(mText);
end;

function AncestorValue(const ASymbol: TIndexSymbol): TQueryValue;
begin
  if Length(ASymbol.Ancestors) > 0 then
  begin
    Result := TQueryValue.OfText(ASymbol.Ancestors[0]);
  end
  else if ASymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType] then
  begin
    Result := TQueryValue.OfText('TObject');
  end
  else
  begin
    Result := TQueryValue.OfText('');
  end;
end;

function TQueryFacts.TryPlainValue(AElement: TQueryElement; const AField: string; out AValue: TQueryValue): Boolean;
begin
  Result := True;
  case IndexText(AField, ['name', 'unit', 'path', 'line', 'class', 'visibility', 'type', 'params', 'virtual',
    'ancestor']) of
    0:
      AValue := TQueryValue.OfText(AElement.Name);
    1:
      AValue := TQueryValue.OfText(AElement.Owner.Data.UnitName);
    2:
      AValue := TQueryValue.OfText(RelativePath(FSource.Root, AElement.Location.FileName));
    3:
      AValue := LineValue(AElement);
    4:
      AValue := TQueryValue.OfText(AElement.Symbol.Container);
    5:
      AValue := TQueryValue.OfText(VisibilityName(AElement.Symbol.Visibility));
    6:
      AValue := TypeValue(AElement.Symbol);
    7:
      AValue := TQueryValue.OfNumber(AElement.Symbol.MaxArgs);
    8:
      AValue := TQueryValue.OfFlag(AElement.Symbol.IsVirtual);
    9:
      AValue := AncestorValue(AElement.Symbol);
  else
    Result := False;
  end;
end;

function TQueryFacts.TryCountValue(AElement: TQueryElement; const AField: string; out AValue: TQueryValue): Boolean;
begin
  Result := True;
  case IndexText(AField, ['classes', 'methods', 'fields', 'properties', 'overrides', 'uses']) of
    0:
      begin
        LoadCounts(AElement.Owner);
        AValue := TQueryValue.OfNumber(AElement.Owner.ClassCount);
      end;
    1:
      if AElement.IsUnit then
      begin
        LoadCounts(AElement.Owner);
        AValue := TQueryValue.OfNumber(AElement.Owner.RoutineCount);
      end
      else
      begin
        AValue := TQueryValue.OfNumber(CountsOf(AElement).Methods);
      end;
    2:
      AValue := TQueryValue.OfNumber(CountsOf(AElement).Fields);
    3:
      AValue := TQueryValue.OfNumber(CountsOf(AElement).Properties);
    4:
      if AElement.Symbol.Kind in cMethodKinds then
      begin
        AValue := TQueryValue.OfNumber(Ord(AElement.Symbol.HasDirective('override')));
      end
      else
      begin
        AValue := TQueryValue.OfNumber(CountsOf(AElement).Overrides);
      end;
    5:
      AValue := TQueryValue.OfNumber(Length(AElement.Owner.Data.InterfaceUses) +
        Length(AElement.Owner.Data.ImplementationUses));
  else
    Result := False;
  end;
end;

function TQueryFacts.LinesValue(AElement: TQueryElement): TQueryValue;
var
  mSymbol: TIndexSymbol;
begin
  if AElement.IsUnit then
  begin
    LoadLength(AElement.Owner);
    if AElement.Owner.UnitLength < 0 then
    begin
      Exit(TQueryValue.Empty);
    end;
    Exit(TQueryValue.OfNumber(AElement.Owner.UnitLength));
  end;
  mSymbol := AElement.Symbol;
  if mSymbol.Kind in cRoutineKinds then
  begin
    Result := MetricValue(AElement, TMetricKind.MethodLength);
  end
  else
  begin
    Result := TQueryValue.OfNumber(mSymbol.Range.EndPos.Line - mSymbol.Range.StartPos.Line + 1);
  end;
end;

function TQueryFacts.TryMetricValue(AElement: TQueryElement; const AField: string; out AValue: TQueryValue): Boolean;
begin
  Result := True;
  case IndexText(AField, ['lines', 'complexity', 'cognitive', 'nesting', 'locals', 'exits']) of
    0:
      AValue := LinesValue(AElement);
    1:
      AValue := MetricValue(AElement, TMetricKind.Cyclomatic);
    2:
      AValue := MetricValue(AElement, TMetricKind.Cognitive);
    3:
      AValue := MetricValue(AElement, TMetricKind.NestingDepth);
    4:
      AValue := MetricValue(AElement, TMetricKind.LocalCount);
    5:
      AValue := MetricValue(AElement, TMetricKind.ExitPoints);
  else
    Result := False;
  end;
end;

function TQueryFacts.UsedByValue(AElement: TQueryElement): TQueryValue;
var
  mNode: Integer;
begin
  mNode := Graph.IndexOfFile(AElement.Owner.Data.FileName);
  if mNode < 0 then
  begin
    Result := TQueryValue.OfNumber(0);
  end
  else
  begin
    Result := TQueryValue.OfNumber(Length(Graph.DirectDependents(mNode, [TUsesSection.Interface_,
      TUsesSection.Implementation_])));
  end;
end;

function TQueryFacts.TryRelationValue(AElement: TQueryElement; const AField: string;
  out AValue: TQueryValue): Boolean;
var
  mField: Integer;
begin
  Result := True;
  mField := IndexText(AField, ['callers', 'callees', 'usedBy', 'components']);
  case mField of
    0, 1:
      if Assigned(FSource.Calls) then
      begin
        AValue := TQueryValue.OfNumber(Length(CallsOf(AElement, mField = 0)));
      end
      else
      begin
        AValue := TQueryValue.Empty;
      end;
    2:
      AValue := UsedByValue(AElement);
    3:
      begin
        LoadForm(AElement.Owner);
        AValue := TQueryValue.OfNumber(AElement.Owner.FormComponents);
      end;
  else
    Result := False;
  end;
end;

function TQueryFacts.Value(AElement: TQueryElement; const AField: string): TQueryValue;
begin
  if not TryPlainValue(AElement, AField, Result) and not TryCountValue(AElement, AField, Result) and
    not TryMetricValue(AElement, AField, Result) and not TryRelationValue(AElement, AField, Result) then
  begin
    Result := TQueryValue.Empty;
  end;
end;

function ValueHolds(const AValue: TQueryValue; AOperator: TQueryOperator; const AExpected: TQueryValue): Boolean;
var
  mOrder: Integer;
begin
  if AValue.Kind = TQueryValueKind.None then
  begin
    Exit(False);
  end;
  if AOperator in [TQueryOperator.Like, TQueryOperator.NotLike] then
  begin
    Result := TConsideredUsed.Matches(AExpected.Text, AValue.Text);
    if AOperator = TQueryOperator.NotLike then
    begin
      Result := not Result;
    end;
    Exit;
  end;
  if AValue.Kind = TQueryValueKind.Text then
  begin
    mOrder := CompareText(AValue.Text, AExpected.Text);
  end
  else if AValue.Number < AExpected.Number then
  begin
    mOrder := -1;
  end
  else if AValue.Number > AExpected.Number then
  begin
    mOrder := 1;
  end
  else
  begin
    mOrder := 0;
  end;
  case AOperator of
    TQueryOperator.Equal:
      Result := mOrder = 0;
    TQueryOperator.NotEqual:
      Result := mOrder <> 0;
    TQueryOperator.Less:
      Result := mOrder < 0;
    TQueryOperator.Greater:
      Result := mOrder > 0;
    TQueryOperator.LessEqual:
      Result := mOrder <= 0;
  else
    Result := mOrder >= 0;
  end;
end;

function TQueryFacts.LogicHolds(AElement: TQueryElement; ANode: TQueryLogicNode): Boolean;
var
  mItem: TQueryNode;
  mAll: Boolean;
begin
  // and: gilt, bis ein Glied nicht gilt; or: gilt nicht, bis ein Glied gilt.
  mAll := ANode.Logic = TQueryLogic.And_;
  for mItem in ANode.Items do
  begin
    if Holds(AElement, mItem) <> mAll then
    begin
      Exit(not mAll);
    end;
  end;
  Result := mAll;
end;

function TQueryFacts.PredicateHolds(AElement: TQueryElement; ANode: TQueryPredicateNode): Boolean;
begin
  case ANode.Kind of
    TQueryPredicateKind.Inherits:
      Result := Inherits(AElement, ANode.Argument);
    TQueryPredicateKind.Implements:
      Result := Implements(AElement, ANode.Argument);
    TQueryPredicateKind.Uses_:
      Result := UsesTarget(AElement, ANode.Argument);
    TQueryPredicateKind.Calls:
      Result := CallsTarget(AElement, ANode.Argument);
  else
    Result := HasAttribute(AElement, ANode.Argument);
  end;
end;

function TQueryFacts.Holds(AElement: TQueryElement; ANode: TQueryNode): Boolean;
var
  mCompare: TQueryCompareNode;
begin
  if ANode = nil then
  begin
    Result := True;
  end
  else if ANode is TQueryLogicNode then
  begin
    Result := LogicHolds(AElement, TQueryLogicNode(ANode));
  end
  else if ANode is TQueryNotNode then
  begin
    Result := not Holds(AElement, TQueryNotNode(ANode).Inner);
  end
  else if ANode is TQueryPredicateNode then
  begin
    Result := PredicateHolds(AElement, TQueryPredicateNode(ANode));
  end
  else
  begin
    mCompare := ANode as TQueryCompareNode;
    Result := ValueHolds(Value(AElement, mCompare.Field.Name), mCompare.Comparison, mCompare.Value);
  end;
end;

{ Reihenfolge der and-Glieder }

function FieldCost(const AField: string): Integer;
begin
  case IndexText(AField, ['callers', 'callees', 'complexity', 'cognitive', 'nesting', 'locals', 'exits', 'lines',
    'usedBy', 'components']) of
    0, 1:
      Result := 4;
    2..9:
      Result := 2;
  else
    Result := 1;
  end;
end;

function NodeCost(ANode: TQueryNode): Integer;
var
  mItem: TQueryNode;
begin
  Result := 1;
  if ANode is TQueryLogicNode then
  begin
    for mItem in TQueryLogicNode(ANode).Items do
    begin
      Result := Max(Result, NodeCost(mItem));
    end;
  end
  else if ANode is TQueryNotNode then
  begin
    Result := NodeCost(TQueryNotNode(ANode).Inner);
  end
  else if ANode is TQueryCompareNode then
  begin
    Result := FieldCost(TQueryCompareNode(ANode).Field.Name);
  end
  else if ANode is TQueryPredicateNode then
  begin
    case TQueryPredicateNode(ANode).Kind of
      TQueryPredicateKind.Calls:
        Result := 4;
      TQueryPredicateKind.Uses_:
        Result := 1;
    else
      Result := 2;
    end;
  end;
end;

/// <summary>Ordnet die Glieder jeder and-Kette nach Kosten, bei Gleichstand in der geschriebenen Reihenfolge.
/// </summary>
procedure OrderByCost(ANode: TQueryNode);
var
  mItems: TArray<TQueryNode>;
  mCosts: TArray<Integer>;
  mIndex, mInner, mCost: Integer;
  mNode: TQueryNode;
  mList: TObjectList<TQueryNode>;
begin
  if ANode is TQueryNotNode then
  begin
    OrderByCost(TQueryNotNode(ANode).Inner);
  end;
  if not (ANode is TQueryLogicNode) then
  begin
    Exit;
  end;
  mList := TQueryLogicNode(ANode).Items;
  for mNode in mList do
  begin
    OrderByCost(mNode);
  end;
  if TQueryLogicNode(ANode).Logic <> TQueryLogic.And_ then
  begin
    Exit;
  end;
  mItems := mList.ToArray;
  SetLength(mCosts, Length(mItems));
  for mIndex := 0 to High(mItems) do
  begin
    mCosts[mIndex] := NodeCost(mItems[mIndex]);
  end;
  // Einfügen ist stabil.
  for mIndex := 1 to High(mItems) do
  begin
    mNode := mItems[mIndex];
    mCost := mCosts[mIndex];
    mInner := mIndex - 1;
    while (mInner >= 0) and (mCosts[mInner] > mCost) do
    begin
      mItems[mInner + 1] := mItems[mInner];
      mCosts[mInner + 1] := mCosts[mInner];
      Dec(mInner);
    end;
    mItems[mInner + 1] := mNode;
    mCosts[mInner + 1] := mCost;
  end;
  mList.OwnsObjects := False;
  try
    mList.Clear;
    for mNode in mItems do
    begin
      mList.Add(mNode);
    end;
  finally
    mList.OwnsObjects := True;
  end;
end;

function CompareValues(const A, B: TQueryValue): Integer;
begin
  // Ohne Wert ans Ende, unabhängig von der Richtung.
  if (A.Kind = TQueryValueKind.None) or (B.Kind = TQueryValueKind.None) then
  begin
    Exit(Ord(A.Kind = TQueryValueKind.None) - Ord(B.Kind = TQueryValueKind.None));
  end;
  if (A.Kind = TQueryValueKind.Text) or (B.Kind = TQueryValueKind.Text) then
  begin
    Exit(CompareText(A.Text, B.Text));
  end;
  if A.Number < B.Number then
  begin
    Result := -1;
  end
  else if A.Number > B.Number then
  begin
    Result := 1;
  end
  else
  begin
    Result := 0;
  end;
end;

function CompareRows(const A, B: TQueryRow): Integer;
begin
  Result := CompareText(A.UnitName, B.UnitName);
  if Result = 0 then
  begin
    Result := A.Range.StartPos.Line - B.Range.StartPos.Line;
  end;
  if Result = 0 then
  begin
    Result := A.Range.StartPos.Character - B.Range.StartPos.Character;
  end;
  if Result = 0 then
  begin
    Result := CompareText(A.QualifiedName, B.QualifiedName);
  end;
  if Result = 0 then
  begin
    Result := CompareText(A.Path, B.Path);
  end;
  if Result = 0 then
  begin
    Result := CompareStr(A.Path, B.Path);
  end;
end;

/// <summary>Vergleich nach AColumn (-1 = keine), dann eindeutig nach Unit, Zeile, Name und Pfad.</summary>
function RowComparer(AColumn: Integer; ADescending: Boolean): IComparer<TQueryRow>;
begin
  Result := TComparer<TQueryRow>.Construct(
    function(const A, B: TQueryRow): Integer
    begin
      Result := 0;
      if AColumn >= 0 then
      begin
        Result := CompareValues(A.Values[AColumn], B.Values[AColumn]);
        if ADescending and (A.Values[AColumn].Kind <> TQueryValueKind.None) and
          (B.Values[AColumn].Kind <> TQueryValueKind.None) then
        begin
          Result := -Result;
        end;
      end;
      if Result = 0 then
      begin
        Result := CompareRows(A, B);
      end;
    end);
end;

function RowOf(AElement: TQueryElement; const ARoot: string): TQueryRow;
var
  mSymbol: TIndexSymbol;
begin
  Result := Default(TQueryRow);
  Result.Name := AElement.Name;
  Result.UnitName := AElement.Owner.Data.UnitName;
  Result.FileName := AElement.Location.FileName;
  Result.Path := RelativePath(ARoot, Result.FileName);
  if not AElement.IsUnit then
  begin
    mSymbol := AElement.Symbol;
    Result.Container := mSymbol.Container;
    Result.Range := mSymbol.SelectionRange;
  end;
  Result.Values := AElement.Values;
  Result.Inferred := AElement.Inferred;
  Result.InferredDetail := AElement.InferredDetail;
end;

/// <summary>Spalten: Name, bei Mitgliedern der Typ, Unit und Zeile, dann die Felder der Abfrage und weitere
/// gewünschte (AFields).</summary>
function QueryColumns(AAst: TQueryAst; const AFields: TArray<string>): TArray<string>;
var
  mName: string;
  mField: TQueryFieldInfo;
begin
  Result := ['name'];
  if AAst.Entity in TQueryCatalog.cMemberEntities then
  begin
    Result := Result + ['class'];
  end;
  if AAst.Entity <> TQueryEntity.Units then
  begin
    Result := Result + ['unit', 'line'];
  end;
  for mName in AAst.UsedFields + AFields do
  begin
    if (IndexText(mName, Result) < 0) and TQueryCatalog.TryField(mName, mField) and
      (AAst.Entity in mField.Entities) then
    begin
      Result := Result + [mField.Name];
    end;
  end;
end;

/// <summary>Zeilen der Elemente, für die die Bedingung von AAst gilt, mit den Werten der Spalten von AResult.
/// </summary>
procedure CollectRows(AFacts: TQueryFacts; AAst: TQueryAst; const ARoot: string; var AResult: TQueryResult;
  ARows: TList<TQueryRow>);
var
  mElements: TObjectList<TQueryElement>;
  mElement: TQueryElement;
  mIndex, mCount: Integer;
  mRow: TQueryRow;
begin
  mElements := AFacts.Elements(AAst.Entity);
  try
    mCount := 0;
    for mElement in mElements do
    begin
      Inc(mCount);
      if mCount mod cCancelStride = 0 then
      begin
        AFacts.CheckCancelled;
      end;
      if not AFacts.Holds(mElement, AAst.Condition) then
      begin
        Continue;
      end;
      SetLength(mElement.Values, Length(AResult.Columns));
      for mIndex := 0 to High(AResult.Columns) do
      begin
        mElement.Values[mIndex] := AFacts.Value(mElement, AResult.Columns[mIndex]);
      end;
      mRow := RowOf(mElement, ARoot);
      ARows.Add(mRow);
      Inc(AResult.InferredCount, Ord(mRow.Inferred));
    end;
  finally
    mElements.Free;
  end;
end;

/// <summary>Höchstzahl der Zeilen aus limit der Abfrage und der Anfrage (0 bzw. -1 = keine Grenze).</summary>
function RowLimit(AAst: TQueryAst; const ARequest: TQueryRequest; ACount: Integer): Integer;
begin
  Result := ACount;
  if (AAst.Limit >= 0) and (AAst.Limit < Result) then
  begin
    Result := AAst.Limit;
  end;
  if (ARequest.Limit > 0) and (ARequest.Limit < Result) then
  begin
    Result := ARequest.Limit;
  end;
end;

/// <summary>Sortiert ARows nach order by und legt die ersten bis zur Grenze in AResult ab.</summary>
procedure TakeRows(AAst: TQueryAst; const ARequest: TQueryRequest; ARows: TList<TQueryRow>;
  var AResult: TQueryResult);
var
  mOrderColumn, mIndex: Integer;
begin
  mOrderColumn := -1;
  if AAst.HasOrder then
  begin
    mOrderColumn := AResult.ColumnOf(AAst.OrderField.Name);
  end;
  ARows.Sort(RowComparer(mOrderColumn, AAst.Descending));
  AResult.Total := ARows.Count;
  SetLength(AResult.Rows, RowLimit(AAst, ARequest, ARows.Count));
  for mIndex := 0 to High(AResult.Rows) do
  begin
    AResult.Rows[mIndex] := ARows[mIndex];
  end;
end;

class function TCodeQueryEngine.Run(const ASource: TQuerySource; const ARequest: TQueryRequest;
  ACollector: TMetricsCollector): TQueryResult;
var
  mAst: TQueryAst;
  mError, mSuggestion: string;
  mColumn: Integer;
  mFacts: TQueryFacts;
  mRows: TList<TQueryRow>;
  mOwnCollector: TMetricsCollector;
  mWatch: TStopwatch;
begin
  mWatch := TStopwatch.StartNew;
  Result := Default(TQueryResult);
  Result.Query := ARequest.Query;
  if not TQueryParser.TryParse(ARequest.Query, mAst, mError, mColumn, mSuggestion) then
  begin
    Result.Error := mError;
    Result.ErrorColumn := mColumn;
    Result.Suggestion := mSuggestion;
    Exit;
  end;
  mOwnCollector := nil;
  if ACollector = nil then
  begin
    mOwnCollector := TMetricsCollector.Create;
    ACollector := mOwnCollector;
  end;
  mFacts := nil;
  mRows := TList<TQueryRow>.Create;
  try
    Result.Entity := TQueryCatalog.EntityName(mAst.Entity);
    Result.Columns := QueryColumns(mAst, ARequest.Fields);
    OrderByCost(mAst.Condition);
    mFacts := TQueryFacts.Create(ASource, ACollector);
    try
      CollectRows(mFacts, mAst, ASource.Root, Result, mRows);
    except
      on E: EQueryCancelled do
      begin
        Result.Error := E.Message;
        Exit;
      end;
    end;
    TakeRows(mAst, ARequest, mRows, Result);
  finally
    mRows.Free;
    mFacts.Free;
    mOwnCollector.Free;
    mAst.Free;
    Result.ElapsedMs := mWatch.ElapsedMilliseconds;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Query.Engine', cTexts);

end.
