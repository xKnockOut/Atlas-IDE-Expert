unit Atlas.Common.Index.Content.Tests;

// Tests für Inhalt, Cache und Verwendungen des Symbolindex (#492): Signatur,
// Direktiven und XMLDoc-Kurztext je Deklaration, Verwendungen der Bezeichner,
// Cache mit Prüfsumme, Auslagern der Verwendungen beim Speicherbudget und die
// Zeitziele beim Öffnen und Speichern.

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Builder,
  Atlas.Common.Index.Service,
  Atlas.Common.Index.Tests;

type
  [TestFixture]
  TIndexContentTests = class
  public
    [Test]
    procedure ExtractsSignatureDirectivesAndSummary;
    [Test]
    procedure MarksClassMembers;
    /// <summary>Prozedurtypen über mehrere Zeilen (#1326): ganze Signatur und Merkmal "of object" bzw.
    /// "reference to".</summary>
    [Test]
    procedure ProcedureTypesOverSeveralLines;
    [Test]
    procedure CollectsUsagesWithoutDeclarations;
    [Test]
    procedure UsagesOnlyOnRequest;
    [Test]
    procedure CacheRoundTripsContentAndUsages;
    [Test]
    procedure ChecksumRejectsChangedByte;
    [Test]
    procedure ExpandWithoutUsagesMarksOffloaded;
    [Test]
    procedure BudgetOffloadsUsagesFirst;
  end;

  [TestFixture]
  TIndexServiceCacheTests = class
  private
    FFiles: TMemoryIndexFileSystem;
    FFilesRef: IIndexFileSystem;
    FResult: TIndexBuildResult;
    FRejected: string;
    function Start(const AIndex: ISymbolIndex; const AFiles: TArray<string>; AUsages: Boolean): TIndexService;
    procedure Build(const AIndex: ISymbolIndex; const AFiles: TArray<string>; AUsages: Boolean);
  public
    /// <summary>Erste Benutzung (VCL, Codepages, RTTI) ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DamagedCacheIsRebuiltSilently;
    [Test]
    procedure OffloadedUsagesComeBackFromCache;
    [Test]
    procedure SwitchingUsagesOnRereadsCachedUnits;
    [Test]
    [Category('Benchmark')]
    procedure ReopensThousandUnitsFromCacheWithinThreeSeconds;
    [Test]
    procedure SavedDeclarationIsAvailableWithinOneSecond;
  end;

implementation

uses
  System.Diagnostics,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.Cache,
  Atlas.Common.Index.Memory,
  Atlas.Common.Index.SymbolIndex;

const
  KundeFile = 'C:\P\Kunde.pas';
  CacheFile = 'C:\Cache\Index\37.0\P\index.atlasidx';
  // Zeilen 0-basiert; die Tests nennen Zeilennummern.
  UnitKunde =
    'unit Kunde;'#13#10 +                                                          // 0
    'interface'#13#10 +                                                            // 1
    'type'#13#10 +                                                                 // 2
    '  /// <summary>Ein Kunde mit <c>Name</c>.</summary>'#13#10 +                  // 3
    '  TKunde = class(TObject)'#13#10 +                                            // 4
    '  public'#13#10 +                                                             // 5
    '    /// <summary>Liefert den Namen.</summary>'#13#10 +                        // 6
    '    function GetName(AIndex: Integer = 0): string; virtual; overload;'#13#10 + // 7
    '    class function Neu: TKunde; static; inline;'#13#10 +                      // 8
    '    procedure Alt; deprecated ''Neu nehmen'';'#13#10 +                       // 9
    '    property Name: string read GetName;'#13#10 +                              // 10
    '  end;'#13#10 +                                                               // 11
    'const'#13#10 +                                                                // 12
    '  Grenze = 10 platform;'#13#10 +                                              // 13
    'var'#13#10 +                                                                  // 14
    '  Zaehler: Integer;'#13#10 +                                                  // 15
    'implementation'#13#10 +                                                       // 16
    'function TKunde.GetName(AIndex: Integer): string;'#13#10 +                    // 17
    'begin'#13#10 +                                                                // 18
    '  Result := IntToStr(Zaehler) + IntToStr(Grenze);'#13#10 +                    // 19
    'end;'#13#10 +                                                                 // 20
    'class function TKunde.Neu: TKunde; begin Result := nil; end;'#13#10 +         // 21
    'procedure TKunde.Alt; begin end;'#13#10 +                                     // 22
    'end.';                                                                        // 23

