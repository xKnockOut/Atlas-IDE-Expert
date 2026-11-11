unit Atlas.Common.Index.Builder.Tests;

// Tests des Index-Aufbaus (TIndexBuilder, TIndexService) und der gemeinsamen Caches einer Projektgruppe.
// Dateisystem im Speicher und Unit A aus Atlas.Common.Index.Tests.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Tests;

type
  [TestFixture]
  TIndexBuilderTests = class
  private
    FFiles: TMemoryIndexFileSystem;
    FFileSystem: IIndexFileSystem;
    FIndex: ISymbolIndex;
    function Resolve(const AUnitName: string): string;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure IndexesProjectAndReferencedUnits;
    [Test]
    procedure ReusesCacheWithoutReading;
    [Test]
    procedure ReparsesChangedFiles;
    [Test]
    procedure ReportsProgressAndCancels;
    [Test]
    procedure EnsureUnitIndexesOnDemand;
    [Test]
    procedure AppliesExternalChanges;
    [Test]
    procedure AppliesUnsavedTextOfKnownUnits;
    [Test]
    procedure ChangedIncludeReindexesUnit;
    [Test]
    procedure CachedIncludeUnitReusedUntilIncludeChanges;
    [Test]
    procedure DecodesOnlyUsedCacheEntries;
    [Test]
    procedure CompactLibraryCacheReusedUnderBudget;
    [Test]
    procedure ReleaseCacheDropsEntries;
    [Test]
    procedure ServiceBuildsInBackgroundAndWritesCache;
    [Test]
    procedure EnsureUnitDoesNotWaitForOtherRequests;
    /// <summary>#1236: Fragen mehrere Threads dieselbe Unit gleichzeitig an, liest und parst sie nur einer.</summary>
    [Test]
    procedure ConcurrentEnsureUnitParsesOnce;
    [Test]
    procedure ReadOnlyServiceWaitsForOtherWriter;
    [Test]
    procedure ServiceSharesLibraryCache;
    /// <summary>Ergänzt ein anderer Schreiber den Bibliotheks-Cache, nachdem dieser Aufbau ihn gelesen hat,
    /// bleiben dessen Units erhalten.</summary>
    [Test]
    procedure ServiceKeepsLibraryUnitsOfOtherWriters;
    /// <summary>Hält ein anderer die Schreibsperre des Bibliotheks-Caches, wartet der Aufbau darauf.</summary>
    [Test]
    procedure ServiceWaitsForLibraryWriteLock;
    /// <summary>Ein nicht geschriebener Cache wird gemeldet statt verschluckt.</summary>
    [Test]
    procedure ServiceReportsUnwrittenCache;
    /// <summary>Rückmeldung 22.10.2026 (3 GB bei acht Projekten): Projekte, die zusammen aufbauen, schreiben
    /// den gemeinsamen Bibliotheks-Cache nur einmal, statt jedes für sich gegen seinen Startstand.</summary>
    [Test]
    [IgnoreMemoryLeaks]
    procedure ConcurrentServicesWriteLibraryCacheOnce;
    /// <summary>Diagnoselog nennt, warum Units nicht aus dem Cache kamen (Rückmeldung 22.10.2026).</summary>
    [Test]
    procedure CountsWhyUnitsWereParsed;
    [Test]
    procedure ReadOnlyServiceStopsWaitingAfterLimit;
    [Test]
    procedure IndexesSearchAndLibraryStages;
    [Test]
    procedure ReportsProjectStageBeforeSearchPaths;
    [Test]
    procedure SkipsUnitIndexedUnderOtherName;
    [Test]
    procedure ReadsInstallationUnitsWithoutProjectDefines;
    [Test]
    procedure ServiceWritesCacheAfterProjectStage;
    /// <summary>Fehler im Aufbau gehen genau einmal an OnError.</summary>
    [Test]
    procedure ServiceReportsCacheWriteFailureOnce;
    [Test]
    procedure ServiceReportsCacheReadFailure;
    [Test]
    procedure ServiceSurvivesFailingErrorHandler;
    /// <summary>#874: Ein neuer Start wartet nicht auf den alten Aufbau; der neue beginnt erst nach dessen
    /// Ende, Prepare läuft dann im Index-Thread.</summary>
    [Test]
    procedure RestartDoesNotWaitForRunningBuild;
  end;

  /// <summary>Speicher bei Projektgruppen (Rückmeldung 01.11.2026): gemeinsamer Suchpfad-Cache und keine doppelte
  /// Übernahme. Eigene Klasse neben TIndexBuilderTests, deren Dateien sie über PutBuilderFiles teilt.</summary>
  [TestFixture]
  TIndexGroupCacheTests = class
  private
    FFileSystem: IIndexFileSystem;
    FIndex: ISymbolIndex;
    function Resolve(const AUnitName: string): string;
    /// <summary>Neu gelesene Units eines Aufbaus von P, A und F mit ADefines.</summary>
    function Parsed(const ADefines: TArray<string>): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Speicher (Rückmeldung 01.11.2026): Suchpfad-Units stehen in einem gemeinsamen Cache statt im Cache
    /// jedes Projekts; ein zweites Projekt mit denselben Suchpfaden liest sie von dort.</summary>
    [Test]
    procedure ServiceSharesSearchPathCache;
    /// <summary>Speicher (Rückmeldung 01.11.2026): Ein weiteres Projekt der Gruppe übernimmt Units, die mit gleichem
    /// Stand und gleichen Defines schon im Index stehen, nicht noch einmal; mit anderen Defines liest es neu.</summary>
    [Test]
    procedure BuilderSkipsUnitsAlreadyIndexed;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Memory,
  Atlas.Common.Index.Cache,
  Atlas.Common.Rationale.Contract,
  Atlas.Common.Index.Builder,
  Atlas.Common.Index.Service,
  Atlas.Common.Index.Scheduler,
  Atlas.Common.Index.ProjectFiles;

