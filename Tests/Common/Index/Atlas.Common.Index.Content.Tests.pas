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
  cKundeFile = 'C:\P\Kunde.pas';
  cCacheFile = 'C:\Cache\Index\37.0\P\index.atlasidx';
  // Zeilen 0-basiert; die Tests nennen Zeilennummern.
  cUnitKunde =
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
  Result := TIndexExtractor.ExtractText(cUnitKunde, cKundeFile, nil, nil, AUsages);
end;

function Find(const AUnit: TUnitIndex; const AQualifiedName: string): TIndexSymbol;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.QualifiedName, AQualifiedName) then
    begin
      Exit(mSymbol);
    end;
  end;
  Assert.Fail('Symbol fehlt: ' + AQualifiedName);
  Result := Default(TIndexSymbol);
end;

function FindUsage(const AUsages: TArray<TIndexUsage>; const AName: string; out AUsage: TIndexUsage): Boolean;
var
  mUsage: TIndexUsage;
begin
  for mUsage in AUsages do
  begin
    if SameText(mUsage.Name, AName) then
    begin
      AUsage := mUsage;
      Exit(True);
    end;
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
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('unit U').Append(ANumber).Append(';'#13#10'interface'#13#10'type'#13#10);
    mBuilder.Append('  TKlasse').Append(ANumber).Append(' = class'#13#10'  private'#13#10);
    for mIndex := 1 to 10 do
    begin
      mBuilder.Append('    FFeld').Append(mIndex).Append(': Integer;'#13#10);
    end;
    mBuilder.Append('  public'#13#10);
    for mIndex := 1 to 20 do
    begin
      mBuilder.Append('    procedure Methode').Append(mIndex).Append('(A: Integer); virtual;'#13#10);
    end;
    mBuilder.Append('  end;'#13#10'implementation'#13#10);
    for mIndex := 1 to 20 do
    begin
      mBuilder.Append('procedure TKlasse').Append(ANumber).Append('.Methode').Append(mIndex)
        .Append('(A: Integer); begin FFeld1 := A; end;'#13#10);
    end;
    mBuilder.Append('end.');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

{ TIndexContentTests }

procedure TIndexContentTests.ExtractsSignatureDirectivesAndSummary;
var
  U: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  U := ExtractKunde(False);
  mSymbol := Find(U, 'TKunde');
  Assert.AreEqual('TKunde = class(TObject)', mSymbol.Signature);
  Assert.AreEqual('Ein Kunde mit Name.', mSymbol.Summary);
  mSymbol := Find(U, 'TKunde.GetName');
  Assert.IsTrue(mSymbol.Signature.StartsWith('function GetName(AIndex: Integer = 0): string'), mSymbol.Signature);
  Assert.IsTrue(mSymbol.HasDirective('virtual'));
  Assert.IsTrue(mSymbol.HasDirective('overload'));
  Assert.AreEqual('Liefert den Namen.', mSymbol.Summary);
  mSymbol := Find(U, 'TKunde.Neu');
  Assert.IsTrue(mSymbol.HasDirective('static'));
  Assert.IsTrue(mSymbol.HasDirective('inline'));
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
  mUsage: TIndexUsage;
begin
  U := ExtractKunde(True);
  Assert.IsTrue(FindUsage(U.Usages, 'Zaehler', mUsage));
  // Die Deklaration in Zeile 15 zählt nicht.
  Assert.AreEqual<NativeInt>(1, Length(mUsage.Positions));
  Assert.AreEqual(19, mUsage.Positions[0].Line);
  Assert.IsTrue(FindUsage(U.Usages, 'IntToStr', mUsage));
  Assert.AreEqual<NativeInt>(2, Length(mUsage.Positions));
  Assert.IsFalse(FindUsage(U.Usages, 'Result', mUsage));
  Assert.IsFalse(FindUsage(U.Usages, 'virtual', mUsage));
  Assert.IsFalse(FindUsage(U.Usages, 'begin', mUsage));
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
  mUnits: TArray<TUnitIndex>;
  mSymbol: TIndexSymbol;
  mUsage: TIndexUsage;
begin
  mUnits := TIndexCache.Deserialize(TIndexCache.Serialize([ExtractKunde(True)]));
  Assert.AreEqual<NativeInt>(1, Length(mUnits));
  mSymbol := Find(mUnits[0], 'TKunde.GetName');
  Assert.IsTrue(mSymbol.Signature.StartsWith('function GetName('), mSymbol.Signature);
  Assert.IsTrue(mSymbol.HasDirective('virtual'));
  Assert.AreEqual('Liefert den Namen.', mSymbol.Summary);
  Assert.AreEqual('Neu nehmen', Find(mUnits[0], 'TKunde.Alt').DeprecatedText);
  Assert.IsTrue(mUnits[0].UsagesIndexed);
  Assert.IsTrue(FindUsage(mUnits[0].Usages, 'Zaehler', mUsage));
  Assert.AreEqual(19, mUsage.Positions[0].Line);
  Assert.IsTrue(FindUsage(mUnits[0].Usages, 'IntToStr', mUsage));
  Assert.AreEqual<NativeInt>(2, Length(mUsage.Positions));
  Assert.IsTrue(mUsage.Positions[0].Character < mUsage.Positions[1].Character);
end;

procedure TIndexContentTests.ChecksumRejectsChangedByte;
var
  mData, mChanged: TBytes;
  mReason: string;
begin
  mData := TIndexCache.Serialize([ExtractKunde(True)]);
  Assert.AreEqual<NativeInt>(1, Length(TIndexCache.ReadEntries(mData, mReason)));
  Assert.AreEqual('', mReason);
  mChanged := Copy(mData);
  mChanged[High(mChanged)] := mChanged[High(mChanged)] xor $FF;
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.ReadEntries(mChanged, mReason)));
  Assert.AreEqual('Prüfsumme stimmt nicht', mReason);
  // Abgeschnitten: ebenfalls die Prüfsumme.
  mChanged := Copy(mData, 0, Length(mData) - 3);
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.ReadEntries(mChanged, mReason)));
  Assert.AreEqual('Prüfsumme stimmt nicht', mReason);
  mChanged := Copy(mData);
  mChanged[8] := 11;
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.ReadEntries(mChanged, mReason)));
  Assert.AreEqual(Format('Formatversion 11 statt %d', [TIndexCache.cFormatVersion]), mReason);
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.ReadEntries(TEncoding.UTF8.GetBytes('{"units":[]}'), mReason)));
  Assert.IsTrue(mReason.StartsWith('kein Atlas-Index'), mReason);
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.ReadEntries(nil, mReason)));
  Assert.AreEqual('', mReason);
