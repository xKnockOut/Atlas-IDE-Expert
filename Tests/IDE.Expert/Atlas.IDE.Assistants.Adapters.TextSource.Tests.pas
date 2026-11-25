unit Atlas.IDE.Assistants.Adapters.TextSource.Tests;

// Quelle für einfache Aufgaben (#2744): Wahl nach assistants.textSource und Stand der beiden Quellen, Weiterleitung
// samt Abbruch an die richtige Quelle, ausgeschlossene Dateien gehen nirgends hin.

interface

uses
  DUnitX.TestFramework,
  Atlas.IDE.Base.Foundation.AiText,
  Atlas.Tests.AiTextFake,
  Atlas.IDE.Assistants.Adapters.TextSource;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasAiTextSourceTests = class
  private
    FOwn: TAtlasFakeAiText;
    FOwnRef: IAtlasAiText;
    FIde: TAtlasFakeAiText;
    FIdeRef: IAtlasAiText;
    FSource: TAtlasAiTextSource;
    FSourceRef: IAtlasAiText;
    FChoice: string;
    FExclude: string;
    FLast: TAtlasAiTextResult;
    FCalls: Integer;
    function Remember: TAtlasAiTextDone;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ChooseFollowsTheSetting;
    [Test]
    procedure IdeIsPreferredByDefault;
    [Test]
    procedure OwnFallsBackToIde;
    [Test]
    procedure NoneSendsNothing;
    [Test]
    procedure ExcludedFileGoesNowhere;
    [Test]
    procedure CancelReachesTheRightSource;
    [Test]
    procedure AnswerComesBackOnce;
  end;

implementation

{ TAtlasAiTextSourceTests }

procedure TAtlasAiTextSourceTests.Setup;
var
  mSelf: TAtlasAiTextSourceTests;
begin
  FOwn := TAtlasFakeAiText.Create(True, 'Anthropic-API');
  FOwnRef := FOwn;
  FIde := TAtlasFakeAiText.Create(True, 'OpenAI');
  FIdeRef := FIde;
  FChoice := TAtlasAiTextSource.cIde;
  FExclude := '*\Geheim\*';
  FCalls := 0;
  mSelf := Self;
  FSource := TAtlasAiTextSource.Create(FOwnRef, FIdeRef,
    function: TAtlasAiTextSourceOptions
    begin
      Result := Default(TAtlasAiTextSourceOptions);
      Result.Source := mSelf.FChoice;
      Result.Exclude := mSelf.FExclude;
    end, 'ausgeschlossen');
  FSourceRef := FSource;
end;

procedure TAtlasAiTextSourceTests.TearDown;
begin
  FSourceRef := nil;
  FSource := nil;
  FOwnRef := nil;
  FOwn := nil;
  FIdeRef := nil;
  FIde := nil;
  FChoice := '';
  FExclude := '';
  FLast := Default(TAtlasAiTextResult);
end;

function TAtlasAiTextSourceTests.Remember: TAtlasAiTextDone;
var
  mSelf: TAtlasAiTextSourceTests;
begin
  mSelf := Self;
  Result :=
    procedure(const AResult: TAtlasAiTextResult)
    begin
      mSelf.FLast := AResult;
      Inc(mSelf.FCalls);
    end;
end;

function Request(const AFileName: string): TAtlasAiTextRequest;
begin
  Result := Default(TAtlasAiTextRequest);
  Result.Task := 'Inhalt';
  Result.FileName := AFileName;
end;

