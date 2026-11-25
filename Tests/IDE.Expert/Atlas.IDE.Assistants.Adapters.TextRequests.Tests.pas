unit Atlas.IDE.Assistants.Adapters.TextRequests.Tests;

// Text von einem Anbieter der IDE (#2744) mit gefälschtem Anbieter: Auswahl, Anweisung oder Chat, Zuordnung der
// Antworten über die Kennung, Fehler, Abbruch und Stop.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  Atlas.IDE.Base.Foundation.AiText,
  Atlas.Core.Assistants.Contract.IdeAi,
  Atlas.IDE.Assistants.Adapters.TextRequests;

type
  /// <summary>Anbieter der IDE zum Mitschreiben; Kennungen „id1“, „id2“ …</summary>
  TFakeIdeEngine = class(TInterfacedObject, IAtlasIdeAiEngine)
  private
    FProviders: TArray<TAtlasIdeAiProvider>;
    FLog: TList<string>;
    FNext: Integer;
    FRefuse: Boolean;
  public
    constructor Create(const AProviders: TArray<TAtlasIdeAiProvider>);
    destructor Destroy; override;
    function Providers: TArray<TAtlasIdeAiProvider>;
    function Instruction(const AName, AInput, AInstruction: string): string;
    function Chat(const AName, AQuestion: string): string;
    procedure Cancel(const AName: string);
    function LogText: string;
    property Refuse: Boolean read FRefuse write FRefuse;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasIdeAiTextRequestsTests = class
  private
    FEngine: TFakeIdeEngine;
    FEngineRef: IAtlasIdeAiEngine;
    FRequests: TAtlasIdeAiTextRequests;
    FRequestsRef: IAtlasAiText;
    FEnabled: Boolean;
    FWanted: string;
    FResults: TList<TAtlasAiTextResult>;
    function Request(const ATask: string): TAtlasAiTextRequest;
    function Collect: TAtlasAiTextDone;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SwitchOffMeansNotReady;
    [Test]
    procedure InstructionGoesSeparately;
    [Test]
    procedure ChatOnlyProviderGetsOneText;
    [Test]
    procedure AnswersFindTheirCallers;
    [Test]
    procedure UnknownAnswerIsDropped;
    [Test]
    procedure ErrorNamesTheProvider;
    [Test]
    procedure RefusedRequestFailsAtOnce;
    [Test]
    procedure CancelWaitsForTheLastRequest;
    [Test]
    procedure StopCancelsEverything;
  end;

implementation

uses
  System.SysUtils;

{ TFakeIdeEngine }

constructor TFakeIdeEngine.Create(const AProviders: TArray<TAtlasIdeAiProvider>);
begin
  inherited Create;
  FProviders := AProviders;
  FLog := TList<string>.Create;
end;

destructor TFakeIdeEngine.Destroy;
begin
  FreeAndNil(FLog);
  inherited Destroy;
end;

function TFakeIdeEngine.Providers: TArray<TAtlasIdeAiProvider>;
begin
  Result := FProviders;
end;

function TFakeIdeEngine.Instruction(const AName, AInput, AInstruction: string): string;
begin
  FLog.Add(Format('instruction %s [%s] [%s]', [AName, AInput, AInstruction]));
  Result := '';
  if not FRefuse then
  begin
    Inc(FNext);
    Result := 'id' + IntToStr(FNext);
  end;
end;

function TFakeIdeEngine.Chat(const AName, AQuestion: string): string;
begin
  FLog.Add(Format('chat %s [%s]', [AName, AQuestion.Replace(sLineBreak, '|')]));
  Result := '';
  if not FRefuse then
  begin
    Inc(FNext);
    Result := 'id' + IntToStr(FNext);
  end;
end;

procedure TFakeIdeEngine.Cancel(const AName: string);
begin
  FLog.Add('cancel ' + AName);
end;

