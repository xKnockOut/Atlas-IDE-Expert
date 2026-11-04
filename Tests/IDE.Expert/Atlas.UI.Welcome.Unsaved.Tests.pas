unit Atlas.UI.Welcome.Unsaved.Tests;

// Tests des Bereichs ungesicherter Änderungen der Willkommensseite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeUnsavedFrameTests = class
  public
    [Test]
    procedure TextsFollowKindAndAge;
    [Test]
    procedure EmptyTextNamesState;
    [Test]
    procedure OnlyButtonAndMenuReachSource;
    [Test]
    procedure PushDialogCancelsByDefault;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.UI.Strings,
  System.DateUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Welcome.Unsaved,
  Atlas.UI.Welcome.Unsaved,
  Atlas.UI.Welcome.Push,
  Atlas.UI.Welcome.TestSupport;


type
  /// <summary>Quelle des Bereichs „Nicht gesichert“ für die Tests; merkt sich die Aufrufe.</summary>
  TFakeUnsaved = class(TInterfacedObject, IAtlasUnsavedSource)
  public
    FView: TAtlasUnsavedView;
    Calls: TArray<string>;
    function View: TAtlasUnsavedView;
    procedure Show(const ARow: TAtlasUnsavedRow);
    procedure Push(const ARow: TAtlasUnsavedRow);
    procedure OpenFolder(const ARow: TAtlasUnsavedRow);
    procedure Ignore(const ARow: TAtlasUnsavedRow);
    procedure Shown;
  end;

{ TFakeUnsaved }

function TFakeUnsaved.View: TAtlasUnsavedView;
begin
  Result := FView;
end;
procedure TFakeUnsaved.Show(const ARow: TAtlasUnsavedRow);
begin
  Calls := Calls + ['show ' + ARow.Name + ' ' + TAtlasWelcomeUnsaved.KindName(ARow.Item.Kind)];
end;
procedure TFakeUnsaved.Push(const ARow: TAtlasUnsavedRow);
begin
  Calls := Calls + ['push ' + ARow.Name + ' ' + TAtlasWelcomeUnsaved.KindName(ARow.Item.Kind)];
end;
procedure TFakeUnsaved.OpenFolder(const ARow: TAtlasUnsavedRow);
begin
  Calls := Calls + ['folder ' + ARow.Name];
end;
procedure TFakeUnsaved.Ignore(const ARow: TAtlasUnsavedRow);
begin
  Calls := Calls + ['ignore ' + ARow.Name + ' ' + TAtlasWelcomeUnsaved.KindName(ARow.Item.Kind)];
end;
procedure TFakeUnsaved.Shown;
begin
  Calls := Calls + ['shown'];
end;
function UnsavedRow(const AName: string; AKind: TAtlasUnsavedKind; ACount: Integer;
  ASince: TDateTime): TAtlasUnsavedRow;
begin
  Result := Default(TAtlasUnsavedRow);
  Result.Project := 'C:\P\' + AName + '.dproj';
  Result.Name := AName;
  Result.Branch := 'main';
  Result.VcsKind := 'git';
  Result.Item := TAtlasUnsavedItem.Create(AKind, ACount);
  Result.Item.Since := ASince;
end;
{ TAtlasWelcomeUnsavedFrameTests }

