unit Atlas.UI.Search.ReplaceFrame.Tests;

// Fenster „Atlas-Suche: Ersetzen“ (#893): Zeilen je Datei und Treffer,
// Häkchen einer Datei gilt für alle ihre Treffer, Kopfzeile mit Anzahl,
// „Ausgewählte ersetzen“ nur mit angehakten Treffern, Sprung per Enter,
// Knopf in einer eigenen Zeile mit voller Höhe.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Search')]
  TAtlasSearchReplaceFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RowsFollowTheModelAndToggleTogether;
    [Test]
    procedure ReplaceAndOpenAreReported;
    [Test]
    procedure ReplaceButtonHasItsOwnRow;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.Files,
  Atlas.Core.Search.ReplaceList,
  Atlas.UI.Search.ReplaceFrame;

function SampleList: TAtlasReplaceList;
var
  mQuery: TAtlasSearchQuery;
begin
  mQuery := Default(TAtlasSearchQuery);
  mQuery.Text := 'foo';
  mQuery.Options := TAtlasSearchOptions.Create(False, False, False);
  Result := TAtlasReplaceList.Create(mQuery, 'bar');
  Result.Add(TAtlasFileSearch.SearchText('C:\P\A.pas', 'foo' + #13#10 + 'x foo', mQuery));
  Result.Add(TAtlasFileSearch.SearchText('C:\P\B.pas', 'foo', mQuery));
end;

procedure TAtlasSearchReplaceFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasSearchReplaceFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasSearchReplaceFrameTests.RowsFollowTheModelAndToggleTogether;
var
  mHost: TForm;
  mFrame: TAtlasSearchReplaceFrame;
  mList: TAtlasReplaceList;
begin
  mHost := TForm.CreateNew(nil);
  mList := SampleList;
  try
    mFrame := TAtlasSearchReplaceFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.SetModel(nil);
    Assert.IsFalse(mFrame.ReplaceButton.Enabled);
    mFrame.SetModel(mList);
    // A mit zwei Treffern, B mit einem: je Datei eine Kopfzeile.
    Assert.AreEqual(5, Integer(Length(mFrame.Rows)));
    Assert.AreEqual(5, mFrame.List.Items.Count);
    Assert.AreEqual('„foo“ → „bar“: 3 von 3 Treffern in 2 Dateien ausgewählt', mFrame.Title.Caption);
    Assert.IsTrue(mFrame.ReplaceButton.Enabled);
    // Datei A abhaken: beide Treffer folgen.
    mFrame.ToggleRow(0);
    Assert.IsFalse(mList.HitChecked(0, 0));
    Assert.IsFalse(mList.HitChecked(0, 1));
    Assert.IsFalse(mFrame.Rows[1].Checked);
    Assert.AreEqual(1, mList.CheckedCount);
    // Einen Treffer wieder anhaken: Die Datei ist nicht ganz angehakt.
    mFrame.ToggleRow(2);
    Assert.IsTrue(mList.HitChecked(0, 1));
    Assert.IsFalse(mFrame.Rows[0].Checked);
    // Alles ab: nichts zu ersetzen.
    mFrame.ToggleRow(2);
    mFrame.ToggleRow(3);
    Assert.AreEqual(0, mList.CheckedCount);
    Assert.IsFalse(mFrame.ReplaceButton.Enabled);
    mFrame.SetNotice('2 Ersetzungen in 1 Datei');
    Assert.AreEqual('2 Ersetzungen in 1 Datei', mFrame.Notice.Caption);
  finally
    mHost.Free;
    mList.Free;
  end;
end;

procedure TAtlasSearchReplaceFrameTests.ReplaceAndOpenAreReported;
var
  mHost: TForm;
  mFrame: TAtlasSearchReplaceFrame;
  mList: TAtlasReplaceList;
  mLog: string;
  mKey: Word;
begin
  mHost := TForm.CreateNew(nil);
  mList := SampleList;
  try
    mFrame := TAtlasSearchReplaceFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.SetModel(mList);
    mLog := '';
    mFrame.OnReplace :=
      procedure
      begin
        mLog := mLog + 'ersetzen;';
      end;
    mFrame.OnOpen :=
      procedure(const AFileName: string; ALine, ACharacter: Integer)
      begin
        mLog := mLog + Format('%s:%d:%d;', [ExtractFileName(AFileName), ALine, ACharacter]);
      end;
    mFrame.ReplaceButton.Click;
    mFrame.List.HandleNeeded;
    mFrame.List.Items[2].Selected := True;
    mKey := VK_RETURN;
    mFrame.List.OnKeyDown(mFrame.List, mKey, []);
    Assert.AreEqual('ersetzen;A.pas:1:2;', mLog);
  finally
    mHost.Free;
    mList.Free;
    mLog := '';
  end;
end;

procedure TAtlasSearchReplaceFrameTests.ReplaceButtonHasItsOwnRow;
var
  mHost: TForm;
  mFrame: TAtlasSearchReplaceFrame;
  mRow: TWinControl;
  mIndex: Integer;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasSearchReplaceFrame.Create(mHost);
    mFrame.Parent := mHost;
    mRow := mFrame.ReplaceButton.Parent;
    // Die VCL richtet alTop vor alRight aus: Neben einem alTop-Geschwister
    // bliebe dem Knopf nur der Rest der Zeilenhöhe (Knopf unsichtbar).
    for mIndex := 0 to mRow.ControlCount - 1 do
    begin
      Assert.IsFalse(mRow.Controls[mIndex].Align = alTop, mRow.Controls[mIndex].ClassName + ' mit alTop neben dem Knopf');
    end;
    Assert.IsTrue(mRow.Height >= mFrame.ReplaceButton.Height + mFrame.ReplaceButton.Margins.Top +
      mFrame.ReplaceButton.Margins.Bottom, 'Zeile so hoch wie der Knopf');
    Assert.IsTrue(mFrame.Notice.Parent = mRow, 'Hinweis neben dem Knopf');
    Assert.IsFalse(mFrame.Title.Parent = mRow, 'Kopfzeile darüber');
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSearchReplaceFrameTests);

end.