function TFakeIdeEngine.LogText: string;
begin
  Result := string.Join('; ', FLog.ToArray);
end;

{ TAtlasIdeAiTextRequestsTests }

procedure TAtlasIdeAiTextRequestsTests.Setup;
var
  mSelf: TAtlasIdeAiTextRequestsTests;
begin
  FEngine := TFakeIdeEngine.Create(TArray<TAtlasIdeAiProvider>.Create(
    TAtlasIdeAiProvider.Make('Atlas (lokal)', True, [TAtlasIdeAiFeature.Instruction]),
    TAtlasIdeAiProvider.Make('OpenAI', True, [TAtlasIdeAiFeature.Chat, TAtlasIdeAiFeature.Instruction]),
    TAtlasIdeAiProvider.Make('Gemini', True, [TAtlasIdeAiFeature.Chat])));
  FEngineRef := FEngine;
  FEnabled := True;
  FWanted := '';
  FResults := TList<TAtlasAiTextResult>.Create;
  mSelf := Self;
  FRequests := TAtlasIdeAiTextRequests.Create(FEngineRef,
    function: TAtlasIdeAiTextOptions
    begin
      Result := Default(TAtlasIdeAiTextOptions);
      Result.Enabled := mSelf.FEnabled;
      Result.Wanted := mSelf.FWanted;
    end, 'abgelehnt von %s');
  FRequestsRef := FRequests;
end;

procedure TAtlasIdeAiTextRequestsTests.TearDown;
begin
  FRequestsRef := nil;
  FRequests := nil;
  FEngineRef := nil;
  FEngine := nil;
  FreeAndNil(FResults);
  FWanted := '';
end;

function TAtlasIdeAiTextRequestsTests.Request(const ATask: string): TAtlasAiTextRequest;
begin
  Result := Default(TAtlasAiTextRequest);
  Result.Instructions := 'Fasse zusammen';
  Result.Task := ATask;
end;

function TAtlasIdeAiTextRequestsTests.Collect: TAtlasAiTextDone;
var
  mResults: TList<TAtlasAiTextResult>;
begin
  mResults := FResults;
  Result :=
    procedure(const AResult: TAtlasAiTextResult)
    begin
      mResults.Add(AResult);
    end;
end;

procedure TAtlasIdeAiTextRequestsTests.SwitchOffMeansNotReady;
begin
  FEnabled := False;
  Assert.IsFalse(FRequests.Ready);
  Assert.AreEqual('', FRequests.ProviderName);
  Assert.AreEqual(0, FRequests.Ask(Request('x'), Collect()));
  Assert.AreEqual(1, Integer(FResults.Count));
  Assert.AreEqual<TAtlasAiTextStatus>(TAtlasAiTextStatus.NotReady, FResults[0].Status);
  Assert.AreEqual('', FEngine.LogText, 'nichts gesendet');
end;

procedure TAtlasIdeAiTextRequestsTests.InstructionGoesSeparately;
begin
  Assert.IsTrue(FRequests.Ready);
  Assert.AreEqual('OpenAI', FRequests.ProviderName, 'Atlas selbst übersprungen');
  Assert.IsTrue(FRequests.Ask(Request('Text'), Collect()) > 0);
  Assert.AreEqual('instruction OpenAI [Text] [Fasse zusammen]', FEngine.LogText);
end;

procedure TAtlasIdeAiTextRequestsTests.ChatOnlyProviderGetsOneText;
begin
  FWanted := 'Gemini';
  FRequests.Ask(Request('Text'), Collect());
  Assert.AreEqual('chat Gemini [Fasse zusammen||Text]', FEngine.LogText);
end;

procedure TAtlasIdeAiTextRequestsTests.AnswersFindTheirCallers;
var
  mFirst: TList<string>;
  mSecond: TList<string>;
