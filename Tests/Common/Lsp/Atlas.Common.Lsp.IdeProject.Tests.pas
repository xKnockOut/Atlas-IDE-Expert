unit Atlas.Common.Lsp.IdeProject.Tests;

// Tests für den Projektkontext aus der IDE (#396).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspIdeProjectTests = class
  public
    [Test]
    procedure ReadsContext;
    [Test]
    procedure AppliesOptionsToProject;
    [Test]
    procedure KeepsDprojValuesWithoutOptions;
    [Test]
    procedure LoadsInitializeAndReportsOnlyChanges;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Lsp.IdeProject;

const
  Sample = '{"project":"C:\\P\\A.dproj","configuration":"Release","platform":"Win64","bdsVersion":"23.0",' +
    '"defines":["RELEASE","$(DCC_Define)","release","Feature_$(Platform)"],' +
    '"searchPaths":["..\\Lib","$(BDS)\\source\\x","Lib\\$(Platform)\\$(Config)","..\\lib"],' +
    '"namespaces":["System","Vcl","system"],"libraryPaths":["$(BDSLIB)\\$(Platform)\\release"]}';

function Parse(const AJson: string): TIdeProjectContext;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TIdeProjectContext.FromJson(Value);
  finally
    Value.Free;
  end;
end;

function Variables: TArray<TPair<string, string>>;
begin
  Result := [TPair<string, string>.Create('BDS', 'C:\RAD'), TPair<string, string>.Create('BDSLIB', 'C:\RAD\lib')];
end;

procedure TLspIdeProjectTests.ReadsContext;
var
  Context: TIdeProjectContext;
begin
  Context := Parse(Sample);
  Assert.AreEqual('C:\P\A.dproj', Context.Project);
  Assert.AreEqual('Release', Context.Configuration);
  Assert.AreEqual('Win64', Context.Platform);
  Assert.AreEqual('23.0', Context.BdsVersion);
  Assert.IsTrue(Context.HasOptions);
  Assert.AreEqual(4, Integer(Length(Context.Defines)));
  Assert.AreEqual(1, Integer(Length(Context.LibraryPaths)));
  Assert.AreEqual('', Parse('null').Project);
  Assert.IsFalse(Parse('{"project":"C:\\P\\A.dproj"}').HasOptions);
end;

procedure TLspIdeProjectTests.AppliesOptionsToProject;
var
  Project: TProjectInfo;
  Paths: TArray<string>;
begin
  Project := Default(TProjectInfo);
  Project.FileName := 'C:\P\A.dproj';
  Project.Config := 'Release';
  Project.Platform := 'Win64';
  Project.Defines := ['DEBUG'];
  Parse(Sample).ApplyTo(Project, Variables);
  // Unaufgelöster Verweis entfällt, Doppelte ohne Rücksicht auf Groß-/Kleinschreibung.
  Assert.AreEqual('RELEASE;FEATURE_WIN64', string.Join(';', Project.Defines));
  Assert.AreEqual('C:\Lib;C:\RAD\source\x;C:\P\Lib\Win64\Release', string.Join(';', Project.SearchPaths));
  Assert.AreEqual('System;Vcl', string.Join(';', Project.Namespaces));
  Paths := Parse(Sample).ExpandedLibraryPaths(Project, Variables);
  Assert.AreEqual('C:\RAD\lib\Win64\release', string.Join(';', Paths));
end;

procedure TLspIdeProjectTests.KeepsDprojValuesWithoutOptions;
var
  Project: TProjectInfo;
begin
  Project := Default(TProjectInfo);
  Project.FileName := 'C:\P\A.dproj';
  Project.Defines := ['DEBUG'];
  Project.SearchPaths := ['C:\P\Src'];
  Parse('{"project":"C:\\P\\A.dproj","configuration":"Debug"}').ApplyTo(Project, nil);
  Assert.AreEqual('DEBUG', string.Join(';', Project.Defines));
  Assert.AreEqual('C:\P\Src', string.Join(';', Project.SearchPaths));
end;

procedure Notify(ADispatcher: TJsonRpcDispatcher; const AParams: string);
var
  Message: TJSONObject;
begin
  Message := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","method":"' + TLspIdeProject.Method + '","params":' +
    AParams + '}') as TJSONObject;
  try
    ADispatcher.DispatchMessage(Message).Free;
  finally
    Message.Free;
  end;
end;

procedure TLspIdeProjectTests.LoadsInitializeAndReportsOnlyChanges;
var
  Store: TLspIdeProject;
  Dispatcher: TJsonRpcDispatcher;
  Params: TJSONValue;
  Context: TIdeProjectContext;
  Changed: Integer;
begin
  Store := TLspIdeProject.Create;
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Changed := 0;
    Store.OnChanged :=
      procedure(const AContext: TIdeProjectContext)
      begin
        Inc(Changed);
      end;
    Store.Attach(Dispatcher);
    Params := TJSONObject.ParseJSONValue('{"initializationOptions":{"projectContexts":[' + Sample + ']}}');
    try
      Store.LoadInitialize(Params);
    finally
      Params.Free;
    end;
    Assert.IsTrue(Store.Find('c:\p\a.dproj', Context));
    Assert.AreEqual('Win64', Context.Platform);
    // Derselbe Stand wie aus initialize: nichts neu laden.
    Notify(Dispatcher, Sample);
    Assert.AreEqual(0, Changed);
    Notify(Dispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug","platform":"Win32"}');
    Assert.AreEqual(1, Changed);
    Assert.IsTrue(Store.Find('C:\P\A.dproj', Context));
    Assert.AreEqual('Win32', Context.Platform);
    Assert.IsFalse(Store.Find('C:\P\B.dproj', Context));
  finally
    Dispatcher.Free;
    Store.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspIdeProjectTests);

end.
