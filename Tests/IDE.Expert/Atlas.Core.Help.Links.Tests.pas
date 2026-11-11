unit Atlas.Core.Help.Links.Tests;

// Ziele der F1-Hilfe (#1886): Regel, Einstellung und Fenster in beiden Sprachen, Meldungen des Compilers ohne Seite,
// Adresse zum Versionstag, Seiten der lokalen Doku, Ordner Doku neben dem Plugin und Weiterleitung mit Anker.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Help')]
  TAtlasHelpLinksTests = class
  public
    [Test]
    procedure RulePageInBothLanguages;
    [Test]
    procedure CompilerMessagesHaveNoPage;
    [Test]
    procedure SettingAnchorFromKey;
    [Test]
    procedure WindowPageAndAnchor;
    [Test]
    procedure UnknownWindowHasNoPage;
    [Test]
    procedure OptionsPageWithoutAnchor;
    [Test]
    procedure EveryWindowOnce;
    [Test]
    procedure OnlineUrlUsesVersionTag;
    [Test]
    procedure LocalPagesMatchBuildDocs;
    [Test]
    procedure LocalFolderNextToPluginOrAbove;
    [Test]
    procedure LocalUrlKeepsAnchor;
    [Test]
    procedure RedirectEscapesUrl;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Help.Links;

procedure TAtlasHelpLinksTests.RulePageInBothLanguages;
var
  mTarget: TAtlasHelpTarget;
begin
  Assert.IsTrue(TAtlasHelpLinks.Rule('pair-without-finally', False, mTarget));
  Assert.AreEqual('docs/Regeln.md', mTarget.Path);
  Assert.AreEqual('pair-without-finally', mTarget.Anchor);
  Assert.IsTrue(TAtlasHelpLinks.Rule(' pair-without-finally ', True, mTarget));
  Assert.AreEqual('docs/en/Rules.md', mTarget.Path);
  Assert.AreEqual('pair-without-finally', mTarget.Anchor, 'ohne Leerraum');
  Assert.IsFalse(TAtlasHelpLinks.Rule('', False, mTarget), 'leer');
end;

procedure TAtlasHelpLinksTests.CompilerMessagesHaveNoPage;
var
  mTarget: TAtlasHelpTarget;
begin
  Assert.IsFalse(TAtlasHelpLinks.Rule('E2003', False, mTarget));
  Assert.IsFalse(TAtlasHelpLinks.Rule('w1000', False, mTarget));
  Assert.IsFalse(TAtlasHelpLinks.Rule('H2443', True, mTarget));
  Assert.IsTrue(TAtlasHelpLinks.Rule('E20031', False, mTarget), 'keine Meldungsnummer');
  Assert.IsTrue(TAtlasHelpLinks.Rule('syntax', False, mTarget));
end;

procedure TAtlasHelpLinksTests.SettingAnchorFromKey;
var
  mTarget: TAtlasHelpTarget;
begin
  Assert.IsTrue(TAtlasHelpLinks.Setting('editor.minimap', False, mTarget));
  Assert.AreEqual('docs/Einstellungen.md', mTarget.Path);
  Assert.AreEqual('setting-editor.minimap', mTarget.Anchor);
  Assert.IsTrue(TAtlasHelpLinks.Setting('help.source', True, mTarget));
  Assert.AreEqual('docs/en/Settings.md', mTarget.Path);
  Assert.IsFalse(TAtlasHelpLinks.Setting(' ', False, mTarget));
end;

procedure TAtlasHelpLinksTests.WindowPageAndAnchor;
var
  mTarget: TAtlasHelpTarget;
begin
  Assert.IsTrue(TAtlasHelpLinks.Window('AtlasProblems', False, mTarget));
  Assert.AreEqual('docs/features/de/Code-Analyse.md', mTarget.Path);
  Assert.AreEqual('window-atlasproblems', mTarget.Anchor);
  Assert.IsTrue(TAtlasHelpLinks.Window('atlasproblems', True, mTarget), 'Groß- und Kleinschreibung egal');
  Assert.AreEqual('docs/features/en/Code-analysis.md', mTarget.Path);
  Assert.AreEqual('window-atlasproblems', mTarget.Anchor);
end;

procedure TAtlasHelpLinksTests.UnknownWindowHasNoPage;
var
  mTarget: TAtlasHelpTarget;
begin
  Assert.IsFalse(TAtlasHelpLinks.Window('FremdesFenster', False, mTarget));
  Assert.AreEqual('', mTarget.Path);
end;

procedure TAtlasHelpLinksTests.OptionsPageWithoutAnchor;
var
  mTarget: TAtlasHelpTarget;
begin
  Assert.IsTrue(TAtlasHelpLinks.Window(TAtlasHelpLinks.cOptionsWindow, False, mTarget));
  Assert.AreEqual('docs/features/de/Einstellungen.md', mTarget.Path);
  Assert.AreEqual('', mTarget.Anchor, 'Seitenanfang');
  Assert.AreEqual('AtlasOptions', TAtlasHelpLinks.cOptionsWindow, 'wie TAtlasIdeHelp.cOptionsWindow in Base');
end;