begin
  mFirst := TList<string>.Create;
  mSecond := TList<string>.Create;
  try
    FRequests.Ask(Request('a'),
      procedure(const AResult: TAtlasAiTextResult)
      begin
        mFirst.Add(AResult.Text);
      end);
    FRequests.Ask(Request('b'),
      procedure(const AResult: TAtlasAiTextResult)
      begin
        mSecond.Add(AResult.Text);
      end);
    Assert.AreEqual(2, FRequests.OpenCount);
    FRequests.Answered('id2', 'zwei');
    FRequests.Answered('id1', 'eins');
    FRequests.Answered('id1', 'doppelt');
    Assert.AreEqual('eins', string.Join(',', mFirst.ToArray));
    Assert.AreEqual('zwei', string.Join(',', mSecond.ToArray));
    Assert.AreEqual(0, FRequests.OpenCount);
  finally
    mSecond.Free;
    mFirst.Free;
  end;
end;

procedure TAtlasIdeAiTextRequestsTests.UnknownAnswerIsDropped;
begin
  FRequests.Ask(Request('a'), Collect());
  FRequests.Answered('fremd', 'x');
  FRequests.Failed('fremd', 'x');
  Assert.AreEqual(0, Integer(FResults.Count));
  Assert.AreEqual(1, FRequests.OpenCount);
end;

procedure TAtlasIdeAiTextRequestsTests.ErrorNamesTheProvider;
begin
  FRequests.Ask(Request('a'), Collect());
  FRequests.Failed('id1', 'Kontingent erschöpft');
  Assert.AreEqual(1, Integer(FResults.Count));
  Assert.AreEqual<TAtlasAiTextStatus>(TAtlasAiTextStatus.Failed, FResults[0].Status);
  Assert.AreEqual('OpenAI: Kontingent erschöpft', FResults[0].Error);
end;

procedure TAtlasIdeAiTextRequestsTests.RefusedRequestFailsAtOnce;
begin
  FEngine.Refuse := True;
  Assert.AreEqual(0, FRequests.Ask(Request('a'), Collect()));
  Assert.AreEqual(1, Integer(FResults.Count));
  Assert.AreEqual('abgelehnt von OpenAI', FResults[0].Error);
end;

procedure TAtlasIdeAiTextRequestsTests.CancelWaitsForTheLastRequest;
var
  mFirst: Integer;
  mSecond: Integer;
begin
  mFirst := FRequests.Ask(Request('a'), Collect());
  mSecond := FRequests.Ask(Request('b'), Collect());
  FRequests.Cancel(mFirst);
  Assert.IsFalse(FEngine.LogText.Contains('cancel'), 'die zweite Anfrage läuft noch');
  FRequests.Answered('id1', 'zu spät');
  Assert.AreEqual(0, Integer(FResults.Count), 'nach Cancel kein Rückruf');
  FRequests.Cancel(mSecond);
  Assert.IsTrue(FEngine.LogText.EndsWith('cancel OpenAI'));
  FRequests.Cancel(4711);
end;

procedure TAtlasIdeAiTextRequestsTests.StopCancelsEverything;
begin
  FRequests.Ask(Request('a'), Collect());
  FWanted := 'Gemini';
  FRequests.Ask(Request('b'), Collect());
  FRequests.Stop;
  Assert.AreEqual(2, Integer(FResults.Count));
  Assert.AreEqual<TAtlasAiTextStatus>(TAtlasAiTextStatus.Cancelled, FResults[0].Status);
  Assert.AreEqual<TAtlasAiTextStatus>(TAtlasAiTextStatus.Cancelled, FResults[1].Status);
  Assert.IsTrue(FEngine.LogText.Contains('cancel OpenAI'));
  Assert.IsTrue(FEngine.LogText.Contains('cancel Gemini'));
  Assert.IsFalse(FRequests.Ready, 'nach Stop nie mehr bereit');
  FRequests.Answered('id1', 'zu spät');
  Assert.AreEqual(2, Integer(FResults.Count));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIdeAiTextRequestsTests);

end.
