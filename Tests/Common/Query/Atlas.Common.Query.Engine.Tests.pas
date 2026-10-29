unit Atlas.Common.Query.Engine.Tests;

// Tests der Auswertung (#1351): jedes Prädikat, Felder aus Index, Metriken,
// Uses-Graph, Formulardatei und Aufrufhierarchie, erschlossene Treffer,
// Sortierung mit eindeutigem Gleichstand, limit und Abbruch. Dazu der
// Benchmark mit 1000 Units bei geladenem Index.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Query.Contract;

type
  [TestFixture]
  TQueryEngineTests = class
  public
    [Test]
    procedure InheritsTransitivelyAndAsWritten;
    [Test]
    procedure ImplementsThroughAncestorsAndDerivedInterfaces;
    [Test]
    procedure FormsCountComponents;
    [Test]
    procedure MethodMetricsMatchCalculator;
    [Test]
    procedure CallersCountInferredAndMarkRow;
    [Test]
    procedure CallsMatchesQualifiedAndShortName;
    [Test]
    procedure UsesAndUsedByWithNamespaces;
    [Test]
    procedure HasAttributeWithAndWithoutSuffix;
    [Test]
    procedure LikeNotAndVisibility;
    [Test]
    procedure TypeCountsAndRecords;
    [Test]
    procedure RoutinesCountOnce;
    [Test]
    procedure OrderByIsUniqueOnTies;
    [Test]
    procedure LimitKeepsTotal;
    [Test]
    procedure ColumnsFromQueryAndRequest;
    [Test]
    procedure ScopeExcludesLibraryAndOtherFiles;
    [Test]
    procedure CancelledReportsError;
    [Test]
    procedure SyntaxErrorInResult;
    [Test]
    [Category('Benchmark')]
    procedure ThousandUnitsUnderTwoSeconds;
  end;

/// <summary>Kleines Projekt aus drei Units samt Formular für Abfragetests; Pfade unter C:\P.</summary>
function QueryTestSource: TQuerySource;
/// <summary>Namen der Zeilen (Container.Name) mit Komma.</summary>
function RowNames(const AResult: TQueryResult): string;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Calculator,
  Atlas.Common.Query.Engine;

const
  cKunden =
    'unit Data.Kunden;' + sLineBreak +
    'interface' + sLineBreak +
    'uses System.SysUtils, Vcl.Forms;' + sLineBreak +
    'type' + sLineBreak +
    '  IKunde = interface' + sLineBreak +
    '    procedure Speichern;' + sLineBreak +
    '  end;' + sLineBreak +
    '  IKundeEx = interface(IKunde)' + sLineBreak +
    '  end;' + sLineBreak +
    '  TBasis = class;' + sLineBreak +
    '  TBasis = class(TInterfacedObject, IKundeEx)' + sLineBreak +
    '  public' + sLineBreak +
    '    procedure Speichern; virtual;' + sLineBreak +
    '  end;' + sLineBreak +
    '  TKunde = class(TBasis)' + sLineBreak +
    '  private' + sLineBreak +
    '    FName: string;' + sLineBreak +
    '    FAlter: Integer;' + sLineBreak +
    '  public' + sLineBreak +
    '    [Serializable]' + sLineBreak +
    '    procedure Speichern; override;' + sLineBreak +
    '    function Rechne(A, B: Integer): Integer; overload;' + sLineBreak +
    '    function Rechne(A: Integer): Integer; overload;' + sLineBreak +
    '    property Name: string read FName;' + sLineBreak +
    '  end;' + sLineBreak +
    '  TPunkt = record' + sLineBreak +
    '    X, Y: Integer;' + sLineBreak +
    '  end;' + sLineBreak +
    'procedure Hilfe;' + sLineBreak +
    'implementation' + sLineBreak +
    'procedure Hilfe;' + sLineBreak +
    'begin' + sLineBreak +
    'end;' + sLineBreak +
    'procedure TBasis.Speichern;' + sLineBreak +
    'begin' + sLineBreak +
    'end;' + sLineBreak +
    'procedure TKunde.Speichern;' + sLineBreak +
    'begin' + sLineBreak +
    '  inherited;' + sLineBreak +
    'end;' + sLineBreak +
    'function TKunde.Rechne(A: Integer): Integer;' + sLineBreak +
    'begin' + sLineBreak +
    '  Result := A;' + sLineBreak +
    'end;' + sLineBreak +
    'function TKunde.Rechne(A, B: Integer): Integer;' + sLineBreak +
    'begin' + sLineBreak +
    '  if A > 0 then' + sLineBreak +
    '    if B > 0 then' + sLineBreak +
    '      if A > B then' + sLineBreak +
    '        Result := 1' + sLineBreak +
    '      else' + sLineBreak +
    '        Result := 2' + sLineBreak +
    '    else' + sLineBreak +
    '      Result := 3' + sLineBreak +
    '  else' + sLineBreak +
    '    Result := 0;' + sLineBreak +
    'end;' + sLineBreak +
    'end.';

  cMain =
    'unit Main;' + sLineBreak +
    'interface' + sLineBreak +
    'uses Vcl.Forms, Data.Kunden;' + sLineBreak +
    'type' + sLineBreak +
    '  TMainForm = class(TForm)' + sLineBreak +
    '    procedure Eins;' + sLineBreak +
    '  end;' + sLineBreak +
    'implementation' + sLineBreak +
    '{$R *.dfm}' + sLineBreak +
    'procedure TMainForm.Eins;' + sLineBreak +
    'begin' + sLineBreak +
    'end;' + sLineBreak +
    'end.';

  cMainForm =
    'object MainForm: TMainForm' + sLineBreak +
    '  Caption = ''Haupt''' + sLineBreak +
    '  object Button1: TButton' + sLineBreak +
    '  end' + sLineBreak +
    '  object Panel1: TPanel' + sLineBreak +
    '    object Edit1: TEdit' + sLineBreak +
    '    end' + sLineBreak +
    '  end' + sLineBreak +
    'end';

  cStart =
    'program Start;' + sLineBreak +
    'uses Main;' + sLineBreak +
    'begin' + sLineBreak +
    'end.';

