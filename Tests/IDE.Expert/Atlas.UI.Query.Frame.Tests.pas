unit Atlas.UI.Query.Frame.Tests;

// Fenster „Atlas-Abfrage“ (#1351), Fensterinhalt: Zeilen und Statuszeile aus
// der Antwort des Servers, Sortieren per Spaltenklick (Gleichstand eindeutig,
// ohne Wert zuletzt), Sprung zur Deklaration, Ausführen und Abbrechen,
// Fehler mit Spalte und Vorschlag, Vervollständigung aus Katalog und
// Symbolsuche, gespeicherte Abfragen, CSV.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Query.Frame;

type
  [TestFixture]
  [Category('Atlas.IDE.Search')]
  TAtlasCodeQueryFrameTests = class
  private
    FForm: TForm;
    FFrame: TAtlasCodeQueryFrame;
    FOpened: string;
    FLine: Integer;
    FRan: string;
    FCancelled: Boolean;
  public
    /// <summary>Einmalige VCL-Puffer (Liste, Klappliste) vor dem Leckmonitor anlegen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ShowsRowsAndStatus;
    [Test]
    procedure SortsByColumnClick;
    [Test]
    procedure OpensRowAndRuns;
    [Test]
    procedure ErrorShowsColumnAndSuggestion;
    [Test]
    procedure CompletesFromCatalogAndSymbols;
    [Test]
    procedure SavedQueryRuns;
    [Test]
    procedure CsvAndMessage;
    /// <summary>Ohne Ergebnis steht die Hilfe mit den Mengen des Katalogs an der Stelle der Liste; der Knopf
    /// blendet sie ein und aus.</summary>
    [Test]
    procedure HelpWithoutAnswerAndOnButton;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Atlas.UI.Search.Strings,
  Atlas.Core.Query.Model,
  Atlas.Core.Query.Model.Tests;

function Joined(const ALines: TArray<string>): string;
begin
  Result := string.Join(#10, ALines);
end;

function FirstCells(const ALines: TArray<string>): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in ALines do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mLine.Split([' | '])[0];
  end;
end;

procedure TAtlasCodeQueryFrameTests.WarmUpFirstUse;
begin
  SetUp;
  try
    ShowsRowsAndStatus;
  finally
    TearDown;
  end;
end;

procedure TAtlasCodeQueryFrameTests.SetUp;
var
  mAnswer: TAtlasQueryAnswer;
  mCatalog: TAtlasQueryCatalog;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 900;
  FForm.Height := 600;
  FFrame := TAtlasCodeQueryFrame.Create(FForm);
  FFrame.Parent := FForm;
  FFrame.Align := alClient;
  FFrame.Events.OnOpenLocation :=
    procedure(AFileName: string; ALine, ACharacter: Integer)
    begin
      FOpened := AFileName;
      FLine := ALine;
    end;
  FFrame.Events.OnRun :=
    procedure(AQuery: string)
    begin
      FRan := AQuery;
    end;
  FFrame.Events.OnCancel :=
    procedure
    begin
      FCancelled := True;
    end;
  TAtlasQueryCatalog.Parse(QuerySampleCatalog, mCatalog);
  FFrame.SetCatalog(mCatalog);
  TAtlasQueryAnswer.Parse(QuerySampleAnswer, mAnswer);
  FFrame.SetAnswer(mAnswer);
end;

procedure TAtlasCodeQueryFrameTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FFrame := nil;
  FOpened := '';
  FRan := '';
  FCancelled := False;
end;

procedure TAtlasCodeQueryFrameTests.HelpWithoutAnswerAndOnButton;
var
  mCatalog: TAtlasQueryCatalog;
begin
  // SetUp hat ein Ergebnis gesetzt: Liste statt Hilfe.
  Assert.IsFalse(FFrame.HelpMemo.Visible);
  Assert.IsTrue(FFrame.ResultList.Visible);
  // Ohne Ergebnis: Hilfe mit Aufbau und den Mengen des Katalogs.
  FFrame.SetMessage('', False);
  Assert.IsTrue(FFrame.HelpMemo.Visible);
  Assert.IsFalse(FFrame.ResultList.Visible);
  Assert.IsTrue(string(FFrame.HelpMemo.Text).Contains('order by'));
  TAtlasQueryCatalog.Parse(QuerySampleCatalog, mCatalog);
  Assert.IsTrue(string(FFrame.HelpMemo.Text).Contains(mCatalog.Entities[0].Name), 'Mengen aus dem Katalog');
  // Knopf schaltet um, auch neben einem Ergebnis.
  FFrame.Toolbar.HelpButton.Click;
  Assert.IsFalse(FFrame.HelpMemo.Visible);
  FFrame.Toolbar.HelpButton.Click;
  Assert.IsTrue(FFrame.HelpMemo.Visible);
end;

procedure TAtlasCodeQueryFrameTests.ShowsRowsAndStatus;
var
  mRows: TArray<string>;
begin
  mRows := FFrame.ResultList.RowText;
  Assert.AreEqual(3, Integer(Length(mRows)));
  Assert.AreEqual('TB | U | 9 | 2 | U.pas:9', mRows[0]);
  Assert.AreEqual('TA | U | 4 | 10 | U.pas:4 · ' + TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryInferred),
    mRows[1]);
  // Spalten je Feld und „Datei“.
  Assert.AreEqual(5, FFrame.ResultList.Columns.Count);
  Assert.AreEqual(3, FFrame.ResultList.Items.Count);
  Assert.AreEqual(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.QueryStatusTruncated, [3, 3, 12]) +
    TAtlasSearchStrings.Fmt(TAtlasSearchTextId.QueryStatusInferred, [1]), FFrame.StatusLabel.Caption);
  Assert.IsTrue(FFrame.Toolbar.CopyCsvButton.Enabled);
  Assert.IsFalse(FFrame.InputBar.ErrorLabel.Visible);