function ExtractKunde(AUsages: Boolean): TUnitIndex;
begin
  Result := TIndexExtractor.ExtractText(UnitKunde, KundeFile, nil, nil, AUsages);
end;

function Find(const AUnit: TUnitIndex; const AQualifiedName: string): TIndexSymbol;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
    if SameText(Symbol.QualifiedName, AQualifiedName) then
      Exit(Symbol);
  Assert.Fail('Symbol fehlt: ' + AQualifiedName);
  Result := Default(TIndexSymbol);
end;

function FindUsage(const AUsages: TArray<TIndexUsage>; const AName: string; out AUsage: TIndexUsage): Boolean;
var
  Usage: TIndexUsage;
begin
  for Usage in AUsages do
    if SameText(Usage.Name, AName) then
    begin
      AUsage := Usage;
      Exit(True);
    end;
  Result := False;
end;

function ResolveNothing(const AUnitName: string): string;
begin
  Result := '';
end;

/// <summary>Unit mit 20 virtuellen Methoden und 10 Feldern für den Zeittest.</summary>
function GenerateUnit(ANumber: Integer): string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('unit U').Append(ANumber).Append(';'#13#10'interface'#13#10'type'#13#10);
    Builder.Append('  TKlasse').Append(ANumber).Append(' = class'#13#10'  private'#13#10);
    for Index := 1 to 10 do
      Builder.Append('    FFeld').Append(Index).Append(': Integer;'#13#10);
    Builder.Append('  public'#13#10);
    for Index := 1 to 20 do
      Builder.Append('    procedure Methode').Append(Index).Append('(A: Integer); virtual;'#13#10);
    Builder.Append('  end;'#13#10'implementation'#13#10);
    for Index := 1 to 20 do
      Builder.Append('procedure TKlasse').Append(ANumber).Append('.Methode').Append(Index)
        .Append('(A: Integer); begin FFeld1 := A; end;'#13#10);
    Builder.Append('end.');
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

{ TIndexContentTests }

procedure TIndexContentTests.ExtractsSignatureDirectivesAndSummary;
var
  U: TUnitIndex;
  Symbol: TIndexSymbol;
begin
  U := ExtractKunde(False);
  Symbol := Find(U, 'TKunde');
  Assert.AreEqual('TKunde = class(TObject)', Symbol.Signature);
  Assert.AreEqual('Ein Kunde mit Name.', Symbol.Summary);
  Symbol := Find(U, 'TKunde.GetName');
  Assert.IsTrue(Symbol.Signature.StartsWith('function GetName(AIndex: Integer = 0): string'), Symbol.Signature);
  Assert.IsTrue(Symbol.HasDirective('virtual'));
  Assert.IsTrue(Symbol.HasDirective('overload'));
  Assert.AreEqual('Liefert den Namen.', Symbol.Summary);
  Symbol := Find(U, 'TKunde.Neu');
  Assert.IsTrue(Symbol.HasDirective('static'));
  Assert.IsTrue(Symbol.HasDirective('inline'));
  Assert.IsTrue(Find(U, 'TKunde.Alt').HasDirective('deprecated'));
  // Grund für Hover und Regel deprecated-symbol (#38).
  Assert.AreEqual('Neu nehmen', Find(U, 'TKunde.Alt').DeprecatedText);
  Assert.AreEqual('', Find(U, 'Grenze').DeprecatedText);
  Assert.AreEqual('property Name: string read GetName', Find(U, 'TKunde.Name').Signature);
  Assert.IsTrue(Find(U, 'Grenze').HasDirective('platform'));
  Assert.AreEqual('Zaehler: Integer', Find(U, 'Zaehler').Signature);
end;

procedure TIndexContentTests.ProcedureTypesOverSeveralLines;
var
  mUnit: TUnitIndex;
begin
  mUnit := TIndexExtractor.ExtractText('unit Ereignisse;'#10'interface'#10'type'#10 +
    '  TEv1 = procedure(Sender: TObject;'#10'    X: Integer) of object;'#10 +
    '  TEv2 = procedure(Sender: TObject;'#10'    X: Integer)'#10'    of { Methode } object;'#10 +
    '  TRoh = procedure(Sender: TObject;'#10'    X: Integer);'#10 +
    '  TRef = reference to procedure(Sender: TObject;'#10'    X: Integer);'#10 +
    '  TFeld = array[0..1] of Byte;'#10'implementation'#10'end.', 'C:\Projekt\Ereignisse.pas', nil);
  Assert.AreEqual('TEv1 = procedure(Sender: TObject; X: Integer) of object', Find(mUnit, 'TEv1').Signature);
  Assert.IsTrue(Find(mUnit, 'TEv1').HasDirective('of object'));
  Assert.IsTrue(Find(mUnit, 'TEv2').HasDirective('of object'));
  Assert.AreEqual('TRoh = procedure(Sender: TObject; X: Integer)', Find(mUnit, 'TRoh').Signature);
  Assert.IsFalse(Find(mUnit, 'TRoh').HasDirective('of object'));
  Assert.IsTrue(Find(mUnit, 'TRef').HasDirective('reference to'));
  Assert.IsFalse(Find(mUnit, 'TRef').HasDirective('of object'));
  Assert.AreEqual(0, Integer(Length(Find(mUnit, 'TFeld').Directives)));
end;

procedure TIndexContentTests.MarksClassMembers;
var
  U: TUnitIndex;
begin
  U := TIndexExtractor.ExtractText(
    'unit Zaehler;'#10'interface'#10'type'#10 +
    '  TErster = class'#10'    property Wert: Integer read FWert;'#10'  var'#10'    FWert: Integer;'#10'  end;'#10 +
    '  TZaehler = class'#10'  private'#10'    FName: string;'#10'    class var FAnzahl: Integer;'#10 +
    '    FGesamt: Integer;'#10'  public'#10'    class function Neu: TZaehler;'#10'    function Name: string;'#10 +
    '    class property Anzahl: Integer read FAnzahl;'#10'    property Titel: string read FName;'#10 +
    '  var'#10'    FLetzter: Integer;'#10'  end;'#10'implementation'#10'end.', 'Zaehler.pas', nil, nil, False);
  // #1001: class var gilt bis zum nächsten Abschnitt, "TErster = class" vor dem ersten Mitglied zählt nicht.
  Assert.IsTrue(Find(U, 'TZaehler.FAnzahl').HasDirective('class'));
  Assert.IsTrue(Find(U, 'TZaehler.FGesamt').HasDirective('class'));
  Assert.IsTrue(Find(U, 'TZaehler.Neu').HasDirective('class'));
  Assert.IsTrue(Find(U, 'TZaehler.Anzahl').HasDirective('class'));
  Assert.IsFalse(Find(U, 'TZaehler.FName').HasDirective('class'));
  Assert.IsFalse(Find(U, 'TZaehler.Name').HasDirective('class'));
  Assert.IsFalse(Find(U, 'TZaehler.Titel').HasDirective('class'));
  Assert.IsFalse(Find(U, 'TZaehler.FLetzter').HasDirective('class'));
  Assert.IsFalse(Find(U, 'TErster.Wert').HasDirective('class'));
  Assert.IsFalse(Find(U, 'TErster.FWert').HasDirective('class'));
end;

procedure TIndexContentTests.CollectsUsagesWithoutDeclarations;
var
  U: TUnitIndex;
  Usage: TIndexUsage;
begin
  U := ExtractKunde(True);
  Assert.IsTrue(FindUsage(U.Usages, 'Zaehler', Usage));
  // Die Deklaration in Zeile 15 zählt nicht.
  Assert.AreEqual<NativeInt>(1, Length(Usage.Positions));
  Assert.AreEqual(19, Usage.Positions[0].Line);
  Assert.IsTrue(FindUsage(U.Usages, 'IntToStr', Usage));
  Assert.AreEqual<NativeInt>(2, Length(Usage.Positions));
  Assert.IsFalse(FindUsage(U.Usages, 'Result', Usage));
  Assert.IsFalse(FindUsage(U.Usages, 'virtual', Usage));
  Assert.IsFalse(FindUsage(U.Usages, 'begin', Usage));
end;

procedure TIndexContentTests.UsagesOnlyOnRequest;
var
  U: TUnitIndex;
begin
  U := ExtractKunde(False);
  Assert.IsFalse(U.UsagesIndexed);
  Assert.AreEqual<NativeInt>(0, Length(U.Usages));
  U := ExtractKunde(True);
  Assert.IsTrue(U.UsagesIndexed);
  Assert.IsTrue(Length(U.Usages) > 0);
end;

procedure TIndexContentTests.CacheRoundTripsContentAndUsages;
var
  Units: TArray<TUnitIndex>;
  Symbol: TIndexSymbol;
  Usage: TIndexUsage;
begin
  Units := TIndexCache.Deserialize(TIndexCache.Serialize([ExtractKunde(True)]));
  Assert.AreEqual<NativeInt>(1, Length(Units));
  Symbol := Find(Units[0], 'TKunde.GetName');
  Assert.IsTrue(Symbol.Signature.StartsWith('function GetName('), Symbol.Signature);
  Assert.IsTrue(Symbol.HasDirective('virtual'));
  Assert.AreEqual('Liefert den Namen.', Symbol.Summary);
  Assert.AreEqual('Neu nehmen', Find(Units[0], 'TKunde.Alt').DeprecatedText);
  Assert.IsTrue(Units[0].UsagesIndexed);
  Assert.IsTrue(FindUsage(Units[0].Usages, 'Zaehler', Usage));
  Assert.AreEqual(19, Usage.Positions[0].Line);
  Assert.IsTrue(FindUsage(Units[0].Usages, 'IntToStr', Usage));
  Assert.AreEqual<NativeInt>(2, Length(Usage.Positions));
  Assert.IsTrue(Usage.Positions[0].Character < Usage.Positions[1].Character);
end;

procedure TIndexContentTests.ChecksumRejectsChangedByte;
var
  Data, Changed: TBytes;
  Reason: string;
begin
  Data := TIndexCache.Serialize([ExtractKunde(True)]);
  Assert.AreEqual<NativeInt>(1, Length(TIndexCache.ReadEntries(Data, Reason)));
  Assert.AreEqual('', Reason);
  Changed := Copy(Data);
  Changed[High(Changed)] := Changed[High(Changed)] xor $FF;
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.ReadEntries(Changed, Reason)));
  Assert.AreEqual('Prüfsumme stimmt nicht', Reason);
  // Abgeschnitten: ebenfalls die Prüfsumme.
  Changed := Copy(Data, 0, Length(Data) - 3);
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.ReadEntries(Changed, Reason)));
  Assert.AreEqual('Prüfsumme stimmt nicht', Reason);
  Changed := Copy(Data);
  Changed[8] := 11;
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.ReadEntries(Changed, Reason)));
  Assert.AreEqual(Format('Formatversion 11 statt %d', [TIndexCache.FormatVersion]), Reason);
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.ReadEntries(TEncoding.UTF8.GetBytes('{"units":[]}'), Reason)));
  Assert.IsTrue(Reason.StartsWith('kein Atlas-Index'), Reason);
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.ReadEntries(nil, Reason)));
  Assert.AreEqual('', Reason);