end;

procedure TIndexContentTests.ExpandWithoutUsagesMarksOffloaded;
var
  mEntries: TArray<TIndexCacheEntry>;
  U: TUnitIndex;
  mUsages: TArray<TIndexUsage>;
  mUsage: TIndexUsage;
begin
  mEntries := TIndexCache.ReadEntries(TIndexCache.Serialize([ExtractKunde(True)]));
  Assert.AreEqual<NativeInt>(1, Length(mEntries));
  Assert.IsTrue(TIndexCache.Expand(mEntries[0], U, False));
  Assert.IsTrue(U.UsagesIndexed);
  Assert.IsTrue(U.UsagesOffloaded);
  Assert.AreEqual<NativeInt>(0, Length(U.Usages));
  Assert.IsTrue(Length(U.Symbols) > 0);
  Assert.IsTrue(TIndexCache.ExpandUsages(mEntries[0], mUsages));
  Assert.IsTrue(FindUsage(mUsages, 'Zaehler', mUsage));
  Assert.AreEqual(19, mUsage.Positions[0].Line);
end;

procedure TIndexContentTests.BudgetOffloadsUsagesFirst;
var
  mIndex: ISymbolIndex;
  U, mFound: TUnitIndex;
begin
  U := ExtractKunde(True);
  mIndex := TSymbolIndex.Create;
  // Ohne Verwendungen passt die Unit ins Budget: Es wird nur ausgelagert, nicht verdichtet.
  mIndex.SetBudget(TIndexMemory.UnitBytes(TIndexMemory.WithoutUsages(U)) + 16);
  mIndex.AddUnit(U);
  Assert.AreEqual(1, mIndex.OffloadedCount);
  Assert.AreEqual(0, mIndex.CompactCount);
  Assert.IsTrue(mIndex.FindFile(cKundeFile, mFound));
  Assert.IsTrue(mFound.UsagesOffloaded);
  Assert.IsFalse(mFound.Compact);
  Assert.AreEqual<NativeInt>(Length(U.Symbols), Length(mFound.Symbols));
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
  FFiles.Put(cKundeFile, cUnitKunde, 1);
