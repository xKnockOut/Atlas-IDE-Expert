unit Atlas.Common.Lsp.Completion.Hooks.Tests;

// Tests für Rückrufe und Schalter der Vervollständigung: Vorgaben ohne Zuweisung, Postfix-Optionen mit Snippets
// und eigenen Vorlagen (#188), Namensräume.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.Completion.Hooks;

type
  [TestFixture]
  TCompletionHooksTests = class
  private
    FHooks: TCompletionHooks;
  public
    /// <summary>Einmal-Belegungen vorwegnehmen; sie gehören nicht in die Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne Zuweisung: Standardeinstellungen und unscharfe Auswahl.</summary>
    [Test]
    procedure DefaultsWithoutHooks;
    /// <summary>Zugewiesene Rückrufe gelten je Dokument.</summary>
    [Test]
    procedure HooksDecidePerDocument;
    /// <summary>Postfix-Optionen bringen Snippets und eigene Vorlagen mit.</summary>
    [Test]
    procedure PostfixCarriesSnippetsAndCustomTemplates;
    /// <summary>Namensräume werden ersetzt und gelesen.</summary>
    [Test]
    procedure NamespacesRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.PostfixTemplates,
  Atlas.Common.Lsp.Completion.Postfix;

const
  cUri = 'file:///C:/P/Haupt.pas';

function PrefixMatching: TCompletionMatchingFunc;
begin
  Result :=
    function(const AUri: string): TCompletionMatching
    begin
      Result := TCompletionMatching.Fuzzy;
      if AUri = cUri then
      begin
        Result := TCompletionMatching.Prefix;
      end;
    end;
end;

function WithoutKeywords: TCompletionSettingsFunc;
begin
  Result :=
    function(const AUri: string): TCompletionSettings
    begin
      Result := TCompletionSettings.Default;
      Result.Keywords := False;
    end;
end;

function PostfixOff: TPostfixOptionsFunc;
begin
  Result :=
    function(const AUri: string): TPostfixOptions
    begin
      Result := TPostfixOptions.Default;
      Result.Enabled := False;
    end;
end;

procedure TCompletionHooksTests.WarmUpFirstUse;
begin
  Setup;
  try
    NamespacesRoundTrip;
  finally
    TearDown;
  end;
end;

procedure TCompletionHooksTests.Setup;
begin
  FHooks := TCompletionHooks.Create;
end;

procedure TCompletionHooksTests.TearDown;
begin
  FreeAndNil(FHooks);
end;

procedure TCompletionHooksTests.DefaultsWithoutHooks;
begin
  Assert.AreEqual<TCompletionMatching>(TCompletionMatching.Fuzzy, FHooks.MatchingOf(cUri));
  Assert.AreEqual(TCompletionSettings.Default.Keywords, FHooks.SettingsOf(cUri).Keywords);
  Assert.AreEqual(TPostfixOptions.Default.Enabled, FHooks.PostfixOf(cUri).Enabled);
end;

procedure TCompletionHooksTests.HooksDecidePerDocument;
begin
  FHooks.MatchingFor := PrefixMatching();
  FHooks.SettingsFor := WithoutKeywords();
  FHooks.PostfixFor := PostfixOff();
  Assert.AreEqual<TCompletionMatching>(TCompletionMatching.Prefix, FHooks.MatchingOf(cUri));
  Assert.AreEqual<TCompletionMatching>(TCompletionMatching.Fuzzy, FHooks.MatchingOf('file:///C:/P/Andere.pas'));
  Assert.IsFalse(FHooks.SettingsOf(cUri).Keywords);
  Assert.IsFalse(FHooks.PostfixOf(cUri).Enabled);
end;

procedure TCompletionHooksTests.PostfixCarriesSnippetsAndCustomTemplates;
var
  mTemplate: TPostfixTemplate;
  mOptions: TPostfixOptions;
begin
  mTemplate := Default(TPostfixTemplate);
  mTemplate.Key := 'logd';
  FHooks.SnippetSupport := True;
  FHooks.SetCustomPostfix([mTemplate]);
  mOptions := FHooks.PostfixOf(cUri);
  Assert.IsTrue(mOptions.Snippet);
  Assert.AreEqual(1, Integer(Length(mOptions.Custom)));
  Assert.AreEqual('logd', mOptions.Custom[0].Key);
  Assert.AreEqual(1, Integer(Length(FHooks.CustomPostfix)));
end;

procedure TCompletionHooksTests.NamespacesRoundTrip;
begin
  Assert.AreEqual(0, Integer(Length(FHooks.Namespaces)));
  FHooks.Namespaces := ['System', 'Vcl'];
  Assert.AreEqual('System,Vcl', string.Join(',', FHooks.Namespaces));
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionHooksTests);

end.
