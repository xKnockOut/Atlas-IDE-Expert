unit Atlas.Core.Vcs.Internals.SvnExternals.Tests;

// svn:externals (#1291): Definitionen aus propget --xml (Fixture
// Tests\Data\Svn\externals-propget.xml), beide Formate, relative Angaben,
// Peg, Kommentare, Anführungszeichen, %20; Umschreiben einzelner Zeilen;
// svnversion, Versionsgrenze 1.9, Auswahl nach Regeln und Vorgaben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSvnExternalsTests = class
  public
    [Test]
    procedure DefinitionsFromXml;
    [Test]
    procedure ParsesFormatsAndRelativeUrls;
    [Test]
    procedure RewritesOnlyOneLine;
    [Test]
    procedure VersionStateAndPinSupport;
    [Test]
    procedure RulesBeforeDefaults;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Internals.SvnExternals;

const
  cRepository = 'https://svn.firma.local/repo';
  cRootUrl = 'https://svn.firma.local/repo/Kasse/trunk';

/// <summary>Datei aus Tests\Data\&lt;AFolder&gt;, gesucht ab dem Ordner des Testprogramms aufwärts.</summary>
function Fixture(const AFolder, AName: string): string;
var
  mDirectory, mFileName: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    mFileName := TPath.Combine(mDirectory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine(AFolder, AName))));
    if TFile.Exists(mFileName) then
      Exit(TFile.ReadAllText(mFileName, TEncoding.UTF8));
    if ExtractFileDir(mDirectory) = mDirectory then
      Break;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  raise Exception.Create('Tests\Data\' + AFolder + '\' + AName + ' nicht gefunden');
end;

function Definitions: TArray<TAtlasVcsSvnExternalDefinition>;
begin
  Result := TAtlasSvnExternals.Definitions(Fixture('Svn', 'externals-propget.xml'), 'C:\Projekte\Kasse');
end;

function Externals: TArray<TAtlasVcsSvnExternal>;
begin
  Result := TAtlasSvnExternals.ParseAll(Definitions, cRootUrl, cRepository);
end;

function Find(const AItems: TArray<TAtlasVcsSvnExternal>; const AFolder: string): TAtlasVcsSvnExternal;
var
  mItem: TAtlasVcsSvnExternal;
begin
  for mItem in AItems do
    if mItem.Folder = AFolder then
      Exit(mItem);
  raise Exception.Create('External ' + AFolder + ' fehlt');
end;

{ TAtlasSvnExternalsTests }

procedure TAtlasSvnExternalsTests.DefinitionsFromXml;
var
  mDefinitions: TArray<TAtlasVcsSvnExternalDefinition>;
  mRoot: string;
begin
  mDefinitions := Definitions;
  Assert.AreEqual(2, Integer(Length(mDefinitions)));
  Assert.AreEqual('', mDefinitions[0].Owner, 'Wurzel');
  Assert.IsTrue(mDefinitions[0].Text.StartsWith('# Packages der Gruppe'#10'^/Packages/Basis/trunk Packages/Basis'),
    mDefinitions[0].Text);
  Assert.AreEqual('Sub', mDefinitions[1].Owner);
  Assert.AreEqual('^/Packages/Sub/trunk Lib'#10, mDefinitions[1].Text);
  // svn schreibt den Pfad vollständig, wenn man ihn vollständig angibt.
  mRoot := TPath.Combine(TPath.GetTempPath, 'Kasse');
  mDefinitions := TAtlasSvnExternals.Definitions('<?xml version="1.0"?><properties><target path="' +
    TPath.Combine(mRoot, 'Packages') + '"><property name="svn:externals">^/x Lib</property></target>' +
    '<target path="' + mRoot + '"><property name="svn:ignore">*.dcu</property></target></properties>', mRoot);
  Assert.AreEqual(1, Integer(Length(mDefinitions)), 'nur svn:externals');
  Assert.AreEqual('Packages', mDefinitions[0].Owner);
  Assert.AreEqual(0, Integer(Length(TAtlasSvnExternals.Definitions('<?xml version="1.0"?><properties/>', mRoot))));
end;

procedure TAtlasSvnExternalsTests.ParsesFormatsAndRelativeUrls;
var
  mItems: TArray<TAtlasVcsSvnExternal>;
  mItem: TAtlasVcsSvnExternal;
begin
  mItems := Externals;
  Assert.AreEqual(13, Integer(Length(mItems)), 'Kommentar und kaputte Zeile entfallen');
  mItem := Find(mItems, 'Packages/Basis');
  Assert.AreEqual(1, mItem.Line, 'Kommentar zählt mit');
  Assert.AreEqual('^/Packages/Basis/trunk', mItem.Url);
  Assert.AreEqual(cRepository + '/Packages/Basis/trunk', mItem.FullUrl);
  Assert.AreEqual('Packages/Basis/trunk', mItem.Source);
  Assert.IsFalse(mItem.Fixed);
  Assert.IsFalse(mItem.Foreign);
  Assert.IsFalse(mItem.OldFormat);
  Assert.IsTrue(mItem.CanBranch);
  mItem := Find(mItems, 'Packages/Kunden');
  Assert.AreEqual('4711', mItem.Revision);
  Assert.IsTrue(mItem.Fixed);
  Assert.IsFalse(mItem.CanBranch);
  mItem := Find(mItems, 'Packages/Drucken');
  Assert.AreEqual('48100', mItem.Peg, 'Peg');
  Assert.AreEqual('../../Packages/Drucken/trunk', mItem.Url);
  Assert.AreEqual('Packages/Drucken/trunk', mItem.Source, '../ relativ zum Ordner mit der Eigenschaft');
  mItem := Find(mItems, 'Packages/Mein Paket');
  Assert.AreEqual('Packages/Mein Paket/trunk', mItem.Source, 'Anführungszeichen');
  mItem := Find(mItems, 'Lieferant');
  Assert.IsTrue(mItem.Foreign);
  Assert.AreEqual('', mItem.Source);
  Assert.IsFalse(mItem.CanBranch, 'fremdes Repository nie mitverzweigen');
  mItem := Find(mItems, 'Alt');
  Assert.IsTrue(mItem.OldFormat);
  Assert.AreEqual('4000', mItem.Revision);
  Assert.AreEqual('Packages/Alt/trunk', mItem.Source);
  mItem := Find(mItems, 'Version.inc');
  Assert.AreEqual('Shared/trunk/Version.inc', mItem.Source);
  mItem.IsFile := True;
  Assert.IsFalse(mItem.CanBranch, 'Datei-External');
  mItem := Find(mItems, 'Anderes');
  Assert.AreEqual('https://svn.firma.local/Anderes/trunk', mItem.FullUrl, '^/../ = Nachbar-Repository');
  Assert.IsTrue(mItem.Foreign);
  Assert.AreEqual('Packages/Netz/trunk', Find(mItems, 'Netz').Source, '// gleiches Schema');
  Assert.AreEqual('Packages/Server/trunk', Find(mItems, 'Server').Source, '/ gleicher Server');
  Assert.AreEqual('Packages/Prozent Satz/trunk', Find(mItems, 'Prozent').Source, '%20');
  Assert.IsTrue(Find(mItems, 'Alt2').OldFormat);
  mItem := Find(mItems, 'Lib');
  Assert.AreEqual('Sub', mItem.Owner);
  Assert.AreEqual('Sub/Lib', mItem.Path);
  Assert.AreEqual(0, mItem.Line);
end;

procedure TAtlasSvnExternalsTests.RewritesOnlyOneLine;
var
  mDefinition: TAtlasVcsSvnExternalDefinition;
  mItems: TArray<TAtlasVcsSvnExternal>;
  mLine, mText: string;
  mBefore, mAfter: TArray<string>;
  mIndex: Integer;
begin
  mDefinition := Definitions[0];
  mItems := Externals;
  mLine := TAtlasSvnExternals.PinnedLine(mDefinition.Text, Find(mItems, 'Packages/Basis'), '48190');
  Assert.AreEqual('-r 48190 ^/Packages/Basis/trunk Packages/Basis', mLine);
  mText := TAtlasSvnExternals.ReplaceLine(mDefinition.Text, Find(mItems, 'Packages/Basis').Line, mLine);
  mBefore := mDefinition.Text.Split([#10]);
  mAfter := mText.Split([#10]);
  Assert.AreEqual(Integer(Length(mBefore)), Integer(Length(mAfter)));
  for mIndex := 0 to High(mBefore) do
    if mIndex <> 1 then
      Assert.AreEqual(mBefore[mIndex], mAfter[mIndex], 'Zeile ' + IntToStr(mIndex) + ' unverändert');
  Assert.AreEqual(mLine, mAfter[1]);
  // Anführungszeichen bleiben, wie sie dastehen.
  Assert.AreEqual('-r 7 "^/Packages/Mein Paket/trunk" "Packages/Mein Paket"',
    TAtlasSvnExternals.PinnedLine(mDefinition.Text, Find(mItems, 'Packages/Mein Paket'), '7'));
  // Altes Format bleibt alt.
  Assert.AreEqual('Alt2 -r7 https://svn.firma.local/repo/Packages/Alt2/trunk',
    TAtlasSvnExternals.PinnedLine(mDefinition.Text, Find(mItems, 'Alt2'), '7'));
  Assert.AreEqual('^/Packages/Basis/branches/KASSE-42 Packages/Basis',
    TAtlasSvnExternals.RetargetedLine(mDefinition.Text, Find(mItems, 'Packages/Basis'),
    'Packages/Basis/branches/KASSE-42', cRepository));
  Assert.AreEqual('Alt2 https://svn.firma.local/repo/Packages/Alt2/branches/KASSE-42',
    TAtlasSvnExternals.RetargetedLine(mDefinition.Text, Find(mItems, 'Alt2'), 'Packages/Alt2/branches/KASSE-42',
    cRepository));
  Assert.AreEqual('^/Packages/Drucken/branches/X Packages/Drucken',
    TAtlasSvnExternals.RetargetedLine(mDefinition.Text, Find(mItems, 'Packages/Drucken'),
    'Packages/Drucken/branches/X', cRepository), 'Peg entfällt');
  // Einrückung und Zeilenenden (CRLF) bleiben.
  Assert.AreEqual('  -r 3 ^/a Lib', TAtlasSvnExternals.PinnedLine('# x'#13#10'  ^/a Lib'#13#10,
    TAtlasSvnExternals.Parse(TAtlasVcsSvnExternalDefinition.Make('', '# x'#10'  ^/a Lib'#10), cRootUrl,
    cRepository)[0], '3'));
  Assert.AreEqual('a'#13#10'X'#13#10'c', TAtlasSvnExternals.ReplaceLine('a'#13#10'b'#13#10'c', 1, 'X'));
  Assert.AreEqual('a'#10'b', TAtlasSvnExternals.ReplaceLine('a'#10'b', 5, 'X'), 'Zeile fehlt');
  Assert.AreEqual('', TAtlasSvnExternals.PinnedLine('a', Find(mItems, 'Packages/Basis'), '1'));
end;

procedure TAtlasSvnExternalsTests.VersionStateAndPinSupport;
var
  mRevision: string;
  mMixed, mModified: Boolean;
begin
  Assert.IsTrue(TAtlasSvnExternals.VersionState('48190', mRevision, mMixed, mModified));
  Assert.AreEqual('48190', mRevision);
  Assert.IsFalse(mMixed);
  Assert.IsFalse(mModified);
  Assert.IsTrue(TAtlasSvnExternals.VersionState('48100:48211MS', mRevision, mMixed, mModified));
  Assert.AreEqual('48211', mRevision);
  Assert.IsTrue(mMixed);
  Assert.IsTrue(mModified);
  Assert.IsTrue(TAtlasSvnExternals.VersionState('48211P', mRevision, mMixed, mModified));
  Assert.IsFalse(mModified);
  Assert.IsFalse(TAtlasSvnExternals.VersionState('Unversioned directory', mRevision, mMixed, mModified));
  Assert.AreEqual('', mRevision);
  Assert.IsTrue(TAtlasSvnExternals.PinExternalsSupported('1.14.3'));
  Assert.IsTrue(TAtlasSvnExternals.PinExternalsSupported('1.9.0'));
  Assert.IsTrue(TAtlasSvnExternals.PinExternalsSupported('svn, version 1.10.0 (r1827917)'));
  Assert.IsFalse(TAtlasSvnExternals.PinExternalsSupported('1.8.19'));
  Assert.IsFalse(TAtlasSvnExternals.PinExternalsSupported(''));
end;

procedure TAtlasSvnExternalsTests.RulesBeforeDefaults;
var
  mItems: TArray<TAtlasVcsSvnExternal>;
  mOptions: TAtlasVcsSvnBranchOptions;
  mItem: TAtlasVcsSvnExternal;
  mAction: TAtlasVcsExternalAction;
begin
  mItems := Externals;
  mOptions := TAtlasVcsSvnBranchOptions.Default;
  Assert.IsTrue(TAtlasSvnExternals.DefaultAction(Find(mItems, 'Packages/Basis'), mOptions) =
    TAtlasVcsExternalAction.Pin, 'Vorgabe pin');
  Assert.IsTrue(TAtlasSvnExternals.DefaultAction(Find(mItems, 'Packages/Kunden'), mOptions) =
    TAtlasVcsExternalAction.Keep, 'mit Revision');
  // Regel vor Vorgabe; die längste gewinnt.
  mOptions.ExternalsRules := [TAtlasVcsExternalRule.Make('^/Packages', TAtlasVcsExternalAction.Branch),
    TAtlasVcsExternalRule.Make('^/Packages/Basis/', TAtlasVcsExternalAction.Keep),
    TAtlasVcsExternalRule.Make('https://svn.lieferant.de/komponenten', TAtlasVcsExternalAction.Branch)];
  Assert.IsTrue(TAtlasSvnExternals.DefaultAction(Find(mItems, 'Packages/Basis'), mOptions) =
    TAtlasVcsExternalAction.Keep);
  Assert.IsTrue(TAtlasSvnExternals.DefaultAction(Find(mItems, 'Packages/Mein Paket'), mOptions) =
    TAtlasVcsExternalAction.Branch);
  Assert.IsTrue(TAtlasSvnExternals.MatchRule(Find(mItems, 'Lieferant'), mOptions.ExternalsRules, mAction));
  Assert.IsTrue(TAtlasSvnExternals.DefaultAction(Find(mItems, 'Lieferant'), mOptions) =
    TAtlasVcsExternalAction.Pin, 'fremdes Repository: Regel „branch“ gilt nicht');
  Assert.IsFalse(TAtlasSvnExternals.MatchRule(Find(mItems, 'Server'),
    [TAtlasVcsExternalRule.Make('^/Packages/Serv', TAtlasVcsExternalAction.Keep)], mAction), 'ganze Pfadteile');
  // Mitverzweigen vorschlagen.
  mOptions.ExternalsRules := nil;
  mItem := Find(mItems, 'Packages/Basis');
  mItem.Modified := True;
  Assert.IsTrue(TAtlasSvnExternals.DefaultAction(mItem, mOptions) = TAtlasVcsExternalAction.Branch, 'geändert');
  mOptions.ExternalsSuggest := TAtlasVcsExternalSuggest.Never;
  Assert.IsTrue(TAtlasSvnExternals.DefaultAction(mItem, mOptions) = TAtlasVcsExternalAction.Pin);
  mOptions.ExternalsSuggest := TAtlasVcsExternalSuggest.Always;
  mItem.Modified := False;
  Assert.IsTrue(TAtlasSvnExternals.DefaultAction(mItem, mOptions) = TAtlasVcsExternalAction.Branch);
  mItem.IsFile := True;
  Assert.IsTrue(TAtlasSvnExternals.DefaultAction(mItem, mOptions) = TAtlasVcsExternalAction.Pin, 'Datei');
  // ask: keine Vorauswahl; keep wie vor #1291.
  mOptions := TAtlasVcsSvnBranchOptions.Default;
  mOptions.ExternalsOnBranch := TAtlasVcsExternalAction.Ask;
  Assert.IsTrue(TAtlasSvnExternals.DefaultAction(Find(mItems, 'Lieferant'), mOptions) =
    TAtlasVcsExternalAction.Ask);
  Assert.IsTrue(TAtlasSvnExternals.DefaultAction(Find(mItems, 'Lieferant'), TAtlasVcsSvnBranchOptions.Legacy) =
    TAtlasVcsExternalAction.Keep);
  Assert.IsTrue(TAtlasSvnExternals.Allowed(Find(mItems, 'Packages/Kunden'), TAtlasVcsExternalAction.Keep));
  Assert.IsFalse(TAtlasSvnExternals.Allowed(Find(mItems, 'Packages/Kunden'), TAtlasVcsExternalAction.Pin));
  Assert.IsFalse(TAtlasSvnExternals.Allowed(Find(mItems, 'Packages/Basis'), TAtlasVcsExternalAction.Ask));
  mOptions := TAtlasVcsSvnBranchOptions.Default;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSvnExternalsTests);

end.
