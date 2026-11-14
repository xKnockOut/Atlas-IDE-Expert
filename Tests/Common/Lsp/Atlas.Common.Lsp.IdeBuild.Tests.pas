unit Atlas.Common.Lsp.IdeBuild.Tests;

// Tests für Build-Ergebnisse aus der IDE (#528).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspIdeBuildTests = class
  public
    [Test]
    procedure ParsesMessagesZeroBased;
    [Test]
    procedure RemembersLastBuildAndRaisesEvent;
    [Test]
    procedure TracksRunningCompiles;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.IdeBuild;

const
  cSample = '{"project":"C:\\P\\A.dproj","platform":"Win32","success":false,"messages":[' +
    '{"file":"C:\\P\\A.dpr","line":10,"column":11,"severity":"error","code":"E2003","text":"Undeklarierter Bezeichner"},' +
    '{"file":"C:\\P\\A.dpr","line":7,"column":3,"severity":"hint","code":"H2164","text":"Variable nicht verwendet"},' +
    '{"file":"","line":0,"column":0,"severity":"fatal","code":"F1026","text":"Datei nicht gefunden"}]}';

procedure TLspIdeBuildTests.ParsesMessagesZeroBased;
var
  mParams: TJSONValue;
  mMessages: TArray<TCompilerMessage>;
begin
  mParams := TJSONObject.ParseJSONValue(cSample);
  try
    mMessages := TLspIdeBuild.ParseMessages(mParams);
  finally
    mParams.Free;
  end;
  Assert.AreEqual(3, Integer(Length(mMessages)));
  Assert.AreEqual(9, mMessages[0].Line);
  Assert.AreEqual(10, mMessages[0].Column);
  Assert.AreEqual(Ord(TCompilerSeverity.Error), Ord(mMessages[0].Severity));
  Assert.AreEqual('E2003', mMessages[0].Code);
  Assert.AreEqual(Ord(TCompilerSeverity.Hint), Ord(mMessages[1].Severity));
  // Ohne Datei und Zeile: Zeile und Spalte -1.
  Assert.AreEqual(-1, mMessages[2].Line);
  Assert.AreEqual(-1, mMessages[2].Column);
  Assert.AreEqual(Ord(TCompilerSeverity.Fatal), Ord(mMessages[2].Severity));
end;

procedure Notify(ADispatcher: TJsonRpcDispatcher; const AMethod, AParams: string);
var
  mMessage: TJSONObject;
begin
  mMessage := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","method":"' + AMethod + '","params":' + AParams + '}')
    as TJSONObject;
  try
    ADispatcher.DispatchMessage(mMessage).Free;
  finally
    mMessage.Free;
  end;
end;

procedure TLspIdeBuildTests.RemembersLastBuildAndRaisesEvent;
var
  mBuild: TLspIdeBuild;
  mDispatcher: TJsonRpcDispatcher;
  mReceived: Integer;
begin
  mBuild := TLspIdeBuild.Create;
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mReceived := -1;
    mBuild.OnMessages :=
      procedure(const AMessages: TArray<TCompilerMessage>)
      begin
        mReceived := Length(AMessages);
      end;
    mBuild.Attach(mDispatcher);
    Assert.IsFalse(mBuild.LastBuild.Known);
    Notify(mDispatcher, TLspIdeBuild.cFinishedMethod,
      '{"project":"C:\\P\\A.dproj","kind":"build","configuration":"Debug","platform":"Win32","success":false,"durationMs":1234}');
    Notify(mDispatcher, TLspIdeBuild.cMessagesMethod, cSample);
    Assert.AreEqual(3, mReceived);
    Assert.IsTrue(mBuild.LastBuild.Known);
    Assert.AreEqual('C:\P\A.dproj', mBuild.LastBuild.Project);
    Assert.AreEqual('build', mBuild.LastBuild.Kind);
    Assert.AreEqual('Debug', mBuild.LastBuild.Configuration);
    Assert.AreEqual(Int64(1234), mBuild.LastBuild.DurationMs);
    Assert.IsFalse(mBuild.LastBuild.Success);
    Assert.AreEqual(3, Integer(Length(mBuild.LastBuild.Messages)));
  finally
    mDispatcher.Free;
    mBuild.Free;
  end;
end;

procedure TLspIdeBuildTests.TracksRunningCompiles;
var
  mBuild: TLspIdeBuild;
  mDispatcher: TJsonRpcDispatcher;
  mEvents: string;
begin
  // Die Projektprüfung pausiert, solange die IDE kompiliert (#1247).
  mBuild := TLspIdeBuild.Create;
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mEvents := '';
    mBuild.OnCompiling :=
      procedure(ARunning: Boolean)
      begin
        if ARunning then
        begin
          mEvents := mEvents + '+';
        end
        else
        begin
          mEvents := mEvents + '-';
        end;
      end;
    mBuild.Attach(mDispatcher);
    Notify(mDispatcher, TLspIdeBuild.cStartedMethod, '{"group":true,"kind":"make"}');
    Notify(mDispatcher, TLspIdeBuild.cStartedMethod, '{"project":"C:\\P\\A.dproj"}');
    Notify(mDispatcher, TLspIdeBuild.cStartedMethod, '{"project":"C:\\P\\B.dproj"}');
    Assert.IsTrue(mBuild.Compiling);
    Notify(mDispatcher, TLspIdeBuild.cFinishedMethod, '{"project":"C:\\P\\A.dproj","success":true}');
    Assert.IsTrue(mBuild.Compiling, 'B und die Gruppe laufen noch');
    // Fehlt das Ende von B, beendet das Ende der Gruppe alles.
    Notify(mDispatcher, TLspIdeBuild.cFinishedMethod, '{"group":true,"success":true}');
    Assert.IsFalse(mBuild.Compiling);
    // Einzelnes Projekt im Hintergrund (#548).
    Notify(mDispatcher, TLspIdeBuild.cStartedMethod, '{"project":"C:\\P\\A.dproj","background":true}');
    Assert.IsTrue(mBuild.Compiling);
    Notify(mDispatcher, TLspIdeBuild.cFinishedMethod, '{"project":"c:\\p\\a.dproj","background":true}');
    Assert.IsFalse(mBuild.Compiling);
    Assert.AreEqual('+-+-', mEvents);
  finally
    mDispatcher.Free;
    mBuild.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspIdeBuildTests);

end.