unit Shell.Composition.DocumentEvents.Tests;

// Ereignisse des Dokumentspeichers auf einem Kern ohne Ordner: Öffnen fragt Tipp-Pause und abgeleitete Ordner,
// Ändern nur die Tipp-Pause.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Shell.Composition.Core,
  Shell.Composition.DocumentEvents;

type
  [TestFixture]
  TShellDocumentEventsTests = class
  private
    FDocuments: IDocumentStore;
    FCore: TShellCore;
    FFileChangesAsked: Integer;
    FDeriveAsked: Integer;
    function NewServices: TShellDocumentEventServices;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Öffnen fragt Tipp-Pause und abgeleitete Ordner je einmal.</summary>
    [Test]
    procedure OpenAsksFileChangesAndDerive;
    /// <summary>Ändern fragt nur die Tipp-Pause.</summary>
    [Test]
    procedure ChangeAsksOnlyFileChanges;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Providers.Logger,
  Shell.CrashCases,
  Shell.Composition.Compile,
  Shell.Composition.FileChanges;

const
  cFile = 'C:\Projekt\Offen.pas';

function NoIndex: ISymbolIndex;
begin
  Result := nil;
end;

function NoSelection(const AOrigin: string): string;
begin
  Result := '';
end;

function NoActive: string;
begin
  Result := '';
end;

function NoCrashCases: TShellCrashCases;
begin
  Result := nil;
end;

function NoCompile: TShellCompileHost;
begin
  Result := nil;
end;

procedure TShellDocumentEventsTests.Setup;
var
  mServices: TShellCoreServices;
begin
  FDocuments := TDocumentStore.Create;
  mServices := Default(TShellCoreServices);
  mServices.Logger := TLogger.Create;
  mServices.Documents := FDocuments;
  mServices.Index := NoIndex;
  mServices.SelectedProject := NoSelection;
  mServices.ActiveProject := NoActive;
  FCore := TShellCore.Create(mServices);
  FFileChangesAsked := 0;
  FDeriveAsked := 0;
  TShellDocumentEvents.Attach(FDocuments, NewServices);
end;

procedure TShellDocumentEventsTests.TearDown;
begin
  FDocuments := nil;
  FCore.FreeWorkspaces;
  FreeAndNil(FCore);
end;

function TShellDocumentEventsTests.NewServices: TShellDocumentEventServices;
begin
  Result := Default(TShellDocumentEventServices);
  Result.Core :=
    function: TShellCore
    begin
      Result := FCore;
    end;
  Result.CrashCases := NoCrashCases;
  Result.Compile := NoCompile;
  Result.FileChanges :=
    function: TShellFileChanges
    begin
      Inc(FFileChangesAsked);
      Result := nil;
    end;
  Result.DeriveWorkspaces :=
    function: Boolean
    begin
      Inc(FDeriveAsked);
      Result := False;
    end;
end;

procedure TShellDocumentEventsTests.OpenAsksFileChangesAndDerive;
begin
  FDocuments.Open(TDocumentUris.FromPath(cFile), 'delphi', 1, 'unit Offen;');
  Assert.AreEqual(1, FFileChangesAsked);
  Assert.AreEqual(1, FDeriveAsked);
end;

procedure TShellDocumentEventsTests.ChangeAsksOnlyFileChanges;
var
  mUri: string;
begin
  mUri := TDocumentUris.FromPath(cFile);
  FDocuments.Open(mUri, 'delphi', 1, 'unit Offen;');
  FFileChangesAsked := 0;
  FDeriveAsked := 0;
  FDocuments.Change(mUri, 2, TArray<TTextChange>.Create(TTextChange.Full('unit Offen; interface')));
  Assert.AreEqual(1, FFileChangesAsked);
  Assert.AreEqual(0, FDeriveAsked);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellDocumentEventsTests);

end.
