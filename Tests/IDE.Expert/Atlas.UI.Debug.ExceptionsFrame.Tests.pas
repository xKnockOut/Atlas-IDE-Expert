unit Atlas.UI.Debug.ExceptionsFrame.Tests;

// Exception-Verlauf (#517), Oberfläche: Spalten, Zeilen zuletzt gesehen
// zuerst, Anzahl mit „ignoriert“, Filter nach Text und Klasse, Hinweis ohne
// Einträge, Zusammenfassung, Enter springt nur mit Quelltext, Strg+C kopiert.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasDebugExceptionsFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Vcl.Forms,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.IgnoreList,
  Atlas.UI.Debug.ExceptionsFrame;

function Sample(ATime: TDateTime; const AClass, AMessage, AFile: string; ALine: Integer): TAtlasDebugException;
begin
  Result := TAtlasDebugException.Create(ATime, AClass, AMessage, 77, '', AFile, ALine, 'Unit1.Laden');
end;

function SampleHistory: TAtlasDebugExceptionHistory;
begin
  Result := TAtlasDebugExceptionHistory.Create;
  Result.Add(Sample(EncodeTime(10, 0, 0, 0), 'EConvertError', 'kein Integer', 'C:\P\Kunde.pas', 10));
  Result.Add(Sample(EncodeTime(10, 5, 0, 0), 'EAbort', '', '', 0));
  Result.Add(Sample(EncodeTime(10, 9, 0, 0), 'EConvertError', 'kein Integer', 'C:\P\Kunde.pas', 10));
end;

{ TAtlasDebugExceptionsFrameTests }

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
  Entry: TAtlasDebugException;
  Texts: TArray<string>;
begin
  Entry := Sample(EncodeTime(14, 3, 7, 0), 'EConvertError', 'kein Integer', 'C:\P\Kunde.pas', 10);
  Entry.Count := 4;
  Texts := TAtlasDebugExceptionsFrame.Cells(Entry, False);
  Assert.AreEqual(6, Integer(Length(Texts)));
  Assert.AreEqual('14:03:07', Texts[0]);
  Assert.AreEqual('EConvertError', Texts[1]);
  Assert.AreEqual('kein Integer', Texts[2]);
  Assert.AreEqual('4', Texts[3]);
  Assert.AreEqual('Kunde.pas:10', Texts[4]);
  Assert.AreEqual('Hauptthread 77', Texts[5]);
  Texts := TAtlasDebugExceptionsFrame.Cells(Entry, True);
  Assert.AreEqual('4 · ignoriert', Texts[3]);
end;

procedure TAtlasDebugExceptionsFrameTests.ShowsRowsNewestFirst;
var
  Host: TForm;
  Frame: TAtlasDebugExceptionsFrame;
  History: TAtlasDebugExceptionHistory;
  Ignore: TAtlasDebugIgnoreList;
begin
  History := SampleHistory;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasDebugExceptionsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.HandleNeeded;
    Ignore := TAtlasDebugIgnoreList.Empty;
    Ignore.AddClass('EAbort');
    Frame.SetHistory(History, Ignore);
    Assert.AreEqual(6, Integer(Frame.List.Columns.Count));
    Assert.AreEqual('Klasse', Frame.List.Columns[1].Caption);
    Assert.AreEqual(2, Integer(Frame.List.Items.Count));
    Assert.AreEqual('10:09:00', Frame.List.Items[0].Caption, 'zuletzt gesehen zuerst');
    Assert.AreEqual('2', Frame.List.Items[0].SubItems[2]);
    Assert.AreEqual('1 · ignoriert', Frame.List.Items[1].SubItems[2]);
    Assert.AreEqual('Unit1.Laden', Frame.List.Items[1].SubItems[3], 'ohne Datei die Routine');
    Assert.AreEqual('2 Einträge, 3 Exceptions in dieser Sitzung', Frame.SummaryLabel.Caption);
    Assert.AreEqual(3, Integer(Frame.ClassBox.Items.Count), 'Alle Klassen und zwei Klassen');
    Assert.AreEqual('Alle Klassen', Frame.ClassBox.Items[0]);
    Assert.IsFalse(Frame.EmptyLabel.Visible);
  finally
    Host.Free;
    History.Free;
  end;
end;

procedure TAtlasDebugExceptionsFrameTests.FiltersByTextAndClass;
var
  Host: TForm;
  Frame: TAtlasDebugExceptionsFrame;
  History: TAtlasDebugExceptionHistory;
begin
  History := SampleHistory;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasDebugExceptionsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.HandleNeeded;
    Frame.SetHistory(History, TAtlasDebugIgnoreList.Empty);
    Frame.Filter.Text := 'kunde integer';
    Assert.AreEqual(1, Integer(Frame.List.Items.Count));
    Assert.AreEqual('EConvertError', Frame.Shown[0].ExceptionClass);
    Frame.Filter.Text := '';
    Frame.ClassBox.ItemIndex := 1;
    Frame.ClassBox.OnChange(Frame.ClassBox);
    Assert.AreEqual(1, Integer(Frame.List.Items.Count));
    Assert.AreEqual('EAbort', Frame.Shown[0].ExceptionClass, 'Klassen sortiert: EAbort zuerst');
    // Neuer Verlauf: die gewählte Klasse bleibt.
    Frame.SetHistory(History, TAtlasDebugIgnoreList.Empty);
    Assert.AreEqual(1, Frame.ClassBox.ItemIndex);
  finally
    Host.Free;
    History.Free;
  end;
end;

procedure TAtlasDebugExceptionsFrameTests.EmptyHistoryShowsHint;
var
  Host: TForm;
  Frame: TAtlasDebugExceptionsFrame;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasDebugExceptionsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.HandleNeeded;
    Frame.SetHistory(nil, TAtlasDebugIgnoreList.Empty);
    Assert.IsTrue(Frame.EmptyLabel.Visible);
    Assert.IsFalse(Frame.List.Visible);
    Assert.AreEqual('Noch keine Exception in dieser Debug-Sitzung.', Frame.EmptyLabel.Caption);
  finally
    Host.Free;
  end;
end;

procedure TAtlasDebugExceptionsFrameTests.EnterOpensOnlyWithSource;
var
  Host: TForm;
  Frame: TAtlasDebugExceptionsFrame;
  History: TAtlasDebugExceptionHistory;
  Opened, Copied: string;
  Key: Word;
begin
  History := SampleHistory;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasDebugExceptionsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.HandleNeeded;
    Frame.SetHistory(History, TAtlasDebugIgnoreList.Empty);
    Opened := '';
    Copied := '';
    Frame.OnOpen :=
      procedure(AException: TAtlasDebugException)
      begin
        Opened := AException.FileName;
      end;
    Frame.OnCopy :=
      procedure(AException: TAtlasDebugException)
      begin
        Copied := AException.ExceptionClass;
      end;
    Frame.List.Items[1].Selected := True;
    Key := VK_RETURN;
    Frame.List.OnKeyDown(Frame.List, Key, []);
    Assert.AreEqual('', Opened, 'ohne Quelltext kein Sprung');
    Key := Ord('C');
    Frame.List.OnKeyDown(Frame.List, Key, [ssCtrl]);
    Assert.AreEqual('EAbort', Copied);
    Frame.List.Items[0].Selected := True;
    Key := VK_RETURN;
    Frame.List.OnKeyDown(Frame.List, Key, []);
    Assert.AreEqual('C:\P\Kunde.pas', Opened);
    Assert.AreEqual(0, Integer(Key));
  finally
    Host.Free;
    History.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugExceptionsFrameTests);

end.
