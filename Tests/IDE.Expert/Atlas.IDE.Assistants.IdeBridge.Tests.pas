unit Atlas.IDE.Assistants.IdeBridge.Tests;

// Eigener Anbieter als Anbieter der IDE (#2745) mit gefälschtem Anbieter und Notifier: Funktionsliste, Name,
// Weiterleitung von Chat und Anweisung, Fehler, Tagesgrenze, Abbruch, Modelle und Stop.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Generics.Collections,
  Atlas.IDE.Contracts.AiText,
  Atlas.Tests.AiTextFake,
  Atlas.Core.Assistants.Contract.IdeAi,
  Atlas.IDE.Assistants.IdeBridge;

type
  /// <summary>Notifier der IDE zum Mitschreiben: „answer id text“, „error id text“, „models id a,b“.</summary>
  TFakeAnswers = class(TInterfacedObject, IAtlasIdeAiAnswers)
  private
    FLog: TList<string>;
  public
    constructor Create(ALog: TList<string>);
    procedure Answer(const AText, AId: string);
    procedure Error(const AText, AId: string);
    procedure Models(const AModels: TArray<string>; const AId: string);
  end;

  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasIdeAiBridgeTests = class
  private
    FText: TAtlasFakeAiText;
    FTextRef: IAtlasAiText;
    FBridge: TAtlasIdeAiBridge;
    FLog: TList<string>;
    FPosted: TList<TProc>;
    FLimitReached: Boolean;
    FIds: Integer;
    FModels: TAtlasIdeAiModelsDone;
    procedure CreateBridge(AWithModels: Boolean);
    /// <summary>Alles ausführen, was die Brücke in den Hauptthread gereiht hat.</summary>
    procedure RunPosted;
    function LogText: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure NameAndFeatures;
    [Test]
    procedure InstructionIsForwardedAndAnswered;
    [Test]
    procedure ChatGoesWithoutInstruction;
    [Test]
    procedure FailureReachesTheNotifiers;
    [Test]
    procedure NotReadyAnswersWithError;
    [Test]
    procedure DailyLimitStopsTheRequest;
    [Test]
    procedure CancelStopsAllRequests;
    [Test]
    procedure ModelsAreListed;
    [Test]
    procedure WithoutListerModelsFail;
    [Test]
    procedure RemovedNotifierHearsNothing;
    [Test]
    procedure AfterStopNothingReachesTheIde;
  end;

implementation

{ TFakeAnswers }

constructor TFakeAnswers.Create(ALog: TList<string>);
begin
  inherited Create;
  FLog := ALog;
end;

procedure TFakeAnswers.Answer(const AText, AId: string);
begin
  FLog.Add('answer ' + AId + ' ' + AText);
end;

procedure TFakeAnswers.Error(const AText, AId: string);
begin
  FLog.Add('error ' + AId + ' ' + AText);
end;

procedure TFakeAnswers.Models(const AModels: TArray<string>; const AId: string);
begin
  FLog.Add('models ' + AId + ' ' + string.Join(',', AModels));
end;

{ TAtlasIdeAiBridgeTests }

procedure TAtlasIdeAiBridgeTests.Setup;
begin
  FText := TAtlasFakeAiText.Create(True, 'lokal, llama3.1');
  FTextRef := FText;
  FLog := TList<string>.Create;
  FPosted := TList<TProc>.Create;
  FLimitReached := False;
  FIds := 0;
end;

procedure TAtlasIdeAiBridgeTests.TearDown;
begin
  FreeAndNil(FBridge);
  FTextRef := nil;
  FText := nil;
  FModels := nil;
  FreeAndNil(FPosted);
  FreeAndNil(FLog);
end;

procedure TAtlasIdeAiBridgeTests.CreateBridge(AWithModels: Boolean);
var
  mSelf: TAtlasIdeAiBridgeTests;
  mTexts: TAtlasIdeAiBridgeTexts;
  mModels: TAtlasIdeAiModelLister;
begin
  mSelf := Self;
  mTexts.NotReady := 'kein Anbieter';
  mTexts.NoModels := 'keine Modelle';
  mModels := nil;
  if AWithModels then
  begin
    mModels :=
      procedure(const ADone: TAtlasIdeAiModelsDone)
      begin
        mSelf.FModels := ADone;
      end;
  end;
  FBridge := TAtlasIdeAiBridge.Create(FTextRef,
    function: string
    begin
      Result := '';
      if mSelf.FLimitReached then
      begin
        Result := 'Tagesgrenze';
      end;
    end, mModels,
    procedure(const AWork: TProc)
    begin
      mSelf.FPosted.Add(AWork);
    end, mTexts,
    function: string
    begin
      Inc(mSelf.FIds);
      Result := 'g' + IntToStr(mSelf.FIds);
    end);
  FBridge.AddNotifier(TFakeAnswers.Create(FLog));
end;

procedure TAtlasIdeAiBridgeTests.RunPosted;
var
  mWork: TProc;
begin
  for mWork in FPosted.ToArray do
  begin
    mWork();
  end;
  FPosted.Clear;
end;

function TAtlasIdeAiBridgeTests.LogText: string;
begin
  Result := string.Join('; ', FLog.ToArray);
end;