var
  gTexts: TDictionary<string, string>;

function Texts: TDictionary<string, string>;
begin
  if gTexts = nil then
  begin
    gTexts := TDictionary<string, string>.Create;
    gTexts.Add(UpperCase('C:\P\Data.Kunden.pas'), cKunden);
    gTexts.Add(UpperCase('C:\P\Main.pas'), cMain);
    gTexts.Add(UpperCase('C:\P\Main.dfm'), cMainForm);
    gTexts.Add(UpperCase('C:\P\Start.dpr'), cStart);
  end;
  Result := gTexts;
end;

function ReadTestText(const AFileName: string; out AText: string): Boolean;
begin
  Result := Texts.TryGetValue(UpperCase(AFileName), AText);
end;

function AddText(const AIndex: ISymbolIndex; const AFileName, AText: string): TUnitIndex;
begin
  Result := TIndexExtractor.ExtractText(AText, AFileName, nil);
  AIndex.AddUnit(Result);
end;

/// <summary>Aufrufe für die Tests: TKunde.Rechne(A, B) ruft niemand, TBasis.Speichern ruft TKunde.Speichern
/// (sicher) und Hilfe über ein Interface (erschlossen).</summary>
function TestCalls(const ALocation: TSymbolLocation; AIncoming: Boolean): TArray<TQueryCall>;
var
  mCall: TQueryCall;
begin
  Result := nil;
  mCall := Default(TQueryCall);
  mCall.UnitName := 'Data.Kunden';
  mCall.FileName := 'C:\P\Data.Kunden.pas';
  if AIncoming and SameText(ALocation.Symbol.QualifiedName, 'TBasis.Speichern') then
  begin
    mCall.Name := 'TKunde.Speichern';
    Result := Result + [mCall];
    mCall.Name := 'Hilfe';
    mCall.Inferred := True;
    mCall.Reason := 'interface';
    Result := Result + [mCall];
  end
  else if AIncoming and SameText(ALocation.Symbol.QualifiedName, 'TKunde.Speichern') then
  begin
    mCall.Name := 'TMainForm.Eins';
    Result := Result + [mCall];
  end
  else if not AIncoming and SameText(ALocation.Symbol.QualifiedName, 'TKunde.Speichern') then
  begin
    mCall.Name := 'TBasis.Speichern';
    Result := Result + [mCall];
  end;
end;

function QueryTestSource: TQuerySource;
var
  mLibrary: TUnitIndex;
begin
  Result := Default(TQuerySource);
  Result.Index := TSymbolIndex.Create;
  Result.Root := 'C:\P';
  AddText(Result.Index, 'C:\P\Data.Kunden.pas', cKunden);
  AddText(Result.Index, 'C:\P\Main.pas', cMain);
  AddText(Result.Index, 'C:\P\Start.dpr', cStart);
  // Bibliotheks-Unit: im Index, aber nicht im Umfang.
  mLibrary := TIndexExtractor.ExtractText('unit Lib.Fremd; interface type TFremd = class(TObject) end; ' +
    'implementation end.', 'C:\Lib\Lib.Fremd.pas', nil);
  mLibrary.Library_ := True;
  Result.Index.AddUnit(mLibrary);
  Result.Namespaces := TArray<string>.Create('System', 'Vcl');
  Result.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadTestText(AFileName, AText);
    end;
  Result.Calls :=
    function(const ALocation: TSymbolLocation; AIncoming: Boolean): TArray<TQueryCall>
    begin
      Result := TestCalls(ALocation, AIncoming);
    end;