end;

procedure TIndexContentTests.ExpandWithoutUsagesMarksOffloaded;
var
  Entries: TArray<TIndexCacheEntry>;
  U: TUnitIndex;
  Usages: TArray<TIndexUsage>;
  Usage: TIndexUsage;
begin
  Entries := TIndexCache.ReadEntries(TIndexCache.Serialize([ExtractKunde(True)]));
  Assert.AreEqual<NativeInt>(1, Length(Entries));
  Assert.IsTrue(TIndexCache.Expand(Entries[0], U, False));
  Assert.IsTrue(U.UsagesIndexed);
  Assert.IsTrue(U.UsagesOffloaded);
  Assert.AreEqual<NativeInt>(0, Length(U.Usages));
  Assert.IsTrue(Length(U.Symbols) > 0);
  Assert.IsTrue(TIndexCache.ExpandUsages(Entries[0], Usages));
  Assert.IsTrue(FindUsage(Usages, 'Zaehler', Usage));
  Assert.AreEqual(19, Usage.Positions[0].Line);
end;

procedure TIndexContentTests.BudgetOffloadsUsagesFirst;
var
  Index: ISymbolIndex;
  U, Found: TUnitIndex;
begin
  U := ExtractKunde(True);
  Index := TSymbolIndex.Create;
  // Ohne Verwendungen passt die Unit ins Budget: Es wird nur ausgelagert, nicht verdichtet.
  Index.SetBudget(TIndexMemory.UnitBytes(TIndexMemory.WithoutUsages(U)) + 16);
  Index.AddUnit(U);
  Assert.AreEqual(1, Index.OffloadedCount);
  Assert.AreEqual(0, Index.CompactCount);
  Assert.IsTrue(Index.FindFile(KundeFile, Found));
  Assert.IsTrue(Found.UsagesOffloaded);
  Assert.IsFalse(Found.Compact);
  Assert.AreEqual<NativeInt>(Length(U.Symbols), Length(Found.Symbols));
