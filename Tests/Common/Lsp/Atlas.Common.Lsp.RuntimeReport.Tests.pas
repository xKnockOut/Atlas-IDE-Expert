unit Atlas.Common.Lsp.RuntimeReport.Tests;

// Befehle atlas.server.runtimeReport und .clear (#74): Diagnosen an Erzeugungs- und Absturzstellen (Zeile ab 0,
// Quelle des Werkzeugs, Warnung bzw. Hinweis), Antwort als JSON, Speicher und Neumeldung der Dateien, Leeren,
// Fehler ohne URI, ohne Text und bei unlesbarer Basis.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Compiler.Results,
  Atlas.Common.Lsp.RuntimeReport;

type
  [TestFixture]
  TLspRuntimeReportTests = class
  private
    FFiles: IRuntimeReportFiles;
    FResults: TCompilerResults;
    FCommand: TLspRuntimeReport;
    FPublished: TArray<string>;
    function Run(const AOptions: string): string;
    function RaisesInvalidParams(const AArguments: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LeakMessagesAtCreationSite;
    [Test]
    procedure CrashMessagesAtSiteAndStack;
    [Test]
    procedure LeakAnswerAsJson;
    [Test]
    procedure CrashAnswerAsJson;
    [Test]
    procedure ExecuteStoresAndPublishes;
    [Test]
    procedure ClearRemovesMessages;
    [Test]
    procedure OtherTextGivesNone;
    [Test]
    procedure InvalidParams;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.Json,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Diagnostics.RuntimeReport,
  Atlas.Common.Localization.Texts;

const
  cNl = #13#10;
  cListe = 'C:\Projekt\Kunden.Liste.pas';
  cMain = 'C:\Projekt\Main.pas';

  cSeparator = '--------------------------------2026/11/13 10:00:00--------------------------------';

  cFastMM =
    cSeparator + cNl +
    'A memory block has been leaked. The size is: 20' + cNl + cNl +
    'This block was allocated by thread 0x1A2C, and the stack trace (return addresses) at the time was:' + cNl +
    '4068F6 [System.pas][System][@GetMem$qqri][4843]' + cNl +
    '4C2C10 [Kunden.Liste.pas][Kunden.Liste][TKundenListe.Lade][42]' + cNl + cNl +
    'The block is currently used for an object of class: TStringList' + cNl + cNl;

  cMadExcept =
    'exception class    : EAccessViolation' + cNl +
    'exception message  : Access violation at address 00401112 in module ''Kunden.exe''. Read of address 0.' + cNl +
    cNl +
    'main thread ($1a2c):' + cNl +
    '00401112 +012 Kunden.exe   System.SysUtils   900 +1 RaiseIt' + cNl +
    '00401112 +012 Kunden.exe   Kunden.Liste       42 +3 TKundenListe.Lade' + cNl +
    '00401200 +000 Kunden.exe   Main               17 +0 TMainForm.FormCreate' + cNl +
    cNl +
    'thread $2b3c (TSyncWorker):' + cNl +
    '00401200 +000 Kunden.exe   Main               17 +0 TMainForm.FormCreate' + cNl;

type
  /// <summary>Ohne Map; das Projekt kennt Kunden.Liste und Main.</summary>
  TFakeFiles = class(TInterfacedObject, IRuntimeReportFiles)
  public
    procedure LoadSymbols(const AUri, AMapName, AExeName: string; ABase: UInt64; out ASymbols: TReportSymbols);
    function UnitFileOf(const AUri: string): TReportUnitFileFunc;
  end;

procedure TFakeFiles.LoadSymbols(const AUri, AMapName, AExeName: string; ABase: UInt64;
  out ASymbols: TReportSymbols);
begin
  ASymbols := Default(TReportSymbols);
  ASymbols.MapName := AMapName;
  ASymbols.Base := ABase;
end;

function TFakeFiles.UnitFileOf(const AUri: string): TReportUnitFileFunc;
begin
  Result :=
    function(const AUnitName, AFileName: string): string
    begin
      Result := '';
      if SameText(AUnitName, 'Kunden.Liste') then
      begin
        Result := cListe;
      end
      else if SameText(AUnitName, 'Main') then
      begin
        Result := cMain;
      end;
    end;
end;

procedure TLspRuntimeReportTests.Setup;
var
  mFiles: TFakeFiles;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  mFiles := TFakeFiles.Create;
  FFiles := mFiles;
  FResults := TCompilerResults.Create;
  FPublished := nil;
  FCommand := TLspRuntimeReport.Create(FFiles, FResults,
    procedure(const AFileNames: TArray<string>)
    begin
      FPublished := FPublished + AFileNames;
    end);
end;

procedure TLspRuntimeReportTests.TearDown;
begin
  FreeAndNil(FCommand);
  FreeAndNil(FResults);
  FFiles := nil;
  FPublished := nil;
  TAtlasLocale.Use(TTextLanguage.German);
end;

function TLspRuntimeReportTests.Run(const AOptions: string): string;
var
  mArguments: TJSONArray;
  mResult: TJSONValue;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add('file:///C:/Projekt/Kunden.dpr');
    mArguments.AddElement(TJsonRead.ParseObject(AOptions));
    mResult := FCommand.Execute(mArguments);
    try
      Result := mResult.ToJSON([]);
    finally
      mResult.Free;
    end;
  finally
    mArguments.Free;
  end;
end;

function TLspRuntimeReportTests.RaisesInvalidParams(const AArguments: string): Boolean;
var
  mArguments: TJSONArray;
begin
  Result := False;
  mArguments := TJsonRead.Parse(AArguments) as TJSONArray;
  try
    try
      FCommand.Execute(mArguments).Free;
    except
      on E: EJsonRpcError do
      begin
        Result := E.Code = TJsonRpcErrorCode.cInvalidParams;
      end;
    end;
  finally
    mArguments.Free;
  end;
end;

function Report(const AText: string): TRuntimeReport;
var
  mFiles: IRuntimeReportFiles;
begin
  mFiles := TFakeFiles.Create;
  Result := TRuntimeReports.Build(AText, Default(TReportSymbols), mFiles.UnitFileOf(''));
end;

procedure TLspRuntimeReportTests.LeakMessagesAtCreationSite;
var
  mMessages: TArray<TCompilerMessage>;
begin
  mMessages := TLspRuntimeReport.MessagesOf(Report(cFastMM + cFastMM));
  Assert.AreEqual(1, Integer(Length(mMessages)));
  Assert.AreEqual(cListe, mMessages[0].FileName);
  Assert.AreEqual(41, mMessages[0].Line);
  Assert.AreEqual(-1, mMessages[0].Column);
  Assert.AreEqual<TCompilerSeverity>(TCompilerSeverity.Warning, mMessages[0].Severity);
  Assert.AreEqual('FastMM', mMessages[0].Source);
  Assert.AreEqual('Leck: TStringList × 2 (40 Bytes) wird hier erzeugt', mMessages[0].Text);
end;

procedure TLspRuntimeReportTests.CrashMessagesAtSiteAndStack;
var
  mMessages: TArray<TCompilerMessage>;
begin
  mMessages := TLspRuntimeReport.MessagesOf(Report(cMadExcept));
  // Nur der Thread der Exception, nur Zeilen im Projekt.
  Assert.AreEqual(2, Integer(Length(mMessages)));
  Assert.AreEqual(cListe, mMessages[0].FileName);
  Assert.AreEqual(41, mMessages[0].Line);
  Assert.AreEqual<TCompilerSeverity>(TCompilerSeverity.Warning, mMessages[0].Severity);
  Assert.AreEqual('madExcept', mMessages[0].Source);
  Assert.AreEqual('Absturz hier: EAccessViolation: Access violation at address 00401112 in module ''Kunden.exe''. ' +
    'Read of address 0.', mMessages[0].Text);
  Assert.AreEqual(cMain, mMessages[1].FileName);
  Assert.AreEqual(16, mMessages[1].Line);
  Assert.AreEqual<TCompilerSeverity>(TCompilerSeverity.Hint, mMessages[1].Severity);
end;

procedure TLspRuntimeReportTests.LeakAnswerAsJson;
var
  mText: string;
begin
  mText := Run('{"text":' + TJsonText.Quote(cFastMM) + '}');
  Assert.IsTrue(mText.Contains('"kind":"leaks","source":"FastMM","title":"1 Lecks (1 Arten)"'), mText);
  Assert.IsTrue(mText.Contains('"mapStatus":"none","map":"","diagnostics":1'), mText);
  Assert.IsTrue(mText.Contains('"groups":[{"name":"TStringList","kind":"instance","count":1,"size":20,"site":1,'),
    mText);
  Assert.IsTrue(mText.Contains('{"address":"$004C2C10","module":"","unit":"Kunden.Liste",' +
    '"routine":"TKundenListe.Lade","line":42,"uri":'), mText);
  Assert.IsTrue(mText.Contains('"file":"C:\\Projekt\\Kunden.Liste.pas"'), mText);
end;

procedure TLspRuntimeReportTests.CrashAnswerAsJson;
var
  mText: string;
begin
  mText := Run('{"text":' + TJsonText.Quote(cMadExcept) + ',"map":"C:\\Projekt\\Kunden.map"}');
  Assert.IsTrue(mText.Contains('"kind":"crash","source":"madExcept","title":"EAccessViolation: Access violation'),
    mText);
  Assert.IsTrue(mText.Contains('"mapStatus":"missing","map":"C:\\Projekt\\Kunden.map","diagnostics":2'), mText);
  Assert.IsTrue(mText.Contains('"crash":{"exceptionClass":"EAccessViolation","message":"Access violation'), mText);
  Assert.IsTrue(mText.Contains('"address":"$00401112","module":"Kunden.exe"}'), mText);
  Assert.IsTrue(mText.Contains('"threads":[{"name":"main thread ($1a2c)","crashed":true,"site":1,'), mText);
  Assert.IsTrue(mText.Contains('{"name":"thread $2b3c (TSyncWorker)","crashed":false,"site":0,'), mText);
  Assert.IsFalse(mText.Contains('"groups"'), mText);
end;

procedure TLspRuntimeReportTests.ExecuteStoresAndPublishes;
begin
  Run('{"text":' + TJsonText.Quote(cMadExcept) + '}');
  Assert.AreEqual(2, Integer(Length(FPublished)));
  Assert.AreEqual(1, Integer(Length(FResults.MessagesFor(cListe))));
  Assert.AreEqual('madExcept', FResults.MessagesFor(cListe)[0].Source);
  // Ein neuer Bericht ersetzt den alten: Main.pas wird mit gemeldet, weil dort nichts mehr steht.
  FPublished := nil;
  Run('{"text":' + TJsonText.Quote(cFastMM) + '}');
  Assert.AreEqual(2, Integer(Length(FPublished)));
  Assert.AreEqual(0, Integer(Length(FResults.MessagesFor(cMain))));
  Assert.AreEqual('FastMM', FResults.MessagesFor(cListe)[0].Source);
end;

procedure TLspRuntimeReportTests.ClearRemovesMessages;
var
  mResult: TJSONValue;
begin
  Run('{"text":' + TJsonText.Quote(cMadExcept) + '}');
  FPublished := nil;
  mResult := FCommand.Clear;
  try
    Assert.AreEqual('{"cleared":2}', mResult.ToJSON([]));
  finally
    mResult.Free;
  end;
  Assert.AreEqual(2, Integer(Length(FPublished)));
  Assert.AreEqual(0, Integer(Length(FResults.MessagesFor(cListe))));
end;

procedure TLspRuntimeReportTests.OtherTextGivesNone;
var
  mText: string;
begin
  mText := Run('{"text":"unit Main; interface end."}');
  Assert.IsTrue(mText.Contains('"kind":"none","source":"","title":""'), mText);
  Assert.IsTrue(mText.Contains('"diagnostics":0'), mText);
  Assert.AreEqual(0, Integer(Length(FPublished)));
end;

procedure TLspRuntimeReportTests.InvalidParams;
begin
  Assert.IsTrue(RaisesInvalidParams('[]'));
  Assert.IsTrue(RaisesInvalidParams('["file:///C:/P/A.dpr"]'));
  Assert.IsTrue(RaisesInvalidParams('["file:///C:/P/A.dpr",{"text":"   "}]'));
  Assert.IsTrue(RaisesInvalidParams('["file:///C:/P/A.dpr",{"text":"x","base":"zz"}]'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspRuntimeReportTests);

end.
