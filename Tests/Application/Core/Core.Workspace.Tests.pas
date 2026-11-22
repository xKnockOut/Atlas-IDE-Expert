unit Core.Workspace.Tests;

// Reload nur im Thread der Nachrichtenschleife; Bereitschaft für
// Prüfungen ohne Projekt (#1220).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreWorkspaceTests = class
  public
    [Test]
    procedure ReloadOutsideLoopThreadRaises;
    /// <summary>Einheitliche Wahl des Arbeitsbereichs: Treffer, sonst der einzige, sonst keiner.</summary>
    [Test]
    procedure ChooseFallsBackToSingleWorkspace;
    /// <summary>Unit in mehreren Projekten (#1112): Gleiche Art bleibt, verschiedene Arten ergeben Unknown,
    /// Projekte ohne die Datei zählen nicht.</summary>
    [Test]
    procedure MergeRuleProjectsKeepsOnlyUnambiguousKind;
    /// <summary>Ordner ohne Projekt (#1220): Nach dem Aufbau wartet keine Prüfung mehr auf ein Projekt, vorher
    /// schon.</summary>
    [Test]
    procedure WorkspaceWithoutProjectIsRuleReady;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.JsonRpc.StreamTransport,
  System.Generics.Collections,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Core.Workspace.Setup,
  Core.Workspace.RuleProjects,
  Atlas.Common.Localization.Texts,
  Core.Workspace,
  Shell.Composition.Platform;

function NewWorkspace(const AName: string): TCoreWorkspace;
begin
  Result := TCoreWorkspace.Create('', AName, TCoreWorkspaceServices.Create(TDocumentStore.Create,
    TJsonRpcStreamTransport.Create(nil, TBytesStream.Create, True), TLogger.Create, TSymbolIndex.Create,
    'atlas-test-index', TShellPlatformAdapters.WorkspaceFactories));
end;

{ TCoreWorkspaceTests }

procedure TCoreWorkspaceTests.ReloadOutsideLoopThreadRaises;
var
  mWorkspace: TCoreWorkspace;
  mWorker: TThread;
  mRaised: string;
begin
  mRaised := '';
  mWorkspace := NewWorkspace('Test');
  try
    mWorkspace.Setup.LoopThreadId := TThread.Current.ThreadID;
    mWorker := TThread.CreateAnonymousThread(
      procedure
      begin
        try
          mWorkspace.Reload;
        except
          on E: Exception do
            mRaised := E.ClassName;
        end;
      end);
    mWorker.FreeOnTerminate := False;
    try
      mWorker.Start;
      mWorker.WaitFor;
    finally
      mWorker.Free;
    end;
    Assert.AreEqual('EInvalidOpException', mRaised);
  finally
    mWorkspace.Free;
  end;
end;

procedure TCoreWorkspaceTests.ChooseFallsBackToSingleWorkspace;
var
  mAll: TObjectList<TCoreWorkspace>;
  A, B: TCoreWorkspace;
begin
  mAll := TObjectList<TCoreWorkspace>.Create(True);
  try
    Assert.IsNull(TCoreWorkspaces.Choose(nil, mAll), 'Ohne Arbeitsbereich keiner');
    Assert.IsNull(TCoreWorkspaces.Choose(nil, nil));
    A := NewWorkspace('A');
    mAll.Add(A);
    Assert.AreSame(A, TCoreWorkspaces.Choose(nil, mAll), 'Einziger Arbeitsbereich als Rückfall');
    B := NewWorkspace('B');
    mAll.Add(B);
    Assert.IsNull(TCoreWorkspaces.Choose(nil, mAll), 'Bei mehreren kein Rückfall');
    Assert.AreSame(B, TCoreWorkspaces.Choose(B, mAll), 'Treffer geht vor');
  finally
    mAll.Free;
  end;
end;

function Member(const AName: string; AKind: TRuleApplicationKind): TCheckProject;
begin
  Result := Default(TCheckProject);
  Result.Application := AKind;
  Result.Name := AName;
  Result.ProjectMainSource := AName + '.dpr';
end;

procedure TCoreWorkspaceTests.MergeRuleProjectsKeepsOnlyUnambiguousKind;
var
  mOutside, mMerged: TCheckProject;
begin
  mOutside := Default(TCheckProject);
  mMerged := TCoreRuleProjects.MergeRuleProjects(nil, 'U.pas');
  Assert.AreEqual('U.pas', mMerged.FileName);
  Assert.AreEqual<TRuleApplicationKind>(TRuleApplicationKind.Unknown, mMerged.Application, 'Ohne Projekt unbekannt');
  mMerged := TCoreRuleProjects.MergeRuleProjects([mOutside, Member('Tests', TRuleApplicationKind.Console)], 'U.pas');
  Assert.AreEqual<TRuleApplicationKind>(TRuleApplicationKind.Console,
    mMerged.Application, 'Projekt ohne die Datei zählt nicht');
  Assert.AreEqual('Tests', mMerged.Name);
  Assert.AreEqual('U.pas', mMerged.FileName);
  mMerged := TCoreRuleProjects.MergeRuleProjects([Member('A', TRuleApplicationKind.Gui),
    Member('B', TRuleApplicationKind.Gui)], 'U.pas');
  Assert.AreEqual<TRuleApplicationKind>(TRuleApplicationKind.Gui, mMerged.Application, 'Gleiche Art bleibt');
  Assert.AreEqual('A', mMerged.Name, 'Das erste Projekt liefert den Namen');
  mMerged := TCoreRuleProjects.MergeRuleProjects([Member('Tests', TRuleApplicationKind.Console),
    Member('Plugin', TRuleApplicationKind.Package), Member('Noch', TRuleApplicationKind.Console)], 'U.pas');
  Assert.AreEqual<TRuleApplicationKind>(TRuleApplicationKind.Unknown,
    mMerged.Application, 'Verschiedene Arten ergeben Unknown');
  Assert.AreEqual('Tests', mMerged.Name);
end;

procedure TCoreWorkspaceTests.WorkspaceWithoutProjectIsRuleReady;
var
  mWorkspace: TCoreWorkspace;
  mReason: string;
  mSaved: TTextLanguage;
begin
  // Der Grund ist ein Text in der aktuellen Sprache: deutsch festlegen, statt sich auf die Testreihenfolge zu
  // verlassen (andere Tests stellen TAtlasLocale um).
  mSaved := TAtlasLocale.Language;
  TAtlasLocale.Use(TTextLanguage.German);
  mWorkspace := NewWorkspace('Ohne');
  try
    mWorkspace.Setup.LoopThreadId := TThread.Current.ThreadID;
    Assert.IsFalse(mWorkspace.RuleReady(mReason), 'Vor dem ersten Aufbau ist offen, ob ein Projekt kommt');
    Assert.AreEqual('Projekte werden geladen', mReason);
    mWorkspace.Reload;
    Assert.IsTrue(mWorkspace.RuleReady(mReason), mReason);
    Assert.AreEqual('', mReason);
  finally
    mWorkspace.Free;
    TAtlasLocale.Use(mSaved);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCoreWorkspaceTests);

end.
