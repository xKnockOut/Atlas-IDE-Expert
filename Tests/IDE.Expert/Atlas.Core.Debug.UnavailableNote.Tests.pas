unit Atlas.Core.Debug.UnavailableNote.Tests;

// Tests für den Hinweis zu „kein Zugriff auf Wert“ (#840, #1967): erklären oder nicht, Server fragen,
// Projektoption und Ursprung, Lage der Variablen, Korrektur zum Knopf; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasUnavailableNoteTests = class
  public
    [Test]
    procedure ExplainsOnlyKnownFailures;
    [Test]
    procedure AsksServerWithEverything;
    [Test]
    procedure OptionAndLifetimeOfCause;
    [Test]
    procedure OriginOfSwitch;
    [Test]
    procedure JoinsSentences;
    [Test]
    procedure FixOfButton;
    [Test]
    procedure FixBelongsToLastExplanation;
  end;

implementation

uses
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.Unavailable,
  Atlas.Core.Debug.UnavailableNote;

function Failed(const AText: string): TAtlasDebugValue;
begin
  Result := Default(TAtlasDebugValue);
  Result.Expression := 'mKunde';
  Result.State := TAtlasDebugValueState.Failed;
  Result.Text := AText;
end;

function Switch(AKnown: Boolean; ASource: TAtlasSwitchSource; const AFileName: string): TAtlasUnavailableSwitch;
begin
  Result := Default(TAtlasUnavailableSwitch);
  Result.Known := AKnown;
  Result.Source := ASource;
  Result.FileName := AFileName;
end;

{ TAtlasUnavailableNoteTests }

procedure TAtlasUnavailableNoteTests.ExplainsOnlyKnownFailures;
var
  mValue: TAtlasDebugValue;
begin
  Assert.IsTrue(TAtlasUnavailableNote.CanExplain(Failed('inaccessible value'), nil));
  Assert.IsFalse(TAtlasUnavailableNote.CanExplain(Failed('Access violation at address 0040A1B2'), nil));
  Assert.IsTrue(TAtlasUnavailableNote.CanExplain(Failed('Wert weg'), ['Wert weg']));
  mValue := Failed('inaccessible value');
  mValue.State := TAtlasDebugValueState.Value;
  Assert.IsFalse(TAtlasUnavailableNote.CanExplain(mValue, nil));
end;

procedure TAtlasUnavailableNoteTests.AsksServerWithEverything;
begin
  Assert.IsTrue(TAtlasUnavailableNote.AskServer(True, True, 'mKunde'));
  Assert.IsFalse(TAtlasUnavailableNote.AskServer(False, True, 'mKunde'));
  Assert.IsFalse(TAtlasUnavailableNote.AskServer(True, False, 'mKunde'));
  Assert.IsFalse(TAtlasUnavailableNote.AskServer(True, True, ''));
end;

procedure TAtlasUnavailableNoteTests.OptionAndLifetimeOfCause;
begin
  Assert.AreEqual(TAtlasUnavailableNote.cDebugInfoOption,
    TAtlasUnavailableNote.OptionOf(TAtlasUnavailableCause.NoDebugInfo));
  Assert.AreEqual(TAtlasUnavailableNote.cLocalSymbolsOption,
    TAtlasUnavailableNote.OptionOf(TAtlasUnavailableCause.NoLocalSymbols));
  Assert.AreEqual(TAtlasUnavailableNote.cOptimizeOption,
    TAtlasUnavailableNote.OptionOf(TAtlasUnavailableCause.Optimization));
  Assert.AreEqual('', TAtlasUnavailableNote.OptionOf(TAtlasUnavailableCause.Lifetime));
  Assert.IsTrue(TAtlasUnavailableNote.WithLifetime(TAtlasUnavailableCause.Optimization));
  Assert.IsTrue(TAtlasUnavailableNote.WithLifetime(TAtlasUnavailableCause.Lifetime));
  Assert.IsFalse(TAtlasUnavailableNote.WithLifetime(TAtlasUnavailableCause.ReleaseBuild));
end;

procedure TAtlasUnavailableNoteTests.OriginOfSwitch;
begin
  Assert.AreEqual<TAtlasUnavailableOrigin>(TAtlasUnavailableOrigin.None,
    TAtlasUnavailableNote.OriginOf(Switch(False, TAtlasSwitchSource.Project, '')));
  Assert.AreEqual<TAtlasUnavailableOrigin>(TAtlasUnavailableOrigin.Directive,
    TAtlasUnavailableNote.OriginOf(Switch(True, TAtlasSwitchSource.Include, 'Opt.inc')));
  // Direktive ohne Datei: kein Ursprung.
  Assert.AreEqual<TAtlasUnavailableOrigin>(TAtlasUnavailableOrigin.None,
    TAtlasUnavailableNote.OriginOf(Switch(True, TAtlasSwitchSource.Directive, '')));
  Assert.AreEqual<TAtlasUnavailableOrigin>(TAtlasUnavailableOrigin.Project,
    TAtlasUnavailableNote.OriginOf(Switch(True, TAtlasSwitchSource.Project, '')));
  Assert.AreEqual<TAtlasUnavailableOrigin>(TAtlasUnavailableOrigin.Default,
    TAtlasUnavailableNote.OriginOf(Switch(True, TAtlasSwitchSource.Default, '')));
end;

procedure TAtlasUnavailableNoteTests.JoinsSentences;
begin
  Assert.AreEqual('Optimiert. Nicht mehr benutzt.', TAtlasUnavailableNote.Joined('Optimiert.',
    'Nicht mehr benutzt.'));
  Assert.AreEqual('Optimiert.', TAtlasUnavailableNote.Joined('Optimiert.', ''));
end;

procedure TAtlasUnavailableNoteTests.FixOfButton;
var
  mValue: TAtlasDebugValue;
  mFix: TAtlasUnavailableFix;
begin
  mValue := Failed('inaccessible value');
  mValue.Note.Fixes := [TAtlasDebugValueFix.Create(Ord(TAtlasUnavailableFix.DebugDcus), 'Debug-DCUs'),
    TAtlasDebugValueFix.Create(99, 'fremd')];
  Assert.IsTrue(TAtlasUnavailableNote.FixOf(mValue, 0, mFix));
  Assert.AreEqual<TAtlasUnavailableFix>(TAtlasUnavailableFix.DebugDcus, mFix);
  Assert.IsFalse(TAtlasUnavailableNote.FixOf(mValue, 1, mFix));
  Assert.IsFalse(TAtlasUnavailableNote.FixOf(mValue, 2, mFix));
  Assert.IsFalse(TAtlasUnavailableNote.FixOf(mValue, -1, mFix));
end;

procedure TAtlasUnavailableNoteTests.FixBelongsToLastExplanation;
var
  mExplanation: TAtlasUnavailableExplanation;
begin
  mExplanation := Default(TAtlasUnavailableExplanation);
  mExplanation.Fixes := [TAtlasUnavailableFix.RestartWithDebug];
  Assert.IsTrue(TAtlasUnavailableNote.FixAllowed('mKunde', 'mKunde', mExplanation,
    TAtlasUnavailableFix.RestartWithDebug));
  Assert.IsFalse(TAtlasUnavailableNote.FixAllowed('mKunde', 'mLager', mExplanation,
    TAtlasUnavailableFix.RestartWithDebug));
  Assert.IsFalse(TAtlasUnavailableNote.FixAllowed('mKunde', 'mKunde', mExplanation,
    TAtlasUnavailableFix.DebugDcus));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnavailableNoteTests);

end.