end;

procedure TIndexServiceCacheTests.TearDown;
begin
  FFiles := nil;
  FFilesRef := nil;
end;

function TIndexServiceCacheTests.Start(const AIndex: ISymbolIndex; const AFiles: TArray<string>;
  AUsages: Boolean): TIndexService;
var
  mRequest: TIndexRequest;
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
  mRequest := Default(TIndexRequest);
  mRequest.Files := AFiles;
  mRequest.ResolveUnit := ResolveNothing;
  mRequest.CacheFile := cCacheFile;
  mRequest.Usages := AUsages;
  Result.Start(mRequest);
  Result.WaitFor;
end;

procedure TIndexServiceCacheTests.Build(const AIndex: ISymbolIndex; const AFiles: TArray<string>; AUsages: Boolean);
begin
  Start(AIndex, AFiles, AUsages).Free;
end;

procedure TIndexServiceCacheTests.DamagedCacheIsRebuiltSilently;
var
  mData: TBytes;
  mReason: string;
  mIndex: ISymbolIndex;
  mFound: TUnitIndex;
begin
  Build(TSymbolIndex.Create, [cKundeFile], True);
  Assert.IsTrue(FFiles.ReadBytes(cCacheFile, mData));
  mData[High(mData)] := mData[High(mData)] xor $FF;
  FFiles.WriteBytes(cCacheFile, mData);
  mIndex := TSymbolIndex.Create;
  Build(mIndex, [cKundeFile], True);
  // Verworfen mit Grund fürs Log, neu gelesen, ohne Fehler.
  Assert.AreEqual('Prüfsumme stimmt nicht', FRejected);
  Assert.AreEqual(1, FResult.Parsed);
  Assert.AreEqual(0, FResult.FromCache);
  Assert.IsTrue(mIndex.FindUnit('Kunde', mFound));
  // Der neu geschriebene Cache ist wieder gültig.
  Assert.IsTrue(FFiles.ReadBytes(cCacheFile, mData));
  Assert.AreEqual<NativeInt>(1, Length(TIndexCache.ReadEntries(mData, mReason)));
  Assert.AreEqual('', mReason);
end;

procedure TIndexServiceCacheTests.OffloadedUsagesComeBackFromCache;
var
  mFirst, mIndex: ISymbolIndex;
  mService: TIndexService;
  mFound: TUnitIndex;
  mUsages: TArray<TIndexUsage>;
  mUsage: TIndexUsage;
begin
  mFirst := TSymbolIndex.Create;
  Build(mFirst, [cKundeFile], True);
  Assert.IsTrue(mFirst.FindFile(cKundeFile, mFound));
  mIndex := TSymbolIndex.Create;
  mIndex.SetBudget(TIndexMemory.UnitBytes(TIndexMemory.WithoutUsages(mFound)) + 16);
  mService := Start(mIndex, [cKundeFile], True);
  try
    Assert.AreEqual(1, FResult.FromCache);
    Assert.IsTrue(mIndex.FindFile(cKundeFile, mFound));
    Assert.IsTrue(mFound.UsagesOffloaded);
    Assert.AreEqual(1, mIndex.OffloadedCount);
    // Die Quelle ist weg: Die Verwendungen kommen aus dem Cache.
    FFiles.Delete(cKundeFile);
    Assert.IsTrue(mService.UsagesOf(cKundeFile, mUsages));
    Assert.IsTrue(FindUsage(mUsages, 'Zaehler', mUsage));
    Assert.AreEqual(19, mUsage.Positions[0].Line);
  finally
    mService.Free;
  end;
