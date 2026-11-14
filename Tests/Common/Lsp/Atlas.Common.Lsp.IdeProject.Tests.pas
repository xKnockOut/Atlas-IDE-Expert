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
  cSample = '{"project":"C:\\P\\A.dproj","configuration":"Release","platform":"Win64","bdsVersion":"23.0",' +
    '"defines":["RELEASE","$(DCC_Define)","release","Feature_$(Platform)"],' +
    '"searchPaths":["..\\Lib","$(BDS)\\source\\x","Lib\\$(Platform)\\$(Config)","..\\lib"],' +
    '"namespaces":["System","Vcl","system"],"libraryPaths":["$(BDSLIB)\\$(Platform)\\release"]}';

function Parse(const AJson: string): TIdeProjectContext;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TIdeProjectContext.FromJson(mValue);
  finally
    mValue.Free;
  end;
end;

function Variables: TArray<TPair<string, string>>;
begin
  Result := [TPair<string, string>.Create('BDS', 'C:\RAD'), TPair<string, string>.Create('BDSLIB', 'C:\RAD\lib')];
end;

procedure TLspIdeProjectTests.ReadsContext;
var
  mContext: TIdeProjectContext;
begin
  mContext := Parse(cSample);
  Assert.AreEqual('C:\P\A.dproj', mContext.Project);
  Assert.AreEqual('Release', mContext.Configuration);
  Assert.AreEqual('Win64', mContext.Platform);
  Assert.AreEqual('23.0', mContext.BdsVersion);
  Assert.IsTrue(mContext.HasOptions);
  Assert.AreEqual(4, Integer(Length(mContext.Defines)));
  Assert.AreEqual(1, Integer(Length(mContext.LibraryPaths)));
  Assert.AreEqual('', Parse('null').Project);
  Assert.IsFalse(Parse('{"project":"C:\\P\\A.dproj"}').HasOptions);
end;

procedure TLspIdeProjectTests.AppliesOptionsToProject;
var
  mProject: TProjectInfo;
  mPaths: TArray<string>;
begin
  mProject := Default(TProjectInfo);
  mProject.FileName := 'C:\P\A.dproj';
  mProject.Config := 'Release';
  mProject.Platform := 'Win64';
  mProject.Defines := ['DEBUG'];
  Parse(cSample).ApplyTo(mProject, Variables);
  // Unaufgelöster Verweis entfällt, Doppelte ohne Rücksicht auf Groß-/Kleinschreibung.
  Assert.AreEqual('RELEASE;FEATURE_WIN64', string.Join(';', mProject.Defines));
  Assert.AreEqual('C:\Lib;C:\RAD\source\x;C:\P\Lib\Win64\Release', string.Join(';', mProject.SearchPaths));
  Assert.AreEqual('System;Vcl', string.Join(';', mProject.Namespaces));
  mPaths := Parse(cSample).ExpandedLibraryPaths(mProject, Variables);
  Assert.AreEqual('C:\RAD\lib\Win64\release', string.Join(';', mPaths));
end;

procedure TLspIdeProjectTests.KeepsDprojValuesWithoutOptions;
var
  mProject: TProjectInfo;
begin
  mProject := Default(TProjectInfo);
  mProject.FileName := 'C:\P\A.dproj';
  mProject.Defines := ['DEBUG'];
  mProject.SearchPaths := ['C:\P\Src'];
  Parse('{"project":"C:\\P\\A.dproj","configuration":"Debug"}').ApplyTo(mProject, nil);
  Assert.AreEqual('DEBUG', string.Join(';', mProject.Defines));
  Assert.AreEqual('C:\P\Src', string.Join(';', mProject.SearchPaths));
end;

procedure Notify(ADispatcher: TJsonRpcDispatcher; const AParams: string);
var
  mMessage: TJSONObject;
begin
  mMessage := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","method":"' + TLspIdeProject.cMethod + '","params":' +
    AParams + '}') as TJSONObject;
  try
    ADispatcher.DispatchMessage(mMessage).Free;
  finally
    mMessage.Free;
  end;
end;