end;

function RowNames(const AResult: TQueryResult): string;
var
  mRow: TQueryRow;
begin
  Result := '';
  if AResult.Failed then
    Exit('Fehler: ' + AResult.Error);
  for mRow in AResult.Rows do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + mRow.QualifiedName;
  end;
end;

function Query(const AText: string): TQueryResult;
begin
  Result := TCodeQueryEngine.Run(QueryTestSource, TQueryRequest.Create(AText, 0), nil);
end;

function CellOf(const AResult: TQueryResult; ARow: Integer; const AColumn: string): TQueryValue;
begin
  Result := AResult.Rows[ARow].Values[AResult.ColumnOf(AColumn)];
end;

{ TQueryEngineTests }

procedure TQueryEngineTests.InheritsTransitivelyAndAsWritten;
begin
  Assert.AreEqual('TBasis,TKunde', RowNames(Query('classes where inherits TInterfacedObject')));
  Assert.AreEqual('TKunde', RowNames(Query('classes where inherits TBasis')));
  // TForm steht nicht im Index; der Vorfahr, wie er geschrieben ist, zählt.
  Assert.AreEqual('TMainForm', RowNames(Query('classes where inherits Vcl.Forms.TForm')));
  // Mitglieder: der deklarierende Typ.
  Assert.AreEqual('TKunde.Speichern,TKunde.Rechne,TKunde.Rechne',
    RowNames(Query('methods where inherits TBasis')));
  Assert.AreEqual('IKundeEx', RowNames(Query('interfaces where inherits IKunde')));
  Assert.AreEqual('', RowNames(Query('classes where inherits TKunde')));
end;

procedure TQueryEngineTests.ImplementsThroughAncestorsAndDerivedInterfaces;
begin
  Assert.AreEqual('TBasis,TKunde', RowNames(Query('classes where implements IKunde')));
  Assert.AreEqual('TBasis,TKunde', RowNames(Query('classes where implements IKundeEx')));
  Assert.AreEqual('TMainForm', RowNames(Query('classes where not implements IKunde')));
end;

procedure TQueryEngineTests.FormsCountComponents;
var
  mResult: TQueryResult;
begin
  mResult := Query('forms where components > 2');
  Assert.AreEqual('TMainForm', RowNames(mResult));
  Assert.AreEqual(Int64(3), CellOf(mResult, 0, 'components').Number);
  Assert.AreEqual('', RowNames(Query('forms where name = TKunde')));
end;

procedure TQueryEngineTests.MethodMetricsMatchCalculator;
var
  mResult: TQueryResult;
  mRoutine: TRoutineMetrics;
  mExpected: Integer;
begin
  mExpected := 0;
  for mRoutine in TMetricsCalculator.ForText(cKunden) do
    if (mRoutine.Name = 'TKunde.Rechne') and (mRoutine.Values[TMetricKind.ParameterCount] = 2) then
      mExpected := mRoutine.Values[TMetricKind.Cyclomatic];
  Assert.IsTrue(mExpected > 3);
  mResult := Query('methods where complexity > 3 and params > 0');
  Assert.AreEqual('TKunde.Rechne', RowNames(mResult));
  // Die Überladung mit zwei Parametern, nicht die erste im Quelltext.
  Assert.AreEqual(Int64(2), CellOf(mResult, 0, 'params').Number);
  Assert.AreEqual(Int64(mExpected), CellOf(mResult, 0, 'complexity').Number);
  // Interface-Methoden haben keinen Rumpf und damit keine Kennzahl.
  Assert.AreEqual('', RowNames(Query('methods where class = IKunde and complexity >= 0')));
  Assert.AreEqual('IKunde.Speichern', RowNames(Query('methods where class = IKunde')));
end;

procedure TQueryEngineTests.CallersCountInferredAndMarkRow;
var
  mResult: TQueryResult;
