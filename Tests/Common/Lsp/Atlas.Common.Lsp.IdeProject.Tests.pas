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
    /// <summary>#452: Präfix-Vorgaben werden gemerkt, laden das Projekt aber nicht neu; #1111: constant und
    /// OnNamingChanged.</summary>
    [Test]
    procedure KeepsNamingWithoutReload;
    /// <summary>#46: Das aktive Projekt wird gemerkt und wechselt, ohne neu zu laden.</summary>
    [Test]
    procedure TracksActiveProjectWithoutReload;
    [Test]
    procedure KeepsFormatFunctionsWithoutReload;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Index.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Rules.Contract,
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

procedure TLspIdeProjectTests.KeepsNamingWithoutReload;
var
  Store: TLspIdeProject;
  Dispatcher: TJsonRpcDispatcher;
  Context: TIdeProjectContext;
  Changed, NamingChanged: Integer;
  Naming: TRuleNaming;
begin
  Context := Parse('{"project":"C:\\P\\A.dproj","naming":{"field":"F","local":"","parameter":3}}');
  Assert.IsTrue(Context.HasNaming[TNamingKind.Field]);
  Assert.AreEqual('F', Context.Naming[TNamingKind.Field]);
  Assert.IsTrue(Context.HasNaming[TNamingKind.Local]);
  Assert.AreEqual('', Context.Naming[TNamingKind.Local]);
  // Kein String: keine Vorgabe.
  Assert.IsFalse(Context.HasNaming[TNamingKind.Parameter]);
  Assert.IsFalse(Context.HasConstantPrefix);
  // Für die Prüfregeln (#1111) mit Konstanten.
  Context := Parse('{"project":"C:\\P\\A.dproj","naming":{"field":"F","local":"m","constant":"c"}}');
  Assert.IsTrue(Context.HasConstantPrefix);
  Assert.AreEqual('c', Context.ConstantPrefix);
  Naming := Context.RuleNaming;
  Assert.IsTrue(Naming.Known[TRuleNamingKind.Field]);
  Assert.AreEqual('F', Naming.Prefixes[TRuleNamingKind.Field]);
  Assert.AreEqual('m', Naming.Prefixes[TRuleNamingKind.Local]);
  Assert.AreEqual('c', Naming.Prefixes[TRuleNamingKind.Constant]);
  Assert.IsFalse(Naming.Known[TRuleNamingKind.Parameter]);
  Assert.AreNotEqual(Parse('{"project":"C:\\P\\A.dproj","naming":{"constant":"c"}}').NamingKey,
    Parse('{"project":"C:\\P\\A.dproj","naming":{"constant":"k"}}').NamingKey);
  Store := TLspIdeProject.Create;
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Changed := 0;
    NamingChanged := 0;
    Store.OnChanged :=
      procedure(const AContext: TIdeProjectContext)
      begin
        Inc(Changed);
      end;
    Store.OnNamingChanged :=
      procedure(const AContext: TIdeProjectContext)
      begin
        Inc(NamingChanged);
      end;
    Store.Attach(Dispatcher);
    Notify(Dispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug"}');
    Assert.AreEqual(1, Changed);
    Assert.AreEqual(0, NamingChanged, 'neues Projekt: OnChanged genügt');
    Notify(Dispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug","naming":{"field":"F"}}');
    Assert.AreEqual(1, Changed);
    Assert.AreEqual(1, NamingChanged);
    Assert.IsTrue(Store.Find('C:\P\A.dproj', Context));
    Assert.AreEqual('F', Context.Naming[TNamingKind.Field]);
    Assert.IsFalse(Context.HasNaming[TNamingKind.Local]);
    // Gleiche Vorgaben: nichts Neues.
    Notify(Dispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug","naming":{"field":"F"}}');
    Assert.AreEqual(1, NamingChanged);
  finally
    Dispatcher.Free;
    Store.Free;
  end;
end;

procedure TLspIdeProjectTests.KeepsFormatFunctionsWithoutReload;
var
  Store: TLspIdeProject;
  Dispatcher: TJsonRpcDispatcher;
  Context: TIdeProjectContext;
  Changed: Integer;
begin
  // Eintrag ohne Name entfällt, ohne formatIndex gilt -1 (Argument vor der Liste) (#451).
  Context := Parse('{"project":"C:\\P\\A.dproj","formatFunctions":[{"name":"Log","formatIndex":1},' +
    '{"name":""},{"name":"TLogger.Fmt"}]}');
  Assert.AreEqual(2, Integer(Length(Context.FormatFunctions)));
  Assert.AreEqual('Log', Context.FormatFunctions[0].Name);
  Assert.AreEqual(1, Context.FormatFunctions[0].FormatIndex);
  Assert.AreEqual(-1, Context.FormatFunctions[1].FormatIndex);
  Assert.IsTrue(Context.FormatFunctions[1].IsMethod);
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
    Notify(Dispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug"}');
    Notify(Dispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug","formatFunctions":[{"name":"Log"}]}');
    Assert.AreEqual(1, Changed);
    Assert.IsTrue(Store.Find('C:\P\A.dproj', Context));
    Assert.AreEqual(1, Integer(Length(Context.FormatFunctions)));
  finally
    Dispatcher.Free;
    Store.Free;
  end;
end;

procedure TLspIdeProjectTests.TracksActiveProjectWithoutReload;
var
  Store: TLspIdeProject;
  Dispatcher: TJsonRpcDispatcher;
  Changed: Integer;
begin
  Assert.IsFalse(Parse('{"project":"C:\\P\\A.dproj"}').HasActive);
  Assert.IsTrue(Parse('{"project":"C:\\P\\A.dproj","active":true}').Active);
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
    Assert.AreEqual('', Store.ActiveProject);
    Notify(Dispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug","active":true}');
    Notify(Dispatcher, '{"project":"C:\\P\\B.dproj","configuration":"Debug","active":false}');
    Assert.AreEqual(2, Changed);
    Assert.AreEqual('C:\P\A.dproj', Store.ActiveProject);
    // Wechsel des aktiven Projekts: gemerkt, aber kein neues Laden.
    Notify(Dispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug","active":false}');
    Assert.AreEqual('', Store.ActiveProject);
    Notify(Dispatcher, '{"project":"C:\\P\\B.dproj","configuration":"Debug","active":true}');
    Assert.AreEqual('C:\P\B.dproj', Store.ActiveProject);
    Assert.AreEqual(2, Changed);
  finally
    Dispatcher.Free;
    Store.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspIdeProjectTests);

end.