end;

{ TIndexServiceCacheTests }

procedure TIndexServiceCacheTests.WarmUpFirstUse;
begin
  Setup;
  try
    DamagedCacheIsRebuiltSilently;
  finally
    TearDown;
  end;
end;

procedure TIndexServiceCacheTests.Setup;
begin
  FFiles := TMemoryIndexFileSystem.Create;
  FFilesRef := FFiles;
  FFiles.Put(KundeFile, UnitKunde, 1);
end;

procedure TIndexServiceCacheTests.TearDown;
begin
  FFiles := nil;
  FFilesRef := nil;
end;

function TIndexServiceCacheTests.Start(const AIndex: ISymbolIndex; const AFiles: TArray<string>;
  AUsages: Boolean): TIndexService;
var
  Request: TIndexRequest;
begin
  FResult := Default(TIndexBuildResult);
  FRejected := '';
  Result := TIndexService.Create(AIndex, FFilesRef);
  Result.OnFinished :=
    procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
    begin
      FResult := AResult;
    end;
  Result.OnCacheRejected :=
    procedure(const AFileName, AReason: string)
    begin
      FRejected := AReason;
    end;
  Request := Default(TIndexRequest);
  Request.Files := AFiles;
  Request.ResolveUnit := ResolveNothing;
  Request.CacheFile := CacheFile;
  Request.Usages := AUsages;
  Result.Start(Request);
  Result.WaitFor;
