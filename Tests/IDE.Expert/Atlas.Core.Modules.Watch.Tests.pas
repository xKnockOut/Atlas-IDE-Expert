unit Atlas.Core.Modules.Watch.Tests;

// Tests zu TAtlasProvidedWatch (#1455): Die Liste folgt Bereitstellen und
// Zurückziehen sofort, OnChanged nur bei einer echten Änderung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TProvidedWatchTests = class
  public
    [Test]
    procedure FollowsProvideAndUnregister;
    [Test]
    procedure OtherInterfacesDoNotNotify;
    [Test]
    procedure WithoutRegistryEmpty;
    [Test]
    procedure DestroyedWatchHearsNothing;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Watch;

type
  IWatchTestThing = interface
    ['{4C0D7B52-91E3-4A86-B5F2-0E6A3D17C948}']
    function Name: string;
  end;

  IWatchTestOther = interface
    ['{D2A85E16-37BC-4F09-8E41-6B9C0F7A2D53}']
  end;

  TThing = class(TInterfacedObject, IWatchTestThing, IWatchTestOther)
  private
    FName: string;
  public
    constructor Create(const AName: string);
    function Name: string;
  end;

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

constructor TThing.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

function TThing.Name: string;
begin
  Result := FName;
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

procedure TProvidedWatchTests.FollowsProvideAndUnregister;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mWatch: TAtlasProvidedWatch;
  mCount: Integer;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mScope := mRegistry.RegisterModule(TFakeModule.Create('atlas.a') as IAtlasModule);
  mScope.Provide(IWatchTestThing, TThing.Create('vorher') as IWatchTestThing);
  mWatch := TAtlasProvidedWatch.Create(mRegistry, IWatchTestThing);
  try
    mCount := 0;
    mWatch.OnChanged :=
      procedure
      begin
        Inc(mCount);
      end;
    Assert.AreEqual(1, Integer(Length(mWatch.Items)), 'schon bereitgestellte sofort');
    mScope.Provide(IWatchTestThing, TThing.Create('nachher') as IWatchTestThing);
    Assert.AreEqual(2, Integer(Length(mWatch.Items)));
    Assert.AreEqual('nachher', (mWatch.Items[1] as IWatchTestThing).Name);
    Assert.AreEqual(1, mCount);
    mScope := nil;
    mRegistry.UnregisterModule('atlas.a');
    Assert.AreEqual(0, Integer(Length(mWatch.Items)), 'mit dem Modul weg');
    Assert.IsTrue(mCount >= 2);
  finally
    mWatch.Free;
  end;
  mRegistry := nil;
end;

procedure TProvidedWatchTests.OtherInterfacesDoNotNotify;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mWatch: TAtlasProvidedWatch;
  mCount: Integer;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mWatch := TAtlasProvidedWatch.Create(mRegistry, IWatchTestThing);
  try
    mCount := 0;
    mWatch.OnChanged :=
      procedure
      begin
        Inc(mCount);
      end;
    mScope := mRegistry.RegisterModule(TFakeModule.Create('atlas.a') as IAtlasModule);
    mScope.Provide(IWatchTestOther, TThing.Create('x') as IWatchTestOther);
    Assert.AreEqual(0, mCount);
    Assert.AreEqual(0, Integer(Length(mWatch.Items)));
    mScope := nil;
    mRegistry.UnregisterModule('atlas.a');
    Assert.AreEqual(0, mCount, 'Abmelden ohne eigene Objekte meldet nichts');
  finally
    mWatch.Free;
  end;
  mRegistry := nil;
end;

procedure TProvidedWatchTests.WithoutRegistryEmpty;
var
  mWatch: TAtlasProvidedWatch;
begin
  mWatch := TAtlasProvidedWatch.Create(nil, IWatchTestThing);
  try
    Assert.AreEqual(0, Integer(Length(mWatch.Items)));
  finally
    mWatch.Free;
  end;
end;

procedure TProvidedWatchTests.DestroyedWatchHearsNothing;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mWatch: TAtlasProvidedWatch;
  mCalls: Integer;
begin
  mCalls := 0;
  mRegistry := TAtlasModuleRegistry.Create;
  mWatch := TAtlasProvidedWatch.Create(mRegistry, IWatchTestThing);
  mWatch.OnChanged :=
    procedure
    begin
      Inc(mCalls);
    end;
  mWatch.Free;
  // Nach Destroy darf eine Bereitstellung den freigegebenen Beobachter nicht erreichen.
  mScope := mRegistry.RegisterModule(TFakeModule.Create('atlas.a') as IAtlasModule);
  mScope.Provide(IWatchTestThing, TThing.Create('x') as IWatchTestThing);
  mScope := nil;
  mRegistry.UnregisterModule('atlas.a');
  mRegistry := nil;
  Assert.AreEqual(0, mCalls);
end;

initialization
  TDUnitX.RegisterTestFixture(TProvidedWatchTests);

end.
