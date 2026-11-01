unit Atlas.Core.Build.Pipeline.Tests;

// Tests zu TAtlasBuildPipeline (#1455): Hörer der Compilermeldungen und
// Bewertung kommen und gehen mit dem Modul der Build-Pipeline.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBuildPipelineTests = class
  public
    [Test]
    procedure MessagesReachEveryListener;
    [Test]
    procedure EvaluateOnlyWhenTaken;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Pipeline;

type
  TFakeModule = class(TInterfacedObject, IAtlasModule)
  private
    FStopped: Boolean;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
  end;

  TFakePipeline = class(TInterfacedObject, IAtlasCompilerMessagesListener, IAtlasBuildEvaluator)
  private
    FTake: Boolean;
  public
    Read: Integer;
    Evaluated: Integer;
    constructor Create(ATake: Boolean);
    procedure MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject);
    function Evaluate(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      ASucceeded: Boolean): Boolean;
  end;

function TFakeModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := 'atlas.buildpipeline';
end;

procedure TFakeModule.Start;
begin
  FStopped := False;
end;

procedure TFakeModule.Stop;
begin
  FStopped := True;
end;

function TFakeModule.IsActive: Boolean;
begin
  Result := not FStopped;
end;

constructor TFakePipeline.Create(ATake: Boolean);
begin
  inherited Create;
  FTake := ATake;
end;

procedure TFakePipeline.MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject);
begin
  Inc(Read, Length(AMessages));
end;

function TFakePipeline.Evaluate(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
  ASucceeded: Boolean): Boolean;
begin
  Inc(Evaluated);
  Result := FTake;
end;

function Project: TAtlasCompileProject;
begin
  Result := Default(TAtlasCompileProject);
  Result.FileName := 'C:\P\Kasse.dproj';
end;

function Messages: TArray<TAtlasCompilerMessage>;
begin
  SetLength(Result, 2);
  Result[0] := Default(TAtlasCompilerMessage);
  Result[1] := Default(TAtlasCompilerMessage);
end;

procedure TAtlasBuildPipelineTests.MessagesReachEveryListener;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mFirst, mSecond: TFakePipeline;
  mKeepFirst, mKeepSecond: IInterface;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mScope := mRegistry.RegisterModule(TFakeModule.Create as IAtlasModule);
  mFirst := TFakePipeline.Create(False);
  mKeepFirst := mFirst as IAtlasCompilerMessagesListener;
  mSecond := TFakePipeline.Create(False);
  mKeepSecond := mSecond as IAtlasCompilerMessagesListener;
  mScope.Provide(IAtlasCompilerMessagesListener, mKeepFirst);
  mScope.Provide(IAtlasCompilerMessagesListener, mKeepSecond);
  Assert.AreEqual(0, Integer(Length(TAtlasBuildPipeline.MessagesRead(mRegistry, Messages, Project))));
  Assert.AreEqual(2, mFirst.Read);
  Assert.AreEqual(2, mSecond.Read);
  mScope := nil;
  mRegistry.UnregisterModule('atlas.buildpipeline');
  Assert.AreEqual(0, Integer(Length(TAtlasBuildPipeline.MessagesRead(mRegistry, Messages, Project))));
  Assert.AreEqual(2, mFirst.Read, 'nach dem Abmelden nichts mehr');
  mKeepFirst := nil;
  mKeepSecond := nil;
  mRegistry := nil;
end;

procedure TAtlasBuildPipelineTests.EvaluateOnlyWhenTaken;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mDeclines, mTakes: TFakePipeline;
  mKeepDeclines, mKeepTakes: IInterface;
  mFailures: TArray<string>;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  Assert.IsFalse(TAtlasBuildPipeline.Evaluate(mRegistry, Messages, Project, True, mFailures), 'ohne Modul bewertet Base');
  mScope := mRegistry.RegisterModule(TFakeModule.Create as IAtlasModule);
  mDeclines := TFakePipeline.Create(False);
  mKeepDeclines := mDeclines as IAtlasBuildEvaluator;
  mScope.Provide(IAtlasBuildEvaluator, mKeepDeclines);
  Assert.IsFalse(TAtlasBuildPipeline.Evaluate(mRegistry, Messages, Project, True, mFailures), 'nicht übernommen');
  mTakes := TFakePipeline.Create(True);
  mKeepTakes := mTakes as IAtlasBuildEvaluator;
  mScope.Provide(IAtlasBuildEvaluator, mKeepTakes);
  Assert.IsTrue(TAtlasBuildPipeline.Evaluate(mRegistry, Messages, Project, True, mFailures));
  Assert.AreEqual(1, mTakes.Evaluated);
  Assert.AreEqual(0, Integer(Length(mFailures)));
  mScope := nil;
  mRegistry.UnregisterModule('atlas.buildpipeline');
  mKeepDeclines := nil;
  mKeepTakes := nil;
  mFailures := nil;
  mRegistry := nil;
end;

end.