end;

procedure TIndexServiceCacheTests.Build(const AIndex: ISymbolIndex; const AFiles: TArray<string>; AUsages: Boolean);
begin
  Start(AIndex, AFiles, AUsages).Free;
end;

procedure TIndexServiceCacheTests.DamagedCacheIsRebuiltSilently;
var
  Data: TBytes;
  Reason: string;
  Index: ISymbolIndex;
  Found: TUnitIndex;
begin
  Build(TSymbolIndex.Create, [KundeFile], True);
  Assert.IsTrue(FFiles.ReadBytes(CacheFile, Data));
  Data[High(Data)] := Data[High(Data)] xor $FF;
  FFiles.WriteBytes(CacheFile, Data);
  Index := TSymbolIndex.Create;
  Build(Index, [KundeFile], True);
  // Verworfen mit Grund fürs Log, neu gelesen, ohne Fehler.
  Assert.AreEqual('Prüfsumme stimmt nicht', FRejected);
  Assert.AreEqual(1, FResult.Parsed);
  Assert.AreEqual(0, FResult.FromCache);
  Assert.IsTrue(Index.FindUnit('Kunde', Found));
  // Der neu geschriebene Cache ist wieder gültig.
  Assert.IsTrue(FFiles.ReadBytes(CacheFile, Data));
  Assert.AreEqual<NativeInt>(1, Length(TIndexCache.ReadEntries(Data, Reason)));
  Assert.AreEqual('', Reason);
end;

procedure TIndexServiceCacheTests.OffloadedUsagesComeBackFromCache;
var
  First, Index: ISymbolIndex;
  Service: TIndexService;
  Found: TUnitIndex;
  Usages: TArray<TIndexUsage>;
  Usage: TIndexUsage;
