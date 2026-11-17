unit Atlas.Tests.MutationShadowFake;

// Fälschung für IAtlasMutationShadowProject: spielt das Schattenprojekt des
// Mutationslaufs ohne IDE. Build und Run antworten nicht sofort, sondern erst,
// wenn der Test FinishBuild bzw. FinishRun ruft (wie Build-Pipeline und
// Thread der Test-EXE). Fehler legt der Test vorher fest: OpenProblem,
// WriteError, BuildRefusal, CloseError. Calls schreibt mit („open“,
// „write“, „build“, „run:<EXE>“, „close“), Written jeden geschriebenen Text.

interface

uses
  System.Classes,
  Atlas.Core.Tests.MutationFlow;

type
  TAtlasMutationShadowFake = class(TInterfacedObject, IAtlasMutationShadowProject)
  private
    FCalls: TStringList;
    FWritten: TStringList;
    FOpenProblem: string;
    FWriteError: string;
    FBuildRefusal: string;
    FCloseError: string;
    FBuilt: TAtlasMutationBuilt;
    FRan: TAtlasMutationRan;
  public
    constructor Create;
    destructor Destroy; override;
    { IAtlasMutationShadowProject }
    function Open(out AProblem: string): Boolean;
    function Name: string;
    procedure Write(const ALines: TArray<string>);
    function Build(const ADone: TAtlasMutationBuilt; out AReason: string): Boolean;
    procedure Run(const AExecutable: string; const ADone: TAtlasMutationRan);
    procedure Close;
    /// <summary>Ausstehenden Build beenden; False, wenn keiner aussteht.</summary>
    function FinishBuild(ASucceeded: Boolean; const AExecutable, AError: string): Boolean;
    /// <summary>Ausstehende Test-EXE beenden; False, wenn keine aussteht.</summary>
    function FinishRun(AState: TAtlasMutationRunState; AExitCode: Integer; const AXml: string): Boolean;
    /// <summary>Wie FinishRun mit einem Bericht, in dem alle Tests grün (AGreen) bzw. U.TT.B rot sind.</summary>
    function FinishTests(AGreen: Boolean): Boolean;
    property Calls: TStringList read FCalls;
    property Written: TStringList read FWritten;
    property OpenProblem: string read FOpenProblem write FOpenProblem;
    property WriteError: string read FWriteError write FWriteError;
    property BuildRefusal: string read FBuildRefusal write FBuildRefusal;
    property CloseError: string read FCloseError write FCloseError;
  end;

const
  /// <summary>Name des gefälschten Schattenprojekts.</summary>
  cMutationShadowFakeName = 'Tests.Mutation';

implementation

uses
  System.SysUtils;

const
  cRed = '<test-run total="2"><test-suite type="TestFixture" name="TT" fullname="U.TT">' +
    '<test-case fullname="U.TT.A" name="A" result="Passed"/>' +
    '<test-case fullname="U.TT.B" name="B" result="Failed"><failure><message>x</message></failure></test-case>' +
    '</test-suite></test-run>';
  cGreen = '<test-run total="1"><test-suite type="TestFixture" name="TT" fullname="U.TT">' +
    '<test-case fullname="U.TT.A" name="A" result="Passed"/></test-suite></test-run>';

{ TAtlasMutationShadowFake }

constructor TAtlasMutationShadowFake.Create;
begin
  inherited Create;
  FCalls := TStringList.Create;
  FWritten := TStringList.Create;
end;

destructor TAtlasMutationShadowFake.Destroy;
begin
  FBuilt := nil;
  FRan := nil;
  FWritten.Free;
  FCalls.Free;
  inherited Destroy;
end;

function TAtlasMutationShadowFake.Open(out AProblem: string): Boolean;
begin
  FCalls.Add('open');
  AProblem := FOpenProblem;
  Result := FOpenProblem = '';
end;

function TAtlasMutationShadowFake.Name: string;
begin
  Result := cMutationShadowFakeName;
end;

procedure TAtlasMutationShadowFake.Write(const ALines: TArray<string>);
begin
  FCalls.Add('write');
  if FWriteError <> '' then
  begin
    raise EInOutError.Create(FWriteError);
  end;
  FWritten.Add(string.Join(#10, ALines));
end;

function TAtlasMutationShadowFake.Build(const ADone: TAtlasMutationBuilt; out AReason: string): Boolean;
begin
  FCalls.Add('build');
  AReason := FBuildRefusal;
  Result := FBuildRefusal = '';
  if Result then
  begin
    FBuilt := ADone;
  end;
end;

procedure TAtlasMutationShadowFake.Run(const AExecutable: string; const ADone: TAtlasMutationRan);
begin
  FCalls.Add('run:' + AExecutable);
  FRan := ADone;
end;

procedure TAtlasMutationShadowFake.Close;
begin
  FCalls.Add('close');
  if FCloseError <> '' then
  begin
    raise EInOutError.Create(FCloseError);
  end;
end;

function TAtlasMutationShadowFake.FinishBuild(ASucceeded: Boolean; const AExecutable, AError: string): Boolean;
var
  mDone: TAtlasMutationBuilt;
begin
  Result := Assigned(FBuilt);
  if not Result then
  begin
    Exit;
  end;
  mDone := FBuilt;
  FBuilt := nil;
  mDone(ASucceeded, AExecutable, AError);
end;

function TAtlasMutationShadowFake.FinishRun(AState: TAtlasMutationRunState; AExitCode: Integer;
  const AXml: string): Boolean;
var
  mDone: TAtlasMutationRan;
begin
  Result := Assigned(FRan);
  if not Result then
  begin
    Exit;
  end;
  mDone := FRan;
  FRan := nil;
  mDone(AState, AExitCode, AXml);
end;

function TAtlasMutationShadowFake.FinishTests(AGreen: Boolean): Boolean;
begin
  if AGreen then
  begin
    Result := FinishRun(TAtlasMutationRunState.Completed, 0, cGreen);
  end
  else
  begin
    Result := FinishRun(TAtlasMutationRunState.Completed, 1, cRed);
  end;
end;

end.