begin
  mResult := Query('methods where callers > 0 order by callers desc');
  Assert.AreEqual('TBasis.Speichern,TKunde.Speichern', RowNames(mResult));
  Assert.AreEqual(Int64(2), CellOf(mResult, 0, 'callers').Number);
  Assert.IsTrue(mResult.Rows[0].Inferred);
  Assert.Contains(mResult.Rows[0].InferredDetail, 'interface');
  Assert.IsFalse(mResult.Rows[1].Inferred);
  Assert.AreEqual(1, mResult.InferredCount);
  Assert.AreEqual('TKunde.Rechne,TKunde.Rechne,TMainForm.Eins',
    RowNames(Query('methods where callers = 0 and class <> IKunde')));
end;

procedure TQueryEngineTests.CallsMatchesQualifiedAndShortName;
begin
  Assert.AreEqual('TKunde.Speichern', RowNames(Query('methods where calls TBasis.Speichern')));
  Assert.AreEqual('TKunde.Speichern', RowNames(Query('methods where calls Speichern')));
  Assert.AreEqual('', RowNames(Query('methods where calls TKunde.Speichern')));
end;

procedure TQueryEngineTests.UsesAndUsedByWithNamespaces;
var
  mResult: TQueryResult;
begin
  Assert.AreEqual('Main', RowNames(Query('units where uses Data.Kunden')));
  // System.SysUtils über den Namensraum System.
  Assert.AreEqual('Data.Kunden', RowNames(Query('units where uses SysUtils')));
  Assert.AreEqual('Start', RowNames(Query('units where usedBy = 0')));
  mResult := Query('units where uses >= 2');
  Assert.AreEqual('Data.Kunden,Main', RowNames(mResult));
  Assert.AreEqual(Int64(2), CellOf(mResult, 0, 'uses').Number);
  Assert.AreEqual('TMainForm', RowNames(Query('classes where uses Data.Kunden')));
end;

procedure TQueryEngineTests.HasAttributeWithAndWithoutSuffix;
begin
  Assert.AreEqual('TKunde.Speichern', RowNames(Query('methods where has attribute Serializable')));
  Assert.AreEqual('TKunde.Speichern', RowNames(Query('methods where has attribute SerializableAttribute')));
  Assert.AreEqual('', RowNames(Query('classes where has attribute Serializable')));
end;

procedure TQueryEngineTests.LikeNotAndVisibility;
begin
  Assert.AreEqual('IKunde.Speichern,TKunde.Speichern',
    RowNames(Query('methods where name like ''sp*'' and not class = TBasis')));
  Assert.AreEqual('TKunde.FName,TKunde.FAlter', RowNames(Query('fields where visibility = private')));
  Assert.AreEqual('TKunde.FAlter', RowNames(Query('fields where type = Integer and class = TKunde')));
  Assert.AreEqual('TKunde.Name', RowNames(Query('properties where name not like F*')));
end;

procedure TQueryEngineTests.TypeCountsAndRecords;
var
  mResult: TQueryResult;
begin
  mResult := Query('classes where fields = 2');
  Assert.AreEqual('TKunde', RowNames(mResult));
  Assert.AreEqual(Int64(2), CellOf(mResult, 0, 'fields').Number);
  mResult := Query('classes where methods >= 3 and properties = 1 and overrides = 1');
  Assert.AreEqual('TKunde', RowNames(mResult));
  Assert.AreEqual(Int64(3), CellOf(mResult, 0, 'methods').Number);
  Assert.AreEqual('TPunkt', RowNames(Query('records where fields = 2')));
  // Vorwärtsdeklaration und Deklaration zählen einmal.
  Assert.AreEqual('TBasis', RowNames(Query('classes where name = TBasis')));
  Assert.AreEqual('Data.Kunden', RowNames(Query('units where classes = 2')));
end;

procedure TQueryEngineTests.RoutinesCountOnce;
begin
  Assert.AreEqual('Hilfe', RowNames(Query('routines')));
end;

procedure TQueryEngineTests.OrderByIsUniqueOnTies;
var
  mFirst, mSecond: string;
begin
  // Gleiche Parameterzahl: dann nach Unit, Zeile und Name, immer gleich.
  mFirst := RowNames(Query('methods order by params desc'));
  mSecond := RowNames(Query('methods order by params desc'));
  Assert.AreEqual(mFirst, mSecond);
  Assert.StartsWith('TKunde.Rechne,TKunde.Rechne,', mFirst);
  Assert.AreEqual('IKunde.Speichern,TBasis.Speichern,TKunde.Speichern,TKunde.Rechne,TKunde.Rechne,TMainForm.Eins',
    RowNames(Query('methods')));
  // Werte ohne Wert (Interface-Methode ohne Rumpf) stehen auch absteigend am Ende.
  mFirst := RowNames(Query('methods order by complexity desc'));
  Assert.AreEqual('IKunde.Speichern', Copy(mFirst, Length(mFirst) - Length('IKunde.Speichern') + 1, MaxInt));
