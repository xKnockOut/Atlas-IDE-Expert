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
  System.Classes,
  Winapi.Windows,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.UI.Strings,
  System.DateUtils,
  Atlas.Core.VersionControl.Contract,
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
  mSaved: TAtlasLanguage;
  mNowUtc: TDateTime;
  mRow: TAtlasUnsavedRow;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mNowUtc := EncodeDateTime(2026, 10, 15, 12, 0, 0, 0);
    // Abnahme: SVN-Projekt mit 2 geänderten Dateien.
    mRow := UnsavedRow('Svn', TAtlasUnsavedKind.Changes, 2, IncHour(mNowUtc, -3));
    mRow.Item.Modified := 2;
    Assert.AreEqual('2 Dateien geändert', TAtlasUnsavedTexts.WhatText(mRow.Item));
    Assert.AreEqual('2 Dateien geändert · seit 3 Std.', TAtlasUnsavedTexts.DetailText(mRow, mNowUtc));
    Assert.AreEqual('Ansehen', TAtlasUnsavedTexts.ButtonText(mRow.Item));
    Assert.AreEqual('Svn · main', TAtlasUnsavedTexts.TitleText(mRow));
    // #1292: Anteile je Arbeitskopie hinter der Summe.
    mRow.Item.Places := [TAtlasUnsavedPlace.Create('', 1), TAtlasUnsavedPlace.Create('Packages/Drucken', 1)];
    Assert.AreEqual('2 Dateien geändert (Svn 1 · Packages\Drucken 1) · seit 3 Std.',
      TAtlasUnsavedTexts.DetailText(mRow, mNowUtc));
    mRow.Item.Places := nil;
    mRow.Item.Count := 1;
    mRow.Item.Modified := 1;
    Assert.AreEqual('1 Datei geändert', TAtlasUnsavedTexts.WhatText(mRow.Item));
    // Gemischt: geändert, neu, gelöscht.
    mRow.Item.Count := 4;
    mRow.Item.Modified := 2;
    mRow.Item.Added := 1;
    mRow.Item.Deleted := 1;
    Assert.AreEqual('4 Dateien: 2 geändert, 1 neu, 1 gelöscht', TAtlasUnsavedTexts.WhatText(mRow.Item));
    mRow := UnsavedRow('Git', TAtlasUnsavedKind.Commits, 3, IncDay(mNowUtc, -2));
    mRow.Item.Branches := ['main'];
    Assert.AreEqual('3 Commits nicht gepusht (main) · seit 2 Tagen',
      TAtlasUnsavedTexts.DetailText(mRow, mNowUtc));
    Assert.AreEqual('Push …', TAtlasUnsavedTexts.ButtonText(mRow.Item));
    mRow := UnsavedRow('Git', TAtlasUnsavedKind.NoUpstream, 1, 0);
    mRow.Item.Branches := ['feature/x'];
    mRow.Item.Commits := 2;
    Assert.AreEqual('Branch feature/x ohne Upstream, 2 Commits nur lokal',
      TAtlasUnsavedTexts.DetailText(mRow, mNowUtc), 'ohne Alter keine Zeitangabe');
    Assert.AreEqual('Push …', TAtlasUnsavedTexts.ButtonText(mRow.Item));
    mRow := UnsavedRow('Git', TAtlasUnsavedKind.Conflicts, 2, 0);
    Assert.AreEqual('2 Dateien im Konflikt', TAtlasUnsavedTexts.WhatText(mRow.Item));
    Assert.AreEqual('Ansehen', TAtlasUnsavedTexts.ButtonText(mRow.Item));
    mRow := UnsavedRow('Git', TAtlasUnsavedKind.Stashes, 1, IncMinute(mNowUtc, -20));
    mRow.Item.Name := 'Versuch';
    Assert.StartsWith('Stash „Versuch“ vom ', TAtlasUnsavedTexts.WhatText(mRow.Item));
    Assert.EndsWith(' · seit 20 Min.', TAtlasUnsavedTexts.DetailText(mRow, mNowUtc));
    Assert.AreEqual('Ansehen', TAtlasUnsavedTexts.ButtonText(mRow.Item));
    Assert.AreEqual('seit 1 Tag', TAtlasUnsavedTexts.AgeText(IncHour(mNowUtc, -30), mNowUtc));
    Assert.AreEqual('', TAtlasUnsavedTexts.AgeText(0, mNowUtc));
    Assert.IsTrue(TAtlasUnsavedTexts.LevelColor(TAtlasUnsavedLevel.Fresh) <>
      TAtlasUnsavedTexts.LevelColor(TAtlasUnsavedLevel.Alert), 'rot ist nicht grün');
    Assert.IsTrue(TAtlasUnsavedTexts.LevelColor(TAtlasUnsavedLevel.Warning) <>
      TAtlasUnsavedTexts.LevelColor(TAtlasUnsavedLevel.Alert), 'gelb ist nicht rot');
    Assert.Contains(TAtlasUnsavedTexts.HintFor(mRow), 'C:\P\Git.dproj');
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('View', TAtlasUnsavedTexts.ButtonText(mRow.Item));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeUnsavedFrameTests.EmptyTextNamesState;
var
  mSaved: TAtlasLanguage;
  mView: TAtlasUnsavedView;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mView := Default(TAtlasUnsavedView);
    mView.Known := True;
    Assert.AreEqual('Alles gesichert', TAtlasUnsavedTexts.EmptyText(mView));
    mView.Known := False;
    mView.Querying := True;
    Assert.AreEqual('Versionsverwaltung wird abgefragt …', TAtlasUnsavedTexts.EmptyText(mView));
    mView.Hidden := 2;
    Assert.StartsWith('Nichts zu zeigen (2 ', TAtlasUnsavedTexts.EmptyText(mView));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeUnsavedFrameTests.OnlyButtonAndMenuReachSource;
