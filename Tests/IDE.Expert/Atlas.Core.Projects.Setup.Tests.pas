unit Atlas.Core.Projects.Setup.Tests;

// Tests für die Einrichtung eines Projekts (#759): Vorlagen für atlas.json
// (gültig gegen atlas.schema.json, eingebaute Fassung gleich den Dateien in
// Setup\Vorlagen), Ordner der Vorlagen, Ziel der Datei und Erkennung offener
// Schritte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProjectSetupTests = class
  public
    [Test]
    procedure TemplatesAreValidAgainstSchema;
    [Test]
    procedure InstalledTemplatesMatchBuiltIn;
    [Test]
    procedure SchemaUrlNamesThisRepository;
    [Test]
    procedure TemplateIdsRoundTrip;
    [Test]
    procedure FindsTemplateFolderBesideOrAbovePlugin;
    [Test]
    procedure ReadsInstalledTemplateOrFallsBack;
    [Test]
    procedure TargetBesideProjectFile;
    [Test]
    procedure FindsExistingConfig;
    [Test]
    procedure DetectsOpenSteps;
    [Test]
    procedure CompleteSetupNeedsNoCard;
    [Test]
    procedure DismissedProjectNeedsNoCard;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Setup;

/// <summary>Setup\Vorlagen des Repositorys über dem Testprogramm bzw. dem Arbeitsordner; '' ohne.</summary>
function RepoTemplates: string;
var
  mStart, mDirectory, mCandidate: string;
  mStarts: TArray<string>;
begin
  mStarts := [ExtractFileDir(ParamStr(0)), GetCurrentDir];
  for mStart in mStarts do
  begin
    mDirectory := mStart;
    while mDirectory <> '' do
    begin
      mCandidate := IncludeTrailingPathDelimiter(mDirectory) + 'Setup' + PathDelim + 'Vorlagen';
      if DirectoryExists(mCandidate) then
      begin
        Exit(mCandidate);
      end;
      if ExtractFileDir(mDirectory) = mDirectory then
      begin
        Break;
      end;
      mDirectory := ExtractFileDir(mDirectory);
    end;
  end;
  Result := '';
end;

function Facts(const AProject: string; AConfig, ABaseline, AChecked, AClean: Boolean): TAtlasSetupFacts;
begin
  Result := Default(TAtlasSetupFacts);
  Result.Project := AProject;
  Result.ConfigExists := AConfig;
  Result.BaselineExists := ABaseline;
  Result.Setup := TAtlasProjectSetup.Empty;
  Result.Setup.Known := AChecked;
  Result.Setup.Checked := AChecked;
  if AChecked and not AClean then
  begin
    Result.Setup.MissingUnitCount := 1;
  end;
end;

{ TAtlasProjectSetupTests }

procedure TAtlasProjectSetupTests.TemplatesAreValidAgainstSchema;
var
  mTemplate: TAtlasSetupTemplate;
  mIssues: TArray<string>;
  mFolder, mText: string;
begin
  mFolder := RepoTemplates;
  for mTemplate := Low(TAtlasSetupTemplate) to High(TAtlasSetupTemplate) do
  begin
    Assert.IsTrue(TAtlasProjectSetups.ValidTemplate(TAtlasProjectSetups.BuiltIn(mTemplate), AtlasSchemaJson, mIssues),
      TAtlasProjectSetups.TemplateId(mTemplate) + ': ' + string.Join('; ', mIssues));
    if mFolder = '' then
    begin
      Continue;
    end;
    mText := TFile.ReadAllText(IncludeTrailingPathDelimiter(mFolder) + TAtlasProjectSetups.TemplateFile(mTemplate),
      TEncoding.UTF8);
    Assert.IsTrue(TAtlasProjectSetups.ValidTemplate(mText, AtlasSchemaJson, mIssues),
      TAtlasProjectSetups.TemplateFile(mTemplate) + ': ' + string.Join('; ', mIssues));
  end;
  // Eine kaputte Vorlage fällt auf.
  Assert.IsFalse(TAtlasProjectSetups.ValidTemplate('{"profile": 3}', AtlasSchemaJson, mIssues));
  Assert.IsFalse(TAtlasProjectSetups.ValidTemplate('{"logLevel": "debug"}', AtlasSchemaJson, mIssues),
    'globaler Schlüssel gehört nicht in atlas.json');
end;

procedure TAtlasProjectSetupTests.InstalledTemplatesMatchBuiltIn;
var
  mTemplate: TAtlasSetupTemplate;
  mFolder, mText: string;
