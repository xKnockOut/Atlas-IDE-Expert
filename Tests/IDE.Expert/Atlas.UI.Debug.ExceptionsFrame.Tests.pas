unit Atlas.UI.Debug.ExceptionsFrame.Tests;

// Exception-Verlauf (#517), Oberfläche: Spalten, Zeilen zuletzt gesehen
// zuerst, Anzahl mit „ignoriert“, Filter nach Text und Klasse, Hinweis ohne
// Einträge, Zusammenfassung, Enter springt nur mit Quelltext, Strg+C kopiert;
// Aufrufstapel mit zusammengefassten Bibliotheksrahmen (#578).

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugExceptionsFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    /// <summary>Einmal-Belegungen vorwegnehmen; sie gehören nicht in die Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CellsShowCountAndIgnored;
    [Test]
    procedure ShowsRowsNewestFirst;
    [Test]
    procedure FiltersByTextAndClass;
    [Test]
    procedure EmptyHistoryShowsHint;
    [Test]
    procedure EnterOpensOnlyWithSource;
    [Test]
    procedure StackGroupsLibraryFrames;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Vcl.Forms,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.IgnoreList,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.OwnCode,
  Atlas.UI.Debug.ExceptionsFrame;

function Sample(ATime: TDateTime; const AClass, AMessage, AFile: string; ALine: Integer): TAtlasDebugException;
begin
  Result := TAtlasDebugException.Create(ATime, AClass, AMessage, 77, '').At(AFile, ALine, 'Unit1.Laden');
end;

function SampleHistory: TAtlasDebugExceptionHistory;
begin
  Result := TAtlasDebugExceptionHistory.Create;
  Result.Add(Sample(EncodeTime(10, 0, 0, 0), 'EConvertError', 'kein Integer', 'C:\P\Kunde.pas', 10));
  Result.Add(Sample(EncodeTime(10, 5, 0, 0), 'EAbort', '', '', 0));
  Result.Add(Sample(EncodeTime(10, 9, 0, 0), 'EConvertError', 'kein Integer', 'C:\P\Kunde.pas', 10));
end;

{ TAtlasDebugExceptionsFrameTests }

procedure TAtlasDebugExceptionsFrameTests.WarmUpFirstUse;
begin
  Setup;
  try
    ShowsRowsNewestFirst;
  finally
    TearDown;
  end;
end;

procedure TAtlasDebugExceptionsFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasDebugExceptionsFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasDebugExceptionsFrameTests.CellsShowCountAndIgnored;
var
  mEntry: TAtlasDebugException;
  mTexts: TArray<string>;
begin
  mEntry := Sample(EncodeTime(14, 3, 7, 0), 'EConvertError', 'kein Integer', 'C:\P\Kunde.pas', 10);
  mEntry.Count := 4;
  mTexts := TAtlasDebugExceptionsFrame.Cells(mEntry, False);
  Assert.AreEqual(6, Integer(Length(mTexts)));
  Assert.AreEqual('14:03:07', mTexts[0]);
  Assert.AreEqual('EConvertError', mTexts[1]);
  Assert.AreEqual('kein Integer', mTexts[2]);
  Assert.AreEqual('4', mTexts[3]);
  Assert.AreEqual('Kunde.pas:10', mTexts[4]);
  Assert.AreEqual('Hauptthread 77', mTexts[5]);
  mTexts := TAtlasDebugExceptionsFrame.Cells(mEntry, True);
  Assert.AreEqual('4 · ignoriert', mTexts[3]);
end;

procedure TAtlasDebugExceptionsFrameTests.ShowsRowsNewestFirst;
var
  mHost: TForm;
  mFrame: TAtlasDebugExceptionsFrame;
  mHistory: TAtlasDebugExceptionHistory;
  mIgnore: TAtlasDebugIgnoreList;
