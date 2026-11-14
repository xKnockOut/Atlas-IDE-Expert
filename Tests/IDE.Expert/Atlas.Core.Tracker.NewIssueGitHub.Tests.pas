unit Atlas.Core.Tracker.NewIssueGitHub.Tests;

// GitHub-Teil von „Issue anlegen …“ (#2137) gegen eine Fake-Transportschicht:
// Adressen, Vorlagen aus der Arbeitskopie und aus dem Repository (base64),
// Meilensteine, Issue-Typen (Repository, sonst Organisation), Issue-Felder,
// Prüfung der Feldwerte, Rumpf des POST mit milestone, type und
// issue_field_values und was GitHub nicht übernommen hat.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasGitHubNewIssueTests = class
  private
    FDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure UrlsOfRepositoryAndOrganisation;
    [Test]
    procedure ParsesListingAndBase64Content;
    [Test]
    procedure ParsesMilestonesTypesAndFields;
    [Test]
    procedure ValidValueByKind;
    [Test]
    procedure AddToMergesLabelsAndAddsMilestoneTypeFields;
    [Test]
    procedure AddToWithEmptyDraftAddsNothing;
    [Test]
    procedure DroppedComparesResponse;
    [Test]
    procedure LoadPrefersLocalFiles;
    [Test]
    procedure LoadReadsTemplatesFromRepository;
    [Test]
    procedure LoadWithoutTemplatesSkipsContents;
    [Test]
    procedure LocalFilesSearchUpToRepositoryRoot;
    [Test]
    procedure AddToProjectsWithoutSendFailsAll;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Diagnostics,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Contract.Files,
  Atlas.Core.Tracker.IssueForms,
  Atlas.Core.Tracker.NewIssueGitHub;

const
  cRepo = 'https://api.github.com/repos/acme/kasse';
  cOrg = 'https://api.github.com/orgs/acme';
  cTimeoutMs = 10000;
  /// <summary>"name: Frage / body: input a mit Beschriftung Ä" als base64 mit Zeilenumbruch wie bei GitHub.
  /// </summary>
  cContent = '{"encoding":"base64","content":"bmFtZTogRnJhZ2UKYm9keToKICAtIHR5cGU6IGlu\n' +
    'cHV0CiAgICBpZDogYQogICAgYXR0cmlidXRlczoKICAgICAgbGFiZWw6IMOECg=="}';
  cListing = '[{"type":"file","name":"frage.yml"},{"type":"dir","name":"alt"},{"type":"file","name":"config.yml"},' +
    '{"type":"file","name":"liesmich.txt"}]';
  cConfig = '{"encoding":"base64","content":"YmxhbmtfaXNzdWVzX2VuYWJsZWQ6IGZhbHNlCg=="}';
  cFields = '[{"id":11,"name":"Kunde","data_type":"text"},{"id":12,"name":"Aufwand","data_type":"number"},' +
    '{"id":13,"name":"Termin","data_type":"date"},{"id":14,"name":"Bereich","data_type":"single_select",' +
    '"options":[{"name":"Kasse"},{"name":"Lager"}]},{"id":15,"name":"Mehrfach","data_type":"multi_select"},' +
    '{"name":"ohne Kennung","data_type":"text"}]';

type
  TFakeTransport = class(TInterfacedObject, IAtlasCiTransport)
  private
    FUrls: TArray<string>;
    FTexts: TArray<string>;
  public
    Calls: TArray<string>;
    destructor Destroy; override;
    /// <summary>GET auf genau AUrl antwortet 200 mit AText; alles andere 404.</summary>
    procedure Reply(const AUrl, AText: string);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

destructor TFakeTransport.Destroy;
begin
  FUrls := nil;
  FTexts := nil;
  Calls := nil;
  inherited Destroy;
end;

procedure TFakeTransport.Reply(const AUrl, AText: string);
begin
  FUrls := FUrls + [AUrl];
  FTexts := FTexts + [AText];
end;

function TFakeTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mIndex: Integer;
begin
  Calls := Calls + [AUrl];
  AError := TAtlasCiFetchError.None;
  AStatus := 404;
  AText := '';
  Result := True;
  for mIndex := 0 to High(FUrls) do
  begin
    if FUrls[mIndex] = AUrl then
    begin
      AStatus := 200;
      AText := FTexts[mIndex];
      Exit;
    end;
  end;
end;

type
  /// <summary>Nur Lesen über System.IOUtils (die Umsetzung des Plugins braucht Windows); alles andere tut nichts.
  /// </summary>
  TReadOnlyFiles = class(TInterfacedObject, IAtlasTrackerFiles)
  public
    function FileExists(const AFileName: string): Boolean;
    function FolderExists(const AFolder: string): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function ReadHead(const AFileName: string; AMaxBytes: Integer; out AData: TBytes): Boolean;
    function ReadTail(const AFileName: string; AMaxBytes: Integer; out AData: TBytes; out ACut: Boolean): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
    function ReplaceText(const AFileName, AText: string): Boolean;
    function WriteBytes(const AFileName: string; const AData: TBytes): Boolean;
    function DeleteFile(const AFileName: string): Boolean;
    function DeleteFolder(const AFolder: string): Boolean;
    function RemoveEmptyFolder(const AFolder: string): Boolean;
    function ForceFolder(const AFolder: string): Boolean;
    function Files(const AFolder, AMask: string): TArray<string>;
    function Folders(const AFolder: string): TArray<string>;
    function WriteTime(const APath: string): TDateTime;
    function Lock(const AFileName: string; AWaitMs: Integer): IInterface;
    function Environment(const AName: string): string;
    function TempFolder: string;
  end;

function TReadOnlyFiles.FileExists(const AFileName: string): Boolean;
begin
  Result := TFile.Exists(AFileName);
end;

function TReadOnlyFiles.FolderExists(const AFolder: string): Boolean;
begin
  Result := TDirectory.Exists(AFolder);
end;

function TReadOnlyFiles.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := TFile.Exists(AFileName);
  if Result then
  begin
    AText := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  end;
end;

function TReadOnlyFiles.ReadHead(const AFileName: string; AMaxBytes: Integer; out AData: TBytes): Boolean;
begin
  AData := nil;
  Result := False;
end;

function TReadOnlyFiles.ReadTail(const AFileName: string; AMaxBytes: Integer; out AData: TBytes;
  out ACut: Boolean): Boolean;
begin
  AData := nil;
  ACut := False;
  Result := False;
end;

function TReadOnlyFiles.WriteText(const AFileName, AText: string): Boolean;
begin
  Result := False;
end;

function TReadOnlyFiles.ReplaceText(const AFileName, AText: string): Boolean;
begin
  Result := False;
end;

function TReadOnlyFiles.WriteBytes(const AFileName: string; const AData: TBytes): Boolean;
begin
  Result := False;
end;

function TReadOnlyFiles.DeleteFile(const AFileName: string): Boolean;
begin
  Result := False;
end;

function TReadOnlyFiles.DeleteFolder(const AFolder: string): Boolean;
begin
  Result := False;
end;

function TReadOnlyFiles.RemoveEmptyFolder(const AFolder: string): Boolean;
begin
  Result := False;
end;

function TReadOnlyFiles.ForceFolder(const AFolder: string): Boolean;
begin
  Result := False;
end;

function TReadOnlyFiles.Files(const AFolder, AMask: string): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in TDirectory.GetFiles(AFolder) do
  begin
    Result := Result + [mName];
  end;
end;

function TReadOnlyFiles.Folders(const AFolder: string): TArray<string>;
begin
  Result := nil;
end;

function TReadOnlyFiles.WriteTime(const APath: string): TDateTime;
begin
  Result := 0;
end;

function TReadOnlyFiles.Lock(const AFileName: string; AWaitMs: Integer): IInterface;
begin
  Result := nil;
end;

function TReadOnlyFiles.Environment(const AName: string): string;
begin
  Result := '';
end;

function TReadOnlyFiles.TempFolder: string;
begin
  Result := '';
end;

function Target: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, 'https://github.com', 'acme/kasse', '');
end;

