unit Atlas.Core.Assistants.IdeProviders.Tests;

// Anbieter der IDE für einfache Aufgaben (#2744): ohne Namen der erste aktive mit Anweisung oder Chat, mit Namen
// nur dieser; der eigene Eintrag „Atlas (…)“ wird nie gewählt (#2745).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasIdeAiProvidersTests = class
  public
    [Test]
    procedure EmptyNamePicksFirstUsable;
    [Test]
    procedure NamedProviderIsPickedIgnoringCase;
    [Test]
    procedure MissingOrDisabledNamedProviderPicksNothing;
    [Test]
    procedure OwnEntryIsNeverPicked;
    [Test]
    procedure ProviderWithoutTextFeatureIsNotUsable;
    [Test]
    procedure OwnNameIsRecognized;
  end;

implementation

uses
  Atlas.Core.Assistants.Contract.IdeAi,
  Atlas.Core.Assistants.IdeProviders;

function Sample: TArray<TAtlasIdeAiProvider>;
begin
  Result := TArray<TAtlasIdeAiProvider>.Create(
    TAtlasIdeAiProvider.Make('Atlas (lokal)', True, [TAtlasIdeAiFeature.Chat, TAtlasIdeAiFeature.Instruction]),
    TAtlasIdeAiProvider.Make('Ollama', False, [TAtlasIdeAiFeature.Chat]),
    TAtlasIdeAiProvider.Make('Bilder', True, [TAtlasIdeAiFeature.ListModels]),
    TAtlasIdeAiProvider.Make('OpenAI', True, [TAtlasIdeAiFeature.Chat, TAtlasIdeAiFeature.Instruction]),
    TAtlasIdeAiProvider.Make('Gemini', True, [TAtlasIdeAiFeature.Chat]));
end;

{ TAtlasIdeAiProvidersTests }

procedure TAtlasIdeAiProvidersTests.EmptyNamePicksFirstUsable;
var
  mProvider: TAtlasIdeAiProvider;
begin
  Assert.IsTrue(TAtlasIdeAiProviders.Pick(Sample, '  ', mProvider));
  Assert.AreEqual('OpenAI', mProvider.Name, 'Atlas, ausgeschaltete und ohne Text übersprungen');
end;

procedure TAtlasIdeAiProvidersTests.NamedProviderIsPickedIgnoringCase;
var
  mProvider: TAtlasIdeAiProvider;
begin
  Assert.IsTrue(TAtlasIdeAiProviders.Pick(Sample, 'gemini', mProvider));
  Assert.AreEqual('Gemini', mProvider.Name);
end;

procedure TAtlasIdeAiProvidersTests.MissingOrDisabledNamedProviderPicksNothing;
var
  mProvider: TAtlasIdeAiProvider;
begin
  Assert.IsFalse(TAtlasIdeAiProviders.Pick(Sample, 'Mistral', mProvider), 'fehlt');
  Assert.IsFalse(TAtlasIdeAiProviders.Pick(Sample, 'Ollama', mProvider), 'aus: kein stiller Wechsel');
  Assert.AreEqual('', mProvider.Name);
end;

procedure TAtlasIdeAiProvidersTests.OwnEntryIsNeverPicked;
var
  mProvider: TAtlasIdeAiProvider;
begin
  Assert.IsFalse(TAtlasIdeAiProviders.Pick(Sample, 'Atlas (lokal)', mProvider), 'keine Schleife');
  Assert.IsFalse(TAtlasIdeAiProviders.Pick(TArray<TAtlasIdeAiProvider>.Create(
    TAtlasIdeAiProvider.Make('Atlas (Anthropic-API)', True, [TAtlasIdeAiFeature.Instruction])), '', mProvider));
end;

procedure TAtlasIdeAiProvidersTests.ProviderWithoutTextFeatureIsNotUsable;
begin
  Assert.IsFalse(TAtlasIdeAiProvider.Make('Bilder', True, [TAtlasIdeAiFeature.ListModels]).Usable);
  Assert.IsFalse(TAtlasIdeAiProvider.Make('Aus', False, [TAtlasIdeAiFeature.Chat]).Usable);
  Assert.IsTrue(TAtlasIdeAiProvider.Make('Chat', True, [TAtlasIdeAiFeature.Chat]).Usable);
end;

procedure TAtlasIdeAiProvidersTests.OwnNameIsRecognized;
begin
  Assert.AreEqual('Atlas (lokal)', TAtlasIdeAiProviders.OwnName('lokal'));
  Assert.IsTrue(TAtlasIdeAiProviders.IsOwn('atlas (OpenAI-kompatibel)'));
  Assert.IsFalse(TAtlasIdeAiProviders.IsOwn('Atlassian'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIdeAiProvidersTests);

end.