end;

procedure TQueryEngineTests.LimitKeepsTotal;
var
  mResult: TQueryResult;
begin
  mResult := Query('methods limit 2');
  Assert.AreEqual(Integer(2), Integer(Length(mResult.Rows)));
  Assert.AreEqual(6, mResult.Total);
  Assert.IsTrue(mResult.Truncated);
  mResult := TCodeQueryEngine.Run(QueryTestSource, TQueryRequest.Create('methods limit 4', 3), nil);
  Assert.AreEqual(Integer(3), Integer(Length(mResult.Rows)));
end;

procedure TQueryEngineTests.ColumnsFromQueryAndRequest;
var
  mRequest: TQueryRequest;
  mResult: TQueryResult;
begin
  mRequest := TQueryRequest.Create('methods where complexity > 3 order by lines', 0);
  mRequest.Fields := TArray<string>.Create('callers', 'unbekannt', 'components');
  mResult := TCodeQueryEngine.Run(QueryTestSource, mRequest, nil);
  Assert.AreEqual('name,class,unit,line,complexity,lines,callers', string.Join(',', mResult.Columns));
  Assert.AreEqual('C:\P\Data.Kunden.pas', mResult.Rows[0].FileName);
  Assert.AreEqual('Data.Kunden.pas', mResult.Rows[0].Path);
  Assert.AreEqual('methods', mResult.Entity);
end;

procedure TQueryEngineTests.ScopeExcludesLibraryAndOtherFiles;
var
  mSource: TQuerySource;
begin
  Assert.AreEqual('TBasis,TKunde,TMainForm', RowNames(Query('classes')));
  mSource := QueryTestSource;
  mSource.Files := TArray<string>.Create('C:\P\Main.pas');
  Assert.AreEqual('TMainForm', RowNames(TCodeQueryEngine.Run(mSource, TQueryRequest.Create('classes', 0), nil)));
end;

procedure TQueryEngineTests.CancelledReportsError;
var
  mSource: TQuerySource;
  mResult: TQueryResult;
begin
  mSource := QueryTestSource;
  mSource.Cancelled :=
    function: Boolean
    begin
      Result := True;
    end;
  mResult := TCodeQueryEngine.Run(mSource, TQueryRequest.Create('classes', 0), nil);
  Assert.IsTrue(mResult.Failed);
  Assert.AreEqual(0, mResult.ErrorColumn);
  Assert.AreEqual(Integer(0), Integer(Length(mResult.Rows)));
end;

procedure TQueryEngineTests.SyntaxErrorInResult;
var
  mResult: TQueryResult;
begin
  mResult := Query('classes where methode > 4');
  Assert.IsTrue(mResult.Failed);
  Assert.AreEqual(15, mResult.ErrorColumn);
  Assert.AreEqual('methods', mResult.Suggestion);
end;

procedure TQueryEngineTests.ThousandUnitsUnderTwoSeconds;
var
  mSource: TQuerySource;
  mUnit, mMethod: Integer;
  mText: string;
  mWatch: TStopwatch;
  mResult: TQueryResult;
begin
  mSource := Default(TQuerySource);
  mSource.Index := TSymbolIndex.Create;
  mSource.Root := 'C:\P';
  for mUnit := 1 to 1000 do
  begin
    mText := Format('unit U%d; interface uses Vcl.Forms; type TForm%d = class(TForm)', [mUnit, mUnit]);
    // Jede zehnte Klasse hat mehr als 40 Methoden.
    for mMethod := 1 to 20 + (mUnit mod 10) * 3 do
      mText := mText + Format(' procedure M%d;', [mMethod]);
    mText := mText + ' end; implementation end.';
    mSource.Index.AddUnit(TIndexExtractor.ExtractText(mText, Format('C:\P\U%d.pas', [mUnit]), nil));
  end;
  mWatch := TStopwatch.StartNew;
  mResult := TCodeQueryEngine.Run(mSource, TQueryRequest.Create(
    'classes where inherits TForm and methods > 40 order by methods desc', 0), nil);
  mWatch.Stop;
  Assert.IsFalse(mResult.Failed, mResult.Error);
  Assert.AreEqual(300, mResult.Total);
  Assert.AreEqual(Int64(47), CellOf(mResult, 0, 'methods').Number);
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 2000, Format('%d ms', [mWatch.ElapsedMilliseconds]));
end;

initialization

finalization
  gTexts.Free;

end.
