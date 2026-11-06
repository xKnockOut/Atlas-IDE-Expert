unit Shell.Composition.Directives.Tests;

// Direktiven je Datei: ohne Arbeitsbereich keine Symbole und kein Build-Ziel, die Kontexte für Hover und
// Compilerschalter nennen trotzdem die Datei und suchen Includes im Ordner der Datei.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings,
  Shell.Composition.Directives;

type
  [TestFixture]
  TShellDirectivesTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
    FDirectives: TShellDirectives;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne Arbeitsbereich: keine Symbole, auch nicht für die uses-Suche.</summary>
    [Test]
    procedure NoWorkspaceNoDefines;
    /// <summary>Ohne Projekt kein Build-Ziel.</summary>
    [Test]
    procedure NoProjectNoBuildTarget;
    /// <summary>Hover-Kontext ohne Symbole nennt die Datei und hat einen Include-Resolver.</summary>
    [Test]
    procedure ConditionalContextWithoutDefines;
    /// <summary>Schalterkontext ohne Projekt nennt die Datei und keine Herkunft.</summary>
    [Test]
    procedure CompilerSwitchesWithoutProject;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Lsp.ConditionalSymbols,
  Atlas.Common.Lsp.CompilerSwitches;

const
  cFile = 'C:\Projekt\A.pas';

function NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function NoSelection(const AOrigin: string): string;
begin
  Result := '';
end;

function NoActive: string;
begin
  Result := '';
end;

function NoLanguageLevel(const AUri: string): string;
begin
  Result := '';
end;

procedure TShellDirectivesTests.Setup;
var
  mRegistry: TShellWorkspaceRegistryServices;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mRegistry);
  FSettings := TShellSettings.Create(FRegistry, NoLanguageLevel);
  FDirectives := TShellDirectives.Create(FRegistry, FSettings);
end;

procedure TShellDirectivesTests.TearDown;
begin
  FreeAndNil(FDirectives);
  FreeAndNil(FSettings);
  FreeAndNil(FRegistry);
end;

procedure TShellDirectivesTests.NoWorkspaceNoDefines;
var
  mDefines: TArray<string>;
begin
  Assert.IsFalse(FDirectives.Defines()(TDocumentUris.FromPath(cFile), mDefines));
  Assert.AreEqual(0, Integer(Length(mDefines)));
  Assert.IsFalse(FDirectives.TreeDefines()(TDocumentUris.FromPath(cFile), mDefines));
  Assert.AreEqual(0, Integer(Length(FDirectives.UsesDefines()(cFile))));
end;

procedure TShellDirectivesTests.NoProjectNoBuildTarget;
var
  mPlatform, mConfig: string;
begin
  Assert.IsFalse(FDirectives.BuildTarget()(TDocumentUris.FromPath(cFile), mPlatform, mConfig));
  Assert.AreEqual('', mPlatform);
  Assert.AreEqual('', mConfig);
end;

procedure TShellDirectivesTests.ConditionalContextWithoutDefines;
var
  mContext: TConditionalContext;
  mResolver: TIncludeResolver;
begin
  mContext := FDirectives.ConditionalContext()(TDocumentUris.FromPath(cFile));
  Assert.AreEqual(TDocumentUris.ToPath(TDocumentUris.FromPath(cFile)), mContext.FileName);
  Assert.IsFalse(mContext.HasDefines);
  Assert.AreEqual(0, Integer(Length(mContext.Sources)));
  mResolver := FDirectives.IncludeResolver(TDocumentUris.FromPath(cFile));
  Assert.IsTrue(Assigned(mResolver));
  Assert.IsTrue(Assigned(FDirectives.TreeIncludes()(TDocumentUris.FromPath(cFile))));
end;

procedure TShellDirectivesTests.CompilerSwitchesWithoutProject;
var
  mContext: TCompilerSwitchContext;
begin
  mContext := FDirectives.CompilerSwitchContext()(TDocumentUris.FromPath(cFile));
  Assert.AreEqual(TDocumentUris.ToPath(TDocumentUris.FromPath(cFile)), mContext.FileName);
  Assert.IsFalse(mContext.HasProject);
  Assert.AreEqual(0, Integer(Length(mContext.Input.DefineOrigins)));
end;

initialization
  TDUnitX.RegisterTestFixture(TShellDirectivesTests);

end.