end;

procedure TAtlasCodeQueryFrameTests.SortsByColumnClick;
begin
  // methods: Zahl, zuerst absteigend; ohne Wert zuletzt.
  FFrame.ResultList.SortBy(3);
  Assert.AreEqual('TA,TB,TC;x', FirstCells(FFrame.ResultList.RowText));
  Assert.IsTrue(FFrame.ResultList.SortDescending);
  FFrame.ResultList.SortBy(3);
  Assert.AreEqual('TB,TA,TC;x', FirstCells(FFrame.ResultList.RowText));
  // unit: Gleichstand bei TA und TB, weiter nach Pfad und Zeile.
  FFrame.ResultList.SortBy(1);
  Assert.IsFalse(FFrame.ResultList.SortDescending);
  Assert.AreEqual('TA,TB,TC;x', FirstCells(FFrame.ResultList.RowText));
  // „Datei“ sortiert nach Pfad, Zeile und Spalte.
  FFrame.ResultList.SortBy(4);
  Assert.AreEqual(-1, FFrame.ResultList.SortColumn);
  Assert.AreEqual('TA,TB,TC;x', FirstCells(FFrame.ResultList.RowText));
end;

procedure TAtlasCodeQueryFrameTests.OpensRowAndRuns;
begin
  FFrame.ResultList.OpenRow(0);
  Assert.AreEqual('C:\P\U.pas', FOpened);
  Assert.AreEqual(9, FLine);
  FFrame.InputBar.Edit.Text := '  classes where methods > 3  ';
  FFrame.Run;
  Assert.AreEqual('classes where methods > 3', FRan);
  FFrame.SetRunning(True);
  Assert.IsFalse(FFrame.Toolbar.RunButton.Enabled);
  Assert.IsTrue(FFrame.Toolbar.CancelButton.Enabled);
  Assert.AreEqual(TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryRunning), FFrame.StatusLabel.Caption);
  // Während eine Abfrage läuft, startet keine zweite.
  FRan := '';
  FFrame.Run;
  Assert.AreEqual('', FRan);
  FFrame.Toolbar.CancelButton.Click;
  Assert.IsTrue(FCancelled);
  FFrame.SetMessage(TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryCancelled), True);
  Assert.IsTrue(FFrame.Toolbar.RunButton.Enabled);
  Assert.IsFalse(FFrame.Toolbar.CancelButton.Enabled);
  // Die bisherigen Treffer bleiben stehen.
  Assert.AreEqual(3, Integer(Length(FFrame.ResultList.RowText)));
end;

procedure TAtlasCodeQueryFrameTests.ErrorShowsColumnAndSuggestion;
var
  mAnswer: TAtlasQueryAnswer;