var
  mHost: TForm;
  mFake: TFakeUnsaved;
  mSource: IAtlasUnsavedSource;
  mFrame: TAtlasWelcomeUnsavedFrame;
  mHit: TAtlasUnsavedHit;
  mHeight: Integer;
begin
  mFake := TFakeUnsaved.Create;
  mSource := mFake;
  mFake.FView.Known := True;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeUnsavedFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)), 'Shown beim Setzen der Quelle');
    Assert.AreEqual('shown', mFake.Calls[0]);
    mHeight := mFrame.PreferredHeight;
    mFake.FView.Rows := [UnsavedRow('Eins', TAtlasUnsavedKind.Changes, 4, 0),
      UnsavedRow('Zwei', TAtlasUnsavedKind.Commits, 3, 0)];
    mFrame.UpdateContent;
    Assert.IsTrue(mFrame.PreferredHeight > mHeight, 'zwei Zeilen brauchen mehr Platz als der leere Bereich');
    mFake.Calls := nil;
    // Klick auf die Zeile außerhalb der Schaltfläche: nichts.
    mHit.Row := 0;
    mHit.Button := False;
    mFrame.ClickAt(mHit);
    mHit.Row := 0;
    mHit.Button := True;
    mFrame.ClickAt(mHit);
    mHit.Row := 1;
    mHit.Button := True;
    mFrame.ClickAt(mHit);
    mHit.Row := 5;
    mFrame.ClickAt(mHit);
    mFrame.MenuRow := 1;
    mFrame.OpenFolderItem.Click;
    mFrame.IgnoreItem.Click;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(4, Integer(Length(mFake.Calls)));
    Assert.AreEqual('show Eins changes', mFake.Calls[0]);
    Assert.AreEqual('push Zwei commits', mFake.Calls[1], '„Push …“ fragt in der Quelle erst nach');
    Assert.AreEqual('folder Zwei', mFake.Calls[2]);
    Assert.AreEqual('ignore Zwei commits', mFake.Calls[3]);
    Assert.AreEqual(-1, mFrame.HitTest(20, 0).Row, 'über der ersten Zeile');
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeUnsavedFrameTests.PushDialogCancelsByDefault;
var
  mSaved: TAtlasLanguage;
  mPlan: TAtlasUnsavedPush;
  mCommit: TAtlasVcsCommit;
  mDialog: TAtlasPushDialog;
  mText: string;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mPlan := Default(TAtlasUnsavedPush);
    mPlan.Branch := 'feature/x';
    mPlan.Remote := 'origin';
    mPlan.RemoteRef := 'refs/heads/feature/x';
    mPlan.SetUpstream := True;
    mCommit := Default(TAtlasVcsCommit);
    mCommit.Hash := '0123456789abcdef';
    mCommit.Date := EncodeDateTime(2026, 10, 14, 9, 0, 0, 0);
    mCommit.Summary := 'Erster Schritt';
    mPlan.Commits := [mCommit];
    mPlan.More := True;
    mText := TAtlasPushDialog.DetailText([mPlan]);
    Assert.Contains(mText, 'feature/x → origin/feature/x (neu auf dem Server');
    Assert.Contains(mText, '0123456');
    Assert.Contains(mText, 'Erster Schritt');
    Assert.Contains(mText, '… und weitere');
    mDialog := TAtlasPushDialog.CreateDialog(nil, 'Atlas', [mPlan]);
    try
      Assert.AreEqual('Push – Atlas', mDialog.Caption);
      Assert.AreEqual(mText, mDialog.Details.Text);
      // Enter und Esc pushen nie.
      Assert.IsTrue(mDialog.CancelButton.Default);
      Assert.IsTrue(mDialog.CancelButton.Cancel);
      Assert.IsFalse(mDialog.PushButton.Default);
      Assert.IsTrue(mDialog.ActiveControl = mDialog.CancelButton);
      Assert.AreEqual(Integer(mrOk), Integer(mDialog.PushButton.ModalResult));
      Assert.AreEqual(Integer(mrCancel), Integer(mDialog.CancelButton.ModalResult));
    finally
      mDialog.Free;
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeUnsavedFrameTests);

end.
