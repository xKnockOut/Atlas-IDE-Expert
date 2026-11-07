unit Atlas.UI.Welcome.State.Tests;

// Tests des Zustandsbereichs der Willkommensseite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeStateFrameTests = class
  public
    [Test]
    procedure TextsUseLineOrFallback;
    [Test]
    procedure UpdateButtonOnlyWithUpdate;
    [Test]
    procedure ClicksReachSource;
    [Test]
    procedure HitTestFindsRows;
  end;

implementation

uses
  System.Classes,
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  Atlas.Core.Status.Lines,
  Atlas.UI.Strings,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Welcome.State,
  Atlas.UI.Welcome.State,
  Atlas.UI.Welcome.TestSupport;


type
  /// <summary>Quelle der Zustandskachel für die Tests; merkt sich die Aufrufe.</summary>
  TFakeState = class(TInterfacedObject, IAtlasStateSource)
  public
    Registry: IAtlasStatusRegistry;
    Calls: TArray<string>;
    function Rows: TAtlasStateRows;
    procedure RunRow(const AId: string);
    procedure Run(AButton: TAtlasStateButton);
  end;

{ TFakeState }

function TFakeState.Rows: TAtlasStateRows;
begin
  Result := TAtlasWelcomeState.Rows(Registry.Items);
end;
procedure TFakeState.RunRow(const AId: string);
begin
  Calls := Calls + ['row ' + AId];
end;
procedure TFakeState.Run(AButton: TAtlasStateButton);
begin
  Calls := Calls + [Format('button %d', [Ord(AButton)])];
end;
/// <summary>Zeile im Statusfeld; ATexts sind Text, Kurzform und Einzelheit; mit AAction anklickbar.</summary>
procedure AddLine(const ARegistry: IAtlasStatusRegistry; const AId: string; AState: TAtlasStatusState;
  const ATexts: array of string; AAction: Boolean);
var
  mLine: TAtlasStatusLine;
  mRef: IAtlasStatusItem;
  mAction: TProc;
begin
  mAction :=
    procedure
    begin
    end;
  if AAction then
  begin
    mLine := TAtlasStatusLine.Create(ARegistry, AId, 0, mAction);
  end
  else
  begin
    mLine := TAtlasStatusLine.Create(ARegistry, AId, 0);
  end;
  mRef := mLine;
  Assert.AreEqual(3, Integer(Length(ATexts)), 'Text, Kurzform, Einzelheit');
  mLine.Update(ATexts[0], AState, '', ATexts[1], ATexts[2]);
  ARegistry.Add(mRef);
end;
function StateFake: TFakeState;
begin
  Result := TFakeState.Create;
  Result.Registry := TAtlasStatusRegistry.Create;
  AddLine(Result.Registry, TAtlasStatusLines.ServerId, TAtlasStatusState.Green, ['Server: läuft seit 19:02',
    'Server läuft', 'seit 19:02'], False);
  AddLine(Result.Registry, TAtlasStatusLines.IndexId, TAtlasStatusState.Green, ['Index: 1284 Units',
    'Index: 1284 Units', 'indiziert 18:40'], False);
  AddLine(Result.Registry, TAtlasStatusLines.SetupId, TAtlasStatusState.Yellow, ['Einrichtung: 5 von 6 erledigt',
    '', ''], True);
end;
{ TAtlasWelcomeStateFrameTests }

procedure TAtlasWelcomeStateFrameTests.TextsUseLineOrFallback;
var
  mSaved: TAtlasLanguage;
  mRows: TAtlasStateRows;
  mFake: TFakeState;
  mSource: IAtlasStateSource;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mFake := StateFake;
    mSource := mFake;
    mRows := mSource.Rows;
    Assert.AreEqual('Server läuft', TAtlasWelcomeStateFrame.RowText(mRows[0]));
    Assert.AreEqual('seit 19:02', TAtlasWelcomeStateFrame.DetailText(mRows[0]));
    Assert.AreEqual('Einrichtung: 5 von 6 erledigt', TAtlasWelcomeStateFrame.RowText(mRows[3]));
    // Ohne Zeile im Statusfeld: Ersatztexte.
    Assert.AreEqual('Diagnosemodus aus', TAtlasWelcomeStateFrame.RowText(mRows[4]));
    Assert.AreEqual('', TAtlasWelcomeStateFrame.DetailText(mRows[4]));
    Assert.IsTrue(TAtlasWelcomeStateFrame.RowText(mRows[1]).StartsWith('Atlas '), 'Version ohne Update-Prüfung');
    mRows := TAtlasWelcomeState.Rows(nil);
    Assert.AreEqual('Einrichtung noch nicht geprüft', TAtlasWelcomeStateFrame.RowText(mRows[3]));
    Assert.AreEqual('Index unbekannt', TAtlasWelcomeStateFrame.RowText(mRows[2]));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Diagnostic mode off', TAtlasWelcomeStateFrame.RowText(mRows[4]));
    Assert.AreEqual('Restart server', TAtlasWelcomeStateFrame.ButtonCaption(TAtlasStateButton.Restart));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeStateFrameTests.UpdateButtonOnlyWithUpdate;
