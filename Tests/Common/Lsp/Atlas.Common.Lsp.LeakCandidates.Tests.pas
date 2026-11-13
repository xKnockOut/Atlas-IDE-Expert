unit Atlas.Common.Lsp.LeakCandidates.Tests;

// Befehl atlas.server.leakCandidates (#1875): Klassen aus dem Bericht und aus
// classes, Kandidaten als JSON, Testunits im Programm und im Testprojekt,
// Dateien ohne den Namen, Fehler ohne URI und ohne Projekt.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.LeakCandidates;

type
  [TestFixture]
  TLspLeakCandidatesTests = class
  private
    FFiles: ILeakCandidateFiles;
    /// <summary>Dasselbe Objekt wie FFiles, ohne Referenz.</summary>
    FFake: TObject;
    FCommand: TLspLeakCandidates;
    function Run(const AOptions: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ClassesFromReportAndNames;
    [Test]
    procedure CandidatesAsJson;
    [Test]
    procedure TestUnitOutsideProgram;
    [Test]
    procedure TestUnitInTestProject;
    [Test]
    procedure MentionsAnyIgnoresCase;
    [Test]
    procedure MissingUriInvalidParams;
    [Test]
    procedure NoProjectInvalidParams;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.Json,
  Atlas.Text.LeakReport,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris;

const
  cNl = #13#10;
  cMain = 'C:\P\App.dpr';
  cUnit = 'C:\P\Kunden.pas';
  cTestUnit = 'C:\P\Kunden.Tests.pas';
  cOther = 'C:\P\Leer.pas';
  cReport = 'An unexpected memory leak has occurred. The unexpected small block leaks are:' + cNl + cNl +
    '13 - 20 bytes: TKunde x 2, UnicodeString x 3' + cNl;

type
  TFakeFiles = class(TInterfacedObject, ILeakCandidateFiles)
  public
    Loaded: Boolean;
    MainText: string;
    function ProjectOf(const AUri: string; out AMainSource: string; out AFiles: TArray<string>;
      out AReason: string): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
  end;

function TFakeFiles.ProjectOf(const AUri: string; out AMainSource: string; out AFiles: TArray<string>;
  out AReason: string): Boolean;
begin
  AMainSource := cMain;
  AFiles := TArray<string>.Create(cUnit, cTestUnit, cOther);
  AReason := 'kein Projekt';
  Result := Loaded;
end;

function TFakeFiles.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if AFileName = cMain then
  begin
    AText := MainText;
  end
  else if AFileName = cUnit then
  begin
    AText := 'unit Kunden;' + cNl + 'interface' + cNl + 'implementation' + cNl + 'procedure Lade;' + cNl + 'begin' +
      cNl + '  TKunde.Create;' + cNl + 'end;' + cNl + 'end.';
  end
  else if AFileName = cTestUnit then
  begin
    AText := 'unit Kunden.Tests;' + cNl + 'interface' + cNl + 'uses DUnitX.TestFramework;' + cNl + 'implementation' +
      cNl + 'procedure T;' + cNl + 'begin' + cNl + '  TKunde.Create;' + cNl + 'end;' + cNl + 'end.';
  end
  else if AFileName = cOther then
  begin
    AText := 'unit Leer;' + cNl + 'interface' + cNl + 'implementation' + cNl + 'end.';
  end
  else
  begin
    Result := False;
  end;
end;

procedure TLspLeakCandidatesTests.Setup;
var
  mFiles: TFakeFiles;
begin
  mFiles := TFakeFiles.Create;
  mFiles.Loaded := True;
  mFiles.MainText := 'program App;' + cNl + 'uses Kunden;' + cNl + 'begin' + cNl + 'end.';
  FFiles := mFiles;
  FFake := mFiles;
  FCommand := TLspLeakCandidates.Create(FFiles);
end;

procedure TLspLeakCandidatesTests.TearDown;
begin
  FreeAndNil(FCommand);
  FFiles := nil;
  FFake := nil;
end;

function TLspLeakCandidatesTests.Run(const AOptions: string): string;
var
  mArguments: TJSONArray;
  mResult: TJSONValue;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(TDocumentUris.FromPath(cMain));
    if AOptions <> '' then
    begin
      mArguments.AddElement(TJsonRead.ParseObject(AOptions));
    end;
    mResult := FCommand.Execute(mArguments);
    try
      Result := mResult.ToJSON;
    finally
      mResult.Free;
    end;
  finally
    mArguments.Free;
  end;
end;

procedure TLspLeakCandidatesTests.ClassesFromReportAndNames;
var
  mOptions: TJSONObject;
  mClasses: TArray<TLeakCount>;
  mHasStacks: Boolean;
begin
  mOptions := TJsonRead.ParseObject('{"report":' + TJsonText.Quote(cReport) +
    ',"classes":["TStringList","tkunde",""]}');
  try
    mClasses := TLspLeakCandidates.ClassesOf(mOptions, mHasStacks);
  finally
    mOptions.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mClasses)), 'ohne UnicodeString, ohne doppelten Namen');
  Assert.AreEqual('TKunde', mClasses[0].Name);
  Assert.AreEqual(2, mClasses[0].Count);
  Assert.AreEqual('TStringList', mClasses[1].Name);
  Assert.AreEqual(0, mClasses[1].Count);
  Assert.IsFalse(mHasStacks);
  mClasses := TLspLeakCandidates.ClassesOf(nil, mHasStacks);
  Assert.AreEqual(0, Integer(Length(mClasses)), 'ohne Optionen');