procedure TLspIdeProjectTests.LoadsInitializeAndReportsOnlyChanges;
var
  mStore: TLspIdeProject;
  mDispatcher: TJsonRpcDispatcher;
  mParams: TJSONValue;
  mContext: TIdeProjectContext;
  mChanged: Integer;
begin
  mStore := TLspIdeProject.Create;
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mChanged := 0;
    mStore.OnChanged :=
      procedure(const AContext: TIdeProjectContext)
      begin
        Inc(mChanged);
      end;
    mStore.Attach(mDispatcher);
    mParams := TJSONObject.ParseJSONValue('{"initializationOptions":{"projectContexts":[' + cSample + ']}}');
    try
      mStore.LoadInitialize(mParams);
    finally
      mParams.Free;
    end;
    Assert.IsTrue(mStore.Find('c:\p\a.dproj', mContext));
    Assert.AreEqual('Win64', mContext.Platform);
    // Derselbe Stand wie aus initialize: nichts neu laden.
    Notify(mDispatcher, cSample);
    Assert.AreEqual(0, mChanged);
    Notify(mDispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug","platform":"Win32"}');
    Assert.AreEqual(1, mChanged);
    Assert.IsTrue(mStore.Find('C:\P\A.dproj', mContext));
    Assert.AreEqual('Win32', mContext.Platform);
    Assert.IsFalse(mStore.Find('C:\P\B.dproj', mContext));
  finally
    mDispatcher.Free;
    mStore.Free;
  end;
end;

procedure TLspIdeProjectTests.KeepsNamingWithoutReload;
var
  mStore: TLspIdeProject;
  mDispatcher: TJsonRpcDispatcher;
  mContext: TIdeProjectContext;
  mChanged, mNamingChanged: Integer;
  mNaming: TRuleNaming;
begin
  mContext := Parse('{"project":"C:\\P\\A.dproj","naming":{"field":"F","local":"","parameter":3}}');
  Assert.IsTrue(mContext.HasNaming[TNamingKind.Field]);
  Assert.AreEqual('F', mContext.Naming[TNamingKind.Field]);
  Assert.IsTrue(mContext.HasNaming[TNamingKind.Local]);
  Assert.AreEqual('', mContext.Naming[TNamingKind.Local]);
  // Kein String: keine Vorgabe.
  Assert.IsFalse(mContext.HasNaming[TNamingKind.Parameter]);
  Assert.IsFalse(mContext.HasConstantPrefix);
  // Für die Prüfregeln (#1111) mit Konstanten.
  mContext := Parse('{"project":"C:\\P\\A.dproj","naming":{"field":"F","local":"m","constant":"c"}}');
  Assert.IsTrue(mContext.HasConstantPrefix);
  Assert.AreEqual('c', mContext.ConstantPrefix);
  mNaming := mContext.RuleNaming;
  Assert.IsTrue(mNaming.Known[TRuleNamingKind.Field]);
  Assert.AreEqual('F', mNaming.Prefixes[TRuleNamingKind.Field]);
  Assert.AreEqual('m', mNaming.Prefixes[TRuleNamingKind.Local]);
  Assert.AreEqual('c', mNaming.Prefixes[TRuleNamingKind.Constant]);
  Assert.IsFalse(mNaming.Known[TRuleNamingKind.Parameter]);
  Assert.AreNotEqual(Parse('{"project":"C:\\P\\A.dproj","naming":{"constant":"c"}}').NamingKey,
    Parse('{"project":"C:\\P\\A.dproj","naming":{"constant":"k"}}').NamingKey);
  mStore := TLspIdeProject.Create;
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mChanged := 0;
    mNamingChanged := 0;
    mStore.OnChanged :=
      procedure(const AContext: TIdeProjectContext)
      begin
        Inc(mChanged);
      end;
    mStore.OnNamingChanged :=
      procedure(const AContext: TIdeProjectContext)
      begin
        Inc(mNamingChanged);
      end;
    mStore.Attach(mDispatcher);
    Notify(mDispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug"}');
    Assert.AreEqual(1, mChanged);
    Assert.AreEqual(0, mNamingChanged, 'neues Projekt: OnChanged genügt');
    Notify(mDispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug","naming":{"field":"F"}}');
    Assert.AreEqual(1, mChanged);
    Assert.AreEqual(1, mNamingChanged);
    Assert.IsTrue(mStore.Find('C:\P\A.dproj', mContext));
    Assert.AreEqual('F', mContext.Naming[TNamingKind.Field]);
    Assert.IsFalse(mContext.HasNaming[TNamingKind.Local]);
    // Gleiche Vorgaben: nichts Neues.
    Notify(mDispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug","naming":{"field":"F"}}');
    Assert.AreEqual(1, mNamingChanged);
  finally
    mDispatcher.Free;
    mStore.Free;
  end;
end;

procedure TLspIdeProjectTests.KeepsFormatFunctionsWithoutReload;
var
  mStore: TLspIdeProject;
  mDispatcher: TJsonRpcDispatcher;
  mContext: TIdeProjectContext;
  mChanged: Integer;
begin
  // Eintrag ohne Name entfällt, ohne formatIndex gilt -1 (Argument vor der Liste) (#451).
  mContext := Parse('{"project":"C:\\P\\A.dproj","formatFunctions":[{"name":"Log","formatIndex":1},' +
    '{"name":""},{"name":"TLogger.Fmt"}]}');
  Assert.AreEqual(2, Integer(Length(mContext.FormatFunctions)));
  Assert.AreEqual('Log', mContext.FormatFunctions[0].Name);
  Assert.AreEqual(1, mContext.FormatFunctions[0].FormatIndex);
  Assert.AreEqual(-1, mContext.FormatFunctions[1].FormatIndex);
  Assert.IsTrue(mContext.FormatFunctions[1].IsMethod);
  mStore := TLspIdeProject.Create;
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mChanged := 0;
    mStore.OnChanged :=
      procedure(const AContext: TIdeProjectContext)
      begin
        Inc(mChanged);
      end;
    mStore.Attach(mDispatcher);
    Notify(mDispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug"}');
    Notify(mDispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug","formatFunctions":[{"name":"Log"}]}');
    Assert.AreEqual(1, mChanged);
    Assert.IsTrue(mStore.Find('C:\P\A.dproj', mContext));
    Assert.AreEqual(1, Integer(Length(mContext.FormatFunctions)));
  finally
    mDispatcher.Free;
    mStore.Free;
  end;
end;

procedure TLspIdeProjectTests.TracksActiveProjectWithoutReload;
var
  mStore: TLspIdeProject;
  mDispatcher: TJsonRpcDispatcher;
  mChanged: Integer;
begin
  Assert.IsFalse(Parse('{"project":"C:\\P\\A.dproj"}').HasActive);
  Assert.IsTrue(Parse('{"project":"C:\\P\\A.dproj","active":true}').Active);
  mStore := TLspIdeProject.Create;
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mChanged := 0;
    mStore.OnChanged :=
      procedure(const AContext: TIdeProjectContext)
      begin
        Inc(mChanged);
      end;
    mStore.Attach(mDispatcher);
    Assert.AreEqual('', mStore.ActiveProject);
    Notify(mDispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug","active":true}');
    Notify(mDispatcher, '{"project":"C:\\P\\B.dproj","configuration":"Debug","active":false}');
    Assert.AreEqual(2, mChanged);
    Assert.AreEqual('C:\P\A.dproj', mStore.ActiveProject);
    // Wechsel des aktiven Projekts: gemerkt, aber kein neues Laden.
    Notify(mDispatcher, '{"project":"C:\\P\\A.dproj","configuration":"Debug","active":false}');
    Assert.AreEqual('', mStore.ActiveProject);
    Notify(mDispatcher, '{"project":"C:\\P\\B.dproj","configuration":"Debug","active":true}');
    Assert.AreEqual('C:\P\B.dproj', mStore.ActiveProject);
    Assert.AreEqual(2, mChanged);
  finally
    mDispatcher.Free;
    mStore.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspIdeProjectTests);

end.