begin
  mFolder := RepoTemplates;
  if mFolder = '' then
  begin
    Exit;
  end;
  for mTemplate := Low(TAtlasSetupTemplate) to High(TAtlasSetupTemplate) do
  begin
    mText := TFile.ReadAllText(IncludeTrailingPathDelimiter(mFolder) + TAtlasProjectSetups.TemplateFile(mTemplate),
      TEncoding.UTF8);
    // Ohne Rücksicht auf die Zeilenenden des Checkouts.
    mText := StringReplace(mText, #13#10, #10, [rfReplaceAll]);
    Assert.AreEqual(TAtlasProjectSetups.BuiltIn(mTemplate), mText, TAtlasProjectSetups.TemplateFile(mTemplate));
  end;
end;

procedure TAtlasProjectSetupTests.SchemaUrlNamesThisRepository;
const
  cExpected = 'https://raw.githubusercontent.com/xKnockOut/Atlas-IDE-Expert/main/schemas/atlas.schema.json';
var
  mFolder, mText: string;
begin
  // Die frühere Adresse unter xKnockOut/Atlas liefert 404: Editoren fanden das Schema nicht (#1971).
  Assert.AreEqual(cExpected, TAtlasProjectSetups.cSchemaUrl);
  mFolder := RepoTemplates;
  if mFolder = '' then
  begin
    Exit;
  end;
  // Die eigene Konfiguration des Plugins nennt dieselbe Adresse wie die Vorlagen.
  mText := TFile.ReadAllText(TPath.Combine(ExtractFileDir(ExtractFileDir(mFolder)),
    TPath.Combine('Packages', TPath.Combine('Atlas.IDE.Base', 'atlas.json'))), TEncoding.UTF8);
  Assert.Contains(mText, '"$schema": "' + TAtlasProjectSetups.cSchemaUrl + '"');
end;

procedure TAtlasProjectSetupTests.TemplateIdsRoundTrip;
var
  mTemplate, mRead: TAtlasSetupTemplate;
begin
  for mTemplate := Low(TAtlasSetupTemplate) to High(TAtlasSetupTemplate) do
  begin
    Assert.IsTrue(TAtlasProjectSetups.TemplateOf(UpperCase(TAtlasProjectSetups.TemplateId(mTemplate)), mRead));
    Assert.AreEqual<TAtlasSetupTemplate>(mTemplate, mRead);
  end;
  Assert.AreEqual('atlas-legacy.json', TAtlasProjectSetups.TemplateFile(TAtlasSetupTemplate.Legacy));
  Assert.IsFalse(TAtlasProjectSetups.TemplateOf('gibtsnicht', mRead));
  Assert.AreEqual<TAtlasSetupTemplate>(TAtlasSetupTemplate.Existing, mRead, 'Vorgabe: Bestehendes Projekt');
end;

procedure TAtlasProjectSetupTests.FindsTemplateFolderBesideOrAbovePlugin;
var
  mPresent: string;
  mExists: TAtlasSetupFileExists;
begin
  mExists :=
    function(const AFileName: string): Boolean
    begin
      Result := SameText(AFileName, mPresent);
    end;
  mPresent := 'C:\Atlas\Vorlagen\atlas-existing.json';
  Assert.AreEqual('C:\Atlas\Vorlagen', TAtlasProjectSetups.TemplateFolder('C:\Atlas\Win64\', mExists));
  Assert.AreEqual('C:\Atlas\Vorlagen', TAtlasProjectSetups.TemplateFolder('C:\Atlas', mExists));
  mPresent := '';
  Assert.AreEqual('', TAtlasProjectSetups.TemplateFolder('C:\Atlas\Win64', mExists));
  Assert.AreEqual('', TAtlasProjectSetups.TemplateFolder('', mExists));
  Assert.AreEqual('', TAtlasProjectSetups.TemplateFolder('C:\Atlas', nil));
end;

procedure TAtlasProjectSetupTests.ReadsInstalledTemplateOrFallsBack;
var
  mRead: TAtlasSetupReadText;
begin
  mRead :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := SameText(AFileName, 'C:\Atlas\Vorlagen\atlas-strict.json');
      if Result then
      begin
        AText := '{"profile": "fast"}';
      end;
    end;
  Assert.AreEqual('{"profile": "fast"}', TAtlasProjectSetups.TemplateText(TAtlasSetupTemplate.NewStrict,
    'C:\Atlas\Vorlagen', mRead));
  Assert.AreEqual(TAtlasProjectSetups.BuiltIn(TAtlasSetupTemplate.Legacy),
    TAtlasProjectSetups.TemplateText(TAtlasSetupTemplate.Legacy, 'C:\Atlas\Vorlagen', mRead));
  Assert.AreEqual(TAtlasProjectSetups.BuiltIn(TAtlasSetupTemplate.Existing),
    TAtlasProjectSetups.TemplateText(TAtlasSetupTemplate.Existing, '', mRead));
  Assert.Contains(TAtlasProjectSetups.BuiltIn(TAtlasSetupTemplate.NewStrict), '"profile": "strict"');
  Assert.Contains(TAtlasProjectSetups.BuiltIn(TAtlasSetupTemplate.Existing), TAtlasProjectSetups.cSchemaUrl);
end;

procedure TAtlasProjectSetupTests.TargetBesideProjectFile;
begin
  Assert.AreEqual('C:\Projekte\Kasse\atlas.json', TAtlasProjectSetups.ConfigTarget('C:\Projekte\Kasse\Kasse.dproj'));
  Assert.AreEqual('C:\Projekte\atlas.json', TAtlasProjectSetups.ConfigTarget(' C:\Projekte\Alle.groupproj '));
  Assert.AreEqual('', TAtlasProjectSetups.ConfigTarget(''));
end;

procedure TAtlasProjectSetupTests.FindsExistingConfig;
var
  mPresent: TArray<string>;
  mExists: TAtlasSetupFileExists;
begin
  mExists :=
    function(const AFileName: string): Boolean
    var
      Each: string;
    begin
      Result := False;
      for Each in mPresent do
      begin
        if SameText(Each, AFileName) then
        begin
          Exit(True);
        end;
      end;
    end;
  mPresent := ['C:\P\delphi-lsp.json'];
  Assert.AreEqual('C:\P\delphi-lsp.json', TAtlasProjectSetups.ExistingConfig('C:\P\App.dproj', mExists));
  mPresent := ['C:\P\delphi-lsp.json', 'C:\P\atlas.json'];
  Assert.AreEqual('C:\P\atlas.json', TAtlasProjectSetups.ExistingConfig('C:\P\App.dproj', mExists));
  mPresent := ['C:\atlas.json'];
  Assert.AreEqual('', TAtlasProjectSetups.ExistingConfig('C:\P\App.dproj', mExists), 'nur neben der Projektdatei');
  Assert.AreEqual('', TAtlasProjectSetups.ExistingConfig('', mExists));
end;

procedure TAtlasProjectSetupTests.DetectsOpenSteps;
var
  mSteps: TArray<TAtlasSetupStep>;
begin
  // Neues Projekt: Schritt 1 erledigt (die Karte erscheint), alles andere offen.
  mSteps := TAtlasProjectSetups.OpenSteps(Facts('C:\P\App.dproj', False, False, False, False));
  Assert.AreEqual(3, Integer(Length(mSteps)));
  Assert.AreEqual<TAtlasSetupStep>(TAtlasSetupStep.Config, mSteps[0]);
  Assert.IsTrue(TAtlasProjectSetups.StepDone(TAtlasSetupStep.Found, Facts('C:\P\App.dproj', False, False, False,
    False)));
  Assert.IsTrue(TAtlasProjectSetups.NeedsCard(Facts('C:\P\App.dproj', False, False, False, False)));
  // atlas.json da, Baseline fehlt: Karte bleibt.
  mSteps := TAtlasProjectSetups.OpenSteps(Facts('C:\P\App.dproj', True, False, False, False));
  Assert.AreEqual(2, Integer(Length(mSteps)));
  Assert.AreEqual<TAtlasSetupStep>(TAtlasSetupStep.Baseline, mSteps[0]);
  Assert.IsTrue(TAtlasProjectSetups.NeedsCard(Facts('C:\P\App.dproj', True, False, False, False)));
  // Prüfung lief, fand aber etwas: Schritt 4 bleibt offen.
  mSteps := TAtlasProjectSetups.OpenSteps(Facts('C:\P\App.dproj', True, True, True, False));
  Assert.AreEqual(1, Integer(Length(mSteps)));
  Assert.AreEqual<TAtlasSetupStep>(TAtlasSetupStep.Paths, mSteps[0]);
  // Ohne Projekt keine Karte.
  Assert.IsFalse(TAtlasProjectSetups.NeedsCard(Facts('', False, False, False, False)));
  Assert.IsFalse(TAtlasProjectSetups.StepDone(TAtlasSetupStep.Found, Facts('', False, False, False, False)));
end;

procedure TAtlasProjectSetupTests.CompleteSetupNeedsNoCard;
var
  mDone: TAtlasSetupFacts;
begin
  mDone := Facts('C:\P\App.dproj', True, True, True, True);
  Assert.IsTrue(TAtlasProjectSetups.Complete(mDone));
  Assert.AreEqual(0, Integer(Length(TAtlasProjectSetups.OpenSteps(mDone))));
  Assert.IsFalse(TAtlasProjectSetups.NeedsCard(mDone));
end;

procedure TAtlasProjectSetupTests.DismissedProjectNeedsNoCard;
var
  mDismissed: TAtlasSetupFacts;
begin
  mDismissed := Facts('C:\P\App.dproj', False, False, False, False);
  mDismissed.Setup.Known := True;
  mDismissed.Setup.Dismissed := True;
  Assert.IsFalse(TAtlasProjectSetups.NeedsCard(mDismissed));
  Assert.IsFalse(TAtlasProjectSetups.Complete(mDismissed), 'abgewählt ist nicht eingerichtet');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectSetupTests);

end.