end;

procedure TLspLeakCandidatesTests.CandidatesAsJson;
var
  mJson: string;
begin
  mJson := Run('{"report":' + TJsonText.Quote(cReport) + '}');
  Assert.IsTrue(Pos('"classes":[{"name":"TKunde","count":2}]', mJson) > 0, mJson);
  Assert.IsTrue(Pos('"hasStacks":false,"truncated":false', mJson) > 0, mJson);
  Assert.IsTrue(Pos('"line":5,"character":2,"className":"TKunde","rating":"neverFreed","target":"",' +
    '"routine":"Lade"', mJson) > 0, mJson);
  Assert.IsTrue(Pos('"project":', mJson) > 0, mJson);
  Assert.IsTrue(Pos('Leer.pas', mJson) = 0, 'Datei ohne den Namen');
end;

procedure TLspLeakCandidatesTests.TestUnitOutsideProgram;
var
  mJson: string;
begin
  mJson := Run('{"classes":["TKunde"]}');
  Assert.IsTrue(Pos('"rating":"notInProgram"', mJson) > 0, mJson);
  Assert.IsTrue(Pos('"rating":"neverFreed"', mJson) < Pos('"rating":"notInProgram"', mJson), 'Programm zuerst');
end;

procedure TLspLeakCandidatesTests.TestUnitInTestProject;
var
  mJson: string;
begin
  TFakeFiles(FFake).MainText := 'program AppTests;' + cNl + 'uses DUnitX.TestFramework, Kunden.Tests;' + cNl +
    'begin' + cNl + 'end.';
  mJson := Run('{"classes":["TKunde"]}');
  Assert.IsTrue(Pos('notInProgram', mJson) = 0, mJson);
end;

procedure TLspLeakCandidatesTests.MentionsAnyIgnoresCase;
begin
  Assert.IsTrue(TLspLeakCandidates.MentionsAny('x := tkunde.create;', TArray<string>.Create('TListe', 'TKunde')));
  Assert.IsFalse(TLspLeakCandidates.MentionsAny('x := TListe.Create;', TArray<string>.Create('TKunde')));
  Assert.IsFalse(TLspLeakCandidates.MentionsAny('TKunde', nil));
end;

procedure TLspLeakCandidatesTests.MissingUriInvalidParams;
var
  mArguments: TJSONArray;
  mRaised: Boolean;
begin
  mArguments := TJSONArray.Create;
  mRaised := False;
  try
    try
      FCommand.Execute(mArguments).Free;
    except
      on E: EJsonRpcError do
      begin
        mRaised := E.Code = TJsonRpcErrorCode.cInvalidParams;
      end;
    end;
  finally
    mArguments.Free;
  end;
  Assert.IsTrue(mRaised);
end;

procedure TLspLeakCandidatesTests.NoProjectInvalidParams;
var
  mRaised: Boolean;
begin
  TFakeFiles(FFake).Loaded := False;
  mRaised := False;
  try
    Run('{"classes":["TKunde"]}');
  except
    on E: EJsonRpcError do
    begin
      mRaised := Pos('kein Projekt', E.Message) > 0;
    end;
  end;
  Assert.IsTrue(mRaised);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspLeakCandidatesTests);

end.
