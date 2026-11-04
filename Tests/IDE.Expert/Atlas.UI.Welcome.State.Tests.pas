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
  Line: TAtlasStatusLine;
  Ref: IAtlasStatusItem;
  Action: TProc;
begin
  Action :=
    procedure
    begin
    end;
  if AAction then
  begin
    Line := TAtlasStatusLine.Create(ARegistry, AId, 0, Action);
  end
  else
  begin
    Line := TAtlasStatusLine.Create(ARegistry, AId, 0);
  end;
  Ref := Line;
  Assert.AreEqual(3, Integer(Length(ATexts)), 'Text, Kurzform, Einzelheit');
  Line.Update(ATexts[0], AState, '', ATexts[1], ATexts[2]);
  ARegistry.Add(Ref);
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
  Saved: TAtlasLanguage;
  Rows: TAtlasStateRows;
  Fake: TFakeState;
  Source: IAtlasStateSource;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Fake := StateFake;
    Source := Fake;
    Rows := Source.Rows;
    Assert.AreEqual('Server läuft', TAtlasWelcomeStateFrame.RowText(Rows[0]));
    Assert.AreEqual('seit 19:02', TAtlasWelcomeStateFrame.DetailText(Rows[0]));
    Assert.AreEqual('Einrichtung: 5 von 6 erledigt', TAtlasWelcomeStateFrame.RowText(Rows[3]));
    // Ohne Zeile im Statusfeld: Ersatztexte.
    Assert.AreEqual('Diagnosemodus aus', TAtlasWelcomeStateFrame.RowText(Rows[4]));
    Assert.AreEqual('', TAtlasWelcomeStateFrame.DetailText(Rows[4]));
    Assert.IsTrue(TAtlasWelcomeStateFrame.RowText(Rows[1]).StartsWith('Atlas '), 'Version ohne Update-Prüfung');
    Rows := TAtlasWelcomeState.Rows(nil);
    Assert.AreEqual('Einrichtung noch nicht geprüft', TAtlasWelcomeStateFrame.RowText(Rows[3]));
    Assert.AreEqual('Index unbekannt', TAtlasWelcomeStateFrame.RowText(Rows[2]));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Diagnostic mode off', TAtlasWelcomeStateFrame.RowText(Rows[4]));
    Assert.AreEqual('Restart server', TAtlasWelcomeStateFrame.ButtonCaption(TAtlasStateButton.Restart));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;
procedure TAtlasWelcomeStateFrameTests.UpdateButtonOnlyWithUpdate;
var
  Host: TForm;
  Fake: TFakeState;
  Source: IAtlasStateSource;
  Frame: TAtlasWelcomeStateFrame;
begin
  Fake := StateFake;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeStateFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Source := Source;
    Assert.AreEqual(5, Integer(Length(Frame.Rows)));
    Assert.IsTrue(Frame.Button(TAtlasStateButton.Restart).Visible);
    Assert.IsTrue(Frame.Button(TAtlasStateButton.Settings).Visible);
    Assert.IsTrue(Frame.Button(TAtlasStateButton.LogFolder).Visible);
    Assert.IsFalse(Frame.Button(TAtlasStateButton.Update).Visible);
    AddLine(Fake.Registry, TAtlasStatusLines.VersionId, TAtlasStatusState.Yellow,
      ['Version: Atlas 1.0.0, Update 1.0.1 bereit', 'Update 1.0.1 bereit', 'installiert 1.0.0'], True);
    Frame.UpdateContent;
    Assert.IsTrue(Frame.Button(TAtlasStateButton.Update).Visible);
    Assert.IsTrue(Frame.PreferredHeight > 5 * Frame.ScaleValue(TAtlasWelcomeStateFrame.RowHeight));
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeStateFrameTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeState;
  Source: IAtlasStateSource;
  Frame: TAtlasWelcomeStateFrame;
begin
  Fake := StateFake;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeStateFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Source := Source;
    // Zeile ohne Aktion (Server) und ohne Zeile im Statusfeld (Diagnosemodus): nichts.
    Frame.ClickRow(0);
    Frame.ClickRow(4);
    // Einrichtung: Aktion der Statusfeld-Zeile (Prüfliste).
    Frame.ClickRow(3);
    Frame.Button(TAtlasStateButton.Restart).Click;
    Frame.Button(TAtlasStateButton.LogFolder).Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(Fake.Calls)));
    Assert.AreEqual('row atlas.setup', Fake.Calls[0]);
    Assert.AreEqual(Format('button %d', [Ord(TAtlasStateButton.Restart)]), Fake.Calls[1]);
    Assert.AreEqual(Format('button %d', [Ord(TAtlasStateButton.LogFolder)]), Fake.Calls[2]);
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeStateFrameTests.HitTestFindsRows;
var
  Host: TForm;
  Fake: TFakeState;
  Source: IAtlasStateSource;
  Frame: TAtlasWelcomeStateFrame;
  Row: Integer;
begin
  Fake := StateFake;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeStateFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Source := Source;
    Row := Frame.ScaleValue(TAtlasWelcomeStateFrame.RowHeight);
    Assert.AreEqual(-1, Frame.HitTest(0));
    Assert.AreEqual(0, Frame.HitTest(Frame.ScaleValue(TAtlasWelcomeStateFrame.Indent) div 2 + 1));
    Assert.AreEqual(3, Frame.HitTest(Frame.ScaleValue(TAtlasWelcomeStateFrame.Indent) div 2 + 3 * Row + 1));
    Assert.AreEqual(-1, Frame.HitTest(Frame.ScaleValue(TAtlasWelcomeStateFrame.Indent) div 2 + 5 * Row + 1));
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeStateFrameTests);

end.