end;

procedure TIndexServiceCacheTests.SwitchingUsagesOnRereadsCachedUnits;
var
  mIndex: ISymbolIndex;
  mFound: TUnitIndex;
begin
  Build(TSymbolIndex.Create, [cKundeFile], False);
  // Cache ohne Verwendungen passt nicht, wenn sie jetzt gewünscht sind.
  mIndex := TSymbolIndex.Create;
  Build(mIndex, [cKundeFile], True);
  Assert.AreEqual(1, FResult.Parsed);
  Assert.AreEqual(0, FResult.FromCache);
  Assert.IsTrue(mIndex.FindFile(cKundeFile, mFound));
  Assert.IsTrue(mFound.UsagesIndexed);
  mIndex := TSymbolIndex.Create;
  Build(mIndex, [cKundeFile], True);
  Assert.AreEqual(1, FResult.FromCache);
  // Abgeschaltet: der Cache passt weiter, die Verwendungen bleiben draußen.
  mIndex := TSymbolIndex.Create;
  Build(mIndex, [cKundeFile], False);
  Assert.AreEqual(1, FResult.FromCache);
  Assert.IsTrue(mIndex.FindFile(cKundeFile, mFound));
  Assert.IsFalse(mFound.UsagesIndexed);
  Assert.AreEqual<NativeInt>(0, Length(mFound.Usages));
end;

procedure TIndexServiceCacheTests.ReopensThousandUnitsFromCacheWithinThreeSeconds;
const
  cUnitCount = 1000;
var
  mFiles: TArray<string>;
  mNumber: Integer;
  mIndex: ISymbolIndex;
  mWatch: TStopwatch;
begin
  SetLength(mFiles, cUnitCount);
  for mNumber := 1 to cUnitCount do
  begin
    mFiles[mNumber - 1] := Format('C:\P\U%d.pas', [mNumber]);
    FFiles.Put(mFiles[mNumber - 1], GenerateUnit(mNumber), 1);
  end;
  Build(TSymbolIndex.Create, mFiles, True);
  Assert.AreEqual(cUnitCount, FResult.Parsed);
  mIndex := TSymbolIndex.Create;
  mWatch := TStopwatch.StartNew;
  Build(mIndex, mFiles, True);
  mWatch.Stop;
  Assert.AreEqual(cUnitCount, FResult.FromCache);
  Assert.AreEqual(cUnitCount, mIndex.UnitCount);
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 3000, Format('%d ms', [mWatch.ElapsedMilliseconds]));
end;

procedure TIndexServiceCacheTests.SavedDeclarationIsAvailableWithinOneSecond;
var
  mIndex: ISymbolIndex;
  mService: TIndexService;
  mWatch: TStopwatch;
begin
  mIndex := TSymbolIndex.Create;
  mService := Start(mIndex, [cKundeFile], True);
  try
    Assert.AreEqual(0, Integer(Length(mIndex.FindSymbols('NeueFunktion'))));
    FFiles.Put(cKundeFile, StringReplace(cUnitKunde, 'var'#13#10, 'procedure NeueFunktion;'#13#10'var'#13#10, []), 2);
    mWatch := TStopwatch.StartNew;
    Assert.AreEqual(1, mService.ApplyChanges([TFileChange.Create(cKundeFile, TFileChangeKind.Changed)]));
    mWatch.Stop;
    Assert.AreEqual(1, Integer(Length(mIndex.FindSymbols('NeueFunktion'))));
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 1000, Format('%d ms', [mWatch.ElapsedMilliseconds]));
  finally
    mService.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexContentTests);
  TDUnitX.RegisterTestFixture(TIndexServiceCacheTests);

end.