procedure TAtlasWelcomeUnsavedFrameTests.TextsFollowKindAndAge;
var
  Saved: TAtlasLanguage;
  NowUtc: TDateTime;
  Row: TAtlasUnsavedRow;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    NowUtc := EncodeDateTime(2026, 10, 15, 12, 0, 0, 0);
    // Abnahme: SVN-Projekt mit 2 geänderten Dateien.
    Row := UnsavedRow('Svn', TAtlasUnsavedKind.Changes, 2, IncHour(NowUtc, -3));
    Row.Item.Modified := 2;
    Assert.AreEqual('2 Dateien geändert', TAtlasWelcomeUnsavedFrame.WhatText(Row.Item));
    Assert.AreEqual('2 Dateien geändert · seit 3 Std.', TAtlasWelcomeUnsavedFrame.DetailText(Row, NowUtc));
    Assert.AreEqual('Ansehen', TAtlasWelcomeUnsavedFrame.ButtonText(Row.Item));
    Assert.AreEqual('Svn · main', TAtlasWelcomeUnsavedFrame.TitleText(Row));
    // #1292: Anteile je Arbeitskopie hinter der Summe.
    Row.Item.Places := [TAtlasUnsavedPlace.Create('', 1), TAtlasUnsavedPlace.Create('Packages/Drucken', 1)];
    Assert.AreEqual('2 Dateien geändert (Svn 1 · Packages\Drucken 1) · seit 3 Std.',
      TAtlasWelcomeUnsavedFrame.DetailText(Row, NowUtc));
    Row.Item.Places := nil;
    Row.Item.Count := 1;
    Row.Item.Modified := 1;
    Assert.AreEqual('1 Datei geändert', TAtlasWelcomeUnsavedFrame.WhatText(Row.Item));
    // Gemischt: geändert, neu, gelöscht.
    Row.Item.Count := 4;
    Row.Item.Modified := 2;
    Row.Item.Added := 1;
    Row.Item.Deleted := 1;
    Assert.AreEqual('4 Dateien: 2 geändert, 1 neu, 1 gelöscht', TAtlasWelcomeUnsavedFrame.WhatText(Row.Item));
    Row := UnsavedRow('Git', TAtlasUnsavedKind.Commits, 3, IncDay(NowUtc, -2));
    Row.Item.Branches := ['main'];
    Assert.AreEqual('3 Commits nicht gepusht (main) · seit 2 Tagen',
      TAtlasWelcomeUnsavedFrame.DetailText(Row, NowUtc));
    Assert.AreEqual('Push …', TAtlasWelcomeUnsavedFrame.ButtonText(Row.Item));
    Row := UnsavedRow('Git', TAtlasUnsavedKind.NoUpstream, 1, 0);
    Row.Item.Branches := ['feature/x'];
    Row.Item.Commits := 2;
    Assert.AreEqual('Branch feature/x ohne Upstream, 2 Commits nur lokal',
      TAtlasWelcomeUnsavedFrame.DetailText(Row, NowUtc), 'ohne Alter keine Zeitangabe');
    Assert.AreEqual('Push …', TAtlasWelcomeUnsavedFrame.ButtonText(Row.Item));
    Row := UnsavedRow('Git', TAtlasUnsavedKind.Conflicts, 2, 0);
    Assert.AreEqual('2 Dateien im Konflikt', TAtlasWelcomeUnsavedFrame.WhatText(Row.Item));
    Assert.AreEqual('Ansehen', TAtlasWelcomeUnsavedFrame.ButtonText(Row.Item));
    Row := UnsavedRow('Git', TAtlasUnsavedKind.Stashes, 1, IncMinute(NowUtc, -20));
    Row.Item.Name := 'Versuch';
    Assert.StartsWith('Stash „Versuch“ vom ', TAtlasWelcomeUnsavedFrame.WhatText(Row.Item));
    Assert.EndsWith(' · seit 20 Min.', TAtlasWelcomeUnsavedFrame.DetailText(Row, NowUtc));
    Assert.AreEqual('Ansehen', TAtlasWelcomeUnsavedFrame.ButtonText(Row.Item));
    Assert.AreEqual('seit 1 Tag', TAtlasWelcomeUnsavedFrame.AgeText(IncHour(NowUtc, -30), NowUtc));
    Assert.AreEqual('', TAtlasWelcomeUnsavedFrame.AgeText(0, NowUtc));
    Assert.IsTrue(TAtlasWelcomeUnsavedFrame.LevelColor(TAtlasUnsavedLevel.Fresh) <>
      TAtlasWelcomeUnsavedFrame.LevelColor(TAtlasUnsavedLevel.Alert), 'rot ist nicht grün');
    Assert.IsTrue(TAtlasWelcomeUnsavedFrame.LevelColor(TAtlasUnsavedLevel.Warning) <>
      TAtlasWelcomeUnsavedFrame.LevelColor(TAtlasUnsavedLevel.Alert), 'gelb ist nicht rot');
    Assert.Contains(TAtlasWelcomeUnsavedFrame.HintFor(Row), 'C:\P\Git.dproj');
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('View', TAtlasWelcomeUnsavedFrame.ButtonText(Row.Item));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;
procedure TAtlasWelcomeUnsavedFrameTests.EmptyTextNamesState;
var
  Saved: TAtlasLanguage;
  View: TAtlasUnsavedView;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    View := Default(TAtlasUnsavedView);
    View.Known := True;
    Assert.AreEqual('Alles gesichert', TAtlasWelcomeUnsavedFrame.EmptyText(View));
    View.Known := False;
    View.Querying := True;
    Assert.AreEqual('Versionsverwaltung wird abgefragt …', TAtlasWelcomeUnsavedFrame.EmptyText(View));
    View.Hidden := 2;
    Assert.StartsWith('Nichts zu zeigen (2 ', TAtlasWelcomeUnsavedFrame.EmptyText(View));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;
