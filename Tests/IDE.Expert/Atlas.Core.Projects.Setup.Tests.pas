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
  Start, Directory, Candidate: string;
  Starts: TArray<string>;
begin
  Starts := [ExtractFileDir(ParamStr(0)), GetCurrentDir];
  for Start in Starts do
  begin
    Directory := Start;
    while Directory <> '' do
    begin
      Candidate := IncludeTrailingPathDelimiter(Directory) + 'Setup' + PathDelim + 'Vorlagen';
      if DirectoryExists(Candidate) then
        Exit(Candidate);
      if ExtractFileDir(Directory) = Directory then
        Break;
      Directory := ExtractFileDir(Directory);
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
    Result.Setup.MissingUnitCount := 1;
end;

{ TAtlasProjectSetupTests }

procedure TAtlasProjectSetupTests.TemplatesAreValidAgainstSchema;
var
  Template: TAtlasSetupTemplate;
  Issues: TArray<string>;
  Folder, Text: string;
begin
  Folder := RepoTemplates;
  for Template := Low(TAtlasSetupTemplate) to High(TAtlasSetupTemplate) do
  begin
    Assert.IsTrue(TAtlasProjectSetups.ValidTemplate(TAtlasProjectSetups.BuiltIn(Template), AtlasSchemaJson, Issues),
      TAtlasProjectSetups.TemplateId(Template) + ': ' + string.Join('; ', Issues));
    if Folder = '' then
      Continue;
    Text := TFile.ReadAllText(IncludeTrailingPathDelimiter(Folder) + TAtlasProjectSetups.TemplateFile(Template),
      TEncoding.UTF8);
    Assert.IsTrue(TAtlasProjectSetups.ValidTemplate(Text, AtlasSchemaJson, Issues),
      TAtlasProjectSetups.TemplateFile(Template) + ': ' + string.Join('; ', Issues));
  end;
  // Eine kaputte Vorlage fällt auf.
  Assert.IsFalse(TAtlasProjectSetups.ValidTemplate('{"profile": 3}', AtlasSchemaJson, Issues));
  Assert.IsFalse(TAtlasProjectSetups.ValidTemplate('{"logLevel": "debug"}', AtlasSchemaJson, Issues),
    'globaler Schlüssel gehört nicht in atlas.json');
end;

procedure TAtlasProjectSetupTests.InstalledTemplatesMatchBuiltIn;
var
  Template: TAtlasSetupTemplate;
  Folder, Text: string;
begin
  Folder := RepoTemplates;
  if Folder = '' then
    Exit;
  for Template := Low(TAtlasSetupTemplate) to High(TAtlasSetupTemplate) do
  begin
    Text := TFile.ReadAllText(IncludeTrailingPathDelimiter(Folder) + TAtlasProjectSetups.TemplateFile(Template),
      TEncoding.UTF8);
    // Ohne Rücksicht auf die Zeilenenden des Checkouts.
    Text := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
    Assert.AreEqual(TAtlasProjectSetups.BuiltIn(Template), Text, TAtlasProjectSetups.TemplateFile(Template));
  end;
end;

procedure TAtlasProjectSetupTests.TemplateIdsRoundTrip;
var
  Template, Read: TAtlasSetupTemplate;
begin
  for Template := Low(TAtlasSetupTemplate) to High(TAtlasSetupTemplate) do
  begin
    Assert.IsTrue(TAtlasProjectSetups.TemplateOf(UpperCase(TAtlasProjectSetups.TemplateId(Template)), Read));
    Assert.IsTrue(Read = Template);
  end;
  Assert.AreEqual('atlas-legacy.json', TAtlasProjectSetups.TemplateFile(TAtlasSetupTemplate.Legacy));
  Assert.IsFalse(TAtlasProjectSetups.TemplateOf('gibtsnicht', Read));
  Assert.IsTrue(Read = TAtlasSetupTemplate.Existing, 'Vorgabe: Bestehendes Projekt');
end;

procedure TAtlasProjectSetupTests.FindsTemplateFolderBesideOrAbovePlugin;
var
  Present: string;
  Exists: TAtlasSetupFileExists;
