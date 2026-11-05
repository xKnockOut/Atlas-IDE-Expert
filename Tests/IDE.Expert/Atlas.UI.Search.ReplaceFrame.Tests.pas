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
  Query: TAtlasSearchQuery;
begin
  Query := Default(TAtlasSearchQuery);
  Query.Text := 'foo';
  Query.Options := TAtlasSearchOptions.Create(False, False, False);
  Result := TAtlasReplaceList.Create(Query, 'bar');
  Result.Add(TAtlasFileSearch.SearchText('C:\P\A.pas', 'foo' + #13#10 + 'x foo', Query));
  Result.Add(TAtlasFileSearch.SearchText('C:\P\B.pas', 'foo', Query));
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
  Host: TForm;
  Frame: TAtlasSearchReplaceFrame;
  List: TAtlasReplaceList;
begin
  Host := TForm.CreateNew(nil);
  List := SampleList;
  try
    Frame := TAtlasSearchReplaceFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetModel(nil);
    Assert.IsFalse(Frame.ReplaceButton.Enabled);
    Frame.SetModel(List);
    // A mit zwei Treffern, B mit einem: je Datei eine Kopfzeile.
    Assert.AreEqual(5, Integer(Length(Frame.Rows)));
    Assert.AreEqual(5, Frame.List.Items.Count);
    Assert.AreEqual('„foo“ → „bar“: 3 von 3 Treffern in 2 Dateien ausgewählt', Frame.Title.Caption);
    Assert.IsTrue(Frame.ReplaceButton.Enabled);
    // Datei A abhaken: beide Treffer folgen.
    Frame.ToggleRow(0);
    Assert.IsFalse(List.HitChecked(0, 0));
    Assert.IsFalse(List.HitChecked(0, 1));
    Assert.IsFalse(Frame.Rows[1].Checked);
    Assert.AreEqual(1, List.CheckedCount);
    // Einen Treffer wieder anhaken: Die Datei ist nicht ganz angehakt.
    Frame.ToggleRow(2);
    Assert.IsTrue(List.HitChecked(0, 1));
    Assert.IsFalse(Frame.Rows[0].Checked);
    // Alles ab: nichts zu ersetzen.
    Frame.ToggleRow(2);
    Frame.ToggleRow(3);
    Assert.AreEqual(0, List.CheckedCount);
    Assert.IsFalse(Frame.ReplaceButton.Enabled);
    Frame.SetNotice('2 Ersetzungen in 1 Datei');
    Assert.AreEqual('2 Ersetzungen in 1 Datei', Frame.Notice.Caption);
  finally
    Host.Free;
    List.Free;
  end;
end;

procedure TAtlasSearchReplaceFrameTests.ReplaceAndOpenAreReported;
var
  Host: TForm;
  Frame: TAtlasSearchReplaceFrame;
  List: TAtlasReplaceList;
  Log: string;
  Key: Word;
begin
  Host := TForm.CreateNew(nil);
  List := SampleList;
  try
    Frame := TAtlasSearchReplaceFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetModel(List);
    Log := '';
    Frame.OnReplace :=
      procedure
      begin
        Log := Log + 'ersetzen;';
      end;
    Frame.OnOpen :=
      procedure(const AFileName: string; ALine, ACharacter: Integer)
      begin
        Log := Log + Format('%s:%d:%d;', [ExtractFileName(AFileName), ALine, ACharacter]);
      end;
    Frame.ReplaceButton.Click;
    Frame.List.HandleNeeded;
    Frame.List.Items[2].Selected := True;
    Key := VK_RETURN;
    Frame.List.OnKeyDown(Frame.List, Key, []);
    Assert.AreEqual('ersetzen;A.pas:1:2;', Log);
  finally
    Host.Free;
    List.Free;
    Log := '';
  end;
end;

procedure TAtlasSearchReplaceFrameTests.ReplaceButtonHasItsOwnRow;
var
  Host: TForm;
  Frame: TAtlasSearchReplaceFrame;
  Row: TWinControl;
  Index: Integer;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasSearchReplaceFrame.Create(Host);
    Frame.Parent := Host;
    Row := Frame.ReplaceButton.Parent;
    // Die VCL richtet alTop vor alRight aus: Neben einem alTop-Geschwister
    // bliebe dem Knopf nur der Rest der Zeilenhöhe (Knopf unsichtbar).
    for Index := 0 to Row.ControlCount - 1 do
    begin
      Assert.IsFalse(Row.Controls[Index].Align = alTop, Row.Controls[Index].ClassName + ' mit alTop neben dem Knopf');
    end;
    Assert.IsTrue(Row.Height >= Frame.ReplaceButton.Height + Frame.ReplaceButton.Margins.Top +
      Frame.ReplaceButton.Margins.Bottom, 'Zeile so hoch wie der Knopf');
    Assert.IsTrue(Frame.Notice.Parent = Row, 'Hinweis neben dem Knopf');
    Assert.IsFalse(Frame.Title.Parent = Row, 'Kopfzeile darüber');
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSearchReplaceFrameTests);

end.