procedure TAtlasIdeAiBridgeTests.NameAndFeatures;
begin
  CreateBridge(False);
  Assert.AreEqual('Atlas (lokal, llama3.1)', FBridge.Name);
  Assert.IsTrue(FBridge.Enabled);
  Assert.IsTrue(FBridge.Features = [TAtlasIdeAiFeature.Chat, TAtlasIdeAiFeature.Instruction]);
  FreeAndNil(FBridge);
  CreateBridge(True);
  Assert.IsTrue(TAtlasIdeAiFeature.ListModels in FBridge.Features);
end;

procedure TAtlasIdeAiBridgeTests.InstructionIsForwardedAndAnswered;
var
  mId: string;
begin
  CreateBridge(False);
  mId := FBridge.Instruction('procedure A;', 'Kommentiere');
  Assert.AreEqual('g1', mId);
  Assert.AreEqual('Kommentiere', FText.LastRequest.Instructions);
  Assert.AreEqual('procedure A;', FText.LastRequest.Task);
  Assert.AreEqual(1, FBridge.OpenCount);
  FText.Complete(1, TAtlasAiTextStatus.Ok, '// A');
  Assert.AreEqual('', LogText, 'erst im Hauptthread');
  RunPosted;
  Assert.AreEqual('answer g1 // A', LogText);
  Assert.AreEqual(0, FBridge.OpenCount);
end;

procedure TAtlasIdeAiBridgeTests.ChatGoesWithoutInstruction;
begin
  CreateBridge(False);
  FBridge.Chat('Was ist TObject?');
  Assert.AreEqual('', FText.LastRequest.Instructions);
  Assert.AreEqual('Was ist TObject?', FText.LastRequest.Task);
end;

procedure TAtlasIdeAiBridgeTests.FailureReachesTheNotifiers;
begin
  CreateBridge(False);
  FBridge.Chat('x');
  FText.Complete(1, TAtlasAiTextStatus.Failed, 'Schlüssel abgelehnt');
  RunPosted;
  Assert.AreEqual('error g1 Schlüssel abgelehnt', LogText);
end;

procedure TAtlasIdeAiBridgeTests.NotReadyAnswersWithError;
begin
  CreateBridge(False);
  FText.IsReady := False;
  Assert.IsFalse(FBridge.Enabled);
  Assert.AreEqual('g1', FBridge.Chat('x'));
  Assert.AreEqual(0, FText.AskCount);
  RunPosted;
  Assert.AreEqual('error g1 kein Anbieter', LogText);
end;

procedure TAtlasIdeAiBridgeTests.DailyLimitStopsTheRequest;
begin
  CreateBridge(False);
  FLimitReached := True;
  FBridge.Instruction('x', 'y');
  Assert.AreEqual(0, FText.AskCount, 'über der Tagesgrenze geht nichts hinaus');
  RunPosted;
  Assert.AreEqual('error g1 Tagesgrenze', LogText);
end;

procedure TAtlasIdeAiBridgeTests.CancelStopsAllRequests;
begin
  CreateBridge(False);
  FBridge.Chat('a');
  FBridge.Chat('b');
  FBridge.Cancel;
  Assert.AreEqual(2, FText.CancelledCount);
  Assert.AreEqual(0, FBridge.OpenCount);
  FText.Complete(1, TAtlasAiTextStatus.Ok, 'zu spät');
  RunPosted;
  Assert.AreEqual('', LogText);
end;

procedure TAtlasIdeAiBridgeTests.ModelsAreListed;
begin
  CreateBridge(True);
  Assert.AreEqual('g1', FBridge.LoadModels);
  Assert.IsTrue(Assigned(FModels));
  FModels(TArray<string>.Create('llama3.1', 'qwen2.5-coder'), '');
  Assert.AreEqual('models g1 llama3.1,qwen2.5-coder', LogText);
  FLog.Clear;
  FModels(nil, 'nicht erreichbar');
  Assert.AreEqual('error g1 nicht erreichbar', LogText);
end;

procedure TAtlasIdeAiBridgeTests.WithoutListerModelsFail;
begin
  CreateBridge(False);
  FBridge.LoadModels;
  RunPosted;
  Assert.AreEqual('error g1 keine Modelle', LogText);
end;

procedure TAtlasIdeAiBridgeTests.RemovedNotifierHearsNothing;
var
  mSecond: TList<string>;
  mIndex: Integer;
begin
  CreateBridge(False);
  mSecond := TList<string>.Create;
  try
    mIndex := FBridge.AddNotifier(TFakeAnswers.Create(mSecond));
    FBridge.Chat('a');
    FText.Complete(1, TAtlasAiTextStatus.Ok, 'eins');
    RunPosted;
    Assert.AreEqual(1, mSecond.Count);
    FBridge.RemoveNotifier(mIndex);
    FBridge.Chat('b');
    FText.Complete(2, TAtlasAiTextStatus.Ok, 'zwei');
    RunPosted;
    Assert.AreEqual(1, mSecond.Count);
    Assert.AreEqual('answer g1 eins; answer g2 zwei', LogText);
  finally
    mSecond.Free;
  end;
end;

procedure TAtlasIdeAiBridgeTests.AfterStopNothingReachesTheIde;
begin
  CreateBridge(True);
  FBridge.Chat('a');
  FBridge.LoadModels;
  FBridge.Stop;
  Assert.AreEqual(1, FText.CancelledCount);
  Assert.IsFalse(FBridge.Enabled);
  // Die Modellliste kommt aus dem Hintergrund erst nach Stop.
  FModels(TArray<string>.Create('spät'), '');
  RunPosted;
  Assert.AreEqual('', LogText);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIdeAiBridgeTests);

end.