begin
  Exists :=
    function(const AFileName: string): Boolean
    begin
      Result := SameText(AFileName, Present);
    end;
  Present := 'C:\Atlas\Vorlagen\atlas-existing.json';
  Assert.AreEqual('C:\Atlas\Vorlagen', TAtlasProjectSetups.TemplateFolder('C:\Atlas\Win64\', Exists));
  Assert.AreEqual('C:\Atlas\Vorlagen', TAtlasProjectSetups.TemplateFolder('C:\Atlas', Exists));
  Present := '';
  Assert.AreEqual('', TAtlasProjectSetups.TemplateFolder('C:\Atlas\Win64', Exists));
  Assert.AreEqual('', TAtlasProjectSetups.TemplateFolder('', Exists));
  Assert.AreEqual('', TAtlasProjectSetups.TemplateFolder('C:\Atlas', nil));
end;

procedure TAtlasProjectSetupTests.ReadsInstalledTemplateOrFallsBack;
var
  Read: TAtlasSetupReadText;
begin
  Read :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := SameText(AFileName, 'C:\Atlas\Vorlagen\atlas-strict.json');
      if Result then
        AText := '{"profile": "fast"}';
    end;
  Assert.AreEqual('{"profile": "fast"}', TAtlasProjectSetups.TemplateText(TAtlasSetupTemplate.NewStrict,
    'C:\Atlas\Vorlagen', Read));
  Assert.AreEqual(TAtlasProjectSetups.BuiltIn(TAtlasSetupTemplate.Legacy),
    TAtlasProjectSetups.TemplateText(TAtlasSetupTemplate.Legacy, 'C:\Atlas\Vorlagen', Read));
  Assert.AreEqual(TAtlasProjectSetups.BuiltIn(TAtlasSetupTemplate.Existing),
    TAtlasProjectSetups.TemplateText(TAtlasSetupTemplate.Existing, '', Read));
  Assert.Contains(TAtlasProjectSetups.BuiltIn(TAtlasSetupTemplate.NewStrict), '"profile": "strict"');
  Assert.Contains(TAtlasProjectSetups.BuiltIn(TAtlasSetupTemplate.Existing), TAtlasProjectSetups.SchemaUrl);
end;

procedure TAtlasProjectSetupTests.TargetBesideProjectFile;
begin
  Assert.AreEqual('C:\Projekte\Kasse\atlas.json', TAtlasProjectSetups.ConfigTarget('C:\Projekte\Kasse\Kasse.dproj'));
  Assert.AreEqual('C:\Projekte\atlas.json', TAtlasProjectSetups.ConfigTarget(' C:\Projekte\Alle.groupproj '));
  Assert.AreEqual('', TAtlasProjectSetups.ConfigTarget(''));
end;

procedure TAtlasProjectSetupTests.FindsExistingConfig;
var
  Present: TArray<string>;
  Exists: TAtlasSetupFileExists;
begin
  Exists :=
    function(const AFileName: string): Boolean
    var
      Each: string;
    begin
      Result := False;
      for Each in Present do
        if SameText(Each, AFileName) then
          Exit(True);
    end;
  Present := ['C:\P\delphi-lsp.json'];
  Assert.AreEqual('C:\P\delphi-lsp.json', TAtlasProjectSetups.ExistingConfig('C:\P\App.dproj', Exists));
  Present := ['C:\P\delphi-lsp.json', 'C:\P\atlas.json'];
  Assert.AreEqual('C:\P\atlas.json', TAtlasProjectSetups.ExistingConfig('C:\P\App.dproj', Exists));
  Present := ['C:\atlas.json'];
  Assert.AreEqual('', TAtlasProjectSetups.ExistingConfig('C:\P\App.dproj', Exists), 'nur neben der Projektdatei');
  Assert.AreEqual('', TAtlasProjectSetups.ExistingConfig('', Exists));
end;

procedure TAtlasProjectSetupTests.DetectsOpenSteps;
var
  Steps: TArray<TAtlasSetupStep>;
begin
  // Neues Projekt: Schritt 1 erledigt (die Karte erscheint), alles andere offen.
  Steps := TAtlasProjectSetups.OpenSteps(Facts('C:\P\App.dproj', False, False, False, False));
  Assert.AreEqual(3, Integer(Length(Steps)));
  Assert.IsTrue(Steps[0] = TAtlasSetupStep.Config);
  Assert.IsTrue(TAtlasProjectSetups.StepDone(TAtlasSetupStep.Found, Facts('C:\P\App.dproj', False, False, False,
    False)));
  Assert.IsTrue(TAtlasProjectSetups.NeedsCard(Facts('C:\P\App.dproj', False, False, False, False)));
  // atlas.json da, Baseline fehlt: Karte bleibt.
  Steps := TAtlasProjectSetups.OpenSteps(Facts('C:\P\App.dproj', True, False, False, False));
  Assert.AreEqual(2, Integer(Length(Steps)));
  Assert.IsTrue(Steps[0] = TAtlasSetupStep.Baseline);
  Assert.IsTrue(TAtlasProjectSetups.NeedsCard(Facts('C:\P\App.dproj', True, False, False, False)));
  // Prüfung lief, fand aber etwas: Schritt 4 bleibt offen.
  Steps := TAtlasProjectSetups.OpenSteps(Facts('C:\P\App.dproj', True, True, True, False));
  Assert.AreEqual(1, Integer(Length(Steps)));
  Assert.IsTrue(Steps[0] = TAtlasSetupStep.Paths);
  // Ohne Projekt keine Karte.
  Assert.IsFalse(TAtlasProjectSetups.NeedsCard(Facts('', False, False, False, False)));
  Assert.IsFalse(TAtlasProjectSetups.StepDone(TAtlasSetupStep.Found, Facts('', False, False, False, False)));
end;

procedure TAtlasProjectSetupTests.CompleteSetupNeedsNoCard;
var
  Done: TAtlasSetupFacts;
begin
  Done := Facts('C:\P\App.dproj', True, True, True, True);
  Assert.IsTrue(TAtlasProjectSetups.Complete(Done));
  Assert.AreEqual(0, Integer(Length(TAtlasProjectSetups.OpenSteps(Done))));
  Assert.IsFalse(TAtlasProjectSetups.NeedsCard(Done));
end;

procedure TAtlasProjectSetupTests.DismissedProjectNeedsNoCard;
var
  Dismissed: TAtlasSetupFacts;
begin
  Dismissed := Facts('C:\P\App.dproj', False, False, False, False);
  Dismissed.Setup.Known := True;
  Dismissed.Setup.Dismissed := True;
  Assert.IsFalse(TAtlasProjectSetups.NeedsCard(Dismissed));
  Assert.IsFalse(TAtlasProjectSetups.Complete(Dismissed), 'abgewählt ist nicht eingerichtet');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectSetupTests);

end.