begin
  FFrame.InputBar.Edit.Text := 'classes where methds > 3';
  TAtlasQueryAnswer.Parse('{"enabled": true, "data": {"query": "classes where methds > 3", ' +
    '"error": {"message": "Unbekanntes Feld „methds“", "column": 15, "suggestion": "methods"}}}', mAnswer);
  FFrame.SetAnswer(mAnswer);
  Assert.IsTrue(FFrame.InputBar.ErrorLabel.Visible);
  Assert.AreEqual(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.QueryError, [15, 'Unbekanntes Feld „methds“']) + ' ' +
    TAtlasSearchStrings.Fmt(TAtlasSearchTextId.QuerySuggestion, ['methods']), FFrame.InputBar.ErrorLabel.Caption);
  // Schreibmarke an der Fehlerstelle (Spalte 15 = nach 14 Zeichen).
  Assert.AreEqual(14, FFrame.InputBar.Edit.SelStart);
  Assert.AreEqual(0, Integer(Length(FFrame.ResultList.RowText)));
  Assert.AreEqual('', FFrame.StatusLabel.Caption);
end;

procedure TAtlasCodeQueryFrameTests.CompletesFromCatalogAndSymbols;
var
  mPredicate: string;
begin
  FFrame.InputBar.Edit.Text := 'cl';
  FFrame.InputBar.Edit.SelStart := 2;
  FFrame.InputBar.ShowSuggestions;
  Assert.AreEqual('classes', Joined(FFrame.InputBar.Suggestions));
  Assert.IsTrue(FFrame.InputBar.SuggestList.Visible);
  FFrame.InputBar.AcceptSuggestion(0);
  Assert.AreEqual('classes ', FFrame.InputBar.Edit.Text);
  Assert.AreEqual(8, FFrame.InputBar.Edit.SelStart);
  Assert.IsFalse(FFrame.InputBar.SuggestList.Visible);
  FFrame.Events.OnSymbols :=
    function(const APredicate, APrefix: string): TArray<string>
    begin
      mPredicate := APredicate;
      Result := TArray<string>.Create(APrefix + 'ormBasis', APrefix + 'ormBasis', 'TFrameX');
    end;
  FFrame.InputBar.Edit.Text := 'classes where inherits TF and methods > 3';
  FFrame.InputBar.Edit.SelStart := 25;
  FFrame.InputBar.ShowSuggestions;
  Assert.AreEqual('inherits', mPredicate);
  // Doppelte Namen nur einmal.
  Assert.AreEqual('TFormBasis'#10'TFrameX', Joined(FFrame.InputBar.Suggestions));
  FFrame.InputBar.AcceptSuggestion(0);
  Assert.AreEqual('classes where inherits TFormBasis  and methods > 3', FFrame.InputBar.Edit.Text);
  // Ein Zeichen reicht nicht für die Symbolsuche.
  mPredicate := '';
  FFrame.InputBar.Edit.Text := 'classes where inherits T';
  FFrame.InputBar.Edit.SelStart := 24;
  FFrame.InputBar.ShowSuggestions;
  Assert.AreEqual('', mPredicate);
  Assert.IsFalse(FFrame.InputBar.SuggestList.Visible);
end;

procedure TAtlasCodeQueryFrameTests.SavedQueryRuns;
begin
  // Hinweis vorn, dann die gespeicherten Abfragen.
  Assert.AreEqual(2, FFrame.Toolbar.SavedCombo.Items.Count);
  Assert.IsTrue(FFrame.Toolbar.SavedCombo.Enabled);
  FFrame.Toolbar.SavedCombo.ItemIndex := 1;
  FFrame.Toolbar.SavedCombo.OnChange(FFrame.Toolbar.SavedCombo);
  Assert.AreEqual('classes where methods > 40', FFrame.InputBar.Edit.Text);
  Assert.AreEqual('classes where methods > 40', FRan);
end;

procedure TAtlasCodeQueryFrameTests.CsvAndMessage;
begin
  Assert.IsTrue(FFrame.ResultList.CsvText.StartsWith('name;unit;line;methods;path;inferred'), FFrame.ResultList.CsvText);
  FFrame.SetMessage(TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryNoServer), False);
  Assert.IsFalse(FFrame.ResultList.HasAnswer);
  Assert.AreEqual(0, Integer(Length(FFrame.ResultList.RowText)));
  Assert.AreEqual(0, FFrame.ResultList.Items.Count);
  Assert.IsFalse(FFrame.Toolbar.CopyCsvButton.Enabled);
  Assert.AreEqual(TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryNoServer), FFrame.StatusLabel.Caption);
  Assert.AreEqual('', FFrame.ResultList.CsvText);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCodeQueryFrameTests);

end.