procedure TAtlasWelcomeUnsavedFrameTests.OnlyButtonAndMenuReachSource;
var
  Host: TForm;
  Fake: TFakeUnsaved;
  Source: IAtlasUnsavedSource;
  Frame: TAtlasWelcomeUnsavedFrame;
  Hit: TAtlasUnsavedHit;
  Height: Integer;
begin
  Fake := TFakeUnsaved.Create;
  Source := Fake;
  Fake.FView.Known := True;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeUnsavedFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    Assert.AreEqual(1, Integer(Length(Fake.Calls)), 'Shown beim Setzen der Quelle');
    Assert.AreEqual('shown', Fake.Calls[0]);
    Height := Frame.PreferredHeight;
    Fake.FView.Rows := [UnsavedRow('Eins', TAtlasUnsavedKind.Changes, 4, 0),
      UnsavedRow('Zwei', TAtlasUnsavedKind.Commits, 3, 0)];
    Frame.UpdateContent;
    Assert.IsTrue(Frame.PreferredHeight > Height, 'zwei Zeilen brauchen mehr Platz als der leere Bereich');
    Fake.Calls := nil;
    // Klick auf die Zeile außerhalb der Schaltfläche: nichts.
    Hit.Row := 0;
    Hit.Button := False;
    Frame.ClickAt(Hit);
    Hit.Row := 0;
    Hit.Button := True;
    Frame.ClickAt(Hit);
    Hit.Row := 1;
    Hit.Button := True;
    Frame.ClickAt(Hit);
    Hit.Row := 5;
    Frame.ClickAt(Hit);
    Frame.MenuRow := 1;
    Frame.OpenFolderItem.Click;
    Frame.IgnoreItem.Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(4, Integer(Length(Fake.Calls)));
    Assert.AreEqual('show Eins changes', Fake.Calls[0]);
    Assert.AreEqual('push Zwei commits', Fake.Calls[1], '„Push …“ fragt in der Quelle erst nach');
    Assert.AreEqual('folder Zwei', Fake.Calls[2]);
    Assert.AreEqual('ignore Zwei commits', Fake.Calls[3]);
    Assert.AreEqual(-1, Frame.HitTest(20, 0).Row, 'über der ersten Zeile');
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeUnsavedFrameTests.PushDialogCancelsByDefault;
var
  Saved: TAtlasLanguage;
  Plan: TAtlasUnsavedPush;
  Commit: TAtlasVcsCommit;
  Dialog: TAtlasPushDialog;
  Text: string;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Plan := Default(TAtlasUnsavedPush);
    Plan.Branch := 'feature/x';
    Plan.Remote := 'origin';
    Plan.RemoteRef := 'refs/heads/feature/x';
    Plan.SetUpstream := True;
    Commit := Default(TAtlasVcsCommit);
    Commit.Hash := '0123456789abcdef';
    Commit.Date := EncodeDateTime(2026, 10, 14, 9, 0, 0, 0);
    Commit.Summary := 'Erster Schritt';
    Plan.Commits := [Commit];
    Plan.More := True;
    Text := TAtlasPushDialog.DetailText([Plan]);
    Assert.Contains(Text, 'feature/x → origin/feature/x (neu auf dem Server');
    Assert.Contains(Text, '0123456');
    Assert.Contains(Text, 'Erster Schritt');
    Assert.Contains(Text, '… und weitere');
    Dialog := TAtlasPushDialog.CreateDialog(nil, 'Atlas', [Plan]);
    try
      Assert.AreEqual('Push – Atlas', Dialog.Caption);
      Assert.AreEqual(Text, Dialog.Details.Text);
      // Enter und Esc pushen nie.
      Assert.IsTrue(Dialog.CancelButton.Default);
      Assert.IsTrue(Dialog.CancelButton.Cancel);
      Assert.IsFalse(Dialog.PushButton.Default);
      Assert.IsTrue(Dialog.ActiveControl = Dialog.CancelButton);
      Assert.AreEqual(Integer(mrOk), Integer(Dialog.PushButton.ModalResult));
      Assert.AreEqual(Integer(mrCancel), Integer(Dialog.CancelButton.ModalResult));
    finally
      Dialog.Free;
    end;
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeUnsavedFrameTests);

end.
