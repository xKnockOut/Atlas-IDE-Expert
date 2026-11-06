unit Atlas.Core.Modules.Answer.Tests;

// Tests zu TAtlasModuleAnswer (#1455, Regel 3): Eine späte Antwort erreicht
// das Modul höchstens einmal und nach seinem Abmelden gar nicht; der
// Rückruf wird beim Abmelden freigegeben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TModuleAnswerTests = class
  public
    [Test]
    procedure DeliversOnce;
    [Test]
    procedure UnregisteredModuleGetsNothing;
    [Test]
    procedure UnregisterReleasesCallback;
    [Test]
    procedure WithoutScopeRevokedAtOnce;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Answer;

type
  TFakeModule = class(TInterfacedObject, IAtlasModule)
  private
    FId: string;
  public
    constructor Create(const AId: string);
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
  end;

  /// <summary>Meldet seine Freigabe über AFreed.</summary>
  TFreeFlag = class(TInterfacedObject)
  private
    FFreed: PBoolean;
  public
    constructor Create(AFreed: PBoolean);
    destructor Destroy; override;
  end;

constructor TFakeModule.Create(const AId: string);
begin
  inherited Create;
  FId := AId;
end;

function TFakeModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := FId;
end;

procedure TFakeModule.Start;
begin
end;

procedure TFakeModule.Stop;
begin
end;

function TFakeModule.IsActive: Boolean;
begin
  Result := False;
end;

constructor TFreeFlag.Create(AFreed: PBoolean);
begin
  inherited Create;
  FFreed := AFreed;
end;

destructor TFreeFlag.Destroy;
begin
  FFreed^ := True;
  inherited;
end;

/// <summary>Rückruf, der AFlag festhält (eigene Routine, damit kein anderer Rahmen ihn hält).</summary>
function HoldingCallback(const AFlag: IInterface): TProc<string>;
begin
  Result :=
    procedure(AText: string)
    begin
      if AFlag = nil then
      begin
        raise Exception.Create('Flagge fehlt');
      end;
    end;
end;

/// <summary>Antwort mit HoldingCallback in eigener Routine: Sonst hielte ein Zwischenwert im Rahmen des Tests den
/// Rückruf bis zum Ende fest.</summary>
function OpenHolding(const AScope: IAtlasModuleScope; AFreed: PBoolean): IAtlasModuleAnswer;
begin
  Result := TAtlasModuleAnswer.Open(AScope, HoldingCallback(TFreeFlag.Create(AFreed)));
end;

procedure TModuleAnswerTests.DeliversOnce;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mAnswer: IAtlasModuleAnswer;
  mGot: string;
  mCount: Integer;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mScope := mRegistry.RegisterModule(TFakeModule.Create('atlas.a') as IAtlasModule);
  mCount := 0;
  mAnswer := TAtlasModuleAnswer.Open(mScope,
    procedure(AText: string)
    begin
      Inc(mCount);
      mGot := AText;
    end);
  Assert.IsFalse(mAnswer.IsRevoked);
  Assert.IsTrue(mAnswer.Deliver('eins'));
  Assert.IsFalse(mAnswer.Deliver('zwei'), 'nur einmal');
  Assert.AreEqual(1, mCount);
  Assert.AreEqual('eins', mGot);
  Assert.IsTrue(mAnswer.IsRevoked, 'geliefert = gelöst');
  mAnswer := nil;
  mScope := nil;
  mRegistry.UnregisterModule('atlas.a');
  mRegistry := nil;
  mGot := '';
end;

procedure TModuleAnswerTests.UnregisteredModuleGetsNothing;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mAnswer: IAtlasModuleAnswer;
  mCount: Integer;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mScope := mRegistry.RegisterModule(TFakeModule.Create('atlas.a') as IAtlasModule);
  mCount := 0;
  mAnswer := TAtlasModuleAnswer.Open(mScope,
    procedure(AText: string)
    begin
      Inc(mCount);
    end);
  mScope := nil;
  mRegistry.UnregisterModule('atlas.a');
  Assert.IsTrue(mAnswer.IsRevoked);
  Assert.IsFalse(mAnswer.Deliver('spät'));
  Assert.AreEqual(0, mCount);
  mAnswer := nil;
  mRegistry := nil;
end;

procedure TModuleAnswerTests.UnregisterReleasesCallback;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mAnswer: IAtlasModuleAnswer;
  mFreed: Boolean;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mScope := mRegistry.RegisterModule(TFakeModule.Create('atlas.a') as IAtlasModule);
  mFreed := False;
  mAnswer := OpenHolding(mScope, @mFreed);
  Assert.IsFalse(mFreed);
  mScope := nil;
  mRegistry.UnregisterModule('atlas.a');
  // Die Antwort selbst lebt noch (etwa in einem wartenden Hintergrundlauf), der Rückruf des Moduls nicht mehr.
  Assert.IsTrue(mFreed);
  mAnswer := nil;
  mRegistry := nil;
end;

procedure TModuleAnswerTests.WithoutScopeRevokedAtOnce;
var
  mAnswer: IAtlasModuleAnswer;
  mCount: Integer;
begin
  mCount := 0;
  mAnswer := TAtlasModuleAnswer.Open(nil,
    procedure(AText: string)
    begin
      Inc(mCount);
    end);
  Assert.IsTrue(mAnswer.IsRevoked);
  Assert.IsFalse(mAnswer.Deliver('x'));
  Assert.AreEqual(0, mCount);
end;

initialization
  TDUnitX.RegisterTestFixture(TModuleAnswerTests);

end.