/// <summary>Projekt P mit A und die Bibliothek B bis F der Index-Aufbau-Tests.</summary>
procedure PutBuilderFiles(AFiles: TMemoryIndexFileSystem);
begin
  AFiles.Put('C:\P\P.dpr', 'program P;'#10'uses A in ''A.pas'';'#10'begin end.', 1);
  AFiles.Put('C:\P\A.pas', UnitA, 1);
  AFiles.Put('C:\Lib\B.pas', 'unit B;'#10'interface'#10'uses D;'#10'type TB = class end;'#10'implementation'#10'uses E;'#10'end.', 1);
  AFiles.Put('C:\Lib\C.pas', 'unit C;'#10'interface'#10'implementation'#10'end.', 1);
  AFiles.Put('C:\Lib\D.pas', 'unit D;'#10'interface'#10'implementation'#10'end.', 1);
  AFiles.Put('C:\Lib\E.pas', 'unit E;'#10'interface'#10'implementation'#10'end.', 1);
  AFiles.Put('C:\Lib\F.pas', 'unit F;'#10'interface'#10'type TF = class end;'#10'implementation'#10'end.', 1);
end;

/// <summary>Units der Tests liegen unter C:\Lib; System.SysUtils gibt es nicht.</summary>
function ResolveLibraryUnit(const AUnitName: string): string;
begin
  if SameText(AUnitName, 'System.SysUtils') then
  begin
    Result := '';
  end
  else
  begin
    Result := 'C:\Lib\' + AUnitName + '.pas';
  end;
end;

{ TIndexBuilderTests }

procedure TIndexBuilderTests.WarmUpFirstUse;
begin
  Setup;
  try
    ServiceSharesLibraryCache;
  finally
    TearDown;
  end;
end;

procedure TIndexBuilderTests.Setup;
begin
  FFiles := TMemoryIndexFileSystem.Create;
  FFileSystem := FFiles;
  PutBuilderFiles(FFiles);
  FIndex := TSymbolIndex.Create;
end;

procedure TIndexBuilderTests.TearDown;
begin
  FIndex := nil;
  FFileSystem := nil;
end;

function TIndexBuilderTests.Resolve(const AUnitName: string): string;
begin
  Result := ResolveLibraryUnit(AUnitName);
end;

procedure TIndexBuilderTests.IndexesProjectAndReferencedUnits;
var
  Builder: TIndexBuilder;
  BuildResult: TIndexBuildResult;
  U: TUnitIndex;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    BuildResult := Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  // P, A aus dem Projekt; B und C aus den uses von A; D aus dem interface von B.
  // E steht nur im implementation-Teil von B und bleibt draußen, F wird nie referenziert.
  Assert.AreEqual(5, BuildResult.Parsed);
  Assert.IsTrue(FIndex.FindUnit('B', U));
  Assert.IsTrue(FIndex.FindUnit('C', U));
  Assert.IsTrue(FIndex.FindUnit('D', U));
  Assert.IsFalse(FIndex.FindUnit('E', U));
  Assert.IsFalse(FIndex.FindUnit('F', U));
end;

procedure TIndexBuilderTests.IndexesSearchAndLibraryStages;
var
  Builder: TIndexBuilder;
  BuildResult: TIndexBuildResult;
  U: TUnitIndex;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    // F nur über den Suchpfad, E nur über den Bibliothekspfad; B kam schon über uses und wird nicht neu gelesen.
    BuildResult := Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], ['C:\Lib\F.pas'], ['C:\Lib\E.pas', 'C:\Lib\B.pas'],
      nil, nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(7, BuildResult.Parsed);
  Assert.IsTrue(FIndex.FindUnit('F', U));
  Assert.IsFalse(U.Library_, 'Suchpfad-Units gehören zum Projekt');
  Assert.IsTrue(FIndex.FindUnit('E', U));
  Assert.IsTrue(U.Library_, 'Bibliotheks-Units sind Bibliothek');
end;

procedure TIndexBuilderTests.ReportsProjectStageBeforeSearchPaths;
var
  Builder: TIndexBuilder;
  StageParsed: Integer;
  HadSearchUnit: Boolean;
  U: TUnitIndex;
begin
  StageParsed := -1;
  HadSearchUnit := True;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.OnProjectDone :=
      procedure(const APartial: TIndexBuildResult)
      begin
        StageParsed := APartial.Parsed;
        HadSearchUnit := FIndex.FindUnit('F', U);
      end;
    Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], ['C:\Lib\F.pas'], ['C:\Lib\E.pas'], nil, nil, nil);
  finally
    Builder.Free;
  end;
  // P, A, B, C, D: Projektdateien und über uses erreichbare Units (#647).
  Assert.AreEqual(5, StageParsed);
  Assert.IsFalse(HadSearchUnit, 'Suchpfade kommen erst nach der Projektstufe');
end;

procedure TIndexBuilderTests.SkipsUnitIndexedUnderOtherName;
var
  Builder: TIndexBuilder;
  BuildResult: TIndexBuildResult;
  ResolveScoped: TUnitFileResolver;
begin
  // "uses Forms" findet Vcl.Forms; im Index steht sie unter "Vcl.Forms" (#647).
  FFiles.Put('C:\Lib\Vcl.Forms.pas', 'unit Vcl.Forms;'#10'interface'#10'implementation'#10'end.', 1);
  FFiles.Put('C:\Q\Q1.pas', 'unit Q1;'#10'interface'#10'uses Forms;'#10'implementation'#10'end.', 1);
  FFiles.Put('C:\Q\Q2.pas', 'unit Q2;'#10'interface'#10'uses Forms;'#10'implementation'#10'end.', 1);
  ResolveScoped :=
    function(const AUnitName: string): string
    begin
      if SameText(AUnitName, 'Forms') then
      begin
        Result := 'C:\Lib\Vcl.Forms.pas';
      end
      else
      begin
        Result := '';
      end;
    end;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, ResolveScoped);
  try
    BuildResult := Builder.Build(['C:\Q\Q1.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(2, BuildResult.Parsed);
  // Zweites Projekt mit demselben Index: Vcl.Forms ist schon da.
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, ResolveScoped);
  try
    BuildResult := Builder.Build(['C:\Q\Q2.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(1, BuildResult.Parsed, 'nur Q2');
end;

procedure TIndexBuilderTests.ReadsInstallationUnitsWithoutProjectDefines;
const
  Source = 'interface'#10'{$IFDEF APP}procedure NurApp;{$ENDIF}'#10'implementation'#10'end.';
var
  Builder: TIndexBuilder;
  ResolveScoped: TUnitFileResolver;
begin
  // RTL/VCL/FMX kommen als fertige DCUs: Projekt-Defines wirken dort nicht (#647).
  FFiles.Put('C:\BDS\source\rtl\RtlUnit.pas', 'unit RtlUnit;'#10 + Source, 1);
  FFiles.Put('C:\Firma\FirmaUnit.pas', 'unit FirmaUnit;'#10 + Source, 1);
  FFiles.Put('C:\P\Haupt.pas', 'unit Haupt;'#10'interface'#10'uses RtlUnit, FirmaUnit;'#10'implementation'#10'end.', 1);
  ResolveScoped :=
    function(const AUnitName: string): string
    begin
      if SameText(AUnitName, 'RtlUnit') then
      begin
        Result := 'C:\BDS\source\rtl\RtlUnit.pas';
      end
      else if SameText(AUnitName, 'FirmaUnit') then
      begin
        Result := 'C:\Firma\FirmaUnit.pas';
      end
      else
      begin
        Result := '';
      end;
    end;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, ['APP', 'MSWINDOWS'], ResolveScoped);
  try
    Builder.LibraryRoots := ['C:\BDS'];
    Builder.LibraryDefines := ['MSWINDOWS'];
    Builder.Build(['C:\P\Haupt.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('NurApp')), 'nur FirmaUnit');
  Assert.AreEqual('FirmaUnit', FIndex.FindSymbols('NurApp')[0].UnitName);
  Assert.IsTrue(TIndexFileDefines.IsUnder('c:\bds\x.pas', ['C:\BDS\']));
  Assert.IsFalse(TIndexFileDefines.IsUnder('C:\BDS2\x.pas', ['C:\BDS']));
end;

procedure TIndexBuilderTests.ServiceWritesCacheAfterProjectStage;
var
  Service: TIndexService;
  Request: TIndexRequest;
  StageUnits: NativeInt;
  Data: TBytes;
begin
  StageUnits := -1;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Service.OnProjectReady :=
      procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
      var
        StageData: TBytes;
      begin
        // In einer Projektgruppe endet der ganze Aufbau erst spät; der Cache muss vorher stehen (#647).
        if FFileSystem.ReadBytes('C:\Cache\index.json', StageData) then
        begin
          StageUnits := Length(TIndexCache.Deserialize(StageData));
        end;
      end;
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.SearchFiles := ['C:\Lib\F.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\index.json';
    Service.Start(Request);
    Service.WaitFor;
  finally
    Service.Free;
  end;
  Assert.AreEqual<NativeInt>(5, StageUnits);
  Assert.IsTrue(FFileSystem.ReadBytes('C:\Cache\index.json', Data));
  Assert.AreEqual<NativeInt>(6, Length(TIndexCache.Deserialize(Data)), 'am Ende mit Suchpfad-Unit');
end;

procedure TIndexBuilderTests.ReusesCacheWithoutReading;
var
  Builder: TIndexBuilder;
  Cache: TArray<TUnitIndex>;
  BuildResult: TIndexBuildResult;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Cache := TIndexCache.Deserialize(TIndexCache.Serialize(FIndex.Units));
  FIndex := TSymbolIndex.Create;
  FFiles.Reads := 0;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.UseCache(Cache);
    BuildResult := Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(0, BuildResult.Parsed);
  Assert.AreEqual(5, BuildResult.FromCache);
  Assert.AreEqual(0, FFiles.Reads);
  Assert.AreEqual(5, FIndex.UnitCount);
end;

procedure TIndexBuilderTests.ReparsesChangedFiles;
var
  Builder: TIndexBuilder;
  Cache: TArray<TUnitIndex>;
  BuildResult: TIndexBuildResult;
  Found: TArray<TSymbolLocation>;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.Build(['C:\Lib\C.pas', 'C:\Lib\D.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Cache := FIndex.Units;
  // C: neuer Zeitstempel, gleicher Inhalt → aus dem Cache. D: neuer Inhalt → neu einlesen.
  FFiles.Put('C:\Lib\C.pas', 'unit C;'#10'interface'#10'implementation'#10'end.', 2);
  FFiles.Put('C:\Lib\D.pas', 'unit D;'#10'interface'#10'type TNeu = class end;'#10'implementation'#10'end.', 2);
  FIndex := TSymbolIndex.Create;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.UseCache(Cache);
    BuildResult := Builder.Build(['C:\Lib\C.pas', 'C:\Lib\D.pas', 'C:\Lib\Fehlt.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(1, BuildResult.Parsed);
  Assert.AreEqual(1, BuildResult.FromCache);
  Assert.AreEqual(1, BuildResult.Missing);
  Found := FIndex.FindSymbols('TNeu');
  Assert.AreEqual<NativeInt>(1, Length(Found));
end;

procedure TIndexBuilderTests.ReportsProgressAndCancels;
var
  Builder: TIndexBuilder;
  Events: TList<TIndexProgressKind>;
  BuildResult: TIndexBuildResult;
begin
  Events := TList<TIndexProgressKind>.Create;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    BuildResult := Builder.Build(['C:\P\A.pas', 'C:\Lib\C.pas'],
      procedure(AKind: TIndexProgressKind; const AMessage: string; APercent: Integer)
      begin
        Events.Add(AKind);
      end,
      function: Boolean
      begin
        // Nach der ersten Datei abbrechen.
        Result := FIndex.UnitCount >= 1;
      end);
    Assert.IsTrue(BuildResult.Cancelled);
    Assert.AreEqual(1, FIndex.UnitCount);
    Assert.IsTrue(Events.First = TIndexProgressKind.Started);
    Assert.IsTrue(Events.Last = TIndexProgressKind.Finished);
  finally
    Builder.Free;
    Events.Free;
  end;
end;

procedure TIndexBuilderTests.EnsureUnitIndexesOnDemand;
var
  Builder: TIndexBuilder;
  U: TUnitIndex;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Assert.IsTrue(Builder.EnsureUnit('F'));
    Assert.IsTrue(FIndex.FindUnit('F', U));
    Assert.IsFalse(Builder.EnsureUnit('GibtEsNicht'));
    Assert.IsFalse(Builder.EnsureUnit('System.SysUtils'));
  finally
    Builder.Free;
  end;
end;

procedure TIndexBuilderTests.AppliesUnsavedTextOfKnownUnits;
var
  Builder: TIndexBuilder;
  U: TUnitIndex;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.Build(['C:\Lib\D.pas'], nil, nil);
    // Getippt, nicht gespeichert: neue Klasse sofort im Index, Datei unverändert.
    Assert.IsTrue(Builder.ApplyText('C:\Lib\D.pas',
      'unit D;'#10'interface'#10'type TGetippt = class end;'#10'implementation'#10'end.'));
    Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('TGetippt')));
    Assert.IsTrue(FIndex.FindUnit('D', U));
    // Gleicher Text: nichts zu tun; unbekannte Datei: nichts.
    Assert.IsFalse(Builder.ApplyText('C:\Lib\D.pas',
      'unit D;'#10'interface'#10'type TGetippt = class end;'#10'implementation'#10'end.'));
    Assert.IsFalse(Builder.ApplyText('C:\Lib\Neu.pas', 'unit Neu;'#10'interface'#10'implementation'#10'end.'));
    // Schließen ohne Speichern: der Stand der Platte gilt wieder.
    Builder.ApplyChanges([TFileChange.Create('C:\Lib\D.pas', TFileChangeKind.Changed)]);
    Assert.AreEqual<NativeInt>(0, Length(FIndex.FindSymbols('TGetippt')));
  finally
    Builder.Free;
  end;
end;

procedure TIndexBuilderTests.AppliesExternalChanges;
var
  Builder: TIndexBuilder;
  U: TUnitIndex;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.Build(['C:\Lib\C.pas', 'C:\Lib\D.pas'], nil, nil);
    Assert.IsFalse(Builder.EnsureUnit('G'));
    // D geändert, C gelöscht, G neu angelegt, F unbekannt und unverändert.
    FFiles.Put('C:\Lib\D.pas', 'unit D;'#10'interface'#10'type TNeu = class end;'#10'implementation'#10'end.', 2);
    FFiles.Delete('C:\Lib\C.pas');
    FFiles.Put('C:\Lib\G.pas', 'unit G;'#10'interface'#10'implementation'#10'end.', 2);
    Assert.AreEqual(2, Builder.ApplyChanges([TFileChange.Create('C:\Lib\D.pas', TFileChangeKind.Changed),
      TFileChange.Create('C:\Lib\C.pas', TFileChangeKind.Deleted),
      TFileChange.Create('C:\Lib\G.pas', TFileChangeKind.Created),
      TFileChange.Create('C:\Lib\F.pas', TFileChangeKind.Changed)]));
    Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('TNeu')));
    Assert.IsFalse(FIndex.FindUnit('C', U));
    Assert.IsFalse(FIndex.FindUnit('F', U));
    // Neue Dateien kommen erst bei Bedarf in den Index, auch wenn die Unit vorher fehlte.
    Assert.IsFalse(FIndex.FindUnit('G', U));
    Assert.IsTrue(Builder.EnsureUnit('G'));
  finally
    Builder.Free;
  end;
end;

procedure TIndexBuilderTests.ChangedIncludeReindexesUnit;
const
  UnitText = 'unit H;'#10'interface'#10'{$I C:\Inc\Schalter.inc}'#10 +
    '{$IFDEF NEU}type TMitNeu = class end;{$ELSE}type TOhneNeu = class end;{$ENDIF}'#10'implementation'#10'end.';
var
  Builder: TIndexBuilder;
  U: TUnitIndex;
begin
  // #264: $DEFINE aus der .inc wirkt; Änderung an der .inc liest H neu ein.
  FFiles.Put('C:\Inc\Schalter.inc', '{$DEFINE NEU}', 1);
  FFiles.Put('C:\Lib\H.pas', UnitText, 1);
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.Build(['C:\Lib\H.pas'], nil, nil);
    Assert.IsTrue(FIndex.FindUnit('H', U));
    Assert.AreEqual<NativeInt>(1, Length(U.Includes));
    Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('TMitNeu')));
    FFiles.Put('C:\Inc\Schalter.inc', '', 2);
    Assert.AreEqual(1, Builder.ApplyChanges([TFileChange.Create('C:\Inc\Schalter.inc', TFileChangeKind.Changed)]));
    Assert.AreEqual<NativeInt>(0, Length(FIndex.FindSymbols('TMitNeu')));
    Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('TOhneNeu')));
  finally
    Builder.Free;
  end;
end;

procedure TIndexBuilderTests.CachedIncludeUnitReusedUntilIncludeChanges;
const
  UnitText = 'unit H;'#10'interface'#10'{$I C:\Inc\Schalter.inc}'#10 +
    '{$IFDEF NEU}type TMitNeu = class end;{$ENDIF}'#10'implementation'#10'end.';
var
  Builder: TIndexBuilder;
  Cache: TArray<TUnitIndex>;
  BuildResult: TIndexBuildResult;
begin
  // #617: Units mit Includes kommen aus dem Cache, solange keine Include-Datei sich ändert.
  FFiles.Put('C:\Inc\Schalter.inc', '{$DEFINE NEU}', 1);
  FFiles.Put('C:\Lib\H.pas', UnitText, 1);
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.Build(['C:\Lib\H.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Cache := TIndexCache.Deserialize(TIndexCache.Serialize(FIndex.Units));
  FIndex := TSymbolIndex.Create;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.UseCache(Cache);
    BuildResult := Builder.Build(['C:\Lib\H.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(0, BuildResult.Parsed);
  Assert.AreEqual(1, BuildResult.FromCache);
  FFiles.Put('C:\Inc\Schalter.inc', '', 2);
  FIndex := TSymbolIndex.Create;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.UseCache(Cache);
    BuildResult := Builder.Build(['C:\Lib\H.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(1, BuildResult.Parsed);
  Assert.AreEqual<NativeInt>(0, Length(FIndex.FindSymbols('TMitNeu')));
end;

procedure TIndexBuilderTests.CompactLibraryCacheReusedUnderBudget;
const
  UnitText = 'unit K;'#10'interface'#10'type TK = class end;'#10'implementation'#10 +
    'procedure Versteckt; begin end;'#10'end.';
var
  Builder: TIndexBuilder;
  Cache: TArray<TUnitIndex>;
  BuildResult: TIndexBuildResult;
begin
  // Diagnoselog 15.10.2026: Bei knappem Budget stehen Bibliotheken kompakt im Cache. Sie werden
  // wiederverwendet, solange ein Budget gilt; ohne Budget braucht es alle Symbole.
  FFiles.Put('C:\Lib\K.pas', UnitText, 1);
  FIndex.SetBudget(1);
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.Build(nil, nil, ['C:\Lib\K.pas'], nil, nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(1, FIndex.CompactCount);
  Cache := TIndexCache.Deserialize(TIndexCache.Serialize(FIndex.Units));
  Assert.IsTrue(Cache[0].Compact);
  FIndex := TSymbolIndex.Create;
  FIndex.SetBudget(1);
  FFiles.Reads := 0;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.UseCache(Cache);
    BuildResult := Builder.Build(nil, nil, ['C:\Lib\K.pas'], nil, nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(0, BuildResult.Parsed);
  Assert.AreEqual(1, BuildResult.FromCache);
  Assert.AreEqual(0, FFiles.Reads);
  FIndex := TSymbolIndex.Create;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.UseCache(Cache);
    BuildResult := Builder.Build(nil, nil, ['C:\Lib\K.pas'], nil, nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(1, BuildResult.Parsed, 'ohne Budget neu einlesen');
  Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('Versteckt')));
end;

procedure TIndexBuilderTests.ReleaseCacheDropsEntries;
var
  Builder: TIndexBuilder;
  Cache: TArray<TUnitIndex>;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.Build(['C:\Lib\C.pas', 'C:\Lib\D.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Cache := FIndex.Units;
  FIndex := TSymbolIndex.Create;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.UseCache(Cache);
    Assert.AreEqual(2, Builder.CachedCount);
    Builder.Build(['C:\Lib\C.pas', 'C:\Lib\D.pas'], nil, nil);
    Builder.ReleaseCache;
    Assert.AreEqual(0, Builder.CachedCount);
    // Später nachgeladene Units liest der Builder aus der Datei.
    Assert.IsTrue(Builder.EnsureUnit('C'));
  finally
    Builder.Free;
  end;
end;

procedure TIndexBuilderTests.DecodesOnlyUsedCacheEntries;
var
  Builder: TIndexBuilder;
  Data: TBytes;
  Entries: TArray<TIndexCacheEntry>;
  Entry: TIndexCacheEntry;
  BuildResult: TIndexBuildResult;
begin
  // #617: Der Builder liest nur die Köpfe und dekodiert die Symbole der Units, die er übernimmt.
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], nil, nil);
    Assert.IsTrue(Builder.EnsureUnit('F'));
  finally
    Builder.Free;
  end;
  Data := TIndexCache.Serialize(FIndex.Units);
  Entries := TIndexCache.ReadEntries(Data);
  Assert.AreEqual<NativeInt>(6, Length(Entries));
  // Den Symbolblock von F nach dem Lesen der Köpfe beschädigen (in der Datei fiele das schon an der
  // Prüfsumme auf, #492); die Einträge teilen sich die Daten.
  for Entry in Entries do
  begin
    if SameText(Entry.Header.UnitName, 'F') then
    begin
      Entry.Data[Entry.SymbolOffset] := $FF;
      Entry.Data[Entry.SymbolOffset + 1] := $7F;
    end;
  end;
  FIndex := TSymbolIndex.Create;
  FFiles.Reads := 0;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.UseCache(Entries);
    BuildResult := Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], nil, nil);
    Assert.AreEqual(0, BuildResult.Parsed);
    Assert.AreEqual(5, BuildResult.FromCache);
    Assert.AreEqual(0, FFiles.Reads);
    Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('TB')));
    // F wurde nie gebraucht; erst EnsureUnit stößt auf den beschädigten Block und liest die Datei.
    Assert.IsTrue(Builder.EnsureUnit('F'));
  finally
    Builder.Free;
  end;
  Assert.AreEqual(1, FFiles.Reads);
  Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('TF')));
end;

procedure TIndexBuilderTests.EnsureUnitDoesNotWaitForOtherRequests;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Entered, Release: TEvent;
  Other: TThread;
  Watch: TStopwatch;
begin
  // #617: Eine Anfrage, die gerade eine Unit sucht und parst, hält die anderen nicht auf.
  Entered := TEvent.Create(nil, True, False, '');
  Release := TEvent.Create(nil, True, False, '');
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit :=
      function(const AUnitName: string): string
      begin
        if SameText(AUnitName, 'Langsam') then
        begin
          Entered.SetEvent;
          Release.WaitFor(5000);
          Exit('');
        end;
        Result := Resolve(AUnitName);
      end;
    Service.Start(Request);
    Service.WaitFor;
    Other := TThread.CreateAnonymousThread(
      procedure
      begin
        Service.EnsureUnit('Langsam');
      end);
    Other.FreeOnTerminate := False;
    Other.Start;
    try
      Assert.AreEqual(TWaitResult.wrSignaled, Entered.WaitFor(5000));
      Watch := TStopwatch.StartNew;
      Assert.IsTrue(Service.EnsureUnit('F'));
      // Mit der alten globalen Sperre hätte F bis zur Freigabe (5 s) gewartet.
      Assert.IsTrue(Watch.ElapsedMilliseconds < 2000, 'F wartete auf Langsam');
    finally
      Release.SetEvent;
      Other.WaitFor;
      Other.Free;
    end;
  finally
    Service.Free;
    Release.Free;
    Entered.Free;
  end;
end;

procedure TIndexBuilderTests.ConcurrentEnsureUnitParsesOnce;
const
  cThreads = 4;
var
  Builder: TIndexBuilder;
  Threads: array[0..cThreads - 1] of TThread;
  Index: Integer;
  ReadsOfF, Found: Integer;
  U: TUnitIndex;
begin
  ReadsOfF := 0;
  Found := 0;
  FFiles.BeforeReadText :=
    procedure(AFileName: string)
    begin
      if SameText(ExtractFileName(AFileName), 'F.pas') then
      begin
        TInterlocked.Increment(ReadsOfF);
        // Lange genug, dass die übrigen Threads währenddessen ankommen.
        Sleep(200);
      end;
    end;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    for Index := 0 to cThreads - 1 do
    begin
      Threads[Index] := TThread.CreateAnonymousThread(
        procedure
        begin
          if Builder.EnsureUnit('F') then
          begin
            TInterlocked.Increment(Found);
          end;
        end);
      Threads[Index].FreeOnTerminate := False;
    end;
    for Index := 0 to cThreads - 1 do
    begin
      Threads[Index].Start;
    end;
    for Index := 0 to cThreads - 1 do
    begin
      Threads[Index].WaitFor;
      Threads[Index].Free;
    end;
  finally
    Builder.Free;
    FFiles.BeforeReadText := nil;
  end;
  Assert.AreEqual(1, ReadsOfF, 'F nur einmal gelesen');
  Assert.AreEqual(cThreads, Found, 'alle finden F');
  Assert.IsTrue(FIndex.FindUnit('F', U));
end;

procedure TIndexBuilderTests.RestartDoesNotWaitForRunningBuild;
var
  Service: TIndexService;
  First, Second: TIndexRequest;
  Entered, Release: TEvent;
  Order: TThreadList<string>;
  Watch: TStopwatch;
  Seen: TList<string>;
  Steps: string;
begin
  Entered := TEvent.Create(nil, True, False, '');
  Release := TEvent.Create(nil, True, False, '');
  Order := TThreadList<string>.Create;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    First := Default(TIndexRequest);
    First.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    First.ResolveUnit := Resolve;
    First.Prepare :=
      procedure
      begin
        Entered.SetEvent;
        // Ein langer Aufbau, z. B. ein großes Projekt beim ersten Start.
        Release.WaitFor(5000);
        Order.Add('erster');
      end;
    Second := First;
    Second.Prepare :=
      procedure
      begin
        Order.Add('zweiter');
      end;
    Service.Start(First);
    Assert.IsTrue(Entered.WaitFor(5000) = TWaitResult.wrSignaled, 'der erste Aufbau läuft');
    Watch := TStopwatch.StartNew;
    Service.Start(Second);
    Assert.IsTrue(Watch.ElapsedMilliseconds < 2000, 'Start wartet nicht auf den laufenden Aufbau');
    Seen := Order.LockList;
    try
      Assert.AreEqual(0, Integer(Seen.Count), 'der neue Aufbau beginnt nicht neben dem alten');
    finally
      Order.UnlockList;
    end;
    Release.SetEvent;
    Service.WaitFor;
    Seen := Order.LockList;
    try
      Steps := string.Join(',', Seen.ToArray);
    finally
      Order.UnlockList;
    end;
    Assert.AreEqual('erster,zweiter', Steps);
    Assert.AreEqual(5, Service.Index.UnitCount, 'der zweite Aufbau läuft vollständig');
  finally
    Service.Free;
    Order.Free;
    Release.Free;
    Entered.Free;
  end;
end;

procedure TIndexBuilderTests.ServiceBuildsInBackgroundAndWritesCache;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Finished: Boolean;
  Data: TBytes;
begin
  Finished := False;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Service.OnFinished :=
      procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
      begin
        Finished := True;
      end;
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\index.json';
    Service.Start(Request);
    Service.WaitFor;
    Assert.IsTrue(Finished);
    Assert.AreEqual(5, Service.Index.UnitCount);
    Assert.IsTrue(Service.EnsureUnit('F'));
  finally
    Service.Free;
  end;
  Assert.IsTrue(FFileSystem.ReadBytes('C:\Cache\index.json', Data));
  Assert.AreEqual<NativeInt>(5, Length(TIndexCache.Deserialize(Data)));
end;

procedure TIndexBuilderTests.ServiceReportsCacheWriteFailureOnce;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Errors, Finished: Integer;
begin
  Errors := 0;
  Finished := 0;
  FFiles.FailWrites := True;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Service.OnFinished :=
      procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
      begin
        Inc(Finished);
      end;
    Service.OnError :=
      procedure(const AError: Exception)
      begin
        Inc(Errors);
      end;
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\index.json';
    Service.Start(Request);
    Service.WaitFor;
    Assert.AreEqual(1, Errors);
    Assert.AreEqual(0, Finished);
  finally
    Service.Free;
  end;
end;

procedure TIndexBuilderTests.ServiceReportsCacheReadFailure;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Errors: Integer;
  ErrorClass: string;
begin
  Errors := 0;
  ErrorClass := '';
  FFiles.FailReads := True;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Service.OnError :=
      procedure(const AError: Exception)
      begin
        Inc(Errors);
        ErrorClass := AError.ClassName;
      end;
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\index.json';
    Service.Start(Request);
    Service.WaitFor;
    Assert.AreEqual(1, Errors);
    Assert.AreEqual('EInOutError', ErrorClass);
    // Der Builder wurde nie veröffentlicht (und nicht geleakt): EnsureUnit findet nichts.
    Assert.IsFalse(Service.EnsureUnit('X'));
  finally
    Service.Free;
  end;
end;

procedure TIndexBuilderTests.ServiceSurvivesFailingErrorHandler;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Finished: Boolean;
begin
  Finished := False;
  FFiles.FailWrites := True;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Service.OnError :=
      procedure(const AError: Exception)
      begin
        raise EInvalidOpException.Create('Meldung scheitert');
      end;
    Service.OnFinished :=
      procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
      begin
        Finished := True;
      end;
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\index.json';
    Service.Start(Request);
    Service.WaitFor;
    Assert.IsFalse(Finished);
    // Der Thread endete geordnet; ein neuer Lauf ohne Fehler läuft durch.
    FFiles.FailWrites := False;
    Service.Start(Request);
    Service.WaitFor;
    Assert.IsTrue(Finished);
  finally
    Service.Free;
  end;
end;

procedure TIndexBuilderTests.ServiceSharesLibraryCache;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Data: TBytes;
  FromCache: Integer;
  UnitIndex: TUnitIndex;
begin
  // Erstes Projekt: Projekt-Units und Bibliothek getrennt (#492).
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\projekt1.json';
    Request.LibraryCacheFile := 'C:\Cache\bibliothek.json';
    Service.Start(Request);
    Service.WaitFor;
  finally
    Service.Free;
  end;
  Assert.IsTrue(FFileSystem.ReadBytes('C:\Cache\projekt1.json', Data));
  for UnitIndex in TIndexCache.Deserialize(Data) do
  begin
    Assert.IsFalse(UnitIndex.Library_, 'keine Bibliothek im Projekt-Cache: ' + UnitIndex.FileName);
  end;
  Assert.IsTrue(FFileSystem.ReadBytes('C:\Cache\bibliothek.json', Data));
  Assert.AreEqual<NativeInt>(3, Length(TIndexCache.Deserialize(Data)));
  // Zweites Projekt mit eigenem Cache: die Bibliothek kommt aus dem gemeinsamen.
  FIndex := TSymbolIndex.Create;
  FromCache := -1;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Service.OnFinished :=
      procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
      begin
        FromCache := AResult.FromCache;
      end;
    Request.CacheFile := 'C:\Cache\projekt2.json';
    Service.Start(Request);
    Service.WaitFor;
  finally
    Service.Free;
  end;
  Assert.AreEqual(3, FromCache, 'nur die Projekt-Units neu eingelesen');
end;

/// <summary>Namen der Units im Cache AData, groß geschrieben und sortiert, mit Komma getrennt.</summary>
function CachedNames(const AData: TBytes): string;
var
  Names: TStringList;
  UnitIndex: TUnitIndex;
begin
  Names := TStringList.Create;
  try
    for UnitIndex in TIndexCache.Deserialize(AData) do
    begin
      Names.Add(UpperCase(ExtractFileName(UnitIndex.FileName)));
    end;
    Names.Sort;
    Result := Names.CommaText;
  finally
    Names.Free;
  end;
end;

{ TIndexGroupCacheTests }

procedure TIndexGroupCacheTests.Setup;
var
  mFiles: TMemoryIndexFileSystem;
begin
  mFiles := TMemoryIndexFileSystem.Create;
  FFileSystem := mFiles;
  PutBuilderFiles(mFiles);
  FIndex := TSymbolIndex.Create;
end;

procedure TIndexGroupCacheTests.TearDown;
begin
  FIndex := nil;
  FFileSystem := nil;
end;

function TIndexGroupCacheTests.Resolve(const AUnitName: string): string;
begin
  Result := ResolveLibraryUnit(AUnitName);
end;

procedure TIndexGroupCacheTests.ServiceSharesSearchPathCache;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Data: TBytes;
  FromCache: Integer;
begin
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.SearchFiles := ['C:\Lib\F.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\projekt1.json';
    Request.LibraryCacheFile := 'C:\Cache\bibliothek.json';
    Request.SearchCacheFile := 'C:\Cache\suchpfade.json';
    Service.Start(Request);
    Service.WaitFor;
  finally
    Service.Free;
  end;
  Assert.IsTrue(FFileSystem.ReadBytes('C:\Cache\projekt1.json', Data));
  Assert.AreEqual('A.PAS,P.DPR', CachedNames(Data), 'Suchpfad-Unit nicht im Projekt-Cache');
  Assert.IsTrue(FFileSystem.ReadBytes('C:\Cache\suchpfade.json', Data));
  Assert.AreEqual('F.PAS', CachedNames(Data));
  // Zweites Projekt mit denselben Suchpfaden: F kommt aus dem gemeinsamen Cache.
  FIndex := TSymbolIndex.Create;
  FromCache := -1;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Service.OnFinished :=
      procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
      begin
        FromCache := AResult.FromCache;
      end;
    Request.CacheFile := 'C:\Cache\projekt2.json';
    Service.Start(Request);
    Service.WaitFor;
  finally
    Service.Free;
  end;
  Assert.AreEqual(4, FromCache, 'Bibliothek und Suchpfad-Unit aus den gemeinsamen Caches');
  Assert.IsTrue(FFileSystem.ReadBytes('C:\Cache\projekt2.json', Data));
  Assert.AreEqual('A.PAS,P.DPR', CachedNames(Data));
end;

function TIndexGroupCacheTests.Parsed(const ADefines: TArray<string>): Integer;
var
  mBuilder: TIndexBuilder;
begin
  mBuilder := TIndexBuilder.Create(FIndex, FFileSystem, ADefines, Resolve);
  try
    Result := mBuilder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], ['C:\Lib\F.pas'], nil, nil, nil, nil).Parsed;
  finally
    mBuilder.Free;
  end;
end;

procedure TIndexGroupCacheTests.BuilderSkipsUnitsAlreadyIndexed;
begin
  Assert.IsTrue(Parsed(['WIN64']) > 0);
  // Der zweite Lauf findet über die implementation-uses der Bibliothek noch Units (E); danach ist alles da.
  Parsed(['WIN64']);
  Assert.AreEqual(0, Parsed(['WIN64']), 'gleiche Defines: nichts erneut übernehmen');
  // Projektdateien (P, A) mit anderen Defines neu. Suchpfad-Units (F) und über uses erreichte überspringt der
  // Aufbau wie bisher, sobald sie im Index stehen.
  Assert.AreEqual(2, Parsed(['WIN64', 'DEBUG']), 'andere Defines: Projektdateien neu einlesen');
end;

procedure TIndexBuilderTests.ServiceKeepsLibraryUnitsOfOtherWriters;
const
  LibraryCache = 'C:\Cache\bibliothek.json';
var
  Other: ISymbolIndex;
  Builder: TIndexBuilder;
  Foreign, Data: TBytes;
  Service: TIndexService;
  Request: TIndexRequest;
begin
  // Was ein anderer Prozess schreibt: F aus der Bibliothek, die dieses Projekt nicht braucht.
  Other := TSymbolIndex.Create;
  Builder := TIndexBuilder.Create(Other, FFileSystem, nil, Resolve);
  try
    Builder.Build(nil, nil, ['C:\Lib\F.pas'], nil, nil, nil);
  finally
    Builder.Free;
  end;
  Foreign := TIndexCache.Serialize(Other.Units);
  Other := nil;
  // Gleich nachdem dieser Aufbau den Cache (noch leer) gelesen hat, schreibt der andere.
  FFiles.AfterRead :=
    procedure(AFileName: string)
    begin
      if SameText(AFileName, LibraryCache) then
      begin
        FFiles.AfterRead := nil;
        FFiles.WriteBytes(LibraryCache, Foreign);
      end;
    end;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\projekt.json';
    Request.LibraryCacheFile := LibraryCache;
    Service.Start(Request);
    Service.WaitFor;
  finally
    Service.Free;
  end;
  FFiles.AfterRead := nil;
  Assert.IsTrue(FFileSystem.ReadBytes(LibraryCache, Data));
  // Vorher überschrieb der Aufbau den Stand des anderen: nur B, C, D.
  Assert.AreEqual('B.PAS,C.PAS,D.PAS,F.PAS', CachedNames(Data));
end;

procedure TIndexBuilderTests.ServiceWaitsForLibraryWriteLock;
const
  LibraryCache = 'C:\Cache\bibliothek.json';
var
  Locked: TEvent;
  Releaser: TThread;
  Service: TIndexService;
  Request: TIndexRequest;
  Data: TBytes;
  NotWritten: string;
  Files: IIndexFileSystem;
begin
  // Ein anderer schreibt gerade und gibt die Sperre nach kurzer Zeit frei. Die Sperre gehört allein dem Thread:
  // Delphi hält das Interface-Ergebnis von TryLockWrite sonst in einem Zwischenwert bis zum Ende der Methode.
  Files := FFileSystem;
  Locked := TEvent.Create;
  Releaser := TThread.CreateAnonymousThread(
    procedure
    var
      Held: IInterface;
    begin
      Held := Files.TryLockWrite(LibraryCache);
      Locked.SetEvent;
      TThread.Sleep(300);
      Held := nil;
    end);
  Releaser.FreeOnTerminate := False;
  Releaser.Start;
  Assert.IsTrue(Locked.WaitFor(5000) = wrSignaled, 'Sperre genommen');
  Assert.IsTrue(FFileSystem.TryLockWrite(LibraryCache) = nil, 'nur ein Schreiber');
  NotWritten := '';
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Service.OnCacheNotWritten :=
      procedure(const AFileName, AReason: string)
      begin
        NotWritten := AReason;
      end;
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\projekt.json';
    Request.LibraryCacheFile := LibraryCache;
    Service.Start(Request);
    Service.WaitFor;
  finally
    Service.Free;
    Releaser.WaitFor;
    Releaser.Free;
    Locked.Free;
  end;
  Assert.AreEqual('', NotWritten);
  Assert.IsTrue(FFileSystem.ReadBytes(LibraryCache, Data));
  Assert.AreEqual('B.PAS,C.PAS,D.PAS', CachedNames(Data));
end;

procedure TIndexBuilderTests.ServiceReportsUnwrittenCache;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Reported: TStringList;
begin
  FFiles.RefuseWrites := True;
  Reported := TStringList.Create;
  try
    Service := TIndexService.Create(FIndex, FFileSystem);
    try
      Service.OnCacheNotWritten :=
        procedure(const AFileName, AReason: string)
        begin
          TMonitor.Enter(Reported);
          try
            Reported.Add(AFileName + '=' + AReason);
          finally
            TMonitor.Exit(Reported);
          end;
        end;
      Request := Default(TIndexRequest);
      Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
      Request.ResolveUnit := Resolve;
      Request.CacheFile := 'C:\Cache\index.json';
      Service.Start(Request);
      Service.WaitFor;
    finally
      Service.Free;
    end;
    Assert.IsTrue(Reported.Count > 0, 'gemeldet');
    Assert.AreEqual('C:\Cache\index.json=simuliert', Reported[0]);
  finally
    Reported.Free;
  end;
end;

/// <summary>Startet R mit AFirst und Q mit ASecond auf denselben Bibliotheks-Cache.</summary>
procedure StartTwoProjects(AFirst, ASecond: TIndexService; const AResolve: TUnitFileResolver);
var
  mRequest: TIndexRequest;
begin
  mRequest := Default(TIndexRequest);
  mRequest.ResolveUnit := AResolve;
  mRequest.LibraryCacheFile := 'C:\Cache\bibliothek.json';
  mRequest.Files := ['C:\P\R.dpr'];
  mRequest.CacheFile := 'C:\Cache\r.json';
  AFirst.Start(mRequest);
  mRequest.Files := ['C:\Q\Q.dpr'];
  mRequest.CacheFile := 'C:\Cache\q.json';
  mRequest.Priority := 1;
  ASecond.Start(mRequest);
end;

/// <summary>Wartet, bis ACounter nicht mehr 0 ist, höchstens ATimeoutMs.</summary>
procedure WaitWhileZero(var ACounter: Integer; ATimeoutMs: Int64);
var
  mWatch: TStopwatch;
begin
  mWatch := TStopwatch.StartNew;
  while (TInterlocked.CompareExchange(ACounter, 0, 0) = 0) and (mWatch.ElapsedMilliseconds < ATimeoutMs) do
  begin
    TThread.Sleep(10);
  end;
end;

procedure TIndexBuilderTests.ConcurrentServicesWriteLibraryCacheOnce;
var
  First, Second: TIndexService;
  Gate: TEvent;
  Waiting, LibraryWrites: Integer;
  Counted: TIndexCacheWrittenEvent;
begin
  // Beide nutzen nur F: Nach dem ersten Schreiben gibt es nichts Neues mehr.
  FFiles.Put('C:\P\R.dpr', 'program R;'#10'uses F;'#10'begin end.', 1);
  FFiles.Put('C:\Q\Q.dpr', 'program Q;'#10'uses F;'#10'begin end.', 1);
  Waiting := 0;
  LibraryWrites := 0;
  Gate := TEvent.Create(nil, True, False, '');
  try
    // Das erste Schreiben wird aufgehalten, bis beide Aufbauten ihren Startstand gelesen haben.
    FFiles.BeforeWrite :=
      procedure
      begin
        TInterlocked.Increment(Waiting);
        Gate.WaitFor(10000);
      end;
    Counted :=
      procedure(ALibrary: Boolean; AUnits: Integer; ABytes, AElapsedMs: Int64)
      begin
        if ALibrary then
        begin
          TInterlocked.Increment(LibraryWrites);
        end;
      end;
    First := TIndexService.Create(FIndex, FFileSystem);
    Second := TIndexService.Create(FIndex, FFileSystem);
    try
      First.OnCacheWritten := Counted;
      Second.OnCacheWritten := Counted;
      StartTwoProjects(First, Second, Resolve);
      WaitWhileZero(Waiting, 5000);
      // Der zweite Aufbau hat dann längst gelesen und wartet auf das Schreiben.
      TThread.Sleep(300);
      Gate.SetEvent;
      First.WaitFor;
      Second.WaitFor;
    finally
      Second.Free;
      First.Free;
    end;
  finally
    FFiles.BeforeWrite := nil;
    Gate.Free;
  end;
  Assert.AreEqual(1, LibraryWrites, 'Bibliotheks-Cache nur einmal geschrieben');
end;

procedure TIndexBuilderTests.CountsWhyUnitsWereParsed;
var
  Builder: TIndexBuilder;
  Cache: TArray<TUnitIndex>;
  BuildResult: TIndexBuildResult;
  Position: Integer;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    BuildResult := Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas', 'C:\Lib\F.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(3, BuildResult.Misses[TIndexCacheMiss.NoEntry]);
  Cache := Copy(FIndex.Units);
  // Kompakte Projekt-Unit taugt nicht; geänderte Datei wird neu gelesen; F kommt aus dem Cache.
  for Position := 0 to High(Cache) do
  begin
    if SameText(Cache[Position].UnitName, 'P') then
    begin
      Cache[Position] := TIndexMemory.Compacted(Cache[Position]);
    end;
  end;
  FFiles.Put('C:\P\A.pas', UnitA + ' ', 2);
  FIndex := TSymbolIndex.Create;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.UseCache(Cache);
    BuildResult := Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas', 'C:\Lib\F.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(2, BuildResult.Parsed);
  Assert.AreEqual(1, BuildResult.FromCache);
  Assert.AreEqual(1, BuildResult.Misses[TIndexCacheMiss.Compact]);
  Assert.AreEqual(1, BuildResult.Misses[TIndexCacheMiss.Changed]);
  Assert.AreEqual(0, BuildResult.Misses[TIndexCacheMiss.NoEntry]);
  Cache := nil;
end;

procedure TIndexBuilderTests.ReadOnlyServiceWaitsForOtherWriter;
const
  CacheFile = 'C:\Cache\index.json';
var
  Service: TIndexService;
  Request: TIndexRequest;
  Builder: TIndexBuilder;
  CacheData: TBytes;
  Busy: Boolean;
  Writer: TThread;
begin
  // Stand der anderen Instanz vorbereiten, aber noch nicht schreiben.
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  CacheData := TIndexCache.Serialize(FIndex.Units);
  FIndex := TSymbolIndex.Create;
  Busy := True;
  // Die andere Instanz schreibt nach kurzer Zeit ihren Cache und gibt die Sperre frei.
  Writer := TThread.CreateAnonymousThread(
    procedure
    begin
      TThread.Sleep(300);
      FFiles.WriteBytes(CacheFile, CacheData);
      Busy := False;
    end);
  Writer.FreeOnTerminate := False;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := CacheFile;
    Request.ReadOnlyCache := True;
    Request.CacheBusy :=
      function: Boolean
      begin
        Result := Busy;
      end;
    Request.CacheWaitMs := 10000;
    FFiles.Reads := 0;
    Writer.Start;
    Service.Start(Request);
    Service.WaitFor;
    // Nur der Cache wurde gelesen, keine Quelldatei.
    Assert.AreEqual(1, FFiles.Reads);
    Assert.AreEqual(5, Service.Index.UnitCount);
  finally
    Service.Free;
    Writer.WaitFor;
    Writer.Free;
  end;
end;

procedure TIndexBuilderTests.ReadOnlyServiceStopsWaitingAfterLimit;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Data: TBytes;
begin
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\index.json';
    Request.ReadOnlyCache := True;
    Request.CacheBusy :=
      function: Boolean
      begin
        Result := True;
      end;
    Request.CacheWaitMs := 300;
    Service.Start(Request);
    Service.WaitFor;
    Assert.AreEqual(5, Service.Index.UnitCount);
  finally
    Service.Free;
  end;
  // Nur lesend: kein Cache geschrieben.
  Assert.IsFalse(FFileSystem.ReadBytes('C:\Cache\index.json', Data));
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexBuilderTests);
  TDUnitX.RegisterTestFixture(TIndexGroupCacheTests);

end.