begin
  mHistory := SampleHistory;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugExceptionsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mIgnore := TAtlasDebugIgnoreList.Empty;
    mIgnore.AddClass('EAbort');
    mFrame.SetHistory(mHistory, mIgnore);
    Assert.AreEqual(6, Integer(mFrame.List.Columns.Count));
    Assert.AreEqual('Klasse', mFrame.List.Columns[1].Caption);
    Assert.AreEqual(2, Integer(mFrame.List.Items.Count));
    Assert.AreEqual('10:09:00', mFrame.List.Items[0].Caption, 'zuletzt gesehen zuerst');
    Assert.AreEqual('2', mFrame.List.Items[0].SubItems[2]);
    Assert.AreEqual('1 · ignoriert', mFrame.List.Items[1].SubItems[2]);
    Assert.AreEqual('Unit1.Laden', mFrame.List.Items[1].SubItems[3], 'ohne Datei die Routine');
    Assert.AreEqual('2 Einträge, 3 Exceptions in dieser Sitzung', mFrame.SummaryLabel.Caption);
    Assert.AreEqual(3, Integer(mFrame.ClassBox.Items.Count), 'Alle Klassen und zwei Klassen');
    Assert.AreEqual('Alle Klassen', mFrame.ClassBox.Items[0]);
    Assert.IsFalse(mFrame.EmptyLabel.Visible);
  finally
    mHost.Free;
    mHistory.Free;
  end;
end;

procedure TAtlasDebugExceptionsFrameTests.FiltersByTextAndClass;
var
  mHost: TForm;
  mFrame: TAtlasDebugExceptionsFrame;
  mHistory: TAtlasDebugExceptionHistory;
begin
  mHistory := SampleHistory;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugExceptionsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.SetHistory(mHistory, TAtlasDebugIgnoreList.Empty);
    mFrame.Filter.Text := 'kunde integer';
    Assert.AreEqual(1, Integer(mFrame.List.Items.Count));
    Assert.AreEqual('EConvertError', mFrame.Shown[0].ExceptionClass);
    mFrame.Filter.Text := '';
    mFrame.ClassBox.ItemIndex := 1;
    mFrame.ClassBox.OnChange(mFrame.ClassBox);
    Assert.AreEqual(1, Integer(mFrame.List.Items.Count));
    Assert.AreEqual('EAbort', mFrame.Shown[0].ExceptionClass, 'Klassen sortiert: EAbort zuerst');
    // Neuer Verlauf: die gewählte Klasse bleibt.
    mFrame.SetHistory(mHistory, TAtlasDebugIgnoreList.Empty);
    Assert.AreEqual(1, mFrame.ClassBox.ItemIndex);
  finally
    mHost.Free;
    mHistory.Free;
  end;
end;

procedure TAtlasDebugExceptionsFrameTests.EmptyHistoryShowsHint;
var
  mHost: TForm;
  mFrame: TAtlasDebugExceptionsFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugExceptionsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.SetHistory(nil, TAtlasDebugIgnoreList.Empty);
    Assert.IsTrue(mFrame.EmptyLabel.Visible);
    Assert.IsFalse(mFrame.List.Visible);
    // Erst der Zustand, dann was das Fenster sammelt und wie man es bedient.
    Assert.IsTrue(string(mFrame.EmptyLabel.Caption).StartsWith('Noch keine Exception in dieser Debug-Sitzung.'),
      mFrame.EmptyLabel.Caption);
    Assert.IsTrue(Pos('Doppelklick', mFrame.EmptyLabel.Caption) > 0, mFrame.EmptyLabel.Caption);
    Assert.IsTrue(Pos('Kontextmenü', mFrame.EmptyLabel.Caption) > 0, mFrame.EmptyLabel.Caption);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasDebugExceptionsFrameTests.EnterOpensOnlyWithSource;
var
  mHost: TForm;
  mFrame: TAtlasDebugExceptionsFrame;
  mHistory: TAtlasDebugExceptionHistory;
  mOpened, mCopied: string;
  mKey: Word;