procedure TAtlasHelpLinksTests.EveryWindowOnce;
var
  mSeen: TDictionary<string, Boolean>;
  mWindow: TAtlasHelpWindow;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mWindow in TAtlasHelpLinks.Windows do
    begin
      Assert.IsFalse(mSeen.ContainsKey(LowerCase(mWindow.Id)), mWindow.Id + ' doppelt');
      mSeen.Add(LowerCase(mWindow.Id), True);
      Assert.AreNotEqual('', mWindow.German, mWindow.Id);
      Assert.AreNotEqual('', mWindow.English, mWindow.Id);
    end;
    Assert.IsTrue(mSeen.Count >= 18, 'alle Dockfenster von Base und Modulen');
  finally
    mSeen.Free;
  end;
end;

procedure TAtlasHelpLinksTests.OnlineUrlUsesVersionTag;
var
  mTarget: TAtlasHelpTarget;
begin
  TAtlasHelpLinks.Rule('pair-without-finally', False, mTarget);
  Assert.AreEqual('https://github.com/xKnockOut/Atlas-IDE-Expert/blob/v2.1.0/docs/Regeln.md#pair-without-finally',
    TAtlasHelpLinks.OnlineUrl(mTarget, '2.1.0'));
  TAtlasHelpLinks.Window(TAtlasHelpLinks.cOptionsWindow, True, mTarget);
  Assert.AreEqual('https://github.com/xKnockOut/Atlas-IDE-Expert/blob/main/docs/features/en/Settings.md',
    TAtlasHelpLinks.OnlineUrl(mTarget, ''), 'ohne Version main, ohne Anker kein #');
end;

procedure TAtlasHelpLinksTests.LocalPagesMatchBuildDocs;
begin
  Assert.AreEqual('Regeln.html', TAtlasHelpLinks.LocalPage('docs/Regeln.md'));
  Assert.AreEqual('Einstellungen.html', TAtlasHelpLinks.LocalPage('docs/Einstellungen.md'));
  Assert.AreEqual('en-Rules.html', TAtlasHelpLinks.LocalPage('docs/en/Rules.md'));
  Assert.AreEqual('en-Settings.html', TAtlasHelpLinks.LocalPage('docs/en/Settings.md'));
  Assert.AreEqual('Funktion-Code-Analyse.html', TAtlasHelpLinks.LocalPage('docs/features/de/Code-Analyse.md'));
  Assert.AreEqual('Feature-Code-analysis.html', TAtlasHelpLinks.LocalPage('docs\features\en\Code-analysis.md'));
  Assert.AreEqual('', TAtlasHelpLinks.LocalPage('docs/Architektur.md'), 'nicht in der lokalen Doku');
end;

procedure TAtlasHelpLinksTests.LocalFolderNextToPluginOrAbove;
var
  mFiles: TArray<string>;
  mExists: TFunc<string, Boolean>;
  mPlugin: string;
begin
  mExists :=
    function(AFileName: string): Boolean
    var
      mFile: string;
    begin
      Result := False;
      for mFile in mFiles do
      begin
        Result := Result or SameText(mFile, AFileName);
      end;
    end;
  mPlugin := IncludeTrailingPathDelimiter('Atlas') + 'Win64';
  mFiles := [IncludeTrailingPathDelimiter('Atlas') + 'Doku' + PathDelim + 'index.html'];
  Assert.AreEqual(IncludeTrailingPathDelimiter('Atlas') + 'Doku' + PathDelim,
    TAtlasHelpLinks.LocalFolder(mPlugin, mExists), 'eine Ebene über Win64');
  mFiles := [IncludeTrailingPathDelimiter(mPlugin) + 'Doku' + PathDelim + 'index.html'];
  Assert.AreEqual(IncludeTrailingPathDelimiter(mPlugin) + 'Doku' + PathDelim,
    TAtlasHelpLinks.LocalFolder(mPlugin, mExists), 'neben der BPL');
  mFiles := nil;
  Assert.AreEqual('', TAtlasHelpLinks.LocalFolder(mPlugin, mExists), 'ohne Doku');
  Assert.AreEqual('', TAtlasHelpLinks.LocalFolder('', mExists));
end;

procedure TAtlasHelpLinksTests.LocalUrlKeepsAnchor;
begin
  Assert.AreEqual('file:///C:/Program%20Files/Atlas/Doku/Regeln.html#pair-without-finally',
    TAtlasHelpLinks.LocalUrl('C:\Program Files\Atlas\Doku\', 'Regeln.html', 'pair-without-finally'));
  Assert.AreEqual('file:///opt/atlas/Doku/index.html', TAtlasHelpLinks.LocalUrl('/opt/atlas/Doku/', 'index.html',
    ''));
end;

procedure TAtlasHelpLinksTests.RedirectEscapesUrl;
var
  mHtml: string;
begin
  mHtml := TAtlasHelpLinks.RedirectHtml('file:///C:/A&B/"x".html#a');
  Assert.Contains(mHtml, 'url=file:///C:/A&amp;B/&quot;x&quot;.html#a');
  Assert.Contains(mHtml, 'http-equiv="refresh"');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasHelpLinksTests);

end.
