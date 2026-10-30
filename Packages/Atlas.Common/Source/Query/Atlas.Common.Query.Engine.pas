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
  Atlas.Common.Query.Language;

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
    if AName[mIndex] = '<' then
      Inc(mDepth)
    else if AName[mIndex] = '>' then
    begin
      if mDepth > 0 then
        Dec(mDepth);
    end
    else if mDepth = 0 then
      Result := Result + AName[mIndex];
end;

function RelativePath(const ARoot, AFileName: string): string;
var
  mRoot, mPath: string;
begin
  mPath := StringReplace(AFileName, '\', '/', [rfReplaceAll]);
  mRoot := StringReplace(ARoot, '\', '/', [rfReplaceAll]);
  if (mRoot <> '') and (mRoot[Length(mRoot)] <> '/') then
    mRoot := mRoot + '/';
  if (mRoot <> '') and (mRoot <> '/') and SameText(Copy(mPath, 1, Length(mRoot)), mRoot) then
    Result := Copy(mPath, Length(mRoot) + 1, MaxInt)
  else
    Result := mPath;
end;

{ TCodeQueryEngine }

class function TCodeQueryEngine.ShortName(const AName: string): string;
var
  mDot: Integer;
begin
  Result := Trim(WithoutTypeArgs(AName));
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
    Result := Copy(Result, mDot + 1, MaxInt);
  if StartsStr('&', Result) then
    Delete(Result, 1, 1);
end;

class function TCodeQueryEngine.UsesUnit(const AUses: TArray<string>; const AUnit: string;
  const ANamespaces: TArray<string>): Boolean;
var
  mName, mNamespace: string;
begin
  for mName in AUses do
  begin
    if SameText(mName, AUnit) then
      Exit(True);
    for mNamespace in ANamespaces do
      if SameText(mNamespace + '.' + mName, AUnit) or SameText(mName, mNamespace + '.' + AUnit) then
        Exit(True);
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
    Result := Default(TIndexSymbol)
  else
    Result := Owner.Data.Symbols[SymbolIndex];
end;

function TQueryElement.IsUnit: Boolean;
begin
  Result := SymbolIndex < 0;
end;

function TQueryElement.Name: string;
begin
  if SymbolIndex < 0 then
    Result := Owner.Data.UnitName
  else
    Result := Owner.Data.Symbols[SymbolIndex].Name;
end;

function TQueryElement.Location: TSymbolLocation;
begin
  Result.UnitName := Owner.Data.UnitName;
  Result.FileName := Owner.Data.FileName;
  Result.Symbol := Symbol;
  if SymbolIndex >= 0 then
    Result.FileName := Owner.Data.SymbolFile(Result.Symbol);
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
    Exit;
  mInScope := TDictionary<string, Boolean>.Create;
  try
    for mFileName in FSource.Files do
      mInScope.AddOrSetValue(LowerCase(mFileName), True);
    for mData in FSource.Index.Units do
    begin
      // Packages kennen nur requires und contains; Bibliotheks-Units gehören nicht zum Projekt.
      if mData.Library_ or SameText(ExtractFileExt(mData.FileName), '.dpk') then
        Continue;
      if (mInScope.Count > 0) and not mInScope.ContainsKey(LowerCase(mData.FileName)) then
        Continue;
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
    raise EQueryCancelled.Create('Abfrage abgebrochen');
end;

function RangeHas(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := ((ARange.StartPos.Line < APosition.Line) or ((ARange.StartPos.Line = APosition.Line) and
    (ARange.StartPos.Character <= APosition.Character))) and ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

procedure TQueryFacts.LoadCounts(AUnit: TQueryUnit);
var
  mIndex, mType: Integer;
  mSymbol: TIndexSymbol;
  mKey: string;
  mCounts: TTypeCounts;
  mClasses: TDictionary<string, Boolean>;
begin
  if AUnit.HasCounts then
    Exit;
  AUnit.HasCounts := True;
  mClasses := TDictionary<string, Boolean>.Create;
  try
    for mIndex := 0 to High(AUnit.Data.Symbols) do
    begin
      mSymbol := AUnit.Data.Symbols[mIndex];
      if not (mSymbol.Kind in cTypeKinds) then
        Continue;
      // Vorwärtsdeklaration und Deklaration: die spätere zählt.
      AUnit.Types.AddOrSetValue(UpperCase(mSymbol.QualifiedName), mIndex);
      if mSymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType] then
        mClasses.AddOrSetValue(UpperCase(mSymbol.QualifiedName), True);
    end;
    AUnit.ClassCount := mClasses.Count;
  finally
    mClasses.Free;
  end;
  SetLength(AUnit.Declared, Length(AUnit.Data.Symbols));
  for mIndex := 0 to High(AUnit.Data.Symbols) do
  begin
    mSymbol := AUnit.Data.Symbols[mIndex];
    if mSymbol.Kind in cTypeKinds then
      Continue;
    if mSymbol.Container = '' then
    begin
      AUnit.Declared[mIndex] := True;
      Continue;
    end;
    // Der Index führt auch die Rümpfe im implementation-Teil (procedure TFoo.Bar) als Methode von TFoo; Mitglied
    // ist nur, was im Rumpf des Typs steht.
    AUnit.Declared[mIndex] := (mSymbol.FileName <> '') or
      (AUnit.Types.TryGetValue(UpperCase(mSymbol.Container), mType) and
      RangeHas(AUnit.Data.Symbols[mType].Range, mSymbol.Range.StartPos));
    if not AUnit.Declared[mIndex] then
      Continue;
    if not (mSymbol.Kind in cMethodKinds + [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) then
      Continue;
    mKey := UpperCase(mSymbol.Container);
    if not AUnit.Counts.TryGetValue(mKey, mCounts) then
      mCounts := Default(TTypeCounts);
    if mSymbol.Kind in cMethodKinds then
    begin
      Inc(mCounts.Methods);
      Inc(AUnit.RoutineCount);
      if mSymbol.HasDirective('override') then
        Inc(mCounts.Overrides);
    end
    else if mSymbol.Kind = TIndexSymbolKind.Field then
      Inc(mCounts.Fields)
    else
      Inc(mCounts.Properties);
    AUnit.Counts.AddOrSetValue(mKey, mCounts);
  end;
end;

procedure TQueryFacts.LoadMetrics(AUnit: TQueryUnit);
var
  mText, mKey: string;
  mByName: TObjectDictionary<string, TList<Integer>>;
  mList: TList<Integer>;
  mIndex, mCandidate, mChosen: Integer;
  mUsed: TDictionary<Integer, Boolean>;
  mSymbol: TIndexSymbol;
begin
  if AUnit.HasMetrics then
    Exit;
  AUnit.HasMetrics := True;
  if not (Assigned(FSource.ReadText) and FSource.ReadText(AUnit.Data.FileName, mText)) then
    Exit;
  AUnit.Metrics := FCollector.FileRoutines(AUnit.Data.FileName, mText);
  mByName := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  mUsed := TDictionary<Integer, Boolean>.Create;
  try
    for mIndex := 0 to High(AUnit.Metrics) do
    begin
      mKey := UpperCase(WithoutTypeArgs(AUnit.Metrics[mIndex].Name));
      if not mByName.TryGetValue(mKey, mList) then
      begin
        mList := TList<Integer>.Create;
        mByName.Add(mKey, mList);
      end;
      mList.Add(mIndex);
    end;
    // Alle Routinen der Unit auf einmal zuordnen, damit Überladungen unabhängig von der Reihenfolge der Abfrage
    // dieselbe Implementierung bekommen: zuerst die mit gleicher Parameterzahl, sonst die erste freie.
    for mIndex := 0 to High(AUnit.Data.Symbols) do
    begin
      mSymbol := AUnit.Data.Symbols[mIndex];
      if not (mSymbol.Kind in cRoutineKinds) or (mSymbol.FileName <> '') then
        Continue;
      if not mByName.TryGetValue(UpperCase(WithoutTypeArgs(mSymbol.QualifiedName)), mList) then
        Continue;
      mChosen := -1;
      for mCandidate in mList do
        if not mUsed.ContainsKey(mCandidate) and
          (AUnit.Metrics[mCandidate].Values[TMetricKind.ParameterCount] = mSymbol.MaxArgs) then
        begin
          mChosen := mCandidate;
          Break;
        end;
      if mChosen < 0 then
        for mCandidate in mList do
          if not mUsed.ContainsKey(mCandidate) then
          begin
            mChosen := mCandidate;
            Break;
          end;
      if mChosen < 0 then
        Continue;
      mUsed.Add(mChosen, True);
      AUnit.MetricOf.AddOrSetValue(mIndex, mChosen);
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
    Exit;
  AUnit.HasLength := True;
  AUnit.UnitLength := -1;
  if not (Assigned(FSource.ReadText) and FSource.ReadText(AUnit.Data.FileName, mText)) then
    Exit;
  for mItem in TMetricsCalculator.StructureForText(mText) do
    if mItem.Kind = TStructureKind.UnitLength then
      AUnit.UnitLength := mItem.Value;
end;

procedure TQueryFacts.LoadTokens(AUnit: TQueryUnit);
var
  mText: string;
  mToken: TPascalToken;
  mCount: Integer;
begin
  if AUnit.HasTokens then
    Exit;
  AUnit.HasTokens := True;
  if not (Assigned(FSource.ReadText) and FSource.ReadText(AUnit.Data.FileName, mText)) then
    Exit;
  AUnit.Tokens := TPascalLexer.Tokenize(mText);
  mCount := 0;
  for mToken in AUnit.Tokens do
    if not (mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      AUnit.Tokens[mCount] := mToken;
      Inc(mCount);
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
      Inc(Result);
    Inc(Result, CountComponents(mChild));
  end;
end;

procedure TQueryFacts.LoadForm(AUnit: TQueryUnit);
var
  mText, mFormText, mDecoded, mFile: string;
  mDocument: TDfmDocument;
begin
  if AUnit.HasForm then
    Exit;
  AUnit.HasForm := True;
  if not Assigned(FSource.ReadText) or not FSource.ReadText(AUnit.Data.FileName, mText) then
    Exit;
  for mFile in TFormFiles.FormFiles(AUnit.Data.FileName, mText) do
  begin
    if not FSource.ReadText(mFile, mFormText) then
      Continue;
    // Binäre Formulardateien erst in Text umwandeln.
    if TDfmBinary.FromDecodedText(mFormText, mDecoded) then
      mFormText := mDecoded;
    mDocument := TDfmParser.Parse(mFormText);
    try
      if mDocument.Root = nil then
        Continue;
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
    AUnit.Ancestry := TAncestry.Create(FSource.Index, AUnit.Data);
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
      mUnits := mUnits + [mUnit.Data];
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
    Result := Default(TTypeCounts);
end;

function TQueryFacts.MetricValue(AElement: TQueryElement; AKind: TMetricKind): TQueryValue;
var
  mPosition: Integer;
begin
  LoadMetrics(AElement.Owner);
  if AElement.Owner.MetricOf.TryGetValue(AElement.SymbolIndex, mPosition) then
    Result := TQueryValue.OfNumber(AElement.Owner.Metrics[mPosition].Values[AKind])
  else
    // Ohne Rumpf (abstract, external, Interface-Methode) gibt es keine Kennzahl.
    Result := TQueryValue.Empty;
end;

function TQueryFacts.CallsOf(AElement: TQueryElement; AIncoming: Boolean): TArray<TQueryCall>;
var
  mCall: TQueryCall;
begin
  if not Assigned(FSource.Calls) or AElement.IsUnit then
    Exit(nil);
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
    Result := AElement.Callers
  else
    Result := AElement.Callees;
  for mCall in Result do
    if mCall.Inferred and not AElement.Inferred then
    begin
      AElement.Inferred := True;
      AElement.InferredDetail := Format('erschlossen: %s (%s)', [mCall.Name, mCall.Reason]);
    end;
end;

function TQueryFacts.TypeOf(AElement: TQueryElement; out ALocation: TSymbolLocation): Boolean;
var
  mSymbol: TIndexSymbol;
  mPosition: Integer;
begin
  ALocation := Default(TSymbolLocation);
  if AElement.IsUnit then
    Exit(False);
  mSymbol := AElement.Symbol;
  if mSymbol.Kind in cTypeKinds then
  begin
    ALocation := AElement.Location;
    Exit(True);
  end;
  if mSymbol.Container = '' then
    Exit(False);
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
    Result := Result + Ancestry(AUnit).Ancestors(ALocation, mComplete, mObjectMissing);
end;

function TQueryFacts.InterfaceClosure(const AName: string): TArray<string>;
var
  mKey, mName, mAncestor: string;
  mQueue: TQueue<string>;
  mSeen: TDictionary<string, Boolean>;
  mLocation: TSymbolLocation;
begin
  mKey := UpperCase(TCodeQueryEngine.ShortName(AName));
  if FInterfaceNames.TryGetValue(mKey, Result) then
    Exit;
  Result := nil;
  mQueue := TQueue<string>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mQueue.Enqueue(TCodeQueryEngine.ShortName(AName));
    while mQueue.Count > 0 do
    begin
      mName := mQueue.Dequeue;
      if (mName = '') or mSeen.ContainsKey(UpperCase(mName)) then
        Continue;
      mSeen.Add(UpperCase(mName), True);
      Result := Result + [mName];
      for mLocation in FSource.Index.FindSymbols(mName) do
        if mLocation.Symbol.Kind = TIndexSymbolKind.InterfaceType then
          for mAncestor in mLocation.Symbol.Ancestors do
            mQueue.Enqueue(TCodeQueryEngine.ShortName(mAncestor));
    end;
  finally
    mSeen.Free;
    mQueue.Free;
  end;
  FInterfaceNames.Add(mKey, Result);
end;

function TQueryFacts.Inherits(AElement: TQueryElement; const AName: string): Boolean;
var
  mType: TSymbolLocation;
  mChain: TArray<TSymbolLocation>;
  mTarget, mAncestor, mName: string;
  mIndex: Integer;
begin
  if not TypeOf(AElement, mType) then
    Exit(False);
  mTarget := TCodeQueryEngine.ShortName(AName);
  if mType.Symbol.Kind = TIndexSymbolKind.InterfaceType then
  begin
    for mAncestor in mType.Symbol.Ancestors do
      for mName in InterfaceClosure(mAncestor) do
        if SameText(mName, mTarget) then
          Exit(True);
    Exit(False);
  end;
  mChain := Chain(AElement.Owner, mType);
  for mIndex := 0 to High(mChain) do
  begin
    // Der erste Eintrag ist der Typ selbst; er erbt nicht von sich.
    if (mIndex > 0) and SameText(TCodeQueryEngine.ShortName(mChain[mIndex].Symbol.Name), mTarget) then
      Exit(True);
    // Der Vorfahr, wie er geschrieben ist: zählt auch, wenn er selbst nicht im Index steht (VCL nicht indiziert).
    if (Length(mChain[mIndex].Symbol.Ancestors) > 0) and
      SameText(TCodeQueryEngine.ShortName(mChain[mIndex].Symbol.Ancestors[0]), mTarget) then
      Exit(True);
  end;
  Result := False;
end;

function TQueryFacts.Implements(AElement: TQueryElement; const AName: string): Boolean;
var
  mType, mLink: TSymbolLocation;
  mTarget, mName: string;
  mIndex, mFirst: Integer;
begin
  if not TypeOf(AElement, mType) then
    Exit(False);
  mTarget := TCodeQueryEngine.ShortName(AName);
  // Ein Interface „setzt um“, wovon es abgeleitet ist.
  if mType.Symbol.Kind = TIndexSymbolKind.InterfaceType then
    Exit(Inherits(AElement, AName));
  for mLink in Chain(AElement.Owner, mType) do
  begin
    // Bei Klassen ist der erste Eintrag der Vorfahr, die übrigen sind Interfaces.
    mFirst := 0;
    if mLink.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType] then
      mFirst := 1;
    for mIndex := mFirst to High(mLink.Symbol.Ancestors) do
      for mName in InterfaceClosure(mLink.Symbol.Ancestors[mIndex]) do
        if SameText(mName, mTarget) then
          Exit(True);
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
    if SameText(WithoutTypeArgs(mCall.Name), mTarget) or
      ((Pos('.', mTarget) = 0) and SameText(TCodeQueryEngine.ShortName(mCall.Name), mTarget)) then
      Exit(True);
  Result := False;
end;

function TQueryFacts.HasAttribute(AElement: TQueryElement; const AName: string): Boolean;
var
  mTarget, mName: string;
  mSymbol: TIndexSymbol;
begin
  if AElement.IsUnit then
    Exit(False);
  mSymbol := AElement.Symbol;
  // Deklarationen aus $I-Dateien: Attribute stehen in einer anderen Datei.
  if mSymbol.FileName <> '' then
    Exit(False);
  LoadTokens(AElement.Owner);
  mTarget := TCodeQueryEngine.ShortName(AName);
  if EndsText('Attribute', mTarget) and (Length(mTarget) > Length('Attribute')) then
    mTarget := Copy(mTarget, 1, Length(mTarget) - Length('Attribute'));
  for mName in TConsideredUsed.AttributesAt(AElement.Owner.Tokens, mSymbol.Range.StartPos) do
    if SameText(mName, mTarget) then
      Exit(True);
  Result := False;
end;

function TQueryFacts.Elements(AEntity: TQueryEntity): TObjectList<TQueryElement>;
var
  mUnit: TQueryUnit;
  mIndex, mSlot: Integer;
  mSymbol: TIndexSymbol;
  mElement: TQueryElement;
  mSeen: TDictionary<string, Integer>;
  mKey: string;
  mTake: Boolean;
begin
  Result := TObjectList<TQueryElement>.Create(True);
  try
    mSeen := TDictionary<string, Integer>.Create;
    try
      for mUnit in FUnits do
      begin
        CheckCancelled;
        if AEntity = TQueryEntity.Units then
        begin
          mElement := TQueryElement.Create;
          mElement.Owner := mUnit;
          mElement.SymbolIndex := -1;
          Result.Add(mElement);
          Continue;
        end;
        if AEntity = TQueryEntity.Forms then
          LoadForm(mUnit);
        mSeen.Clear;
        for mIndex := 0 to High(mUnit.Data.Symbols) do
        begin
          mSymbol := mUnit.Data.Symbols[mIndex];
          case AEntity of
            TQueryEntity.Classes:
              mTake := mSymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType];
            TQueryEntity.Records:
              mTake := mSymbol.Kind = TIndexSymbolKind.RecordType;
            TQueryEntity.Interfaces:
              mTake := mSymbol.Kind = TIndexSymbolKind.InterfaceType;
            TQueryEntity.Forms:
              mTake := (mSymbol.Kind = TIndexSymbolKind.ClassType) and (mUnit.FormClass <> '') and
                SameText(mSymbol.QualifiedName, mUnit.FormClass);
            TQueryEntity.Methods:
              mTake := (mSymbol.Kind in cMethodKinds) and (mSymbol.Container <> '');
            TQueryEntity.Routines:
              mTake := (mSymbol.Kind = TIndexSymbolKind.Routine) and (mSymbol.Container = '');
            TQueryEntity.Fields:
              mTake := (mSymbol.Kind = TIndexSymbolKind.Field) and (mSymbol.Container <> '');
            TQueryEntity.Properties:
              mTake := (mSymbol.Kind = TIndexSymbolKind.Property_) and (mSymbol.Container <> '');
          else
            mTake := False;
          end;
          if not mTake then
            Continue;
          if AEntity in TQueryCatalog.MemberEntities then
          begin
            LoadCounts(mUnit);
            if not mUnit.Declared[mIndex] then
              Continue;
          end;
          // Typen: Vorwärtsdeklaration und Deklaration einmal (die spätere gilt). Routinen: Deklaration im
          // interface und Rumpf im implementation einmal (die erste gilt).
          if AEntity in TQueryCatalog.TypeEntities then
            mKey := UpperCase(mSymbol.QualifiedName)
          else if AEntity = TQueryEntity.Routines then
            mKey := UpperCase(mSymbol.Name) + '(' + UpperCase(string.Join(',', mSymbol.ParamTypes)) + ')'
          else
            mKey := '';
          if (mKey <> '') and mSeen.TryGetValue(mKey, mSlot) then
          begin
            if AEntity in TQueryCatalog.TypeEntities then
              Result[mSlot].SymbolIndex := mIndex;
            Continue;
          end;
          mElement := TQueryElement.Create;
          mElement.Owner := mUnit;
          mElement.SymbolIndex := mIndex;
          Result.Add(mElement);
          if mKey <> '' then
            mSeen.Add(mKey, Result.Count - 1);
        end;
      end;
    finally
      mSeen.Free;
    end;
  except
    // Abbruch (EQueryCancelled) mitten im Sammeln: die Liste gehört noch niemandem.
    Result.Free;
    raise;
  end;
end;

function TQueryFacts.Value(AElement: TQueryElement; const AField: string): TQueryValue;
var
  mSymbol: TIndexSymbol;
  mNode: Integer;
  mText: string;
begin
  mSymbol := AElement.Symbol;
  case IndexText(AField, ['name', 'unit', 'path', 'line', 'class', 'visibility', 'type', 'classes', 'methods',
    'fields', 'properties', 'lines', 'complexity', 'cognitive', 'nesting', 'params', 'locals', 'exits', 'callers',
    'callees', 'overrides', 'virtual', 'uses', 'usedBy', 'ancestor', 'components']) of
    0:
      Result := TQueryValue.OfText(AElement.Name);
    1:
      Result := TQueryValue.OfText(AElement.Owner.Data.UnitName);
    2:
      Result := TQueryValue.OfText(RelativePath(FSource.Root, AElement.Location.FileName));
    3:
      if AElement.IsUnit then
        Result := TQueryValue.OfNumber(1)
      else
        Result := TQueryValue.OfNumber(mSymbol.SelectionRange.StartPos.Line + 1);
    4:
      Result := TQueryValue.OfText(mSymbol.Container);
    5:
      Result := TQueryValue.OfText(VisibilityName(mSymbol.Visibility));
    6:
      begin
        mText := mSymbol.TypeName;
        if mSymbol.TypeArgs <> '' then
          mText := mText + '<' + mSymbol.TypeArgs + '>';
        Result := TQueryValue.OfText(mText);
      end;
    7:
      begin
        LoadCounts(AElement.Owner);
        Result := TQueryValue.OfNumber(AElement.Owner.ClassCount);
      end;
    8:
      if AElement.IsUnit then
      begin
        LoadCounts(AElement.Owner);
        Result := TQueryValue.OfNumber(AElement.Owner.RoutineCount);
      end
      else
        Result := TQueryValue.OfNumber(CountsOf(AElement).Methods);
    9:
      Result := TQueryValue.OfNumber(CountsOf(AElement).Fields);
    10:
      Result := TQueryValue.OfNumber(CountsOf(AElement).Properties);
    11:
      if AElement.IsUnit then
      begin
        LoadLength(AElement.Owner);
        if AElement.Owner.UnitLength < 0 then
          Result := TQueryValue.Empty
        else
          Result := TQueryValue.OfNumber(AElement.Owner.UnitLength);
      end
      else if mSymbol.Kind in cRoutineKinds then
        Result := MetricValue(AElement, TMetricKind.MethodLength)
      else
        Result := TQueryValue.OfNumber(mSymbol.Range.EndPos.Line - mSymbol.Range.StartPos.Line + 1);
    12:
      Result := MetricValue(AElement, TMetricKind.Cyclomatic);
    13:
      Result := MetricValue(AElement, TMetricKind.Cognitive);
    14:
      Result := MetricValue(AElement, TMetricKind.NestingDepth);
    15:
      Result := TQueryValue.OfNumber(mSymbol.MaxArgs);
    16:
      Result := MetricValue(AElement, TMetricKind.LocalCount);
    17:
      Result := MetricValue(AElement, TMetricKind.ExitPoints);
    18:
      if Assigned(FSource.Calls) then
        Result := TQueryValue.OfNumber(Length(CallsOf(AElement, True)))
      else
        Result := TQueryValue.Empty;
    19:
      if Assigned(FSource.Calls) then
        Result := TQueryValue.OfNumber(Length(CallsOf(AElement, False)))
      else
        Result := TQueryValue.Empty;
    20:
      if mSymbol.Kind in cMethodKinds then
      begin
        if mSymbol.HasDirective('override') then
          Result := TQueryValue.OfNumber(1)
        else
          Result := TQueryValue.OfNumber(0);
      end
      else
        Result := TQueryValue.OfNumber(CountsOf(AElement).Overrides);
    21:
      Result := TQueryValue.OfFlag(mSymbol.IsVirtual);
    22:
      Result := TQueryValue.OfNumber(Length(AElement.Owner.Data.InterfaceUses) +
        Length(AElement.Owner.Data.ImplementationUses));
    23:
      begin
        mNode := Graph.IndexOfFile(AElement.Owner.Data.FileName);
        if mNode < 0 then
          Result := TQueryValue.OfNumber(0)
        else
          Result := TQueryValue.OfNumber(Length(Graph.DirectDependents(mNode, [TUsesSection.Interface_,
            TUsesSection.Implementation_])));
      end;
    24:
      if Length(mSymbol.Ancestors) > 0 then
        Result := TQueryValue.OfText(mSymbol.Ancestors[0])
      else if mSymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType] then
        Result := TQueryValue.OfText('TObject')
      else
        Result := TQueryValue.OfText('');
    25:
      begin
        LoadForm(AElement.Owner);
        Result := TQueryValue.OfNumber(AElement.Owner.FormComponents);
      end;
  else
    Result := TQueryValue.Empty;
  end;
end;

function ValueHolds(const AValue: TQueryValue; AOperator: TQueryOperator; const AExpected: TQueryValue): Boolean;
var
  mOrder: Integer;
begin
  if AValue.Kind = TQueryValueKind.None then
    Exit(False);
  if AOperator in [TQueryOperator.Like, TQueryOperator.NotLike] then
  begin
    Result := TConsideredUsed.Matches(AExpected.Text, AValue.Text);
    if AOperator = TQueryOperator.NotLike then
      Result := not Result;
    Exit;
  end;
  if AValue.Kind = TQueryValueKind.Text then
    mOrder := CompareText(AValue.Text, AExpected.Text)
  else if AValue.Number < AExpected.Number then
    mOrder := -1
  else if AValue.Number > AExpected.Number then
    mOrder := 1
  else
    mOrder := 0;
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

function TQueryFacts.Holds(AElement: TQueryElement; ANode: TQueryNode): Boolean;
var
  mItem: TQueryNode;
  mPredicate: TQueryPredicateNode;
  mCompare: TQueryCompareNode;
begin
  if ANode = nil then
    Exit(True);
  if ANode is TQueryLogicNode then
  begin
    if TQueryLogicNode(ANode).Logic = TQueryLogic.And_ then
    begin
      for mItem in TQueryLogicNode(ANode).Items do
        if not Holds(AElement, mItem) then
          Exit(False);
      Exit(True);
    end;
    for mItem in TQueryLogicNode(ANode).Items do
      if Holds(AElement, mItem) then
        Exit(True);
    Exit(False);
  end;
  if ANode is TQueryNotNode then
    Exit(not Holds(AElement, TQueryNotNode(ANode).Inner));
  if ANode is TQueryPredicateNode then
  begin
    mPredicate := TQueryPredicateNode(ANode);
    case mPredicate.Kind of
      TQueryPredicateKind.Inherits:
        Result := Inherits(AElement, mPredicate.Argument);
      TQueryPredicateKind.Implements:
        Result := Implements(AElement, mPredicate.Argument);
      TQueryPredicateKind.Uses_:
        Result := UsesTarget(AElement, mPredicate.Argument);
      TQueryPredicateKind.Calls:
        Result := CallsTarget(AElement, mPredicate.Argument);
    else
      Result := HasAttribute(AElement, mPredicate.Argument);
    end;
    Exit;
  end;
  mCompare := ANode as TQueryCompareNode;
  Result := ValueHolds(Value(AElement, mCompare.Field.Name), mCompare.Comparison, mCompare.Value);
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
      Result := Max(Result, NodeCost(mItem));
  end
  else if ANode is TQueryNotNode then
    Result := NodeCost(TQueryNotNode(ANode).Inner)
  else if ANode is TQueryCompareNode then
    Result := FieldCost(TQueryCompareNode(ANode).Field.Name)
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
    OrderByCost(TQueryNotNode(ANode).Inner);
  if not (ANode is TQueryLogicNode) then
    Exit;
  mList := TQueryLogicNode(ANode).Items;
  for mNode in mList do
    OrderByCost(mNode);
  if TQueryLogicNode(ANode).Logic <> TQueryLogic.And_ then
    Exit;
  mItems := mList.ToArray;
  SetLength(mCosts, Length(mItems));
  for mIndex := 0 to High(mItems) do
    mCosts[mIndex] := NodeCost(mItems[mIndex]);
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
      mList.Add(mNode);
  finally
    mList.OwnsObjects := True;
  end;
end;

function CompareValues(const A, B: TQueryValue): Integer;
begin
  // Ohne Wert ans Ende, unabhängig von der Richtung.
  if (A.Kind = TQueryValueKind.None) or (B.Kind = TQueryValueKind.None) then
    Exit(Ord(A.Kind = TQueryValueKind.None) - Ord(B.Kind = TQueryValueKind.None));
  if (A.Kind = TQueryValueKind.Text) or (B.Kind = TQueryValueKind.Text) then
    Exit(CompareText(A.Text, B.Text));
  if A.Number < B.Number then
    Result := -1
  else if A.Number > B.Number then
    Result := 1
  else
    Result := 0;
end;

function CompareRows(const A, B: TQueryRow): Integer;
begin
  Result := CompareText(A.UnitName, B.UnitName);
  if Result = 0 then
    Result := A.Range.StartPos.Line - B.Range.StartPos.Line;
  if Result = 0 then
    Result := A.Range.StartPos.Character - B.Range.StartPos.Character;
  if Result = 0 then
    Result := CompareText(A.QualifiedName, B.QualifiedName);
  if Result = 0 then
    Result := CompareText(A.Path, B.Path);
  if Result = 0 then
    Result := CompareStr(A.Path, B.Path);
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
          Result := -Result;
      end;
      if Result = 0 then
        Result := CompareRows(A, B);
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

class function TCodeQueryEngine.Run(const ASource: TQuerySource; const ARequest: TQueryRequest;
  ACollector: TMetricsCollector): TQueryResult;
var
  mAst: TQueryAst;
  mError, mSuggestion, mName: string;
  mColumn, mIndex, mLimit, mOrderColumn, mCount: Integer;
  mFacts: TQueryFacts;
  mElements: TObjectList<TQueryElement>;
  mElement: TQueryElement;
  mRows: TList<TQueryRow>;
  mRow: TQueryRow;
  mOwnCollector: TMetricsCollector;
  mField: TQueryFieldInfo;
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
  mElements := nil;
  mRows := TList<TQueryRow>.Create;
  try
    Result.Entity := TQueryCatalog.EntityName(mAst.Entity);
    // Spalten: Name, bei Mitgliedern der Typ, Unit und Zeile, dann die Felder der Abfrage und weitere gewünschte.
    Result.Columns := ['name'];
    if mAst.Entity in TQueryCatalog.MemberEntities then
      Result.Columns := Result.Columns + ['class'];
    if mAst.Entity <> TQueryEntity.Units then
      Result.Columns := Result.Columns + ['unit', 'line'];
    for mName in mAst.UsedFields + ARequest.Fields do
      if (Result.ColumnOf(mName) < 0) and TQueryCatalog.TryField(mName, mField) and
        (mAst.Entity in mField.Entities) then
        Result.Columns := Result.Columns + [mField.Name];
    OrderByCost(mAst.Condition);
    mFacts := TQueryFacts.Create(ASource, ACollector);
    try
      mElements := mFacts.Elements(mAst.Entity);
      mCount := 0;
      for mElement in mElements do
      begin
        Inc(mCount);
        if mCount mod cCancelStride = 0 then
          mFacts.CheckCancelled;
        if not mFacts.Holds(mElement, mAst.Condition) then
          Continue;
        SetLength(mElement.Values, Length(Result.Columns));
        for mIndex := 0 to High(Result.Columns) do
          mElement.Values[mIndex] := mFacts.Value(mElement, Result.Columns[mIndex]);
        mRow := RowOf(mElement, ASource.Root);
        mRows.Add(mRow);
        if mRow.Inferred then
          Inc(Result.InferredCount);
      end;
    except
      on E: EQueryCancelled do
      begin
        Result.Error := E.Message;
        Exit;
      end;
    end;
    mOrderColumn := -1;
    if mAst.HasOrder then
      mOrderColumn := Result.ColumnOf(mAst.OrderField.Name);
    mRows.Sort(RowComparer(mOrderColumn, mAst.Descending));
    Result.Total := mRows.Count;
    mLimit := mRows.Count;
    if (mAst.Limit >= 0) and (mAst.Limit < mLimit) then
      mLimit := mAst.Limit;
    if (ARequest.Limit > 0) and (ARequest.Limit < mLimit) then
      mLimit := ARequest.Limit;
    SetLength(Result.Rows, mLimit);
    for mIndex := 0 to mLimit - 1 do
      Result.Rows[mIndex] := mRows[mIndex];
  finally
    mRows.Free;
    mElements.Free;
    mFacts.Free;
    mOwnCollector.Free;
    mAst.Free;
    Result.ElapsedMs := mWatch.ElapsedMilliseconds;
  end;
end;

end.