begin
  mHistory := SampleHistory;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugExceptionsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.SetHistory(mHistory, TAtlasDebugIgnoreList.Empty);
    mOpened := '';
    mCopied := '';
    mFrame.OnOpen :=
      procedure(AException: TAtlasDebugException)
      begin
        mOpened := AException.FileName;
      end;
    mFrame.OnCopy :=
      procedure(AException: TAtlasDebugException)
      begin
        mCopied := AException.ExceptionClass;
      end;
    mFrame.List.Items[1].Selected := True;
    mKey := VK_RETURN;
    mFrame.List.OnKeyDown(mFrame.List, mKey, []);
    Assert.AreEqual('', mOpened, 'ohne Quelltext kein Sprung');
    mKey := Ord('C');
    mFrame.List.OnKeyDown(mFrame.List, mKey, [ssCtrl]);
    Assert.AreEqual('EAbort', mCopied);
    mFrame.List.Items[0].Selected := True;
    mKey := VK_RETURN;
    mFrame.List.OnKeyDown(mFrame.List, mKey, []);
    Assert.AreEqual('C:\P\Kunde.pas', mOpened);
    Assert.AreEqual(0, Integer(mKey));
  finally
    mHost.Free;
    mHistory.Free;
  end;
end;

procedure TAtlasDebugExceptionsFrameTests.StackGroupsLibraryFrames;
var
  mHost: TForm;
  mFrame: TAtlasDebugExceptionsFrame;
  mHistory: TAtlasDebugExceptionHistory;
  mEntry: TAtlasDebugException;
  mOwn: TAtlasDebugFrame;
  mOpened: string;
begin
  mHistory := TAtlasDebugExceptionHistory.Create;
  mHost := TForm.CreateNew(nil);
  try
    mEntry := Sample(EncodeTime(10, 0, 0, 0), 'EConvertError', 'kein Integer', 'C:\P\Kunde.pas', 10);
    mOwn := TAtlasDebugFrame.Create('Kunde.TKunde.Laden', 'C:\P\Kunde.pas', 10);
    mOwn.Own := True;
    mEntry.Frames := TArray<TAtlasDebugFrame>.Create(
      TAtlasDebugFrame.Create(':7714C3E2 KERNELBASE.RaiseException', '', 0),
      TAtlasDebugFrame.Create('System.SysUtils.StrToInt', '', 0), mOwn);
    mHistory.Add(mEntry);
    mFrame := TAtlasDebugExceptionsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.Stack.JustMyCode := True;
    mFrame.SetHistory(mHistory, TAtlasDebugIgnoreList.Empty);
    mOpened := '';
    mFrame.Stack.OnOpenFrame :=
      procedure(AFrame: TAtlasDebugFrame)
      begin
        mOpened := AFrame.FileName + ':' + IntToStr(AFrame.Line);
      end;
    Assert.AreEqual(0, Integer(mFrame.Stack.List.Items.Count), 'ohne Auswahl kein Stapel');
    mFrame.List.Items[0].Selected := True;
    Assert.AreEqual(2, Integer(mFrame.Stack.List.Items.Count));
    Assert.AreEqual('… 2 Bibliotheksrahmen', mFrame.Stack.List.Items[0].Caption);
    Assert.AreEqual('Kunde.pas:10', mFrame.Stack.List.Items[1].SubItems[0]);
    mFrame.Stack.OpenRow(1);
    Assert.AreEqual('C:\P\Kunde.pas:10', mOpened);
    // Gruppe aufklappen: drei Zeilen, die ersten beiden abgeschwächt.
    mFrame.Stack.OpenRow(0);
    Assert.AreEqual(3, Integer(mFrame.Stack.List.Items.Count));
    Assert.IsTrue(mFrame.Stack.Rows[0].Faded);
    Assert.IsFalse(mFrame.Stack.Rows[2].Faded);
    mOpened := '';
    mFrame.Stack.OpenRow(0);
    Assert.AreEqual('', mOpened, 'Rahmen ohne Quelltext springt nicht');
    // Ohne „Nur eigener Code“ jeder Rahmen einzeln.
    mFrame.Stack.JustMyCode := False;
    Assert.AreEqual(3, Integer(mFrame.Stack.List.Items.Count));
    Assert.IsFalse(mFrame.Stack.Rows[0].Faded);
  finally
    mHost.Free;
    mHistory.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugExceptionsFrameTests);

end.