function Field(AId: Int64; AKind: TAtlasIssueFieldKind; const AOptions: TArray<string>): TAtlasGitHubIssueField;
begin
  Result := Default(TAtlasGitHubIssueField);
  Result.Id := AId;
  Result.Name := 'Feld';
  Result.Kind := AKind;
  Result.Options := AOptions;
end;

procedure WriteFile(const AFileName, AText: string);
begin
  ForceDirectories(ExtractFileDir(AFileName));
  TFile.WriteAllText(AFileName, AText, TEncoding.UTF8);
end;

{ TAtlasGitHubNewIssueTests }

procedure TAtlasGitHubNewIssueTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'AtlasIssueForms-' + TGUID.NewGuid.ToString);
end;

procedure TAtlasGitHubNewIssueTests.TearDown;
begin
  if TDirectory.Exists(FDir) then
  begin
    TDirectory.Delete(FDir, True);
  end;
  FDir := '';
end;

procedure TAtlasGitHubNewIssueTests.UrlsOfRepositoryAndOrganisation;
var
  mEmpty: TAtlasTrackerTarget;
begin
  Assert.AreEqual('https://github.com/acme/kasse', TAtlasGitHubNewIssue.RepositoryPage(Target));
  Assert.AreEqual(cRepo + '/contents/.github/ISSUE_TEMPLATE',
    TAtlasGitHubNewIssue.ContentsUrl(Target, TAtlasIssueForms.cFolder));
  Assert.AreEqual(cRepo + '/milestones?state=open&sort=due_on&per_page=100',
    TAtlasGitHubNewIssue.MilestonesUrl(Target));
  Assert.AreEqual(cRepo + '/issue-types,' + cOrg + '/issue-types',
    string.Join(',', TAtlasGitHubNewIssue.IssueTypesUrls(Target)));
  Assert.AreEqual(cRepo + '/issue-fields,' + cOrg + '/issue-fields',
    string.Join(',', TAtlasGitHubNewIssue.IssueFieldsUrls(Target)));
  mEmpty := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, 'https://github.com', 'ohne-slash', '');
  Assert.AreEqual('', TAtlasGitHubNewIssue.MilestonesUrl(mEmpty));
  Assert.AreEqual(0, Integer(Length(TAtlasGitHubNewIssue.IssueTypesUrls(mEmpty))));
end;

procedure TAtlasGitHubNewIssueTests.ParsesListingAndBase64Content;
var
  mText: string;