var
  mHost: TForm;
  mFake: TFakeState;
  mSource: IAtlasStateSource;
  mFrame: TAtlasWelcomeStateFrame;
begin
  mFake := StateFake;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeStateFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Source := mSource;
    Assert.AreEqual(5, Integer(Length(mFrame.Rows)));
    Assert.IsTrue(mFrame.Button(TAtlasStateButton.Restart).Visible);
    Assert.IsTrue(mFrame.Button(TAtlasStateButton.Settings).Visible);
    Assert.IsTrue(mFrame.Button(TAtlasStateButton.LogFolder).Visible);
    Assert.IsFalse(mFrame.Button(TAtlasStateButton.Update).Visible);
    AddLine(mFake.Registry, TAtlasStatusLines.VersionId, TAtlasStatusState.Yellow,
      ['Version: Atlas 1.0.0, Update 1.0.1 bereit', 'Update 1.0.1 bereit', 'installiert 1.0.0'], True);
    mFrame.UpdateContent;
    Assert.IsTrue(mFrame.Button(TAtlasStateButton.Update).Visible);
    Assert.IsTrue(mFrame.PreferredHeight > 5 * mFrame.ScaleValue(TAtlasWelcomeStateFrame.cRowHeight));
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeStateFrameTests.ClicksReachSource;
var
  mHost: TForm;
  mFake: TFakeState;
  mSource: IAtlasStateSource;
  mFrame: TAtlasWelcomeStateFrame;
begin
  mFake := StateFake;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeStateFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Source := mSource;
    // Zeile ohne Aktion (Server) und ohne Zeile im Statusfeld (Diagnosemodus): nichts.
    mFrame.ClickRow(0);
    mFrame.ClickRow(4);
    // Einrichtung: Aktion der Statusfeld-Zeile (Prüfliste).
    mFrame.ClickRow(3);
    mFrame.Button(TAtlasStateButton.Restart).Click;
    mFrame.Button(TAtlasStateButton.LogFolder).Click;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(mFake.Calls)));
    Assert.AreEqual('row atlas.setup', mFake.Calls[0]);
    Assert.AreEqual(Format('button %d', [Ord(TAtlasStateButton.Restart)]), mFake.Calls[1]);
    Assert.AreEqual(Format('button %d', [Ord(TAtlasStateButton.LogFolder)]), mFake.Calls[2]);
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeStateFrameTests.HitTestFindsRows;
var
  mHost: TForm;
  mFake: TFakeState;
  mSource: IAtlasStateSource;
  mFrame: TAtlasWelcomeStateFrame;
  mRow: Integer;
begin
  mFake := StateFake;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeStateFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Source := mSource;
    mRow := mFrame.ScaleValue(TAtlasWelcomeStateFrame.cRowHeight);
    Assert.AreEqual(-1, mFrame.HitTest(0));
    Assert.AreEqual(0, mFrame.HitTest(mFrame.ScaleValue(TAtlasWelcomeStateFrame.cIndent) div 2 + 1));
    Assert.AreEqual(3, mFrame.HitTest(mFrame.ScaleValue(TAtlasWelcomeStateFrame.cIndent) div 2 + 3 * mRow + 1));
    Assert.AreEqual(-1, mFrame.HitTest(mFrame.ScaleValue(TAtlasWelcomeStateFrame.cIndent) div 2 + 5 * mRow + 1));
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeStateFrameTests);

end.