begin
  First := TSymbolIndex.Create;
  Build(First, [KundeFile], True);
  Assert.IsTrue(First.FindFile(KundeFile, Found));
  Index := TSymbolIndex.Create;
  Index.SetBudget(TIndexMemory.UnitBytes(TIndexMemory.WithoutUsages(Found)) + 16);
  Service := Start(Index, [KundeFile], True);
  try
    Assert.AreEqual(1, FResult.FromCache);
    Assert.IsTrue(Index.FindFile(KundeFile, Found));
    Assert.IsTrue(Found.UsagesOffloaded);
    Assert.AreEqual(1, Index.OffloadedCount);
    // Die Quelle ist weg: Die Verwendungen kommen aus dem Cache.
    FFiles.Delete(KundeFile);
    Assert.IsTrue(Service.UsagesOf(KundeFile, Usages));
    Assert.IsTrue(FindUsage(Usages, 'Zaehler', Usage));
    Assert.AreEqual(19, Usage.Positions[0].Line);
  finally
    Service.Free;
  end;
end;

procedure TIndexServiceCacheTests.SwitchingUsagesOnRereadsCachedUnits;
var
  Index: ISymbolIndex;
  Found: TUnitIndex;
begin
  Build(TSymbolIndex.Create, [KundeFile], False);
  // Cache ohne Verwendungen passt nicht, wenn sie jetzt gewünscht sind.
  Index := TSymbolIndex.Create;
  Build(Index, [KundeFile], True);
  Assert.AreEqual(1, FResult.Parsed);
  Assert.AreEqual(0, FResult.FromCache);
  Assert.IsTrue(Index.FindFile(KundeFile, Found));
  Assert.IsTrue(Found.UsagesIndexed);
  Index := TSymbolIndex.Create;
  Build(Index, [KundeFile], True);
  Assert.AreEqual(1, FResult.FromCache);
  // Abgeschaltet: der Cache passt weiter, die Verwendungen bleiben draußen.
  Index := TSymbolIndex.Create;
  Build(Index, [KundeFile], False);
  Assert.AreEqual(1, FResult.FromCache);
  Assert.IsTrue(Index.FindFile(KundeFile, Found));
  Assert.IsFalse(Found.UsagesIndexed);
  Assert.AreEqual<NativeInt>(0, Length(Found.Usages));
end;

procedure TIndexServiceCacheTests.ReopensThousandUnitsFromCacheWithinThreeSeconds;
const
  UnitCount = 1000;
var
  Files: TArray<string>;
  Number: Integer;
  Index: ISymbolIndex;
  Watch: TStopwatch;
begin
  SetLength(Files, UnitCount);
  for Number := 1 to UnitCount do
  begin
    Files[Number - 1] := Format('C:\P\U%d.pas', [Number]);
    FFiles.Put(Files[Number - 1], GenerateUnit(Number), 1);
  end;
  Build(TSymbolIndex.Create, Files, True);
  Assert.AreEqual(UnitCount, FResult.Parsed);
  Index := TSymbolIndex.Create;
  Watch := TStopwatch.StartNew;
  Build(Index, Files, True);
  Watch.Stop;
  Assert.AreEqual(UnitCount, FResult.FromCache);
  Assert.AreEqual(UnitCount, Index.UnitCount);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 3000, Format('%d ms', [Watch.ElapsedMilliseconds]));
end;

procedure TIndexServiceCacheTests.SavedDeclarationIsAvailableWithinOneSecond;
var
  Index: ISymbolIndex;
  Service: TIndexService;
  Watch: TStopwatch;
begin
  Index := TSymbolIndex.Create;
  Service := Start(Index, [KundeFile], True);
  try
    Assert.AreEqual(0, Integer(Length(Index.FindSymbols('NeueFunktion'))));
    FFiles.Put(KundeFile, StringReplace(UnitKunde, 'var'#13#10, 'procedure NeueFunktion;'#13#10'var'#13#10, []), 2);
    Watch := TStopwatch.StartNew;
    Assert.AreEqual(1, Service.ApplyChanges([TFileChange.Create(KundeFile, TFileChangeKind.Changed)]));
    Watch.Stop;
    Assert.AreEqual(1, Integer(Length(Index.FindSymbols('NeueFunktion'))));
    Assert.IsTrue(Watch.ElapsedMilliseconds < 1000, Format('%d ms', [Watch.ElapsedMilliseconds]));
  finally
    Service.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexContentTests);
  TDUnitX.RegisterTestFixture(TIndexServiceCacheTests);

end.