begin
  Assert.AreEqual('frage.yml,config.yml,liesmich.txt', string.Join(',',
    TAtlasGitHubNewIssue.ParseListing(cListing)), 'nur Dateien');
  Assert.AreEqual(0, Integer(Length(TAtlasGitHubNewIssue.ParseListing('{"message":"Not Found"}'))));
  Assert.IsTrue(TAtlasGitHubNewIssue.ParseContent(cContent, mText));
  Assert.IsTrue(mText.StartsWith('name: Frage' + #10 + 'body:'));
  Assert.IsTrue(mText.EndsWith('label: Ä' + #10), 'UTF-8');
  Assert.IsFalse(TAtlasGitHubNewIssue.ParseContent('{"encoding":"none","content":"x"}', mText));
  Assert.IsFalse(TAtlasGitHubNewIssue.ParseContent('{"encoding":"base64","content":"%%"}', mText));
end;

procedure TAtlasGitHubNewIssueTests.ParsesMilestonesTypesAndFields;
var
  mMilestones: TArray<TAtlasGitHubMilestone>;
  mTypes: TArray<string>;
  mFields: TArray<TAtlasGitHubIssueField>;
begin
  Assert.IsTrue(TAtlasGitHubNewIssue.ParseMilestones('[{"number":3,"title":"v2.2.0"},{"number":0,"title":"x"},' +
    '{"number":4,"title":""}]', mMilestones));
  Assert.AreEqual(1, Integer(Length(mMilestones)));
  Assert.AreEqual(3, mMilestones[0].Number);
  Assert.AreEqual('v2.2.0', mMilestones[0].Title);
  Assert.IsFalse(TAtlasGitHubNewIssue.ParseMilestones('{"message":"Not Found"}', mMilestones));
  Assert.IsTrue(TAtlasGitHubNewIssue.ParseIssueTypes('[{"name":"Bug","is_enabled":true},' +
    '{"name":"Alt","is_enabled":false},{"name":"Task"}]', mTypes));
  Assert.AreEqual('Bug,Task', string.Join(',', mTypes));
  Assert.IsTrue(TAtlasGitHubNewIssue.ParseIssueFields(cFields, mFields));
  Assert.AreEqual(4, Integer(Length(mFields)), 'ohne Mehrfachauswahl und ohne Kennung');
  Assert.AreEqual(Int64(12), mFields[1].Id);
  Assert.AreEqual<TAtlasIssueFieldKind>(TAtlasIssueFieldKind.Number, mFields[1].Kind);
  Assert.AreEqual<TAtlasIssueFieldKind>(TAtlasIssueFieldKind.Date, mFields[2].Kind);
  Assert.AreEqual<TAtlasIssueFieldKind>(TAtlasIssueFieldKind.SingleSelect, mFields[3].Kind);
  Assert.AreEqual('Kasse,Lager', string.Join(',', mFields[3].Options));
end;

procedure TAtlasGitHubNewIssueTests.ValidValueByKind;
var
  mSelect: TAtlasGitHubIssueField;
begin
  Assert.IsTrue(TAtlasGitHubNewIssue.ValidValue(Field(1, TAtlasIssueFieldKind.Number, nil), '2.5'));
  Assert.IsFalse(TAtlasGitHubNewIssue.ValidValue(Field(1, TAtlasIssueFieldKind.Number, nil), 'zwei'));
  Assert.IsTrue(TAtlasGitHubNewIssue.ValidValue(Field(1, TAtlasIssueFieldKind.Date, nil), '2026-11-13'));
  Assert.IsFalse(TAtlasGitHubNewIssue.ValidValue(Field(1, TAtlasIssueFieldKind.Date, nil), '13.11.2026'));
  Assert.IsFalse(TAtlasGitHubNewIssue.ValidValue(Field(1, TAtlasIssueFieldKind.Date, nil), '2026-13-40'));
  mSelect := Field(1, TAtlasIssueFieldKind.SingleSelect, TArray<string>.Create('Kasse', 'Lager'));
  Assert.IsTrue(TAtlasGitHubNewIssue.ValidValue(mSelect, 'kasse'));
  Assert.IsFalse(TAtlasGitHubNewIssue.ValidValue(mSelect, 'Büro'));
  Assert.IsTrue(TAtlasGitHubNewIssue.ValidValue(mSelect, ''), 'leer passt immer');
  Assert.IsTrue(TAtlasGitHubNewIssue.ValidValue(Field(1, TAtlasIssueFieldKind.Text, nil), 'frei'));
end;

procedure TAtlasGitHubNewIssueTests.AddToMergesLabelsAndAddsMilestoneTypeFields;
var
  mRoot: TJSONObject;
  mDraft: TAtlasGitHubDraft;
begin
  mDraft := TAtlasGitHubDraft.Empty;
  mDraft.Labels := TArray<string>.Create('Bug', 'triage');
  mDraft.Assignees := TArray<string>.Create('anna');
  mDraft.Milestone := 3;
  mDraft.IssueType := 'Bug';
  mDraft.FieldValues := [TAtlasGitHubFieldValue.Create(Field(12, TAtlasIssueFieldKind.Number, nil), '2.5'),
    TAtlasGitHubFieldValue.Create(Field(11, TAtlasIssueFieldKind.Text, nil), ' Kunde A '),
    TAtlasGitHubFieldValue.Create(Field(13, TAtlasIssueFieldKind.Date, nil), '')];
  mRoot := TJSONObject.ParseJSONValue('{"title":"T","labels":["bug"]}') as TJSONObject;
  try
    TAtlasGitHubNewIssue.AddTo(mRoot, mDraft);
    Assert.AreEqual('{"title":"T","labels":["bug","triage"],"assignees":["anna"],"milestone":3,"type":"Bug",' +
      '"issue_field_values":[{"field_id":12,"value":2.5},{"field_id":11,"value":"Kunde A"}]}', mRoot.ToJSON);
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasGitHubNewIssueTests.AddToWithEmptyDraftAddsNothing;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.ParseJSONValue('{"title":"T"}') as TJSONObject;
  try
    TAtlasGitHubNewIssue.AddTo(mRoot, TAtlasGitHubDraft.Empty);
    Assert.AreEqual('{"title":"T"}', mRoot.ToJSON);
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasGitHubNewIssueTests.DroppedComparesResponse;
var
  mDraft: TAtlasGitHubDraft;
  mDropped: TAtlasGitHubDropped;
begin
  mDraft := TAtlasGitHubDraft.Empty;
  mDraft.Milestone := 3;
  mDraft.IssueType := 'Bug';
  mDropped := TAtlasGitHubNewIssue.Dropped('{"number":7,"milestone":{"number":3},"type":{"name":"bug"}}', mDraft);
  Assert.IsFalse(mDropped.Any);
  mDropped := TAtlasGitHubNewIssue.Dropped('{"number":7,"milestone":null,"type":null}', mDraft);
  Assert.IsTrue(mDropped.Milestone);
  Assert.IsTrue(mDropped.IssueType);
  mDropped := TAtlasGitHubNewIssue.Dropped('{"number":7}', TAtlasGitHubDraft.Empty);
  Assert.IsFalse(mDropped.Any, 'nichts verlangt, nichts fehlt');
  Assert.AreEqual('I_7', TAtlasGitHubNewIssue.NodeId('{"node_id":"I_7"}'));
end;

procedure TAtlasGitHubNewIssueTests.LoadPrefersLocalFiles;
var
  mTransport: TFakeTransport;
  mRef: IAtlasCiTransport;
  mMeta: TAtlasGitHubIssueMeta;
  mCall: string;
begin
  mTransport := TFakeTransport.Create;
  mRef := mTransport;
  mTransport.Reply(cRepo + '/milestones?state=open&sort=due_on&per_page=100', '[{"number":3,"title":"v2.2.0"}]');
  mTransport.Reply(cOrg + '/issue-types', '[{"name":"Bug"}]');
  mTransport.Reply(cRepo + '/issue-fields', cFields);
  mMeta := TAtlasGitHubNewIssue.Load(Target, mRef, TAtlasGitHubMetaRequest.Create(True,
    [TAtlasIssueFormFile.Create('b.md', 'Text'), TAtlasIssueFormFile.Create('config.yml',
    'blank_issues_enabled: false'), TAtlasIssueFormFile.Create('a.yml', 'name: A' + #10 + 'body: []')]),
    TStopwatch.StartNew, cTimeoutMs);
  Assert.AreEqual(2, Integer(Length(mMeta.Forms)));
  Assert.AreEqual('a.yml', mMeta.Forms[0].FileName);
  Assert.IsFalse(mMeta.BlankAllowed);
  Assert.AreEqual(1, Integer(Length(mMeta.Milestones)));
  Assert.AreEqual('Bug', string.Join(',', mMeta.IssueTypes), 'Typen der Organisation nach 404 beim Repository');
  Assert.AreEqual(4, Integer(Length(mMeta.Fields)));
  for mCall in mTransport.Calls do
  begin
    Assert.IsFalse(mCall.Contains('/contents/'), 'keine Vorlagen aus dem Netz: ' + mCall);
  end;
end;

procedure TAtlasGitHubNewIssueTests.LoadReadsTemplatesFromRepository;
var
  mTransport: TFakeTransport;
  mRef: IAtlasCiTransport;
  mMeta: TAtlasGitHubIssueMeta;
begin
  mTransport := TFakeTransport.Create;
  mRef := mTransport;
  mTransport.Reply(cRepo + '/contents/.github/ISSUE_TEMPLATE', cListing);
  mTransport.Reply(cRepo + '/contents/.github/ISSUE_TEMPLATE/frage.yml', cContent);
  mTransport.Reply(cRepo + '/contents/.github/ISSUE_TEMPLATE/config.yml', cConfig);
  mMeta := TAtlasGitHubNewIssue.Load(Target, mRef, TAtlasGitHubMetaRequest.Create(True, nil), TStopwatch.StartNew,
    cTimeoutMs);
  Assert.AreEqual(1, Integer(Length(mMeta.Forms)));
  Assert.AreEqual('Frage', mMeta.Forms[0].Name);
  Assert.AreEqual('Ä', mMeta.Forms[0].Fields[0].Caption);
  Assert.IsFalse(mMeta.BlankAllowed);
  Assert.AreEqual(0, Integer(Length(mMeta.Milestones)), '404: Zeile bleibt aus');
  Assert.AreEqual(0, Integer(Length(mMeta.IssueTypes)));
  Assert.AreEqual(0, Integer(Length(mMeta.Fields)));
  Assert.AreEqual(-1, string.Join(' ', mTransport.Calls).IndexOf('liesmich.txt'), 'nur Vorlagen geladen');
end;

procedure TAtlasGitHubNewIssueTests.LoadWithoutTemplatesSkipsContents;
var
  mTransport: TFakeTransport;
  mRef: IAtlasCiTransport;
  mMeta: TAtlasGitHubIssueMeta;
begin
  mTransport := TFakeTransport.Create;
  mRef := mTransport;
  mTransport.Reply(cRepo + '/contents/.github/ISSUE_TEMPLATE', cListing);
  mMeta := TAtlasGitHubNewIssue.Load(Target, mRef, TAtlasGitHubMetaRequest.Create(False, nil), TStopwatch.StartNew,
    cTimeoutMs);
  Assert.AreEqual(0, Integer(Length(mMeta.Forms)));
  Assert.IsTrue(mMeta.BlankAllowed);
  Assert.AreEqual(-1, string.Join(' ', mTransport.Calls).IndexOf('/contents/'));
end;

procedure TAtlasGitHubNewIssueTests.LocalFilesSearchUpToRepositoryRoot;
var
  mFiles: IAtlasTrackerFiles;
  mFound: TArray<TAtlasIssueFormFile>;
  mTemplates, mProject: string;
begin
  mFiles := TReadOnlyFiles.Create;
  mTemplates := TPath.Combine(TPath.Combine(TPath.Combine(FDir, 'repo'), '.github'), 'ISSUE_TEMPLATE');
  mProject := TPath.Combine(TPath.Combine(TPath.Combine(FDir, 'repo'), 'src'), 'app');
  WriteFile(TPath.Combine(mTemplates, '1-fehler.yml'), 'name: Fehler');
  WriteFile(TPath.Combine(mTemplates, 'config.yml'), 'blank_issues_enabled: false');
  WriteFile(TPath.Combine(mTemplates, 'notiz.txt'), 'x');
  WriteFile(TPath.Combine(mProject, 'App.dproj'), '<Project/>');
  mFound := TAtlasGitHubNewIssue.LocalFiles(mFiles, mProject);
  Assert.AreEqual(2, Integer(Length(mFound)), 'Vorlage und config.yml, keine anderen Dateien');
  // Die Wurzel des Repositorys (.git) beendet die Suche: Vorlagen darüber zählen nicht.
  ForceDirectories(TPath.Combine(TPath.Combine(TPath.Combine(FDir, 'repo'), 'src'), '.git'));
  Assert.AreEqual(0, Integer(Length(TAtlasGitHubNewIssue.LocalFiles(mFiles, mProject))));
end;

procedure TAtlasGitHubNewIssueTests.AddToProjectsWithoutSendFailsAll;
var
  mCall: TAtlasTrackerCall;
begin
  mCall := Default(TAtlasTrackerCall);
  Assert.AreEqual('acme/4,acme/5', string.Join(',', TAtlasGitHubNewIssue.AddToProjects(mCall, TStopwatch.StartNew,
    nil, 'I_7', TArray<string>.Create('acme/4', 'acme/5'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGitHubNewIssueTests);

end.