procedure TAtlasAiTextSourceTests.ChooseFollowsTheSetting;
begin
  Assert.AreEqual<TAtlasAiTextPick>(TAtlasAiTextPick.Ide, TAtlasAiTextSource.Choose('ide', True, True));
  Assert.AreEqual<TAtlasAiTextPick>(TAtlasAiTextPick.Own, TAtlasAiTextSource.Choose('ide', True, False));
  Assert.AreEqual<TAtlasAiTextPick>(TAtlasAiTextPick.Own, TAtlasAiTextSource.Choose('own', True, True));
  Assert.AreEqual<TAtlasAiTextPick>(TAtlasAiTextPick.Ide, TAtlasAiTextSource.Choose('OWN', False, True));
  Assert.AreEqual<TAtlasAiTextPick>(TAtlasAiTextPick.None, TAtlasAiTextSource.Choose('none', True, True));
  Assert.AreEqual<TAtlasAiTextPick>(TAtlasAiTextPick.None, TAtlasAiTextSource.Choose('ide', False, False));
end;

procedure TAtlasAiTextSourceTests.IdeIsPreferredByDefault;
begin
  Assert.AreEqual('OpenAI', FSource.ProviderName);
  FSource.Ask(Request(''), Remember());
  Assert.AreEqual(1, FIde.AskCount);
  Assert.AreEqual(0, FOwn.AskCount);
end;

procedure TAtlasAiTextSourceTests.OwnFallsBackToIde;
begin
  FChoice := TAtlasAiTextSource.cOwn;
  FOwn.IsReady := False;
  Assert.IsTrue(FSource.Ready);
  Assert.AreEqual('OpenAI', FSource.ProviderName);
  FOwn.IsReady := True;
  Assert.AreEqual('Anthropic-API', FSource.ProviderName);
end;

procedure TAtlasAiTextSourceTests.NoneSendsNothing;
begin
  FChoice := TAtlasAiTextSource.cNone;
  Assert.IsFalse(FSource.Ready);
  Assert.AreEqual(0, FSource.Ask(Request(''), Remember()));
  Assert.AreEqual<TAtlasAiTextStatus>(TAtlasAiTextStatus.NotReady, FLast.Status);
  Assert.AreEqual(0, FIde.AskCount + FOwn.AskCount);
end;

procedure TAtlasAiTextSourceTests.ExcludedFileGoesNowhere;
begin
  Assert.AreEqual(0, FSource.Ask(Request('C:\Projekt\Geheim\Schluessel.pas'), Remember()));
  Assert.AreEqual<TAtlasAiTextStatus>(TAtlasAiTextStatus.Failed, FLast.Status);
  Assert.AreEqual('ausgeschlossen', FLast.Error);
  Assert.AreEqual(0, FIde.AskCount + FOwn.AskCount);
  Assert.IsTrue(FSource.Ask(Request('C:\Projekt\Offen\Main.pas'), Remember()) > 0);
  Assert.AreEqual(1, FIde.AskCount);
end;

procedure TAtlasAiTextSourceTests.CancelReachesTheRightSource;
var
  mIdeTicket: Integer;
  mOwnTicket: Integer;
begin
  mIdeTicket := FSource.Ask(Request(''), Remember());
  FChoice := TAtlasAiTextSource.cOwn;
  mOwnTicket := FSource.Ask(Request(''), Remember());
  Assert.AreNotEqual(mIdeTicket, mOwnTicket);
  FSource.Cancel(mOwnTicket);
  Assert.AreEqual(1, FOwn.CancelledCount);
  Assert.AreEqual(0, FIde.CancelledCount);
  FSource.Cancel(mIdeTicket);
  Assert.AreEqual(1, FIde.CancelledCount);
  FSource.Cancel(mIdeTicket);
  Assert.AreEqual(1, FIde.CancelledCount, 'zweites Cancel: nichts');
end;

procedure TAtlasAiTextSourceTests.AnswerComesBackOnce;
var
  mTicket: Integer;
begin
  mTicket := FSource.Ask(Request(''), Remember());
  FIde.Complete(1, TAtlasAiTextStatus.Ok, 'Antwort');
  Assert.AreEqual(1, FCalls);
  Assert.AreEqual('Antwort', FLast.Text);
  FSource.Cancel(mTicket);
  Assert.AreEqual(0, FIde.CancelledCount, 'beantwortet: nichts mehr abzubrechen');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAiTextSourceTests);

end.
